import Foundation
import Testing
@testable import SQLServerKit
struct CatalogDiskIndexTests {
  private func location() -> URL { URL(fileURLWithPath: "/tmp").appendingPathComponent("StudioCatalog-" + UUID().uuidString + "/catalog.sqlite") }
  @Test func persistsIsolatesAndKeepsOldSnapshotUntilCommit() async throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let index = CatalogDiskIndex(url:url)
    try await index.append(scope:"stage-a",items:[CatalogItem(id:1,name:"First",schema:"dbo",detail:"USER_TABLE")])
    #expect(try await index.status(scope:"a") == nil)
    try await index.finishBuild(staging:"stage-a",scope:"a")
    try await index.append(scope:"stage-b",items:[CatalogItem(id:1,name:"Other",schema:"dbo",detail:"VIEW")])
    try await index.finishBuild(staging:"stage-b",scope:"b")
    try await index.append(scope:"incomplete",items:[CatalogItem(id:2,name:"Unpublished",schema:"dbo",detail:"USER_TABLE")])
    let reopened = CatalogDiskIndex(url:url)
    #expect(try await reopened.search(scope:"a",text:"",operation:0,folder:nil).map(\.name) == ["First"])
    #expect(try await reopened.search(scope:"b",text:"",operation:0,folder:nil).map(\.name) == ["Other"])
    try await index.discard(staging:"incomplete")
    #expect(try await index.status(scope:"a")?.count == 1)
    try await index.finishBuild(staging:"empty",scope:"a")
    #expect(try await reopened.status(scope:"a")?.count == 0)
    #expect(try await reopened.search(scope:"a",text:"",operation:0,folder:nil).isEmpty)
  }
  @Test func operatorsUnicodeAndLiteralWildcards() async throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let index = CatalogDiskIndex(url:url)
    try await index.append(scope:"stage",items:[
      CatalogItem(id:1,name:"İstanbul_Satış",schema:"dbo",detail:"USER_TABLE"),
      CatalogItem(id:2,name:"Sales_%'",schema:"dbo",detail:"SQL_STORED_PROCEDURE"),
      CatalogItem(id:3,name:"Sales_Archive",schema:"audit",detail:"VIEW")])
    try await index.finishBuild(staging:"stage",scope:"a")
    #expect(try await index.search(scope:"a",text:"istanbul_satis",operation:1,folder:.tables).count == 1)
    #expect(try await index.search(scope:"a",text:"%",operation:0,folder:nil).map(\.id) == [2])
    #expect(try await index.search(scope:"a",text:"dbo.Sales",operation:2,folder:nil).map(\.id) == [2])
    #expect(try await index.search(scope:"a",text:"Archive",operation:3,folder:nil).map(\.id) == [3])
    #expect(try await index.search(scope:"a",text:"Sales",operation:4,folder:nil).map(\.id) == [1])
    #expect(try await index.search(scope:"a",text:"Sales",operation:0,folder:.tables).isEmpty)
  }
  @Test func targetRefreshOnlyReplacesMatchingObjectAndHandlesDrop() async throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let index = CatalogDiskIndex(url:url)
    try await index.append(scope:"stage",items:[CatalogItem(id:1,name:"One",schema:"dbo",detail:"VIEW"),CatalogItem(id:2,name:"One",schema:"audit",detail:"VIEW"),CatalogItem(id:3,name:"Keep",schema:"dbo",detail:"USER_TABLE")])
    try await index.finishBuild(staging:"stage",scope:"a")
    try await index.replaceTarget(scope:"a",name:"dbo.One",kind:.views,items:[CatalogItem(id:4,name:"One",schema:"dbo",detail:"VIEW")])
    #expect(try await index.search(scope:"a",text:"dbo.One",operation:1,folder:.views).map(\.id) == [4])
    try await index.replaceTarget(scope:"a",name:"dbo.One",kind:.views,items:[])
    #expect(try await index.status(scope:"a")?.count == 2)
    #expect(try await index.search(scope:"a",text:"audit.One",operation:1,folder:.views).map(\.id) == [2])
    #expect(try await index.search(scope:"a",text:"Keep",operation:1,folder:.tables).map(\.id) == [3])
  }
  @Test func warmServiceUsesDiskWithoutConnectingAndScopeChangesWithAccount() async throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let index = CatalogDiskIndex(url:url), profile = ServerProfile()
    let scope = CatalogDiskIndex.scope(profile:profile,database:"master")
    var other = profile; other.login = "other"
    #expect(scope != CatalogDiskIndex.scope(profile:other,database:"master"))
    #expect(scope != CatalogDiskIndex.scope(profile:profile,database:"other"))
    try await index.finishBuild(staging:"empty",scope:scope)
    let service = CatalogIndexService(index:index)
    #expect(try await service.refresh(profile:profile,password:"not-used",database:"master").count == 0)
  }
  @Test func largeIndexBoundsResultAndRemainsCancellable() async throws {
    let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let index = CatalogDiskIndex(url:url)
    let start = Date()
    for page in 0..<50 {
      try await index.append(scope:"stage",items:(1...1000).map { CatalogItem(id:page*1000+$0,name:"Object_\(page*1000+$0)",schema:"dbo",detail:"USER_TABLE") })
    }
    try await index.finishBuild(staging:"stage",scope:"a")
    #expect(try await index.status(scope:"a")?.count == 50000)
    let searchStart = Date()
    #expect(try await index.search(scope:"a",text:"Object_",operation:0,folder:.tables,limit:100000).count == 501)
    #expect(try await index.search(scope:"a",text:"Object_49999",operation:1,folder:.tables).map(\.id) == [49999])
    if ProcessInfo.processInfo.environment["MSSQL_CATALOG_BENCHMARK"] == "1" {
      print("CATALOG_DISK_BENCHMARK rows=50000 buildSeconds=\(searchStart.timeIntervalSince(start)) searchPairSeconds=\(Date().timeIntervalSince(searchStart))")
    }
    let task = Task {
      try Task.checkCancellation()
      return try await index.search(scope:"a",text:"no match",operation:0,folder:nil)
    }
    task.cancel()
    do { _ = try await task.value; Issue.record("Cancelled search must not publish results") } catch is CancellationError { }
  }
}

private actor CatalogCompletionRefreshGate {
  private var continuation:CheckedContinuation<Void,Never>?
  private(set) var started=false
  func wait() async {
    started=true
    await withCheckedContinuation {continuation=$0}
  }
  func release() {continuation?.resume();continuation=nil}
}

struct CatalogCompletionTargetTests {
  private func location()->URL {URL(fileURLWithPath:"/tmp/StudioCompletionTarget-"+UUID().uuidString).appendingPathComponent("catalog.sqlite")}
  @Test func replacementKeepsOtherSchemasAndExactUnicodeNamesAndOriginalFreshnessOnDisk() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),service=SQLCatalogService(index:disk),profile=ServerProfile()
    let scope=CatalogDiskIndex.scope(profile:profile,database:"D"),date=Date(timeIntervalSince1970:1234)
    let symbols=[CatalogSymbol(schema:"dbo",name:"One",columns:["Old"]),CatalogSymbol(schema:"audit",name:"One",columns:["Audit"]),CatalogSymbol(schema:"DBO",name:"One",columns:["Upper"]),CatalogSymbol(schema:"dbo",name:"one",columns:["Lower"]),CatalogSymbol(schema:"dbo",name:"Å",columns:["Angstrom"]),CatalogSymbol(schema:"dbo",name:"Å",columns:["Ring"])]
    try await disk.saveCompletionSnapshot(scope:scope,snapshot:.init(symbols:symbols,synchronizedAt:date))
    let replacement=CatalogSymbol(schema:"dbo",name:"One",columns:["New","City"],kind:"VIEW")
    let updated=try #require(try await service.replaceTarget(profile:profile,database:"D",schema:"dbo",name:"One",symbol:replacement))
    #expect(updated.snapshot.synchronizedAt==date && !updated.fresh)
    #expect(updated.snapshot.symbols.count==symbols.count)
    #expect(updated.snapshot.symbols[0].columns==["New","City"] && updated.snapshot.symbols[0].kind=="VIEW")
    #expect(updated.snapshot.symbols.dropFirst().map(\.columns)==symbols.dropFirst().map(\.columns))
    let unicode=try #require(try await service.replaceTarget(profile:profile,database:"D",schema:"dbo",name:"Å",symbol:CatalogSymbol(schema:"dbo",name:"Å",columns:["Changed"])))
    #expect(unicode.snapshot.symbols[4].columns==["Changed"] && unicode.snapshot.symbols[5].columns==["Ring"])
    let reopened=SQLCatalogService(index:CatalogDiskIndex(url:url))
    let persisted=try #require(try await reopened.cached(profile:profile,database:"D"))
    #expect(persisted.snapshot.synchronizedAt==date && persisted.snapshot.symbols.map(\.columns)==unicode.snapshot.symbols.map(\.columns))
    #expect(try await reopened.cached(profile:profile,database:"Other")==nil)
  }
  @Test func deletionAndNewObjectAreScopedAndAnAbsentCacheDoesNotCreateSnapshot() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),service=SQLCatalogService(index:disk),profile=ServerProfile()
    let symbol=CatalogSymbol(schema:"dbo",name:"One",columns:["ID"]),scope=CatalogDiskIndex.scope(profile:profile,database:"D"),date=Date(timeIntervalSince1970:321)
    #expect(try await service.replaceTarget(profile:profile,database:"D",schema:"dbo",name:"One",symbol:symbol)==nil)
    #expect(try await disk.completionSnapshot(scope:scope)==nil)
    try await disk.saveCompletionSnapshot(scope:scope,snapshot:.init(symbols:[symbol,CatalogSymbol(schema:"audit",name:"One",columns:["Keep"])],synchronizedAt:date))
    let removed=try #require(try await service.replaceTarget(profile:profile,database:"D",schema:"dbo",name:"One",symbol:nil))
    #expect(removed.snapshot.symbols.map(\.schema)==["audit"] && removed.snapshot.synchronizedAt==date)
    let created=try #require(try await service.replaceTarget(profile:profile,database:"D",schema:"dbo",name:"New",symbol:CatalogSymbol(schema:"dbo",name:"New",columns:[],kind:"SQL_STORED_PROCEDURE")))
    #expect(created.snapshot.symbols.map(\.name)==["One","New"] && created.snapshot.symbols.first?.columns==["Keep"])
    #expect(try await disk.completionSnapshot(scope:scope)?.symbols.map(\.name)==["One","New"])
  }
  @Test func concurrentTargetedNotificationsPreserveEachOtherWithoutMarkingCatalogFresh() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),service=SQLCatalogService(index:disk),profile=ServerProfile(),date=Date(timeIntervalSince1970:456)
    let scope=CatalogDiskIndex.scope(profile:profile,database:"D")
    try await disk.saveCompletionSnapshot(scope:scope,snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"Keep",columns:["ID"])],synchronizedAt:date))
    try await withThrowingTaskGroup(of:Void.self) {group in
      for index in 0..<12 {
        group.addTask {
          _=try await service.replaceTarget(profile:profile,database:"D",schema:"dbo",name:"New\(index)",symbol:CatalogSymbol(schema:"dbo",name:"New\(index)",columns:["Column\(index)"]))
        }
      }
      try await group.waitForAll()
    }
    let memory=try #require(try await service.cached(profile:profile,database:"D")),persisted=try #require(try await disk.completionSnapshot(scope:scope))
    #expect(memory.snapshot.symbols.count==13 && persisted.symbols.count==13)
    #expect(memory.snapshot.symbols.first?.name=="Keep" && memory.snapshot.symbols.first?.columns==["ID"])
    #expect(Set(memory.snapshot.symbols.dropFirst().map(\.name))==Set((0..<12).map {"New\($0)"}))
    #expect(memory.snapshot.synchronizedAt==date && persisted.synchronizedAt==date)
  }
  @Test func scopedUpdateWaitsForFullRefreshAndLateWaitersDoNotRestoreOldSymbol() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),gate=CatalogCompletionRefreshGate(),profile=ServerProfile(),date=Date()
    let service=SQLCatalogService(index:disk,refreshFixture:{_,_,_ in
      await gate.wait()
      return SQLCatalogSnapshot(symbols:[CatalogSymbol(schema:"dbo",name:"One",columns:["Before"]),CatalogSymbol(schema:"audit",name:"Keep",columns:["ID"])],synchronizedAt:date)
    })
    let full=Task {try await service.refresh(profile:profile,password:"unused",database:"D",force:true)}
    let deadline=ContinuousClock.now.advanced(by:.seconds(2))
    while !(await gate.started),ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(10))}
    #expect(await gate.started)
    let second=Task {try await service.refresh(profile:profile,password:"unused",database:"D")}
    let target=Task {try await service.replaceTarget(profile:profile,database:"D",schema:"dbo",name:"One",symbol:CatalogSymbol(schema:"dbo",name:"One",columns:["After"]))}
    await gate.release()
    let updated=try #require(try await target.value)
    _=try await full.value;_=try await second.value
    let cached=try #require(try await service.cached(profile:profile,database:"D"))
    #expect(updated.snapshot.symbols.first?.columns==["After"] && cached.snapshot.symbols.first?.columns==["After"])
    #expect(cached.snapshot.symbols.last?.name=="Keep" && cached.snapshot.synchronizedAt==date)
    #expect(try await disk.completionSnapshot(scope:CatalogDiskIndex.scope(profile:profile,database:"D"))?.symbols.first?.columns==["After"])
  }
  @Test func invalidTargetMetadataLeavesExistingCompletionSnapshotUntouched() async throws {
    let url=location();defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),service=SQLCatalogService(index:disk),profile=ServerProfile(),scope=CatalogDiskIndex.scope(profile:profile,database:"D")
    try await disk.saveCompletionSnapshot(scope:scope,snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"One",columns:["Keep"])]))
    for symbol in [CatalogSymbol(schema:"audit",name:"One",columns:["ID"]),CatalogSymbol(schema:"dbo",name:"One",columns:[String(repeating:"x",count:129)]),CatalogSymbol(schema:"dbo",name:"One",columns:["Bad\0Name"])] {
      do {_=try await service.replaceTarget(profile:profile,database:"D",schema:"dbo",name:"One",symbol:symbol);Issue.record("Invalid scoped completion metadata must fail")}
      catch is SQLFailure {}
    }
    #expect(try await service.cached(profile:profile,database:"D")?.snapshot.symbols.first?.columns==["Keep"])
    #expect(try await disk.completionSnapshot(scope:scope)?.symbols.first?.columns==["Keep"])
  }
}

struct ResultEditingDiskCacheTests {
  @Test func persistedProvenanceSkipsNetworkAndSeparatesScopeQueryAndProjection() async throws {
    let folder=URL(fileURLWithPath:"/tmp/StudioEditing-"+UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let url=folder.appendingPathComponent("index.sqlite"), profile=ServerProfile()
    let index=CatalogDiskIndex(url:url), sql="SELECT Id, Code FROM dbo.T;", fields=[Field("Id",type:4),Field("Code")]
    let table=TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int"),.init(id:2,name:"Code",type:"[dbo].[CodeType]",defaultSQL:"'PRIVATE_DEFAULT'",baseType:"varchar(12)")],primaryKey:["Id"])
    let snapshot=ResultEditingSnapshot(objectID:42,table:table)
    let scope=CatalogDiskIndex.scope(profile:profile,database:"D"), key=CatalogDiskIndex.editingFingerprint(sql:sql,fields:fields)
    try await index.saveEditingMetadata(snapshot,scope:scope,fingerprint:key)
    let reopened=CatalogDiskIndex(url:url)
    let cached=try await ResultEditingPreparation.load(sql:sql,fields:fields,profile:profile,database:"D",index:reopened) { _ in throw SQLFailure("Network must not be used on cache hit") }
    #expect(cached.cached && cached.snapshot.objectID == 42)
    #expect(cached.snapshot.columns[1].baseType == "varchar(12)")
    #expect(cached.snapshot.metadataSignature == ResultEditingSnapshot.signature(table:table))
    #expect(cached.snapshot.columns[1].defaultSQL.isEmpty)
    let payload=String(decoding:try JSONEncoder().encode(cached.snapshot),as:UTF8.self)
    #expect(!payload.contains("PRIVATE_DEFAULT") && !payload.contains("SELECT"))
    #expect(try await reopened.editingMetadata(scope:scope,fingerprint:CatalogDiskIndex.editingFingerprint(sql:sql+" ",fields:fields)) == nil)
    #expect(try await reopened.editingMetadata(scope:scope,fingerprint:CatalogDiskIndex.editingFingerprint(sql:sql,fields:fields.reversed())) == nil)
    #expect(try await reopened.editingMetadata(scope:CatalogDiskIndex.scope(profile:profile,database:"Other"),fingerprint:key) == nil)
    #expect(try await reopened.editingMetadata(scope:scope,fingerprint:key,now:Date().addingTimeInterval(86401)) == nil)
    var changed=table; changed.columns[1].baseType="varchar(13)"
    #expect(ResultEditingSnapshot.signature(table:changed) != snapshot.metadataSignature)
    changed=table; changed.columns[1].defaultSQL="'OTHER'"
    #expect(ResultEditingSnapshot.signature(table:changed) != snapshot.metadataSignature)
    try await reopened.finishBuild(staging:"empty",scope:scope)
    #expect(try await reopened.editingMetadata(scope:scope,fingerprint:key) == nil)
  }
}

private actor EditingMetadataFixture {
  var calls=0
  func fetch(_ sql: String) -> Execution {
    calls += 1
    var result=Execution()
    if sql.contains("dm_exec_describe_first_result_set") {
      result.results=[Rows(values:[["Id",nil,"D","dbo","T","Id",nil,nil,"1"],["Code",nil,"D","dbo","T","Code",nil,nil,"2"]])]
    } else if sql.hasPrefix("SELECT object_id") {
      result.results=[Rows(values:[["42"]]), Rows(values:[["1","Id","int","0","0",nil,nil,nil,"0",nil,nil,nil,"0","0","0","int"],["2","Code","[dbo].[CodeType]","1","0",nil,nil,nil,"0",nil,"'PRIVATE_DEFAULT'",nil,"0","0","0","varchar(12)"]]),Rows(values:[["Id","PK_T"]]),Rows(values:[["0",nil]])]
    } else {
      result.results=[Rows(values:[["1","Id","int","0","0",nil,nil,nil,"0",nil,nil,nil,"0","0","0","int"],["2","Code","[dbo].[CodeType]","1","0",nil,nil,nil,"0",nil,"'PRIVATE_DEFAULT'",nil,"0","0","0","varchar(12)"]]),Rows(values:[["Id","PK_T"]]),Rows(),Rows(),Rows(),Rows(),Rows(values:[["0",nil]])]
    }
    return result
  }
}
struct ResultEditingPreparationTests {
  @Test func cacheMissLoadsThenSubsequentPreparationUsesDiskAndSourceChangesFail() async throws {
    let folder=URL(fileURLWithPath:"/tmp/StudioPreparation-"+UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let index=CatalogDiskIndex(url:folder.appendingPathComponent("index.sqlite")), profile=ServerProfile(), fixture=EditingMetadataFixture()
    let sql="SELECT Id, Code FROM dbo.T;", fields=[Field("Id",type:4),Field("Code")]
    let first=try await ResultEditingPreparation.load(sql:sql,fields:fields,profile:profile,database:"D",index:index) { await fixture.fetch($0) }
    #expect(!first.cached && first.snapshot.objectID == 42)
    #expect(await fixture.calls == 2)
    let second=try await ResultEditingPreparation.load(sql:sql,fields:fields,profile:profile,database:"D",index:index) { await fixture.fetch($0) }
    #expect(second.cached && second.snapshot.metadataSignature == first.snapshot.metadataSignature)
    #expect(await fixture.calls == 2)
    let fresh=try ResultEditSource.decode(await fixture.fetch("dm_exec_describe_first_result_set"),fields:fields,database:"D")
    #expect(second.snapshot.matchesSource(fresh))
    var other=await fixture.fetch("dm_exec_describe_first_result_set")
    other.results=[Rows(values:[["Id",nil,"D","other","T","Id",nil,nil,"1"],["Code",nil,"D","other","T","Code",nil,nil,"2"]])]
    let changed=try ResultEditSource.decode(other,fields:fields,database:"D")
    #expect(!second.snapshot.matchesSource(changed))
    try await index.invalidateEditingMetadata(scope:CatalogDiskIndex.scope(profile:profile,database:"D"))
    let refreshed=try await ResultEditingPreparation.load(sql:sql,fields:fields,profile:profile,database:"D",index:index) { await fixture.fetch($0) }
    #expect(!refreshed.cached)
    #expect(await fixture.calls == 6)
  }
}
