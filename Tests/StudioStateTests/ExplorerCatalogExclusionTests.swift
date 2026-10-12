import Foundation
import Testing
@testable import MSSQLStudio
@testable import SQLServerKit

private actor ExplorerIndexCalls {
  private(set) var databases:[String]=[]
  func add(_ value:String) {databases.append(value)}
}
private actor ExplorerCompletionGate {
  private var continuation:CheckedContinuation<Void,Never>?
  private(set) var started=false
  func wait() async {started=true;await withCheckedContinuation {continuation=$0}}
  func release() {continuation?.resume();continuation=nil}
}

@MainActor struct ExplorerCatalogExclusionTests {
  private func location()->URL {URL(fileURLWithPath:"/tmp/StudioExplorerExclusion-"+UUID().uuidString).appendingPathComponent("index.sqlite")}
  @Test func persistedExclusionsCleanOnlyHiddenAccessibleScopesAndLeaveOpenQueryUntouched() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url)
    var profile=ServerProfile();profile.database="Keep";profile.visibleDatabases=["Keep"]
    let objects=CatalogIndexService(index:disk),completion=SQLCatalogService(index:disk)
    let server=ConnectedServer(profile:profile,password:"unused",diskIndex:disk,objectIndexService:objects,completionIndexService:completion)
    let available=[CatalogItem(id:1,name:"Keep"),CatalogItem(id:2,name:"Hidden")]
    server.databases=profile.visibleItems(from:available)
    for database in ["Keep","Hidden"] {
      let scope=CatalogDiskIndex.scope(profile:profile,database:database)
      try await disk.append(scope:scope+":seed",items:[CatalogItem(id:1,name:database,schema:"dbo",detail:"VIEW")])
      try await disk.finishBuild(staging:scope+":seed",scope:scope)
      try await disk.saveCompletionSnapshot(scope:scope,snapshot:.init(symbols:[.init(schema:"dbo",name:database,columns:[])]))
    }
    let doc=QueryDocument(server:server,database:"Hidden",title:"Existing.sql")
    doc.sql="SELECT 1;";doc.state = .ready;doc.transactionCount=1
    let queryConnection=doc.connection,metadata=server.metadata,generation=server.generation
    server.indexingDatabases=["Hidden"];server.indexErrors=["Hidden":"Old error"]
    await server.synchronizeCatalogVisibility(available:available)
    let reopened=CatalogDiskIndex(url:url)
    let hidden=CatalogDiskIndex.scope(profile:profile,database:"Hidden"),keep=CatalogDiskIndex.scope(profile:profile,database:"Keep")
    #expect(try await reopened.status(scope:hidden)==nil)
    #expect(try await reopened.completionSnapshot(scope:hidden)==nil)
    #expect(try await reopened.status(scope:keep)?.count==1)
    #expect(server.indexingDatabases.isEmpty && server.indexErrors["Hidden"]==nil)
    #expect(!server.allowsCatalogIndex("Hidden") && server.allowsCatalogIndex("Keep"))
    // An existing hidden-database tab remains executable, but no longer creates
    // a background completion index. No real/shared cache or connection is used.
    await doc.loadSymbols(force:true)
    #expect(doc.catalogDatabase==nil && doc.symbols.isEmpty && doc.catalogError==nil)
    #expect(doc.connection === queryConnection && server.metadata === metadata && server.generation==generation)
    #expect(doc.state == .ready && doc.transactionCount==1 && doc.database=="Hidden" && doc.sql=="SELECT 1;")
  }
  @Test func removedDatabaseIsCleanedEvenWhenAbsentFromNewAccessibleListAndReincludeAllowsRebuild() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url)
    var original=ServerProfile();original.database="Keep";original.visibleDatabases=["Keep","Gone"]
    let server=ConnectedServer(profile:original,password:"unused",diskIndex:disk,objectIndexService:CatalogIndexService(index:disk),completionIndexService:SQLCatalogService(index:disk))
    let previous=[CatalogItem(id:1,name:"Keep"),CatalogItem(id:2,name:"Gone")]
    let removed=CatalogDiskIndex.scope(profile:original,database:"Gone")
    try await disk.finishBuild(staging:removed+":empty",scope:removed)
    let old=try await disk.generation(scope:removed)
    server.profile.visibleDatabases=["Keep"]
    await server.synchronizeCatalogVisibility(available:[previous[0]],previousProfile:original,previousDatabases:previous)
    #expect(try await CatalogDiskIndex(url:url).status(scope:removed)==nil)
    server.profile.visibleDatabases=["Keep","Gone"]
    await server.synchronizeCatalogVisibility(available:previous)
    let fresh=try await disk.generation(scope:removed)
    #expect(old != fresh && server.allowsCatalogIndex("Gone"))
    #expect(try await disk.status(scope:removed)==nil)
    try await disk.append(scope:removed+":new",items:[CatalogItem(id:10,name:"New",schema:"dbo",detail:"VIEW")],targetScope:removed,generation:fresh)
    try await disk.finishBuild(staging:removed+":new",scope:removed,generation:fresh)
    #expect(try await disk.status(scope:removed)?.count==1)
  }
  @Test func backgroundPreparationSkipsHiddenDatabaseEvenInStaleExplorerList() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),calls=ExplorerIndexCalls()
    var profile=ServerProfile();profile.database="Keep";profile.visibleDatabases=["Keep"]
    let objects=CatalogIndexService(index:disk,refreshFixture:{_,_,database in
      await calls.add("objects:"+database);return []
    })
    let completion=SQLCatalogService(index:disk,refreshFixture:{_,_,database in
      await calls.add("completion:"+database);return .init(symbols:[])
    })
    let server=ConnectedServer(profile:profile,password:"unused",diskIndex:disk,objectIndexService:objects,completionIndexService:completion)
    server.databases=[CatalogItem(id:1,name:"Hidden"),CatalogItem(id:2,name:"Keep")]
    server.prepareCatalogIndexes(force:true)
    let deadline=ContinuousClock.now.advanced(by:.seconds(2))
    while (await calls.databases.count<2 || !server.indexingDatabases.isEmpty),ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(5))}
    server.pauseIndexing()
    #expect(await calls.databases==["objects:Keep","completion:Keep"])
    #expect(server.indexErrors.isEmpty && server.indexingDatabases.isEmpty)
    #expect(try await disk.status(scope:CatalogDiskIndex.scope(profile:profile,database:"Hidden"))==nil)
    #expect(try await disk.status(scope:CatalogDiskIndex.scope(profile:profile,database:"Keep"))?.count==0)
  }
  @Test func supersededVisibilityCleanupCannotExcludeNewlyReincludedDatabase() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),exclusionGate=ExplorerCompletionGate(),calls=ExplorerIndexCalls()
    var profile=ServerProfile();profile.visibleDatabases=["Hidden","Keep"]
    let scope=CatalogDiskIndex.scope(profile:profile,database:"Hidden")
    let initialGeneration=try await disk.generation(scope:scope)
    try await disk.finishBuild(staging:scope+":seed",scope:scope)
    try await disk.saveCompletionSnapshot(scope:scope,snapshot:.init(symbols:[.init(schema:"dbo",name:"Old",columns:[])]))
    let objects=CatalogIndexService(index:disk,refreshFixture:{_,_,database in
      await calls.add("objects:"+database)
      return [CatalogItem(id:10,name:"New",schema:"dbo",detail:"VIEW")]
    },exclusionFixture:{await exclusionGate.wait()})
    let completion=SQLCatalogService(index:disk,refreshFixture:{_,_,database in
      await calls.add("completion:"+database)
      return .init(symbols:[.init(schema:"dbo",name:"New",columns:[])])
    })
    #expect(try await completion.cached(profile:profile,database:"Hidden")?.snapshot.symbols.first?.name=="Old")
    let server=ConnectedServer(profile:profile,password:"unused",diskIndex:disk,objectIndexService:objects,completionIndexService:completion)
    let available=[CatalogItem(id:1,name:"Hidden"),CatalogItem(id:2,name:"Keep")]
    server.databases=available
    server.profile.visibleDatabases=["Keep"]
    let old=Task {await server.synchronizeCatalogVisibility(available:available)}
    let deadline=ContinuousClock.now.advanced(by:.seconds(2))
    while !(await exclusionGate.started),ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(5))}
    #expect(await exclusionGate.started)
    // Hold the old operation at the service actor entry, before its disk hop.
    // The reinclude must remain queued until both old service evictions finish.
    let oldRevision=server.catalogIndexRevision
    server.profile.visibleDatabases=["Hidden","Keep"]
    var latestFinished=false
    let latest=Task {await server.synchronizeCatalogVisibility(available:available);latestFinished=true}
    while server.catalogIndexRevision==oldRevision,ContinuousClock.now<deadline {await Task.yield()}
    #expect(server.catalogIndexRevision != oldRevision && !latestFinished)
    server.prepareCatalogIndexes(force:true)
    #expect(await calls.databases.isEmpty)
    await exclusionGate.release()
    await old.value;await latest.value
    #expect(latestFinished && server.allowsCatalogIndex("Hidden") && server.indexErrors.isEmpty)
    let generation=try await disk.generation(scope:scope)
    #expect(generation != initialGeneration)
    #expect(try await disk.status(scope:scope)==nil)
    #expect(try await completion.cached(profile:profile,database:"Hidden")==nil)
    #expect(try await objects.refresh(profile:profile,password:"unused",database:"Hidden",force:true).count==1)
    #expect(try await completion.refresh(profile:profile,password:"unused",database:"Hidden",force:true).snapshot.symbols.first?.name=="New")
    #expect(try await disk.search(scope:scope,text:"",operation:0,folder:nil).map(\.name)==["New"])
  }
  @Test func obsoleteCompletionPublicationAndCancellationDoNotAlterOpenQueryAfterExcludeAndReadd() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),gate=ExplorerCompletionGate()
    var profile=ServerProfile();profile.visibleDatabases=["Hidden","Keep"]
    let completion=SQLCatalogService(index:disk,refreshFixture:{_,_,_ in
      await gate.wait();return .init(symbols:[.init(schema:"dbo",name:"Obsolete",columns:[])])
    })
    let server=ConnectedServer(profile:profile,password:"unused",diskIndex:disk,objectIndexService:CatalogIndexService(index:disk),completionIndexService:completion)
    let doc=QueryDocument(server:server,database:"Hidden",title:"Existing.sql")
    doc.state = .ready;doc.sql="SELECT 1;";doc.transactionCount=1
    let pending=Task {await doc.loadSymbols(force:true)}
    let deadline=ContinuousClock.now.advanced(by:.seconds(2))
    while !(await gate.started),ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(5))}
    #expect(await gate.started)
    let available=[CatalogItem(id:1,name:"Hidden"),CatalogItem(id:2,name:"Keep")]
    server.profile.visibleDatabases=["Keep"]
    await server.synchronizeCatalogVisibility(available:available)
    server.profile.visibleDatabases=["Hidden","Keep"]
    await server.synchronizeCatalogVisibility(available:available)
    await gate.release();await pending.value
    #expect(doc.catalogError==nil && doc.symbols.isEmpty && !doc.catalogVerified)
    #expect(doc.state == .ready && doc.transactionCount==1 && doc.sql=="SELECT 1;")
    #expect(try await disk.completionSnapshot(scope:CatalogDiskIndex.scope(profile:profile,database:"Hidden"))==nil)
  }
}
