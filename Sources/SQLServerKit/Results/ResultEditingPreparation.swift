import Foundation
import CryptoKit

/// Provenance is obtained from SQL Server once; only schema metadata is persisted, never result values or SQL text.
public struct ResultEditingSnapshot: Codable, Sendable {
  public let metadataSignature: String
  public let objectID: Int
  public let schema: String
  public let name: String
  public let columns: [TableColumn]
  public let primaryKey: [String]
  public var table: TableDefinition { TableDefinition(schema:schema,name:name,columns:columns,primaryKey:primaryKey) }
  public init(objectID: Int, table: TableDefinition) {
    metadataSignature=Self.signature(table:table)
    self.objectID=objectID; schema=table.schema; name=table.name; primaryKey=table.primaryKey
    columns=table.columns.map { original in
      var column=original
      column.defaultSQL=""
      if !column.computed.isEmpty { column.computed="(computed)" }
      return column
    }
  }
  public func matchesSource(_ source: ResultEditSource) -> Bool { Self.matchesSource(source,table:table) }
  public static func matchesSource(_ source: ResultEditSource, table: TableDefinition) -> Bool {
    source.schema == table.schema && source.table == table.name && source.columns == table.columns.map(\.name)
  }
  public static func signature(table: TableDefinition) -> String {
    struct Shape: Encodable { let columns: [TableColumn]; let primaryKey: [String] }
    let encoder=JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let data=(try? encoder.encode(Shape(columns:table.columns.sorted { $0.id < $1.id },primaryKey:table.primaryKey))) ?? Data()
    return SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
  }
}
public enum ResultEditingPreparation {
  public static func load(sql: String, fields: [Field], profile: ServerProfile, database: String,
                          index: CatalogDiskIndex = .shared,
                          fetch: @Sendable (String) async throws -> Execution) async throws -> (snapshot: ResultEditingSnapshot, cached: Bool) {
    // Retain the same eligibility checks even on a cache hit.
    let provenanceSQL = try ResultEditSource.metadata(sql)
    let scope = CatalogDiskIndex.scope(profile:profile,database:database)
    let generation=profile.visibleDatabases?.contains(database) != false ? try? await index.generation(scope:scope):nil
    let fingerprint = CatalogDiskIndex.editingFingerprint(sql:sql,fields:fields)
    if generation != nil,let cached = try? await index.editingMetadata(scope:scope,fingerprint:fingerprint),
       cached.columns.count == fields.count, cached.objectID > 0, !cached.schema.isEmpty, !cached.name.isEmpty,
       Set(cached.columns.map(\.name)).count == cached.columns.count,
       cached.primaryKey.allSatisfy({ key in cached.columns.contains { $0.name == key } }),
       cached.metadataSignature.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil {
      return (cached,true)
    }
    let source = try ResultEditSource.decode(await fetch(provenanceSQL),fields:fields,database:database)
    try Task.checkCancellation()
    let metadata = try ObjectMetadata.decodeEditing(await fetch(ObjectMetadata.editingTable(schema: source.schema, name: source.table)), schema: source.schema, name: source.table)
    let id = metadata.objectID
    let table = try source.projected(metadata.table)
    let snapshot = ResultEditingSnapshot(objectID:id,table:table)
    try Task.checkCancellation()
    if let generation {try? await index.saveEditingMetadata(snapshot,scope:scope,fingerprint:fingerprint,generation:generation)}
    return (snapshot,false)
  }
}
