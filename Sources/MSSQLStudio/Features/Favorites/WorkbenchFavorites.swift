import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  @objc func favoritesChanged() {
    guard isViewLoaded else {return}
    let selection=selected
    for root in roots {
      let folder=synchronizeFavorites(in:root)
      if !showingSearch {reloadExplorer(item:folder,children:true)}
    }
    if !showingSearch,let selection {
      let row=outline.row(forItem:selection)
      if row>=0 {outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
      else {outline.deselectAll(nil)}
    }
  }
  @objc func favoriteWindowClosed(_ notification:Notification) {
    guard let window=notification.object as? NSWindow,let identity=window.identifier?.rawValue,
      ["favorite-editor|","favorite-picker|","favorites|"].contains(where:identity.hasPrefix),
      auxiliaryWindows.contains(where:{$0.window === window}) else {return}
    // Release SwiftUI subscriptions and SQL text storage after AppKit finishes closing.
    Task { @MainActor [weak self,weak window] in
      guard let window else {return}
      window.contentViewController=nil
      self?.auxiliaryWindows.removeAll {$0.window === window}
    }
  }
  @discardableResult func synchronizeFavorites(in root:TreeNode) -> TreeNode {explorerTree.synchronizeFavorites(in:root,favorites:state.favorites.items)}
  func openExplorerFavorite(_ node:TreeNode) {
    guard let favorite=node.favorite else {return}
    do {try state.openFavorite(favorite,contextServerID:node.server.id,contextDatabase:node.database)}
    catch {state.showError(error.localizedDescription)}
  }
  @objc private func openFavoriteAtNode() {if let node=contextNode {openExplorerFavorite(node)}}
  func favoriteMenu(for node:TreeNode) -> NSMenu {
    let menu=StudioMenu()
    guard let favorite=node.favorite else {return menu}
    for (title,symbol,selector) in [("Sorguda Aç","arrow.up.right.square",#selector(openFavoriteMenu(_:))),("Düzenle…","pencil",#selector(editFavoriteMenu(_:))),("Sil…","trash",#selector(deleteFavoriteMenu(_:)))] {
      let item=NSMenuItem(title:title,action:selector,keyEquivalent:"")
      item.target=self;item.representedObject=node;item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:title)
      item.toolTip=favorite.name;menu.addItem(item)
    }
    return menu
  }
  @objc private func openFavoriteMenu(_ item:NSMenuItem) {if let node=item.representedObject as? TreeNode {openExplorerFavorite(node)}}
  @objc private func editFavoriteMenu(_ item:NSMenuItem) {
    guard let node=item.representedObject as? TreeNode,let favorite=state.favorites.items.first(where:{$0.id == node.favorite?.id}) else {return}
    presentFavoriteEditor(favorite:favorite,serverID:node.server.id,database:node.database)
  }
  @objc private func deleteFavoriteMenu(_ item:NSMenuItem) {
    guard let node=item.representedObject as? TreeNode,let favorite=state.favorites.items.first(where:{$0.id == node.favorite?.id}),let window=view.window else {return}
    let alert=StudioAlert();alert.messageText="Favori sorgu silinsin mi?";alert.informativeText=favorite.name
    alert.addButton(withTitle:"Favoriyi Sil");alert.addButton(withTitle:"Vazgeç")
    alert.beginSheetModal(for:window) { [weak self] response in
      guard response == .alertFirstButtonReturn else {return}
      Task {await self?.state.favorites.remove(favorite.id);if let self,!self.state.favorites.error.isEmpty {self.state.showError(self.state.favorites.error)}}
    }
  }
}
extension WorkbenchController {
  var favoriteContextDocument:QueryDocument? {
    favoriteContextDocument(in:NSApp.keyWindow)
  }
  func favoriteContextDocument(in window:NSWindow?)->QueryDocument? {
    detached.values.first {$0.window === window}?.query.document ?? state.active
  }
  @objc func showFavorites() {presentFavoritePicker(from:NSApp.keyWindow)}
  func presentFavoritePicker(from window:NSWindow?) {
    if let window,let picker=window.contentViewController as? FavoriteQueryPickerController,picker.model === state.favorites {
      window.makeKeyAndOrderFront(nil);picker.focusSearch();return
    }
    let document=favoriteContextDocument(in:window)
    let server=document?.server ?? selectedServer,database=document?.database ?? selectedDatabase
    let identity="favorite-picker|\(server?.id.uuidString ?? "global")|\(database)"
    if let existing=auxiliaryWindows.compactMap(\.window).first(where:{$0.identifier?.rawValue == identity && $0.isVisible}) {
      existing.makeKeyAndOrderFront(nil);(existing.contentViewController as? FavoriteQueryPickerController)?.focusSearch();return
    }
    let controller=FavoriteQueryPickerController(model:state.favorites,serverID:server?.id,database:database,
      contextLabel:(server?.profile.name ?? "Bağlantı seçilmedi")+" / "+database,
      open:{[weak self] favorite in
        guard let self else {return}
        try self.state.openFavorite(favorite,contextServerID:server?.id,contextDatabase:database)
        self.view.window?.makeKeyAndOrderFront(nil)
      },insert:{[weak self,weak document] favorite in
        guard let self else {return};try insertSavedSQL(favorite.sql,into:document)
      },manage:{[weak self] in self?.presentFavorites(server:server,database:database,target:document)})
    let window=StudioPanelWindow(contentViewController:controller)
    window.animationBehavior = .none
    window.framePersistenceRole="favoritePicker"
    window.identifier = .init(identity);window.title="Favori Sorgular"
    window.styleMask=[.titled,.closable,.resizable]
    window.setContentSize(NSSize(width:840,height:540))
    window.minSize=window.frameRect(forContentRect:NSRect(x:0,y:0,width:720,height:440)).size
    window.center()
    let owner=NSWindowController(window:window);auxiliaryWindows.append(owner);owner.showWindow(nil)
    controller.focusSearch()
    Task {await state.favorites.load()}
  }
  @objc func manageFavorites() {presentFavoritesManagement(from:NSApp.keyWindow)}
  func presentFavoritesManagement(from window:NSWindow?) {
    if let picker=window?.contentViewController as? FavoriteQueryPickerController,picker.model === state.favorites {
      presentFavorites(server:state.servers.first {$0.id == picker.serverID},database:picker.database);return
    }
    let document=favoriteContextDocument(in:window)
    presentFavorites(server:document?.server ?? selectedServer,database:document?.database ?? selectedDatabase)
  }
  @objc func showFavoritesAtNode() {if let node=contextNode {presentFavorites(server:node.server,database:Self.queryDatabase(for:node))}}
  private func presentFavorites(server:ConnectedServer?,database:String,target:QueryDocument? = nil) {
    let document=target ?? favoriteContextDocument
    present(FavoriteQueriesPanel(state:state,model:state.favorites,contextServerID:server?.id,contextDatabase:database,didOpen:{[weak self] in self?.view.window?.makeKeyAndOrderFront(nil)},
      insert:{[weak self,weak document] favorite in guard let self else {return};try insertSavedSQL(favorite.sql,into:document)},
      editFavorite:{[weak self] favorite,serverID,database in self?.presentFavoriteEditor(favorite:favorite,serverID:serverID,database:database)}),
      title:"Favori Sorgular",width:1100,height:760,minWidth:900,minHeight:660,identity:"favorites|\(server?.id.uuidString ?? "global")|\(database)")
  }
  @objc func addFavorite() {if let doc=favoriteContextDocument {presentFavoriteEditor(for:doc)}}
  func presentFavoriteEditor(for doc:QueryDocument) {
    guard !doc.sql.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return}
    presentFavoriteEditor(favorite:nil,serverID:doc.server.id,database:doc.database,sql:doc.sql,name:doc.title)
  }
  @discardableResult func presentFavoriteEditor(favorite:FavoriteQuery?,serverID:UUID?,database:String,sql:String="",name:String="")->FavoriteEditorWindowTarget {
    let identity="favorite-editor|\(favorite?.id ?? UUID())"
    let target=FavoriteEditorWindowTarget()
    target.window=present(FavoriteQueryEditor(model:state.favorites,servers:state.servers,contextServerID:serverID,database:database,favorite:favorite,sql:sql,name:name,close:target.close),
      title:favorite == nil ? "Favorilere Ekle":"Favoriyi Düzenle",width:720,height:660,minWidth:620,minHeight:540,identity:identity)
    return target
  }
}

extension WorkbenchController {
  func insertSavedSQL(_ sql:String, into target:QueryDocument?) throws {
    guard let target,state.documents.contains(where:{$0 === target}),
      let controller=queryController(for:target) else {throw SQLFailure("Önce SQL eklenecek sorgu sekmesini açın.")}
    try controller.insertSQLAtCaret(sql)
  }
  func insertExplorerFavorite(_ node:TreeNode) {
    guard let favorite=node.favorite else {return}
    do {try insertSavedSQL(favorite.sql,into:favoriteContextDocument)}
    catch {state.showError(error.localizedDescription)}
  }
}
