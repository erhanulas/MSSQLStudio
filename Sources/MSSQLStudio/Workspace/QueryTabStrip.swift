import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor private final class QueryTabClipView:NSClipView {
  override func constrainBoundsRect(_ proposedBounds:NSRect)->NSRect {
    var rect=super.constrainBoundsRect(proposedBounds)
    rect.origin.y=0
    rect.origin.x=max(0,min(rect.origin.x,max(0,(documentView?.frame.width ?? 0)-rect.width)))
    return rect
  }
}

@MainActor final class QueryTabScrollView:NSScrollView {
  override init(frame:NSRect) {
    super.init(frame:frame)
    contentView=QueryTabClipView()
    contentView.drawsBackground=false;drawsBackground=true
    refreshBackground()
    hasHorizontalScroller=false;scrollerStyle = .overlay
    horizontalScroller?.controlSize = .small;autohidesScrollers=true
    horizontalScrollElasticity = .none;verticalScrollElasticity = .none
  }
  required init?(coder:NSCoder) {fatalError()}
  private func refreshBackground() {
    effectiveAppearance.performAsCurrentDrawingAppearance {backgroundColor = .windowBackgroundColor}
  }
  override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();refreshBackground()}
  override func layout() {
    super.layout()
    guard let tabs=documentView as? QueryTabStrip else {return}
    let width=tabs.arrangedSubviews.reduce(tabs.edgeInsets.left+tabs.edgeInsets.right) {$0+$1.fittingSize.width}+CGFloat(max(0,tabs.arrangedSubviews.count-1))*tabs.spacing
    let size=NSSize(width:max(contentView.bounds.width,width),height:contentView.bounds.height)
    if tabs.frame != NSRect(origin:.zero,size:size) {tabs.frame=NSRect(origin:.zero,size:size)}
    tabs.layoutSubtreeIfNeeded()
    let bounds=contentView.constrainBoundsRect(contentView.bounds)
    if contentView.bounds.origin != bounds.origin {contentView.scroll(to:bounds.origin);reflectScrolledClipView(contentView)}
  }
  func revealActiveTab() {
    needsLayout=true;layoutSubtreeIfNeeded()
    if let tabs=documentView as? QueryTabStrip,let active=tabs.arrangedSubviews.compactMap({$0 as? QueryTabSurface}).first(where:{$0.isActiveTab}) {
      active.scrollToVisible(active.bounds)
    }
  }
}

@MainActor class DocumentButton: StudioFullAreaButton, NSDraggingSource {
  var document: QueryDocument?
  var showMenu: ((NSEvent) -> Void)?
  var draggable = false
  weak var selectionSurface: NSView?
  var trackingEventFixture: (() -> NSEvent?)?
  private weak var draggedSurface:NSView?
  private weak var draggedStrip:QueryTabStrip?
  func dragPreview()->(frame:NSRect,image:NSImage) {
    let surface=selectionSurface ?? self
    surface.layoutSubtreeIfNeeded()
    let image=NSImage(size:surface.bounds.size)
    if let rep=surface.bitmapImageRepForCachingDisplay(in:surface.bounds) {
      surface.cacheDisplay(in:surface.bounds,to:rep);image.addRepresentation(rep)
    }
    return (convert(surface.bounds,from:surface),image)
  }
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
        let preview=dragPreview()
        drag.setDraggingFrame(preview.frame,contents:preview.image)
        let surface=selectionSurface ?? self
        draggedSurface=surface;draggedStrip=surface.superview as? QueryTabStrip
        if let strip=draggedStrip,let index=strip.documentIDs.firstIndex(of:document.id) {
          strip.showDragPreview(id:document.id,insertionIndex:index,animated:false)
        } else {surface.alphaValue=0}
        let session=beginDraggingSession(with:[drag],event:next,source:self)
        session.animatesToStartingPositionsOnCancelOrFail=true
        session.draggingFormation = .none
        return
      }
    }
    highlight(false)
  }
  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
  func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) {
    draggedStrip?.resetDragPreview(animated:false)
    draggedSurface?.alphaValue=1;draggedSurface=nil;draggedStrip=nil
  }
}
@MainActor final class QueryTabCloseButton:DocumentButton {
  private var tracking:NSTrackingArea?
  private(set) var hovered=false
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking {removeTrackingArea(tracking)}
    let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
    addTrackingArea(area);tracking=area
    synchronizeHover()
  }
  @objc private func windowFocusChanged(_ notification:Notification) {
    if notification.name == NSWindow.didResignKeyNotification {clearHover()}
    else {synchronizeHover()}
  }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    for name in [NSWindow.didResignKeyNotification,NSWindow.didBecomeKeyNotification] {
      NotificationCenter.default.removeObserver(self,name:name,object:nil)
      if let window {NotificationCenter.default.addObserver(self,selector:#selector(windowFocusChanged(_:)),name:name,object:window)}
    }
    clearHover()
  }
  private func clearHover() {
    hovered=false;highlight(false);refreshStyle()
  }
  private func synchronizeHover() {
    let inside:Bool
    if let window,window.isVisible,window.isKeyWindow,!isHiddenOrHasHiddenAncestor {
      let point=convert(window.mouseLocationOutsideOfEventStream,from:nil)
      inside=bounds.contains(point) && visibleRect.contains(point)
    } else {inside=false}
    if !inside,isHighlighted {highlight(false)}
    if hovered != inside {hovered=inside;refreshStyle()}
  }
  override func layout() {super.layout();synchronizeHover()}
  override func mouseDown(with event:NSEvent) {
    defer {synchronizeHover()}
    super.mouseDown(with:event)
  }
  override func mouseEntered(with event:NSEvent) {hovered=true;refreshStyle()}
  override func mouseExited(with event:NSEvent) {hovered=false;refreshStyle()}
  func refreshStyle() {
    effectiveAppearance.performAsCurrentDrawingAppearance {contentTintColor=hovered ? StudioTheme.danger:.labelColor}
    needsDisplay=true
  }
  override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();refreshStyle()}
  override func draw(_ dirtyRect:NSRect) {
    synchronizeHover()
    if hovered || isHighlighted {
      StudioTheme.danger.withAlphaComponent(isHighlighted ? 0.22:0.12).setFill()
      NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:6,yRadius:6).fill()
    }
    super.draw(dirtyRect)
  }
}
@MainActor final class QueryTabSurface: NSStackView {
  weak var primaryButton: DocumentButton?
  var sourceColor:NSColor?
  private var hoverArea: NSTrackingArea?
  private var hovered = false
  private(set) var isActiveTab = false
  func configure(active: Bool) {
    isActiveTab = active
    wantsLayer = true
    layer?.cornerRadius = 6
    layer?.masksToBounds = true
    layer?.borderWidth = active ? 1:0
    layer?.borderColor = StudioTheme.accent.withAlphaComponent(0.42).cgColor
    setAccessibilitySelected(active)
    refreshSurface()
    needsLayout = true
  }
  private func refreshSurface() {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    // Resolve semantic colors in this view's appearance, including accessibility contrast.
    // Opaque surfaces keep inactive tabs readable independently of window/titlebar materials.
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let selected = NSColor.selectedContentBackgroundColor.blended(withFraction:0.82,of:.controlBackgroundColor) ?? .controlBackgroundColor
      layer?.borderWidth = isActiveTab ? 1:0
      layer?.borderColor = NSColor.controlAccentColor.cgColor
      layer?.backgroundColor = (isActiveTab ? selected : hovered ? NSColor.controlBackgroundColor : NSColor.windowBackgroundColor).cgColor
      if let button=primaryButton {
        button.contentTintColor = .labelColor
        button.attributedTitle=NSAttributedString(string:button.title,attributes:[.font:button.font ?? StudioTheme.uiFont,.foregroundColor:NSColor.labelColor])
      }
    }
    CATransaction.commit()
  }
  override func viewDidMoveToWindow() {super.viewDidMoveToWindow();refreshSurface()}
  override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();refreshSurface()}
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area); hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; refreshSurface() }
  override func mouseExited(with event: NSEvent) { hovered = false; refreshSurface() }
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
    indicator.layer?.cornerRadius=6;indicator.layer?.borderWidth=1
    addSubview(indicator,positioned:.below,relativeTo:nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  func showDragPreview(id:UUID,insertionIndex:Int,animated:Bool=true) {
    let surfaces=arrangedSubviews.prefix(documentIDs.count).compactMap {$0 as? QueryTabSurface}
    guard let old=documentIDs.firstIndex(of:id),old<surfaces.count else {return}
    let pinned=surfaces.filter {$0.primaryButton?.document?.pinned == true}.count
    let isPinned=surfaces[old].primaryButton?.document?.pinned == true
    let raw=insertionIndex>old ? insertionIndex-1:insertionIndex
    let destination=min(isPinned ? max(0,pinned-1):surfaces.count-1,max(isPinned ? 0:pinned,raw))
    let source=surfaces[old],distance=source.frame.width+spacing
    for (index,view) in surfaces.enumerated() {
      let x:CGFloat = old<destination && index>old && index<=destination ? -distance:
        destination<old && index>=destination && index<old ? distance:0
      view.alphaValue=index==old ? 0:1
      translate(view,x:x,animated:animated)
    }
    let x=destination>old ? surfaces[destination].frame.maxX-source.frame.width:surfaces[destination].frame.minX
    indicator.frame=NSRect(x:x,y:source.frame.minY,width:source.frame.width,height:source.frame.height)
    indicator.layer?.backgroundColor=StudioTheme.selection.withAlphaComponent(0.45).cgColor
    indicator.layer?.borderColor=StudioTheme.accent.withAlphaComponent(0.3).cgColor
    indicator.isHidden=false
  }
  private func translate(_ view:NSView,x:CGFloat,animated:Bool) {
    view.wantsLayer=true
    guard let layer=view.layer else {return}
    let target=CATransform3DMakeTranslation(x,0,0)
    guard !CATransform3DEqualToTransform(layer.transform,target) else {return}
    let previous=layer.presentation()?.transform ?? layer.transform
    CATransaction.begin();CATransaction.setDisableActions(true);layer.transform=target;CATransaction.commit()
    if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      let animation=CABasicAnimation(keyPath:"transform")
      animation.fromValue=NSValue(caTransform3D:previous);animation.toValue=NSValue(caTransform3D:target)
      animation.duration=0.14;animation.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
      layer.add(animation,forKey:"queryTabReorder")
    } else {layer.removeAnimation(forKey:"queryTabReorder")}
  }
  func resetDragPreview(animated:Bool=false) {
    indicator.isHidden=true
    for view in arrangedSubviews.prefix(documentIDs.count) {view.alphaValue=1;translate(view,x:0,animated:animated)}
  }
  private func location(_ sender: NSDraggingInfo) -> Int {
    let point = convert(sender.draggingLocation,from: nil)
    for (index,view) in arrangedSubviews.prefix(documentIDs.count).enumerated() where point.x < view.frame.midX { return index }
    return documentIDs.count
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard let raw = sender.draggingPasteboard.string(forType: Self.type), let id = UUID(uuidString: raw), documentIDs.contains(id), sender.draggingSource is DocumentButton else {resetDragPreview();return []}
    if let event=NSApp.currentEvent {_ = autoscroll(with:event)}
    showDragPreview(id:id,insertionIndex:location(sender))
    return .move
  }
  override func draggingExited(_ sender: NSDraggingInfo?) { resetDragPreview(animated:true) }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    resetDragPreview()
    guard sender.draggingSource is DocumentButton, let raw = sender.draggingPasteboard.string(forType: Self.type), let id = UUID(uuidString: raw), documentIDs.contains(id) else { return false }
    reorder?(id,location(sender)); return true
  }
  override func draggingEnded(_ sender: NSDraggingInfo) { resetDragPreview() }
}
