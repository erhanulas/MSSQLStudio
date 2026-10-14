import AppKit
import SwiftUI

/// The overlay only tracks hover; clicks, selection and keyboard stay with its host.
@MainActor private final class StudioHelpAnchorView:NSView {
  var text="" {didSet {if text != oldValue {StudioHoverHelp.shared.hide(for:self)}}}
  private var area:NSTrackingArea?
  override func hitTest(_ point:NSPoint)->NSView? {nil}
  override func updateTrackingAreas() {
    super.updateTrackingAreas();if let area {removeTrackingArea(area)}
    area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
    if let area {addTrackingArea(area)}
  }
  override func mouseEntered(with event:NSEvent) {if !text.isEmpty {StudioHoverHelp.shared.schedule(for:self,title:text)}}
  override func mouseExited(with event:NSEvent) {StudioHoverHelp.shared.hide(for:self)}
  override func viewWillMove(toWindow newWindow:NSWindow?) {StudioHoverHelp.shared.hide(for:self);super.viewWillMove(toWindow:newWindow)}
}
private struct StudioHelpAnchor:NSViewRepresentable {
  let text:String
  func makeNSView(context:Context)->StudioHelpAnchorView {let view=StudioHelpAnchorView();view.setAccessibilityElement(false);return view}
  func updateNSView(_ view:StudioHelpAnchorView,context:Context) {view.text=text}
}
extension View {
  func studioHelp(_ text:String)->some View {
    accessibilityHint(text).overlay(StudioHelpAnchor(text:text).allowsHitTesting(false).accessibilityHidden(true))
  }
}
