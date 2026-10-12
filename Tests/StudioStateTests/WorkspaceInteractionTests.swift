import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct WorkspaceInteractionTests {
  func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
  @Test func searchScopeOnlyOffersSelectedExplorerAndRemembersItsDatabase() throws {
    _=NSApplication.shared
    let state=StudioState()
    let servers=["Alpha","Beta"].map { name in
      let server=ConnectedServer(profile:ServerProfile(name:name),password:"");server.online=false
      server.databases=[CatalogItem(id:1,name:"Shared"),CatalogItem(id:2,name:name+"DB")]
      return server
    }
    let old=UserDefaults.standard.string(forKey:"explorerSearchScope")
    defer {if let old {UserDefaults.standard.set(old,forKey:"explorerSearchScope")} else {UserDefaults.standard.removeObject(forKey:"explorerSearchScope")}}
    // A saved scope for another connection must not leak into the selected one.
    UserDefaults.standard.set(servers[1].id.uuidString+"|BetaDB",forKey:"explorerSearchScope")
    state.servers=servers
    let controller=WorkbenchController(state:state);_ = controller.view
    let controls=views(controller.view)
    let outline=try #require(controls.compactMap {$0 as? NSOutlineView}.first)
    let picker=try #require(controls.compactMap {$0 as? NSPopUpButton}.first {$0.accessibilityLabel() == "Nesne arama kapsamı"})
    let search=try #require(controls.compactMap {$0 as? NSSearchField}.first {$0.placeholderString == "Nesnelerde filtrele"})
    let roots=(0..<outline.numberOfRows).compactMap {outline.item(atRow:$0) as? TreeNode}.filter {if case .server=$0.kind {return true};return false}
    func select(_ node:TreeNode) {
      outline.selectRowIndexes(IndexSet(integer:outline.row(forItem:node)),byExtendingSelection:false)
    }
    func choose(_ title:String) throws {
      picker.selectItem(withTitle:title)
      #expect(NSApp.sendAction(try #require(picker.action),to:picker.target,from:picker))
    }
    select(roots[0])
    #expect(picker.itemTitles == ["Alpha / Tüm seçili veritabanları","Alpha / Shared","Alpha / AlphaDB"])
    try choose("Alpha / AlphaDB")
    let folder=try #require(roots[0].children.first);outline.expandItem(folder)
    select(try #require(folder.children.first))
    #expect(picker.titleOfSelectedItem == "Alpha / AlphaDB")
    select(roots[1])
    #expect(picker.itemTitles == ["Beta / Tüm seçili veritabanları","Beta / Shared","Beta / BetaDB"])
    try choose("Beta / Shared")
    select(roots[0]);#expect(picker.titleOfSelectedItem == "Alpha / AlphaDB")
    search.stringValue="";#expect(NSApp.sendAction(try #require(search.action),to:search.target,from:search))
    #expect(picker.titleOfSelectedItem == "Alpha / AlphaDB")
    state.changed?();#expect(picker.titleOfSelectedItem == "Alpha / AlphaDB")
    select(roots[1]);#expect(picker.titleOfSelectedItem == "Beta / Shared")
    servers[1].databases=[CatalogItem(id:2,name:"BetaDB")];state.changed?()
    #expect(picker.itemTitles == ["Beta / Tüm seçili veritabanları","Beta / BetaDB"])
    #expect(picker.indexOfSelectedItem == 0)
    state.servers=[servers[0]];state.changed?()
    #expect(picker.itemTitles.allSatisfy {$0.hasPrefix("Alpha / ")})
    state.servers=[];state.changed?()
    #expect(picker.numberOfItems == 0 && !picker.isEnabled)
  }
  @Test func newQueryFocusesEditorAndUpdatesDoNotStealFocus() async throws {
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"")
    server.online=false
    let controller=WorkbenchController(state:state)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:700),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=controller;defer {window.close()}
    let doc=state.newQuery(server:server)
    try await Task.sleep(for:.milliseconds(80))
    let editor=try #require(window.firstResponder as? SQLTextView)
    editor.insertText("SELECT 26;",replacementRange:editor.selectedRange())
    #expect(doc.sql == "SELECT 26;")
    let search=try #require(views(controller.view).compactMap {$0 as? NSSearchField}.first)
    window.makeFirstResponder(search)
    let responder=window.firstResponder
    state.changed?()
    try await Task.sleep(for:.milliseconds(80))
    #expect(window.firstResponder === responder)
    let second=state.newQuery(server:server)
    try await Task.sleep(for:.milliseconds(80))
    let secondEditor=try #require(window.firstResponder as? SQLTextView)
    #expect(secondEditor !== editor)
    secondEditor.insertText("SELECT 27;",replacementRange:secondEditor.selectedRange())
    #expect(second.sql == "SELECT 27;" && doc.sql == "SELECT 26;")
  }
  @Test func explicitSearchScopeSurvivesClearAndTreeSelection() throws {
    let originalScope = UserDefaults.standard.string(forKey:"explorerSearchScope")
    defer { if let originalScope { UserDefaults.standard.set(originalScope,forKey:"explorerSearchScope") } else { UserDefaults.standard.removeObject(forKey:"explorerSearchScope") } }
    let state = StudioState()
    let server = ConnectedServer(profile:ServerProfile(visibleDatabases:["master","Sample"]),password:"")
    server.databases = [CatalogItem(id:1,name:"master"),CatalogItem(id:10,name:"Sample")]
    state.servers = [server]
    let controller = WorkbenchController(state:state); _ = controller.view
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let controls = descendants(controller.view)
    let picker = try #require(controls.compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("Local SQL Server / Sample") })
    picker.selectItem(withTitle:"Local SQL Server / Sample")
    // Trigger the popup selection without opening a menu.
    NSApp.sendAction(picker.action!,to:picker.target,from:picker)
    let search = try #require(controls.compactMap { $0 as? NSSearchField }.first { $0.placeholderString == "Nesnelerde filtrele" })
    search.stringValue = ""; NSApp.sendAction(search.action!,to:search.target,from:search)
    #expect(picker.titleOfSelectedItem == "Local SQL Server / Sample")
    let previous = UserDefaults.standard.string(forKey:"explorerSearchScope")
    #expect(previous == server.id.uuidString + "|Sample")
    UserDefaults.standard.removeObject(forKey:"explorerSearchScope")
  }
  @Test func explorerSearchIncludesSelectedDatabases() async throws {
    let old = UserDefaults.standard.string(forKey:"explorerSearchScope")
    defer { if let old { UserDefaults.standard.set(old,forKey:"explorerSearchScope") } else { UserDefaults.standard.removeObject(forKey:"explorerSearchScope") } }
    let state = StudioState()
    let server = ConnectedServer(profile:ServerProfile(),password:"")
    server.databases = [CatalogItem(id:1,name:"First"),CatalogItem(id:2,name:"Second")]
    for db in server.databases {
      let key = CatalogDiskIndex.scope(profile:server.profile,database:db.name)
      let staging = key + ":test"
      try await CatalogDiskIndex.shared.append(scope:staging,items:[CatalogItem(id:10,name:"ScopeNeedle",schema:"dbo",detail:"USER_TABLE")])
      try await CatalogDiskIndex.shared.finishBuild(staging:staging,scope:key)
    }
    state.servers = [server]
    let controller = WorkbenchController(state:state); _ = controller.view
    let controls = views(controller.view)
    let picker = try #require(controls.compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("Local SQL Server / Tüm seçili veritabanları") })
    picker.selectItem(at:0); NSApp.sendAction(picker.action!,to:picker.target,from:picker)
    let search = try #require(controls.compactMap { $0 as? NSSearchField }.first { $0.placeholderString == "Nesnelerde filtrele" })
    search.stringValue = "ScopeNeedle"; NSApp.sendAction(search.action!,to:search.target,from:search)
    let outline = try #require(controls.compactMap { $0 as? NSOutlineView }.first)
    // Wait for asynchronous disk search completion rather than assuming a fixed machine speed.
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while outline.numberOfRows != 2 && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(100))
    }
    #expect(outline.numberOfRows == 2)
    let first = try #require(outline.item(atRow:0) as? TreeNode)
    let second = try #require(outline.item(atRow:1) as? TreeNode)
    #expect(first.database == "First")
    #expect(second.database == "Second")
    #expect(UserDefaults.standard.string(forKey:"explorerSearchScope") == server.id.uuidString + "|*")
    search.stringValue = ""; NSApp.sendAction(search.action!,to:search.target,from:search)
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func connectingPreparesDiskIndexWithoutSearch() async throws {
    let password = try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let state = StudioState()
    let profile = ServerProfile(trustCertificate:true,visibleDatabases:["master"])
    let server = try await state.connect(profile,password:password,save:false)
    let key = CatalogDiskIndex.scope(profile:profile,database:"master")
    var ready = false
    for _ in 0..<100 {
      if try await CatalogDiskIndex.shared.status(scope:key) != nil { ready = true; break }
      try await Task.sleep(for:.milliseconds(100))
    }
    await server.metadata.disconnect()
    #expect(ready)
  }
  @Test func clearingSearchRestoresExpandedTreeAndSelectedObject() throws {
    let state = StudioState(), server = ConnectedServer(profile:ServerProfile(),password:"")
    server.databases = [CatalogItem(id:10,name:"Sample")]; state.servers = [server]
    let controller = WorkbenchController(state:state); _ = controller.view
    let controls = views(controller.view)
    let outline = try #require(controls.compactMap { $0 as? NSOutlineView }.first)
    let root = try #require(outline.item(atRow:0) as? TreeNode)
    let databases = try #require(root.children.first)
    outline.expandItem(databases)
    let db = try #require(databases.children.first)
    outline.expandItem(db)
    let tables = try #require(db.children.first)
    tables.loaded = true
    let object = TreeNode("dbo.Kept",kind:.object(.tables),server:server,database:"Sample",item:CatalogItem(id:42,name:"Kept",schema:"dbo"))
    tables.children = [object]; outline.reloadItem(tables,reloadChildren:true); outline.expandItem(tables)
    outline.selectRowIndexes(IndexSet(integer:outline.row(forItem:object)),byExtendingSelection:false)
    let search = try #require(controls.compactMap { $0 as? NSSearchField }.first { $0.placeholderString == "Nesnelerde filtrele" })
    search.stringValue = "something"; NSApp.sendAction(search.action!,to:search.target,from:search)
    search.stringValue = ""; NSApp.sendAction(search.action!,to:search.target,from:search)
    #expect(outline.isItemExpanded(databases))
    #expect(outline.isItemExpanded(db))
    #expect(outline.isItemExpanded(tables))
    #expect(outline.item(atRow:outline.selectedRow) as? TreeNode === object)
  }
  @Test func pageSizesCopyMappingAndDefaultAreIndependentOfReadLimit() throws {
    _ = NSApplication.shared
    let old = UserDefaults.standard.object(forKey: "gridDefaultPageSize")
    defer { if let old { UserDefaults.standard.set(old,forKey:"gridDefaultPageSize") } else { UserDefaults.standard.removeObject(forKey:"gridDefaultPageSize") } }
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(),password:""),database:"master",title:"Pages")
    doc.results = [Rows(fields:[Field("ID",type:4)],values:(0..<1200).map { [String($0)] })]
    let query = QueryController(document:doc); _ = query.view
    let grid = try #require(query.children.compactMap { $0 as? ResultController }.first)
    let cap = doc.limits.rows
    query.applyPageSize(10)
    #expect(grid.table.numberOfRows == 10)
    let next = try #require(grid.toolbar.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.tag == 2 })
    next.performClick(nil)
    #expect(grid.pageExportIndices == Array(10..<20))
    grid.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
    grid.table.copyWithHeaders()
    #expect(NSPasteboard.general.string(forType:.string) == "ID\n10")
    query.applyPageSize(0)
    #expect(grid.table.numberOfRows == 1200)
    query.applyPageSize(77,makeDefault:true)
    #expect(GridPaging.defaultSize == 77)
    #expect(ResultController().pageSize == 77)
    #expect(grid.table.numberOfRows == 77)
    #expect(doc.limits.rows == cap)
    let popup = try #require(views(query.view).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityIdentifier() == "gridRowOptions" })
    #expect(popup.itemArray.contains { $0.title == "Varsayılan Yap" })
    #expect(popup.itemArray.contains {$0.identifier?.rawValue == "gridReadChoices"})
    #expect(popup.toolTip?.contains(doc.limits.rows.formatted()) == true)
  }
  @Test func automaticWidthsHorizontalScrollingAndLeftResultTabs() throws {
    _ = NSApplication.shared
    let doc = QueryDocument(server: ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Wide")
    let fields = (0..<24).map { Field("Column\($0)") }
    doc.results = [Rows(fields:fields,values:(0..<80).map { row in (0..<24).map { c in c == 1 ? "A fairly long sample cell value for fitting" : String(row) } })]
    let query = QueryController(document:doc)
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:850,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false; defer { window.close() }
    window.contentViewController = query; query.view.layoutSubtreeIfNeeded()
    let grid = try #require(query.children.compactMap { $0 as? ResultController }.first)
    #expect(grid.table.tableColumns[2].width > grid.table.tableColumns[1].width)
    #expect(grid.table.tableColumns[2].width <= 420)
    let scroll = try #require(grid.table.enclosingScrollView)
    #expect(scroll.hasHorizontalScroller && !scroll.autohidesScrollers)
    grid.table.scrollColumnToVisible(24)
    query.view.layoutSubtreeIfNeeded()
    #expect(scroll.contentView.bounds.minX > 0)
    let strip = try #require(views(query.view).first { $0.accessibilityIdentifier() == "resultTabStrip" })
    let first = try #require(strip.subviews.compactMap { $0 as? NSButton }.first)
    let rect = query.view.convert(first.bounds,from:first)
    #expect(rect.minX >= 0 && rect.minX < 20)
    #expect(first.title.hasPrefix("Results"))
    let search = try #require(views(query.view).compactMap { $0 as? NSSearchField }.first)
    let bar = try #require(views(query.view).first { $0.accessibilityIdentifier() == "gridToolbar" } as? NSStackView)
    #expect(bar.arrangedSubviews.contains { $0 === search })
    #expect(bar.arrangedSubviews.last?.accessibilityLabel() == "Sonuçları dışa aktar")
    grid.table.tableColumns[2].width = 222
    grid.update(doc.results[0],generation:55)
    #expect(grid.table.tableColumns[2].width == 222)
  }
  @Test func tabMovesKeepDocumentAndExplorerContext() {
    _ = NSApplication.shared
    let state = StudioState(); state.recoveryEnabled = false
    let server = ConnectedServer(profile:ServerProfile(database:"DefaultDB"),password:"")
    let docs = (0..<4).map { QueryDocument(server:server,database:"master",title:"Q\($0)") }
    docs[1].sql = "SELECT 7"; docs[1].pinned = true
    state.documents = docs; state.active = docs[1]
    let controller = WorkbenchController(state:state); _ = controller.view
    controller.moveQueryTab(docs[1].id,to:4)
    #expect(state.documents.map(\.title) == ["Q0","Q2","Q3","Q1"])
    #expect(state.active === docs[1] && docs[1].pinned && docs[1].sql == "SELECT 7")
    controller.moveQueryTab(docs[1].id,to:0)
    #expect(state.documents.first === docs[1])
    #expect(WorkbenchController.queryDatabase(for: TreeNode("Server",kind:.server,server:server)) == "DefaultDB")
    #expect(WorkbenchController.queryDatabase(for: TreeNode("Sales",kind:.database,server:server,database:"Sales")) == "Sales")
    #expect(WorkbenchController.queryDatabase(for: TreeNode("Table",kind:.object(.tables),server:server,database:"Sales")) == "Sales")
  }
  @Test func customShortcutCaptureRejectsConflictsAndUpdatesMenu() throws {
    _ = NSApplication.shared
    let keys = ["shortcut.newQuery","shortcut.headers","gridCopyHeadersShortcut"]
    let old = keys.map { UserDefaults.standard.object(forKey:$0) }
    let menu = NSApp.mainMenu
    defer {
      for (key,value) in zip(keys,old) { if let value { UserDefaults.standard.set(value,forKey:key) } else { UserDefaults.standard.removeObject(forKey:key) } }
      NSApp.mainMenu = menu
    }
    for key in keys { UserDefaults.standard.removeObject(forKey:key) }
    func event(_ key:String,_ flags:NSEvent.ModifierFlags) throws -> NSEvent {
      try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:0))
    }
    #expect(GridShortcuts.save(try event("k",[.control,.shift]),action:.newQuery) == nil)
    #expect(GridShortcuts.binding(.newQuery).label == "⌃⇧K")
    #expect(GridShortcuts.save(try event("k",[.control,.shift]),action:.headers) != nil)
    #expect(GridShortcuts.save(try event("q",.command),action:.headers) != nil)
    #expect(GridShortcuts.save(try event("f",.control),action:.newQuery) != nil)
    #expect(GridShortcuts.save(try event("k",[]),action:.headers) != nil)
    let main = NSMenu(); let item = main.addItem(withTitle:"New",action:#selector(WorkbenchController.newQuery),keyEquivalent:"n"); NSApp.mainMenu = main
    let controller = WorkbenchController(state:StudioState()); controller.refreshShortcuts()
    #expect(item.keyEquivalent == "k" && item.keyEquivalentModifierMask == [.control,.shift])
    GridShortcuts.reset(.newQuery)
    #expect(GridShortcuts.binding(.newQuery).label == "⌘N")
  }
}
