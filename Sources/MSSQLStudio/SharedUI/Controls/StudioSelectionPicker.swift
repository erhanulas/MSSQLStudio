import AppKit
import SwiftUI

/// The Settings reference surface, with native popup tracking/keyboard behavior.
@MainActor private final class StudioSelectionCell:NSPopUpButtonCell {
  override func draw(withFrame frame:NSRect,in view:NSView) {
    let background=isHighlighted ? StudioTheme.selection:StudioTheme.panel
    background.setFill()
    NSBezierPath(roundedRect:frame,xRadius:StudioMetrics.controlRadius,yRadius:StudioMetrics.controlRadius).fill()
    let ink=isEnabled ? StudioTheme.accent:StudioTheme.muted
    let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingTail
    let font=NSFont.systemFont(ofSize:StudioMetrics.bodyFont)
    let text=NSAttributedString(string:title,attributes:[.font:font,.foregroundColor:ink,.paragraphStyle:paragraph])
    let height=ceil(font.boundingRectForFont.height)
    text.draw(in:NSRect(x:frame.minX+10,y:frame.midY-height/2,width:max(0,frame.width-36),height:height))
    if let image=NSImage(systemSymbolName:"chevron.up.chevron.down",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[ink])) {
      StudioSymbolDrawing.draw(image,in:NSRect(x:frame.maxX-24,y:frame.midY-7,width:14,height:14))
    }
  }
}

@MainActor final class StudioSelectionControl:NSPopUpButton {
  convenience init() {self.init(frame:.zero,pullsDown:false)}
  override init(frame:NSRect,pullsDown:Bool) {
    super.init(frame:frame,pullsDown:pullsDown)
    cell=StudioSelectionCell(textCell:"",pullsDown:pullsDown)
    font = .systemFont(ofSize:StudioMetrics.bodyFont)
    (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
    setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    NotificationCenter.default.addObserver(self,selector:#selector(refreshStyle),name:StudioTheme.changed,object:nil)
  }
  required init?(coder:NSCoder) {fatalError()}
  override var alignmentRectInsets:NSEdgeInsets {NSEdgeInsetsZero}
  override var intrinsicContentSize:NSSize {NSSize(width:142,height:StudioMetrics.controlHeight)}
  override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();refreshStyle()}
  @objc private func refreshStyle() {needsDisplay=true}
}

struct StudioSelectionPicker<Value:Equatable>:NSViewRepresentable {
  let title:String
  @Binding var selection:Value
  let options:[Value]
  let label:(Value)->String
  @Environment(\.isEnabled) private var isEnabled
  func makeCoordinator()->Coordinator {Coordinator(self)}
  func makeNSView(context:Context)->StudioSelectionControl {
    let view=StudioSelectionControl()
    view.target=context.coordinator;view.action=#selector(Coordinator.choose(_:))
    return view
  }
  func updateNSView(_ view:StudioSelectionControl,context:Context) {
    context.coordinator.parent=self
    let titles=options.map(label)
    if view.itemTitles != titles {view.removeAllItems();view.addItems(withTitles:titles)}
    view.selectItem(at:options.firstIndex(of:selection) ?? -1)
    view.isEnabled=isEnabled;view.setAccessibilityLabel(title)
  }
  func sizeThatFits(_ proposal:ProposedViewSize,nsView:StudioSelectionControl,context:Context)->CGSize? {
    CGSize(width:proposal.width ?? nsView.intrinsicContentSize.width,height:StudioMetrics.controlHeight)
  }
  @MainActor final class Coordinator:NSObject {
    var parent:StudioSelectionPicker
    init(_ parent:StudioSelectionPicker) {self.parent=parent}
    @objc func choose(_ sender:NSPopUpButton) {
      guard parent.options.indices.contains(sender.indexOfSelectedItem) else {return}
      parent.selection=parent.options[sender.indexOfSelectedItem]
    }
  }
}
