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
