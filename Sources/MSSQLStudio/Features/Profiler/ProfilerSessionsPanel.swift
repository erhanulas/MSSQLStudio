import AppKit
import SwiftUI
import SQLServerKit

struct ProfilerSessionsPanel:View {
  @ObservedObject var model:ProfilerSessionsModel
  let currentSession:String?
  @State private var selection:String?
  var body:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Text("Sunucudaki MSSQL Studio izlemeleri").font(.headline)
        Spacer()
        if model.busy {ProgressView().controlSize(.small)}
        Button {Task {await model.refresh()}} label:{Label("Yenile",systemImage:"arrow.clockwise")}.buttonStyle(StudioSecondaryButton()).disabled(model.busy)
      }
      Text("Diğer kullanıcıların etkin izlemeleri de görünebilir. Yalnız artık kullanılmadığından emin olduğunuz oturumu kaldırın.").foregroundStyle(.secondary)
      if !model.error.isEmpty {StudioFeedback(message:model.error,tone:.error)}
      Table(model.sessions,selection:$selection) {
        TableColumn("Oturum") {session in Text(session.name).textSelection(.enabled)}.width(min:250,ideal:350)
        TableColumn("Durum") {session in Text(session.name==currentSession ? "Bu pencere":session.running ? "İzleniyor":"Durduruldu")}.width(90)
        TableColumn("Başlangıç · sunucu") {Text($0.started)}.width(160)
      }.tableStyle(.inset(alternatesRowBackgrounds:true))
      HStack {
        Text("\(model.sessions.count) oturum").foregroundStyle(.secondary)
        Spacer()
        Button {removeSelected()} label:{Label("Seçili Oturumu Kaldır",systemImage:"stop.circle")}
          .buttonStyle(StudioSecondaryButton()).disabled(model.busy || selection==nil || selection==currentSession)
      }
    }.padding(12).frame(width:680,height:360).font(.system(size:12))
  }
  private func removeSelected() {
    guard let session=model.sessions.first(where:{$0.name==selection}),session.name != currentSession else {return}
    let alert=StudioAlert();alert.messageText="Sunucu izleme oturumu kaldırılsın mı?"
    alert.informativeText=session.name+"\nBu oturum başka bir kullanıcının etkin izlemesi olabilir. Yakalama durur ve sunucu arabelleğindeki olaylar silinir."
    alert.addButton(withTitle:"Oturumu Kaldır");alert.addButton(withTitle:"Vazgeç")
    if alert.runModal() == .alertFirstButtonReturn {Task {await model.remove(session,currentSession:currentSession)}}
  }
}
