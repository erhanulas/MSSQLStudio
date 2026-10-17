import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  @objc func showDatabaseIndex(_ sender:DatabaseIndexButton) {showIndexDetails(sender.node,relativeTo:sender)}
  @objc func showIndexStatus(_ sender:NSButton) {
    let scope=(showingSearch ? searchScope:selected) ?? searchScope ?? roots.first
    showIndexDetails(scope,relativeTo:sender)
  }
  @objc func showContextIndex() {showIndexDetails(contextNode,relativeTo:indexStatus)}
  private func showIndexDetails(_ scope:TreeNode?,relativeTo button:NSButton) {
    guard let scope else {return}
    let refreshScope:TreeNode
    if case .server=scope.kind {refreshScope=scope}
    else {refreshScope=explorerTree.databaseNode(server:scope.server,database:scope.database) ?? TreeNode(scope.database,kind:.database,server:scope.server,database:scope.database)}
    let popover=NSPopover();popover.animates = false;popover.behavior = .transient
    let panel=ExplorerIndexPanel(server:scope.server,databases:searchDatabases(scope), refresh: { [weak self] in
      self?.refreshExplorerScope(refreshScope)
    }, setDefinitionIndex: { [weak self] database, enabled in
      guard let self else { throw CancellationError() }
      try await state.setDefinitionIndex(scope.server, database: database, enabled: enabled)
    })
    indexPopover?.close();indexPopover=popover
    StudioPopover.show(popover,content:panel,from:button,size:NSSize(width:420,height:500))
  }
  func searchDatabases(_ scope: TreeNode) -> [String] {
    if case .server = scope.kind { return scope.server.databases.map(\.name) }
    return [scope.database]
  }
  func rebuildSearchScopes() {
    if let scope=searchScope {searchDatabaseByServer[scope.server.id]=scope.database}
    let candidate = (showingSearch ? searchScope?.server : selected?.server) ?? searchScope?.server ?? selectedServer
    let server = roots.first {$0.server === candidate}?.server ?? roots.first?.server
    searchScopes = server.map { server in
      [TreeNode("Tüm seçili veritabanları",kind:.server,server:server,database:"*")] + server.databases.map { item in
        TreeNode(item.name,kind:.database,server:server,database:item.name,item:item)
      }
    } ?? []
    searchScopePicker.removeAllItems()
    for scope in searchScopes { searchScopePicker.addItem(withTitle: "\(scope.server.profile.name) / \(scope.database == "*" ? "Tüm seçili veritabanları" : scope.database)") }
    let previous = UserDefaults.standard.string(forKey: "explorerSearchScope")
    let index = searchScopes.firstIndex { scope in
      if let database=searchDatabaseByServer[scope.server.id] {return scope.database == database}
      return "\(scope.server.id.uuidString)|\(scope.database)" == previous
    } ?? 0
    if searchScopes.indices.contains(index) { searchScopePicker.selectItem(at:index); searchScope = searchScopes[index] }
    else { searchScope = nil }
    searchScopePicker.isEnabled = !searchScopes.isEmpty
  }
  @objc func changeSearchScope() {
    guard searchScopes.indices.contains(searchScopePicker.indexOfSelectedItem) else { return }
    searchScope = searchScopes[searchScopePicker.indexOfSelectedItem]
    updateIndexStatus()
    if let scope = searchScope { UserDefaults.standard.set("\(scope.server.id.uuidString)|\(scope.database)",forKey:"explorerSearchScope") }
    filterExplorer()
  }
  func showExplorerSearch(_ show: Bool) {
    guard show != showingSearch else { return }
    if show {
      savedExpanded = (0..<outline.numberOfRows).compactMap { outline.item(atRow:$0) as? TreeNode }.filter { outline.isItemExpanded($0) }
      savedTreeSelection = outline.item(atRow:outline.selectedRow) as? TreeNode
      savedTreeOrigin = outline.enclosingScrollView?.contentView.bounds.origin ?? .zero
    }
    showingSearch = show
    explorerTabs.selectedSegment = show ? 1 : 0
    searchFilters.isHidden = !show
    reloadExplorer()
    if !show {
      restoringTree=true
      for node in savedExpanded { outline.expandItem(node) }
      restoringTree=false
      restoreExplorerExpansion()
      if let node = savedTreeSelection {
        let row = outline.row(forItem:node)
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false) }
      }
      if let scroll = outline.enclosingScrollView {
        scroll.contentView.scroll(to:savedTreeOrigin)
        scroll.reflectScrolledClipView(scroll.contentView)
      }
    }
  }
  @objc func changeExplorerTab() { showExplorerSearch(explorerTabs.selectedSegment == 1) }
  @objc func filterExplorer() {
    explorerSearchController.cancel()
    let text = explorerSearch.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      searchResults = nil
      searchStatus.stringValue = searchScope.map { "Arama kapsamı: " + ($0.database == "*" ? $0.server.profile.name + " / Tüm seçili veritabanları" : $0.database) } ?? "Önce bir bağlantı / veritabanı seçin"
      searchStatus.toolTip = nil
      if showingSearch {reloadExplorer()}
      return
    }
    showExplorerSearch(true)
    if searchScope == nil { searchScope = selected ?? roots.first }
    guard let scope = searchScope else { return }
    let databases = searchDatabases(scope)
    let types: [Folder?] = [nil,.tables,.views,.procedures,.functions,.synonyms]
    let folder = types[max(0,min(searchType.indexOfSelectedItem,types.count-1))]
    let generation = scope.server.generation
    searchStatus.stringValue = "\(scope.displayTitle) · Aranıyor…"
    let request = ExplorerSearchController.Request(profile:scope.server.profile,databases:databases,
      text:text,operation:searchOperator.indexOfSelectedItem,folder:folder)
    explorerSearchController.search(request) { [weak self] result in
      guard let self, scope.server.generation == generation else { return }
      switch result {
      case .success(let output):
        for db in output.staleDatabases {refreshIndexInBackground(server:scope.server,database:db)}
        searchResults = output.matches.map { match in
          let item=match.item,db=match.database
          let type: Folder = item.detail == "USER_TABLE" ? .tables : item.detail == "VIEW" ? .views : item.detail.contains("PROCEDURE") ? .procedures : item.detail == "SYNONYM" ? .synonyms : .functions
          let title = (databases.count > 1 ? db + " · " : "") + item.schema + "." + item.name
          return TreeNode(title,kind:.object(type),server:scope.server,database:db,item:item)
        }
        searchStatus.stringValue = "\(databases.count) veritabanı · \(output.matches.count) sonuç" + (output.truncated ? " · İlk 500" : "") + (output.pending > 0 ? " · \(output.pending) indeks hazırlanıyor" : "")
        searchStatus.toolTip = "Seçili veritabanlarının yerel disk indeksinde arama yapılır. Sonuçlar veritabanı sırasındadır; en fazla 500 sonuç gösterilir."
      case .failure(let error):
        searchResults = []; searchStatus.stringValue = "Arama başarısız: \(error.localizedDescription)"
      }
      if showingSearch { reloadExplorer() }
    }
  }
}
