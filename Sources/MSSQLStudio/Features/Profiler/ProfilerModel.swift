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
  @Published var configuration=SQLProfiler.Configuration()
  @Published private(set) var events:[SQLProfiler.Event]=[]
  @Published var displayFilter=SQLProfilerFiltering.Filter() {didSet {scheduleProjection(debounce:true)}}
  @Published private(set) var gridRevision=UUID()
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
  private let interval:Duration
  init(server:ConnectedServer,executor:Executor?=nil,disconnect:(@Sendable () async -> Void)?=nil,interval:Duration = .seconds(2)) {
    serverName=server.profile.name;serverID=server.id;self.interval=interval
    let connection=ProfilerConnection(profile:server.profile,password:server.password)
    self.executor=executor ?? {sql in try await connection.execute(sql)}
    self.disconnect=disconnect ?? {await connection.disconnect()}
  }
  var hasSession:Bool {sessionName != nil}
  func preview(name:String) throws -> String {try SQLProfiler.createSQL(name:name,configuration:configuration)}
  /// Only the confirmation sheet calls this; opening/hiding never creates a session.
  func start(name:String,confirmedSQL:String) async {
    guard !busy,!hasSession else {return}
    do {guard try preview(name:name)==confirmedSQL else {throw SQLFailure("Profiler ayarları değişti; yeni SQL’i onaylayın.")}}
    catch {self.error=error.localizedDescription;return}
    busy=true;error="";warning="";buffer = .init();events=[];scheduleProjection(debounce:false);lastRead=nil
    sessionName=name
    do {
      let result=try await executor(confirmedSQL)
      guard !result.partial,!result.stoppedEarly else {throw SQLFailure("İzleme kurulumu eksik; oturum durumunu temizleyin.")}
      running=true;busy=false
      task=Task { [weak self] in
        guard let self else {return}
        while !Task.isCancelled,running {
          await poll()
          guard running,!Task.isCancelled else {break}
          do {try await Task.sleep(for:interval)} catch {break}
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
      buffer.append(snapshot);events=buffer.events;scheduleProjection(debounce:false);lastRead=Date()
      warning=[(buffer.possibleLoss ? "Sunucu arabelleği olay kaybetmiş/kesilmiş olabilir; bu kayıt eksiksiz denetim izi değildir. ":"")
        ,(buffer.discarded>0 ? "Yerel sınır nedeniyle \(buffer.discarded) eski olay kaldırıldı. ":"")
        ,(buffer.serverDropped>0 ? "Sunucuda düşen olay: \(buffer.serverDropped).":"")].joined()
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
      sessionName=nil;error="";await disconnect();return true
    } catch {
      self.error="Sunucu izleme oturumu kaldırılamadı: \(name)\n"+error.localizedDescription
      return false
    }
  }
  func clearDisplay() {buffer.clearDisplay();events=[];scheduleProjection(debounce:false)}
  func focusClient(_ client:SQLProfilerFiltering.Client) {
    var filter=displayFilter
    filter.rules.removeAll {$0.column == .clientPID || $0.column == .host}
    filter.rules.append(.init(column:.clientPID,comparison:.equals,value:client.id.pid))
    filter.rules.append(.init(column:.host,comparison:.equals,value:client.id.host))
    displayFilter=filter
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
        case .success(let value):visibleEvents=value.events;clients=value.clients;unknownClientEvents=value.unknownClientEvents;filterError=""
        case .failure(let error):visibleEvents=[];clients=[];unknownClientEvents=0;filterError=error.localizedDescription
        }
        gridRevision=UUID();filtering=false
      }
      if let pending=pendingProjection {pendingProjection=nil;enqueueProjection(pending)}
    }
  }
}
