import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class ManagedDataModel:ObservableObject {
  var table:TableDefinition?
  var rows:[DataEditRow]=[]
  var selectedRow = -1
  @Published var revision=0
  func editable(row:Int,column:Int) -> Bool {
    guard let table, rows.indices.contains(row), table.columns.indices.contains(column), !rows[row].deleted, !table.columns[column].generated else { return false }
    return rows[row].original == nil || !table.primaryKey.contains(table.columns[column].name)
  }
  func set(_ value:String?,row:Int,column:Int) {
    guard editable(row:row,column:column) else { return }
    rows[row].values[column]=value; rows[row].touched.insert(column)
  }
}
private struct EditableDataGrid:NSViewRepresentable {
  @ObservedObject var model:ManagedDataModel
  func makeCoordinator() -> Coordinator { Coordinator(model:model) }
  func makeNSView(context:Context) -> NSScrollView {
    let scroll=NSScrollView(); scroll.hasHorizontalScroller=true; scroll.hasVerticalScroller=true; scroll.usesPredominantAxisScrolling=true
    let table=context.coordinator.table; table.delegate=context.coordinator; table.dataSource=context.coordinator
    table.usesAlternatingRowBackgroundColors=true; table.rowHeight=25; table.allowsMultipleSelection=false
    table.setAccessibilityIdentifier("managedDataGrid")
    scroll.documentView=table; return scroll
  }
  func updateNSView(_ view:NSScrollView,context:Context) {
    let c=context.coordinator
    if c.columns != model.table?.columns.map(\.name) ?? [] {
      c.columns=model.table?.columns.map(\.name) ?? []
      for column in c.table.tableColumns { c.table.removeTableColumn(column) }
      let row=NSTableColumn(identifier:.init("row")); row.title="#"; row.width=45; c.table.addTableColumn(row)
      for (i,name) in c.columns.enumerated() { let column=NSTableColumn(identifier:.init(String(i))); column.title=name; column.width=150; column.isEditable=true; column.headerToolTip=model.table?.columns[i].type; c.table.addTableColumn(column) }
    }
    c.table.reloadData()
  }
  @MainActor final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
    let model:ManagedDataModel
    let table=NSTableView()
    var columns:[String]=[]
    init(model:ManagedDataModel) { self.model=model }
    func numberOfRows(in tableView:NSTableView) -> Int { model.rows.count }
    func tableView(_ tableView:NSTableView,objectValueFor column:NSTableColumn?,row:Int) -> Any? {
      guard model.rows.indices.contains(row) else { return nil }
      guard let raw=column?.identifier.rawValue, let i=Int(raw) else { return (model.rows[row].deleted ? "− " : model.rows[row].original == nil ? "+ " : "")+String(row+1) }
      return model.rows[row].values[i] ?? "NULL"
    }
    func tableView(_ tableView:NSTableView,shouldEdit column:NSTableColumn?,row:Int) -> Bool { guard let raw=column?.identifier.rawValue, let i=Int(raw) else { return false }; return model.editable(row:row,column:i) }
    func tableView(_ tableView:NSTableView,setObjectValue object:Any?,for column:NSTableColumn?,row:Int) { guard let raw=column?.identifier.rawValue, let i=Int(raw) else { return }; model.set(object as? String ?? "",row:row,column:i) }
    func tableViewSelectionDidChange(_ notification:Notification) { model.selectedRow=table.selectedRow }
    func tableView(_ tableView:NSTableView,willDisplayCell cell:Any,for column:NSTableColumn?,row:Int) {
      guard let cell=cell as? NSTextFieldCell, model.rows.indices.contains(row) else { return }
      cell.font=StudioTheme.uiFont
      cell.textColor=model.rows[row].deleted ? .systemRed : .labelColor
    }
  }
}
struct DataEditorPanel:View {
  let load:() async throws -> (TableDefinition,[DataEditRow])
  let open:(String)->Void
  @StateObject private var model=ManagedDataModel()
  @State private var ready=false
  @State private var error=""
  @State private var nullColumn=0
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Edit Top 200 Rows",icon:"pencil.and.list.clipboard",subtitle:model.table?.qualified ?? "Metadata yükleniyor")
      Text("Hücreye çift tıkla: düzenle · Primary key/identity/computed salt okunur · Yeni satırda dokunulmayan alanlar DEFAULT olur.").font(.caption).foregroundStyle(.secondary)
      HStack {
        Button { guard let table=model.table, model.rows.filter({$0.original==nil}).count < 200 else {return}; model.rows.append(.init(original:nil,values:Array(repeating:nil,count:table.columns.count))); model.revision += 1 } label:{ Label("Satır Ekle",systemImage:"plus") }.disabled(!ready)
        Button("Satırı Sil / Geri Al") { let i=model.selectedRow; guard model.rows.indices.contains(i) else {return}; model.rows[i].deleted.toggle(); model.revision += 1 }.disabled(!ready)
        Picker("NULL kolonu",selection:$nullColumn) { if let table=model.table { ForEach(table.columns.indices,id:\.self) { Text(table.columns[$0].name).tag($0) } } }.frame(width:250)
        StudioActionButton("NULL Yap", icon:"nosign", tint:.orange) { model.set(nil,row:model.selectedRow,column:nullColumn); model.revision += 1 }.disabled(!ready)
        Spacer()
        StudioActionButton("Yenile / Düzenlemeleri Sıfırla", icon:"arrow.clockwise", tint:.orange) { Task { await reload() } }.disabled(!ready)
      }
      if !ready { ProgressView() }
      EditableDataGrid(model:model)
      Text(error).foregroundStyle(.red).textSelection(.enabled)
      HStack {
        Text("Güncellemeler PK + rowversion veya orijinal kolonlarla denetlenir; eşzamanlı değişiklikte transaction geri alınır.").font(.caption).foregroundStyle(.secondary)
        Spacer()
        StudioActionButton("Değişiklikleri SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) {
          NSApp.keyWindow?.makeFirstResponder(nil)
          do { guard let table=model.table else {return}; open(try DataEditScripts.changes(table:table,rows:model.rows)); error="" }
          catch { self.error=error.localizedDescription }
        }.disabled(!ready)
      }
    }.padding(18).studioPanel().task { await reload() }
  }
  private func reload() async {
    ready=false
    do { let (table,rows)=try await load(); model.table=table; model.rows=rows; model.selectedRow = -1; model.revision += 1; ready=true; error="" }
    catch { self.error=error.localizedDescription; ready=false }
  }
}

