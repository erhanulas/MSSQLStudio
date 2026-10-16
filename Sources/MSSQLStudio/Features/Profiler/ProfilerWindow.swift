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
  init(server:ConnectedServer,model:ProfilerModel?=nil,openQuery:(([SQLProfiler.Event])->Void)?=nil) {
    let model=model ?? ProfilerModel(server:server);self.model=model
    let window=ProfilerWindow(contentRect:NSRect(x:0,y:0,width:1240,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
    super.init(window:window)
    window.isReleasedWhenClosed=false;window.delegate=self
    window.title="SQL Profiler · "+model.serverName
    window.identifier = .init("profiler|"+model.serverID.uuidString)
    window.framePersistenceRole="SQLProfiler"
    window.contentMinSize=NSSize(width:960,height:640);window.center()
    let host=NSHostingController(rootView:ProfilerPanel(model:model,background:{[weak window] in window?.orderOut(nil)},openQuery:openQuery))
    host.sizingOptions=[];window.contentViewController=host
    window.tabbingMode = .disallowed
    model.choices.refresh(automatic:true);model.sessions.refreshOnOpen()
  }
  required init?(coder:NSCoder) {fatalError()}
  func windowWillClose(_ notification:Notification) {model.choices.cancel();model.sessions.cancel()}
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
    if let owner=profilerWindows[server.id] {owner.model.choices.refresh(automatic:true);owner.model.sessions.refreshOnOpen();owner.showWindow(nil);owner.window?.makeKeyAndOrderFront(nil);return}
    let model=ProfilerModel(server:server,explorerChoices:{ [weak self,weak server] in
      guard let server else {return .init(databases:[],logins:nil)}
      let root=self?.roots.first {$0.server === server && $0.generation==server.generation}
      let security=root?.children.first {if case .group=$0.kind {return $0.title=="Security"};return false}
      let branch=security?.children.first {if case .folder(.logins)=$0.kind {return true};return false}
      return .init(databases:server.databases.map(\.name),logins:branch?.loaded == true && branch?.error == nil ? branch?.children.map {$0.item?.name ?? $0.title}:nil)
    })
    let owner=ProfilerWindowController(server:server,model:model,openQuery:{ [weak self,weak server] events in
      guard let self,let server,!events.isEmpty else {return}
      openProfilerSQL(events,server:server)
    });profilerWindows[server.id]=owner
    (owner.window as? ProfilerWindow)?.didClose={ [weak self,weak owner] in
      guard let owner else {return};owner.model.choices.cancel();self?.profilerWindows.removeValue(forKey:owner.model.serverID)
    }
    (owner.window as? StudioAssociatedWindow)?.associate(with:view.window)
    owner.showWindow(nil);owner.window?.makeKeyAndOrderFront(nil)
  }
  func openProfilerSQL(_ events:[SQLProfiler.Event],server:ConnectedServer) {
    guard !events.isEmpty else {return}
    let databases=Set(events.map(\.database).filter {!$0.isEmpty})
    let database=databases.count==1 ? databases.first!:server.profile.database
    state.newQuery(server:server,database:database,text:ProfilerExport.sql(events),title:"Profiler SQL")
    view.window?.makeKeyAndOrderFront(nil)
  }
  var hasActiveProfilers:Bool {profilerWindows.values.contains {$0.model.hasSession || $0.model.busy}}
  func stopProfilersForTermination() async -> Bool {
    for owner in Array(profilerWindows.values) {
      guard await owner.model.stop() else {owner.showWindow(nil);owner.window?.makeKeyAndOrderFront(nil);return false}
    }
    return true
  }
}
