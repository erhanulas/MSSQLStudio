import AppKit

/// A nonblocking, owner-centered progress surface. Pointer and editor focus stay with the workspace.
@MainActor final class StudioLoadingCard:NSView {
  let phase=NSTextField(wrappingLabelWithString:"")
  let progress=NSProgressIndicator()
  private let heading=NSTextField(labelWithString:"")
  private let context=NSTextField(labelWithString:"")
  init(title:String,context:String) {
    super.init(frame:.zero)
    heading.stringValue=title;self.context.stringValue=context
    heading.font = .systemFont(ofSize:StudioMetrics.headingFont,weight:.semibold)
    self.context.font=StudioTheme.uiFont;self.context.lineBreakMode = .byTruncatingMiddle
    phase.font=StudioTheme.uiFont;phase.maximumNumberOfLines=2
    progress.style = .spinning;progress.controlSize = .regular;progress.isIndeterminate=true
    progress.setAccessibilityLabel(title);progress.startAnimation(nil)
    let titles=NSStackView(views:[heading,self.context]);titles.orientation = .vertical;titles.alignment = .leading;titles.spacing=4
    let row=NSStackView(views:[progress,titles,NSView()]);row.spacing=12;row.alignment = .centerY
    let stack=NSStackView(views:[row,phase]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12
    stack.translatesAutoresizingMaskIntoConstraints=false;addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),
      stack.topAnchor.constraint(equalTo:topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-16),
      heading.widthAnchor.constraint(equalTo:titles.widthAnchor),self.context.widthAnchor.constraint(equalTo:titles.widthAnchor),
      row.widthAnchor.constraint(equalTo:stack.widthAnchor),phase.widthAnchor.constraint(equalTo:stack.widthAnchor),
      progress.widthAnchor.constraint(equalToConstant:28),progress.heightAnchor.constraint(equalToConstant:28)
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
