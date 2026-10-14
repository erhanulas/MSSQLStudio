import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor class DocumentButton: StudioFullAreaButton, NSDraggingSource {
  var document: QueryDocument?
  var showMenu: ((NSEvent) -> Void)?
  var draggable = false
  weak var selectionSurface: NSView?
  var trackingEventFixture: (() -> NSEvent?)?
  private func nextTrackingEvent(in window:NSWindow)->NSEvent? {
    if let trackingEventFixture {return trackingEventFixture()}
    return window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp])
  }
  func acceptsRelease(at point: NSPoint) -> Bool {
    let surface = selectionSurface ?? self
    return surface.bounds.contains(surface.convert(point, from: nil))
  }
  override func rightMouseDown(with event: NSEvent) { showMenu?(event) }
  override func mouseDown(with event: NSEvent) {
    guard draggable, let document, let window else { super.mouseDown(with: event); return }
    let origin = event.locationInWindow
    highlight(true)
    while let next = nextTrackingEvent(in:window) {
      if next.type == .leftMouseUp { highlight(false); if acceptsRelease(at: next.locationInWindow),let action { _ = sendAction(action,to: target) }; return }
      if hypot(next.locationInWindow.x-origin.x,next.locationInWindow.y-origin.y) > 4 {
        highlight(false)
        let item = NSPasteboardItem(); item.setString(document.id.uuidString,forType: QueryTabStrip.type)
        let drag = NSDraggingItem(pasteboardWriter: item)
        let image = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) { cacheDisplay(in: bounds,to: rep); image.addRepresentation(rep) }
        drag.setDraggingFrame(bounds,contents: image)
        beginDraggingSession(with: [drag],event: next,source: self)
        return
      }
    }
    highlight(false)
  }
  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
}
@MainActor final class QueryTabCloseButton:DocumentButton {
  private var tracking:NSTrackingArea?
  private(set) var hovered=false
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking {removeTrackingArea(tracking)}
    let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
    addTrackingArea(area);tracking=area
  }
  override func mouseEntered(with event:NSEvent) {hovered=true;refreshStyle()}
  override func mouseExited(with event:NSEvent) {hovered=false;refreshStyle()}
  func refreshStyle() {contentTintColor=hovered ? StudioTheme.danger:StudioTheme.muted;needsDisplay=true}
  override func draw(_ dirtyRect:NSRect) {
    if hovered || isHighlighted {
      StudioTheme.danger.withAlphaComponent(isHighlighted ? 0.22:0.12).setFill()
      NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:6,yRadius:6).fill()
    }
    super.draw(dirtyRect)
  }
}
@MainActor final class QueryTabSurface: NSStackView {
  weak var primaryButton: DocumentButton?
  private let activeIndicator = CALayer()
  var sourceColor:NSColor?
  private var hoverArea: NSTrackingArea?
  private var hovered = false
  private(set) var isActiveTab = false
  func configure(active: Bool) {
    isActiveTab = active
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.masksToBounds = true
    layer?.borderWidth = 0
    if activeIndicator.superlayer == nil { layer?.addSublayer(activeIndicator) }
    activeIndicator.backgroundColor = (sourceColor ?? StudioTheme.accent).withAlphaComponent(0.9).cgColor
    activeIndicator.cornerRadius = 1
    activeIndicator.isHidden = !active
    setAccessibilitySelected(active)
    refreshSurface()
    needsLayout = true
  }
  private func refreshSurface() {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    let selected = sourceColor.map {StudioTheme.canvas.blended(withFraction:StudioTheme.dark ? 0.18:0.08,of:$0) ?? StudioTheme.selection} ?? (StudioTheme.selection.blended(withFraction:0.55,of:StudioTheme.canvas) ?? StudioTheme.selection)
    layer?.backgroundColor = (isActiveTab ? selected : hovered ? StudioTheme.panel : .clear).cgColor
    CATransaction.commit()
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area); hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; refreshSurface() }
  override func mouseExited(with event: NSEvent) { hovered = false; refreshSurface() }
  override func layout() {
    super.layout()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    activeIndicator.frame = NSRect(x: 10, y: isFlipped ? max(0, bounds.height-2) : 0, width: max(0, bounds.width-20), height: 2)
    CATransaction.commit()
  }
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let hit = super.hitTest(point) else { return nil }
    if hit is QueryTabCloseButton { return hit }
    primaryButton?.selectionSurface = self
    return primaryButton ?? hit
  }
  // Padding and the document icon belong to the same draggable/selectable tab.
  override func mouseDown(with event: NSEvent) { primaryButton?.mouseDown(with: event) }
  override func rightMouseDown(with event: NSEvent) { primaryButton?.rightMouseDown(with: event) }
}
@MainActor final class QueryTabStrip: NSStackView {
  static let type = NSPasteboard.PasteboardType("local.mssqlstudio.queryTab")
  var documentIDs: [UUID] = []
  var reorder: ((UUID,Int) -> Void)?
  private let indicator = NSView()
  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([Self.type])
    indicator.wantsLayer = true; indicator.isHidden = true
    addSubview(indicator)
  }
  required init?(coder: NSCoder) { fatalError() }
  private func location(_ sender: NSDraggingInfo) -> Int {
    let point = convert(sender.draggingLocation,from: nil)
    for (index,view) in arrangedSubviews.prefix(documentIDs.count).enumerated() where point.x < view.frame.midX { return index }
    return documentIDs.count
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard let raw = sender.draggingPasteboard.string(forType: Self.type), let id = UUID(uuidString: raw), documentIDs.contains(id), sender.draggingSource is DocumentButton else { return [] }
    let index = location(sender)
    let x = index < documentIDs.count ? arrangedSubviews[index].frame.minX : arrangedSubviews.prefix(documentIDs.count).last?.frame.maxX ?? 0
    indicator.frame = NSRect(x:x,y:2,width:2,height:max(0,bounds.height-4))
    indicator.layer?.backgroundColor = StudioTheme.accent.cgColor; indicator.isHidden = false
    return .move
  }
  override func draggingExited(_ sender: NSDraggingInfo?) { indicator.isHidden = true }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    indicator.isHidden = true
    guard sender.draggingSource is DocumentButton, let raw = sender.draggingPasteboard.string(forType: Self.type), let id = UUID(uuidString: raw), documentIDs.contains(id) else { return false }
    reorder?(id,location(sender)); return true
  }
  override func draggingEnded(_ sender: NSDraggingInfo) { indicator.isHidden = true }
}
