import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class ResultRowGutter: NSView {
  static func width(maxRow:Int,editing:Bool,newRows:Bool) -> CGFloat {
    let font=NSFont.monospacedDigitSystemFont(ofSize:11,weight:.semibold)
    let label=(editing ? "✎ ":"")+String(max(1,maxRow))
    let textWidth=(label as NSString).size(withAttributes:[.font:font]).width
    let newWidth=newRows ? ("+ Yeni" as NSString).size(withAttributes:[.font:font]).width:0
    return max(36,ceil(max(textWidth,newWidth))+12)
  }
  weak var table: CopyTable?
  var label: ((Int) -> (String, NSColor))?
  override var isFlipped: Bool { true }
  override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
  func connect(_ table:CopyTable) {
    self.table=table; table.rowGutter=self
    clipsToBounds=true
    setAccessibilityIdentifier("resultsRowNumbers")
    setAccessibilityElement(true); setAccessibilityRole(.group)
    setAccessibilityLabel("Sabit satır numaraları")
    toolTip="Satır numarası · Tıklayarak satırı, Shift ile aralığı seçin."
    for (name,object) in [(NSView.boundsDidChangeNotification,table.enclosingScrollView?.contentView as Any?), (NSTableView.selectionDidChangeNotification,table), (StudioTheme.changed,nil)] {
      NotificationCenter.default.addObserver(self,selector:#selector(redraw),name:name,object:object)
    }
    table.enclosingScrollView?.contentView.postsBoundsChangedNotifications=true
  }
  @objc private func redraw() { needsDisplay=true }
  var viewport:NSRect {
    guard let clip=table?.enclosingScrollView?.contentView else { return .zero }
    let rect=convert(clip.bounds,from:clip)
    let headerBottom=table?.headerView.map {convert($0.bounds,from:$0).maxY} ?? rect.minY
    let top=max(0,rect.minY,headerBottom)
    return NSRect(x:0,y:top,width:bounds.width,height:max(0,min(bounds.height,rect.maxY)-top))
  }
  func rowRect(_ row:Int) -> NSRect {
    guard let table else { return .zero }
    let rect=convert(table.rect(ofRow:row),from:table)
    return NSRect(x:0,y:rect.minY,width:bounds.width,height:rect.height)
  }
  var visibleRows:Range<Int> {
    guard let table else { return 0..<0 }
    let range=table.rows(in:table.enclosingScrollView?.documentVisibleRect ?? .zero)
    guard range.location != NSNotFound, range.length>0 else { return 0..<0 }
    return range.location..<min(table.numberOfRows,NSMaxRange(range))
  }
  private func rowAccessibility() -> [Any] {
    visibleRows.compactMap { row -> NSAccessibilityElement? in
      let rect=NSIntersectionRect(rowRect(row),viewport)
      guard !rect.isEmpty else { return nil }
      let screen=window?.convertToScreen(convert(rect,to:nil)) ?? .zero
      let element=NSAccessibilityElement()
      element.setAccessibilityRole(.staticText); element.setAccessibilityFrame(screen)
      element.setAccessibilityLabel(label?(row).0 ?? ""); element.setAccessibilityParent(self)
      return element
    }
  }
  override func draw(_ dirtyRect:NSRect) {
    StudioTheme.panel.setFill(); bounds.fill()
    guard let table else { return }
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect:viewport).addClip()
    let paragraph=NSMutableParagraphStyle(); paragraph.alignment = .right; paragraph.lineBreakMode = .byTruncatingHead
    for row in visibleRows {
      let rect=rowRect(row)
      guard rect.intersects(dirtyRect) else { continue }
      (table.selectedRowIndexes.contains(row) ? StudioTheme.selection:row.isMultiple(of:2) ? StudioTheme.panel:StudioTheme.stripe).setFill()
      rect.fill()
      let (text,color)=label?(row) ?? (String(row+1),StudioTheme.muted)
      text.draw(in:NSRect(x:3,y:rect.midY-7,width:bounds.width-12,height:16),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:table.selectedRowIndexes.contains(row) ? .semibold:.regular),.foregroundColor:color,.paragraphStyle:paragraph])
      StudioTheme.border.setFill(); NSRect(x:0,y:rect.maxY,width:bounds.width,height:1).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    if let header=table.headerView {
      let rect=convert(header.bounds,from:header)
      StudioTheme.panel.setFill()
      NSRect(x:0,y:rect.minY,width:bounds.width,height:rect.height).fill()
      "#".draw(in:NSRect(x:8,y:rect.midY-7,width:bounds.width-18,height:16),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:11,weight:.semibold),.foregroundColor:StudioTheme.muted,.paragraphStyle:paragraph])
      StudioTheme.border.setFill(); NSRect(x:0,y:rect.maxY-1,width:bounds.width,height:1).fill()
    }
    StudioTheme.border.setFill(); NSRect(x:bounds.width-1,y:0,width:1,height:bounds.height).fill()
    setAccessibilityChildren(rowAccessibility())
  }
  private func row(at event:NSEvent) -> Int {
    guard let table else { return -1 }
    let local=convert(event.locationInWindow,from:nil)
    guard viewport.contains(local) else { return -1 }
    return table.row(at:NSPoint(x:table.enclosingScrollView?.documentVisibleRect.midX ?? 1,y:table.convert(event.locationInWindow,from:nil).y))
  }
  override func mouseDown(with event:NSEvent) {
    table?.selectGutterRow(row(at:event),extending:event.modifierFlags.contains(.shift))
  }
  override func mouseDragged(with event:NSEvent) {
    guard let table, let clip=table.enclosingScrollView?.contentView else { return }
    // Keep native autoscroll vertical even though this event originates left of the table.
    let point=table.convert(event.locationInWindow,from:nil)
    let location=table.convert(NSPoint(x:table.enclosingScrollView?.documentVisibleRect.midX ?? 1,y:point.y),to:nil)
    if let adjusted=NSEvent.mouseEvent(with:.leftMouseDragged,location:location,modifierFlags:event.modifierFlags,timestamp:event.timestamp,windowNumber:event.windowNumber,context:nil,eventNumber:event.eventNumber,clickCount:event.clickCount,pressure:event.pressure) { _ = table.autoscroll(with:adjusted) }
    let y=max(clip.bounds.minY,min(clip.bounds.maxY-1,table.convert(event.locationInWindow,from:nil).y))
    table.selectGutterRow(table.row(at:NSPoint(x:table.enclosingScrollView?.documentVisibleRect.midX ?? 1,y:y)),dragging:true)
  }
  override func rightMouseDown(with event:NSEvent) { table?.gutterContextMenu(with:event,row:row(at:event)) }
  override func scrollWheel(with event:NSEvent) { table?.enclosingScrollView?.scrollWheel(with:event) }
}
