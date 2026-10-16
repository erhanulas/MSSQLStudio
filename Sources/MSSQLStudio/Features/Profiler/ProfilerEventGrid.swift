import AppKit
import SwiftUI
import SQLServerKit

private final class ProfilerTextCell:NSTextFieldCell {
  var normalTextColor:NSColor = .labelColor
  override var backgroundStyle:NSView.BackgroundStyle {
    didSet {textColor = backgroundStyle == .emphasized ? .selectedControlTextColor:normalTextColor}
  }
}

private final class ProfilerRowView:NSTableRowView {
  override var isSelected:Bool {didSet {updateInk()}}
  override var isEmphasized:Bool {didSet {updateInk()}}
  override func didAddSubview(_ subview:NSView) {super.didAddSubview(subview);updateInk()}
  private func updateInk() {
    for field in subviews.compactMap({$0 as? NSTextField}) {
      field.cell?.backgroundStyle = isSelected && isEmphasized ? .emphasized:.normal
    }
  }
}

private final class ProfilerTableView:NSTableView {
  var contextMenu:((Int,Int)->NSMenu)?
  override func mouseDown(with event:NSEvent) {
    let modifiers=event.modifierFlags.intersection([.command,.shift,.option,.control])
    let clicked=row(at:convert(event.locationInWindow,from:nil))
    if modifiers.isEmpty,selectedRowIndexes.count>1,clicked>=0 {
      selectRowIndexes(IndexSet(integer:clicked),byExtendingSelection:false)
    }
    super.mouseDown(with:event)
  }
  override func menu(for event:NSEvent)->NSMenu? {
    let row=row(at:convert(event.locationInWindow,from:nil))
    if row>=0 && !selectedRowIndexes.contains(row) {selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
    return contextMenu?(row,column(at:convert(event.locationInWindow,from:nil)))
  }
}
struct ProfilerEventGrid:NSViewRepresentable {
  @ObservedObject var model:ProfilerModel
  @Binding var selection:Set<UInt64>
  func makeCoordinator()->Coordinator {Coordinator(model:model,selection:$selection)}
  func makeNSView(context:Context)->NSScrollView {
    let scroll=NSScrollView(),table=ProfilerTableView()
    scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true
    scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay
    table.usesAlternatingRowBackgroundColors=true;table.rowHeight=24;table.intercellSpacing=NSSize(width:8,height:0)
    table.columnAutoresizingStyle = .noColumnAutoresizing;table.allowsMultipleSelection=true
    for (key,title,width) in Coordinator.columns {
      let column=NSTableColumn(identifier:.init(key));column.title=title;column.width=width;column.minWidth=44
      let cell=FilterHeaderCell(textCell:title);cell.typeSymbol=key=="timestamp" ? "clock":SQLProfilerFiltering.Column(rawValue:key)?.numeric==true ? "number":"textformat"
      column.headerCell=cell;column.width=max(width,GridColumnSizing.headerWidth(title))
      table.addTableColumn(column)
    }
    let header=FilterHeader(frame:NSRect(x:0,y:0,width:0,height:28))
    header.openFilter={ [weak table,weak owner=context.coordinator] position in
      guard let table,table.tableColumns.indices.contains(position) else {return}
      owner?.tableView(table,didClick:table.tableColumns[position])
    }
    table.headerView=header
    table.dataSource=context.coordinator;table.delegate=context.coordinator
    table.contextMenu={ [weak coordinator=context.coordinator] row,column in coordinator?.menu(row:row,column:column) ?? StudioMenu() }
    table.setAccessibilityIdentifier("profilerEventGrid")
    return scroll
  }
  func updateNSView(_ scroll:NSScrollView,context:Context) {
    guard let table=scroll.documentView as? NSTableView else {return}
    let owner=context.coordinator;owner.selection=$selection
    for (key,title,_) in Coordinator.columns {
      if let column=table.tableColumns.first(where:{$0.identifier.rawValue==key}) {
        let active=model.displayFilter.rules.contains {$0.column.rawValue==key && !$0.value.isEmpty} || model.displayFilter.columnRules.contains {$0.key.rawValue==key && $0.value.active}
        column.title=title
        if let cell=column.headerCell as? FilterHeaderCell {cell.active=active}
        column.headerToolTip=active ? "Etkin filtre · Düzenlemek için tıklayın":"Filtrelemek için tıklayın"
      }
    }
    table.headerView?.needsDisplay=true
    scroll.backgroundColor=StudioTheme.resultCanvas;table.backgroundColor=StudioTheme.resultCanvas
    if owner.revision != model.gridRevision {
      owner.revision=model.gridRevision;owner.events=model.visibleEvents
      owner.updating=true
      table.reloadData()
      let indexes=IndexSet(owner.events.indices.filter {selection.contains(owner.events[$0].id)})
      table.selectRowIndexes(indexes,byExtendingSelection:false)
      owner.updating=false
    }
  }
  @MainActor final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
    static let columns:[(String,String,CGFloat)]=[
      ("timestamp","Zaman (UTC)",185),("kind","Olay",150),("messageLevel","Bildirim",85),("errorNumber","Hata no",75),("severity","Önem derecesi",100),("clientPID","ClientProcessID",110),
      ("session","SPID",55),("database","Veritabanı",120),("duration","Süre (ms)",90),
      ("cpu","CPU (ham)",85),("reads","Okuma",80),("writes","Yazma",80),
      ("application","Uygulama",160),("host","Host",140),("login","Login",130),("sql","SQL metni",480)
    ]
    let model:ProfilerModel
    var selection:Binding<Set<UInt64>>
    var events:[SQLProfiler.Event]=[]
    var revision:UUID?
    var updating=false
    private var menuEvent:SQLProfiler.Event?
    private var menuSQL=""
    private var menuColumn:SQLProfilerFiltering.Column?
    private(set) var filterPopover:NSPopover?
    func tableView(_ tableView:NSTableView,didClick tableColumn:NSTableColumn) {
      guard let column=SQLProfilerFiltering.Column(rawValue:tableColumn.identifier.rawValue),let header=tableView.headerView else {return}
      filterPopover?.close()
      let popup=NSPopover()
      let initial=model.displayFilter.columnRules[column] ?? legacyRule(column)
      let panel=ProfilerColumnFilter(model:model,column:column,events:model.events,initial:initial,close:{ [weak popup] in popup?.close()}).studioPanel()
      filterPopover=popup
      let index=tableView.column(withIdentifier:tableColumn.identifier)
      guard index>=0 else {return}
      StudioPopover.show(popup,content:panel,from:header,rect:header.headerRect(ofColumn:index),size:NSSize(width:400,height:540))

    }
    private func legacyRule(_ column:SQLProfilerFiltering.Column)->ColumnRule {
      var result=ColumnRule()
      guard let rule=model.displayFilter.rules.first(where:{$0.column==column}) else {return result}
      result.first=rule.value
      switch rule.comparison {
      case .contains:result.operation = .contains
      case .notContains:result.operation = .notContains
      case .equals:result.operation = .equal
      case .notEquals:result.operation = .unequal
      case .atLeast:result.operation = .atLeast
      case .atMost:result.operation = .atMost
      }
      return result
    }
    init(model:ProfilerModel,selection:Binding<Set<UInt64>>) {self.model=model;self.selection=selection}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView? {ProfilerRowView()}
    func numberOfRows(in tableView:NSTableView)->Int {events.count}
    func tableViewSelectionDidChange(_ notification:Notification) {
      guard !updating,let table=notification.object as? NSTableView else {return}
      selection.wrappedValue=Set(table.selectedRowIndexes.compactMap {events.indices.contains($0) ? events[$0].id:nil})
    }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
      guard events.indices.contains(row),let column=tableColumn else {return nil}
      let cell=(tableView.makeView(withIdentifier:column.identifier,owner:self) as? NSTextField) ?? NSTextField(labelWithString:"")
      if !(cell.cell is ProfilerTextCell) {cell.cell=ProfilerTextCell(textCell:"")}
      (cell.cell as? ProfilerTextCell)?.normalTextColor=column.identifier.rawValue=="messageLevel" ? ProfilerMessagePresentation.color(events[row].messageLevel):.labelColor
      cell.identifier=column.identifier;cell.font=StudioTheme.uiFont;cell.textColor = .labelColor;cell.drawsBackground=false;cell.isBordered=false;cell.isEditable=false;cell.isSelectable=false
      cell.cell?.backgroundStyle = tableView.selectedRowIndexes.contains(row) ? .emphasized:.normal
      cell.lineBreakMode = .byTruncatingTail;cell.maximumNumberOfLines=1
      let event=events[row],key=column.identifier.rawValue
      if key=="timestamp" {cell.stringValue=ProfilerTimestamp.display(event.timestamp)}
      else if key=="duration" {cell.stringValue=event.durationMS.map {String(format:"%.3f",$0)} ?? "—"}
      else if key=="sql" {cell.stringValue=String(event.sql.prefix(240)).replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\r",with:" ")}
      else if let field=SQLProfilerFiltering.Column(rawValue:key) {cell.stringValue=field.value(event)}
      else {cell.stringValue=""}
      cell.alignment=["errorNumber","severity","clientPID","session","duration","cpu","reads","writes"].contains(key) ? .right:.left
      if cell.stringValue.isEmpty {cell.stringValue="—"}
      return cell
    }
    func menu(row:Int,column:Int = -1)->NSMenu {
      menuColumn=Self.columns.indices.contains(column) ? SQLProfilerFiltering.Column(rawValue:Self.columns[column].0):nil
      menuEvent=events.indices.contains(row) ? events[row]:nil
      let chosen=events.filter {selection.wrappedValue.contains($0.id)}
      menuSQL=ProfilerExport.sql(chosen.isEmpty ? menuEvent.map {[$0]} ?? []:chosen)
      let menu=StudioMenu(title:"Profiler");menu.autoenablesItems=false
      func item(_ title:String,_ selector:Selector,_ symbol:String,_ enabled:Bool) {
        let item=NSMenuItem(title:title,action:selector,keyEquivalent:"");item.target=self;item.isEnabled=enabled
        item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:title);menu.addItem(item)
      }
      item("Bu İstemciyi Filtrele",#selector(filterClient),"line.3.horizontal.decrease.circle",menuEvent.map {!$0.host.isEmpty && !$0.clientPID.isEmpty} ?? false)
      if let menuColumn {
        item(menuColumn.title+" değerini filtrele",#selector(filterValue),"line.3.horizontal.decrease",menuEvent != nil && canFilter(menuColumn))
      }
      item("SQL’i Kopyala",#selector(copySQL),"doc.on.doc",menuEvent != nil)
      menu.addItem(.separator())
      item("İzlemeyi Durdur",#selector(stop),"stop.fill",model.hasSession && !model.busy)
      item("Listeyi Temizle",#selector(clear),"clear",!model.events.isEmpty && !model.busy)
      return menu
    }
    private func canFilter(_ column:SQLProfilerFiltering.Column)->Bool {
      model.displayFilter.rules.filter {$0.column != column}.count+model.displayFilter.columnRules.keys.filter {$0 != column}.count<20
    }
    @objc private func filterValue() {
      guard let column=menuColumn,let event=menuEvent,canFilter(column) else {return}
      let value=column.value(event)
      guard !value.isEmpty else {return}
      var filter=model.displayFilter
      filter.columnRules.removeValue(forKey:column)
      filter.rules.removeAll {$0.column==column}
      filter.rules.append(.init(column:column,comparison:.equals,value:value))
      model.displayFilter=filter
    }
    @objc private func filterClient() {
      guard let event=menuEvent,let client=model.clients.first(where:{$0.id.host==event.host && $0.id.pid==event.clientPID}) else {return}
      model.focusClient(client)
    }
    @objc private func copySQL() {guard !menuSQL.isEmpty else {return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(menuSQL,forType:.string)}
    @objc private func stop() {Task {await model.stop()}}
    @objc private func clear() {selection.wrappedValue=[];model.clearDisplay()}
  }
}
