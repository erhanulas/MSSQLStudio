import Foundation
import Testing
@testable import SQLServerKit

private actor ExcludedCatalogGate {
  private var continuation:CheckedContinuation<Void,Never>?
  private(set) var calls=0
  func waitFirst() async -> Int {
    calls+=1
    let value=calls
    if value==1 {await withCheckedContinuation {continuation=$0}}
    return value
  }
  func release() {continuation?.resume();continuation=nil}
}

struct CatalogExclusionTests {
  private func location()->URL {URL(fileURLWithPath:"/tmp/StudioExcludedCatalog-"+UUID().uuidString).appendingPathComponent("index.sqlite")}
  private func waitForFirst(_ gate:ExcludedCatalogGate) async throws {
    let deadline=ContinuousClock.now.advanced(by:.seconds(2))
    while await gate.calls==0,ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(5))}
    #expect(await gate.calls==1)
  }
  private func expectCancelled<T:Sendable>(_ task:Task<T,Error>) async {
    do {_=try await task.value;Issue.record("Excluded metadata request must not finish successfully")}
    catch is CancellationError {}
    catch {Issue.record("Expected cancellation, received \(error)")}
  }
  @Test func exclusionDeletesOnlyMatchingDerivedRecordsAndOwnedStaging() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),profile=ServerProfile()
    var other=profile;other.id=UUID()
    let removed=CatalogDiskIndex.scope(profile:profile,database:"D"),keep=CatalogDiskIndex.scope(profile:profile,database:"Keep"),otherServer=CatalogDiskIndex.scope(profile:other,database:"D")
    let snapshot=ResultEditingSnapshot(objectID:1,table:TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"ID",type:"int")],primaryKey:["ID"]))
    for scope in [removed,keep,otherServer,removed+"extra"] {
      try await disk.append(scope:scope+":initial",items:[CatalogItem(id:1,name:"T",schema:"dbo",detail:"USER_TABLE")])
      try await disk.finishBuild(staging:scope+":initial",scope:scope)
      try await disk.saveCompletionSnapshot(scope:scope,snapshot:.init(symbols:[.init(schema:"dbo",name:"T",columns:["ID"])]))
      try await disk.saveEditingMetadata(snapshot,scope:scope,fingerprint:"query")
    }
    try await disk.append(scope:removed+":pending",items:[CatalogItem(id:2,name:"Pending",schema:"dbo",detail:"VIEW")])
    try await disk.setExcluded(true,scope:removed)
    // Reopen to verify physical records were deleted, rather than merely hidden.
    let reopened=CatalogDiskIndex(url:url)
    #expect(try await reopened.status(scope:removed)==nil)
    #expect(try await reopened.search(scope:removed,text:"",operation:0,folder:nil).isEmpty)
    #expect(try await reopened.search(scope:removed+":pending",text:"",operation:0,folder:nil).isEmpty)
    #expect(try await reopened.completionSnapshot(scope:removed)==nil)
    #expect(try await reopened.editingMetadata(scope:removed,fingerprint:"query")==nil)
    for scope in [keep,otherServer,removed+"extra"] {
      #expect(try await reopened.status(scope:scope)?.count==1)
      #expect(try await reopened.completionSnapshot(scope:scope)?.symbols.first?.name=="T")
      #expect(try await reopened.editingMetadata(scope:scope,fingerprint:"query")?.objectID==1)
    }
  }
  @Test func exclusionDoesNotCreateCacheAndReincludeRevokesEveryOldWriteLease() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),scope="exact-scope"
    let old=try await disk.generation(scope:scope)
    try await disk.setExcluded(true,scope:scope)
    #expect(!FileManager.default.fileExists(atPath:url.path))
    try await disk.setExcluded(false,scope:scope)
    let fresh=try await disk.generation(scope:scope)
    #expect(old != fresh)
    let item=CatalogItem(id:1,name:"New",schema:"dbo",detail:"VIEW"),snapshot=SQLCatalogSnapshot(symbols:[.init(schema:"dbo",name:"New",columns:[])])
    let editing=ResultEditingSnapshot(objectID:1,table:TableDefinition(schema:"dbo",name:"T",columns:[],primaryKey:[]))
    let writes:[@Sendable () async throws -> Void]=[
      {try await disk.append(scope:scope+":old",items:[item],targetScope:scope,generation:old)},
      {try await disk.finishBuild(staging:scope+":old",scope:scope,generation:old)},
      {try await disk.replaceTarget(scope:scope,name:"dbo.New",kind:.views,items:[item],generation:old)},
      {try await disk.saveCompletionSnapshot(scope:scope,snapshot:snapshot,generation:old)},
      {try await disk.saveEditingMetadata(editing,scope:scope,fingerprint:"old",generation:old)}
    ]
    for write in writes {
      do {try await write();Issue.record("Old generation must not resurrect excluded cache")}
      catch is CancellationError {}
    }
    #expect(!FileManager.default.fileExists(atPath:url.path))
    try await disk.append(scope:scope+":new",items:[item],targetScope:scope,generation:fresh)
    try await disk.finishBuild(staging:scope+":new",scope:scope,generation:fresh)
    #expect(try await disk.status(scope:scope)?.count==1)
  }
  @Test func excludedProfileCannotStartMetadataOrReadOldCompletionMemory() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),gate=ExcludedCatalogGate()
    var profile=ServerProfile();profile.visibleDatabases=["Keep"]
    let service=SQLCatalogService(index:disk,refreshFixture:{_,_,_ in
      _=await gate.waitFirst();return .init(symbols:[])
    })
    let objects=CatalogIndexService(index:disk,refreshFixture:{_,_,_ in
      _=await gate.waitFirst();return []
    })
    #expect(try await service.cached(profile:profile,database:"Hidden")==nil)
    #expect(try await service.replaceTarget(profile:profile,database:"Hidden",schema:"dbo",name:"T",symbol:nil)==nil)
    do {_=try await service.refresh(profile:profile,password:"unused",database:"Hidden",force:true);Issue.record("Hidden metadata refresh must be skipped")}
    catch is CancellationError {}
    do {_=try await objects.refresh(profile:profile,password:"unused",database:"Hidden",force:true);Issue.record("Hidden object refresh must be skipped")}
    catch is CancellationError {}
    #expect(await gate.calls==0)
    #expect(!FileManager.default.fileExists(atPath:url.path))
  }
  @Test func lateCompletionAndTargetedJobsCannotResurrectExcludedThenReaddedDatabase() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),gate=ExcludedCatalogGate(),profile=ServerProfile()
    let scope=CatalogDiskIndex.scope(profile:profile,database:"D")
    let service=SQLCatalogService(index:disk,refreshFixture:{_,_,_ in
      let call=await gate.waitFirst()
      return .init(symbols:[.init(schema:"dbo",name:call==1 ? "Old":"New",columns:[])])
    })
    let old=Task {try await service.refresh(profile:profile,password:"unused",database:"D",force:true)}
    try await waitForFirst(gate)
    let targeted=Task {try await service.replaceTarget(profile:profile,database:"D",schema:"dbo",name:"Old",symbol:.init(schema:"dbo",name:"Old",columns:["Late"]))}
    // The targeted job registers before exclusion while waiting for the full job.
    let deadline=ContinuousClock.now.advanced(by:.seconds(2))
    while !(await service.hasPendingTarget(profile:profile,database:"D")),ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(5))}
    #expect(await service.hasPendingTarget(profile:profile,database:"D"))
    try await service.exclude(profile:profile,database:"D")
    #expect(try await disk.completionSnapshot(scope:scope)==nil)
    try await disk.setExcluded(false,scope:scope)
    let new=try await service.refresh(profile:profile,password:"unused",database:"D",force:true)
    #expect(new.snapshot.symbols.map(\.name)==["New"])
    await gate.release()
    await expectCancelled(old);await expectCancelled(targeted)
    #expect(try await service.cached(profile:profile,database:"D")?.snapshot.symbols.map(\.name)==["New"])
    #expect(try await disk.completionSnapshot(scope:scope)?.symbols.map(\.name)==["New"])
  }
  @Test func lateObjectBuildCannotReplaceReaddedDatabaseAndOtherScopesRemainUsable() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),gate=ExcludedCatalogGate(),profile=ServerProfile()
    let scope=CatalogDiskIndex.scope(profile:profile,database:"D")
    let service=CatalogIndexService(index:disk,refreshFixture:{_,_,_ in
      let call=await gate.waitFirst()
      return [CatalogItem(id:call,name:call==1 ? "Old":"New",schema:"dbo",detail:"VIEW")]
    })
    let old=Task {try await service.refresh(profile:profile,password:"unused",database:"D",force:true)}
    try await waitForFirst(gate)
    try await service.exclude(profile:profile,database:"D")
    try await disk.setExcluded(false,scope:scope)
    #expect(try await service.refresh(profile:profile,password:"unused",database:"D",force:true).count==1)
    await gate.release();await expectCancelled(old)
    #expect(try await disk.search(scope:scope,text:"",operation:0,folder:nil).map(\.name)==["New"])
    #expect(try await service.refresh(profile:profile,password:"unused",database:"Keep",force:true).count==1)
    #expect(try await disk.status(scope:scope)?.count==1)
  }
  @Test func existingHiddenQueryCanPrepareEditingWithoutCachingAndLatePreparationCannotResurrectCache() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),gate=ExcludedCatalogGate(),profile=ServerProfile()
    let scope=CatalogDiskIndex.scope(profile:profile,database:"D"),sql="SELECT Id FROM dbo.T;",fields=[Field("Id",type:4)]
    let fetch:@Sendable (String) async throws -> Execution={query in
      var output=Execution()
      if query.contains("dm_exec_describe_first_result_set") {
        _=await gate.waitFirst()
        output.results=[Rows(values:[["Id",nil,"D","dbo","T","Id",nil,nil,"1"]])]
      } else if query.hasPrefix("SELECT object_id") {
        output.results=[Rows(values:[["42"]]),Rows(values:[["1","Id","int","0","0",nil,nil,nil,"0",nil,nil,nil,"0","0","0","int"]]),Rows(values:[["Id","PK_T"]]),Rows(values:[["0",nil]])]
      } else {
        output.results=[Rows(values:[["1","Id","int","0","0",nil,nil,nil,"0",nil,nil,nil,"0","0","0","int"]]),Rows(values:[["Id","PK_T"]]),Rows(),Rows(),Rows(),Rows(),Rows(values:[["0",nil]])]
      }
      return output
    }
    let pending=Task {try await ResultEditingPreparation.load(sql:sql,fields:fields,profile:profile,database:"D",index:disk,fetch:fetch)}
    try await waitForFirst(gate)
    try await disk.setExcluded(true,scope:scope)
    try await disk.setExcluded(false,scope:scope)
    await gate.release()
    let result=try await pending.value
    #expect(result.snapshot.objectID==42 && !result.cached)
    let fingerprint=CatalogDiskIndex.editingFingerprint(sql:sql,fields:fields)
    #expect(try await disk.editingMetadata(scope:scope,fingerprint:fingerprint)==nil)
    try await disk.setExcluded(true,scope:scope)
    var hidden=profile;hidden.visibleDatabases=["Keep"]
    let uncached=try await ResultEditingPreparation.load(sql:sql,fields:fields,profile:hidden,database:"D",index:disk,fetch:fetch)
    #expect(uncached.snapshot.objectID==42 && !uncached.cached)
    #expect(try await CatalogDiskIndex(url:url).editingMetadata(scope:scope,fingerprint:fingerprint)==nil)
  }
}
