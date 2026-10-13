import AppKit
import SQLServerKit
import SwiftUI

struct AgentRelatedPage:View {
  let server:ConnectedServer
  let name:String
  let targets:Bool
  @State private var rows:[[String?]]=[]
  @State private var error=""
  @State private var loading=true
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      Text(targets ? "Hedef sunucular":"İşi tetikleyen uyarılar").font(.title2)
      if loading {ProgressView()}
      if !error.isEmpty {Text(error).foregroundStyle(.red).textSelection(.enabled)}
      List(Array(rows.enumerated()),id:\.offset) {item in Text(item.element.compactMap {$0}.joined(separator:" · ")).textSelection(.enabled)}
      Text(targets ? "Bu sayfa hedef sunucuları salt okunur gösterir; çoklu sunucu dağıtımı yönetilmez.":"Bu sayfa mevcut uyarıları salt okunur gösterir. E-posta koşulları Bildirimler sayfasından düzenlenir.").font(.caption).foregroundStyle(.secondary)
      if rows.isEmpty && !loading && error.isEmpty {Text("Kayıt bulunamadı.").foregroundStyle(.secondary)}
    }.task(id:"\(targets)|\(name)") {
      loading=true;error="";defer {loading=false}
      let sql=targets ? "SELECT COALESCE(s.name,CONVERT(nvarchar(20),t.server_id)),t.last_run_outcome,t.last_run_date,t.last_run_time FROM msdb.dbo.sysjobservers t JOIN msdb.dbo.sysjobs j ON j.job_id=t.job_id LEFT JOIN master.sys.servers s ON s.server_id=t.server_id WHERE j.name=\(SQL.literal(name));":"SELECT a.name,a.enabled,a.message_id,a.severity FROM msdb.dbo.sysalerts a JOIN msdb.dbo.sysjobs j ON j.job_id=a.job_id WHERE j.name=\(SQL.literal(name));"
      do {let result=try await server.catalog(sql,database:"msdb");try Task.checkCancellation();guard !result.partial else {throw SQLFailure("Sonuç kısmi; yenileyin.")};rows=result.results.first.map {Array($0.values)} ?? []} catch is CancellationError {} catch {rows=[];self.error=error.localizedDescription}
    }
  }
}
