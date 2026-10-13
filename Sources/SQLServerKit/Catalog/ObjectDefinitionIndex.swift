import CSQLite
import CryptoKit
import Foundation

/// A fetched server snapshot, never an editable document or conflict baseline.
public struct IndexedObjectDefinition: Codable, Sendable {
  public let id: Int
  public let schema: String
  public let name: String
  public let type: String
  public let sql: String
  public let original: String?
  public let parentID: Int?
  public let modified: String
  public let fetchedAt: Date
  public let digest: String
  public init(
    id: Int, schema: String, name: String, type: String, sql: String,
    original: String? = nil, parentID: Int? = nil, modified: String = "", fetchedAt: Date = Date()
  ) {
    self.id = id
    self.schema = schema
    self.name = name
    self.type = type
    self.sql = sql
    self.parentID = parentID
    self.original = original
    self.modified = modified
    self.fetchedAt = fetchedAt
    digest = SHA256.hash(data: Data(sql.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  public var item: CatalogItem {
    CatalogItem(id: id, name: name, schema: schema, detail: Self.kind(type))
  }
  public static func kind(_ type: String) -> String {
    switch type {
    case "U": return "USER_TABLE"
    case "V": return "VIEW"
    case "P": return "SQL_STORED_PROCEDURE"
    case "FN": return "SQL_SCALAR_FUNCTION"
    case "IF": return "SQL_INLINE_TABLE_VALUED_FUNCTION"
    case "TF": return "SQL_TABLE_VALUED_FUNCTION"
    case "SN": return "SYNONYM"
    default: return "SQL_TRIGGER"
    }
  }
  public static func stamp(schema: String, name: String, type: String, modified: String) -> String {
    String(
      decoding: (try? JSONEncoder().encode([schema, name, type, modified])) ?? Data(), as: UTF8.self
    )
  }
  public static let inventorySQL = """
    -- StudioObjectDefinitionInventory
    SELECT o.object_id,SCHEMA_NAME(o.schema_id),o.name,RTRIM(o.type),CONVERT(nvarchar(30),o.modify_date,126),o.parent_object_id
    FROM sys.objects o WHERE o.is_ms_shipped=0 AND o.type IN ('U','V','P','FN','IF','TF','TR','SN')
    UNION ALL
    SELECT t.object_id,N'',t.name,'TRD',CONVERT(nvarchar(30),t.modify_date,126),t.parent_id
    FROM sys.triggers t WHERE t.is_ms_shipped=0 AND t.parent_class=0 ORDER BY 1;
    """
}

extension CatalogDiskIndex {
  func prepareDefinitionSchema() throws {
    try execute(
      "CREATE TABLE IF NOT EXISTS source_definitions(owner TEXT NOT NULL,scope TEXT NOT NULL,id INTEGER NOT NULL,payload TEXT NOT NULL,fetched REAL NOT NULL,schema_name TEXT NOT NULL DEFAULT '',name TEXT NOT NULL DEFAULT '',kind TEXT NOT NULL DEFAULT '',parent_id INTEGER NOT NULL DEFAULT 0,modified TEXT NOT NULL DEFAULT '',digest TEXT NOT NULL DEFAULT '',PRIMARY KEY(scope,id)) WITHOUT ROWID; CREATE INDEX IF NOT EXISTS source_owner ON source_definitions(owner); CREATE TABLE IF NOT EXISTS catalog_owners(owner TEXT NOT NULL,scope TEXT NOT NULL,PRIMARY KEY(owner,scope)) WITHOUT ROWID;"
    )
    let columns = try statement("PRAGMA table_info(source_definitions)")
    var names = Set<String>()
    while sqlite3_step(columns) == SQLITE_ROW {
      if let raw = sqlite3_column_text(columns, 1) { names.insert(String(cString: raw)) }
    }
    sqlite3_finalize(columns)
    // Accommodate an early local schema without reading every body on normal startup.
    if !names.contains("modified") {
      for (name, type) in [
        ("schema_name", "TEXT NOT NULL DEFAULT ''"), ("name", "TEXT NOT NULL DEFAULT ''"),
        ("kind", "TEXT NOT NULL DEFAULT ''"), ("parent_id", "INTEGER NOT NULL DEFAULT 0"),
        ("modified", "TEXT NOT NULL DEFAULT ''"), ("digest", "TEXT NOT NULL DEFAULT ''"),
      ] {
        if !names.contains(name) {
          try execute("ALTER TABLE source_definitions ADD COLUMN " + name + " " + type)
        }
      }
      try execute(
        "UPDATE source_definitions SET schema_name=json_extract(payload,'$.schema'),name=json_extract(payload,'$.name'),kind=json_extract(payload,'$.type'),parent_id=COALESCE(json_extract(payload,'$.parentID'),0),modified=json_extract(payload,'$.modified'),digest=json_extract(payload,'$.digest')"
      )
    }
    try execute(
      "CREATE INDEX IF NOT EXISTS source_identity ON source_definitions(scope,kind,schema_name,name,parent_id); CREATE INDEX IF NOT EXISTS source_stamps ON source_definitions(scope,id,modified)"
    )
  }

  public func registerCatalogOwner(_ owner: UUID, scope: String) throws {
    try validate(scope: scope)
    let key = owner.uuidString + scope
    guard !registeredCatalogOwners.contains(key) else { return }
    try write("INSERT OR IGNORE INTO catalog_owners VALUES(?,?)", [owner.uuidString, scope])
    registeredCatalogOwners.insert(key)
  }
  public func removeOwnedCatalogs(_ owner: UUID) throws {
    guard FileManager.default.fileExists(atPath: urlForDefinitions.path) else { return }
    let s = try statement(
      "SELECT scope FROM catalog_owners WHERE owner=? UNION SELECT scope FROM source_definitions WHERE owner=?",
      [owner.uuidString, owner.uuidString])
    var scopes: [String] = []
    while sqlite3_step(s) == SQLITE_ROW {
      if let raw = sqlite3_column_text(s, 0) { scopes.append(String(cString: raw)) }
    }
    sqlite3_finalize(s)
    for scope in scopes { try setExcluded(true, scope: scope) }
    try write("DELETE FROM catalog_owners WHERE owner=?", [owner.uuidString])
    registeredCatalogOwners = registeredCatalogOwners.filter { !$0.hasPrefix(owner.uuidString) }
  }

  /// Revocation precedes deletion, so late network completions cannot recreate removed data.
  public func configureDefinitions(owner: UUID, enabled: Bool, purge: Bool = false) throws -> UUID?
  {
    sourceLeases[owner] = nil
    if purge || !enabled, FileManager.default.fileExists(atPath: urlForDefinitions.path) {
      try write("DELETE FROM source_sync WHERE scope IN (SELECT scope FROM catalog_owners WHERE owner=?)",[owner.uuidString])
      try write("DELETE FROM source_definitions WHERE owner=?", [owner.uuidString])
    }
    guard enabled else { return nil }
    let lease = UUID()
    sourceLeases[owner] = lease
    return lease
  }
  func validateDefinitions(owner: UUID, lease: UUID, scope: String, generation: UUID) throws {
    guard sourceLeases[owner] == lease else { throw CancellationError() }
    try validate(scope: scope, generation: generation)
  }
  public func definitionStamps(scope: String) throws -> [Int: String] {
    let s = try statement(
      "SELECT id,modified FROM source_definitions WHERE scope=?", [scope])
    defer { sqlite3_finalize(s) }
    var values: [Int: String] = [:]
    while sqlite3_step(s) == SQLITE_ROW {
      if let raw = sqlite3_column_text(s, 1) {
        values[Int(sqlite3_column_int64(s, 0))] = String(cString: raw)
      }
    }
    return values
  }
  public func definition(scope: String, id: Int) throws -> IndexedObjectDefinition? {
    guard (try? validate(scope: scope)) != nil else { return nil }
    let s = try statement(
      "SELECT payload FROM source_definitions WHERE scope=? AND id=?", [scope, String(id)])
    defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW, let raw = sqlite3_column_text(s, 0) else { return nil }
    return try JSONDecoder().decode(
      IndexedObjectDefinition.self, from: Data(String(cString: raw).utf8))
  }
  public func definitions(scope: String, types: [String], parentID: Int? = nil) throws
    -> [CatalogItem]
  {
    // Covering metadata indexes avoid touching body overflow pages for tree/stamp scans.
    guard !types.isEmpty else { return [] }
    guard types.count <= 32 else { throw SQLFailure("Geçersiz tanım türü kapsamı.") }
    let placeholders = Array(repeating: "?", count: types.count).joined(separator: ",")
    let s = try statement(
      "SELECT id,schema_name,name,kind FROM source_definitions WHERE scope=? AND kind IN (\(placeholders)) AND (?='' OR parent_id=CAST(? AS INTEGER)) ORDER BY 2,3",
      [scope] + types + [parentID.map(String.init) ?? "", parentID.map(String.init) ?? ""])
    defer { sqlite3_finalize(s) }
    var items: [CatalogItem] = []
    while sqlite3_step(s) == SQLITE_ROW {
      func text(_ i: Int32) -> String {
        sqlite3_column_text(s, i).map { String(cString: $0) } ?? ""
      }
      let type = text(3)
      if types.contains(type) {
        items.append(
          CatalogItem(
            id: Int(sqlite3_column_int64(s, 0)), name: text(2), schema: text(1),
            detail: IndexedObjectDefinition.kind(type)))
      }
    }
    return items
  }
  public func saveDefinition(
    _ value: IndexedObjectDefinition, owner: UUID, lease: UUID, scope: String, generation: UUID
  ) throws {
    try validateDefinitions(owner: owner, lease: lease, scope: scope, generation: generation)
    try registerCatalogOwner(owner, scope: scope)
    let payload = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    guard payload.utf8.count <= 4_194_304 else {
      throw SQLFailure("Nesne tanımı 4 MB indeks sınırını aşıyor.")
    }
    // A slower background request cannot overwrite a newer interactive fetch.
    try write(
      "INSERT INTO source_definitions(owner,scope,id,payload,fetched,schema_name,name,kind,parent_id,modified,digest) VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(scope,id) DO UPDATE SET payload=excluded.payload,fetched=excluded.fetched,schema_name=excluded.schema_name,name=excluded.name,kind=excluded.kind,parent_id=excluded.parent_id,modified=excluded.modified,digest=excluded.digest WHERE excluded.fetched>=source_definitions.fetched",
      [
        owner.uuidString, scope, String(value.id), payload,
        String(value.fetchedAt.timeIntervalSince1970), value.schema, value.name, value.type,
        String(value.parentID ?? 0), value.modified, value.digest,
      ])
    try trimDefinitions()
  }

  public func removeDefinition(
    scope: String, id: Int, owner: UUID, lease: UUID, generation: UUID, before: Date
  ) throws {
    try validateDefinitions(owner: owner, lease: lease, scope: scope, generation: generation)
    try write(
      "DELETE FROM source_definitions WHERE scope=? AND id=? AND fetched<=?",
      [scope, String(id), String(before.timeIntervalSince1970)])
  }
  public func pruneDefinitions(
    scope: String, ids: Set<Int>, owner: UUID, lease: UUID, generation: UUID, before: Date
  ) throws {
    try validateDefinitions(owner: owner, lease: lease, scope: scope, generation: generation)
    let items = try definitions(
      scope: scope, types: ["U", "V", "P", "FN", "IF", "TF", "TR", "TRD", "SN"])
    for item in items where !ids.contains(item.id) {
      try removeDefinition(
        scope: scope, id: item.id, owner: owner, lease: lease, generation: generation,
        before: before)
    }
  }
}
