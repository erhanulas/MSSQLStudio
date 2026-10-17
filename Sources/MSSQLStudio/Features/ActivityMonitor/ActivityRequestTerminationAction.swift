import AppKit
import SwiftUI
import SQLServerKit

@MainActor final class ActivityRequestTerminationModel:ObservableObject {
  typealias Writer = @MainActor (String) async throws -> Execution
  @Published private(set) var busy=false
  @Published private(set) var message=""
  @Published private(set) var failed=false
  private(set) var needsRefresh=false
  @Published private(set) var phase=""
  @Published private(set) var operationContext=""
  private let server:ConnectedServer
  private let writer:Writer?
  init(server:ConnectedServer,writer:Writer?=nil) {self.server=server;self.writer=writer}
  func prepare(_ target:ActivityRequestTermination.Target,generation:UUID) async -> Bool {
    guard !busy,server.online,server.generation==generation else {return false}
    busy=true;failed=false;message="";needsRefresh=false
    phase="Seçili oturum ve istek sunucudan doğrulanıyor…"
    operationContext="\(server.profile.name) · Oturum \(target.sessionID)"
    defer {busy=false}
    do {
      var limits=Limits();limits.rows=2;limits.resultSets=2;limits.totalBytes=64_000;limits.timeout=10
      let result=try await server.catalog(ActivityRequestTermination.validationSQL(for:target),database:"master",limits:limits)
      try Task.checkCancellation()
      guard server.online,server.generation==generation else {return false}
      guard !result.partial,!result.stoppedEarly,result.results.count==1,
        !result.results[0].truncated,result.results[0].values.count==1,result.results[0].values[0]==["1"] else {
        throw SQLFailure("Seçili hedef doğrulanamadı; DBA listesini yenileyin.")
      }
      return true
    } catch {
      guard server.generation==generation,!Task.isCancelled else {return false}
      needsRefresh=(error as? SQLFailure)?.diagnostics.contains {$0.code==51081} == true
      failed = !needsRefresh
      message=needsRefresh ? "Seçili sorgu tamamlanmış veya durumu değişmiş; liste yeniden okunuyor.":error.localizedDescription
      return false
    }
  }
  func completeStaleRefresh(_ updated:Bool) {
    guard needsRefresh,!busy else {return}
    message=updated ? "Seçili hedef tamamlanmış veya değişmiş. Liste güncellendi; güncel satırı seçebilirsiniz.":"Seçili hedef artık güncel değil. DBA listesini Yenile ile tekrar okuyun."
  }
  func terminate(_ request:ActivityMonitoring.Request,generation:UUID) async -> Bool {
    await terminate(.request(request),generation:generation)
  }
  func terminate(_ target:ActivityRequestTermination.Target,generation:UUID) async -> Bool {
    guard !busy else {return false}
    guard server.online,server.generation==generation else {
      message="Bağlantı değişmiş veya çevrimdışı; DBA listesini yenileyin.";failed=true;return false
    }
    busy=true;message="";failed=false;needsRefresh=false
    phase="Sonlandırma sunucuya gönderiliyor; yanıt bekleniyor…"
    operationContext="\(server.profile.name) · Oturum \(target.sessionID)"
    defer {busy=false}
    var connection:ODBCConnection?
    do {
      let sql=try ActivityRequestTermination.sql(for:target)
      let result:Execution
      if let writer {result=try await writer(sql)}
      else {
        guard server.catalogFixture==nil,server.asyncCatalogFixture==nil else {throw SQLFailure("İzole önizlemede oturum sonlandırılamaz.")}
        let dedicated=ODBCConnection();connection=dedicated
        var profile=server.profile;profile.database="master"
        try await dedicated.connect(profile,password:server.password)
        try Task.checkCancellation()
        guard server.online,server.generation==generation else {throw SQLFailure("Bağlantı değişti; sonlandırma gönderilmedi.")}
        var limits=Limits();limits.rows=1;limits.resultSets=1;limits.totalBytes=64_000;limits.timeout=10
        result=try await dedicated.execute(sql,limits:limits)
      }
      if let connection {await connection.disconnect()}
      connection=nil
      guard !result.partial,!result.stoppedEarly,!result.results.contains(where:{$0.truncated}) else {
        throw SQLFailure("Sonlandırma sonucu doğrulanamadı. Otomatik tekrar gönderilmedi; DBA listesini yenileyin.")
      }
      guard server.generation==generation else {return false}
      message="Oturum \(target.sessionID) için sonlandırma gönderildi. Açık transaction’ların geri alınması sürebilir."
      return true
    } catch {
      if let connection {await connection.disconnect()}
      guard server.generation==generation else {return false}
      needsRefresh=(error as? SQLFailure)?.diagnostics.contains {$0.code==51081} == true
      failed = !needsRefresh
      message=needsRefresh ? "Seçili hedef tamamlanmış veya değişmiş; liste yeniden okunuyor.":"Sonlandırma tamamlandığı doğrulanamadı; otomatik tekrar gönderilmedi. "+error.localizedDescription
      return false
    }
  }
}

struct ActivityRequestTerminationAction:View {
  @ObservedObject var monitor:ActivityMonitorModel
  @ObservedObject var model:ActivityRequestTerminationModel
  var request:ActivityMonitoring.Request?=nil
  var applicationLock:ActivityApplicationLocks.Lock?=nil
  var applicationLockMode=false
  var staleSelection:((ActivityRequestTermination.Target)->Void)?=nil
  private struct Confirmation:Identifiable {
    let id=UUID()
    let target:ActivityRequestTermination.Target
    let generation:UUID
    let serverName:String
  }
  @State private var confirmation:Confirmation?
  @State private var preparation:Task<Void,Never>?
  @State private var presented=true
  private var isApplicationLockAction:Bool {applicationLockMode || applicationLock != nil}
  private var candidate:ActivityRequestTermination.Target? {
    if let applicationLock {return .applicationLock(applicationLock)}
    return request.map { .request($0) }
  }
  private var canTerminateTarget:Bool {
    if let applicationLock {return (try? ActivityRequestTermination.sql(for:.applicationLock(applicationLock))) != nil}
    guard let request else {return false}
    return ActivityRequestTermination.canTerminate(request)
      && !monitor.diagnostics.backups.contains {$0.sessionID==request.sessionID}
      && !monitor.diagnostics.active.contains {$0.sessionID==request.sessionID && $0.command.uppercased().hasPrefix("BACKUP")}
  }
  var actionEnabled:Bool {candidate != nil && canTerminateTarget && monitor.server.online && !model.busy}
  private var unavailableReason:String? {
    guard let applicationLock else {return nil}
    do {_=try ActivityRequestTermination.sql(for:.applicationLock(applicationLock));return nil}
    catch {return error.localizedDescription}
  }
  var body:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Spacer()
        if model.busy {ProgressView().controlSize(.small)}
        StudioActionButton(!isApplicationLockAction ? "Sorguyu Sonlandır":"Oturumu Sonlandır",icon:"stop.circle",tint:Color(nsColor:StudioTheme.danger)) {
          guard let target=candidate else {return}
          let snapshot=Confirmation(target:target,generation:monitor.server.generation,serverName:monitor.server.profile.name)
          preparation=Task {
            if await model.prepare(target,generation:snapshot.generation),presented,!Task.isCancelled {confirmation=snapshot}
            else if model.needsRefresh,presented,!Task.isCancelled {
              staleSelection?(target)
              let updated=await monitor.refreshAfterStaleTarget(target,generation:snapshot.generation)
              model.completeStaleRefresh(updated)
            }
            preparation=nil
          }
        }.disabled(!actionEnabled)
          .accessibilityIdentifier(!isApplicationLockAction ? "activityTerminateRequest":"activityTerminateApplicationLock")
          .studioHelp(unavailableReason ?? (!isApplicationLockAction ? (request?.command.uppercased().hasPrefix("BACKUP")==true ? "Yedekleme sorguları bu ekrandan sonlandırılamaz.":request?.wait.uppercased().hasPrefix("SP_SERVER_DIAGNOSTICS")==true ? "SQL Server tanılama beklemesindeki oturumlar sonlandırılamaz.":"Seçili sorgunun oturumunu sonlandırır; bloklayan başka oturumu hedeflemez. Aynı oturumdaki tüm sorgular etkilenir."):"Seçili application lock sahibinin tüm oturumunu sonlandırır. Boşta oturumlar da sonlandırılabilir; diğer sorgu ve kilitler de etkilenir."))
      }
      if model.busy {StudioLoadingView(title:"Oturum işlemi",context:model.operationContext,phase:model.phase).frame(height:124)}
      if !model.message.isEmpty {StudioFeedback(message:model.message,tone:model.failed ? .error:.info)}
    }.onAppear {presented=true}.onDisappear {presented=false;preparation?.cancel();preparation=nil;confirmation=nil}
      .sheet(item:$confirmation) {snapshot in
        ActivityTerminationConfirmation(target:snapshot.target,serverName:snapshot.serverName,cancel:{confirmation=nil},confirm:{
          confirmation=nil
          Task {
            if await model.terminate(snapshot.target,generation:snapshot.generation) {
              monitor.clearDiagnostics()
              if presented {await monitor.load(includeDiagnostics:true,includeApplicationLocks:snapshot.target.isApplicationLock)}
            } else if model.needsRefresh,presented {
              staleSelection?(snapshot.target)
              let updated=await monitor.refreshAfterStaleTarget(snapshot.target,generation:snapshot.generation)
              model.completeStaleRefresh(updated)
            }
          }
        })
      }
  }
}

extension ActivityRequestTermination.Target {
  var isApplicationLock:Bool {if case .applicationLock=self {return true};return false}
}
