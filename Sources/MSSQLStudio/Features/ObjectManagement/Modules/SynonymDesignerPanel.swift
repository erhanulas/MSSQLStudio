import AppKit
import SQLServerKit
import SwiftUI

struct SynonymDesignerPanel:View {
  @State var schema:String
  @State var name:String
  let existing:Bool
  let load:(() async throws -> String)?
  let open:(String)->Void
  @State private var target=""
  @State private var error=""
  @State private var ready=false
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:existing ? "Modify Synonym" : "New Synonym",icon:"link",subtitle:"Synonym hedefi")
      VStack(spacing:12) {StudioFormField("Şema") {TextField("Şema",text:$schema)};StudioFormField("Ad") {TextField("Ad",text:$name)}}.disabled(existing)
      StudioFormField("Hedef nesne") {TextField("Hedef: [server].[database].[schema].[object]",text:$target)}
      Text(existing ? "SQL Server ALTER SYNONYM desteklemez. DROP + CREATE transaction scripti hazırlanır; nesne izinlerini ayrıca kontrol edin." : "1–4 parçalı hedef nesne adı girin.").foregroundStyle(.secondary)
      Text(error).foregroundStyle(.red);Spacer()
      HStack {Spacer();StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) {do {guard !schema.isEmpty,!name.isEmpty else {throw SQLFailure("Şema ve ad gerekli.")};let q=SQL.identifier(schema)+"."+SQL.identifier(name);let create=try ExplorerScripts.synonym(qualified:q,target:target);open(existing ? ObjectScripts.transaction("DROP SYNONYM \(q);\n"+create) : create)} catch {self.error=error.localizedDescription}}.disabled(!ready)}
    }.padding(18).studioPanel().task {do {if let load {target=try await load()};ready=true} catch {self.error=error.localizedDescription}}
  }
}
