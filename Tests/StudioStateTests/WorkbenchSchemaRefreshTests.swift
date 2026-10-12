import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor struct WorkbenchSchemaRefreshTests {
  private func cacheURL()->URL {URL(fileURLWithPath:"/tmp/StudioWorkbenchSchemaRefresh-"+UUID().uuidString).appendingPathComponent("catalog.sqlite")}
  @Test func comparedObjectRefreshKeepsUnrelatedExplorerBranchesAndUsesOneScopedRead() async throws {
    _=NSApplication.shared
    let cache=cacheURL(),disk=CatalogDiskIndex(url:cache)
    defer {try? FileManager.default.removeItem(at:cache.deletingLastPathComponent())}
    let indexService=CatalogIndexService(index:disk),catalogService=SQLCatalogService(index:disk)
    let state=StudioState(),server=SchemaComparisonUIFixture.server()
    defer {state.changed=nil}
    server.online=false;state.servers=[server]
    let controller=WorkbenchController(state:state);_=controller.view
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let outline=try #require(descendants(controller.view).compactMap {$0 as? NSOutlineView}.first)
    let root=try #require(outline.item(atRow:0) as? TreeNode)
    let db=TreeNode("TargetDB",kind:.database,server:server,database:"TargetDB")
    let folder=TreeNode("Tables",kind:.folder(.tables),server:server,database:"TargetDB")
    let changed=TreeNode("dbo.Customers",kind:.object(.tables),server:server,database:"TargetDB",item:.init(id:106,name:"Customers",schema:"dbo",detail:"USER_TABLE"))
    let unrelated=TreeNode("dbo.Unrelated",kind:.object(.tables),server:server,database:"TargetDB",item:.init(id:200,name:"Unrelated",schema:"dbo",detail:"USER_TABLE"))
    let child=TreeNode("Preserved",kind:.detail,server:server,database:"TargetDB")
    unrelated.children=[child];unrelated.loaded=true;changed.loaded=true
    folder.children=[changed,unrelated];folder.loaded=true;db.children=[folder];db.loaded=true;root.children=[db]
    var reads:[String]=[]
    server.asyncCatalogFixture={sql in
      reads.append(sql)
      var result=Execution();result.results=[Rows(values:[["106","Customers","dbo","USER_TABLE","CustomerID","0"],["106","Customers","dbo","USER_TABLE","City","0"]])]
      return result
    }
    server.online=true
    await controller.refreshComparedObject(server:server,database:"TargetDB",key:.init(schema:"dbo",name:"Customers"),type:"U",indexService:indexService,catalogService:catalogService)
    #expect(reads.count==1 && reads[0].contains("StudioSchemaTargetRefresh"))
    #expect(reads[0].contains("s.name=N'dbo'") && reads[0].contains("o.name=N'Customers'"))
    #expect(root.children.first === db && db.children.first === folder)
    #expect(folder.children.count==2 && folder.children.contains {$0 === changed})
    #expect(unrelated.loaded && unrelated.children.first === child)
    #expect(!changed.loaded && server.indexingDatabases.isEmpty)
    if let path=ProcessInfo.processInfo.environment["MSSQL_SCHEMA_SQL_DUMP"] {try reads[0].write(toFile:path+".observer.sql",atomically:true,encoding:.utf8)}
  }
  @Test func databaseTriggerRefreshUsesTriggerIdentityWithoutWholeDatabaseIndexing() async throws {
    _=NSApplication.shared
    let cache=cacheURL(),disk=CatalogDiskIndex(url:cache)
    defer {try? FileManager.default.removeItem(at:cache.deletingLastPathComponent())}
    let indexService=CatalogIndexService(index:disk),catalogService=SQLCatalogService(index:disk)
    let state=StudioState(),server=SchemaComparisonUIFixture.server();server.online=false;state.servers=[server]
    defer {state.changed=nil}
    let controller=WorkbenchController(state:state);_=controller.view
    var reads:[String]=[]
    server.asyncCatalogFixture={sql in
      reads.append(sql)
      var result=Execution();result.results=[Rows(values:[["501","AuditDDL","","SQL_TRIGGER Disabled",nil,"0"]])];return result
    }
    server.online=true
    await controller.refreshComparedObject(server:server,database:"TargetDB",key:.init(schema:"",name:"AuditDDL",databaseTrigger:true),type:"TRD",indexService:indexService,catalogService:catalogService)
    #expect(reads.count==1 && reads[0].contains("sys.triggers") && reads[0].contains("parent_class=0"))
    #expect(!reads[0].contains("JOIN sys.schemas") && server.indexingDatabases.isEmpty)
    if let path=ProcessInfo.processInfo.environment["MSSQL_SCHEMA_SQL_DUMP"] {try reads[0].write(toFile:path+".trigger-observer.sql",atomically:true,encoding:.utf8)}
  }
}
