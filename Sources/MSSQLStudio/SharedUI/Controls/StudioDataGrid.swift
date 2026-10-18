import AppKit
import SwiftUI
import SQLServerKit

private final class StudioDataGridTextCell:NSTextFieldCell {
  override var backgroundStyle:NSView.BackgroundStyle {
    didSet {textColor=backgroundStyle == .emphasized ? .selectedControlTextColor:.labelColor}
  }
}

enum StudioGridTone:Int {
  case neutral,success,warning,danger
  @MainActor var color:NSColor {
    switch self {case .neutral:return StudioTheme.muted;case .success:return StudioTheme.success;case .warning:return StudioTheme.warning;case .danger:return StudioTheme.danger}
  }
}
struct StudioGridMenuAction {
  let title:String
  var enabled=true
  let perform:()->Void
}
private final class StudioDataGridScrollView:NSScrollView {
  var fitsColumns=false
  private var fittingColumns=false
  private var fittedWidth:CGFloat=0
  override func tile() {
    super.tile()
    guard fitsColumns,!fittingColumns,let table=documentView as? NSTableView,
      !table.tableColumns.isEmpty,contentSize.width>0,abs(contentSize.width-fittedWidth)>0.5 else {return}
    let spacing=table.intercellSpacing.width*CGFloat(table.tableColumns.count)
    let available=contentSize.width-spacing
    let minimum=table.tableColumns.reduce(CGFloat(0)) {$0+$1.minWidth}
    guard available>=minimum else {return}
    fittingColumns=true;defer {fittingColumns=false}
    fittedWidth=contentSize.width
    let flexible=table.tableColumns.reduce(CGFloat(0)) {$0+max(0,$1.width-$1.minWidth)}
    let remaining=available-minimum
    for column in table.tableColumns {
      let fraction=flexible>0 ? max(0,column.width-column.minWidth)/flexible:1/CGFloat(table.tableColumns.count)
      column.width=column.minWidth+remaining*fraction
    }
  }
}
private final class StudioDataGridTable:StudioColumnSelectionTable {
  var rowMenu:((Int)->NSMenu?)?
  override func menu(for event:NSEvent)->NSMenu? {
    let index=row(at:convert(event.locationInWindow,from:nil))
    guard index>=0 else {return nil}
    selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)
    return rowMenu?(index)
  }
}
@MainActor final class StudioGridStatusCell:NSTableCellView {
  private let label=NSTextField(labelWithString:"")
  private let symbol=NSImageView()
  var selected=false {didSet {applyColor()}}
  private var tone=StudioGridTone.neutral
  private var symbolName=""
  override var backgroundStyle:NSView.BackgroundStyle {didSet {applyColor()}}
  override init(frame:NSRect) {
    super.init(frame:frame)
    for view in [label,symbol] {view.translatesAutoresizingMaskIntoConstraints=false;addSubview(view)}
    label.font=StudioTheme.uiFont;label.lineBreakMode = .byTruncatingTail
    NSLayoutConstraint.activate([
      symbol.leadingAnchor.constraint(equalTo:leadingAnchor,constant:2),symbol.centerYAnchor.constraint(equalTo:centerYAnchor),symbol.widthAnchor.constraint(equalToConstant:14),symbol.heightAnchor.constraint(equalToConstant:14),
      label.leadingAnchor.constraint(equalTo:symbol.trailingAnchor,constant:6),label.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-2),label.centerYAnchor.constraint(equalTo:centerYAnchor)
    ])
    textField=label;imageView=symbol
  }
  required init?(coder:NSCoder) {fatalError()}
  func show(_ text:String,tone:StudioGridTone,symbol:String) {
    label.stringValue=text;self.tone=tone;symbolName=symbol;toolTip=text;applyColor()
  }
  override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();applyColor()}
  private func applyColor() {
    let emphasized=backgroundStyle == .emphasized || backgroundStyle == .dark
    let color=selected ? (emphasized ? NSColor.selectedControlTextColor:NSColor.labelColor):tone.color
    label.textColor=color
    let image=NSImage(systemSymbolName:symbolName,accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[color]))
    image?.isTemplate=false;symbol.image=image
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
    var tone:((Row)->StudioGridTone)?=nil
    var symbol:((Row)->String)?=nil
  }
  let rows:[Row]
  let columns:[Column]
  @Binding var selection:Row.ID?
  var identifier="activityGrid"
  var revision:UUID?=nil
  var fitsColumns=false
  var menu:((Row)->[StudioGridMenuAction])?
  var activate:((Row)->Void)?
  func makeCoordinator()->Coordinator {Coordinator(selection:$selection)}
  func makeNSView(context:Context)->NSScrollView {
    let scroll=StudioDataGridScrollView(),table=StudioDataGridTable()
    scroll.fitsColumns=fitsColumns
    scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true
    table.rowHeight=24;table.intercellSpacing = .zero;table.usesAlternatingRowBackgroundColors=true;table.columnAutoresizingStyle = .noColumnAutoresizing
    table.allowsMultipleSelection=false;table.dataSource=context.coordinator;table.delegate=context.coordinator
    for (index,column) in columns.enumerated() {
      let native=NSTableColumn(identifier:.init(String(index)));native.title=column.title
      native.width=max(column.width,GridColumnSizing.headerWidth(column.title));native.minWidth=100
      let cell=FilterHeaderCell(textCell:column.title);cell.showsSortControl=true;cell.typeSymbol=column.numeric ? "number":"textformat"
      native.headerCell=cell;table.addTableColumn(native)
    }
    let header=FilterHeader(frame:NSRect(x:0,y:0,width:0,height:28))
    header.openFilter={ [weak owner=context.coordinator,weak table] index in
      guard let table,table.tableColumns.indices.contains(index) else {return}
      owner?.openColumnFilter(table,column:table.tableColumns[index])
    }
    header.enableColumnSelection(on:table)
    header.sortColumn={ [weak owner=context.coordinator,weak table] index in
      guard let table,table.tableColumns.indices.contains(index) else {return}
      owner?.tableView(table,didClick:table.tableColumns[index])
    }
    table.headerView=header;table.setAccessibilityIdentifier(identifier)
    table.target=context.coordinator;table.doubleAction=#selector(Coordinator.activateRow(_:))
    table.rowMenu={ [weak owner=context.coordinator] in owner?.menuForRow($0) }
    return scroll
  }
  func updateNSView(_ view:NSScrollView,context:Context) {
    guard let table=view.documentView as? NSTableView else {return}
    context.coordinator.selection=$selection
    context.coordinator.menu=menu;context.coordinator.activate=activate
    context.coordinator.update(rows:rows,columns:columns,table:table,revision:revision)
  }
  static func dismantleNSView(_ view:NSScrollView,coordinator:Coordinator) {coordinator.cancel()}
  @MainActor final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
    var selection:Binding<Row.ID?>
    private var ids:[Row.ID]=[]
    private var revision:UUID?
    private var source=Rows()
    private var snapshotValues:[[String?]]=[]
    private var displayValues:[[String]]=[]
    private var tones:[[StudioGridTone?]]=[]
    private var symbols:[[String?]]=[]
    private var rows:[Row]=[]
    var menu:((Row)->[StudioGridMenuAction])?
    var activate:((Row)->Void)?
    private var indices:[Int]=[]
    private var sortColumn:Int?
    private var ascending=true
    private var rules:[Int:ColumnRule]=[:]
    private let projection=ResultProjectionController()
    private var popover:NSPopover?
    private var updating=false
    init(selection:Binding<Row.ID?>) {self.selection=selection}
    func cancel() {projection.cancel();popover?.close();popover=nil}
    func update(rows:[Row],columns:[Column],table:NSTableView,revision:UUID?=nil) {
      let newIDs=rows.map(\.id)
      if let revision,self.revision==revision,newIDs==ids {select(table);return}
      self.revision=revision
      let values=rows.map {row in columns.map {$0.value(row)}}
      let displays=rows.map {row in columns.map {$0.display?(row) ?? $0.value(row) ?? "—"}}
      self.rows=rows
      let newTones=rows.map {row in columns.map {$0.tone?(row)}}
      let newSymbols=rows.map {row in columns.map {$0.symbol?(row)}}
      let fields=columns.map {Field($0.title,type:$0.numeric ? 3:-9,declaredType:$0.numeric ? "decimal":"nvarchar")}
      guard values != snapshotValues || newIDs != ids || fields != source.fields || displays != displayValues || newTones != tones || newSymbols != symbols else {select(table);return}
      ids=newIDs;snapshotValues=values;displayValues=displays;tones=newTones;symbols=newSymbols
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
      updateStatusSelection(table)
    }
    func tableView(_ table:NSTableView,rowViewForRow row:Int)->NSTableRowView? {
      let view=StudioColumnSelectionRowView();view.columnSelectionTable=table as? StudioColumnSelectionTable
      return view
    }
    func numberOfRows(in tableView:NSTableView)->Int {indices.count}
    func tableViewSelectionDidChange(_ notification:Notification) {
      guard !updating,let table=notification.object as? NSTableView else {return}
      selection.wrappedValue=indices.indices.contains(table.selectedRow) ? ids[indices[table.selectedRow]]:nil
      updateStatusSelection(table)
    }
    private func updateStatusSelection(_ table:NSTableView) {
      table.enumerateAvailableRowViews {_,row in
        for column in table.tableColumns.indices {
          (table.view(atColumn:column,row:row,makeIfNecessary:false) as? StudioGridStatusCell)?.selected=table.selectedRowIndexes.contains(row)
        }
      }
    }
    func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView? {
      guard indices.indices.contains(row),let column,let index=Int(column.identifier.rawValue) else {return nil}
      let sourceIndex=indices[row]
      if let tone=tones[sourceIndex][index] {
        let cell=(tableView.makeView(withIdentifier:column.identifier,owner:self) as? StudioGridStatusCell) ?? StudioGridStatusCell()
        cell.identifier=column.identifier
        cell.show(displayValues[sourceIndex][index],tone:tone,symbol:symbols[sourceIndex][index] ?? "circle.fill")
        cell.selected=tableView.selectedRowIndexes.contains(row)
        cell.backgroundStyle=cell.selected ? .emphasized:.normal
        return cell
      }
      let cell=(tableView.makeView(withIdentifier:column.identifier,owner:self) as? NSTextField) ?? NSTextField(labelWithString:"")
      if !(cell.cell is StudioDataGridTextCell) {cell.cell=StudioDataGridTextCell(textCell:"")}
      cell.cell?.backgroundStyle=tableView.selectedRowIndexes.contains(row) ? .emphasized:.normal
      cell.identifier=column.identifier;cell.font=StudioTheme.uiFont;cell.lineBreakMode = .byTruncatingTail
      cell.stringValue=displayValues[indices[row]][index]
      return cell
    }
    func menuForRow(_ index:Int)->NSMenu? {
      guard indices.indices.contains(index),let actions=menu?(rows[indices[index]]) else {return nil}
      let result=StudioMenu()
      for action in actions {
        let item=NSMenuItem(title:action.title,action:#selector(invokeMenuAction(_:)),keyEquivalent:"")
        item.target=self;item.representedObject=action;item.isEnabled=action.enabled;result.addItem(item)
      }
      result.autoenablesItems=false;return result
    }
    @objc func invokeMenuAction(_ item:NSMenuItem) {(item.representedObject as? StudioGridMenuAction)?.perform()}
    @objc func activateRow(_ table:NSTableView) {
      let index=table.clickedRow>=0 ? table.clickedRow:table.selectedRow
      guard indices.indices.contains(index) else {return}
      activate?(rows[indices[index]])
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
