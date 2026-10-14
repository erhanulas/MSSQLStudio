import AppKit

@MainActor final class DetachedQueryWindow: NSWindowController, NSWindowDelegate {
  var redock: (() -> Void)?
  let query: QueryController
  private let label = NSTextField(labelWithString: "")
  private let status=NSTextField(labelWithString:"")
  private let selection=NSTextField(labelWithString:"")
  init(query: QueryController) {
    self.query = query
    let window = StudioAssociatedWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1050, height: 740),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    super.init(window: window)
    window.title = query.document.title
    window.subtitle = "\(query.document.server.profile.name) — \(query.document.database)"
    window.minSize = NSSize(width: 800, height: 600)
    window.center()
    window.delegate = self
    let host = NSViewController()
    host.view = NSView()
    host.addChild(query)
    StudioTheme.surface(host.view, chrome: true)
    let run = StudioToolbarButton(symbol: "play.fill", label: "Çalıştır", tone: .success, title: "Çalıştır", width: 88, prominent: true)
    let cancel = StudioToolbarButton(symbol: "stop.fill", label: "İptal", tone: .warning, title: "İptal", width: 66)
    let dock = StudioToolbarButton(symbol: "arrow.uturn.backward", label: "Çalışma Alanına Dön", tone: .neutral, title: "Çalışma Alanına Dön", width: 170)
    run.target = self; run.action = #selector(execute)
    cancel.target = self; cancel.action = #selector(stop)
    dock.target = self; dock.action = #selector(DetachedQueryWindow.dock)
    label.font = .systemFont(ofSize: 11, weight: .medium)
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    updateConnectionAppearance()
    let header = NSStackView(views: [label, NSView(), run, cancel, dock])
    StudioTheme.surface(header)
    header.edgeInsets = NSEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)
    let footer=NSStackView(views:[status,NSView(),selection])
    StudioTheme.statusSurface(footer);footer.spacing=10
    footer.edgeInsets=NSEdgeInsets(top:1,left:8,bottom:1,right:8)
    for field in [status,selection] {
      field.font = .monospacedDigitSystemFont(ofSize:10,weight:.regular)
      field.lineBreakMode = .byTruncatingMiddle
      field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    }
    selection.isSelectable=true;selection.setAccessibilityIdentifier("resultSelectionSummaryValues")
    selection.widthAnchor.constraint(lessThanOrEqualToConstant:340).isActive=true
    let stack = NSStackView(views: [header, query.view,footer])
    stack.orientation = .vertical
    stack.spacing = 0
    host.view.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    query.view.setContentHuggingPriority(.init(1), for: .vertical)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: host.view.topAnchor),
      stack.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
      header.heightAnchor.constraint(equalToConstant: 36),
      footer.heightAnchor.constraint(equalToConstant:26),
      footer.widthAnchor.constraint(equalTo:stack.widthAnchor),
      header.widthAnchor.constraint(equalTo: stack.widthAnchor),
      query.view.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
    window.contentViewController = host
  }
  required init?(coder: NSCoder) { fatalError() }
  func updateConnectionAppearance() {
    let profile = query.document.server.profile
    let badge = profile.appearance?.badge ?? ""
    label.stringValue =
      (badge.isEmpty ? "" : "[\(badge)] ")
      + "\(profile.name) · \(profile.host),\(profile.port) · \(query.document.database)"
    label.lineBreakMode = .byTruncatingMiddle
    window?.subtitle = label.stringValue
    query.updateConnectionAppearance()
    updateStatus()
  }
  func updateStatus() {
    let doc=query.document
    let phase:String
    switch doc.state {
    case .ready:phase=doc.offlinePreview != nil ? "Çevrimdışı tanım · Salt okunur":"Ready"
    case .running:phase="Executing…"
    case .connecting:phase="Connecting…"
    case .cancelling:phase="Cancelling…"
    case .disconnected:phase="Çalıştırıldığında bağlanacak"
    }
    status.stringValue="\(phase) · \(doc.database) · Son çalıştırma: \(doc.lastExecutionDate?.formatted(date:.numeric,time:.standard) ?? "—")"
    selection.stringValue=query.selectionStatus?.text ?? ""
    selection.toolTip=query.selectionStatus?.help
    selection.isHidden=query.selectionStatus==nil
  }
  @objc private func execute() {guard query.document.canExecute else {return};query.focusEditor();query.document.execute()}
  @objc private func stop() { query.document.cancel() }
  @objc private func dock() { close() }
  func windowWillClose(_ notification: Notification) {
    redock?()
    redock = nil
  }
}
