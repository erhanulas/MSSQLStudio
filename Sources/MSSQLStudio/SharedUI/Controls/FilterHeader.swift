import AppKit
import SQLServerKit
import SwiftUI

@MainActor enum GridHeaderActionLayout {
  static func rect(in frame:NSRect,sort:Bool)->NSRect {
    let height=min(26,max(0,frame.height-4))
    return NSRect(x:frame.maxX-(sort ? 70:40),y:frame.midY-height/2,width:28,height:height)
  }
}
/// View-based tables do not support AppKit column selection painting.
@MainActor class StudioColumnSelectionTable:NSTableView {
  var headerSelectedColumns=IndexSet() {
    didSet {
      guard headerSelectedColumns != oldValue else {return}
      enumerateAvailableRowViews {view,_ in view.needsDisplay=true}
    }
  }
  override func selectRowIndexes(_ indexes:IndexSet,byExtendingSelection extend:Bool) {
    if !indexes.isEmpty {headerSelectedColumns=[]}
    super.selectRowIndexes(indexes,byExtendingSelection:extend)
  }
  override func mouseDown(with event:NSEvent) {
    headerSelectedColumns=[]
    super.mouseDown(with:event)
  }
}
@MainActor class StudioColumnSelectionRowView:NSTableRowView {
  weak var columnSelectionTable:StudioColumnSelectionTable?
  override func drawBackground(in dirtyRect:NSRect) {
    super.drawBackground(in:dirtyRect)
    guard !isSelected,let table=columnSelectionTable else {return}
    StudioTheme.selection.setFill()
    for column in table.headerSelectedColumns where table.tableColumns.indices.contains(column) && !table.tableColumns[column].isHidden {
      let columnRect=convert(table.rect(ofColumn:column),from:table)
      NSRect(x:columnRect.minX,y:bounds.minY,width:columnRect.width,height:bounds.height).intersection(dirtyRect).fill()
    }
  }
}
@MainActor final class FilterHeaderCell: NSTableHeaderCell {
  var active = false
  var pinned = false
  var primaryKey = false
  var hovered = false
  var sortHovered = false
  var navigationTarget = false
  var typeSymbol = "textformat"
  var typeDetail = ""
  var showsFilter = true
  var showsSortControl = false
  var ascending: Bool?
  private static var symbols: [String: NSImage] = [:]
  private static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
  private static let detailFont = NSFont.systemFont(ofSize: 9, weight: .regular)

  override func copy(with zone: NSZone? = nil) -> Any {
    // NSCell's shallow copy cannot retain Swift String storage in subclass ivars.
    // Construct a fresh cell so both headers own their metadata independently.
    let cell=FilterHeaderCell(textCell:stringValue)
    cell.active=active;cell.pinned=pinned;cell.primaryKey=primaryKey
    cell.hovered=hovered;cell.sortHovered=sortHovered;cell.navigationTarget=navigationTarget
    cell.typeSymbol=typeSymbol;cell.typeDetail=typeDetail
    cell.showsFilter=showsFilter;cell.showsSortControl=showsSortControl;cell.ascending=ascending
    cell.font=font;cell.alignment=alignment;cell.textColor=textColor
    cell.backgroundColor=backgroundColor;cell.backgroundStyle=backgroundStyle
    cell.isEnabled=isEnabled;cell.isHighlighted=isHighlighted
    cell.lineBreakMode=lineBreakMode;cell.wraps=wraps
    cell.usesSingleLineMode=usesSingleLineMode
    cell.attributedStringValue=attributedStringValue
    return cell
  }

  private func symbol(_ name: String, accent: Bool) -> NSImage? {
    let key = name + (accent ? "/accent" : "/muted") + (StudioTheme.dark ? "/dark" : "/light")
    if let image = Self.symbols[key] { return image }
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [accent ? StudioTheme.accent : StudioTheme.muted]))
    Self.symbols[key] = image
    return image
  }
  override func draw(withFrame frame: NSRect, in controlView: NSView) {
    (navigationTarget ? StudioTheme.selection : active ? StudioTheme.resultFilteredHeader : StudioTheme.resultHeader).setFill()
    frame.fill()
    StudioTheme.resultBorder.setFill()
    NSRect(x: frame.maxX - 1, y: frame.minY + 7, width: 1, height: max(0, frame.height - 14)).fill()
    NSRect(x: frame.minX, y: frame.maxY - 1, width: frame.width, height: 1).fill()
    if navigationTarget || active {
      StudioTheme.accent.withAlphaComponent(navigationTarget ? 1 : 0.65).setFill()
      NSRect(x: frame.minX, y: frame.maxY - 2, width: frame.width, height: 2).fill()
    }
    drawInterior(withFrame: frame, in: controlView)
  }
  override func drawInterior(withFrame frame: NSRect, in controlView: NSView) {
    guard !stringValue.isEmpty else { return }
    let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
    let textWidth = max(0, frame.width - (pinned ? 128 : 112))
    stringValue.draw(in: NSRect(x: frame.minX + 25, y: typeDetail.isEmpty ? frame.midY - 8 : frame.minY + 5, width: textWidth, height: 16),
      withAttributes: [.font: Self.titleFont, .foregroundColor: StudioTheme.text, .paragraphStyle: paragraph])
    if !typeDetail.isEmpty {
      typeDetail.draw(in: NSRect(x: frame.minX + 25, y: frame.minY + 22, width: textWidth, height: 13),
        withAttributes: [.font: Self.detailFont, .foregroundColor: StudioTheme.muted, .paragraphStyle: paragraph])
    }
    symbol(primaryKey ? "key.fill" : typeSymbol, accent: primaryKey)?.draw(in: NSRect(x: frame.minX + 7, y: frame.midY - 6, width: 12, height: 12))
    if pinned { symbol("pin.fill", accent: true)?.draw(in: NSRect(x: frame.maxX - 84, y: frame.midY - 5, width: 9, height: 10)) }
    if showsSortControl || ascending != nil {
      let rect=GridHeaderActionLayout.rect(in:frame,sort:true)
      drawActionSurface(rect,highlighted:sortHovered,active:ascending != nil)
      let name=ascending.map {$0 ? "arrow.up":"arrow.down"} ?? "arrow.up.arrow.down"
      symbol(name,accent:ascending != nil)?.draw(in:NSRect(x:rect.midX-6,y:rect.midY-6,width:12,height:12))
    }
    if showsFilter {
      let rect=GridHeaderActionLayout.rect(in:frame,sort:false)
      drawActionSurface(rect,highlighted:hovered,active:active)
      symbol("line.3.horizontal.decrease.circle",accent:active)?.draw(in:NSRect(x:rect.midX-7,y:rect.midY-7,width:14,height:14))
    }
  }
  private func drawActionSurface(_ rect:NSRect,highlighted:Bool,active:Bool) {
    let path=NSBezierPath(roundedRect:rect,xRadius:StudioMetrics.controlRadius,yRadius:StudioMetrics.controlRadius)
    (highlighted || active ? StudioTheme.selection:StudioTheme.resultHeader).setFill();path.fill()
    (active ? StudioTheme.accent.withAlphaComponent(0.4):StudioTheme.resultBorder).setStroke()
    path.lineWidth=1;path.stroke()
  }
  override func drawSortIndicator(withFrame cellFrame: NSRect, in controlView: NSView, ascending: Bool, priority: Int) {
    // The custom header paints one sort indicator beside the local filter.
  }
}
@MainActor enum GridColumnSizing {
  static func headerWidth(_ name: String, detail: String = "") -> CGFloat {
    let title = name.size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
    let type = detail.size(withAttributes: [.font: NSFont.systemFont(ofSize: 9)]).width
    return ceil(max(title, type)) + 116
  }
}
@MainActor final class FilterHeader: NSTableHeaderView {
  private var tracking: NSTrackingArea?
  private var hoveredColumn = -1
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area); tracking = area
  }
  private func hover(_ point:NSPoint?) {
    let column=point.map {self.column(at:$0)} ?? -1
    for position in Set([hoveredColumn,column]) where tableView?.tableColumns.indices.contains(position)==true {
      guard let cell=tableView?.tableColumns[position].headerCell as? FilterHeaderCell else {continue}
      let filter=position==column && point.map {filterHitRect(column:position).contains($0)} == true
      let sort=position==column && point.map {sortHitRect(column:position).contains($0)} == true
      if cell.hovered != filter || cell.sortHovered != sort {
        cell.hovered=filter;cell.sortHovered=sort;setNeedsDisplay(headerRect(ofColumn:position))
      }
    }
    hoveredColumn=column
  }
  override func mouseMoved(with event:NSEvent) {hover(convert(event.locationInWindow,from:nil))}
  override func mouseExited(with event:NSEvent) {hover(nil)}
  func filterHitRect(column: Int) -> NSRect {
    guard column >= 0, let tableView, tableView.tableColumns.indices.contains(column),
      (tableView.tableColumns[column].headerCell as? FilterHeaderCell)?.showsFilter == true else { return .zero }
    let rect = headerRect(ofColumn: column)
    return GridHeaderActionLayout.rect(in:rect,sort:false)
  }
  var openFilter: ((Int) -> Void)?
  var openMenu: ((Int, NSEvent) -> Void)?
  override func rightMouseDown(with event: NSEvent) {
    openMenu?(column(at: convert(event.locationInWindow, from: nil)), event)
  }
  func sortHitRect(column:Int)->NSRect {
    guard let tableView,tableView.tableColumns.indices.contains(column),
      (tableView.tableColumns[column].headerCell as? FilterHeaderCell)?.showsSortControl == true else {return .zero}
    let rect=headerRect(ofColumn:column)
    return GridHeaderActionLayout.rect(in:rect,sort:true)
  }
  func enableColumnSelection(on table:StudioColumnSelectionTable) {
    selectColumn={ [weak table] column,modifiers in
      guard let table,table.tableColumns.indices.contains(column),
        table.window?.makeFirstResponder(table) != false else {return}
      let previous=table.headerSelectedColumns
      let columns:IndexSet
      if modifiers.contains(.shift),let anchor=previous.first {columns=IndexSet(integersIn:min(anchor,column)...max(anchor,column))}
      else if modifiers.contains(.command) {columns=previous.symmetricDifference(IndexSet(integer:column))}
      else {columns=IndexSet(integer:column)}
      // Column selection must not retain a row as a destructive action target.
      table.deselectAll(nil)
      table.headerSelectedColumns=columns
    }
  }
  var trackingEventFixture:(()->NSEvent?)?
  private func nextTrackingEvent()->NSEvent? {
    if let trackingEventFixture {return trackingEventFixture()}
    return window?.nextEvent(matching:[.leftMouseDragged,.leftMouseUp])
  }
  var selectColumn:((Int,NSEvent.ModifierFlags)->Void)?
  var sortColumn:((Int)->Void)?
  override func mouseDown(with event:NSEvent) {
    let point=convert(event.locationInWindow,from:nil),column=column(at:convert(event.locationInWindow,from:nil))
    guard column>=0 else {super.mouseDown(with:event);return}
    let filter=filterHitRect(column:column),sort=sortHitRect(column:column),rect=headerRect(ofColumn:column)
    let hitsFilter=filter.contains(point),hitsSort=sort.contains(point)
    // Native resizing keeps exclusive ownership of the divider edges.
    if !hitsFilter && !hitsSort && (selectColumn==nil || point.x>=rect.maxX-12 || point.x<rect.minX+4) {
      super.mouseDown(with:event);return
    }
    var dragged=false
    while let next=nextTrackingEvent() {
      let location=convert(next.locationInWindow,from:nil)
      if hypot(location.x-point.x,location.y-point.y)>3 {
        dragged=true
        if !hitsFilter && !hitsSort && next.type == .leftMouseDragged {
          // Let AppKit continue its native column-reordering gesture.
          NSApp.postEvent(next,atStart:true)
          super.mouseDown(with:event);return
        }
      }
      if next.type == .leftMouseUp {
        guard !dragged else {return}
        if hitsFilter && filter.contains(location) {openFilter?(column)}
        else if hitsSort && sort.contains(location) {sortColumn?(column)}
        else if !hitsFilter && !hitsSort && self.column(at:location)==column {selectColumn?(column,event.modifierFlags)}
        return
      }
    }
  }
}
