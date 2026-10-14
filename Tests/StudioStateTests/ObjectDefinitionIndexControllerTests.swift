import AppKit
import Foundation
import SQLServerKit
import SwiftUI
import Testing

@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ObjectDefinitionIndexControllerTests {
  private func output(_ values: [[String?]]) -> Execution {
    var result = Execution()
    result.results = [
      Rows(fields: (0..<(values.first?.count ?? 5)).map { Field(String($0)) }, values: values)
    ]
    return result
  }
  private func wait(_ controller: ObjectDefinitionIndexController) async throws {
    for _ in 0..<400 where controller.isRefreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!controller.isRefreshing)
  }
  @Test func incrementalIndexOfflineReadAndLiveOpenNeverFallsBack() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionController-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(visibleDatabases: ["master"], indexObjectDefinitions: true)
    let server = ConnectedServer(
      profile: profile, password: "", diskIndex: disk,
      objectIndexService: CatalogIndexService(index: disk),
      completionIndexService: SQLCatalogService(index: disk))
    server.databases = [CatalogItem(id: 1, name: "master")]
    var reads = 0
    var body = "CREATE VIEW [dbo].[Example] AS SELECT 1 AS n;"
    var stamp = "1"
    server.catalogFixture = { sql in
      if sql.contains("StudioObjectDefinitionInventory") {
        return output([["9", "dbo", "Example", "V", stamp, "0"]])
      }
      if sql.contains("m.definition") {
        reads += 1
        return output([["9", body, "1", "1", "0", nil]])
      }
      if sql.contains("OBJECT_DEFINITION") {
        reads += 1
        return output([[body]])
      }
      return output([["1", "1"]])
    }
    await server.definitionIndex.configure()
    server.definitionIndex.refresh()
    try await wait(server.definitionIndex)
    #expect(reads == 1)
    await server.definitionIndex.configure()
    server.definitionIndex.refresh()
    try await wait(server.definitionIndex)
    #expect(reads == 1)
    server.online = false
    #expect(try await server.definitionIndex.cached(database: "master", id: 9).original == body)
    #expect(
      try await server.definitionIndex.items(database: "master", folder: .views).map(\.name) == [
        "Example"
      ])
    server.online = true
    await #expect(throws: SQLFailure.self) {
      try await server.definitionIndex.cached(database: "master", id: 9)
    }
    body = "CREATE VIEW [dbo].[Example] AS SELECT 2 AS n;"
    stamp = "2"
    let workbench = WorkbenchController(state: StudioState())
    let node = TreeNode(
      "dbo.Example", kind: .object(.views), server: server, database: "master",
      item: .init(id: 9, name: "Example", schema: "dbo", detail: "VIEW"))
    let loaded = try await workbench.loadManagedModule(node, verb: "ALTER")
    #expect(loaded.original == body && reads == 2)
    server.online = false
    #expect(try await server.definitionIndex.cached(database: "master", id: 9).original == body)
    server.online = true
    server.asyncCatalogFixture = { _ in throw SQLFailure("Live permission denied") }
    await #expect(throws: SQLFailure.self) {
      try await workbench.loadManagedModule(node, verb: "ALTER")
    }
    #expect(reads == 2)
    let oldGeneration = server.generation
    server.generation = UUID()
    await server.definitionIndex.record(
      .init(id: 9, schema: "dbo", name: "Example", type: "V", sql: "Stale response"),
      database: "master", generation: oldGeneration)
    server.online = false
    #expect(try await server.definitionIndex.cached(database: "master", id: 9).original == body)
    await server.definitionIndex.remove()
    server.online = false
    await #expect(throws: SQLFailure.self) {
      try await server.definitionIndex.cached(database: "master", id: 9)
    }
  }
  @Test func removalRevokesLateNetworkWritesAndPreservesOtherExplorer() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionLate-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(indexObjectDefinitions: true)
    let server = ConnectedServer(
      profile: profile, password: "", diskIndex: disk,
      objectIndexService: CatalogIndexService(index: disk),
      completionIndexService: SQLCatalogService(index: disk))
    server.databases = [CatalogItem(id: 1, name: "master")]
    var continuation: CheckedContinuation<Execution, Never>?
    server.asyncCatalogFixture = { _ in await withCheckedContinuation { continuation = $0 } }
    await server.definitionIndex.configure()
    server.definitionIndex.refresh()
    for _ in 0..<100 where continuation == nil { try await Task.sleep(for: .milliseconds(5)) }
    #expect(continuation != nil)
    await server.definitionIndex.remove()
    continuation?.resume(returning: output([["9", "dbo", "Late", "V", "1", "0"]]))
    try await wait(server.definitionIndex)
    let scope = CatalogDiskIndex.scope(profile: profile, database: "master")
    #expect(try await disk.definition(scope: scope, id: 9) == nil)
    #expect(server.definitionIndex.status != "master · 1 tanım · 0 okunamadı")
  }
  @Test func partialPageSplitsWithoutPublishingPartialBodies() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionSplit-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(indexObjectDefinitions: true)
    let server = ConnectedServer(profile: profile, password: "", diskIndex: disk)
    server.databases = [.init(id: 1, name: "master")]
    var reads = 0
    server.catalogFixture = { sql in
      if sql.contains("StudioObjectDefinitionInventory") {
        return output([["1", "dbo", "P1", "P", "1", "0"], ["2", "dbo", "P2", "P", "1", "0"]])
      }
      reads += 1
      if sql.contains("IN (1,2)") { var partial = output([["1", "incomplete", "1", "1", "0", nil]]); partial.partial = true; return partial }
      let id = sql.contains("IN (1)") ? "1" : "2"
      return output([[id, "CREATE PROC dbo.P" + id + " AS SELECT 1;", "1", "1", "0", nil]])
    }
    await server.definitionIndex.configure(); server.definitionIndex.refresh()
    try await wait(server.definitionIndex)
    #expect(reads == 3)
    let scope = CatalogDiskIndex.scope(profile: profile, database: "master")
    #expect(try await disk.definitionStatus(scope: scope).count == 2)
    #expect(try await disk.definition(scope: scope, id: 1)?.sql.contains("incomplete") == false)
  }
  @Test func sevenThousandModulesUseBoundedPagesAndSkipUnchangedBodies() async throws {
    let url = URL(fileURLWithPath: "/tmp/Definition7000-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(indexObjectDefinitions: true)
    let server = ConnectedServer(profile: profile, password: "", diskIndex: disk,
      objectIndexService: CatalogIndexService(index: disk), completionIndexService: SQLCatalogService(index: disk))
    server.databases = [.init(id: 1, name: "master")]
    var reads = 0
    server.catalogFixture = { sql in
      if sql.contains("StudioObjectDefinitionInventory") {
        return output((1...7000).map { [String($0), "dbo", "P" + String($0), "P", "1", "0"] })
      }
      reads += 1
      let list = sql.components(separatedBy: "IN (").last!.components(separatedBy: ")").first!
      let ids = list.split(separator: ",").map(String.init)
      #expect(ids.count <= 200)
      return output(ids.map { [$0, "CREATE PROCEDURE dbo.P" + $0 + " AS SELECT 1;", "1", "1", "0", nil] })
    }
    let began = Date()
    await server.definitionIndex.configure(); server.definitionIndex.refresh()
    for _ in 0..<6000 where server.definitionIndex.isRefreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!server.definitionIndex.isRefreshing)
    #expect(reads == 37)
    let scope = CatalogDiskIndex.scope(profile: profile, database: "master")
    #expect(try await disk.definitionStatus(scope: scope).count == 7000)
    print("Definition7000: \(Date().timeIntervalSince(began)) seconds, \(reads) detail queries")
    await server.definitionIndex.configure(); server.definitionIndex.refresh()
    try await wait(server.definitionIndex)
    #expect(reads == 37)
  }
  @Test func sevenThousandTablesUseSharedMetadataRowsetsInsteadOfSevenPerObject() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionTables7000-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let server = ConnectedServer(profile: .init(definitionIndexDatabases: ["master": true]), password: "", diskIndex: disk)
    server.databases = [.init(id: 1, name: "master")]
    var reads = 0, rowsets = 0
    server.catalogFixture = { sql in
      if sql.contains("Inventory") {
        return output((1...7000).map { [String($0), "dbo", "T" + String($0), "U", "1", "0"] })
      }
      reads += 1
      #expect(sql.components(separatedBy: "SELECT c.object_id,c.column_id").count == 2)
      let list = sql.components(separatedBy: "c.object_id IN (").last!.components(separatedBy: ")").first!
      let ids = list.split(separator: ",").map(String.init)
      #expect(ids.count <= 64)
      var result = Execution()
      result.results = [Rows(values: ids.map { [$0, "1", "A", "int", "0", "0", nil, nil, nil, "0", nil, nil, nil, "0", "0", "0"] }),
        Rows(), Rows(), Rows(), Rows(), Rows(), Rows(values: ids.map { [$0, "0", "PRIMARY"] })]
      rowsets += result.results.count
      return result
    }
    let began = Date()
    await server.definitionIndex.configure(); server.definitionIndex.refresh()
    for _ in 0..<6000 where server.definitionIndex.isRefreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!server.definitionIndex.isRefreshing && reads == 110 && rowsets == 770)
    let scope = CatalogDiskIndex.scope(profile: server.profile, database: "master")
    #expect(try await disk.definitionStatus(scope: scope).count == 7000)
    #expect(try await disk.definition(scope: scope, id: 7000)?.sql.contains("[T7000]") == true)
    print("DefinitionTables7000: \(Date().timeIntervalSince(began)) seconds, \(reads) detail queries, \(rowsets) rowsets")
  }
  @Test func offlinePreviewUsesReadOnlyNativeSQLAndFitsLightAndDark() async throws {
    _ = NSApplication.shared
    let value = IndexedObjectDefinition(
      id: 1, schema: "dbo", name: "Example", type: "V",
      sql: "CREATE VIEW [dbo].[Example]\nAS\nSELECT N'Çevrimdışı içerik' AS [Ad];")
    let host = NSHostingView(
      rootView: InlineOfflineDefinitionView(preview:OfflineDefinitionPreview(server:ConnectedServer(profile:ServerProfile(),password:""),database:"Synthetic",value:value),back:{},navigate:{_ in}))
    let window = NSWindow(
      contentRect: NSRect(x: -20000, y: 0, width: 820, height: 540), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    let old = StudioTheme.mode
    defer {
      window.close()
      StudioTheme.apply(old)
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    for mode in ["light", "dark"] {
      StudioTheme.apply(mode)
      window.orderFront(nil)
      try await Task.sleep(for: .milliseconds(60))
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      let text = try #require(
        descendants(host).compactMap { $0 as? NSTextView }.first {
          $0.identifier?.rawValue == "sqlSourcePreview"
        })
      #expect(!text.isEditable && text.isSelectable && text.string == value.sql)
      #expect(host.fittingSize.width <= 820 && host.fittingSize.height <= 540)
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try bitmap.representation(using: .png, properties: [:])?.write(
        to: URL(fileURLWithPath: "/tmp/MSSQLStudio-offline-definition-\(mode).png"))
    }
  }

}
