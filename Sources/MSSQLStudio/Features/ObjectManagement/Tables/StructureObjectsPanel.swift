import AppKit
import SQLServerKit
import SwiftUI

struct StructureObjectsPanel:View {
  let table:TableDefinition
  let initialKind:String
  let open:(String)->Void
  @State private var kind="INDEX"
  @State private var name="IX_NewIndex"
  @State private var selected:Set<String>=[]
  @State private var includes:Set<String>=[]
  @State private var unique=false
  @State private var expression=""
  @State private var targetSchema="dbo"
  @State private var targetTable=""
  @State private var targetColumns=""
  @State private var deleteAction="NO ACTION"
  @State private var updateAction="NO ACTION"
  @State private var error=""
  var body:some View {
    HSplitView {
      VStack(alignment:.leading,spacing:8) {
        Text("Mevcut nesneler").font(.headline)
        List(table.definitions) { object in
          VStack(alignment:.leading) {
            Text(object.name+" · "+object.kind)
            HStack {
              Button("Script") { open(object.sql) }
              Button("DROP + CREATE") { open(drop(object)+"\nGO\n"+object.sql) }
              Button("Drop Script") { open(drop(object)) }
            }.buttonStyle(.borderless).font(.caption)
          }.padding(.vertical,4)
        }
      }.frame(minWidth:330)
      VStack(alignment:.leading,spacing:8) {
       ScrollView {
        VStack(alignment:.leading,spacing:12) {
          Text("Yeni nesne").font(.headline)
          StudioFormField("Tür") {Picker("Tür",selection:$kind) { Text("Index").tag("INDEX"); Text("Unique Key").tag("UQ"); Text("Foreign Key / Relationship").tag("FK"); Text("Check Constraint").tag("CHECK") }.labelsHidden()}
          StudioFormField("Ad") {TextField("Ad",text:$name)}
          if kind != "CHECK" {
            Text("Anahtar kolonları (tablo sırası)").font(.caption)
            ForEach(table.columns) { c in HStack {
              Toggle(c.name,isOn:membership(c.name,in:$selected))
              if kind == "INDEX" { Toggle("Include",isOn:membership(c.name,in:$includes)) }
            } }
          }
          if kind == "INDEX" { Toggle("UNIQUE",isOn:$unique); StudioFormField("Filtre") {TextField("Filtre: isteğe bağlı WHERE",text:$expression)} }
          if kind == "CHECK" { StudioFormField("CHECK koşulu") {TextField("Koşul: [Amount] >= 0",text:$expression)} }
          if kind == "FK" {
            StudioFormField("Hedef şema") {TextField("Hedef şema",text:$targetSchema)}; StudioFormField("Hedef tablo") {TextField("Hedef tablo",text:$targetTable)}; StudioFormField("Hedef kolonlar") {TextField("Hedef kolonlar: Id, Code",text:$targetColumns)}
            StudioFormField("ON DELETE") {Picker("ON DELETE",selection:$deleteAction) { ForEach(["NO ACTION","CASCADE","SET NULL","SET DEFAULT"],id:\.self) { Text($0) } }.labelsHidden()}
            StudioFormField("ON UPDATE") {Picker("ON UPDATE",selection:$updateAction) { ForEach(["NO ACTION","CASCADE","SET NULL","SET DEFAULT"],id:\.self) { Text($0) } }.labelsHidden()}
          }
        }.padding(12)
       }
       Divider()
       Text(error).foregroundStyle(.red)
       StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) {generate()}.padding(.horizontal,12)
       Text("SQL hazırlanır; bu pencereden veritabanına yazılmaz.").font(.caption).foregroundStyle(.secondary).padding(.horizontal,12)
      }.frame(minWidth:350)
    }.padding(8).onAppear { if !initialKind.isEmpty { kind=initialKind }; name=kind == "FK" ? "FK_NewRelationship" : kind == "CHECK" ? "CK_NewConstraint" : "IX_NewIndex" }
  }
  private func membership(_ name:String,in set:Binding<Set<String>>) -> Binding<Bool> { Binding(get:{set.wrappedValue.contains(name)},set:{ if $0 { set.wrappedValue.insert(name) } else { set.wrappedValue.remove(name) } }) }
  private func drop(_ object:ManagedDefinition) -> String {
    if object.kind == "INDEX" { return "DROP INDEX \(SQL.identifier(object.name)) ON \(table.qualified);" }
    if object.kind == "TRIGGER" { return "DROP TRIGGER \(SQL.identifier(table.schema)).\(SQL.identifier(object.name));" }
    return "ALTER TABLE \(table.qualified) DROP CONSTRAINT \(SQL.identifier(object.name));"
  }
  private func generate() {
    do {
      let keys=table.columns.filter { selected.contains($0.name) }.map(\.name)
      guard !name.isEmpty else { throw SQLFailure("Nesne adı gerekli.") }
      let sql:String
      switch kind {
      case "INDEX": sql=try Scripts.index(table:table.qualified,name:name,keys:keys,included:table.columns.filter { includes.contains($0.name) }.map(\.name),unique:unique,filter:expression)
      case "UQ": guard !keys.isEmpty else { throw SQLFailure("Anahtar kolonu seçin.") }; sql="ALTER TABLE \(table.qualified) ADD CONSTRAINT \(SQL.identifier(name)) UNIQUE (\(keys.map(SQL.identifier).joined(separator:", ")));"
      case "FK": sql=try ObjectScripts.foreignKey(table:table.qualified,name:name,columns:keys,referencedSchema:targetSchema,referencedTable:targetTable,referencedColumns:targetColumns.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) },onDelete:deleteAction,onUpdate:updateAction)
      default: guard !expression.isEmpty else { throw SQLFailure("CHECK koşulu gerekli.") }; sql="ALTER TABLE \(table.qualified) WITH CHECK ADD CONSTRAINT \(SQL.identifier(name)) CHECK (\(expression));"
      }
      open(sql); error=""
    } catch { self.error=error.localizedDescription }
  }
}

