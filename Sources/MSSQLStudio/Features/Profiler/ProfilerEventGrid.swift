import AppKit
import SwiftUI
import SQLServerKit

private final class ProfilerTableView:NSTableView {
  var contextMenu:((Int)->NSMenu)?
  override func menu(for event:NSEvent)->NSMenu? {
    let row=row(at:convert(event.locationInWindow,from:nil))
    if row>=0 {selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
    return contextMenu?(row)
  }
}
struct ProfilerEventGrid:NSViewRepresentable {
  @ObservedObject var model:ProfilerModel
  @Binding var selection:UInt64?
  func makeCoordinator()->Coordinator {Coordinator(model:model,selection:$selection)}
  func makeNSView(context:Context)->NSScrollView {
    let scroll=NSScrollView(),table=ProfilerTableView()
    scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true
    scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay
    table.usesAlternatingRowBackgroundColors=true;table.rowHeight=24;table.intercellSpacing=NSSize(width:8,height:0)
    table.columnAutoresizingStyle = .noColumnAutoresizing;table.allowsMultipleSelection=false
    for (key,title,width) in Coordinator.columns {
      let column=NSTableColumn(identifier:.init(key));column.title=title;column.width=width;column.minWidth=44
      table.addTableColumn(column)
    }
    table.dataSource=context.coordinator;table.delegate=context.coordinator
    table.contextMenu={ [weak coordinator=context.coordinator] row in coordinator?.menu(row:row) ?? StudioMenu() }
    table.setAccessibilityIdentifier("profilerEventGrid")
    return scroll
  }
  func updateNSView(_ scroll:NSScrollView,context:Context) {
    guard let table=scroll.documentView as? NSTableView else {return}
    let owner=context.coordinator;owner.selection=$selection
    scroll.backgroundColor=StudioTheme.resultCanvas;table.backgroundColor=StudioTheme.resultCanvas
    if owner.revision != model.gridRevision {
      owner.revision=model.gridRevision;owner.events=model.visibleEvents
      owner.updating=true
      table.reloadData()
      let index=owner.events.firstIndex {$0.id==selection}
      if let index {table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)} else {table.deselectAll(nil)}
      owner.updating=false
    }
  }
  @MainActor final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
    static let columns:[(String,String,CGFloat)]=[
      ("timestamp","Zaman (UTC)",185),("kind","Olay",150),("clientPID","ClientProcessID",110),
      ("session","SPID",55),("database","Veritabanı",120),("duration","Süre (ms)",90),
      ("cpu","CPU (ham)",85),("reads","Okuma",80),("writes","Yazma",80),
      ("application","Uygulama",160),("host","Host",140),("login","Login",130),("sql","SQL metni",480)
    ]
    let model:ProfilerModel
    var selection:Binding<UInt64?>
    var events:[SQLProfiler.Event]=[]
    var revision:UUID?
    var updating=false
    private var menuEvent:SQLProfiler.Event?
    init(model:ProfilerModel,selection:Binding<UInt64?>) {self.model=model;self.selection=selection}
    func numberOfRows(in tableView:NSTableView)->Int {events.count}
    func tableViewSelectionDidChange(_ notification:Notification) {
      guard !updating,let table=notification.object as? NSTableView else {return}
      selection.wrappedValue=events.indices.contains(table.selectedRow) ? events[table.selectedRow].id:nil
    }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
      guard events.indices.contains(row),let column=tableColumn else {return nil}
      let cell=(tableView.makeView(withIdentifier:column.identifier,owner:self) as? NSTextField) ?? NSTextField(labelWithString:"")
      cell.identifier=column.identifier;cell.font=StudioTheme.uiFont;cell.textColor=StudioTheme.text
      cell.lineBreakMode = .byTruncatingTail;cell.maximumNumberOfLines=1
      let event=events[row],key=column.identifier.rawValue
      if key=="timestamp" {cell.stringValue=event.timestamp}
      else if key=="duration" {cell.stringValue=event.durationMS.map {String(format:"%.3f",$0)} ?? "—"}
      else if key=="sql" {cell.stringValue=String(event.sql.prefix(240)).replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\r",with:" ")}
      else if let field=SQLProfilerFiltering.Column(rawValue:key) {cell.stringValue=field.value(event)}
      else {cell.stringValue=""}
      cell.alignment=["clientPID","session","duration","cpu","reads","writes"].contains(key) ? .right:.left
      if cell.stringValue.isEmpty {cell.stringValue="—"}
      return cell
    }
    func menu(row:Int)->NSMenu {
      menuEvent=events.indices.contains(row) ? events[row]:nil
      let menu=StudioMenu(title:"Profiler");menu.autoenablesItems=false
      func item(_ title:String,_ selector:Selector,_ symbol:String,_ enabled:Bool) {
        let item=NSMenuItem(title:title,action:selector,keyEquivalent:"");item.target=self;item.isEnabled=enabled
        item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:title);menu.addItem(item)
      }
      item("Bu İstemciyi Filtrele",#selector(filterClient),"line.3.horizontal.decrease.circle",menuEvent.map {!$0.host.isEmpty && !$0.clientPID.isEmpty} ?? false)
      item("SQL’i Kopyala",#selector(copySQL),"doc.on.doc",menuEvent != nil)
      menu.addItem(.separator())
      item("İzlemeyi Durdur",#selector(stop),"stop.fill",model.hasSession && !model.busy)
      item("Listeyi Temizle",#selector(clear),"clear",!model.events.isEmpty && !model.busy)
      return menu
    }
    @objc private func filterClient() {
      guard let event=menuEvent,let client=model.clients.first(where:{$0.id.host==event.host && $0.id.pid==event.clientPID}) else {return}
      model.focusClient(client)
    }
    @objc private func copySQL() {guard let event=menuEvent else {return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(event.sql,forType:.string)}
    @objc private func stop() {Task {await model.stop()}}
    @objc private func clear() {selection.wrappedValue=nil;model.clearDisplay()}
  }
}
