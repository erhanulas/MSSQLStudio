import Foundation
import Testing

@testable import SQLServerKit

struct DefinitionIndexStatusTests {
  @Test func scopedStatusSurvivesReopenDistinguishesEmptySyncAndRevokesWithOwner() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionStatus-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile()
    let a = CatalogDiskIndex.scope(profile: profile, database: "A")
    let b = CatalogDiskIndex.scope(profile: profile, database: "B")
    #expect(try await disk.definitionStatus(scope: a).synchronizedAt == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    let lease = try #require(try await disk.configureDefinitions(owner: profile.id, enabled: true))
    let generation = try await disk.generation(scope: a)
    let other = try await disk.generation(scope: b)
    try await disk.saveDefinition(
      .init(id: 1, schema: "dbo", name: "First", type: "V", sql: "SELECT 1"), owner: profile.id,
      lease: lease, scope: a, generation: generation)
    #expect(try await disk.definitionStatus(scope: a).count == 1)
    #expect(try await disk.definitionStatus(scope: a).synchronizedAt == nil)
    try await disk.finishDefinitionSync(
      scope: a, owner: profile.id, lease: lease, generation: generation, expected: 2, unavailable: 1
    )
    try await disk.finishDefinitionSync(
      scope: b, owner: profile.id, lease: lease, generation: other, expected: 0, unavailable: 0)
    let reopened = CatalogDiskIndex(url: url)
    let status = try await reopened.definitionStatus(scope: a)
    let empty = try await reopened.definitionStatus(scope: b)
    #expect(
      status.count == 1 && status.lastFetched != nil && status.synchronizedAt != nil
        && status.unavailable == 1 && !status.incomplete)
    #expect(empty.count == 0 && empty.synchronizedAt != nil && !empty.incomplete)
    try await disk.setExcluded(true, scope: a)
    #expect(try await reopened.definitionStatus(scope: a).synchronizedAt == nil)
    await #expect(throws: CancellationError.self) {
      try await disk.finishDefinitionSync(
        scope: a, owner: profile.id, lease: lease, generation: generation, expected: 1,
        unavailable: 0)
    }
    _ = try await disk.configureDefinitions(owner: profile.id, enabled: false)
    #expect(try await reopened.definitionStatus(scope: b).synchronizedAt == nil)
  }
}
