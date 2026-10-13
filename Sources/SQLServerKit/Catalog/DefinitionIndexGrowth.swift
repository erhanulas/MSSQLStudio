import CSQLite
import Foundation

public struct DefinitionIndexGrowth: Sendable, Equatable {
  public var enabled: Bool
  public var incrementBytes: Int
  public var maximumBytes: Int
  public init(enabled: Bool = false, incrementBytes: Int = 1_073_741_824,
              maximumBytes: Int = 4_294_967_296) {
    self.enabled = enabled; self.incrementBytes = incrementBytes; self.maximumBytes = maximumBytes
  }
}

extension CatalogDiskIndex {
  public func definitionGrowth() throws -> DefinitionIndexGrowth {
    guard FileManager.default.fileExists(atPath: urlForDefinitions.path) else { return .init() }
    try execute("CREATE TABLE IF NOT EXISTS source_growth(id INTEGER PRIMARY KEY,enabled INTEGER NOT NULL,increment_bytes INTEGER NOT NULL,maximum_bytes INTEGER NOT NULL)")
    let s = try statement("SELECT enabled,increment_bytes,maximum_bytes FROM source_growth WHERE id=1")
    defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW else { return .init() }
    return .init(enabled: sqlite3_column_int(s, 0) == 1,
      incrementBytes: Int(sqlite3_column_int64(s, 1)), maximumBytes: Int(sqlite3_column_int64(s, 2)))
  }
  public func setDefinitionStorage(quota: Int, growth: DefinitionIndexGrowth) throws -> DefinitionIndexUsage {
    guard (DefinitionIndexUsage.minimumQuota...DefinitionIndexUsage.maximumQuota).contains(quota),
      (DefinitionIndexUsage.minimumQuota...DefinitionIndexUsage.maximumQuota).contains(growth.incrementBytes),
      (DefinitionIndexUsage.minimumQuota...DefinitionIndexUsage.maximumQuota).contains(growth.maximumBytes),
      !growth.enabled || growth.maximumBytes >= quota
    else { throw SQLFailure("Kota/artış 128 MB–64 GB arasında; otomatik üst sınır mevcut kotadan küçük olmamalı.") }
    _ = try definitionQuota(); _ = try definitionGrowth()
    try execute("BEGIN IMMEDIATE")
    do {
      try write("INSERT INTO source_growth VALUES(1,?,?,?) ON CONFLICT(id) DO UPDATE SET enabled=excluded.enabled,increment_bytes=excluded.increment_bytes,maximum_bytes=excluded.maximum_bytes",
        [growth.enabled ? "1" : "0", String(growth.incrementBytes), String(growth.maximumBytes)])
      try write("INSERT INTO source_settings VALUES(1,?) ON CONFLICT(id) DO UPDATE SET quota=excluded.quota", [String(quota)])
      try trimDefinitions(quota: quota)
      try execute("COMMIT"); cachedDefinitionQuota = quota
    } catch { try? execute("ROLLBACK"); cachedDefinitionQuota = nil; throw error }
    return try definitionStorageUsage()
  }
  func expandedDefinitionQuota(current: Int, used: Int) throws -> Int {
    guard definitionByteLimit == nil, used > current else { return current }
    let growth = try definitionGrowth()
    guard growth.enabled, growth.incrementBytes > 0, growth.maximumBytes > current else { return current }
    let needed = used - current
    let steps = (needed + growth.incrementBytes - 1) / growth.incrementBytes
    let next = min(growth.maximumBytes, current + steps * growth.incrementBytes)
    try write("UPDATE source_settings SET quota=? WHERE id=1", [String(next)])
    // First use may still have only the default quota, without a settings row.
    try write("INSERT OR IGNORE INTO source_settings VALUES(1,?)", [String(next)])
    cachedDefinitionQuota = next
    return next
  }
}
