import AppKit
import SwiftUI
import SQLServerKit

struct ActivityApplicationLocksPanel:View {
  @ObservedObject var model:ActivityMonitorModel
  @State private var selected:[String]?
  init(model:ActivityMonitorModel,initialSelection:[String]?=nil) {self.model=model;_selected=State(initialValue:initialSelection)}
  private var lock:ActivityApplicationLocks.Lock? {model.applicationLocks.first {$0.id==selected}}
  var body:some View {
    VStack(alignment:.leading,spacing:8) {
      Text("APPLICATION · Alınmış ve bekleyen kilitler · İlk 100 kayıt")
        .font(.system(size:StudioMetrics.detailFont)).foregroundStyle(.secondary)
        .studioHelp("SQL Server kaynak adının yalnız görünür kısmını ve hash’ini sağlar. Boşta oturumlar da session/transaction kilidi tutabilir; kilidin yaşı DMV tarafından sağlanmaz.")
      ActivityRequestTerminationAction(monitor:model,model:model.termination,applicationLock:lock,applicationLockMode:true)
      if model.applicationLocks.isEmpty {
        StudioEmptyState(title:model.applicationLocksTime==nil ? "Uygulama kilitleri bekleniyor":!model.applicationLockError.isEmpty || !model.applicationLockIssues.isEmpty ? "Kilit bilgisi doğrulanamadı":"Etkin uygulama kilidi yok",icon:"lock.shield",detail:"Yalnız bu sekme açıkken application lock kaynakları salt okunur olarak alınır.")
      } else {
        Table(model.applicationLocks,selection:$selected) {
          TableColumn("Oturum") {Text(String($0.sessionID)).monospacedDigit()}.width(55)
          TableColumn("Kaynak",value:\.resource).width(min:130,ideal:220)
          TableColumn("Durum") {Text($0.status).foregroundStyle(Color(nsColor:$0.status=="GRANTED" ? StudioTheme.success:StudioTheme.warning))}.width(min:75,ideal:90)
          TableColumn("Mod",value:\.mode).width(55)
          TableColumn("Sahip",value:\.ownerType).width(min:85,ideal:100)
          TableColumn("Veritabanı",value:\.database).width(min:85,ideal:110)
          TableColumn("Login",value:\.login).width(min:90,ideal:120)
          TableColumn("Host",value:\.host).width(min:90,ideal:120)
          TableColumn("Uygulama",value:\.program).width(min:110,ideal:160)
        }.frame(minHeight:120).accessibilityIdentifier("activityApplicationLocks")
        if let lock {
          VStack(alignment:.leading,spacing:8) {
            HStack {
              Label("Oturum \(lock.sessionID) · \(lock.ownerType) · \(lock.ownerID)",systemImage:"lock.shield").fontWeight(.medium)
              Spacer()
              StudioActionButton("SQL’i Kopyala",icon:"doc.on.doc") {NSPasteboard.general.clearContents();NSPasteboard.general.setString(lock.sql,forType:.string)}.disabled(lock.sql.isEmpty)
            }
            Text(lock.resource).textSelection(.enabled)
            Text(lock.sqlSource=="current" ? "Etkin isteğin batch’i · Kilidi alan ifade olduğu kesin değil":lock.sqlSource=="recent" ? "Son batch · Geçmiş bağlam; kilidi alan ifade olduğu kesin değil":"SQL bağlamı sağlanmadı.")
              .font(.system(size:StudioMetrics.detailFont)).foregroundStyle(Color(nsColor:StudioTheme.warning))
            SQLReadOnlyPreview(sql:lock.sql.isEmpty ? "-- SQL metni sağlanmadı.":lock.sql).frame(minHeight:100,idealHeight:140,maxHeight:190)
          }.studioCard(padding:12)
        }
      }
    }.onChange(of:model.applicationLocks) {_,rows in if let selected,!rows.contains(where:{$0.id==selected}) {self.selected=nil}}
  }
}
