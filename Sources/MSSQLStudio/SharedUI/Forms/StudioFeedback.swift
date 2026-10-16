import AppKit
import SwiftUI

/// Bounded inline feedback keeps long server errors from displacing the form.
/// Full details remain selectable in a native transient popover and copyable.
struct StudioFeedback: View {
  enum Tone {
    case info, warning, error, success
    @MainActor var color: NSColor {
      switch self {
      case .info: StudioTheme.muted
      case .warning: StudioTheme.warning
      case .error: StudioTheme.danger
      case .success: StudioTheme.success
      }
    }
    var symbol: String {
      switch self {
      case .info: "info.circle"
      case .warning: "exclamationmark.triangle"
      case .error: "exclamationmark.circle"
      case .success: "checkmark.circle"
      }
    }
  }
  let message: String
  var tone: Tone = .error
  var heading: String? = nil
  var body: some View {
    if !message.isEmpty {
      HStack(alignment: .top, spacing: StudioMetrics.small) {
        Image(systemName: tone.symbol).frame(width: StudioMetrics.icon)
        VStack(alignment: .leading, spacing: 4) {
          if let heading { Text(heading).fontWeight(.medium) }
          Text(heading == nil ? message : message.trimmingCharacters(in: .whitespacesAndNewlines)).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
        StudioFeedbackDetailsButton(message: heading.map { $0 + "\n" + message } ?? message, color: tone.color)
          .frame(width: 24, height: 22)
      }.font(.system(size: StudioMetrics.detailFont))
        .foregroundStyle(Color(nsColor: tone.color))
        .padding(.horizontal, StudioMetrics.small).padding(.vertical, 6)
        .background(Color(nsColor: tone.color).opacity(0.06), in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
  }
}

/// Own the native popup explicitly, like StudioSearchablePopUpButton, so
/// keyboard cancellation belongs to the details and never reaches the form.
private struct StudioFeedbackDetailsButton: NSViewRepresentable {
  let message: String
  let color: NSColor
  func makeNSView(context: Context) -> StudioFeedbackButton { StudioFeedbackButton() }
  func updateNSView(_ button: StudioFeedbackButton, context: Context) {
    if button.message != message { button.popup.close(); button.message = message }
    button.contentTintColor = color
  }
}

@MainActor final class StudioFeedbackButton: StudioDialogButton, NSPopoverDelegate {
  let popup = NSPopover()
  var message = ""
  private var keyMonitor: Any?
  init() {
    super.init(frame: .zero)
    image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
    isBordered = false; imagePosition = .imageOnly
    setAccessibilityLabel("İleti ayrıntıları")
    toolTip = "İletinin tamamını oku veya kopyala"
    target = self; action = #selector(showDetails); popup.delegate = self
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func showDetails() {
    guard window != nil, !popup.isShown else { return }
    StudioHoverHelp.shared.hide()
    let dismiss = { [weak self] in self?.popup.close() }
    let content = VStack(alignment: .leading, spacing: StudioMetrics.small) {
      ScrollView { Text(message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
      HStack {
        StudioActionButton("Kopyala", icon: "doc.on.doc") { [message] in
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(message, forType: .string)
        }
        Spacer()
        StudioActionButton("Kapat", icon: "xmark") { dismiss() }.keyboardShortcut(.cancelAction)
      }
    }.padding(StudioMetrics.gap).frame(width: 420, height: 220).studioPanel()
      .foregroundStyle(Color(nsColor: StudioTheme.text))
    let controller = StudioFeedbackDetailsController(rootView: AnyView(content))
    controller.dismiss = { dismiss() }; controller.sizingOptions = []
    popup.behavior = .transient; popup.animates = false
    popup.contentViewController = controller; popup.contentSize = NSSize(width: 420, height: 220)
    (window as? StudioPanelWindow)?.activePopover = popup
    popup.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    controller.view.window?.makeKey()
    controller.view.window?.makeFirstResponder(controller)
    // Consume Escape while details are open, without forwarding the same
    // event to the owning form's cancel shortcut.
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let consumed = MainActor.assumeIsolated {
        guard let self, self.popup.isShown, event.keyCode == 53,
          event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        self.popup.close(); return true
      }
      return consumed ? nil : event
    }
  }
  func popoverDidClose(_ notification: Notification) {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
  }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    popup.close(); super.viewWillMove(toWindow: newWindow)
  }
}

@MainActor private final class StudioFeedbackDetailsController: NSHostingController<AnyView> {
  var dismiss: (() -> Void)?
  override var acceptsFirstResponder: Bool { true }
  override func cancelOperation(_ sender: Any?) { dismiss?() }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { dismiss?() } else { super.keyDown(with: event) }
  }
}
