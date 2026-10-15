import Foundation
import Testing
@testable import SQLServerKit

struct DefinitionIndexBatchTests {
  @Test func structureBatchUsesOrderedCompatibilitySafeXMLLists() throws {
    let sql=try DefinitionIndexBatch.query([entry(5,type:"U"),entry(6,type:"SN")])
    #expect(!sql.contains("STRING_AGG") && !sql.contains("WITHIN GROUP"))
    #expect(sql.components(separatedBy:"FOR XML PATH(''),TYPE").count==5)
    for order in ["ic.key_ordinal","ic.index_column_id","c.constraint_column_id"] {
      #expect(sql.contains("ORDER BY "+order+" FOR XML"))
    }
    #expect(sql.components(separatedBy:".value('.','nvarchar(max)')").count==5)
    try sql.write(toFile:"/tmp/mssql137-table-batch.sql",atomically:true,encoding:.utf8)
    let preview=Catalog.tableColumnDefinition(5)
    #expect(!preview.contains("STRING_AGG") && preview.contains("ORDER BY c.column_id FOR XML PATH(''),TYPE"))
    try preview.write(toFile:"/tmp/mssql137-table-preview.sql",atomically:true,encoding:.utf8)
  }
  private func entry(_ id: Int, type: String = "P") throws -> DefinitionIndexEntry {
    try .init([String(id), "dbo", "P\(id)", type, "1", "0"])
  }
  @Test func identitiesMissingEncryptedAndPartialPages() throws {
    let entries = try [entry(1), entry(2), entry(3)]
    var result = Execution()
    result.results = [Rows(values: [["2", nil, "1", "1", "0", nil, nil],
      ["1", "CREATE PROC dbo.P1 AS SELECT 1;", "1", "1", "0", nil, String("CREATE PROC dbo.P1 AS SELECT 1;".utf16.count*2)]])]
    let decoded = try DefinitionIndexBatch.decode(result, entries: entries, fetched: Date())
    #expect(decoded.values.map(\.id) == [1])
    #expect(decoded.unavailable == [2, 3])
    result.results[0].truncated = true
    #expect(throws: SQLFailure.self) { try DefinitionIndexBatch.decode(result, entries: entries, fetched: Date()) }
    result.results = [Rows(values: [["99", "wrong", "1", "1", "0", nil]])]
    #expect(throws: SQLFailure.self) { try DefinitionIndexBatch.decode(result, entries: entries, fetched: Date()) }
    #expect(throws: SQLFailure.self) { try DefinitionIndexBatch.query([entries[0], entries[0]]) }
    #expect(try DefinitionIndexBatch.query([entry(5, type: "U"), entry(6, type: "SN")]).contains("sys.columns"))
  }
  @Test func fullUnicodeModuleLengthIsVerifiedBeforeIndexing() throws {
    let body="CREATE PROC dbo.P1 AS\r"+String(repeating:"-- İstanbul 🦊\r",count:10000)+"SELECT N'FINAL_MARKER';"
    var result=Execution();result.results=[Rows(values:[["1",body,"1","1","0",nil,String(body.utf16.count*2)]])]
    let decoded=try DefinitionIndexBatch.decode(result,entries:[entry(1)],fetched:Date())
    #expect(decoded.values.first?.original==body && decoded.values.first?.sql.contains("FINAL_MARKER';")==true)
    result.results[0]=Rows(values:[["1",String(body.prefix(500)),"1","1","0",nil,String(body.utf16.count*2)]])
    #expect(throws:SQLFailure.self) {try DefinitionIndexBatch.decode(result,entries:[entry(1)],fetched:Date())}
    #expect(try DefinitionIndexBatch.query([entry(1)]).contains("DATALENGTH(m.definition)"))
  }
  @Test func longDefinitionSurvivesDiskRoundTripWithOriginalAndTail() async throws {
    let folder=URL(fileURLWithPath:"/tmp/LongDefinition-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("index.sqlite")),owner=UUID()
    let lease=try #require(try await disk.configureDefinitions(owner:owner,enabled:true))
    let generation=try await disk.generation(scope:"long")
    let body="CREATE PROC dbo.P1 AS\r"+String(repeating:"-- İstanbul 🦊\r",count:10000)+"SELECT N'FINAL_MARKER';"
    let value=IndexedObjectDefinition(id:1,schema:"dbo",name:"P1",type:"P",sql:body,original:body)
    try await disk.saveDefinitions([value],owner:owner,lease:lease,scope:"long",generation:generation)
    let restored=try #require(try await disk.definition(scope:"long",id:1))
    #expect(restored.sql.utf8.elementsEqual(body.utf8) && restored.original==body && restored.digest==value.digest)
  }
  @Test func structuralBatchPreservesTableBoundariesAndSynonym() throws {
    var result = Execution()
    func table(_ name: String) -> [Rows] {
      [Rows(values: [["1", name, "int", "0", "0", nil, nil, nil, "0", nil, nil, nil, "0", "0", "0"]]),
       Rows(), Rows(), Rows(), Rows(), Rows(), Rows(values: [["0", "PRIMARY"]])]
    }
    let a = table("A"), b = table("B")
    result.results = (0..<7).map { index in
      Rows(values: a[index].values.map { ["1"] + $0 } + b[index].values.map { ["2"] + $0 })
    } + [Rows(values: [["3", "[other].[dbo].[Target]"]])]
    let entries = try [entry(1, type: "U"), entry(2, type: "U"), entry(3, type: "SN")]
    try DefinitionIndexBatch.query(entries).write(toFile: "/tmp/MSSQLStudio-112-table-batch.sql", atomically: true, encoding: .utf8)
    try ObjectMetadata.table(1).write(toFile: "/tmp/MSSQLStudio-112-table-single.sql", atomically: true, encoding: .utf8)
    let decoded = try DefinitionIndexBatch.decode(result, entries: entries, fetched: Date())
    #expect(decoded.values.count == 3 && decoded.unavailable.isEmpty)
    #expect(decoded.values[0].sql.contains("[A]") && !decoded.values[0].sql.contains("[B]"))
    #expect(decoded.values[1].sql.contains("[B]"))
    #expect(decoded.values[2].sql.contains("SYNONYM"))
    var wrongID = result
    wrongID.results[0] = Rows(values: [["999", "1", "A"]])
    #expect(throws: SQLFailure.self) { try DefinitionIndexBatch.decode(wrongID, entries: entries, fetched: Date()) }
    #expect(throws: SQLFailure.self) { try ObjectMetadata.tableBatch([1, 1]) }
    result.results.removeLast()
    #expect(throws: SQLFailure.self) { try DefinitionIndexBatch.decode(result, entries: entries, fetched: Date()) }
  }
  @Test func writesAutomaticallyGrowThenEvictAtConfiguredCap() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionAutoGrow-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url), owner = UUID(), scope = "auto"
    let lease = try #require(try await disk.configureDefinitions(owner: owner, enabled: true))
    let generation = try await disk.generation(scope: scope)
    _ = try await disk.setDefinitionStorage(quota: 134_217_728,
      growth: .init(enabled: true, incrementBytes: 134_217_728, maximumBytes: 268_435_456))
    let body = String(repeating: "x", count: 2_097_152)
    let values = (1...65).map { IndexedObjectDefinition(id: $0, schema: "dbo", name: "P", type: "P",
      sql: body, fetchedAt: Date(timeIntervalSince1970: Double($0))) }
    try await disk.saveDefinitions(values, owner: owner, lease: lease, scope: scope, generation: generation)
    let grown = try await disk.definitionStorageUsage()
    #expect(grown.quotaBytes == 268_435_456 && grown.count == 65)
    #expect(try await CatalogDiskIndex(url: url).definitionStorageUsage().quotaBytes == grown.quotaBytes)
    let next = (66...130).map { IndexedObjectDefinition(id: $0, schema: "dbo", name: "P", type: "P",
      sql: body, fetchedAt: Date(timeIntervalSince1970: Double($0))) }
    try await disk.saveDefinitions(next, owner: owner, lease: lease, scope: scope, generation: generation)
    let capped = try await disk.definitionStorageUsage()
    #expect(capped.quotaBytes == grown.quotaBytes && capped.usedBytes <= capped.quotaBytes)
    #expect(capped.count < 130)
    #expect(try await disk.definition(scope: scope, id: 1) == nil)
    #expect(try await disk.definition(scope: scope, id: 130) != nil)
  }
  @Test func batchRollbackGrowthCapAndLease() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionGrowth-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    // A small synthetic override makes cap/eviction checks cheap; production growth
    // is tested separately with realistic minimum settings, without allocating GB.
    let disk = CatalogDiskIndex(url: url)
    let owner = UUID(), scope = "growth"
    let lease = try #require(try await disk.configureDefinitions(owner: owner, enabled: true))
    let generation = try await disk.generation(scope: scope)
    _ = try await disk.setDefinitionStorage(quota: 134_217_728,
      growth: .init(enabled: true, incrementBytes: 134_217_728, maximumBytes: 268_435_456))
    #expect(try await disk.definitionGrowth().enabled)
    #expect(try await CatalogDiskIndex(url: url).definitionGrowth().maximumBytes == 268_435_456)
    let small = IndexedObjectDefinition(id: 1, schema: "dbo", name: "P1", type: "P", sql: "small")
    let large = IndexedObjectDefinition(id: 2, schema: "dbo", name: "P2", type: "P", sql: String(repeating: "x", count: 4_194_305))
    await #expect(throws: SQLFailure.self) {
      try await disk.saveDefinitions([small, large], owner: owner, lease: lease, scope: scope, generation: generation)
    }
    #expect(try await disk.definition(scope: scope, id: 1) == nil)
    #expect(try await disk.definitionStorageUsage().usedBytes == 0)
    let value = try await disk.expandedDefinitionQuota(current: 134_217_728, used: 134_217_729)
    #expect(value == 268_435_456)
    #expect(try await disk.expandedDefinitionQuota(current: value, used: value + 1) == value)
    await #expect(throws: SQLFailure.self) {
      try await disk.setDefinitionStorage(quota: 536_870_912,
        growth: .init(enabled: true, incrementBytes: 134_217_728, maximumBytes: 268_435_456))
    }
    _ = try await disk.configureDefinitions(owner: owner, enabled: false)
    await #expect(throws: CancellationError.self) {
      try await disk.saveDefinitions([small], owner: owner, lease: lease, scope: scope, generation: generation)
    }
  }
}

struct DatabaseDefinitionProfileTests {
  @Test func legacyOptInMigrationPreservesKnownDatabasesAndNewDatabasesDefaultOff() throws {
    var profile = ServerProfile(indexObjectDefinitions: true)
    #expect(profile.indexesDefinitions(in: "A"))
    profile.setDefinitionIndex(false, database: "A", known: ["A", "B"])
    #expect(!profile.indexesDefinitions(in: "A") && profile.indexesDefinitions(in: "B"))
    #expect(!profile.indexesDefinitions(in: "new") && profile.hasDefinitionIndexes)
    let restored = try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(profile))
    #expect(restored.definitionIndexDatabases == profile.definitionIndexDatabases && restored.indexObjectDefinitions == nil)
    profile.setDefinitionIndex(false, database: "B", known: ["A", "B"])
    #expect(!profile.hasDefinitionIndexes)
    #expect(!ServerProfile().indexesDefinitions(in: "A"))
  }
}
