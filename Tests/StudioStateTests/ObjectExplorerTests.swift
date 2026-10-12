import AppKit
import Testing
import SQLServerKit
@testable import MSSQLStudio

@MainActor struct ObjectExplorerTests {
  @Test func agentPollingOnlyRunsForVisibleExpandedBranchesAndPreservesSelection() async throws {
    _=NSApplication.shared
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"")
    state.servers=[server]
    var requests=0,detail="Enabled, Idle"
    server.catalogFixture={_ in requests+=1;var e=Execution();e.results=[Rows(values:[["0","JobOne",nil,detail]])];return e}
    let host=WorkbenchController(state:state)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:800),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=host
    window.makeKeyAndOrderFront(nil)
    defer {window.close()}
    func descendants(_ v:NSView)->[NSView] {[v]+v.subviews.flatMap(descendants)}
    let outline=try #require(descendants(host.view).compactMap {$0 as? NSOutlineView}.first)
    let root=try #require(outline.item(atRow:0) as? TreeNode)
    let agent=try #require(root.children.first {$0.title == "SQL Server Agent"})
    await host.refreshExpandedAgentJobs();#expect(requests == 0)
    outline.expandItem(agent)
    let jobs=try #require(agent.children.first {if case .folder(.jobs)=$0.kind {return true};return false})
    outline.expandItem(jobs)
    for _ in 0..<100 {if jobs.loaded {break};try await Task.sleep(for:.milliseconds(10))}
    let job=try #require(jobs.children.first),icon=job.icon
    outline.selectRowIndexes(IndexSet(integer:outline.row(forItem:job)),byExtendingSelection:false)
    detail="Enabled, Running";await host.refreshExpandedAgentJobs()
    #expect(requests == 2 && jobs.children.first === job)
    #expect(job.displayTitle == "JobOne" && job.icon != icon)
    #expect(outline.item(atRow:outline.selectedRow) as? TreeNode === job)
    outline.collapseItem(agent);await host.refreshExpandedAgentJobs();#expect(requests == 2)
    outline.expandItem(agent);server.online=false;await host.refreshExpandedAgentJobs();#expect(requests == 2)
  }
  @Test func explorerHealthDetectsLostConnectionsAndIgnoresSQLAndStaleFailures() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    let state=StudioState();state.servers=[server]
    let host=WorkbenchController(state:state)
    let window=NSWindow(contentRect:NSRect(x:-2000,y:0,width:1200,height:800),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=host;host.view.frame.size=NSSize(width:1200,height:800)
    host.view.layoutSubtreeIfNeeded();defer {window.close()}
    let doc=QueryDocument(server:server,database:"master",title:"Independent session");doc.state = .ready
    let lost=SQLFailure("Connection lost",diagnostics:[Diagnostic(state:"08S01",code:10054,message:"Transport error")])
    server.healthCheckFixture={throw SQLFailure("Permission denied",diagnostics:[Diagnostic(state:"42000",code:229,message:"Permission denied")])}
    await server.checkExplorerHealth();#expect(server.online)
    server.healthCheckFixture={server.generation=UUID();throw lost}
    await server.checkExplorerHealth();#expect(server.online)
    server.healthCheckFixture={throw lost}
    await server.checkExplorerHealth()
    #expect(!server.online && server.startupError?.contains("08S01") == true)
    #expect(doc.state == .ready)
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let outline=try #require(descendants(host.view).compactMap {$0 as? NSOutlineView}.first)
    let root=try #require(outline.item(atRow:0) as? TreeNode)
    #expect(root.displayTitle.contains("Bağlantı kapalı"))
    let cell=try #require(outline.view(atColumn:0,row:outline.row(forItem:root),makeIfNecessary:true))
    let labels=descendants(cell).compactMap {$0 as? NSTextField}.map(\.stringValue)
    #expect(labels.contains {$0.contains("Bağlantı kapalı")})
    var calls=0
    server.healthCheckFixture={calls+=1}
    await server.checkExplorerHealth();#expect(calls == 0)
    server.online=true;await server.checkExplorerHealth();#expect(calls == 1 && server.online)
    server.reconnecting=true;await server.checkExplorerHealth();#expect(calls == 1)
  }
  @Test func closedQuerySessionDoesNotClaimReadyOrDisconnectHealthyExplorer() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var checks=0;server.healthCheckFixture={checks+=1}
    let doc=QueryDocument(server:server,database:"master",title:"Closed handle")
    doc.sql="SELECT 1;";doc.state = .ready
    doc.execute()
    await doc.task?.value
    #expect(doc.task == nil && doc.state == .disconnected && !doc.canRefresh)
    #expect(doc.messages.contains("08003") && server.online && checks == 1)
    doc.state = .ready;doc.useDatabase("OtherDB")
    await doc.task?.value
    #expect(doc.task == nil && doc.state == .disconnected && doc.database == "master")
    #expect(server.online && checks == 2)
    let offline=ConnectedServer(profile:ServerProfile(),password:"")
    await offline.checkExplorerHealth()
    #expect(!offline.online && offline.startupError?.contains("08003") == true)
  }
  @Test func runningQueryDoesNotPreventNativeTabSwitchAndVisiblePanelsAreReused() async throws {
    _=NSApplication.shared
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let first=QueryDocument(server:server,database:"master",title:"LoadingTab")
    let second=QueryDocument(server:server,database:"master",title:"OtherTab")
    first.state = .running;state.documents=[first,second];state.active=first
    let host=WorkbenchController(state:state)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:800),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=host
    window.makeKeyAndOrderFront(nil)
    defer {window.close()}
    func descendants(_ v:NSView)->[NSView] {[v]+v.subviews.flatMap(descendants)}
    let views=descendants(host.view)
    #expect(views.contains {$0 is NSProgressIndicator})
    first.changed?()
    let button=try #require(views.compactMap {$0 as? NSButton}.first {$0.title == "OtherTab"})
    #expect(NSApp.sendAction(try #require(button.action),to:button.target,from:button))
    #expect(state.active === second && first.state == .running)
    try await Task.sleep(for:.milliseconds(100))
    #expect(state.active === second)
    var historyRequests:[String]=[]
    server.catalogFixture={sql in historyRequests.append(sql);return ObjectManagementUIFixture.catalog(sql)}
    let node=TreeNode("Demo Nightly",kind:.object(.jobs),server:server,item:CatalogItem(name:"Demo Nightly"))
    host.showAgentHistory(node);host.showAgentHistory(node)
    let windows=NSApp.windows.filter {$0.identifier?.rawValue.hasPrefix("agent.history|"+server.id.uuidString) == true}
    defer {windows.forEach {$0.close()}}
    #expect(windows.count == 1)
    for _ in 0..<100 {if !historyRequests.isEmpty {break};try await Task.sleep(for:.milliseconds(10))}
    #expect(historyRequests.count == 1)
    #expect(historyRequests.first?.contains("SELECT MAX(p.instance_id)") == false)
  }
  @Test func linkedMetadataExplainsEmptyPartialAndMalformedProviderResults() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    var mode=0
    server.catalogFixture={ sql in
      var e=Execution()
      if mode == 1 {e.results=[Rows(fields:[Field("Unexpected")],values:[["value"]])];return e}
      if sql.contains("sp_catalogs") {e.results=[Rows(fields:[Field("CATALOG_NAME")],values:[])];e.partial=true}
      else {e.results=[Rows(fields:[Field("TABLE_CAT"),Field("TABLE_SCHEM"),Field("TABLE_NAME"),Field("TABLE_TYPE")],values:[])]}
      return e
    }
    let host=WorkbenchController(state:StudioState());_=host.view
    let catalogs=TreeNode("Catalogs",kind:.group,server:server);catalogs.linked = .catalogs("L")
    func load(_ node:TreeNode) async throws {
      host.loadLinked(node)
      for _ in 0..<100 {if node.loaded {return};try await Task.sleep(for:.milliseconds(10))}
      #expect(node.loaded)
    }
    try await load(catalogs)
    #expect(catalogs.children.count == 2)
    let fallback=try #require(catalogs.children.first)
    if case .catalog(let link,let name)=fallback.linked {#expect(link == "L" && name == nil)} else {Issue.record("Missing default catalog fallback")}
    #expect(catalogs.children.last?.title.contains("Kısmi liste") == true)
    try await load(fallback)
    #expect(fallback.children.first?.title.contains("Görünür metadata yok") == true)
    mode=1;catalogs.loaded=false
    try await load(catalogs)
    #expect(catalogs.error != nil)
    #expect(catalogs.children.first?.title.contains("Yenile") == true)
  }
  @Test func linkedServerNativeExpansionUsesProviderMetadataAndSafeMenus() async throws {
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"")
    server.online=false;state.servers=[server]
    var queries:[String]=[]
    server.catalogFixture={ sql in
      queries.append(sql)
      var e=Execution()
      if sql == Catalog.objects(.linkedServers) {e.results=[Rows(values:[["42","Remote",nil,"SQL Server"]])]}
      else if sql.contains("sp_catalogs") {e.results=[Rows(fields:[Field("CATALOG_NAME"),Field("DESCRIPTION")],values:[["RemoteDb",nil]])]}
      else if sql.contains("sp_tables_ex") {
        e.results=[Rows(fields:[Field("TABLE_CAT"),Field("TABLE_SCHEM"),Field("TABLE_NAME"),Field("TABLE_TYPE")],values:[["RemoteDb","dbo","Customers","TABLE"],["RemoteDb","report","Summary","VIEW"],["RemoteDb","sys","Meta","SYSTEM VIEW"]])]
      } else if sql.contains("sp_columns_ex") {
        e.results=[Rows(fields:[Field("TABLE_CAT"),Field("TABLE_SCHEM"),Field("TABLE_NAME"),Field("COLUMN_NAME"),Field("TYPE_NAME"),Field("ORDINAL_POSITION")],values:[["RemoteDb","dbo","Customers","ID","int","1"]])]
      }
      return e
    }
    let host=WorkbenchController(state:state);_=host.view
    func descendants(_ v:NSView) -> [NSView] {[v]+v.subviews.flatMap(descendants)}
    let outline=try #require(descendants(host.view).compactMap {$0 as? NSOutlineView}.first)
    let root=try #require(outline.item(atRow:0) as? TreeNode)
    let objects=try #require(root.children.first {$0.title == "Server Objects"})
    let links=try #require(objects.children.first)
    func expand(_ node:TreeNode) async throws {
      outline.expandItem(node)
      for _ in 0..<100 {if node.loaded {return};try await Task.sleep(for:.milliseconds(10))}
      #expect(node.loaded)
    }
    outline.expandItem(objects)
    try await expand(links)
    let linked=try #require(links.children.first)
    #expect(linked.expandable)
    try await expand(linked)
    let catalogs=try #require(linked.children.first)
    #expect(catalogs.title == "Catalogs" && queries.count == 1)
    try await expand(catalogs)
    let catalog=try #require(catalogs.children.first)
    #expect(catalog.title == "RemoteDb")
    try await expand(catalog)
    #expect(catalog.children.map(\.title) == ["Tables","Views","System Views"])
    let tables=try #require(catalog.children.first);outline.expandItem(tables)
    let table=try #require(tables.children.first)
    #expect(outline.row(forItem:table)>=0)
    let titles=host.linkedMenu(for:table).items.map(\.title)
    #expect(titles.contains("Select Top 1000 Rows") && titles.contains("Tam Adı Kopyala"))
    #expect(!titles.contains(where: {$0.contains("Delete") || $0.contains("Design") || $0.contains("ALTER")}))
    try await expand(table)
    #expect(table.children.map(\.title) == ["Columns"])
    let columns=try #require(table.children.first);try await expand(columns)
    #expect(columns.children.first?.item?.name == "ID")
    #expect(queries.count == 4 && queries.last?.contains("@table_catalog=N'RemoteDb'") == true)
    host.openLinkedRelation(table,run:false)
    #expect(state.active?.database == "master")
    #expect(state.active?.sql == "SELECT TOP (1000) *\nFROM [Remote].[RemoteDb].[dbo].[Customers];")
    #expect(state.active?.runAfterConnect == false && queries.count == 4)
  }
  @Test func explorerRemovalPreservesOpenQueryAndSavedCredentials() async throws {
    let key="explorerActiveServerIDs", defaults=UserDefaults.standard
    let old=defaults.object(forKey:key)
    defer {if let old {defaults.set(old,forKey:key)} else {defaults.removeObject(forKey:key)}}
    let state=StudioState()
    let server=ConnectedServer(profile:ServerProfile(),password:"fixture-only")
    server.remembered=true;state.servers=[server]
    defaults.set([server.id.uuidString],forKey:key)
    let doc=QueryDocument(server:server,database:"master",title:"Keep")
    doc.state = .ready;doc.transactionCount=1;doc.sql="SELECT 1;"
    state.documents=[doc];state.active=doc
    let host=WorkbenchController(state:state);_ = host.view
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let outline=try #require(descendants(host.view).compactMap {$0 as? NSOutlineView}.first)
    await state.removeExplorer(server)
    #expect(outline.numberOfRows == 0)
    #expect(state.servers.isEmpty && !server.online)
    #expect(state.documents.first === doc && state.active === doc)
    #expect(doc.server === server && doc.transactionCount == 1 && doc.sql == "SELECT 1;")
    #expect(server.remembered && server.password == "fixture-only")
    #expect(defaults.stringArray(forKey:key) == [])
  }
  @Test func explorerDisconnectPreservesQuerySessionAndCachedNativeTree() async throws {
    let state = StudioState()
    let server = ConnectedServer(profile: ServerProfile(), password: "")
    server.databases = [CatalogItem(id: 1, name: "master")]
    state.servers = [server]
    let doc = QueryDocument(server: server, database: "master", title: "Keep")
    doc.state = .ready; doc.transactionCount = 1; doc.sql = "SELECT N'keep';"
    state.documents = [doc]; state.active = doc
    let host = WorkbenchController(state: state); _ = host.view
    func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
    let outline = try #require(descendants(host.view).compactMap { $0 as? NSOutlineView }.first)
    let root = try #require(outline.item(atRow: 0) as? TreeNode)
    let children = root.children
    await state.disconnectExplorer(server)
    #expect(state.servers.first === server && state.active === doc)
    #expect(doc.server === server && doc.state == .ready && doc.transactionCount == 1)
    #expect(doc.sql == "SELECT N'keep';" && !server.online)
    #expect(outline.item(atRow: 0) as? TreeNode === root)
    #expect(root.children.elementsEqual(children, by: { $0 === $1 }))
    #expect(root.displayTitle.contains("Bağlantı kapalı"))
    server.reconnecting = true
    #expect(root.displayTitle.contains("Bağlanıyor"))
    server.reconnecting = false
    server.online = true
    server.recordExplorerFailure(SQLFailure("Denied", diagnostics: [.init(state: "42000", code: 229, message: "permission")]))
    #expect(server.online)
    server.recordExplorerFailure(SQLFailure("Lost", diagnostics: [.init(state: "08S01", code: 0, message: "link")]))
    #expect(!server.online && server.startupError != nil)
  }
  @Test func offlineRefreshNeverReconnectsAndNewQueryExplicitlyAttemptsOnce() async throws {
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"")
    server.online=false;state.servers=[server]
    var attempts=0,checks=0
    server.reconnectFixture={attempts += 1;try await Task.sleep(for:.milliseconds(40));throw SQLFailure("Fixture unavailable")}
    server.healthCheckFixture={checks += 1}
    let host=WorkbenchController(state:state);_ = host.view
    #expect(host.selectedServer === server)
    let root=TreeNode("Offline",kind:.server,server:server)
    host.refresh(root);await server.checkExplorerHealth()
    #expect(attempts == 0 && checks == 0)
    host.newQuery();host.newQuery()
    for _ in 0..<100 where attempts == 0 || server.reconnecting {try await Task.sleep(for:.milliseconds(10))}
    #expect(attempts == 1 && !server.online && !server.reconnecting)
    #expect(server.startupError == "Fixture unavailable" && state.documents.isEmpty)
    host.refresh(root);await server.checkExplorerHealth()
    #expect(attempts == 1 && checks == 0)
    server.reconnectFixture={attempts += 1}
    #expect(await state.prepareExplorerForNewQuery(server))
    #expect(server.online && attempts == 2)
    #expect(await state.prepareExplorerForNewQuery(server))
    #expect(attempts == 2)
  }
  @Test func connectionMenuClosesOnlyExplorerAndOffersExplicitReconnect() async throws {
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"")
    state.servers=[server]
    let doc=QueryDocument(server:server,database:"master",title:"Independent")
    doc.state = .ready;doc.transactionCount=1;state.documents=[doc];state.active=doc
    let host=WorkbenchController(state:state);_ = host.view
    let menu=host.explorerConnectionMenu(server:server)
    let close=try #require(menu.items.first {$0.title == "Aktif Bağlantıyı Kapat"})
    #expect(close.isEnabled && close.image != nil && close.representedObject as? ConnectedServer === server)
    #expect(NSApp.sendAction(try #require(close.action),to:close.target,from:close))
    for _ in 0..<100 where server.online {try await Task.sleep(for:.milliseconds(10))}
    #expect(!server.online && state.servers.first === server && doc.state == .ready && doc.transactionCount == 1)
    let offline=host.explorerConnectionMenu(server:server)
    let reconnect=try #require(offline.items.first {$0.title == "Yeniden Bağlan"})
    server.reconnecting=true
    #expect(host.explorerConnectionMenu(server:server).items.last?.isEnabled == false)
    server.reconnecting=false
    var attempts=0;server.reconnectFixture={attempts += 1}
    #expect(NSApp.sendAction(try #require(reconnect.action),to:reconnect.target,from:reconnect))
    for _ in 0..<100 where !server.online {try await Task.sleep(for:.milliseconds(10))}
    #expect(server.online && attempts == 1 && doc.transactionCount == 1)
  }
  @Test func procedureFunctionAndTriggerIconsHaveDistinctSemanticsAndParentOwnership() throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    func node(_ f:Folder,_ detail:String="")->TreeNode {TreeNode("Example",kind:.object(f),server:server,item:.init(id:1,name:"Example",schema:"dbo",detail:detail))}
    let procedure=node(.procedures),function=node(.functions)
    let enabled=node(.triggers,"SQL_TRIGGER, Enabled"),disabled=node(.triggers,"SQL_TRIGGER, Disabled")
    #expect(procedure.icon != function.icon)
    #expect(enabled.icon != disabled.icon)
    #expect(disabled.displayTitle == "Example" && disabled.triggerDisabled)
    #expect(enabled.displayTitle == "Example" && !enabled.triggerDisabled)
    for n in [procedure,function,enabled,disabled] {#expect(NSImage(systemSymbolName:n.icon,accessibilityDescription:nil) != nil)}
    let table=node(.tables),folder=TreeNode("Triggers",kind:.folder(.triggers),server:server,item:table.item)
    table.children=[folder];folder.children=[enabled,disabled]
    #expect(enabled.ownerObject === table)
    #expect(disabled.parent === folder)
    let properties=ObjectManagementUIFixture.catalog("SELECT t.parent_class_desc FROM sys.triggers t WHERE t.object_id=1006;")
    #expect(properties.results.first?.values.first?[0] == "TR_CustomersAudit")
    #expect(properties.results.first?.values.first?[1] == "Disabled")
  }
}
