import AppKit
import SwiftUI
import SQLServerKit

@MainActor final class ActivityRequestTerminationModel:ObservableObject {
  typealias Writer = @MainActor (String) async throws -> Execution
  @Published private(set) var busy=false
  @Published private(set) var message=""
  @Published private(set) var failed=false
  private let server:ConnectedServer
  private let writer:Writer?
  init(server:ConnectedServer,writer:Writer?=nil) {self.server=server;self.writer=writer}
  func terminate(_ request:ActivityMonitoring.Request,generation:UUID) async -> Bool {
    await terminate(.request(request),generation:generation)
  }
  func terminate(_ target:ActivityRequestTermination.Target,generation:UUID) async -> Bool {
    guard !busy else {return false}
    guard server.online,server.generation==generation else {
      message="Bağlantı değişmiş veya çevrimdışı; DBA listesini yenileyin.";failed=true;return false
    }
    busy=true;message="";failed=false
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
      failed=true
      message="Sonlandırma tamamlandığı doğrulanamadı; otomatik tekrar gönderilmedi. "+error.localizedDescription
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
  @State private var target:ActivityRequestTermination.Target?
  @State private var generation:UUID?
  @State private var confirming=false
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
  var body:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Spacer()
        if model.busy {ProgressView().controlSize(.small)}
        StudioActionButton(!isApplicationLockAction ? "Sorguyu Sonlandır":"Oturumu Sonlandır",icon:"stop.circle",tint:Color(nsColor:StudioTheme.danger)) {
          target=candidate;generation=monitor.server.generation;confirming=true
        }.disabled(candidate==nil || !canTerminateTarget || !monitor.server.online || model.busy || monitor.loading)
          .accessibilityIdentifier(!isApplicationLockAction ? "activityTerminateRequest":"activityTerminateApplicationLock")
          .studioHelp(!isApplicationLockAction ? (request?.command.uppercased().hasPrefix("BACKUP")==true ? "Yedekleme sorguları bu ekrandan sonlandırılamaz.":"Seçili sorgunun oturumunu sonlandırır; bloklayan başka oturumu hedeflemez. Aynı oturumdaki tüm sorgular etkilenir."):"Seçili application lock sahibinin tüm oturumunu sonlandırır. Boşta oturumlar da sonlandırılabilir; diğer sorgu ve kilitler de etkilenir.")
      }
      if !model.message.isEmpty {StudioFeedback(message:model.message,tone:model.failed ? .error:.info)}
    }.onAppear {presented=true}.onDisappear {presented=false}
      .alert(!isApplicationLockAction ? "Seçili sorgunun oturumu sonlandırılsın mı?":"Uygulama kilidinin sahibi sonlandırılsın mı?",isPresented:$confirming) {
      Button("Vazgeç",role:.cancel) {target=nil;generation=nil}
      Button("Oturumu Sonlandır",role:.destructive) {
        guard let target,let generation else {return}
        Task {
          if await model.terminate(target,generation:generation) {
            monitor.clearDiagnostics()
            if presented {await monitor.load(includeDiagnostics:true,includeApplicationLocks:target.isApplicationLock)}
          }
        }
        self.target=nil;self.generation=nil
      }
    } message: {
      if let target {
        Text("\(monitor.server.profile.name) · Oturum \(target.sessionID)\n\(target.confirmationDetails)\n\nAynı oturumdaki tüm sorgular durur ve application lock’lar dahil kilitler bırakılır. Açık transaction’ların geri alınması zaman alabilir.")
      }
    }
  }
}

private extension ActivityRequestTermination.Target {
  var isApplicationLock:Bool {if case .applicationLock=self {return true};return false}
  var confirmationDetails:String {
    switch self {
    case .request(let value):
      return "İstek \(value.requestID) · \(value.database) · \(value.login) · \(value.host) · \(value.program)\n\n"+String(value.sql.prefix(400))
    case .applicationLock(let value):
      return "\(value.database) · \(value.login) · \(value.host) · \(value.program)\nKaynak: \(value.resource)\n\(value.ownerType) · \(value.mode) · \(value.status)\n\nBu işlem yalnız seçili kilidi bırakmaz; sahibi olan oturumun tamamını sonlandırır."
    }
  }
}
