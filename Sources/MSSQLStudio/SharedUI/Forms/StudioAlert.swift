import AppKit

/// Native confirmation semantics with a stable placement identity for every caller.
@MainActor final class StudioAlert:NSAlert {
  let framePersistenceRole:String
  private var desiredModalFrame:NSRect?
  init(role:String) {
    framePersistenceRole=role
    super.init()
  }
  convenience init(role:String,error:Error) {
    self.init(role:role)
    let source=NSAlert(error:error)
    messageText=source.messageText
    informativeText=source.informativeText
    alertStyle=source.alertStyle
    for button in source.buttons {addButton(withTitle:button.title)}
  }
  private func preparePresentation() {
    layout()
    window.animationBehavior = .none
    window.backgroundColor=StudioTheme.canvas
    window.styleMask.insert(.resizable)
    // A different message may need more room than the previously saved dialog.
    window.minSize=window.frame.size
    func style(_ view:NSView) {
      if let label=view as? NSTextField,!label.isEditable {
        let heading=label.stringValue==messageText
        label.textColor=heading ? StudioTheme.text:StudioTheme.muted
        label.font = .systemFont(ofSize:heading ? 15:12,weight:heading ? .semibold:.regular)
      }
      for child in view.subviews {style(child)}
    }
    if let content=window.contentView {style(content)}
  }
  @objc private func restoreModalFrame(_ timer:Timer) {
    if let desiredModalFrame {window.setFrame(desiredModalFrame,display:true)}
  }
  @discardableResult override func runModal()->NSApplication.ModalResponse {
    preparePresentation()
    let focused=NSApp.keyWindow ?? NSApp.mainWindow
    let parent=focused?.sheetParent ?? focused
    StudioWindowPlacement.restore(window,role:framePersistenceRole,owner:parent)
    if let parent,parent !== window {parent.addChildWindow(window,ordered:.above)}
    // NSAlert positions itself before its modal loop; restore once, not on focus.
    desiredModalFrame=window.frame
    let timer=Timer(timeInterval:0,target:self,selector:#selector(restoreModalFrame(_:)),userInfo:nil,repeats:false)
    RunLoop.main.add(timer,forMode:.modalPanel)
    defer {
      timer.invalidate();desiredModalFrame=nil
      StudioWindowPlacement.save(window,role:framePersistenceRole)
      window.setFrameAutosaveName("")
      window.parent?.removeChildWindow(window)
    }
    return super.runModal()
  }
  override func beginSheetModal(for sheetWindow:NSWindow,completionHandler handler:((NSApplication.ModalResponse)->Void)?=nil) {
    preparePresentation()
    StudioWindowPlacement.restoreSheetSize(window,role:framePersistenceRole,owner:sheetWindow)
    let size=window.frame.size
    super.beginSheetModal(for:sheetWindow) { [self] response in
      StudioWindowPlacement.save(window,role:framePersistenceRole)
      handler?(response)
    }
    // Sheet attachment controls the origin; restore size after NSAlert's layout.
    window.setFrame(NSRect(origin:window.frame.origin,size:size),display:true)
  }
}
