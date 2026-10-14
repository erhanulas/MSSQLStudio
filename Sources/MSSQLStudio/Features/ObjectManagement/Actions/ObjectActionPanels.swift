import AppKit
import SQLServerKit
import SwiftUI

struct DeleteObjectPanel:View {
  let qualified:String
  let warning:String
  let load:() async throws -> Execution
  let open:()->Void
  @State private var rows:[[String?]]=[]
  @State private var confirm=""
  @State private var error=""
  @State private var loaded=false
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:"Delete Object",icon:"trash",subtitle:qualified)
      StudioFeedback(message:warning,tone:.warning)
      Text("Bağımlılıklar (SQL Server tarafından kaydedilen)").font(.headline)
      ScrollView {
        LazyVStack(alignment:.leading,spacing:10) {
          if loaded && rows.isEmpty { Text("Kaydedilmiş bağımlılık bulunamadı.").foregroundStyle(.secondary) }
          ForEach(rows.indices,id:\.self) { i in
            Text(rows[i].map { $0 ?? "NULL" }.joined(separator:" → ")).textSelection(.enabled)
            Divider()
          }
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
      }.frame(maxHeight:.infinity).background(.background.opacity(0.5))
      Text("Dinamik SQL bağımlılıkları metadata içinde görünmeyebilir.").font(.caption).foregroundStyle(.secondary)
      StudioFormField("Nesne adıyla onayla") {TextField(qualified,text:$confirm)}
      StudioFeedback(message:error)
      HStack { Spacer(); StudioActionButton("DROP Scriptini SQL Editöründe Aç", icon:"trash", tint:.red) { open() }.disabled(!loaded || confirm != qualified) }
    }.padding(StudioMetrics.gap).studioPanel().task {
      do { let result=try await load(); guard !result.partial else {throw SQLFailure("Bağımlılık listesi kısmi geldi.")}; rows=result.results.first?.values.map {$0} ?? []; loaded=true }
      catch { self.error=error.localizedDescription }
    }
  }
}
struct RenameObjectPanel:View {
  let qualified:String
  @State var name:String
  let open:(String)->Void
  @State private var error=""
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      StudioPanelHeading(title:"Rename Object",icon:"character.cursor.ibeam",subtitle:qualified)
      StudioFormField("Yeni ad") {TextField("Yeni ad (şema hariç)",text:$name)}
      Text("sp_rename metin başvurularını ve sys.sql_modules içindeki eski adı güncellemez. Procedure/fonksiyon/trigger için bağımlılıkları inceleyin; CREATE/DROP ile taşıma SQL editöründe yapılabilir.").foregroundStyle(.secondary)
      StudioFeedback(message:error)
      Spacer(); HStack { Spacer(); StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) { do { open(try ObjectScripts.rename(qualified:qualified,name:name)) } catch { self.error=error.localizedDescription } } }
    }.padding(StudioMetrics.gap).studioPanel()
  }
}
struct ObjectPropertiesPanel:View {
  let qualified:String
  var permissions=true
  let load:() async throws -> Execution
  let open:(String)->Void
  @State private var result=Execution()
  @State private var principal=""
  @State private var permission="SELECT"
  @State private var operation="GRANT"
  @State var page=0
  @State private var error=""
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Object Properties",icon:"info.circle",subtitle:qualified)
      if permissions {
        Picker("Özellik sayfası",selection:$page) {
          Text("Genel").tag(0)
          Text("İzinler").tag(1)
        }.pickerStyle(.segmented).labelsHidden().fixedSize()
      }
      Group {
        if page == 0 || !permissions {
          ScrollView { VStack(alignment:.leading,spacing:10) {
            if let rows=result.results.first, let row=rows.values.first { ForEach(rows.fields.indices,id:\.self) { i in HStack { Text(rows.fields[i].name).frame(width:150,alignment:.leading); Text(row[i] ?? "—").textSelection(.enabled) } } }
          }.padding(12).frame(maxWidth:.infinity,alignment:.leading) }
        } else { VStack(alignment:.leading,spacing:12) {
          List { if result.results.count > 1 { ForEach(Array(result.results[1].values.enumerated()),id:\.offset) { _,row in Text(row.map {$0 ?? ""}.joined(separator:" · ")) } } }
          VStack(spacing:8) {
            StudioFormField("Kullanıcı / rol") {TextField("Kullanıcı / rol",text:$principal)}
            StudioFormField("İzin") {Picker("İzin",selection:$permission) { ForEach(["SELECT","EXECUTE","INSERT","UPDATE","DELETE","ALTER","REFERENCES","VIEW DEFINITION"],id:\.self) { Text($0) } }.labelsHidden()}
            StudioFormField("İşlem") {Picker("İşlem",selection:$operation) { ForEach(["GRANT","DENY","REVOKE"],id:\.self) { Text($0) } }.labelsHidden()}
          }
          StudioActionButton("İzin Scriptini SQL Editöründe Aç", icon:"lock.shield", tint:.accentColor) { guard !principal.isEmpty else {error="Kullanıcı / rol gerekli.";return}; open("\(operation) \(permission) ON OBJECT::\(qualified) \(operation == "REVOKE" ? "FROM" : "TO") \(SQL.identifier(principal));") }
        }.padding(12) }
      }.frame(maxWidth:.infinity,maxHeight:.infinity).studioCard(padding:0)
      StudioFeedback(message:error)
    }.padding(StudioMetrics.gap).studioPanel().task { do { result=try await load(); if result.partial { error="Özellik listesi kısmi geldi." } } catch {self.error=error.localizedDescription} }
  }
}

/// Synthetic UI-only metadata. Assigned exclusively by the isolated UI-test launch branch.
