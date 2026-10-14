import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor final class StudioToolbarPopUpButton: NSPopUpButton {
  private var hoverArea: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area); hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) { StudioHoverHelp.shared.schedule(for: self) }
  override func mouseExited(with event: NSEvent) { StudioHoverHelp.shared.hide(for: self) }
  override func mouseDown(with event: NSEvent) { StudioHoverHelp.shared.hide(); super.mouseDown(with: event) }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    StudioHoverHelp.shared.hide(for: self); super.viewWillMove(toWindow: newWindow)
  }
}

/// Native tabs retain keyboard, target/action and accessibility behavior.
@MainActor final class StudioResultTabButton: StudioFullAreaButton {
  private var hoverArea: NSTrackingArea?
  var source: SQLResultSource? {
    didSet {
      guard source != oldValue else { return }
      StudioHoverHelp.shared.hide(for: self)
      toolTip = source?.help
      setAccessibilityHelp(source?.help)
    }
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area); hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) {
    if let source { StudioHoverHelp.shared.schedule(for: self, sqlSource: source) }
  }
  override func mouseExited(with event: NSEvent) { StudioHoverHelp.shared.hide(for: self) }
  override func mouseDown(with event: NSEvent) { StudioHoverHelp.shared.hide(); super.mouseDown(with: event) }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    StudioHoverHelp.shared.hide(for: self); super.viewWillMove(toWindow: newWindow)
  }
  override var state: NSControl.StateValue { didSet { refreshStyle() } }
  override var intrinsicContentSize: NSSize {
    let size = super.intrinsicContentSize
    return NSSize(width: size.width + 18, height: 26)
  }
  func refreshStyle() {
    wantsLayer = true; layer?.cornerRadius = 5
    layer?.backgroundColor = (state == .on ? StudioTheme.selection : .clear).cgColor
    contentTintColor = state == .on ? StudioTheme.accent : StudioTheme.muted
    font = .systemFont(ofSize: 11, weight: state == .on ? .semibold : .regular)
  }
}

/// Borderless buttons must track their padded surface, including empty corners.
@MainActor class StudioFullAreaButtonCell: NSButtonCell {
  override func hitTest(for event:NSEvent,in cellFrame:NSRect,of controlView:NSView)->NSCell.HitResult {
    guard isEnabled,cellFrame.contains(controlView.convert(event.locationInWindow,from:nil)) else {return []}
    return [.contentArea,.trackableArea]
  }
}
@MainActor class StudioFullAreaButton: NSButton {
  override var alignmentRectInsets:NSEdgeInsets {.init(top:0,left:0,bottom:0,right:0)}
  override init(frame:NSRect) {super.init(frame:frame);cell=StudioFullAreaButtonCell()}
  required init?(coder:NSCoder) {super.init(coder:coder)}
}
@MainActor final class StudioToolbarButtonCell: StudioFullAreaButtonCell {
  func contentFrame(_ bounds:NSRect) -> NSRect {
    bounds.insetBy(dx:title.isEmpty ? 4:10,dy:3)
  }
  override func drawInterior(withFrame cellFrame:NSRect,in controlView:NSView) {
    super.drawInterior(withFrame:contentFrame(cellFrame),in:controlView)
  }
}

@MainActor final class StudioToolbarButton: NSButton {
  enum Tone { case neutral, accent, success, warning, danger }
  var tone: Tone { didSet { refreshStyle() } }
  var prominent: Bool { didSet { refreshStyle() } }
  var tracksActiveState = false
  private var hovered = false
  private var pressed = false
  private var hoverArea: NSTrackingArea?
  override var isEnabled: Bool { didSet { refreshStyle() } }
  override var state: NSControl.StateValue { didSet { refreshStyle() } }

  init(symbol: String, label: String, tone: Tone = .accent, title: String = "", width: CGFloat = 28, prominent: Bool = false) {
    self.tone = tone; self.prominent = prominent
    super.init(frame: .zero)
    cell = StudioToolbarButtonCell()
    setButtonType(.momentaryPushIn)
    focusRingType = .none
    self.title = title
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    bezelStyle = .rounded; isBordered = false; controlSize = .small
    font = .systemFont(ofSize: 11, weight: .semibold)
    setAccessibilityLabel(label); toolTip = label
    wantsLayer = true; layer?.cornerRadius = 7; layer?.borderWidth = 1
    widthAnchor.constraint(equalToConstant: width).isActive = true
    heightAnchor.constraint(equalToConstant: 26).isActive = true
    setContentCompressionResistancePriority(.required, for: .horizontal)
    refreshStyle()
  }
  required init?(coder: NSCoder) { fatalError() }
  func refreshStyle() {
    let color: NSColor
    switch tone {
    case .neutral: color = StudioTheme.muted
    case .accent: color = StudioTheme.accent
    case .success: color = StudioTheme.success
    case .warning: color = StudioTheme.warning
    case .danger: color = StudioTheme.danger
    }
    let active = prominent || tracksActiveState && state == .on
    contentTintColor = isEnabled ? prominent ? (StudioTheme.dark ? StudioTheme.canvas : .white) : color : StudioTheme.muted.withAlphaComponent(0.4)
    layer?.backgroundColor = (isEnabled
      ? color.withAlphaComponent(prominent ? pressed ? 0.80 : hovered ? 0.92 : 1 : pressed ? 0.20 : hovered ? 0.12 : active ? 0.12 : 0.035)
      : StudioTheme.muted.withAlphaComponent(0.015)).cgColor
    layer?.borderColor = (isEnabled ? color.withAlphaComponent(active || hovered ? 0.28 : 0) : NSColor.clear).cgColor
  }
  override func sendAction(_ action:Selector?, to target:Any?) -> Bool {
    // Native momentary cells may leave their last state behind. Only controls
    // representing a model mode (editing, favorites, refresh) retain that state.
    if !tracksActiveState {state = .off}
    defer {if !tracksActiveState {state = .off}}
    return super.sendAction(action,to:target)
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area); hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; refreshStyle(); StudioHoverHelp.shared.schedule(for: self,title:toolTip) }
  override func mouseExited(with event: NSEvent) { hovered = false; refreshStyle(); StudioHoverHelp.shared.hide(for: self) }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    StudioHoverHelp.shared.hide(for: self); super.viewWillMove(toWindow: newWindow)
  }
  override func mouseDown(with event: NSEvent) {
    StudioHoverHelp.shared.hide()
    pressed = true; refreshStyle()
    defer { pressed = false; refreshStyle() }
    super.mouseDown(with: event)
  }
}
