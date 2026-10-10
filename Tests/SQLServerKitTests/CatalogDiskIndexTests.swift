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
      result.results=[Rows(values:[["42"]])]
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
    #expect(await fixture.calls == 3)
    let second=try await ResultEditingPreparation.load(sql:sql,fields:fields,profile:profile,database:"D",index:index) { await fixture.fetch($0) }
    #expect(second.cached && second.snapshot.metadataSignature == first.snapshot.metadataSignature)
    #expect(await fixture.calls == 3)
    let fresh=try ResultEditSource.decode(await fixture.fetch("dm_exec_describe_first_result_set"),fields:fields,database:"D")
    #expect(second.snapshot.matchesSource(fresh))
    var other=await fixture.fetch("dm_exec_describe_first_result_set")
    other.results=[Rows(values:[["Id",nil,"D","other","T","Id",nil,nil,"1"],["Code",nil,"D","other","T","Code",nil,nil,"2"]])]
    let changed=try ResultEditSource.decode(other,fields:fields,database:"D")
    #expect(!second.snapshot.matchesSource(changed))
    try await index.invalidateEditingMetadata(scope:CatalogDiskIndex.scope(profile:profile,database:"D"))
    let refreshed=try await ResultEditingPreparation.load(sql:sql,fields:fields,profile:profile,database:"D",index:index) { await fixture.fetch($0) }
    #expect(!refreshed.cached)
    #expect(await fixture.calls == 8)
  }
}
