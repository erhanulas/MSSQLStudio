import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  func rebuildOrganizationRoots() {explorerTree.rebuildOrganizationRoots(state.explorerOrganization)}
  func groupColor(_ id:UUID)->NSColor? {explorerTree.groupColor(id)}
  func sourceColor(for server:ConnectedServer)->NSColor? {explorerTree.sourceColor(for:server)}
  @discardableResult func presentExplorerName(title:String,value:String="",save:@escaping (String) async throws->Void)->StudioNameWindowController {
    let owner=StudioNameWindowController(title:title,value:value,save:save)
    auxiliaryWindows.append(owner)
    owner.closed={ [weak self,weak owner] in
      Task { @MainActor [weak self,weak owner] in self?.auxiliaryWindows.removeAll {$0 === owner} }
    }
    if ProcessInfo.processInfo.arguments.contains(where:{$0.contains(".xctest")}) {owner.window?.setFrameOrigin(NSPoint(x:-20_000,y:-20_000))}
    (owner.window as? StudioAssociatedWindow)?.associate(with:view.window)
    owner.showWindow(nil);owner.window?.makeKeyAndOrderFront(nil)
    return owner
  }
  @objc func createExplorerGroup(_ sender:NSMenuItem) {
    let parent=(sender.representedObject as? String).flatMap(UUID.init(uuidString:))
    Task { @MainActor [weak self] in
      self?.presentExplorerName(title:parent == nil ? "Yeni bağlantı klasörü":"Yeni alt klasör") {[weak self] name in
        guard let self else {throw CancellationError()}
        try state.changeExplorerOrganization {try $0.create(name,parent:parent)}
      }
    }
  }
  @objc func renameExplorerGroup() {
    guard let node=contextNode,let id=node.connectionGroupID else {return}
    Task { @MainActor [weak self] in
      self?.presentExplorerName(title:"Klasörü yeniden adlandır",value:node.title) {[weak self] name in
        guard let self else {throw CancellationError()}
        try state.changeExplorerOrganization {try $0.rename(id,name:name)}
      }
    }
  }
  @objc func removeExplorerGroup() {
    guard let node=contextNode,let id=node.connectionGroupID else {return}
    Task {[weak self] in
      guard let self else {return}
      let alert=StudioAlert(role:"deleteExplorerFolder");alert.messageText="\(node.title) klasörü kaldırılsın mı?"
      alert.informativeText="Bağlantılar ve alt klasörler bir üst konuma taşınır. Kayıtlı bağlantılar silinmez."
      alert.addButton(withTitle:"Klasörü Kaldır");alert.addButton(withTitle:"Vazgeç")
      guard alert.runModal() == .alertFirstButtonReturn else {return}
      do {try state.changeExplorerOrganization {try $0.remove(id)}} catch {state.showError(error.localizedDescription)}
    }
  }
  func addMoveMenu(to menu:NSMenu,group:UUID?,server:UUID?) {
    let child=StudioMenu();child.autoenablesItems=false
    func option(_ title:String,_ destination:UUID?) {
      let item=NSMenuItem(title:title,action:#selector(moveOrganizationItem(_:)),keyEquivalent:"")
      item.target=self;item.representedObject=[group == nil ? "server":"group",(group ?? server)!.uuidString,destination?.uuidString ?? ""]
      item.state=(group.flatMap {id in organization.groups.first {$0.id==id}?.parent} ?? server.flatMap {organization.assignments[$0]}) == destination ? .on:.off
      item.isEnabled = item.state != .on
      item.image=NSImage(systemSymbolName:destination == nil ? "tray":"folder",accessibilityDescription:nil)
      child.addItem(item)
    }
    option("Üst Düzey",nil)
    for value in organization.groups where value.id != group && (group == nil || (try? organization.ancestors(value.id).contains {$0.id==group}) == false) {option(organization.path(value.id),value.id)}
    let item=NSMenuItem(title:"Klasöre Taşı",action:nil,keyEquivalent:"");item.submenu=child;item.image=NSImage(systemSymbolName:"folder",accessibilityDescription:nil);menu.addItem(item)
  }
  @objc private func moveOrganizationItem(_ sender:NSMenuItem) {
    guard let parts=sender.representedObject as? [String],parts.count==3,let id=UUID(uuidString:parts[1]) else {return}
    let destination=UUID(uuidString:parts[2])
    do {try state.changeExplorerOrganization {if parts[0]=="group" {try $0.move(id,to:destination)} else {try $0.assign(id,to:destination)}}} catch {state.showError(error.localizedDescription)}
  }
  func addGroupColorMenu(to menu:NSMenu,id:UUID) {
    let child=StudioMenu()
    for (name,hex) in [("Varsayılan",""),("Mavi","3B82F6"),("Yeşil","238B65"),("Turuncu","C47C25"),("Mor","8B5CF6"),("Kırmızı","C74242")] {
      let item=NSMenuItem(title:name,action:#selector(changeExplorerGroupColor(_:)),keyEquivalent:"");item.target=self;item.representedObject=[id.uuidString,hex]
      item.state=organization.groups.first {$0.id==id}?.colorHex == (hex.isEmpty ? nil:hex) ? .on:.off
      item.image=NSImage(systemSymbolName:"circle.fill",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[hex.isEmpty ? StudioTheme.accent:ServerAppearance(colorHex:hex).color]));child.addItem(item)
    }
    let item=NSMenuItem(title:"Klasör Rengi",action:nil,keyEquivalent:"");item.submenu=child;menu.addItem(item)
  }
  @objc private func changeExplorerGroupColor(_ sender:NSMenuItem) {
    guard let parts=sender.representedObject as? [String],parts.count==2,let id=UUID(uuidString:parts[0]) else {return}
    do {try state.changeExplorerOrganization {try $0.setColor(id,hex:parts[1].isEmpty ? nil:parts[1])}} catch {state.showError(error.localizedDescription)}
  }
  @objc func deleteExplorerConnection() {
    guard let server=contextNode?.server,!server.updatingProfile,!server.reconnecting else {return}
    Task {[weak self] in
      guard let self else {return}
      let alert=StudioAlert(role:"deleteConnectionConfirmation");alert.messageText="\(server.profile.name) bağlantısı silinsin mi?"
      alert.informativeText="Kayıtlı profil ve bu profile ait parola silinir. Açık sorgu sekmeleri korunur."
      alert.addButton(withTitle:"Bağlantıyı Sil");alert.addButton(withTitle:"Vazgeç")
      guard alert.runModal() == .alertFirstButtonReturn else {return}
      do {try await state.deleteConnectionProfile(server)} catch {state.showError(error.localizedDescription)}
    }
  }
  @discardableResult func explorerGroupDrop(sourceID:UUID,item:Any?,childIndex:Int,apply:Bool)->Bool {
    guard !showingSearch,state.servers.contains(where:{$0.id==sourceID}) else {return false}
    let destination:UUID?,before:UUID?
    if let node=item as? TreeNode {
      if let id=node.connectionGroupID {
        guard childIndex == NSOutlineViewDropOnItemIndex || (0...node.children.count).contains(childIndex) else {return false}
        if childIndex>=0,childIndex<node.children.count,node.children[childIndex].connectionGroupID != nil {return false}
        destination=id
        before=childIndex>=0 && childIndex<node.children.count && node.children[childIndex].connectionGroupID == nil ? node.children[childIndex].server.id:nil
      } else if case .server=node.kind {
        destination=organization.assignments[node.server.id];before=node.server.id
      } else {return false}
    } else {
      guard (0...displayRoots.count).contains(childIndex) else {return false}
      if childIndex<displayRoots.count,displayRoots[childIndex].connectionGroupID != nil {return false}
      destination=nil;before=childIndex<displayRoots.count ? displayRoots[childIndex].server.id:nil
    }
    let insertion=before.flatMap {id in state.servers.firstIndex {$0.id==id}} ?? state.servers.count
    let movedGroup=organization.assignments[sourceID] != destination
    let old=state.servers.firstIndex {$0.id==sourceID}!
    guard movedGroup || insertion != old && insertion != old+1 else {return false}
    guard apply else {return true}
    do {
      if movedGroup {try state.changeExplorerOrganization {try $0.assign(sourceID,to:destination)}}
      _ = state.moveExplorer(sourceID,to:insertion)
      return true
    } catch {state.showError(error.localizedDescription);return false}
  }
}
