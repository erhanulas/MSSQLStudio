import CSQLite
import Foundation

public struct CatalogScopeUsage: Sendable {
  public let objects: Int64
  public let columns: Int64
  public let definitions: Int64
  public let editing: Int64
  public var total: Int64 { objects + columns + definitions + editing }
}

extension CatalogDiskIndex {
  /// Reads only the timestamp, without decoding/constructing the completion catalog.
  public func completionDate(scope: String) throws -> Date? {
    guard (try? validate(scope:scope)) != nil else { return nil }
    let s = try statement("SELECT json_extract(payload,'$.synchronizedAt') FROM completion_snapshots WHERE scope=?", [scope])
    defer { sqlite3_finalize(s) }
    let code=sqlite3_step(s)
    if code == SQLITE_DONE {return nil}
    guard code == SQLITE_ROW else {throw SQLFailure("Kolon indeksi tarihi okunamadı.")}
    guard sqlite3_column_type(s,0) != SQLITE_NULL else {return nil}
    return Date(timeIntervalSinceReferenceDate: sqlite3_column_double(s,0))
  }
  /// Logical UTF-8 stored data; shared SQLite pages, indexes, staging and WAL are not attributable to a DB.
  public func scopeUsage(scope: String) throws -> CatalogScopeUsage {
    guard (try? validate(scope:scope)) != nil else { return .init(objects:0,columns:0,definitions:0,editing:0) }
    let s = try statement("""
      SELECT
      (SELECT COALESCE(SUM(length(CAST(name AS BLOB))+length(CAST(schema_name AS BLOB))+length(CAST(kind AS BLOB))+length(CAST(folded_name AS BLOB))+length(CAST(folded_qualified AS BLOB))+8),0) FROM objects WHERE scope=?),
      (SELECT COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM completion_snapshots WHERE scope=?),
      (SELECT COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM source_definitions WHERE scope=?),
      (SELECT COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM editing_metadata WHERE scope=?)
      """, [scope,scope,scope,scope])
    defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW else { throw SQLFailure("Veritabanı indeks boyutu okunamadı.") }
    return .init(objects:sqlite3_column_int64(s,0),columns:sqlite3_column_int64(s,1),definitions:sqlite3_column_int64(s,2),editing:sqlite3_column_int64(s,3))
  }
}
