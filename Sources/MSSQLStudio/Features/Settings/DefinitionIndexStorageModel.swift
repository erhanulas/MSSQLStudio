import Foundation
import SQLServerKit
import SwiftUI

@MainActor final class DefinitionIndexStorageModel: ObservableObject {
  @Published var quotaMB = 1024
  @Published private(set) var usage: DefinitionIndexUsage?
  @Published private(set) var busy = false
  @Published private(set) var error = ""
  private let disk: CatalogDiskIndex
  private var loaded = false
  init(disk: CatalogDiskIndex? = nil) {
    if let disk {
      self.disk = disk
    } else if Bundle.main.bundleIdentifier == "local.mssqlstudio.uitest"
      || ProcessInfo.processInfo.arguments.contains("--ui-smoke")
      || ProcessInfo.processInfo.arguments.contains(where: { $0.contains(".xctest") })
    {
      self.disk = CatalogDiskIndex(
        url: URL(
          fileURLWithPath:
            "/tmp/MSSQLStudio-settings-\(ProcessInfo.processInfo.processIdentifier)/index.sqlite"))
    } else {
      self.disk = .shared
    }
  }
  func refresh() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      let value = try await disk.definitionStorageUsage()
      usage = value
      if !loaded {
        quotaMB = value.quotaBytes / 1_048_576
        loaded = true
      }
      error = ""
    } catch { self.error = error.localizedDescription }
  }
  func apply() async -> Bool {
    guard !busy else { return false }
    guard (128...65_536).contains(quotaMB) else {
      error = "Kota 128–65.536 MB arasında olmalı."
      return false
    }
    busy = true
    defer { busy = false }
    do {
      usage = try await disk.setDefinitionQuota(quotaMB * 1_048_576)
      loaded = true
      error = ""
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  var usageText: String {
    guard let usage else {
      return error.isEmpty ? "Tanım indeksi okunuyor…" : "Tanım indeksi okunamadı"
    }
    let formatter=ByteCountFormatter();formatter.countStyle = .binary;formatter.allowsNonnumericFormatting=false
    return String(format: "%.1f%%", usage.percentage) + " · "
      + formatter.string(fromByteCount: Int64(usage.usedBytes))
      + " / "
      + formatter.string(fromByteCount: Int64(usage.quotaBytes))
  }
}
