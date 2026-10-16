import AppKit
import Testing
@testable import MSSQLStudio
@testable import SQLServerKit

private actor EditorCatalogReadCounter {
  var counts:[String:Int]=[:]
  func read(_ database:String)->SQLCatalogSnapshot {
    counts[database,default:0]+=1
    return .init(symbols:[.init(schema:"dbo",name:"Example",columns:[],kind:"SQL_STORED_PROCEDURE")])
  }
}
@MainActor @Suite(.serialized) struct EditorConnectionSynchronizationTests {
  private func wait(_ condition:()->Bool) async throws {
    for _ in 0..<400 where !condition() {try await Task.sleep(for:.milliseconds(5))}
    #expect(condition())
  }
  @Test func explorerReconnectRefreshesRecoveredTabsOncePerDatabaseWithoutQuerySessions() async throws {
    let folder=URL(fileURLWithPath:"/tmp/EditorConnection-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("index.sqlite")),counter=EditorCatalogReadCounter()
    let service=SQLCatalogService(index:disk,refreshFixture:{_,_,db in await counter.read(db)})
    let server=ConnectedServer(profile:ServerProfile(visibleDatabases:["Demo","Other"]),password:"",diskIndex:disk,completionIndexService:service)
    server.online=false;server.reconnectFixture={}
    let state=StudioState();state.servers=[server];state.recoveryEnabled=true
    let saved=(0..<8).map {index in StudioState.SavedTab(title:"Recovered \(index)",sql:"EXEC dbo.Example; -- \(index)",saved:"",path:nil,serverID:server.id,database:index==7 ? "Other":"Demo",endpoint:nil)}
    state.recover(for:[server],tabs:saved)
    let active=state.active
    await state.reconnectExplorer(server)
    try await wait {state.documents.allSatisfy {$0.intelligenceCatalog?.resolve(["dbo","Example"]) != nil} && state.editorCatalogTasks.isEmpty}
    #expect(server.online && state.active === active && state.documents.count==8)
    #expect(state.documents.allSatisfy {$0.state == .disconnected && $0.task==nil && $0.offlinePreview==nil && $0.catalogVerified})
    #expect(state.documents.map(\.sql)==saved.map(\.sql))
    let counts=await counter.counts
    #expect(counts==["Demo":1,"Other":1])
  }
  @Test func queryConnectionReconnectsExplorerAndRefreshesOtherTabs() async throws {
    let folder=URL(fileURLWithPath:"/tmp/QueryConnection-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("index.sqlite")),counter=EditorCatalogReadCounter()
    let service=SQLCatalogService(index:disk,refreshFixture:{_,_,db in await counter.read(db)})
    let server=ConnectedServer(profile:ServerProfile(visibleDatabases:["Demo"]),password:"",diskIndex:disk,completionIndexService:service)
    server.online=false;var reconnects=0;server.reconnectFixture={reconnects+=1}
    let state=StudioState();state.servers=[server];state.recoveryEnabled=false
    let first=state.newQuery(server:server,database:"Demo",text:"EXEC Example;")
    let second=state.newQuery(server:server,database:"Demo",text:"SELECT 1;")
    first.connected?()
    try await wait {server.online && second.intelligenceCatalog?.resolve(["Example"]) != nil && state.editorCatalogTasks.isEmpty}
    #expect(reconnects==1 && state.active === second)
    #expect(first.state == .disconnected && second.state == .disconnected)
    #expect(first.sql=="EXEC Example;" && second.sql=="SELECT 1;")
  }
  @Test func onlineNamedNavigationLoadsMissingCatalogAndOpensLiveDefinitionWithoutExecuting() async throws {
    _=NSApplication.shared
    let folder=URL(fileURLWithPath:"/tmp/EditorNavigation-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("index.sqlite"))
    let service=SQLCatalogService(index:disk,refreshFixture:{_,_,_ in .init(symbols:[.init(schema:"dbo",name:"Example",columns:[],kind:"SQL_STORED_PROCEDURE")])})
    let server=ConnectedServer(profile:ServerProfile(visibleDatabases:["Demo"]),password:"",diskIndex:disk,completionIndexService:service)
    server.online=false
    server.catalogFixture={sql in var result=Execution();result.results=[Rows(values:[[sql.contains("SELECT object_id") ? "42":"CREATE PROCEDURE dbo.Example AS SELECT 1;"]])];return result}
    let state=StudioState();state.servers=[server];state.recoveryEnabled=false
    let source=state.newQuery(server:server,database:"Demo",text:"EXEC dbo.Example;")
    let host=WorkbenchController(state:state);_=host.view
    server.online=true
    host.openDefinitionReference(["Example"],document:source)
    try await wait {state.documents.count==2 && state.active?.definitionLoading==false}
    let target=try #require(state.active)
    #expect(target !== source && target.sql.contains("ALTER PROCEDURE"))
    #expect(source.offlinePreview==nil && source.sql=="EXEC dbo.Example;" && source.state == .disconnected && source.task==nil)
    #expect(target.state == .disconnected && target.task==nil)
  }
  @Test func staleOfflineLookupCannotOpenPreviewAfterExplorerBecomesOnline() async throws {
    _=NSApplication.shared
    let state=StudioState();state.recoveryEnabled=false
    let folder=URL(fileURLWithPath:"/tmp/OfflineRace-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("index.sqlite"))
    let server=ConnectedServer(profile:ServerProfile(visibleDatabases:["Demo"]),password:"",diskIndex:disk,completionIndexService:SQLCatalogService(index:disk,refreshFixture:{_,_,_ in .init(symbols:[])}))
    server.online=false;state.servers=[server]
    let doc=state.newQuery(server:server,database:"Demo",text:"EXEC dbo.Example;")
    var errors=0;state.errorFixture={_ in errors+=1}
    let host=WorkbenchController(state:state)
    host.openOfflineDefinition(named:["Example"],server:server,database:"Demo",in:doc)
    server.online=true
    try await Task.sleep(for:.milliseconds(100))
    #expect(doc.offlinePreview==nil && errors==0 && doc.sql=="EXEC dbo.Example;")
  }
}
