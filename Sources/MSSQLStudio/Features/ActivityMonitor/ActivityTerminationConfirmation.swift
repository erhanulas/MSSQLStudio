import SwiftUI
import SQLServerKit

/// Immutable selection snapshot: periodic sampling must not change the confirmation target.
struct ActivityTerminationConfirmation:View {
  let target:ActivityRequestTermination.Target
  let serverName:String
  let cancel:()->Void
  let confirm:()->Void
  private var details:[(String,String,String)] {
    var values=[("Sunucu",serverName,"server.rack"),("Oturum",String(target.sessionID),"person.crop.circle")]
    switch target {
    case .request(let value):
      values += [("Veritabanı",value.database,"externaldrive"),("İstek",String(value.requestID),"number"),("Login",value.login,"person"),("Host",value.host,"desktopcomputer"),("Uygulama",value.program,"app"),("Komut",value.command,"terminal")]
    case .applicationLock(let value):
      values += [("Veritabanı",value.database,"externaldrive"),("Login",value.login,"person"),("Host",value.host,"desktopcomputer"),("Uygulama",value.program,"app"),("Kaynak",value.resource,"lock"),("Kilit",value.ownerType+" · "+value.mode+" · "+value.status,"key")]
    }
    return values
  }
  private var sql:String {
    switch target {case .request(let value):value.sql;case .applicationLock(let value):value.sql}
  }
  private var sqlTitle:String {
    if case .applicationLock(let value)=target,value.sqlSource=="recent" {return "Son SQL · geçmiş bağlam"}
    return "SQL"
  }
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:target.isApplicationLock ? "Uygulama kilidinin sahibi sonlandırılsın mı?":"Seçili sorgunun oturumu sonlandırılsın mı?",icon:"stop.circle",subtitle:"Oturum sonlandırma onayı")
      ScrollView {
        LazyVGrid(columns:[GridItem(.flexible(),alignment:.leading),GridItem(.flexible(),alignment:.leading)],alignment:.leading,spacing:8) {
          ForEach(Array(details.enumerated()),id:\.offset) {_,item in
            HStack(alignment:.top,spacing:8) {
              Image(systemName:item.2).foregroundStyle(Color(nsColor:StudioTheme.muted)).frame(width:16)
              VStack(alignment:.leading,spacing:4) {
                Text(item.0).font(.system(size:11)).foregroundStyle(Color(nsColor:StudioTheme.muted))
                Text(item.1.isEmpty ? "—":item.1).font(.system(size:12,weight:.medium)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
              }.frame(maxWidth:.infinity,alignment:.leading)
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).studioCard(padding:8)
          }
        }
      }.frame(minHeight:240,maxHeight:280)
      Text("Aynı oturumdaki tüm sorgular durur ve application lock’lar dahil kilitler bırakılır. Bu işlem yalnız seçili sorguyu veya kilidi etkilemez. Açık transaction’ların geri alınması zaman alabilir.")
        .font(.system(size:12)).foregroundStyle(Color(nsColor:StudioTheme.warning))
        .padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:StudioTheme.warning).opacity(0.07),in:RoundedRectangle(cornerRadius:StudioMetrics.cardRadius))
      Text(sqlTitle).font(.system(size:12,weight:.semibold))
      if sql.isEmpty {
        StudioEmptyState(title:"SQL metni alınamadı",icon:"text.alignleft",detail:"Sonlandırma hedefi yukarıdaki oturum bilgileridir.")
          .frame(maxWidth:.infinity,maxHeight:.infinity)
      } else {
        SQLReadOnlyPreview(sql:sql).frame(minHeight:160,maxHeight:.infinity).studioCard(padding:0)
      }
      HStack {
        Spacer()
        Button("Vazgeç",action:cancel).buttonStyle(StudioSecondaryButton()).keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("activityTerminationCancel")
        StudioActionButton("Oturumu Sonlandır",icon:"stop.circle",tint:Color(nsColor:StudioTheme.danger),action:confirm)
          .accessibilityIdentifier("activityTerminationConfirm")
      }.fixedSize(horizontal:false,vertical:true)
    }.padding(16).studioPanel().frame(minWidth:620,idealWidth:680,minHeight:600,idealHeight:660)
      .accessibilityIdentifier("activityTerminationConfirmation")
  }
}
