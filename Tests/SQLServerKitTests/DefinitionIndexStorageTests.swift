import Foundation
import Testing

@testable import SQLServerKit

struct DefinitionIndexStorageTests {
  @Test func defaultQuotaPersistenceExactUsageAndInvalidQuotaPreserveRecords() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionQuota-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile()
    let initial = try await disk.definitionStorageUsage()
    #expect(
      initial.quotaBytes == 1_073_741_824 && initial.usedBytes == 0 && initial.count == 0
        && initial.percentage == 0)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    let usage = try await disk.setDefinitionQuota(2_147_483_648)
    #expect(usage.quotaBytes == 2_147_483_648)
    let scope = CatalogDiskIndex.scope(profile: profile, database: "master")
    let lease = try #require(try await disk.configureDefinitions(owner: profile.id, enabled: true))
    let generation = try await disk.generation(scope: scope)
    let record = IndexedObjectDefinition(
      id: 1, schema: "dbo", name: "Quota", type: "V",
      sql: "CREATE VIEW dbo.Quota AS SELECT N'İçerik';")
    try await disk.saveDefinition(
      record, owner: profile.id, lease: lease, scope: scope, generation: generation)
    let actual = try await disk.definitionStorageUsage()
    let expected = try JSONEncoder().encode(record).count
    #expect(actual.usedBytes == expected && actual.count == 1)
    #expect(abs(actual.percentage - Double(expected) / 2_147_483_648 * 100) < 0.000001)
    let reopened = CatalogDiskIndex(url: url)
    #expect(try await reopened.definitionStorageUsage().quotaBytes == 2_147_483_648)
    for invalid in [0, -1, Int.max, DefinitionIndexUsage.maximumQuota + 1] {
      await #expect(throws: SQLFailure.self) { try await disk.setDefinitionQuota(invalid) }
    }
    #expect(try await disk.definitionStorageUsage().usedBytes == expected)
    _ = try await disk.setDefinitionQuota(DefinitionIndexUsage.minimumQuota)
    #expect(try await disk.definition(scope: scope, id: 1)?.sql == record.sql)
    _ = try await disk.configureDefinitions(owner: profile.id, enabled: false)
    #expect(try await disk.definitionStorageUsage().usedBytes == 0)
    #expect(try await disk.definitionStorageUsage().quotaBytes == DefinitionIndexUsage.minimumQuota)
  }
  @Test func loweringQuotaImmediatelyEvictsOldestAndPersistsNewLimit() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionQuotaShrink-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile()
    let sql = String(repeating: "a", count: 2_097_152)
    let scope = CatalogDiskIndex.scope(profile: profile, database: "master")
    let lease = try #require(try await disk.configureDefinitions(owner: profile.id, enabled: true))
    let generation = try await disk.generation(scope: scope)
    try await disk.execute("BEGIN IMMEDIATE")
    do {
      for id in 1...65 {
        let value = IndexedObjectDefinition(
          id: id, schema: "dbo", name: "Quota", type: "V", sql: sql,
          fetchedAt: Date(timeIntervalSince1970: Double(id)))
        try await disk.saveDefinition(
          value, owner: profile.id, lease: lease, scope: scope, generation: generation)
      }
      try await disk.execute("COMMIT")
    } catch {
      try? await disk.execute("ROLLBACK")
      throw error
    }
    #expect(try await disk.definitionStorageUsage().usedBytes > DefinitionIndexUsage.minimumQuota)
    let result = try await disk.setDefinitionQuota(DefinitionIndexUsage.minimumQuota)
    #expect(result.usedBytes <= result.quotaBytes && result.count < 65)
    #expect(try await disk.definition(scope: scope, id: 1) == nil)
    #expect(try await disk.definition(scope: scope, id: 65) != nil)
    #expect(
      try await CatalogDiskIndex(url: url).definitionStorageUsage().quotaBytes
        == DefinitionIndexUsage.minimumQuota)
  }

}
