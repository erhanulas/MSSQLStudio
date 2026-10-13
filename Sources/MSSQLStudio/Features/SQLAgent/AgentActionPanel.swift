import AppKit
import SQLServerKit
import SwiftUI

struct AgentActionPanel:View {
  let server:ConnectedServer
  let name:String
  let action:SQLAgent.Action
  let open:(String)->Void
  @State private var sql=""
  @State private var job:SQLAgent.Job?
  @State private var busy=false
  @State private var error=""
  @State private var done=false
  @State private var startAt=""
  @State private var steps:[SQLAgent.Step]=[]
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:action.rawValue.capitalized+" Job",icon:action == .delete ? "trash":"clock.badge.checkmark",subtitle:server.profile.name+" · "+name)
      if let job {Text("\(job.enabled ? "Enabled":"Disabled") · \(job.state) · Owner: \(job.owner)").foregroundStyle(.secondary)}
      Text(action == .start ? "İşin adımları çalıştırılır; komut kabul edilmesi işin başarıyla tamamlandığı anlamına gelmez. Sonucu History’den izleyin.":action == .stop ? "Çalışan iş durdurulur. Önceden tamamlanan adımların etkileri geri alınmaz.":action == .delete ? "İş ve iş geçmişi silinir. Paylaşılan zamanlamalar korunur.":"İşin etkinlik ayarı değiştirilir; devam eden çalışma durdurulmaz.").font(.callout)
      if action == .start {
        Picker("Başlatılacak adım",selection:$startAt) {Text("İşin tanımlı başlangıç adımı").tag("");ForEach(steps) {Text("\($0.id) · \($0.name)").tag($0.name)}}.disabled(busy || done)
      }
      AgentSQLPreview(sql:sql).studioEditor()
      if !error.isEmpty {Text(error).foregroundStyle(done ? .green:.red).textSelection(.enabled)}
      HStack {
        if busy {ProgressView().controlSize(.small)}
        Spacer()
        StudioActionButton("SQL’i Sorgu Sekmesine Aktar", icon:"arrow.up.forward.square", tint:.accentColor) {open(sql)}.disabled(sql.isEmpty || busy)
        // Explicit command action, separate from property/design SQL generation.
        StudioActionButton(action == .delete ? "İşi Sil":"Uygula",icon:action == .delete ? "trash":"checkmark") {apply()}.buttonStyle(StudioPrimaryButton()).disabled(sql.isEmpty || busy || done)
      }
    }.padding(20).studioPanel().task {
      busy=true;defer {busy=false}
      do {
        let output=try await server.catalog(action == .start ? SQLAgent.details(name:name):SQLAgent.jobs(name:name),database:"msdb")
        if action == .start {let details=try SQLAgent.decodeDetails(output);job=details.0;steps=details.1} else {job=try SQLAgent.decodeJobs(output).first}
        guard let job else {throw SQLFailure("İş bulunamadı.")};sql=try SQLAgent.command(action,id:job.id)
      } catch {self.error=error.localizedDescription}
    }.onChange(of:startAt) {_,value in
      guard let job else {return}
      do {sql=try SQLAgent.command(action,id:job.id,stepName:value.isEmpty ? nil:value)} catch {sql="";self.error=error.localizedDescription}
    }
  }
  private func apply() {
    guard !busy,!done,!sql.isEmpty else {return};busy=true;error=""
    Task { @MainActor in
      defer {busy=false}
      do {
        let result=try await server.catalog(sql,database:"msdb")
        guard !result.partial else {throw SQLFailure("Komut sonucu kısmi; durumu yenileyerek kontrol edin.")}
        done=true;error=action == .start ? "Başlatma isteği kabul edildi. Sonucu History’den izleyin.":"İşlem tamamlandı."
        NotificationCenter.default.post(name:.init("studioAgentChanged"),object:server)
      } catch {self.error=error.localizedDescription}
    }
  }
}

