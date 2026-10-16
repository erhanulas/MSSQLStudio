import AppKit
import SwiftUI

/// Compact native selection for small, fixed option sets, shared by AppKit and SwiftUI.
@MainActor final class StudioSelectionPopUpButton:NSPopUpButton {
  convenience init() {self.init(frame:.zero,pullsDown:false)}
  override init(frame:NSRect,pullsDown:Bool) {
    super.init(frame:frame,pullsDown:pullsDown)
    controlSize = .regular;bezelStyle = .rounded;isBordered=true
    font = .systemFont(ofSize:StudioMetrics.bodyFont)
    setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    (cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
  }
  required init?(coder:NSCoder) {fatalError()}
  override var intrinsicContentSize:NSSize {
    NSSize(width:super.intrinsicContentSize.width,height:StudioMetrics.controlHeight)
  }
}

struct StudioSelectionPicker<Value:Equatable>:NSViewRepresentable {
  let title:String
  @Binding var selection:Value
  let options:[Value]
  let label:(Value)->String
  @Environment(\.isEnabled) private var isEnabled
  func makeCoordinator()->Coordinator {Coordinator(self)}
  func makeNSView(context:Context)->StudioSelectionPopUpButton {
    let view=StudioSelectionPopUpButton()
    view.target=context.coordinator;view.action=#selector(Coordinator.choose(_:))
    return view
  }
  func updateNSView(_ view:StudioSelectionPopUpButton,context:Context) {
    context.coordinator.parent=self
    let titles=options.map(label)
    if view.itemTitles != titles {view.removeAllItems();view.addItems(withTitles:titles)}
    view.selectItem(at:options.firstIndex(of:selection) ?? -1)
    view.isEnabled=isEnabled;view.setAccessibilityLabel(title)
  }
  func sizeThatFits(_ proposal:ProposedViewSize,nsView:StudioSelectionPopUpButton,context:Context)->CGSize? {
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
