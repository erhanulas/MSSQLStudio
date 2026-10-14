import AppKit
import SwiftUI

struct SettingsCategoryPicker:NSViewRepresentable {
  var selected:SettingsSection
  var choose:(SettingsSection)->Void
  final class Coordinator:NSObject {
    var choose:(SettingsSection)->Void
    init(_ choose:@escaping (SettingsSection)->Void) {self.choose=choose}
    @objc func pick(_ sender:NSButton) {guard SettingsSection.allCases.indices.contains(sender.tag) else {return};choose(SettingsSection.allCases[sender.tag])}
  }
  func makeCoordinator()->Coordinator {Coordinator(choose)}
  func makeNSView(context:Context)->NSStackView {
    let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=4
    for (index,section) in SettingsSection.allCases.enumerated() {
      let button=StudioFullAreaButton(title:section.title,target:context.coordinator,action:#selector(Coordinator.pick(_:)))
      button.tag=index;button.setButtonType(.pushOnPushOff);button.isBordered=false;button.bezelStyle = .inline;button.alignment = .left
      button.image=NSImage(systemSymbolName:section.icon,accessibilityDescription:nil);button.imagePosition = .imageLeading
      button.setAccessibilityIdentifier("settingsSection_"+section.rawValue)
      stack.addArrangedSubview(button);button.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;button.heightAnchor.constraint(equalToConstant:34).isActive=true
    }
    let spacer=NSView();spacer.setContentHuggingPriority(.init(1),for:.vertical);stack.addArrangedSubview(spacer)
    return stack
  }
  func updateNSView(_ stack:NSStackView,context:Context) {
    context.coordinator.choose=choose
    for button in stack.arrangedSubviews.compactMap({$0 as? NSButton}) {
      let active=SettingsSection.allCases[button.tag]==selected
      button.state=active ? .on:.off;button.contentTintColor=active ? StudioTheme.accent:StudioTheme.text
      button.wantsLayer=true;button.layer?.cornerRadius=6;button.layer?.backgroundColor=(active ? StudioTheme.selection:NSColor.clear).cgColor
    }
  }
}
