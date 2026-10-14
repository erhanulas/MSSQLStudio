import AppKit

/// Explicit fill and ink avoid AppKit bezel/tint combinations changing contrast.
@MainActor final class StudioPrimaryActionButton: StudioDialogButton {
  override var isEnabled:Bool {didSet {needsDisplay=true}}
  override func highlight(_ flag:Bool) {super.highlight(flag);needsDisplay=true}
  func refreshStyle() {isBordered=false;needsDisplay=true}
  override func draw(_ dirtyRect:NSRect) {
    let fill=isEnabled ? StudioTheme.accent:StudioTheme.muted.withAlphaComponent(0.18)
    (isHighlighted ? fill.withAlphaComponent(0.85):fill).setFill()
    NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:7,yRadius:7).fill()
    let ink=isEnabled ? (StudioTheme.dark ? StudioTheme.canvas:NSColor.white):StudioTheme.muted
    let text=NSAttributedString(string:title,attributes:[.font:font ?? NSFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:ink])
    let size=text.size(),total=size.width+20
    let x=(bounds.width-total)/2
    if let icon=image?.withSymbolConfiguration(.init(paletteColors:[ink])) {
      icon.draw(in:NSRect(x:x,y:(bounds.height-12)/2,width:12,height:12),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
    text.draw(at:NSPoint(x:x+20,y:(bounds.height-size.height)/2))
    if window?.firstResponder === self {
      ink.withAlphaComponent(0.7).setStroke()
      let path=NSBezierPath(roundedRect:bounds.insetBy(dx:3,dy:3),xRadius:5,yRadius:5);path.lineWidth=1;path.stroke()
    }
  }
}
