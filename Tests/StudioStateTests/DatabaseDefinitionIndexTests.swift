import AppKit
import Foundation
import SQLServerKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct DatabaseDefinitionIndexTests {
  private func output(_ values: [[String?]]) -> Execution {
    var result = Execution(); result.results = [Rows(values: values)]; return result
  }
  @Test func databaseChoicePersistsWithoutReconnectAndOnlyClearsItsDefinitions() async throws {
    let url = URL(fileURLWithPath: "/tmp/DatabaseDefinitions-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(visibleDatabases: ["A", "B"], indexObjectDefinitions: true)
    let server = ConnectedServer(profile: profile, password: "", diskIndex: disk,
      objectIndexService: CatalogIndexService(index: disk), completionIndexService: SQLCatalogService(index: disk))
    server.databases = [.init(id: 5, name: "A"), .init(id: 6, name: "B")]; server.remembered = true
    server.online = false
    let state = StudioState(); state.servers = [server]; state.recoveryEnabled = false
    let document = QueryDocument(server: server, database: "A", title: "Keep")
    document.sql = "SELECT 1"; document.transactionCount = 3
    state.documents = [document]
    var saved: ServerProfile?
    state.profilePersistenceFixture = { profile, _ in saved = profile }
    await server.definitionIndex.configure()
    let owner = server.id
    let lease = try #require(try await disk.configureDefinitions(owner: owner, enabled: true))
    for database in ["A", "B"] {
      let scope = CatalogDiskIndex.scope(profile: profile, database: database)
      try await disk.saveDefinition(.init(id: 1, schema: "dbo", name: "P", type: "P", sql: "CREATE PROC dbo.P AS SELECT 1"),
        owner: owner, lease: lease, scope: scope, generation: disk.generation(scope: scope))
    }
    let staleFetch = Date()
    let metadata = server.metadata, generation = server.generation
    try await state.setDefinitionIndex(server, database: "A", enabled: false)
    #expect(document.sql == "SELECT 1" && document.transactionCount == 3)
    #expect(server.metadata === metadata && server.generation == generation && !server.online)
    #expect(saved?.indexesDefinitions(in: "A") == false && saved?.indexesDefinitions(in: "B") == true)
    #expect(try await disk.definition(scope: CatalogDiskIndex.scope(profile: profile, database: "A"), id: 1) == nil)
    #expect(try await disk.definition(scope: CatalogDiskIndex.scope(profile: profile, database: "B"), id: 1) != nil)
    #expect(try await server.definitionIndex.cached(database: "B", id: 1).id == 1)
    await #expect(throws: SQLFailure.self) { try await server.definitionIndex.cached(database: "A", id: 1) }
    try await state.setDefinitionIndex(server, database: "A", enabled: true)
    #expect(server.allowsDefinitionIndex("A") && server.allowsDefinitionIndex("B"))
    server.online = true
    await server.definitionIndex.record(.init(id: 2, schema: "dbo", name: "Late", type: "P", sql: "late", fetchedAt: staleFetch),
      database: "A", generation: generation)
    #expect(try await disk.definition(scope: CatalogDiskIndex.scope(profile: profile, database: "A"), id: 2) == nil)
    server.online = false
    state.profilePersistenceFixture = { _, _ in throw SQLFailure("Synthetic persistence failure") }
    await #expect(throws: SQLFailure.self) { try await state.setDefinitionIndex(server, database: "B", enabled: false) }
    #expect(server.allowsDefinitionIndex("B"))
    #expect(try await server.definitionIndex.cached(database: "B", id: 1).id == 1)
  }
  @Test func disabledDatabaseNeverStartsContentReadAndLateResponseCannotRecreateIt() async throws {
    let url = URL(fileURLWithPath: "/tmp/DatabaseDefinitionLate-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(visibleDatabases: ["A", "B"], definitionIndexDatabases: ["A": false, "B": true])
    let server = ConnectedServer(profile: profile, password: "", diskIndex: disk)
    server.databases = [.init(id: 5, name: "A"), .init(id: 6, name: "B")]
    var reads = 0
    var continuation: CheckedContinuation<Execution, Never>?
    server.asyncCatalogFixture = { sql in
      reads += 1
      if sql.contains("Inventory") { return output([["1", "dbo", "P", "P", "1", "0"]]) }
      return await withCheckedContinuation { continuation = $0 }
    }
    await server.definitionIndex.configure(); server.definitionIndex.refresh()
    for _ in 0..<400 where continuation == nil { try await Task.sleep(for: .milliseconds(5)) }
    #expect(reads == 2 && continuation != nil)
    server.profile.setDefinitionIndex(false, database: "B", known: ["A", "B"])
    let change = Task { await server.definitionIndex.configure() }
    await Task.yield()
    continuation?.resume(returning: output([["1", "CREATE PROC dbo.P AS SELECT 1", "1", "1", "0", nil, String("CREATE PROC dbo.P AS SELECT 1".utf16.count*2)]]))
    await change.value
    #expect(try await disk.definitionStatus(scope: CatalogDiskIndex.scope(profile: profile, database: "B")).count == 0)
    server.definitionIndex.refresh()
    #expect(reads == 2 && !server.definitionIndex.isRefreshing)
  }
  @Test func databaseRefreshDoesNotReadOtherEnabledDatabases() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionRefreshScope-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let server = ConnectedServer(profile: .init(definitionIndexDatabases: ["A": true, "B": true]), password: "", diskIndex: disk)
    server.databases = [.init(id: 5, name: "A"), .init(id: 6, name: "B")]
    var reads = 0
    server.catalogFixture = { sql in
      reads += 1
      if sql.contains("Inventory") { return output([["1", "dbo", "P", "P", "1", "0"]]) }
      return output([["1", "CREATE PROC dbo.P AS SELECT 1", "1", "1", "0", nil, String("CREATE PROC dbo.P AS SELECT 1".utf16.count*2)]])
    }
    await server.definitionIndex.configure(); server.definitionIndex.refresh(force: true, database: "A")
    for _ in 0..<400 where server.definitionIndex.isRefreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(reads == 2)
    #expect(try await disk.definitionStatus(scope: CatalogDiskIndex.scope(profile: server.profile, database: "A")).count == 1)
    #expect(try await disk.definitionStatus(scope: CatalogDiskIndex.scope(profile: server.profile, database: "B")).count == 0)
  }
  @Test func connectionFormDatabaseChoicesFitWithContentSwitches() async throws {
    _ = NSApplication.shared
    let server = ConnectedServer(profile: .init(visibleDatabases: ["A", "LongDatabaseName_For_Layout_2026"], definitionIndexDatabases: ["A": true]), password: "")
    server.online = false
    server.databases = [.init(id: 5, name: "A"), .init(id: 6, name: "LongDatabaseName_For_Layout_2026")]
    let host = NSHostingController(rootView: ConnectionForm(initial: server, connect: { _, _, _ in }, saveProfile: { _, _, _ in }, cancel: {}))
    host.sizingOptions = []
    let window = NSWindow(contentViewController: host); window.isReleasedWhenClosed = false
    defer { window.close() }
    window.setFrame(window.frameRect(forContentRect: NSRect(x: -20000, y: 0, width: 940, height: 620)), display: true)
    host.view.frame = NSRect(x: 0, y: 0, width: 940, height: 620); window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(100)); host.view.layoutSubtreeIfNeeded()
    #expect(host.sizeThatFits(in: NSSize(width: 940, height: 620)) == NSSize(width: 940, height: 620))
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let search=try #require(descendants(host.view).compactMap {$0 as? StudioSearchField}.first {$0.accessibilityIdentifier()=="databaseSearch"})
    #expect(search.frame.width>100 && search.frame.height==search.intrinsicContentSize.height)
    let rep = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: rep)
    try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/MSSQLStudio-112-connection-choices.png"))
  }
  @Test func indexPanelFitsMinimumViewportInBothThemes() async throws {
    _ = NSApplication.shared
    let old = StudioTheme.mode
    defer { StudioTheme.apply(old) }
    let url = URL(fileURLWithPath: "/tmp/DatabaseDefinitionUI-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let server = ConnectedServer(profile: .init(definitionIndexDatabases: ["A": true]), password: "", diskIndex: disk,
      objectIndexService: CatalogIndexService(index: disk), completionIndexService: SQLCatalogService(index: disk))
    server.online = false
    for mode in ["light", "dark"] {
      StudioTheme.apply(mode)
      let host = NSHostingController(rootView: ExplorerIndexPanel(server: server, databases: ["A"], refresh: {}, setDefinitionIndex: { _, _ in }))
      host.sizingOptions = []
      let window = NSWindow(contentViewController: host); window.isReleasedWhenClosed = false
      defer { window.close() }
      window.setFrame(window.frameRect(forContentRect: NSRect(x: -20000, y: 0, width: 420, height: 500)), display: true)
      host.view.frame = NSRect(x: 0, y: 0, width: 420, height: 500); window.orderFront(nil)
      try await Task.sleep(for: .milliseconds(100)); host.view.layoutSubtreeIfNeeded()
      let fitting = host.sizeThatFits(in: NSSize(width: 420, height: 500))
      #expect(fitting.width <= 420 && fitting.height <= 500)
      #expect(host.view.bounds == NSRect(x: 0, y: 0, width: 420, height: 500))
      let rep = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
      host.view.cacheDisplay(in: host.view.bounds, to: rep)
      try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/MSSQLStudio-112-database-index-\(mode).png"))

    }
  }
}
