import AppKit
import QuartzCore
import SwiftUI

/// A nonblocking, owner-centered progress surface. Pointer and editor focus stay with the workspace.
@MainActor final class StudioLoadingCard:NSView {
  let phase=NSTextField(wrappingLabelWithString:"")
  let progress=StudioTransferProgressView(frame:.zero)
  private let emblem=StudioLoadingEmblem(frame:.zero)
  private let heading=NSTextField(labelWithString:"")
  private let context=NSTextField(labelWithString:"")
  init(title:String,context:String) {
    super.init(frame:.zero)
    heading.stringValue=title;self.context.stringValue=context
    heading.font = .systemFont(ofSize:StudioMetrics.headingFont,weight:.semibold)
    self.context.font=StudioTheme.uiFont;self.context.lineBreakMode = .byTruncatingMiddle
    phase.font=StudioTheme.uiFont;phase.maximumNumberOfLines=2
    progress.isIndeterminate=true
    progress.setAccessibilityLabel(title);progress.startAnimation(nil)
    let titles=NSStackView(views:[heading,self.context]);titles.orientation = .vertical;titles.alignment = .leading;titles.spacing=4
    let row=NSStackView(views:[emblem,titles,NSView()]);row.spacing=12;row.alignment = .centerY
    let stack=NSStackView(views:[row,phase,progress]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12
    stack.translatesAutoresizingMaskIntoConstraints=false;addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),
      stack.topAnchor.constraint(equalTo:topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-16),
      heading.widthAnchor.constraint(equalTo:titles.widthAnchor),self.context.widthAnchor.constraint(equalTo:titles.widthAnchor),
      row.widthAnchor.constraint(equalTo:stack.widthAnchor),phase.widthAnchor.constraint(equalTo:stack.widthAnchor),
      emblem.widthAnchor.constraint(equalToConstant:36),emblem.heightAnchor.constraint(equalToConstant:36),
      progress.widthAnchor.constraint(equalTo:stack.widthAnchor),progress.heightAnchor.constraint(equalToConstant:4)
    ])
    setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel(title)
    refreshStyle()
  }
  required init?(coder:NSCoder) {fatalError()}
  func updatePhase(_ text:String) {
    phase.stringValue=text;setAccessibilityValue(text);progress.setAccessibilityHelp(text)
  }
  override func hitTest(_ point:NSPoint)->NSView? {nil}
  override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();refreshStyle()}
  private func refreshStyle() {
    StudioTheme.surface(self,card:true)
    heading.textColor=StudioTheme.text;context.textColor=StudioTheme.muted;phase.textColor=StudioTheme.text
  }
}

/// Layer animation keeps loading feedback independent of SwiftUI redraws and timer ticks.
@MainActor private final class StudioLoadingEmblem:NSView {
  private let ring=CAShapeLayer()
  private let icon=NSImageView()
  override init(frame:NSRect) {
    super.init(frame:frame);wantsLayer=true;layer?.addSublayer(ring)
    ring.fillColor=NSColor.clear.cgColor;ring.lineWidth=2;ring.lineCap = .round
    icon.image=NSImage(systemSymbolName:"network",accessibilityDescription:nil)
    icon.symbolConfiguration = .init(pointSize:16,weight:.medium)
    addSubview(icon)
    NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(motionChanged),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
  }
  required init?(coder:NSCoder) {fatalError()}
  @objc private func motionChanged() {needsLayout=true}
  override func viewDidMoveToWindow() {super.viewDidMoveToWindow();if window==nil {ring.removeAllAnimations()};needsLayout=true}
  override var isHidden:Bool {didSet {if isHidden {ring.removeAllAnimations()};needsLayout=true}}
  override func layout() {
    super.layout()
    CATransaction.begin();CATransaction.setDisableActions(true)
    layer?.cornerRadius=bounds.width/2
    layer?.backgroundColor=StudioTheme.selection.cgColor
    ring.frame=bounds
    ring.path=CGPath(ellipseIn:bounds.insetBy(dx:2,dy:2),transform:nil)
    ring.strokeColor=StudioTheme.accent.cgColor;ring.strokeStart=0.05;ring.strokeEnd=0.78
    icon.frame=bounds.insetBy(dx:9,dy:9);icon.contentTintColor=StudioTheme.accent
    CATransaction.commit()
    if window != nil,!isHiddenOrHasHiddenAncestor,!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      if ring.animation(forKey:"loading") == nil {
        let rotation=CABasicAnimation(keyPath:"transform.rotation.z")
        rotation.fromValue=0;rotation.toValue=Double.pi*2;rotation.duration=1.8;rotation.repeatCount = .infinity
        ring.add(rotation,forKey:"loading")
      }
    } else {ring.removeAllAnimations()}
  }
  override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();needsLayout=true}
}

struct StudioLoadingView:NSViewRepresentable {
  let title:String
  let context:String
  let phase:String
  func makeNSView(context:Context)->StudioLoadingCard {StudioLoadingCard(title:title,context:self.context)}
  func updateNSView(_ view:StudioLoadingCard,context:Context) {view.updatePhase(phase)}
}
