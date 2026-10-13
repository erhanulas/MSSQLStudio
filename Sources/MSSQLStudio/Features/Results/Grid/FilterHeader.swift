import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class FilterHeaderCell: NSTableHeaderCell {
  var active = false
  var pinned = false
  var primaryKey = false
  var hovered = false
  var navigationTarget = false
  var typeSymbol = "textformat"
  var typeDetail = ""
  var showsFilter = true
  var ascending: Bool?
  private static var symbols: [String: NSImage] = [:]
  private static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
  private static let detailFont = NSFont.systemFont(ofSize: 9, weight: .regular)

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
    let textWidth = max(0, frame.width - (pinned ? 92 : 76))
    stringValue.draw(in: NSRect(x: frame.minX + 25, y: typeDetail.isEmpty ? frame.midY - 8 : frame.minY + 5, width: textWidth, height: 16),
      withAttributes: [.font: Self.titleFont, .foregroundColor: StudioTheme.text, .paragraphStyle: paragraph])
    if !typeDetail.isEmpty {
      typeDetail.draw(in: NSRect(x: frame.minX + 25, y: frame.minY + 22, width: textWidth, height: 13),
        withAttributes: [.font: Self.detailFont, .foregroundColor: StudioTheme.muted, .paragraphStyle: paragraph])
    }
    symbol(primaryKey ? "key.fill" : typeSymbol, accent: primaryKey)?.draw(in: NSRect(x: frame.minX + 7, y: frame.midY - 6, width: 12, height: 12))
    if pinned { symbol("pin.fill", accent: true)?.draw(in: NSRect(x: frame.maxX - 60, y: frame.midY - 5, width: 9, height: 10)) }
    if let ascending { symbol(ascending ? "chevron.up" : "chevron.down", accent: true)?.draw(in: NSRect(x: frame.maxX - 44, y: frame.midY - 4, width: 8, height: 8)) }
    if showsFilter {
      if hovered || active {
        StudioTheme.selection.setFill()
        NSBezierPath(roundedRect: NSRect(x: frame.maxX - 32, y: frame.midY - 11, width: 20, height: 22), xRadius: 5, yRadius: 5).fill()
      }
      symbol("line.3.horizontal.decrease", accent: active)?.draw(in: NSRect(x: frame.maxX - 28, y: frame.midY - 6, width: 12, height: 12))
    }
  }
  override func drawSortIndicator(withFrame cellFrame: NSRect, in controlView: NSView, ascending: Bool, priority: Int) {
    // The custom header paints one sort indicator beside the local filter.
  }
}
@MainActor enum GridColumnSizing {
  static func headerWidth(_ name: String, detail: String = "") -> CGFloat {
    let title = name.size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
    let type = detail.size(withAttributes: [.font: NSFont.systemFont(ofSize: 9)]).width
    return ceil(max(title, type)) + 80
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
  private func hover(_ column: Int) {
    guard hoveredColumn != column else { return }
    for position in [hoveredColumn, column] where tableView?.tableColumns.indices.contains(position) == true {
      (tableView?.tableColumns[position].headerCell as? FilterHeaderCell)?.hovered = position == column
      setNeedsDisplay(headerRect(ofColumn: position))
    }
    hoveredColumn = column
  }
  override func mouseMoved(with event: NSEvent) { hover(column(at: convert(event.locationInWindow, from: nil))) }
  override func mouseExited(with event: NSEvent) { hover(-1) }
  func filterHitRect(column: Int) -> NSRect {
    guard column >= 0, let tableView, tableView.tableColumns.indices.contains(column),
      (tableView.tableColumns[column].headerCell as? FilterHeaderCell)?.showsFilter == true else { return .zero }
    let rect = headerRect(ofColumn: column)
    return NSRect(x:rect.maxX-32,y:rect.minY+3,width:20,height:max(0,rect.height-6))
  }
  var openFilter: ((Int) -> Void)?
  var openMenu: ((Int, NSEvent) -> Void)?
  override func rightMouseDown(with event: NSEvent) {
    openMenu?(column(at: convert(event.locationInWindow, from: nil)), event)
  }
  override func mouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    let c = column(at: p)
    if c >= 0 && filterHitRect(column:c).contains(p) {
      // The outer 12 pt belong exclusively to native column resizing.
      var dragged = false
      while let next = window?.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
        let location = convert(next.locationInWindow,from:nil)
        if hypot(location.x-p.x,location.y-p.y) > 3 { dragged = true }
        if next.type == .leftMouseUp {
          if !dragged && filterHitRect(column:c).contains(location) { openFilter?(c) }
          break
        }
      }
    } else {
      super.mouseDown(with: event)
    }
  }
}
