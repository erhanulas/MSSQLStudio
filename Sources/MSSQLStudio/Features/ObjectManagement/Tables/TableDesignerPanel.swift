import AppKit
import SQLServerKit
import SwiftUI

struct TableDesignerPanel: View {
  let server:String
  let database:String
  let initialKind:String
  @State private var tab="columns"
  let load:(() async throws -> TableDefinition)?
  let open:(String)->Void
  @State private var original:TableDefinition?
  @State private var schema="dbo"
  @State private var name="NewTable"
  @State private var columns:[SQLServerKit.TableColumn]=[SQLServerKit.TableColumn(id:-1,name:"Id",type:"int",nullable:false,identity:true)]
  @State private var primary:Set<Int>=[-1]
  @State private var selectedColumn=Int.min
  private struct ColumnFocus:Hashable {let id:Int;let field:Int}
  @FocusState private var focusedColumn:ColumnFocus?
  @State private var ready=false
  @State private var error=""
  @State private var preview=""
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:load == nil ? "New Table" : "Table Designer",icon:"tablecells",subtitle:server+" · "+database)
      VStack(alignment:.leading,spacing:10) { StudioFormField("Şema") {TextField("Şema",text:$schema).disabled(load != nil)}; StudioFormField("Tablo adı") {TextField("Tablo adı",text:$name).disabled(load != nil)}; Text("\(columns.count) kolon").font(.caption).foregroundStyle(.secondary) }.studioCard()
      if !ready { ProgressView("Metadata yükleniyor…") }
      TabView(selection:$tab) {
        columnEditor.tag("columns").tabItem { Label("Columns",systemImage:"tablecells") }
        if let original {
          StructureObjectsPanel(table:original,initialKind:initialKind,open:open).tag("management").tabItem { Label("Keys / Indexes / Relationships",systemImage:"link") }
        }
      }
      if !error.isEmpty { StudioFeedback(message:error) }
      HStack {
        StudioActionButton("Değişiklik Scripti Oluştur", icon:"doc.badge.gearshape", tint:.accentColor) { generate() }.disabled(!ready)
        StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) { generate(); if !preview.isEmpty { open(preview) } }.disabled(!ready)
        Spacer()
        Text("Bağımlı nesneler varsa SQL Server değişikliği reddedebilir; otomatik tablo rebuild yapılmaz.").font(.caption).foregroundStyle(.secondary)
      }
      if !preview.isEmpty { SQLReadOnlyPreview(sql:preview).frame(minHeight:90,idealHeight:130,maxHeight:180) }
    }.padding(StudioMetrics.gap).studioPanel().task {
      do {
        if let load { let table=try await load(); original=table; schema=table.schema; name=table.name; columns=table.columns; primary=Set(table.columns.filter { table.primaryKey.contains($0.name) }.map(\.id)) }
        if !initialKind.isEmpty { tab="management" }
        ready=true
      } catch { self.error=error.localizedDescription }
    }
  }
  private var columnEditor:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Button {
          let id=min(0,columns.map(\.id).min() ?? 0)-1
          var name="NewColumn",suffix=2
          while columns.contains(where:{$0.name.caseInsensitiveCompare(name) == .orderedSame}) {name="NewColumn\(suffix)";suffix+=1}
          columns.append(SQLServerKit.TableColumn(id:id,name:name));selectedColumn=id;preview=""
        } label:{Label("Kolon Ekle",systemImage:"plus")}.accessibilityIdentifier("addDesignerColumn")
        Button(role:.destructive) {columns.removeAll {$0.id==selectedColumn};primary.remove(selectedColumn);selectedColumn=Int.min;preview=""} label:{Label("Seçili Kolonu Kaldır",systemImage:"minus.circle")}.disabled(!columns.contains {$0.id==selectedColumn}).accessibilityIdentifier("removeDesignerColumn")
        Spacer()
        Text(columns.first(where:{$0.id==selectedColumn}).map {"Seçili: "+$0.name} ?? "Düzenlemek için satıra tıklayın").font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }.fixedSize(horizontal:false,vertical:true)
      Divider()
      ScrollViewReader { proxy in
      ScrollView([.horizontal,.vertical]) {
        LazyVStack(alignment:.leading,spacing:6) {
          HStack {Color.clear.frame(width:28,height:1);Text("Kolon adı").frame(width:150);Text("Veri tipi").frame(width:150);Text("NULL").frame(width:45);Text("PK").frame(width:40);Text("Identity").frame(width:70);Text("Default / computed").frame(width:240,alignment:.leading)}.font(.caption).foregroundStyle(.secondary)
          ForEach($columns) { $column in
            HStack {
              Button {selectedColumn=column.id;focusedColumn=ColumnFocus(id:column.id,field:0)} label:{Image(systemName:selectedColumn == column.id ? "arrowtriangle.right.fill" : "circle").foregroundStyle(selectedColumn == column.id ? Color.accentColor : Color.secondary).frame(width:28,height:24).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel(column.name+" kolonunu seç").accessibilityIdentifier("selectDesignerColumn_\(column.id)").studioHelp("Bu kolonu seç; üstteki − düğmesi seçili kolonu kaldırır.")
              TextField("Kolon",text:$column.name).frame(width:150).focused($focusedColumn,equals:ColumnFocus(id:column.id,field:0))
              TextField("int / nvarchar(100)",text:$column.type).frame(width:150).disabled(original?.columns.first(where:{$0.id==column.id})?.generated == true).focused($focusedColumn,equals:ColumnFocus(id:column.id,field:1))
              Toggle("",isOn:$column.nullable).labelsHidden().frame(width:45).disabled(column.identity || !column.computed.isEmpty)
              Toggle("",isOn:Binding(get:{primary.contains(column.id)},set:{if $0 {primary.insert(column.id);if let i=columns.firstIndex(where:{$0.id==column.id}) {columns[i].nullable=false}} else {primary.remove(column.id)}})).labelsHidden().frame(width:40)
              Toggle("",isOn:Binding(get:{column.identity},set:{column.identity=$0;if $0 {column.nullable=false}})).labelsHidden().frame(width:70).disabled(original?.columns.contains(where:{$0.id==column.id}) == true)
              if column.computed.isEmpty {TextField("DEFAULT SQL",text:$column.defaultSQL).frame(width:240).focused($focusedColumn,equals:ColumnFocus(id:column.id,field:2))}
              else {Text("AS "+column.computed).lineLimit(1).frame(width:240,alignment:.leading).studioHelp(column.computed)}
            }.padding(.vertical,3).background(selectedColumn == column.id ? Color.accentColor.opacity(0.13) : Color.clear).overlay(alignment:.leading) {if selectedColumn == column.id {Rectangle().fill(Color.accentColor).frame(width:2)}}.contentShape(Rectangle()).simultaneousGesture(TapGesture().onEnded {selectedColumn=column.id}).id(column.id)
          }
        }.padding(.vertical,8)
      }.frame(minHeight:80,maxHeight:.infinity).layoutPriority(-1)
      .onChange(of:columns.count) {old,new in if new > old,let selected=columns.last,selected.id==selectedColumn {proxy.scrollTo(selected.id,anchor:.bottom)} }
      }
      Text("Identity seed/increment yeni kolonlarda 1,1. Computed/özel üretilen kolon değişikliği SQL editöründe yapılır.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
    }.padding(10).disabled(!ready).onChange(of:focusedColumn) {_,focus in if let focus {selectedColumn=focus.id} }
  }
  private func generate() {
    do { preview=try ObjectScripts.tableChanges(original:original,schema:schema,name:name,columns:columns,primaryKey:columns.filter { primary.contains($0.id) }.map(\.name)); error="" }
    catch { preview=""; self.error=error.localizedDescription }
  }
}
