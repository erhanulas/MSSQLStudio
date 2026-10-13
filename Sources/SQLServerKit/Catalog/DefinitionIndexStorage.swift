import CSQLite
import Foundation

public struct DefinitionIndexUsage: Sendable {
  public static let defaultQuota = 1_073_741_824
  public static let minimumQuota = 134_217_728
  public static let maximumQuota = 68_719_476_736
  public let usedBytes: Int
  public let quotaBytes: Int
  public let count: Int
  public var fraction: Double { min(1, max(0, Double(usedBytes) / Double(max(1, quotaBytes)))) }
  public var percentage: Double { fraction * 100 }
}

extension CatalogDiskIndex {
  func definitionQuota() throws -> Int {
    if let definitionByteLimit { return definitionByteLimit }
    if let cachedDefinitionQuota { return cachedDefinitionQuota }
    try execute(
      "CREATE TABLE IF NOT EXISTS source_settings(id INTEGER PRIMARY KEY,quota INTEGER NOT NULL)")
    let s = try statement("SELECT quota FROM source_settings WHERE id=1")
    defer { sqlite3_finalize(s) }
    let quota =
      sqlite3_step(s) == SQLITE_ROW
      ? max(
        DefinitionIndexUsage.minimumQuota,
        min(DefinitionIndexUsage.maximumQuota, Int(sqlite3_column_int64(s, 0))))
      : DefinitionIndexUsage.defaultQuota
    cachedDefinitionQuota = quota
    return quota
  }
  public func definitionStorageUsage() throws -> DefinitionIndexUsage {
    guard FileManager.default.fileExists(atPath: urlForDefinitions.path) else {
      return .init(
        usedBytes: 0, quotaBytes: definitionByteLimit ?? DefinitionIndexUsage.defaultQuota, count: 0
      )
    }
    let quota = try definitionQuota()
    let s = try statement(
      "SELECT total,(SELECT COUNT(*) FROM source_definitions) FROM source_budget WHERE id=1")
    defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW else {
      throw SQLFailure("Tanım indeksi doluluğu okunamadı.")
    }
    return .init(
      usedBytes: Int(sqlite3_column_int64(s, 0)), quotaBytes: quota,
      count: Int(sqlite3_column_int64(s, 1)))
  }
  public func setDefinitionQuota(_ bytes: Int) throws -> DefinitionIndexUsage {
    guard (DefinitionIndexUsage.minimumQuota...DefinitionIndexUsage.maximumQuota).contains(bytes)
    else { throw SQLFailure("Tanım indeksi kotası 128 MB–64 GB arasında olmalı.") }
    _ = try definitionQuota()
    try execute("BEGIN IMMEDIATE")
    do {
      try write(
        "INSERT INTO source_settings VALUES(1,?) ON CONFLICT(id) DO UPDATE SET quota=excluded.quota",
        [String(bytes)])
      try trimDefinitions(quota: bytes)
      try execute("COMMIT")
      cachedDefinitionQuota = bytes
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
    return try definitionStorageUsage()
  }
  func trimDefinitions(quota: Int? = nil) throws {
    let quota = try quota ?? definitionQuota()
    // O(1) byte counter and an ordered index; bodies are never summed on each save.
    while true {
      let s = try statement("SELECT total FROM source_budget WHERE id=1")
      let bytes = sqlite3_step(s) == SQLITE_ROW ? sqlite3_column_int64(s, 0) : 0
      sqlite3_finalize(s)
      guard bytes > quota else { return }
      try execute(
        "DELETE FROM source_definitions WHERE (scope,id)=(SELECT scope,id FROM source_definitions ORDER BY fetched LIMIT 1)"
      )
    }
  }
}
