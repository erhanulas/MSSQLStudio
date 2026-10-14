import AppKit
import SQLServerKit

/// A scrollable projection, preserving SQL Server column ordinals and complete type text.
@MainActor final class FunctionReturnPreview: NSView, NSTableViewDataSource, NSTableViewDelegate {
  let columns: [SQLObjectHover.Column]
  let table = NSTableView()
  let scroll = NSScrollView()
  private var tracking: NSTrackingArea?
  init(title: String, columns: [SQLObjectHover.Column], screen: NSSize) {
    self.columns = columns
    let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    let widths: [CGFloat] = [36,
      max(120, columns.map { ($0.name as NSString).size(withAttributes: [.font: font]).width + 20 }.max() ?? 120),
      max(150, columns.map { ($0.type as NSString).size(withAttributes: [.font: font]).width + 20 }.max() ?? 150)]
    let width = min(max(360, widths.reduce(0,+) + 20), min(760, screen.width-24))
    let headingHeight = ceil((title as NSString).boundingRect(with: NSSize(width: width-24,height: 1000),options: [.usesLineFragmentOrigin,.usesFontLeading],attributes: [.font: NSFont.systemFont(ofSize: 12,weight: .semibold)]).height)
    let top = headingHeight+44
    let height = min(CGFloat(columns.count)*24+top+36, min(440, screen.height-32))
    super.init(frame: NSRect(x: 0,y: 0,width: width,height: height))
    let heading = NSTextField(wrappingLabelWithString: title)
    heading.font = .systemFont(ofSize: 12,weight: .semibold); heading.textColor = StudioTheme.accent
    heading.frame = NSRect(x: 12,y: height-12-headingHeight,width: width-24,height: headingHeight)
    heading.maximumNumberOfLines = 0
    let subtitle = NSTextField(labelWithString: "TABLE · \(columns.count) dönüş kolonu")
    subtitle.font = .systemFont(ofSize: 11); subtitle.textColor = StudioTheme.muted
    subtitle.frame = NSRect(x: 12,y: height-top+10,width: width-24,height: 16)
    scroll.frame = NSRect(x: 8,y: 8,width: width-16,height: height-top-8)
    scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay; scroll.borderType = .noBorder
    table.style = .plain; scroll.automaticallyAdjustsContentInsets = false
    table.intercellSpacing = NSSize(width: 0,height: 0); table.rowHeight = 24
    table.backgroundColor = StudioTheme.panel; table.usesAlternatingRowBackgroundColors = true
    table.columnAutoresizingStyle = .noColumnAutoresizing
    table.allowsColumnReordering = false; table.allowsColumnResizing = false
    table.selectionHighlightStyle = .none
    for (index,title) in ["#","Kolon","Veri tipi"].enumerated() {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
      column.title = title; column.width = widths[index]; table.addTableColumn(column)
    }
    table.dataSource = self; table.delegate = self; scroll.documentView = table
    table.setAccessibilityIdentifier("functionReturnColumns")
    addSubview(heading); addSubview(subtitle); addSubview(scroll)
    table.reloadData()
  }
  required init?(coder: NSCoder) {fatalError()}
  func numberOfRows(in tableView: NSTableView) -> Int {columns.count}
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {false}
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard columns.indices.contains(row),let index=Int(tableColumn?.identifier.rawValue ?? "") else {return nil}
    let column=columns[row]
    let text=NSTextField(labelWithString: [String(column.ordinal),column.name,column.type][index])
    text.font = .monospacedSystemFont(ofSize: 11,weight: .regular)
    text.textColor = index == 0 ? StudioTheme.muted : StudioTheme.text
    text.alignment = index == 0 ? .right : .left
    return text
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking {removeTrackingArea(tracking)}
    tracking = NSTrackingArea(rect: .zero,options: [.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner: self)
    if let tracking {addTrackingArea(tracking)}
  }
  override func mouseExited(with event: NSEvent) {StudioHoverHelp.shared.leaveTablePreview()}
}
