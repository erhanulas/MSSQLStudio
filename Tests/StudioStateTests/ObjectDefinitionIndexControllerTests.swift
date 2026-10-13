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
        return output([[body, "1", "1", "0", nil]])
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
  @Test func offlinePreviewUsesReadOnlyNativeSQLAndFitsLightAndDark() async throws {
    _ = NSApplication.shared
    let value = IndexedObjectDefinition(
      id: 1, schema: "dbo", name: "Example", type: "V",
      sql: "CREATE VIEW [dbo].[Example]\nAS\nSELECT N'Çevrimdışı içerik' AS [Ad];")
    let host = NSHostingView(
      rootView: OfflineObjectDefinitionView(value: value, database: "Synthetic"))
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
