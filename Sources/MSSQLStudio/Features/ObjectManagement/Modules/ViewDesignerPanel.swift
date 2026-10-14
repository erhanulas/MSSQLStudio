import AppKit
import SQLServerKit
import SwiftUI

struct ManagedSQLEditor:NSViewRepresentable {
  let document:QueryDocument
  // A value snapshot lets SwiftUI observe asynchronous loads on the reference document.
  let source:String
  func makeCoordinator() -> EditorController { EditorController(document:document) }
  func makeNSView(context:Context) -> NSView { context.coordinator.setText(); return context.coordinator.surface }
  func updateNSView(_ view:NSView,context:Context) { if context.coordinator.editor.string != document.sql { context.coordinator.setText() } }
}
struct ViewDesignerPanel:View {
  let document:QueryDocument
  let load:(() async throws -> String)?
  let open:(String)->Void
  @State private var ready=false
  @State private var error=""
  @State private var schema="dbo"
  @State private var name="NewView"
  @State private var sourceSchema="dbo"
  @State private var sourceTable=""
  @State private var filter=""
  @State private var columns:[String]=[]
  @State private var selected:Set<String>=[]
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:load == nil ? "New View" : "View Designer",icon:"rectangle.on.rectangle",subtitle:document.server.profile.name+" · "+document.database)
      if load == nil {
        VStack(alignment:.leading,spacing:10) { StudioFormField("View şeması") {TextField("View şeması",text:$schema)}; StudioFormField("View adı") {TextField("View adı",text:$name)}; StudioFormField("Kaynak şema") {TextField("Kaynak şema",text:$sourceSchema)}; StudioFormField("Kaynak tablo / view") {TextField("Kaynak tablo / view",text:$sourceTable)}; HStack {Spacer();StudioActionButton("Kolonları Getir", icon:"arrow.down.square", tint:.accentColor) { Task { await loadColumns() } }} }
        if !columns.isEmpty {
          ScrollView(.horizontal) { HStack { ForEach(columns,id:\.self) { column in Toggle(column,isOn:Binding(get:{selected.contains(column)},set:{ if $0 {selected.insert(column)} else {selected.remove(column)} })) } } }.frame(height:35)
          HStack { TextField("WHERE koşulu (isteğe bağlı SQL)",text:$filter); Button("Seçimden View SQL'i Oluştur") { build() } }
        }
      }
      Text("SQL tanımı · Karmaşık JOIN/CTE/sorguları burada düzenleyin. Değişiklik otomatik çalıştırılmaz.").font(.caption).foregroundStyle(.secondary)
      if !ready { ProgressView("Tanım yükleniyor…") }
      ManagedSQLEditor(document:document,source:document.sql).disabled(!ready)
      StudioFeedback(message:error)
      HStack {
        if load != nil { StudioActionButton("Farkları Göster", icon:"rectangle.split.2x1", tint:.accentColor) { error=ModuleEditing.difference(original:document.savedText,edited:document.sql) } }
        Spacer(); StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) { open(document.sql) }.disabled(!ready)
      }
    }.padding(StudioMetrics.gap).studioPanel().task {
      do { if let load { document.sql=try await load() }; document.savedText=document.sql; ready=true }
      catch { self.error=error.localizedDescription }
    }
  }
  private func loadColumns() async {
    do {
      guard !sourceSchema.isEmpty, !sourceTable.isEmpty else { throw SQLFailure("Kaynak şema ve tablo gerekli.") }
      let result=try await document.server.catalog("SELECT c.name FROM sys.columns c WHERE c.object_id=OBJECT_ID(\(SQL.literal(SQL.identifier(sourceSchema)+"."+SQL.identifier(sourceTable)))) ORDER BY c.column_id;",database:document.database)
      guard !result.partial else { throw SQLFailure("Kolon listesi kısmi geldi.") }
      columns=result.results.first?.values.compactMap { $0.first ?? nil } ?? []; selected=Set(columns); error=columns.isEmpty ? "Kaynak nesne/kolon bulunamadı." : ""
    } catch { self.error=error.localizedDescription }
  }
  private func build() {
    guard !schema.isEmpty, !name.isEmpty, !selected.isEmpty else { error="View adı ve kolon seçimi gerekli."; return }
    document.sql="CREATE VIEW \(SQL.identifier(schema)).\(SQL.identifier(name))\nAS\nSELECT \(columns.filter { selected.contains($0) }.map(SQL.identifier).joined(separator:",\n       "))\nFROM \(SQL.identifier(sourceSchema)).\(SQL.identifier(sourceTable))\(filter.isEmpty ? "" : "\nWHERE "+filter);"
    error=""; ready.toggle(); ready=true
  }
}
