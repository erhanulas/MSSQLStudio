import Foundation
import Testing

@testable import SQLServerKit

struct ObjectDefinitionIndexTests {
  @Test func persistentUnicodeSnapshotsRespectScopesMonotonicFetchAndRevocation() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionIndex-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile()
    let scope = CatalogDiskIndex.scope(profile: profile, database: "DB")
    let lease = try #require(try await disk.configureDefinitions(owner: profile.id, enabled: true))
    let generation = try await disk.generation(scope: scope)
    let fresh = IndexedObjectDefinition(
      id: 7, schema: "şema", name: "Nesne", type: "P",
      sql: "CREATE PROC [şema].[Nesne] AS SELECT N'İçerik';",
      fetchedAt: Date(timeIntervalSince1970: 20))
    try await disk.saveDefinition(
      fresh, owner: profile.id, lease: lease, scope: scope, generation: generation)
    let old = IndexedObjectDefinition(
      id: 7, schema: "dbo", name: "Old", type: "P", sql: "Old",
      fetchedAt: Date(timeIntervalSince1970: 10))
    try await disk.saveDefinition(
      old, owner: profile.id, lease: lease, scope: scope, generation: generation)
    let reopened = CatalogDiskIndex(url: url)
    #expect(try await reopened.definition(scope: scope, id: 7)?.sql == fresh.sql)
    #expect(try await reopened.definitions(scope: scope, types: ["P"]).map(\.name) == ["Nesne"])
    #expect(
      try await reopened.definition(
        scope: CatalogDiskIndex.scope(profile: profile, database: "Other"), id: 7) == nil)
    _ = try await disk.configureDefinitions(owner: profile.id, enabled: false)
    await #expect(throws: CancellationError.self) {
      try await disk.saveDefinition(
        fresh, owner: profile.id, lease: lease, scope: scope, generation: generation)
    }
    #expect(try await reopened.definition(scope: scope, id: 7) == nil)
    let newLease = try #require(
      try await disk.configureDefinitions(owner: profile.id, enabled: true))
    try await disk.setExcluded(true, scope: scope)
    try await disk.setExcluded(false, scope: scope)
    await #expect(throws: CancellationError.self) {
      try await disk.saveDefinition(
        fresh, owner: profile.id, lease: newLease, scope: scope, generation: generation)
    }
  }
  @Test func legacyProfilesStayOptOutAndOptInRoundTrips() throws {
    var profile = ServerProfile()
    let legacy = try JSONEncoder().encode(profile)
    #expect(
      try JSONDecoder().decode(ServerProfile.self, from: legacy).indexObjectDefinitions != true)
    profile.indexObjectDefinitions = true
    #expect(
      try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(profile))
        .indexObjectDefinitions == true)
    #expect(!IndexedObjectDefinition.inventorySQL.contains("definition,"))
  }
  @Test func ownerRemovalAndPruningLeaveOtherExplorerUntouched() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionOwners-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let a = ServerProfile()
    let b = ServerProfile()
    for profile in [a, b] {
      let scope = CatalogDiskIndex.scope(profile: profile, database: "master")
      try await disk.registerCatalogOwner(profile.id, scope: scope)
      let lease = try #require(
        try await disk.configureDefinitions(owner: profile.id, enabled: true))
      let generation = try await disk.generation(scope: scope)
      try await disk.append(
        scope: scope + ":seed",
        items: [CatalogItem(id: 1, name: "Test", schema: "dbo", detail: "VIEW")])
      try await disk.finishBuild(staging: scope + ":seed", scope: scope)
      try await disk.saveCompletionSnapshot(scope: scope, snapshot: .init(symbols: []))
      for id in [1, 2] {
        try await disk.saveDefinition(
          .init(id: id, schema: "dbo", name: "Test", type: "V", sql: "SELECT 1;"),
          owner: profile.id, lease: lease, scope: scope, generation: generation)
      }
      try await disk.pruneDefinitions(
        scope: scope, ids: [1], owner: profile.id, lease: lease, generation: generation,
        before: Date())
      #expect(try await disk.definition(scope: scope, id: 2) == nil)
    }
    try await disk.removeOwnedCatalogs(a.id)
    let removed = CatalogDiskIndex.scope(profile: a, database: "master")
    let kept = CatalogDiskIndex.scope(profile: b, database: "master")
    let reopened = CatalogDiskIndex(url: url)
    #expect(try await reopened.status(scope: removed) == nil)
    #expect(try await reopened.completionSnapshot(scope: removed) == nil)
    #expect(try await reopened.definition(scope: removed, id: 1) == nil)
    #expect(try await reopened.status(scope: kept)?.count == 1)
    #expect(try await reopened.definition(scope: kept, id: 1) != nil)
  }

  @Test func storageBudgetEvictsOldestAndUpdatesDoNotDoubleCount() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionBudget-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let profile = ServerProfile()
    let scope = CatalogDiskIndex.scope(profile: profile, database: "master")
    func record(_ id: Int, _ time: Double) -> IndexedObjectDefinition {
      .init(
        id: id, schema: "dbo", name: "Budget", type: "V", sql: String(repeating: "x", count: 800),
        fetchedAt: Date(timeIntervalSince1970: time))
    }
    let size = try JSONEncoder().encode(record(1, 1)).count
    let disk = CatalogDiskIndex(url: url, definitionByteLimit: size * 2 + 20)
    let lease = try #require(try await disk.configureDefinitions(owner: profile.id, enabled: true))
    let generation = try await disk.generation(scope: scope)
    for id in [1, 2, 3] {
      try await disk.saveDefinition(
        record(id, Double(id)), owner: profile.id, lease: lease, scope: scope,
        generation: generation)
    }
    #expect(try await disk.definition(scope: scope, id: 1) == nil)
    #expect(try await disk.definition(scope: scope, id: 2) != nil)
    #expect(try await disk.definition(scope: scope, id: 3) != nil)
    try await disk.saveDefinition(
      record(3, 4), owner: profile.id, lease: lease, scope: scope, generation: generation)
    #expect(try await disk.definition(scope: scope, id: 2) != nil)
    let oversized = IndexedObjectDefinition(
      id: 4, schema: "dbo", name: "Large", type: "V", sql: String(repeating: "a", count: 4_194_305))
    await #expect(throws: SQLFailure.self) {
      try await disk.saveDefinition(
        oversized, owner: profile.id, lease: lease, scope: scope, generation: generation)
    }
    #expect(try await disk.definition(scope: scope, id: 3) != nil)
  }

}
