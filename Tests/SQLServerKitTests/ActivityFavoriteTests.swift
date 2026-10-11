import Foundation
import Testing
@testable import SQLServerKit

struct ActivityFavoriteTests {
  func snapshot(_ seconds:Double=0,start:String?="A",cpu:Double?=25,waiting:Int64?=3,bytes:Int64?=0,batches:Int64?=0) -> ActivityMonitoring.Snapshot {
    .init(time:Date(timeIntervalSince1970:1_800_000_000+seconds),started:start,cpu:cpu,waiting:waiting,bytes:bytes,batches:batches)
  }
  @Test func ratesUseElapsedTimeAndDoNotInventInitialZero() {
    let old=snapshot(bytes:10_485_760,batches:1000)
    let current=snapshot(5,bytes:20_971_520,batches:1100)
    let initial=ActivityMonitoring.sample(old,previous:nil)
    #expect(initial.megabytesPerSecond == nil && initial.batchesPerSecond == nil)
    let sample=ActivityMonitoring.sample(current,previous:old)
    #expect(sample.megabytesPerSecond == 2 && sample.batchesPerSecond == 20)
    #expect(sample.cpu == 25 && sample.waiting == 3 && !sample.beginsSequence)
    #expect(ActivityMonitoring.sample(snapshot(10,bytes:20_971_520,batches:1100),previous:current).batchesPerSecond == 0)
  }
  @Test func resetsMissingValuesAndClockDiscontinuitiesHaveNoRate() {
    let old=snapshot(bytes:100,batches:100)
    for current in [snapshot(5,start:"B",bytes:500,batches:500),snapshot(5,start:nil,bytes:500,batches:500),snapshot(0,bytes:500,batches:500),snapshot(-5,bytes:500,batches:500),snapshot(181,bytes:500,batches:500),snapshot(5,bytes:99,batches:99),snapshot(5,bytes:nil,batches:nil)] {
      let sample=ActivityMonitoring.sample(current,previous:old)
      #expect(sample.megabytesPerSecond == nil && sample.batchesPerSecond == nil)
    }
  }
  @Test func decodingPreservesUnavailableMetricsAndPermissionMessages() throws {
    var e=Execution();e.results=[Rows(values:[["2026-10-11T08:00:00.1234567Z","server-start","32",nil,"9007199254740993","30"]]),Rows(values:[["Bekleyen görevler","VIEW SERVER PERFORMANCE STATE izni gerekli."]])]
    let s=try ActivityMonitoring.decode(e)
    #expect(s.cpu == 32 && s.waiting == nil && s.bytes == 9_007_199_254_740_993)
    #expect(s.issues == ["Bekleyen görevler: VIEW SERVER PERFORMANCE STATE izni gerekli."])
    e.partial=true;#expect(throws:SQLFailure.self) {try ActivityMonitoring.decode(e)}
    e.partial=false;e.results=[Rows(values:[["invalid",nil,nil,nil,nil,nil]])]
    #expect(throws:SQLFailure.self) {try ActivityMonitoring.decode(e)}
    e.results=[Rows(values:[["2026-10-11T08:00:00Z",nil,"101","-1","overflow","-5"]])]
    let invalid=try ActivityMonitoring.decode(e)
    #expect(invalid.cpu == nil && invalid.waiting == nil && invalid.bytes == nil && invalid.batches == nil)
  }
  @Test func overviewKeepsIndependentMetricsAndCumulativeCounters() {
    let sql=ActivityMonitoring.overviewSQL
    #expect(sql.contains("sys.dm_os_ring_buffers") && sql.contains("ProcessUtilization"))
    #expect(sql.contains("s.is_user_process=1") && sql.contains("w.session_id<>@@SPID"))
    #expect(sql.contains("sys.dm_io_virtual_file_stats") && sql.contains("cntr_type IN (272696320,272696576)"))
    #expect(sql.components(separatedBy:"BEGIN CATCH").count == 6)
  }
  @Test func favoritesMatchProfileIdentityAndExactDatabase() throws {
    let a=UUID(),b=UUID()
    let global=try FavoriteQuery(name:" Genel ",sql:"SELECT N'İstanbul';",scope:.global,serverID:a,database:"DB")
    #expect(global.name == "Genel" && global.serverID == nil && global.database == nil)
    #expect(global.visible(serverID:nil,database:nil) && global.visible(serverID:b,database:"Other"))
    let connection=try FavoriteQuery(name:"Server",sql:"SELECT 1",scope:.connection,serverID:a,database:"Ignored")
    #expect(connection.database == nil && connection.visible(serverID:a,database:"Other"))
    #expect(!connection.visible(serverID:b,database:"DB"))
    let db=try FavoriteQuery(name:"DB",sql:"SELECT 1",scope:.database,serverID:a,database:" Sales ")
    #expect(db.database == "Sales" && db.visible(serverID:a,database:"Sales"))
    #expect(!db.visible(serverID:a,database:"sales") && !db.visible(serverID:b,database:"Sales"))
  }
  @Test func invalidFavoritesCannotBeSaved() {
    for args in [("","SELECT 1",FavoriteQuery.Scope.global,nil as UUID?,nil as String?),("Name"," ",.global,nil,nil),("Name","SELECT 1",.connection,nil,nil),("Name","SELECT 1",.database,UUID(),"  "),(String(repeating:"x",count:121),"SELECT 1",.global,nil,nil)] {
      #expect(throws:SQLFailure.self) {try FavoriteQuery(name:args.0,sql:args.1,scope:args.2,serverID:args.3,database:args.4)}
    }
  }
  @Test func storeRoundTripsUpdatesRemovesAndRestrictsFilePermissions() async throws {
    let dir=URL(fileURLWithPath:"/tmp/favorite-tests-\(UUID())")
    defer {try? FileManager.default.removeItem(at:dir)}
    let url=dir.appendingPathComponent("favorites.json"),store=FavoriteQueryStore(url:url)
    #expect(try await store.load().isEmpty)
    var f=try FavoriteQuery(name:"Sales",sql:"-- unchanged\nSELECT N'İstanbul', 999999999999.12345678;",scope:.database,serverID:UUID(),database:"Sales")
    #expect(try await store.save(f) == [f])
    f.name="Daily Sales";f.sql+="\nGO\nSELECT NULL;"
    #expect(try await store.save(f) == [f])
    #expect(try await FavoriteQueryStore(url:url).load() == [f])
    #expect((try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try await store.remove(f.id).isEmpty)
  }
  @Test func malformedStoreIsNotOverwritten() async throws {
    let url=URL(fileURLWithPath:"/tmp/favorite-bad-\(UUID()).json")
    defer {try? FileManager.default.removeItem(at:url)}
    let data=Data("invalid existing JSON".utf8);try data.write(to:url)
    let f=try FavoriteQuery(name:"New",sql:"SELECT 1",scope:.global)
    await #expect(throws:(any Error).self) {try await FavoriteQueryStore(url:url).save(f)}
    #expect(try Data(contentsOf:url) == data)
  }
}
