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
  @Test func smokeAndNativeTestHistoryWritesUseTemporaryStateFolder() throws {
    let state=StudioState()
    #expect(state.folder.path.hasPrefix("/tmp/MSSQLStudio-UI-"))
    let url=state.folder.appendingPathComponent("history.json")
    let previous=try? Data(contentsOf:url)
    defer {
      if let previous {try? previous.write(to:url,options:.atomic)}
      else {try? FileManager.default.removeItem(at:url)}
    }
    state.history=[];state.saveHistory()
    #expect(try Data(contentsOf:url)==Data("[]".utf8))
  }

}
