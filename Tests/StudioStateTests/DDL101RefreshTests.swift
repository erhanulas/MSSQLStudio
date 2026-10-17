import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor private final class DDL101Recorder:NSObject {
  var changes:[[ModuleEditing.Change]]=[]
  @objc func receive(_ notification:Notification) {if let value=notification.userInfo?["changes"] as? [ModuleEditing.Change] {changes.append(value)}}
}

@MainActor @Suite(.serialized) struct DDL101RefreshTests {
  private func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
  @Test func ddlSeedsMissingSharedCatalogAndPublishesOneSnapshotToOlderTabsOnlyInItsDatabase() async throws {
    _=NSApplication.shared
    let folder=URL(fileURLWithPath:"/tmp/StudioDDL-open-tabs-\(UUID())");defer {try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("catalog.sqlite")),index=CatalogIndexService(index:disk),catalog=SQLCatalogService(index:disk)
    let server=ConnectedServer(profile:ServerProfile(),password:"",diskIndex:disk,objectIndexService:index,completionIndexService:catalog)
    server.online=false
    let old=QueryDocument(server:server,database:"master",title:"Older SQL"),writer=QueryDocument(server:server,database:"master",title:"DDL"),other=QueryDocument(server:server,database:"Other",title:"Other DB")
    old.sql="EXEC NewRoutine";old.catalogDatabase="master";old.catalogVerified=true
    let date=Date()
    old.intelligenceCatalog = .init(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"Keep",columns:["ID"],kind:"USER_TABLE")],synchronizedAt:date))
    let oldEditor=EditorController(document:old)
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false;state.servers=[server];state.documents=[old,writer,other];state.active=writer
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
    defer {server.online=false;window.close()}
    var reads=0,dropped=false
    server.asyncCatalogFixture={sql in
      reads+=1;#expect(sql.contains("StudioSchemaTargetRefresh"))
      var output=Execution();output.results=[Rows(values:dropped ? []:[["99","NewRoutine","dbo","SQL_STORED_PROCEDURE",nil,"0"]])];return output
    }
    server.online=true
    await host.refreshDDLChanges(ModuleEditing.changes("CREATE PROCEDURE dbo.NewRoutine AS SELECT 1;"),server:server,database:"master",indexService:index,catalogService:catalog)
    let updated=try #require(old.intelligenceCatalog)
    #expect(writer.intelligenceCatalog === updated && other.intelligenceCatalog == nil)
    #expect(updated.resolve(["Keep"]) != nil && updated.snapshot.synchronizedAt==date)
    #expect(try SQLIntelligence.analyze(source:old.sql,caret:old.sql.utf16.count,catalog:updated,verified:true).suggestions.contains {$0.text.contains("NewRoutine")})
    #expect(old.sql=="EXEC NewRoutine" && reads==1 && oldEditor.catalogAnalysisPending)
    let oldWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    oldWindow.isReleasedWhenClosed=false;oldWindow.contentView=oldEditor.surface
    defer {oldWindow.close()}
    oldWindow.makeFirstResponder(oldEditor.editor)
    oldEditor.refreshCatalogAnalysisIfNeeded()
    #expect(!oldEditor.catalogAnalysisPending && reads==1)
    dropped=true
    await host.refreshDDLChanges(ModuleEditing.changes("DROP PROCEDURE dbo.NewRoutine;"),server:server,database:"master",indexService:index,catalogService:catalog)
    #expect(old.intelligenceCatalog?.resolve(["NewRoutine"]) == nil && writer.intelligenceCatalog === old.intelligenceCatalog && reads==2)
  }
  @Test func editorDDLUpdatesOnlyItsObjectInExplorerDiskAndCompletionIncludingDropAndCreate() async throws {
    _=NSApplication.shared
    let folder=URL(fileURLWithPath:"/tmp/StudioDDL101-\(UUID())");defer {try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("catalog.sqlite")),index=CatalogIndexService(index:disk),catalog=SQLCatalogService(index:disk)
    let server=ConnectedServer(profile:ServerProfile(name:"Anonymous DDL"),password:"",diskIndex:disk,objectIndexService:index,completionIndexService:catalog);server.online=false
    let scope=CatalogDiskIndex.scope(profile:server.profile,database:"master"),at=Date()
    try await disk.append(scope:"stage",items:[.init(id:1,name:"News",schema:"dbo",detail:"USER_TABLE"),.init(id:2,name:"Keep",schema:"dbo",detail:"USER_TABLE")]);try await disk.finishBuild(staging:"stage",scope:scope)
    let snapshot=SQLCatalogSnapshot(symbols:[.init(schema:"dbo",name:"News",columns:["ID","Old"]),.init(schema:"dbo",name:"Keep",columns:["Unchanged"])],synchronizedAt:at)
    try await disk.saveCompletionSnapshot(scope:scope,snapshot:snapshot)
    for (id,name) in [(1,"News"),(2,"Keep")] {
      let table=TableDefinition(schema:"dbo",name:name,columns:[.init(id:1,name:"ID",type:"int")],primaryKey:["ID"])
      try await disk.saveEditingMetadata(ResultEditingSnapshot(objectID:id,table:table),scope:scope,fingerprint:name)
    }
    let doc=QueryDocument(server:server,database:"master",title:"DDL observer");doc.intelligenceCatalog = .init(snapshot:snapshot);doc.catalogDatabase="master";doc.catalogVerified=true
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false;state.servers=[server];state.documents=[doc];state.active=doc
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;defer {server.online=false;window.close()}
    let outline=try #require(views(host.view).compactMap {$0 as? NSOutlineView}.first),root=try #require(outline.item(atRow:0) as? TreeNode)
    let tables=TreeNode("Tables",kind:.folder(.tables),server:server,database:"master");tables.loaded=true
    let keep=TreeNode("dbo.Keep",kind:.object(.tables),server:server,database:"master",item:.init(id:2,name:"Keep",schema:"dbo",detail:"USER_TABLE"));keep.loaded=true
    tables.children=[TreeNode("dbo.News",kind:.object(.tables),server:server,database:"master",item:.init(id:1,name:"News",schema:"dbo",detail:"USER_TABLE")),keep];root.children=[tables]
    var reads:[String]=[],mode=0
    server.asyncCatalogFixture={sql in
      reads.append(sql);var result=Execution()
      result.results=[Rows(values:mode==0 ? [["1","News","dbo","USER_TABLE","ID","0"],["1","News","dbo","USER_TABLE","Title","0"]] : mode==1 ? []:[["501","Created","dbo","USER_TABLE","NewID","0"]])]
      return result
    };server.online=true
    await host.refreshDDLChanges(ModuleEditing.changes("ALTER TABLE dbo.News ADD Title nvarchar(100);"),server:server,database:"master",indexService:index,catalogService:catalog)
    #expect(doc.intelligenceCatalog?.resolve(["dbo","News"])?.columns==["ID","Title"])
    #expect(try await disk.editingMetadata(scope:scope,fingerprint:"News")==nil)
    #expect(try await disk.editingMetadata(scope:scope,fingerprint:"Keep")?.objectID==2)
    #expect(doc.intelligenceCatalog?.snapshot.synchronizedAt==at && doc.intelligenceCatalog?.resolve(["dbo","Keep"])?.columns==["Unchanged"])
    mode=1
    await host.refreshDDLChanges(ModuleEditing.changes("DROP TABLE dbo.News;"),server:server,database:"master",indexService:index,catalogService:catalog)
    #expect(doc.intelligenceCatalog?.resolve(["dbo","News"])==nil && tables.children.count==1 && tables.children.first === keep)
    mode=2
    await host.refreshDDLChanges(ModuleEditing.changes("CREATE TABLE dbo.Created(NewID int);"),server:server,database:"master",indexService:index,catalogService:catalog)
    #expect(doc.intelligenceCatalog?.resolve(["dbo","Created"])?.columns==["NewID"])
    #expect(tables.children.contains {$0.item?.name=="Created"} && keep.loaded)
    #expect(try await disk.search(scope:scope,text:"",operation:0,folder:.tables).map(\.name).sorted()==["Created","Keep"])
    #expect(reads.count==3 && reads.allSatisfy {$0.contains("StudioSchemaTargetRefresh")} && server.indexingDatabases.isEmpty)
  }
  @Test func unqualifiedNameUsesServerResolutionAndDroppedNameChecksBothDefaultAndDbo() async throws {
    _=NSApplication.shared
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(name:"Anonymous default schema"),password:"");server.online=false;state.servers=[server]
    let host=WorkbenchController(state:state);_=host.view
    let folder=URL(fileURLWithPath:"/tmp/StudioDDLDefault101-\(UUID())");defer {server.online=false;try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("catalog.sqlite")),index=CatalogIndexService(index:disk),catalog=SQLCatalogService(index:disk)
    var reads:[String]=[],dropped=false
    server.asyncCatalogFixture={sql in
      reads.append(sql);var result=Execution()
      result.results=[Rows(values:sql.contains("StudioDDLDefaultSchema") ? [["audit",dropped ? nil:"dbo"]]:[])]
      return result
    };server.online=true
    await host.refreshDDLChanges(ModuleEditing.changes("ALTER TABLE News ADD X int;"),server:server,database:"master",indexService:index,catalogService:catalog)
    #expect(reads.count==2 && reads.last?.contains("s.name=N'dbo'")==true)
    reads=[];dropped=true
    await host.refreshDDLChanges(ModuleEditing.changes("DROP TABLE News;"),server:server,database:"master",indexService:index,catalogService:catalog)
    #expect(reads.count==3 && reads[1].contains("s.name=N'audit'") && reads[2].contains("s.name=N'dbo'"))
  }
  @Test func failedSessionProbeDefersDDLUntilAVerifiedSessionRead() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Probe fixture");doc.state = .ready
    doc.executionFixture={_,_ in Execution()}
    var fail=true
    doc.sessionProbeFixture={_,_ in
      if fail {throw SQLFailure("Synthetic session probe timeout")}
      var result=Execution();result.results=[Rows(values:[["0","master"]])];return result
    }
    let observer=DDL101Recorder();NotificationCenter.default.addObserver(observer,selector:#selector(DDL101Recorder.receive(_:)),name:.init("studioDDLCompleted"),object:doc)
    defer {NotificationCenter.default.removeObserver(observer)}
    doc.sql="ALTER TABLE dbo.News ADD Title int;";doc.execute()
    for _ in 0..<200 where doc.task != nil {try await Task.sleep(for:.milliseconds(5))}
    #expect(observer.changes.isEmpty)
    fail=false;doc.sql="SELECT 1;";doc.execute()
    for _ in 0..<200 where doc.task != nil {try await Task.sleep(for:.milliseconds(5))}
    #expect(observer.changes.count==1 && observer.changes.first?.first?.name=="News")
  }
  @Test func transactionalDDLWaitsForCommitOrRollbackAndPreservesItsOriginalDatabase() async throws {
    for ending in ["COMMIT;","ROLLBACK;"] {
      let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
      let doc=QueryDocument(server:server,database:"FirstDB",title:"Transaction fixture");doc.state = .ready
      doc.executionFixture={_,_ in Execution()}
      var probes=0
      doc.sessionProbeFixture={_,_ in probes+=1;var result=Execution();result.results=[Rows(values:[[probes==1 ? "1":"0",probes==1 ? "FirstDB":"SecondDB"]])];return result}
      let observer=DDL101Recorder();NotificationCenter.default.addObserver(observer,selector:#selector(DDL101Recorder.receive(_:)),name:.init("studioDDLCompleted"),object:doc)
      defer {NotificationCenter.default.removeObserver(observer)}
      doc.sql="CREATE TABLE dbo.NewObject(ID int);";doc.execute()
      for _ in 0..<200 where doc.task != nil {try await Task.sleep(for:.milliseconds(5))}
      #expect(observer.changes.isEmpty && doc.transactionCount==1)
      doc.database="SecondDB";doc.sql=ending;doc.execute()
      for _ in 0..<200 where doc.task != nil {try await Task.sleep(for:.milliseconds(5))}
      #expect(observer.changes.count==1 && observer.changes.first?.first?.name=="NewObject" && observer.changes.first?.first?.database=="FirstDB")
    }
  }
  @Test func indexDDLRefreshesExpandedOwnerFoldersWithoutReplacingThemOrPublishingAnOldRead() async throws {
    _=NSApplication.shared
    let url=URL(fileURLWithPath:"/tmp/StudioDDL-index-owner-\(UUID())");defer {try? FileManager.default.removeItem(at:url)}
    let disk=CatalogDiskIndex(url:url.appendingPathComponent("catalog.sqlite")),index=CatalogIndexService(index:disk),catalog=SQLCatalogService(index:disk)
    let server=ConnectedServer(profile:.init(),password:"",diskIndex:disk,objectIndexService:index,completionIndexService:catalog);server.online=false
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false;state.servers=[server]
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
    defer {server.online=false;window.close()}
    let outline=try #require(views(host.view).compactMap {$0 as? NSOutlineView}.first)
    let root=try #require(outline.item(atRow:0) as? TreeNode)
    let tables=TreeNode("Tables",kind:.folder(.tables),server:server,database:"master");tables.loaded=true
    let table=TreeNode("dbo.News",kind:.object(.tables),server:server,database:"master",item:.init(id:1,name:"News",schema:"dbo",detail:"USER_TABLE"));table.loaded=true
    let indexes=TreeNode("Indexes",kind:.folder(.indexes),server:server,database:"master",item:table.item);indexes.loaded=true
    indexes.children=[TreeNode("Old",kind:.object(.indexes),server:server,database:"master",item:.init(id:1,name:"Old"))]
    table.children=[indexes];tables.children=[table];root.children=[tables];root.loaded=true
    outline.reloadData();for node in [root,tables,table,indexes] {outline.expandItem(node)}
    var reads=0,continuation:CheckedContinuation<Execution,Never>?
    server.asyncCatalogFixture={sql in
      var output=Execution()
      if sql.contains("StudioSchemaTargetRefresh") {output.results=[Rows(values:[["1","News","dbo","USER_TABLE","ID","0"]])];return output}
      #expect(sql.contains("sys.indexes"));reads+=1
      if reads==1 {return await withCheckedContinuation {continuation=$0}}
      output.results=[Rows(values:[["2","NewIndex","","NONCLUSTERED"]])];return output
    };server.online=true
    indexes.loaded=false;host.load(indexes)
    for _ in 0..<100 where continuation==nil {try await Task.sleep(for:.milliseconds(2))}
    #expect(continuation != nil)
    await host.refreshDDLChanges(ModuleEditing.changes("DROP INDEX Old ON dbo.News; CREATE NONCLUSTERED INDEX NewIndex ON dbo.News(ID);"),server:server,database:"master",indexService:index,catalogService:catalog)
    #expect(table.children.first === indexes && outline.isItemExpanded(indexes) && indexes.refreshAfterLoad && reads==1)
    var stale=Execution();stale.results=[Rows(values:[["1","Old","","NONCLUSTERED"]])];continuation?.resume(returning:stale);continuation=nil
    for _ in 0..<100 where indexes.loading {try await Task.sleep(for:.milliseconds(2))}
    #expect(reads==2 && indexes.loaded && !indexes.refreshAfterLoad)
    #expect(indexes.children.map {$0.item?.name}==["NewIndex"] && outline.isItemExpanded(indexes))
  }

  @Test func principalChangesRefreshOnlyTheirLoadedCatalogBranches() async throws {
    _=NSApplication.shared
    let url=URL(fileURLWithPath:"/tmp/StudioDDL-principals-\(UUID())");defer {try? FileManager.default.removeItem(at:url)}
    let disk=CatalogDiskIndex(url:url.appendingPathComponent("catalog.sqlite")),index=CatalogIndexService(index:disk),catalog=SQLCatalogService(index:disk)
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false;state.servers=[server]
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;defer {server.online=false;window.close()}
    let outline=try #require(views(host.view).compactMap {$0 as? NSOutlineView}.first),root=try #require(outline.item(atRow:0) as? TreeNode)
    let users=TreeNode("Users",kind:.folder(.users),server:server,database:"master");users.loaded=true
    let other=TreeNode("Users",kind:.folder(.users),server:server,database:"Other");other.loaded=true
    let logins=TreeNode("Logins",kind:.folder(.logins),server:server,database:"Other");logins.loaded=true
    let roles=TreeNode("Roles",kind:.folder(.roles),server:server,database:"Other");roles.loaded=true
    roles.children=[TreeNode("Ops",kind:.object(.roles),server:server,item:.init(id:12,name:"Ops"))]
    root.children=[users,other,logins,roles]
    var reads:[String]=[]
    server.asyncCatalogFixture={sql in
      reads.append(sql);#expect(sql.contains("StudioSchemaTargetRefresh"));var output=Execution()
      output.results=[Rows(values:sql.contains("N'Ops'") ? []:[["10",sql.contains("sys.database_principals") ? "NewUser":"AppLogin","","SQL_USER",nil,"0"]])];return output
    };server.online=true
    await host.refreshDDLChanges(ModuleEditing.changes("CREATE USER NewUser FOR LOGIN AppLogin; ALTER LOGIN AppLogin ENABLE; DROP SERVER ROLE Ops;"),server:server,database:"master",indexService:index,catalogService:catalog)
    #expect(reads.count==3 && users.children.first?.item?.name=="NewUser" && other.children.isEmpty)
    #expect(logins.children.first?.item?.name=="AppLogin" && roles.children.isEmpty)
  }

}
