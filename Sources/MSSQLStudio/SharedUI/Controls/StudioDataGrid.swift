import AppKit
import SwiftUI
import SQLServerKit

private final class StudioDataGridTextCell:NSTextFieldCell {
  override var backgroundStyle:NSView.BackgroundStyle {
    didSet {textColor=backgroundStyle == .emphasized ? .selectedControlTextColor:.labelColor}
  }
}

/// Read-only monitoring rows with the result grid's native filter header and rule editor.
struct StudioDataGrid<Row:Identifiable>:NSViewRepresentable {
  struct Column {
    let title:String
    var width:CGFloat=110
    var numeric=false
    let value:(Row)->String?
    var display:((Row)->String)?=nil
  }
  let rows:[Row]
  let columns:[Column]
  @Binding var selection:Row.ID?
  var identifier="activityGrid"
  func makeCoordinator()->Coordinator {Coordinator(selection:$selection)}
  func makeNSView(context:Context)->NSScrollView {
    let scroll=NSScrollView(),table=NSTableView()
    scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true
    table.rowHeight=24;table.usesAlternatingRowBackgroundColors=true;table.columnAutoresizingStyle = .noColumnAutoresizing
    table.allowsMultipleSelection=false;table.dataSource=context.coordinator;table.delegate=context.coordinator
    for (index,column) in columns.enumerated() {
      let native=NSTableColumn(identifier:.init(String(index)));native.title=column.title
      native.width=max(column.width,GridColumnSizing.headerWidth(column.title));native.minWidth=44
      let cell=FilterHeaderCell(textCell:column.title);cell.typeSymbol=column.numeric ? "number":"textformat"
      native.headerCell=cell;table.addTableColumn(native)
    }
    let header=FilterHeader(frame:NSRect(x:0,y:0,width:0,height:28))
    header.openFilter={ [weak owner=context.coordinator,weak table] index in
      guard let table,table.tableColumns.indices.contains(index) else {return}
      owner?.openColumnFilter(table,column:table.tableColumns[index])
    }
    table.headerView=header;table.setAccessibilityIdentifier(identifier)
    return scroll
  }
  func updateNSView(_ view:NSScrollView,context:Context) {
    guard let table=view.documentView as? NSTableView else {return}
    context.coordinator.selection=$selection
    context.coordinator.update(rows:rows,columns:columns,table:table)
  }
  static func dismantleNSView(_ view:NSScrollView,coordinator:Coordinator) {coordinator.cancel()}
  @MainActor final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
    var selection:Binding<Row.ID?>
    private var ids:[Row.ID]=[]
    private var source=Rows()
    private var snapshotValues:[[String?]]=[]
    private var displayValues:[[String]]=[]
    private var indices:[Int]=[]
    private var sortColumn:Int?
    private var ascending=true
    private var rules:[Int:ColumnRule]=[:]
    private let projection=ResultProjectionController()
    private var popover:NSPopover?
    private var updating=false
    init(selection:Binding<Row.ID?>) {self.selection=selection}
    func cancel() {projection.cancel();popover?.close();popover=nil}
    func update(rows:[Row],columns:[Column],table:NSTableView) {
      let values=rows.map {row in columns.map {$0.value(row)}}
      let newIDs=rows.map(\.id)
      let displays=rows.map {row in columns.map {$0.display?(row) ?? $0.value(row) ?? "—"}}
      let fields=columns.map {Field($0.title,type:$0.numeric ? 3:-9,declaredType:$0.numeric ? "decimal":"nvarchar")}
      guard values != snapshotValues || newIDs != ids || fields != source.fields || displays != displayValues else {select(table);return}
      ids=newIDs;snapshotValues=values;displayValues=displays
      source=Rows(fields:fields,values:values)
      apply(table)
    }
    private func apply(_ table:NSTableView) {
      projection.cancel()
      for (index,column) in table.tableColumns.enumerated() {
        (column.headerCell as? FilterHeaderCell)?.active=rules[index]?.active==true
        (column.headerCell as? FilterHeaderCell)?.ascending=sortColumn==index ? ascending:nil
      }
      table.headerView?.needsDisplay=true
      if rules.isEmpty,sortColumn==nil {indices=Array(ids.indices);reload(table);return}
      indices=[];updating=true;table.reloadData();updating=false
      projection.project(.init(rows:source,search:"",rules:rules,sortColumn:sortColumn,ascending:ascending),debounce:false) { [weak self,weak table] result in
        guard let self,let table else {return}
        switch result {
        case .success(let output):indices=output ?? Array(ids.indices)
        case .failure:indices=[]
        }
        if let id=selection.wrappedValue,!indices.contains(where:{ids[$0]==id}) {selection.wrappedValue=nil}
        reload(table)
      }
    }
    private func reload(_ table:NSTableView) {updating=true;table.reloadData();updating=false;select(table)}
    private func select(_ table:NSTableView) {
      updating=true;defer {updating=false}
      if let id=selection.wrappedValue,let index=indices.firstIndex(where:{ids[$0]==id}) {table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
      else {table.deselectAll(nil)}
    }
    func numberOfRows(in tableView:NSTableView)->Int {indices.count}
    func tableViewSelectionDidChange(_ notification:Notification) {
      guard !updating,let table=notification.object as? NSTableView else {return}
      selection.wrappedValue=indices.indices.contains(table.selectedRow) ? ids[indices[table.selectedRow]]:nil
    }
    func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView? {
      guard indices.indices.contains(row),let column,let index=Int(column.identifier.rawValue) else {return nil}
      let cell=(tableView.makeView(withIdentifier:column.identifier,owner:self) as? NSTextField) ?? NSTextField(labelWithString:"")
      if !(cell.cell is StudioDataGridTextCell) {cell.cell=StudioDataGridTextCell(textCell:"")}
      cell.cell?.backgroundStyle=tableView.selectedRowIndexes.contains(row) ? .emphasized:.normal
      cell.identifier=column.identifier;cell.font=StudioTheme.uiFont;cell.lineBreakMode = .byTruncatingTail
      cell.stringValue=displayValues[indices[row]][index]
      return cell
    }
    func setRule(_ rule:ColumnRule,column:Int,table:NSTableView) throws {
      guard source.fields.indices.contains(column) else {return}
      try ResultFiltering.validate(rule,field:source.fields[column])
      if rule.active {rules[column]=rule} else {rules.removeValue(forKey:column)}
      apply(table)
    }
    func tableView(_ table:NSTableView,didClick column:NSTableColumn) {
      guard let index=Int(column.identifier.rawValue),source.fields.indices.contains(index) else {return}
      if sortColumn != index {sortColumn=index;ascending=true}
      else if ascending {ascending=false}
      else {sortColumn=nil;ascending=true}
      apply(table)
    }
    func openColumnFilter(_ table:NSTableView,column:NSTableColumn) {
      guard let index=Int(column.identifier.rawValue),source.fields.indices.contains(index),let header=table.headerView else {return}
      popover?.close();let popup=NSPopover();popover=popup
      let panel=ColumnFilterPanel(rows:source,column:index,initial:rules[index] ?? .init()) { [weak self,weak table,weak popup] rule in
        guard let self,let table else {return}
        try setRule(rule,column:index,table:table);popup?.close()
      }.studioPanel()
      StudioPopover.show(popup,content:panel,from:header,rect:header.headerRect(ofColumn:index),size:NSSize(width:400,height:540))
    }
  }
}
