import AppKit
import SwiftUI
import SQLServerKit

/// A long-lived tool window, not an Escape-dismissed auxiliary dialog.
@MainActor final class ProfilerWindow:StudioAssociatedWindow {
  override func cancelOperation(_ sender:Any?) {}
}
@MainActor final class ProfilerWindowController:NSWindowController,NSWindowDelegate {
  let model:ProfilerModel
  private var closing=false
  init(server:ConnectedServer,model:ProfilerModel?=nil) {
    let model=model ?? ProfilerModel(server:server);self.model=model
    let window=ProfilerWindow(contentRect:NSRect(x:0,y:0,width:1240,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
    super.init(window:window)
    window.isReleasedWhenClosed=false;window.delegate=self
    window.title="SQL Profiler · "+model.serverName
    window.identifier = .init("profiler|"+model.serverID.uuidString)
    window.framePersistenceRole="SQLProfiler"
    window.contentMinSize=NSSize(width:960,height:640);window.center()
    let host=NSHostingController(rootView:ProfilerPanel(model:model,background:{[weak window] in window?.orderOut(nil)}))
    host.sizingOptions=[];window.contentViewController=host
    window.tabbingMode = .disallowed
  }
  required init?(coder:NSCoder) {fatalError()}
  func windowShouldClose(_ sender:NSWindow)->Bool {
    guard !closing,!model.busy else {return false}
    guard model.hasSession else {return true}
    let alert=StudioAlert();alert.messageText="Profiler izlemeye devam ediyor"
    alert.informativeText="Arka planda izlemeyi sürdürün veya yalnız bu Profiler’ın sunucu oturumunu kaldırıp kapatın."
    alert.addButton(withTitle:"Arka Planda İzle");alert.addButton(withTitle:"Durdur ve Kapat");alert.addButton(withTitle:"Vazgeç")
    switch alert.runModal() {
    case .alertFirstButtonReturn:sender.orderOut(nil)
    case .alertSecondButtonReturn:
      closing=true
      Task { [weak self] in
        guard let self else {return}
        let stopped=await model.stop();closing=false
        if stopped {window?.close()} else {window?.makeKeyAndOrderFront(nil)}
      }
    default:break
    }
    return false
  }
}

extension WorkbenchController {
  @objc func profiler() {
    guard let server=selectedServer else {return}
    if let owner=profilerWindows[server.id] {owner.showWindow(nil);owner.window?.makeKeyAndOrderFront(nil);return}
    let owner=ProfilerWindowController(server:server);profilerWindows[server.id]=owner
    (owner.window as? ProfilerWindow)?.didClose={ [weak self,weak owner] in
      guard let owner else {return};self?.profilerWindows.removeValue(forKey:owner.model.serverID)
    }
    (owner.window as? StudioAssociatedWindow)?.associate(with:view.window)
    owner.showWindow(nil);owner.window?.makeKeyAndOrderFront(nil)
  }
  var hasActiveProfilers:Bool {profilerWindows.values.contains {$0.model.hasSession || $0.model.busy}}
  func stopProfilersForTermination() async -> Bool {
    for owner in Array(profilerWindows.values) {
      guard await owner.model.stop() else {owner.showWindow(nil);owner.window?.makeKeyAndOrderFront(nil);return false}
    }
    return true
  }
}
