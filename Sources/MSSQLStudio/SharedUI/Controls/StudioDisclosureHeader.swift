import AppKit
import SwiftUI

/// The whole heading is one native button; content below keeps its own controls.
struct StudioDisclosureHeader:NSViewRepresentable {
  let title:String
  let icon:String
  let tint:NSColor
  let expanded:Bool
  let toggle:()->Void
  func makeNSView(context:Context)->StudioDisclosureButton {StudioDisclosureButton(frame:.zero)}
  func updateNSView(_ button:StudioDisclosureButton,context:Context) {
    button.title=title;button.symbol=icon;button.tint=tint;button.expanded=expanded;button.toggle=toggle
    button.setAccessibilityIdentifier("disclosure_"+title)
    button.setAccessibilityLabel(title)
    button.setAccessibilityValue(expanded ? "Açık":"Kapalı")
    button.toolTip=title+(expanded ? " · Daralt":" · Genişlet")
    button.needsDisplay=true
  }
}
@MainActor final class StudioDisclosureButton:StudioFullAreaButton {
  var symbol=""
  var tint=NSColor.controlAccentColor
  var expanded=false
  var toggle:(()->Void)?
  private(set) var hovered=false
  private var hoverArea:NSTrackingArea?
  override init(frame:NSRect) {
    super.init(frame:frame)
    isBordered=false;setButtonType(.momentaryPushIn);target=self;action=#selector(activate)
    focusRingType = .exterior
  }
  required init?(coder:NSCoder) {fatalError()}
  @objc private func activate() {toggle?()}
  override func updateTrackingAreas() {
    if let hoverArea {removeTrackingArea(hoverArea)}
    let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self)
    addTrackingArea(area);hoverArea=area;super.updateTrackingAreas()
  }
  override func mouseEntered(with event:NSEvent) {hovered=true;needsDisplay=true}
  override func mouseExited(with event:NSEvent) {hovered=false;needsDisplay=true}
  override func highlight(_ flag:Bool) {super.highlight(flag);needsDisplay=true}
  override func draw(_ dirtyRect:NSRect) {
    if hovered || isHighlighted {
      StudioTheme.accent.withAlphaComponent(isHighlighted ? 0.14:0.07).setFill()
      NSBezierPath(roundedRect:bounds,xRadius:6,yRadius:6).fill()
    }
    let config=NSImage.SymbolConfiguration(pointSize:12,weight:.semibold)
    for (name,x,color) in [(symbol,CGFloat(8),tint),(expanded ? "chevron.down":"chevron.right",bounds.maxX-24,StudioTheme.muted)] {
      if let image=NSImage(systemSymbolName:name,accessibilityDescription:nil)?.withSymbolConfiguration(config)?.withSymbolConfiguration(.init(paletteColors:[color])) {
        StudioSymbolDrawing.draw(image,in:NSRect(x:x,y:(bounds.height-16)/2,width:16,height:16))
      }
    }
    let text=NSAttributedString(string:title,attributes:[.font:NSFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:StudioTheme.text])
    text.draw(in:NSRect(x:32,y:(bounds.height-text.size().height)/2,width:max(0,bounds.width-64),height:text.size().height))
  }
}
