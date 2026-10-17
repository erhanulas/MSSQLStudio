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
      ActivityRequestTerminationAction(monitor:model,model:model.termination,applicationLock:lock,applicationLockMode:true,staleSelection:{target in
        if case .applicationLock(let stale)=target,selected==stale.id {selected=nil}
      })
      if model.applicationLocks.isEmpty {
        StudioEmptyState(title:model.applicationLocksTime==nil ? "Uygulama kilitleri bekleniyor":!model.applicationLockError.isEmpty || !model.applicationLockIssues.isEmpty ? "Kilit bilgisi doğrulanamadı":"Etkin uygulama kilidi yok",icon:"lock.shield",detail:"Yalnız bu sekme açıkken application lock kaynakları salt okunur olarak alınır.")
      } else {
        StudioDataGrid(rows:model.applicationLocks,columns:[
          .init(title:"Oturum",width:65,numeric:true,value:{String($0.sessionID)}),
          .init(title:"Kaynak",width:220,value:{$0.resource}),.init(title:"Durum",value:{$0.status}),
          .init(title:"Mod",width:65,value:{$0.mode}),.init(title:"Sahip",value:{$0.ownerType}),
          .init(title:"Veritabanı",value:{$0.database}),.init(title:"Login",value:{$0.login}),
          .init(title:"Host",value:{$0.host}),.init(title:"Uygulama",width:160,value:{$0.program}),
          .init(title:"Sahip no",numeric:true,value:{$0.ownerID}),.init(title:"SQL kaynağı",value:{$0.sqlSource}),
          .init(title:"SQL",width:380,value:{$0.sql})
        ],selection:$selected,identifier:"activityApplicationLocks").frame(minHeight:120)

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
