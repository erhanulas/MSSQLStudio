import AppKit
import SwiftUI
import SQLServerKit

@MainActor final class SuggestionTable: NSTableView {
  override var acceptsFirstResponder: Bool { false }
}
@MainActor enum SQLSuggestionStyle {
  static func title(_ kind: SQLIntelligence.Suggestion.Kind) -> String {
    switch kind {
    case .table: return "Tablo"
    case .view: return "Görünüm"
    case .procedure: return "Prosedür"
    case .synonym: return "Eş anlamlı"
    case .column: return "Kolon"
    case .variable: return "Değişken"
    case .keyword: return "Anahtar sözcük"
    case .function: return "Fonksiyon"
    }
  }
  static func symbol(_ kind: SQLIntelligence.Suggestion.Kind) -> String {
    switch kind {
    case .table: return "tablecells"
    case .view: return "rectangle.on.rectangle"
    case .procedure: return "terminal"
    case .synonym: return "link"
    case .column: return "rectangle.split.3x1"
    case .variable: return "at"
    case .keyword: return "curlybraces"
    case .function: return "function"
    }
  }
  static func color(_ kind: SQLIntelligence.Suggestion.Kind) -> NSColor {
    switch kind {
    case .table, .view: return StudioTheme.accent
    case .column: return StudioTheme.success
    case .variable: return StudioTheme.text
    case .procedure: return StudioTheme.syntax(.procedure)
    case .function: return StudioTheme.syntax(.function)
    case .synonym: return StudioTheme.warning
    case .keyword: return StudioTheme.syntax(.keyword)
    }
  }
}
@MainActor private final class SQLSuggestionRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    StudioTheme.selection.setFill()
    NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:7,yRadius:7).fill()
    StudioTheme.accent.withAlphaComponent(0.35).setStroke()
    let border=NSBezierPath(roundedRect:bounds.insetBy(dx:1.5,dy:1.5),xRadius:7,yRadius:7)
    border.lineWidth=1; border.stroke()
  }
}
@MainActor private final class SQLSuggestionCell: NSTableCellView {
  var item: SQLIntelligence.Suggestion?
  var prefix = ""
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    guard let item else { return }
    let color=SQLSuggestionStyle.color(item.kind)
    color.withAlphaComponent(StudioTheme.dark ? 0.16:0.08).setFill()
    NSBezierPath(roundedRect:NSRect(x:5,y:3,width:20,height:20),xRadius:4,yRadius:4).fill()
    NSImage(systemSymbolName:SQLSuggestionStyle.symbol(item.kind),accessibilityDescription:nil)?
      .withSymbolConfiguration(.init(paletteColors:[color]))?
      .draw(in:NSRect(x:8,y:6,width:14,height:14))
    let paragraph=NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
    let label=NSMutableAttributedString(string:item.label,attributes:[.font:NSFont.monospacedSystemFont(ofSize:12,weight:.medium),.foregroundColor:StudioTheme.text,.paragraphStyle:paragraph])
    if !prefix.isEmpty {
      let match=(item.label as NSString).range(of:prefix,options:.caseInsensitive)
      if match.location != NSNotFound { label.addAttributes([.foregroundColor:StudioTheme.accent,.font:NSFont.monospacedSystemFont(ofSize:12,weight:.bold)],range:match) }
    }
    label.draw(in:NSRect(x:34,y:5,width:max(0,bounds.width-140),height:17))
    paragraph.alignment = .right
    SQLSuggestionStyle.title(item.kind).draw(in:NSRect(x:bounds.width-100,y:6,width:90,height:14),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:StudioTheme.muted,.paragraphStyle:paragraph])
  }
}
@MainActor private final class SQLSuggestionSurface: NSView {
  let scroll=NSScrollView()
  var count=0 { didSet { needsDisplay=true } }
  override var isFlipped: Bool { true }
  override init(frame:NSRect) {
    super.init(frame:frame)
    addSubview(scroll); scroll.drawsBackground=false
    scroll.automaticallyAdjustsContentInsets=false; scroll.contentInsets = NSEdgeInsets(top:0,left:0,bottom:0,right:0)
    scroll.hasVerticalScroller=true; scroll.autohidesScrollers=true
    scroll.horizontalScrollElasticity = .none; scroll.verticalScrollElasticity = .none
  }
  required init?(coder:NSCoder) { fatalError() }
  override func layout() {
    super.layout()
    scroll.frame=NSRect(x:6,y:27,width:max(0,bounds.width-12),height:max(0,bounds.height-52))
    (scroll.documentView as? NSTableView)?.tableColumns.first?.width=max(0,scroll.contentSize.width)
  }
  override func draw(_ dirtyRect:NSRect) {
    StudioTheme.canvas.setFill(); bounds.fill()
    StudioTheme.panel.setFill()
    NSRect(x:0,y:0,width:bounds.width,height:25).fill()
    NSRect(x:0,y:bounds.height-23,width:bounds.width,height:23).fill()
    StudioTheme.border.setFill()
    NSRect(x:0,y:24,width:bounds.width,height:1).fill()
    NSRect(x:0,y:bounds.height-23,width:bounds.width,height:1).fill()
    "SQL TAMAMLAMA".draw(at:NSPoint(x:14,y:6),withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.semibold),.foregroundColor:StudioTheme.muted])
    let countLabel="\(count) öneri"
    let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:10,weight:.medium),.foregroundColor:StudioTheme.accent]
    countLabel.draw(at:NSPoint(x:bounds.width-countLabel.size(withAttributes:attributes).width-14,y:6),withAttributes:attributes)
    "↑ ↓  Gezin    PgUp / PgDn  Sayfa    ⇥ / ↵  Ekle    esc  Kapat".draw(at:NSPoint(x:14,y:bounds.height-18),withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.medium),.foregroundColor:StudioTheme.muted])
  }
}
@MainActor final class SQLSuggestionList: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  let table = SuggestionTable()
  private(set) var items: [SQLIntelligence.Suggestion] = []
  private var prefix = ""
  var accept: ((Int) -> Void)?
  override func loadView() {
    let surface=SQLSuggestionSurface(frame:NSRect(x:0,y:0,width:500,height:200))
    surface.autoresizingMask = [.width,.height]
    let column=NSTableColumn(identifier:.init("suggestion")); column.width=488
    table.addTableColumn(column); table.headerView=nil; table.rowHeight=26
    table.style = .plain
    table.intercellSpacing=NSSize(width:0,height:0); table.backgroundColor=StudioTheme.canvas
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.delegate=self; table.dataSource=self; table.target=self; table.doubleAction=#selector(commit)
    table.focusRingType = .none
    table.setAccessibilityIdentifier("sqlSuggestions")
    table.setAccessibilityLabel("SQL tamamlama önerileri")
    table.setAccessibilityHelp("Yukarı/aşağı ile gezin, Tab veya Enter ile ekleyin; Escape ile kapatın.")
    surface.scroll.documentView=table; view=surface
    NotificationCenter.default.addObserver(self,selector:#selector(refreshTheme),name:StudioTheme.changed,object:nil)
  }
  @objc private func refreshTheme() {
    table.backgroundColor=StudioTheme.canvas
    table.enumerateAvailableRowViews { row, _ in
      row.needsDisplay=true; for child in row.subviews { child.needsDisplay=true }
    }
    view.needsDisplay=true
  }
  @objc private func commit() { if table.selectedRow >= 0 { accept?(table.selectedRow) } }
  func numberOfRows(in tableView: NSTableView) -> Int { items.count }
  func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? { SQLSuggestionRowView() }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let identifier=NSUserInterfaceItemIdentifier("sqlSuggestionCell")
    let cell=tableView.makeView(withIdentifier:identifier,owner:self) as? SQLSuggestionCell ?? SQLSuggestionCell()
    cell.identifier=identifier; cell.item=items[row]; cell.prefix=prefix; cell.needsDisplay=true
    cell.toolTip=SQLSuggestionStyle.title(items[row].kind)+" · "+items[row].text+(items[row].detail.isEmpty ? "":"\n"+items[row].detail)+"\nTab/Enter ile ekle; Escape kapatır"
    cell.setAccessibilityElement(true); cell.setAccessibilityRole(.staticText)
    cell.setAccessibilityLabel(items[row].label+" · "+SQLSuggestionStyle.title(items[row].kind))
    cell.setAccessibilityHelp(items[row].text)
    return cell
  }
  func update(_ items: [SQLIntelligence.Suggestion], prefix:String = "") {
    self.items=items; self.prefix=prefix; _ = view
    (view as? SQLSuggestionSurface)?.count=items.count
    table.reloadData(); if !items.isEmpty { table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false) }
    preferredContentSize=NSSize(width:500,height:CGFloat(max(1,min(16,items.count)))*26+52)
    view.frame.size=preferredContentSize; view.needsLayout=true
    view.layoutSubtreeIfNeeded(); if !items.isEmpty { table.scrollRowToVisible(0) }
  }
  func fit(maximumHeight:CGFloat) {
    // Keep full rows between the fixed heading and keyboard hint footer.
    let rows=max(1,min(16,Int((maximumHeight-52)/26),max(1,items.count)))
    preferredContentSize=NSSize(width:500,height:CGFloat(rows)*26+52)
    view.frame.size=preferredContentSize; view.needsLayout=true; view.layoutSubtreeIfNeeded()
  }
  var visibleRowCount:Int {max(1,Int((view.bounds.height-52)/26))}
  static func placement(anchor:NSRect,screen:NSRect,preferredHeight:CGFloat) -> (below:Bool,height:CGFloat) {
    let above=max(0,screen.maxY-anchor.maxY-32), below=max(0,anchor.minY-screen.minY-32)
    let down=below >= preferredHeight || (above < preferredHeight && below >= above)
    return (down,down ? below:above)
  }
  func move(_ step: Int) {
    guard !items.isEmpty else { return }
    let row = max(0,min(items.count-1,table.selectedRow+step))
    table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false); table.scrollRowToVisible(row)
  }
}

