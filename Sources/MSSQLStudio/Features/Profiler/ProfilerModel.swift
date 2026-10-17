import AppKit
import SQLServerKit

private actor ProfilerConnection {
  let connection=ODBCConnection()
  let profile:ServerProfile
  let password:String
  private var connected=false
  init(profile:ServerProfile,password:String) {var copy=profile;copy.database="master";self.profile=copy;self.password=password}
  func execute(_ sql:String) async throws -> Execution {
    if !connected {try await connection.connect(profile,password:password);connected=true}
    var limits=Limits();limits.rows=2;limits.resultSets=1;limits.cellBytes=4_194_304;limits.totalBytes=5_000_000;limits.timeout=10
    do {return try await connection.execute(sql,limits:limits)}
    catch {
      if let failure=error as? SQLFailure,failure.diagnostics.contains(where:{$0.state.hasPrefix("08")}) {connected=false}
      throw error
    }
  }
  func disconnect() async {await connection.disconnect();connected=false}
}

@MainActor final class ProfilerModel:ObservableObject {
  typealias Executor=@Sendable (String) async throws -> Execution
  let serverName:String
  let serverID:UUID
  let choices:ProfilerChoicesModel
  let sessions:ProfilerSessionsModel
  let templates:ProfilerFilterTemplatesModel
  @Published var configuration=SQLProfiler.Configuration()
  @Published private(set) var events:[SQLProfiler.Event]=[]
  @Published var displayFilter=SQLProfilerFiltering.Filter() {didSet {scheduleProjection(debounce:true)}}
  @Published private(set) var gridRevision=UUID()
  private(set) var relations:[UInt64:SQLProfilerCorrelation.Relation]=[:]
  @Published private(set) var visibleEvents:[SQLProfiler.Event]=[]
  @Published private(set) var clients:[SQLProfilerFiltering.Client]=[]
  @Published private(set) var unknownClientEvents=0
  @Published private(set) var filterError=""
  @Published private(set) var filtering=false
  private var projectionRevision=UUID()
  private struct ProjectionRequest:Sendable {let revision:UUID;let events:[SQLProfiler.Event];let filter:SQLProfilerFiltering.Filter}
  private var projectionTask:Task<Void,Never>?
  private var projectionDebounce:Task<Void,Never>?
  private var pendingProjection:ProjectionRequest?
  @Published private(set) var running=false
  @Published private(set) var busy=false
  @Published private(set) var error=""
  @Published private(set) var warning=""
  @Published private(set) var sessionName:String?
  @Published private(set) var lastRead:Date?
  private var buffer=SQLProfiler.Buffer()
  private var task:Task<Void,Never>?
  private let executor:Executor
  private let disconnect:@Sendable () async -> Void
  static let defaultReadIntervalMilliseconds=500
  private let interval:Duration
  var pollingCaption:String {
    let parts=interval.components
    return String(format:"%.0f ms",Double(parts.seconds)*1000+Double(parts.attoseconds)/1e15)
  }
  init(server:ConnectedServer,executor:Executor?=nil,disconnect:(@Sendable () async -> Void)?=nil,interval:Duration = .milliseconds(ProfilerModel.defaultReadIntervalMilliseconds),explorerChoices:(()->ProfilerChoicesModel.ExplorerSnapshot)?=nil,templates:ProfilerFilterTemplatesModel?=nil) {
    serverName=server.profile.name;serverID=server.id;self.interval=interval
    self.templates=templates ?? ProfilerFilterTemplatesModel()
    sessions=ProfilerSessionsModel(server:server)
    choices=ProfilerChoicesModel(server:server,explorer:explorerChoices)
    let connection=ProfilerConnection(profile:server.profile,password:server.password)
    self.executor=executor ?? {sql in try await connection.execute(sql)}
    self.disconnect=disconnect ?? {await connection.disconnect()}
  }
  func applyTemplate(_ value:ProfilerFilterTemplate) throws {
    guard !hasSession,!busy else {throw SQLFailure("Şablon uygulamak için önce izlemeyi durdurun ve varsa sunucu oturumunu temizleyin.")}
    try value.validate()
    configuration=value.configuration;displayFilter=value.displayFilter
  }
  var hasSession:Bool {sessionName != nil}
  func preview(name:String) throws -> String {try SQLProfiler.createSQL(name:name,configuration:configuration)}
  /// Only the explicit Start action calls this; opening/hiding never creates a session.
  func start(name:String,confirmedSQL:String) async {
    guard !busy,!hasSession else {return}
    do {guard try preview(name:name)==confirmedSQL else {throw SQLFailure("Profiler ayarları değişti; güncel ayarlarla yeniden başlatın.")}}
    catch {self.error=error.localizedDescription;return}
    busy=true;error=""
    sessionName=name
    do {
      let result=try await executor(confirmedSQL)
      guard !result.partial,!result.stoppedEarly else {throw SQLFailure("İzleme kurulumu eksik; oturum durumunu temizleyin.")}
      buffer.beginSession(name:name)
      running=true;busy=false
      task=Task { [weak self] in
        guard let self else {return}
        let clock=ContinuousClock()
        while !Task.isCancelled,running {
          let deadline=clock.now.advanced(by:interval)
          await poll()
          guard running,!Task.isCancelled else {break}
          do {try await clock.sleep(until:deadline)} catch {break}
        }
      }
    } catch {
      busy=false;running=false
      if let failure=error as? SQLFailure,failure.diagnostics.contains(where:{$0.code==51071}) {
        sessionName=nil;await disconnect();self.error=error.localizedDescription;return
      }
      self.error=error.localizedDescription+"\nKurulum sonucu belirsiz olabilir. Bu oturumu Temizle ile kaldırın: "+name
    }
  }
  private func poll() async {
    guard let name=sessionName else {return}
    do {
      let execution=try await executor(SQLProfiler.readSQL(name:name))
      let snapshot=try await Task.detached(priority:.utility) {try SQLProfiler.decode(execution)}.value
      guard !Task.isCancelled,running,sessionName==name else {return}
      let previous=buffer.lastSequence
      buffer.append(snapshot)
      if buffer.lastSequence != previous {
        events=buffer.events;choices.updateCaptured(events);scheduleProjection(debounce:false)
      }
      lastRead=Date()
      let nextWarning=[(buffer.possibleLoss ? "Sunucu arabelleği olay kaybetmiş/kesilmiş olabilir; bu kayıt eksiksiz denetim izi değildir. ":"")
        ,(buffer.discarded>0 ? "Yerel sınır nedeniyle \(buffer.discarded) eski olay kaldırıldı. ":"")
        ,(buffer.serverDropped>0 ? "Sunucuda düşen olay: \(buffer.serverDropped).":"")].joined()
      if warning != nextWarning {warning=nextWarning}
    } catch {
      guard !Task.isCancelled else {return}
      self.error=error.localizedDescription;running=false
      // An explicit stop/cleanup must still remove the owned server session.
    }
  }
  @discardableResult func stop() async -> Bool {
    guard !busy else {return false}
    busy=true;running=false
    task?.cancel();await task?.value;task=nil
    defer {busy=false}
    guard let name=sessionName else {await disconnect();return true}
    do {
      let result=try await executor(SQLProfiler.dropSQL(name:name))
      guard !result.partial,!result.stoppedEarly else {throw SQLFailure("Profiler temizliği tamamlanamadı.")}
      sessionName=nil;sessions.forget(name);error="";await disconnect();return true
    } catch {
      self.error="Sunucu izleme oturumu kaldırılamadı: \(name)\n"+error.localizedDescription
      return false
    }
  }
  func clearDisplay() {buffer.clearDisplay();events=[];choices.updateCaptured([]);scheduleProjection(debounce:false)}
  func focusClient(_ client:SQLProfilerFiltering.Client) {
    var filter=displayFilter
    filter.columnRules.removeValue(forKey:.clientPID);filter.columnRules.removeValue(forKey:.host)
    filter.rules.removeAll {$0.column == .clientPID || $0.column == .host}
    filter.rules.append(.init(column:.clientPID,comparison:.equals,value:client.id.pid))
    filter.rules.append(.init(column:.host,comparison:.equals,value:client.id.host))
    displayFilter=filter
  }
  func setColumnFilter(_ rule:ColumnRule,column:SQLProfilerFiltering.Column)throws {
    var filter=displayFilter
    filter.rules.removeAll {$0.column==column}
    filter.columnRules[column]=rule.active ? rule:nil
    guard filter.columnRules.count+filter.rules.count<=20 else {throw SQLFailure("En fazla 20 kolon filtresi kullanılabilir.")}
    displayFilter=filter
  }
  func previewEvents(_ selected:[SQLProfiler.Event])->[SQLProfiler.Event] {
    selected.map {event in event.sql.isEmpty ? relations[event.id]?.source ?? event:event}
  }
  private func scheduleProjection(debounce:Bool) {
    projectionRevision=UUID();projectionDebounce?.cancel();pendingProjection=nil;filtering=true
    let request=ProjectionRequest(revision:projectionRevision,events:events,filter:displayFilter)
    if debounce {
      projectionDebounce=Task { [weak self] in
        do {try await Task.sleep(for:.milliseconds(120))} catch {return}
        guard let self,request.revision==projectionRevision else {return}
        enqueueProjection(request)
      }
    } else {enqueueProjection(request)}
  }
  private func enqueueProjection(_ request:ProjectionRequest) {
    guard projectionTask==nil else {pendingProjection=request;return}
    let worker=Task.detached(priority:.utility) {try SQLProfilerFiltering.project(request.events,filter:request.filter)}
    projectionTask=Task { [weak self] in
      let result=await worker.result
      guard let self else {return}
      projectionTask=nil
      if request.revision==projectionRevision {
        switch result {
        case .success(let value):relations=value.relations;visibleEvents=value.events;clients=value.clients;unknownClientEvents=value.unknownClientEvents;filterError=""
        case .failure(let error):relations=[:];visibleEvents=[];clients=[];unknownClientEvents=0;filterError=error.localizedDescription
        }
        gridRevision=UUID();filtering=false
      }
      if let pending=pendingProjection {pendingProjection=nil;enqueueProjection(pending)}
    }
  }
}
