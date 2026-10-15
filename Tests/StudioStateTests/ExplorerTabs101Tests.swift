import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ExplorerTabs101Tests {
  private func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
  @Test func foldersRestoreOfflineAndDragMovesConnectionsWithoutLosingExpansionIdentity() throws {
    _=NSApplication.shared
    let suite="StudioFolders-\(UUID())",defaults=try #require(UserDefaults(suiteName:suite));defer {defaults.removePersistentDomain(forName:suite)}
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false;state.explorerTreeDefaults=defaults
    let a=ConnectedServer(profile:ServerProfile(name:"Offline A"),password:""),b=ConnectedServer(profile:ServerProfile(name:"Offline B"),password:"")
    a.online=false;b.online=false;state.servers=[a,b]
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;defer {window.close()}
    let outline=try #require(views(host.view).compactMap {$0 as? NSOutlineView}.first)
    let original=try #require(outline.item(atRow:0) as? TreeNode),key=original.persistenceKey
    var parent:UUID!,child:UUID!
    try state.changeExplorerOrganization {parent=try $0.create("Production");child=try $0.create("Reports",parent:parent);try $0.assign(a.id,to:child);try $0.setColor(parent,hex:"238B65")}
    let folder=try #require(outline.item(atRow:0) as? TreeNode)
    #expect(folder.connectionGroupID==parent && folder.children.first?.connectionGroupID==child)
    #expect(original.persistenceKey==key && original.server === a && !a.online && !b.online)
    #expect(host.explorerGroupDrop(sourceID:b.id,item:folder,childIndex:NSOutlineViewDropOnItemIndex,apply:true))
    #expect(state.explorerOrganization.assignments[b.id]==parent && state.servers.count==2)
    let restored=StudioState();restored.explorerTreeDefaults=defaults
    #expect(restored.explorerOrganization == state.explorerOrganization)
    try state.changeExplorerOrganization {try $0.remove(parent)}
    #expect(state.servers.map(\.id)==[a.id,b.id] && state.explorerOrganization.assignments[b.id]==nil)
    #expect(a.profile.name=="Offline A" && a.generation==original.generation)
  }
  @Test func offlineProfileRenameAndEndpointEditingNeverRequireAConnection() async throws {
    let url=URL(fileURLWithPath:"/tmp/OfflineProfile-"+UUID().uuidString).appendingPathComponent("index.sqlite")
    defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url)
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(name:"Offline",host:"offline.invalid"),password:"",diskIndex:disk,objectIndexService:CatalogIndexService(index:disk),completionIndexService:SQLCatalogService(index:disk))
    server.online=false;state.servers=[server];state.historyEnabled=false;state.recoveryEnabled=false
    let doc=QueryDocument(server:server,database:"master",title:"Keep SQL");doc.sql="SELECT N'local draft';";doc.state = .ready;state.documents=[doc]
    let generation=server.generation
    var renamed=server.profile;renamed.name="Renamed"
    try await state.saveConnectionProfile(server,profile:renamed,password:"",remember:false)
    #expect(server.profile.name=="Renamed" && !server.online && server.generation==generation && doc.state == .ready)
    renamed.host="new-offline.invalid"
    try await state.saveConnectionProfile(server,profile:renamed,password:"",remember:false)
    #expect(server.profile.host=="new-offline.invalid" && !server.online && server.generation != generation)
    #expect(doc.state == .disconnected && doc.sql=="SELECT N'local draft';" && !server.updatingProfile)
  }
  @Test func failedProfilePersistenceRestoresQueryStateAndKeepsOriginalSettings() async throws {
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(name:"Original"),password:"");server.online=false;server.remembered=true;state.servers=[server]
    let doc=QueryDocument(server:server,database:"master",title:"Preserved");doc.state = .ready;state.documents=[doc]
    state.profilePersistenceFixture={_,_ in #expect(doc.state == .connecting);throw SQLFailure("Anonymous persistence failure")}
    var changed=server.profile;changed.host="offline.invalid"
    do {try await state.saveConnectionProfile(server,profile:changed,password:"",remember:false);Issue.record("Persistence must fail")} catch {}
    #expect(server.profile.name=="Original" && server.profile.host=="localhost" && !server.updatingProfile && doc.state == .ready)
  }
  @Test func explicitDiscardAllClosesDirtyPinnedAndDetachedTabsWithoutPerDocumentPrompts() async throws {
    _=NSApplication.shared
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false;state.servers=[server];state.recoveryEnabled=false
    let host=WorkbenchController(state:state);_=host.view
    let docs=(0..<3).map {state.newQuery(server:server,text:"SELECT \($0)",title:"Discard fixture \($0)")}
    var prompts=0
    for doc in docs {doc.sql+="; -- unsaved";doc.confirmDiscardResultEdits={prompts+=1;return false}}
    docs[1].pinned=true;state.active=docs[1];host.detachQuery()
    let detached=NSApp.windows.first {$0.title==docs[1].title && $0.isVisible}
    let menu=host.tabMenu(for:docs[0]);#expect(!menu.items.contains {$0.title=="Tümünü Kaydetmeden Kapat"})
    let item=try #require(menu.items.first {$0.title=="Close All Tabs"})
    #expect(NSApp.sendAction(try #require(item.action),to:item.target,from:item))
    for _ in 0..<100 where !NSApp.windows.contains(where:{$0.identifier?.rawValue=="studio.bulkClose" && $0.isVisible}) {await Task.yield()}
    let prompt=try #require(NSApp.windows.first {$0.identifier?.rawValue=="studio.bulkClose" && $0.isVisible}?.windowController as? StudioCloseWindowController)
    prompt.discardAll()
    #expect(prompts==0 && state.documents.isEmpty && state.active==nil && detached?.isVisible != true)
  }
  @Test func closeIconHasAHitAreaHoverFeedbackAndNormalCloseStillChecksDrafts() throws {
    _=NSApplication.shared
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false;state.servers=[server]
    let doc=state.newQuery(server:server,text:"SELECT 1",title:"Close fixture")
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;defer {window.close()}
    host.view.layoutSubtreeIfNeeded()
    let button=try #require(views(host.view).compactMap {$0 as? QueryTabCloseButton}.first)
    #expect(button.bounds.width>=24 && button.bounds.height>=24 && button.toolTip?.contains("Close fixture")==true)
    let event=try #require(NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,trackingNumber:1,userData:nil))
    button.mouseEntered(with:event);#expect(button.hovered && button.contentTintColor==StudioTheme.danger)
    button.mouseExited(with:event);#expect(!button.hovered && button.contentTintColor==NSColor.labelColor)
    var prompts=0;doc.sql+=" -- draft";doc.confirmDiscardResultEdits={prompts+=1;return false}
    button.performClick(nil)
    #expect(prompts==1 && state.documents.first === doc && doc.needsCloseConfirmation)
    #expect(doc.state == .disconnected)
  }
}
