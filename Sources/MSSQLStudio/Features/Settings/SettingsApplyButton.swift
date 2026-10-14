import AppKit
import SwiftUI

/// A stable native primary action avoids SwiftUI label/background sizing races
/// while the hosting window receives its first content-size proposal.
struct SettingsApplyButton:NSViewRepresentable {
  let apply:()->Void
  @Environment(\.isEnabled) private var enabled
  @Environment(\.colorScheme) private var scheme
  final class Coordinator:NSObject {
    var apply:()->Void
    init(_ apply:@escaping ()->Void) {self.apply=apply}
    @objc func submit() {apply()}
  }
  func makeCoordinator()->Coordinator {Coordinator(apply)}
  func makeNSView(context:Context)->StudioDialogButton {
    let button=StudioDialogButton(title:"Uygula",target:context.coordinator,action:#selector(Coordinator.submit))
    button.bezelStyle = .rounded;button.controlSize = .regular
    button.image=NSImage(systemSymbolName:"checkmark",accessibilityDescription:nil)
    button.imagePosition = .imageLeading
    button.font = .systemFont(ofSize:12,weight:.medium)
    button.setAccessibilityIdentifier("settingsApply");button.setAccessibilityLabel("Uygula")
    button.toolTip="Tercihleri uygula"
    return button
  }
  func updateNSView(_ button:StudioDialogButton,context:Context) {
    context.coordinator.apply=apply;button.isEnabled=enabled
    button.bezelColor=StudioTheme.accent
    button.contentTintColor=scheme == .dark ? StudioTheme.canvas:.white
  }
}
