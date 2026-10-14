import CSQLite
import Foundation

public struct DefinitionIndexStatus: Sendable {
  public let count: Int
  public let lastFetched: Date?
  public let synchronizedAt: Date?
  public let expected: Int?
  public let unavailable: Int
  public var incomplete: Bool { expected.map { count < max(0,$0-unavailable) } ?? true }
}
extension CatalogDiskIndex {
  func prepareDefinitionStatus() throws {
    try execute(
      "CREATE TABLE IF NOT EXISTS source_sync(scope TEXT PRIMARY KEY,synced REAL NOT NULL,expected INTEGER NOT NULL,unavailable INTEGER NOT NULL); CREATE INDEX IF NOT EXISTS source_scope_fetched ON source_definitions(scope,fetched)"
    )
  }
  public func definitionStatus(scope: String) throws -> DefinitionIndexStatus {
    guard FileManager.default.fileExists(atPath: urlForDefinitions.path) else {
      return .init(count: 0, lastFetched: nil, synchronizedAt: nil, expected: nil, unavailable: 0)
    }
    let s = try statement(
      "SELECT COUNT(*),MAX(fetched),(SELECT synced FROM source_sync WHERE scope=?),(SELECT expected FROM source_sync WHERE scope=?),(SELECT unavailable FROM source_sync WHERE scope=?) FROM source_definitions WHERE scope=?",
      [scope, scope, scope, scope])
    defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW else {
      throw SQLFailure("Nesne içeriği indeks durumu okunamadı.")
    }
    func date(_ column: Int32) -> Date? {
      sqlite3_column_type(s, column) == SQLITE_NULL
        ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, column))
    }
    return .init(
      count: Int(sqlite3_column_int64(s, 0)), lastFetched: date(1), synchronizedAt: date(2),
      expected: sqlite3_column_type(s, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, 3)),
      unavailable: Int(sqlite3_column_int64(s, 4)))
  }
  public func finishDefinitionSync(
    scope: String, owner: UUID, lease: UUID, generation: UUID, expected: Int, unavailable: Int
  ) throws {
    try validateDefinitions(owner: owner, lease: lease, scope: scope, generation: generation)
    try registerCatalogOwner(owner, scope: scope)
    try write(
      "INSERT INTO source_sync VALUES(?,?,?,?) ON CONFLICT(scope) DO UPDATE SET synced=excluded.synced,expected=excluded.expected,unavailable=excluded.unavailable",
      [scope, String(Date().timeIntervalSince1970), String(expected), String(unavailable)])
  }
}
