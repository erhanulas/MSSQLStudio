import AppKit

private final class StudioWindowKeyMonitor {
  let token:Any
  init(_ token:Any) {self.token=token}
  deinit {NSEvent.removeMonitor(token)}
}

/// Cycle only persistent application windows, never sheets, hover panels or native file dialogs.
@MainActor final class StudioWindowCycler {
  private weak var main:NSWindow?
  private var monitor:StudioWindowKeyMonitor?
  private let activate:(NSWindow)->Void
  init(main:NSWindow,activate:@escaping (NSWindow)->Void = {window in
    if window.isMiniaturized {window.deminiaturize(nil)}
    window.makeKeyAndOrderFront(nil)
  }) {
    self.main=main;self.activate=activate
    let token=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
      let handled=MainActor.assumeIsolated {self?.handle(event)==true}
      return handled ? nil:event
    }
    if let token {monitor=StudioWindowKeyMonitor(token)}
  }
  func candidates(_ windows:[NSWindow])->[NSWindow] {
    windows.filter {
      ($0 === main || $0 is StudioAssociatedWindow) && ($0.isVisible || $0.isMiniaturized)
        && $0.canBecomeKey && $0.sheetParent==nil && $0.level == .normal
        && !$0.styleMask.contains(.nonactivatingPanel)
    }.sorted {$0.windowNumber<$1.windowNumber}
  }
  func handle(_ event:NSEvent)->Bool {
    let flags=event.modifierFlags.intersection([.command,.control,.option,.shift])
    guard event.type == .keyDown,event.keyCode==48,flags == .control || flags == [.control,.shift],
      NSApp.modalWindow==nil,let current=event.window,current.attachedSheet==nil,
      (current as? StudioPanelWindow)?.activePopover?.isShown != true else {return false}
    let windows=candidates(NSApp.windows)
    guard windows.count>1,let index=windows.firstIndex(where:{$0 === current}) else {return false}
    let next=windows[(index+(flags.contains(.shift) ? windows.count-1:1)) % windows.count]
    activate(next)
    return true
  }
}
