import AppKit
import SwiftUI
import Foundation
import SQLServerKit
import Testing

@testable import MSSQLStudio

@MainActor struct DefinitionIndexStorageModelTests {
  @Test func refreshPreservesDraftAndApplyPersistsQuotaWithoutDefaultsOrNetwork() async throws {
    let url = URL(fileURLWithPath: "/tmp/QuotaModel-" + UUID().uuidString).appendingPathComponent(
      "index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let model = DefinitionIndexStorageModel(disk: disk)
    await model.refresh()
    #expect(
      model.quotaMB == 1024 && model.usage?.quotaBytes == 1_073_741_824
        && model.usageText.contains("0.0%"))
    model.quotaMB = 2048
    await model.refresh()
    #expect(model.quotaMB == 2048 && model.usage?.quotaBytes == 1_073_741_824)
    #expect(await model.apply())
    let restored = DefinitionIndexStorageModel(disk: CatalogDiskIndex(url: url))
    await restored.refresh()
    #expect(restored.quotaMB == 2048 && restored.usage?.quotaBytes == 2_147_483_648)
    restored.quotaMB = Int.max
    #expect(await restored.apply() == false && !restored.error.isEmpty && !restored.busy)
    #expect(try await disk.definitionStorageUsage().quotaBytes == 2_147_483_648)
    #expect(SettingsSearch.results("kota").contains { $0.id == "definitionQuota" })
    #expect(SettingsSearch.results("doluluk").contains { $0.section == .workspace })
  }
  @Test func typedIntegersAndAutomaticGrowthDraftsValidateAndPersist() async throws {
    for text in ["", "abc", "1.5", "-1", "999999999999999999999999999999", "1,024"] {
      #expect(SettingsIntegerInput.parsed(text) == Int.min)
    }
    #expect(SettingsIntegerInput.parsed(" 2048 ") == 2048)
    let url = URL(fileURLWithPath: "/tmp/GrowthModel-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url), model = DefinitionIndexStorageModel(disk: disk)
    await model.refresh()
    model.automaticGrowth = true; model.incrementMB = 512; model.maximumMB = 8192
    await model.refresh()
    #expect(model.automaticGrowth && model.incrementMB == 512)
    #expect(await model.apply())
    let restored = DefinitionIndexStorageModel(disk: CatalogDiskIndex(url: url))
    await restored.refresh()
    #expect(restored.automaticGrowth && restored.incrementMB == 512 && restored.maximumMB == 8192)
    restored.maximumMB = 128
    #expect(await restored.apply() == false)
    restored.maximumMB = 8192; restored.incrementMB = Int.min
    #expect(await restored.apply() == false)
    #expect(try await disk.definitionGrowth().incrementBytes == 536_870_912)
  }
  @Test func nativeIntegerFieldAcceptsTypingAndRejectsInvalidDraftWithoutLosingText() async throws {
    _ = NSApplication.shared
    var value = 1024
    let host = NSHostingController(rootView: SettingsIntegerInput("MB", value: Binding(get: { value }, set: { value = $0 })))
    let window = NSWindow(contentViewController: host); window.isReleasedWhenClosed = false
    defer { window.close() }
    window.setFrame(NSRect(x: -20000, y: 0, width: 200, height: 80), display: true)
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(80))
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let field = try #require(descendants(host.view).compactMap { $0 as? NSTextField }.first { $0.isEditable })
    for (text, expected) in [("3072", 3072), ("abc", Int.min), ("365", 365)] {
      field.stringValue = text
      field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
      try await Task.sleep(for: .milliseconds(30))
      #expect(value == expected)
      #expect(field.stringValue == text)
    }
  }
  @Test func smokeAndNativeTestHistoryWritesUseTemporaryStateFolder() async throws {
    let state=StudioState()
    #expect(state.folder.path.hasPrefix("/tmp/MSSQLStudio-UI-"))
    let url=state.folder.appendingPathComponent("history.json")
    let previous=try? Data(contentsOf:url)
    defer {
      if let previous {try? previous.write(to:url,options:.atomic)}
      else {try? FileManager.default.removeItem(at:url)}
    }
    state.history=[];state.saveHistory()
    #expect(await state.flushHistory())
    #expect(try Data(contentsOf:url)==Data("[]".utf8))
  }

}
