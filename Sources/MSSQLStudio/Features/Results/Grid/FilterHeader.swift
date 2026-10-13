import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class FilterHeaderCell: NSTableHeaderCell {
  var active = false
  var pinned = false
  var navigationTarget = false
  var typeSymbol = "textformat"
  var typeDetail = ""
  var showsFilter = true
  var ascending: Bool?
  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    (navigationTarget ? StudioTheme.selection:StudioTheme.panel).setFill()
    NSBezierPath(rect: cellFrame).fill()
    if navigationTarget {
      StudioTheme.accent.setFill()
      NSBezierPath(rect:NSRect(x:cellFrame.minX,y:cellFrame.maxY-3,width:cellFrame.width,height:3)).fill()
    }
    StudioTheme.border.setFill()
    NSBezierPath(rect: NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY, width: 1, height: cellFrame.height)).fill()
    NSBezierPath(rect: NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1)).fill()
    drawInterior(withFrame: cellFrame, in: controlView)
  }
  override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
    guard !stringValue.isEmpty else { return }
    let label = NSMutableParagraphStyle()
    label.lineBreakMode = .byTruncatingTail
    let font = NSFont.systemFont(ofSize: 11, weight: navigationTarget ? .semibold:.medium)
    stringValue.draw(
      in: NSRect(
        x: cellFrame.minX + 24, y: typeDetail.isEmpty ? cellFrame.midY - font.pointSize / 2 - 2 : cellFrame.minY + 4,
        width: max(0, cellFrame.width - (pinned ? 92:76)), height: font.pointSize + 5),
      withAttributes: [.font: font, .foregroundColor: StudioTheme.text, .paragraphStyle: label])
    if !typeDetail.isEmpty {
      typeDetail.draw(in:NSRect(x:cellFrame.minX+24,y:cellFrame.minY+21,width:max(0,cellFrame.width-(pinned ? 92:76)),height:13),withAttributes:[.font:NSFont.systemFont(ofSize:9),.foregroundColor:StudioTheme.muted,.paragraphStyle:label])
    }
    if let type = NSImage(systemSymbolName: typeSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [StudioTheme.accent])) {
      StudioTheme.accent.set()
      type.draw(in: NSRect(x: cellFrame.minX + 6, y: cellFrame.midY - 6, width: 12, height: 12))
    }
    if pinned, let pin=NSImage(systemSymbolName:"pin.fill",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[StudioTheme.accent])) {
      pin.draw(in:NSRect(x:cellFrame.maxX-60,y:cellFrame.midY-5,width:9,height:10))
    }
    if let ascending, let sort = NSImage(systemSymbolName: ascending ? "chevron.up" : "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [StudioTheme.accent])) {
      sort.draw(in: NSRect(x: cellFrame.maxX - 44, y: cellFrame.midY - 4, width: 8, height: 8))
    }
    if showsFilter, let filter = NSImage(systemSymbolName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [active ? StudioTheme.accent : StudioTheme.muted])) {
      filter.draw(in: NSRect(x: cellFrame.maxX - 28, y: cellFrame.midY - 6, width: 12, height: 12))
    }

  }
  override func drawSortIndicator(
    withFrame cellFrame: NSRect, in controlView: NSView, ascending: Bool, priority: Int
  ) {
    super.drawSortIndicator(
      withFrame: cellFrame.offsetBy(dx: -19, dy: 0), in: controlView, ascending: ascending,
      priority: priority)
  }
}
@MainActor enum GridColumnSizing {
  static func headerWidth(_ name: String) -> CGFloat {
    ceil(name.size(withAttributes: [.font: NSFont.systemFont(ofSize:11,weight:.medium)]).width) + 80
  }
}
@MainActor final class FilterHeader: NSTableHeaderView {
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
