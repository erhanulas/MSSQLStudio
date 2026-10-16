import AppKit

extension WorkbenchController {
  private static let toolWindowPrefixes:[String:[String]]=[
    "activity":["activity|"],"history":["studio.timeline"],
    "favorites":["favorite-picker|","favorites|","favorite-editor|"]
  ]
  func toolWindowIsOpen(_ id:String)->Bool {
    if id=="profiler" {return !profilerWindows.isEmpty}
    guard let prefixes=Self.toolWindowPrefixes[id] else {return false}
    return auxiliaryWindows.compactMap(\.window).contains {window in
      guard window.isVisible || window.isMiniaturized,let identity=window.identifier?.rawValue else {return false}
      return prefixes.contains {identity.hasPrefix($0)}
    }
  }
  func configureToolWindowIndicator(_ button:StudioToolbarButton,id:String,label:String) {
    guard id=="profiler" || Self.toolWindowPrefixes[id] != nil else {return}
    let open=toolWindowIsOpen(id)
    button.tracksActiveState=true;button.tone=open ? .success:.neutral;button.state=open ? .on:.off
    button.setAccessibilityValue(open ? "Pencere açık":"Pencere kapalı")
    button.toolTip=StudioCommandCatalog.help(label,selector:button.action)+(open ? " · Açık pencere var":"")
  }
  func refreshToolWindowIndicators() {
    guard isViewLoaded else {return}
    for item in view.window?.toolbar?.items ?? [] {
      if let button=item.view as? StudioToolbarButton {configureToolWindowIndicator(button,id:item.itemIdentifier.rawValue,label:item.label)}
    }
  }
  @objc func toolWindowVisibilityChanged(_ notification:Notification) {
    if notification.name==NSWindow.willCloseNotification,isViewLoaded,(notification.object as? NSWindow) === view.window {profilerLauncher.cancel()}
    refreshToolWindowIndicators()
  }
}
