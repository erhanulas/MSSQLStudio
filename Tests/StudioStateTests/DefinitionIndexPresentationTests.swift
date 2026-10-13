import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MSSQLStudio
@testable import SQLServerKit

@MainActor @Suite(.serialized) struct DefinitionIndexPresentationTests {
  private func output(_ rows: [[String?]]) -> Execution {
    var e = Execution()
    e.results = [
      Rows(fields: (0..<(rows.first?.count ?? 6)).map { Field(String($0)) }, values: rows)
    ]
    return e
  }
  @Test func perDatabaseFailureRemainsVisibleAfterAnotherDatabaseSucceeds() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionDatabaseStatus-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(visibleDatabases: ["A", "B"], indexObjectDefinitions: true)
    let server = ConnectedServer(profile: profile, password: "", diskIndex: disk)
    server.databases = [CatalogItem(id: 5, name: "A"), CatalogItem(id: 6, name: "B")]
    var inventories = 0
    server.asyncCatalogFixture = { sql in
      if sql.contains("StudioObjectDefinitionInventory") {
        inventories += 1
        if inventories == 1 { throw SQLFailure("Synthetic A failure") }
        return output([["1", "dbo", "Example", "V", "stamp", "0"]])
      }
      return output([["CREATE VIEW dbo.Example AS SELECT 1 AS n", "1", "1", "0", nil]])
    }
    await server.definitionIndex.configure()
    server.definitionIndex.refresh()
    for _ in 0..<400 where server.definitionIndex.isRefreshing {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(!server.definitionIndex.isRefreshing)
    let a = try await server.definitionIndex.presentation(database: "A")
    let b = try await server.definitionIndex.presentation(database: "B")
    #expect(a.failed && a.detail.contains("Synthetic A failure"))
    #expect(b.title == "Hazır" && b.stored?.count == 1 && b.stored?.synchronizedAt != nil)
    server.online = false
    #expect(
      try await server.definitionIndex.presentation(database: "B").detail.contains("Çevrimdışı"))
    server.profile.indexObjectDefinitions = false
    #expect(try await server.definitionIndex.presentation(database: "B").title == "Kapalı")
  }
  @Test func statesAndNativeMetricAreReadableWithoutQueryOrSettingsWrites() async throws {
    _ = NSApplication.shared
    let stored = DefinitionIndexStatus(
      count: 3, lastFetched: Date(), synchronizedAt: Date(), expected: 5, unavailable: 1)
    let partial = DefinitionIndexPresentation(
      enabled: true, online: false, stored: stored, activity: nil)
    #expect(
      partial.title == "Kısmi indeks" && partial.detail.contains("1 nesne okunamadı")
        && partial.detail.contains("kotadan"))
    let building = DefinitionIndexPresentation(
      enabled: true, online: true, stored: stored,
      activity: .init(phase: .building, processed: 2, total: 5))
    #expect(building.building && building.detail.contains("2 / 5"))
    let old = StudioTheme.mode
    defer { StudioTheme.apply(old) }
    for mode in ["light", "dark"] {
      StudioTheme.apply(mode)
      let controller = NSHostingController(rootView: DefinitionIndexMetric(value: partial).padding(16).studioPanel())
      controller.sizingOptions=[]
      let host=controller.view
      let window = NSWindow(
        contentRect: NSRect(x: -20000, y: 0, width: 380, height: 300), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer { window.close() }
      window.orderFront(nil)
      try await Task.sleep(for: .milliseconds(70))
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      let fitting=controller.sizeThatFits(in:NSSize(width:380,height:300))
      #expect(fitting.width<=380 && fitting.height<=300)
      #expect(host.bounds.size==NSSize(width:380,height:300))
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try bitmap.representation(using: .png, properties: [:])?.write(
        to: URL(fileURLWithPath: "/tmp/MSSQLStudio-definition-status-\(mode).png"))
    }
  }
}
