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
}
