import Foundation
import Testing
@testable import SQLServerKit

struct DefinitionIndexBatchTests {
  private func entry(_ id: Int, type: String = "P") throws -> DefinitionIndexEntry {
    try .init([String(id), "dbo", "P\(id)", type, "1", "0"])
  }
  @Test func identitiesMissingEncryptedAndPartialPages() throws {
    let entries = try [entry(1), entry(2), entry(3)]
    var result = Execution()
    result.results = [Rows(values: [["2", nil, "1", "1", "0", nil],
      ["1", "CREATE PROC dbo.P1 AS SELECT 1;", "1", "1", "0", nil]])]
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
  @Test func structuralBatchPreservesTableBoundariesAndSynonym() throws {
    var result = Execution()
    func table(_ name: String) -> [Rows] {
      [Rows(values: [["1", name, "int", "0", "0", nil, nil, nil, "0", nil, nil, nil, "0", "0", "0"]]),
       Rows(), Rows(), Rows(), Rows(), Rows(), Rows(values: [["0", "PRIMARY"]])]
    }
    result.results = table("A") + table("B") + [Rows(values: [["[other].[dbo].[Target]"]])]
    let entries = try [entry(1, type: "U"), entry(2, type: "U"), entry(3, type: "SN")]
    let decoded = try DefinitionIndexBatch.decode(result, entries: entries, fetched: Date())
    #expect(decoded.values.count == 3 && decoded.unavailable.isEmpty)
    #expect(decoded.values[0].sql.contains("[A]") && !decoded.values[0].sql.contains("[B]"))
    #expect(decoded.values[1].sql.contains("[B]"))
    #expect(decoded.values[2].sql.contains("SYNONYM"))
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
