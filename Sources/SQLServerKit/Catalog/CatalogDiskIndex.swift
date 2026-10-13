import Foundation
import CryptoKit
import CSQLite

/// Only the actor accesses this handle; wrapper permits safe destruction off its executor.
private final class CatalogSQLiteHandle: @unchecked Sendable {
  let value: OpaquePointer
  init(_ value: OpaquePointer) { self.value = value }
  deinit { sqlite3_close_v2(value) }
}
public struct CatalogIndexStatus: Sendable {
  public let synchronizedAt: Date
  public let count: Int
}
public actor CatalogDiskIndex {
  public static let shared = CatalogDiskIndex(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MSSQLStudio/CatalogIndex/catalog-v1.sqlite"))
  private let url: URL
  private var handle: CatalogSQLiteHandle?
  var registeredCatalogOwners=Set<String>()
  var urlForDefinitions:URL {url}
  var sourceLeases: [UUID: UUID] = [:]
  private var excludedScopes = Set<String>()
  private var generations: [String: UUID] = [:]
  var cachedDefinitionQuota:Int?
  let definitionByteLimit:Int?
  public init(url: URL) { self.url = url;definitionByteLimit=nil }
  init(url:URL,definitionByteLimit:Int) {self.url=url;self.definitionByteLimit=max(1024,definitionByteLimit)}
  /// Excluding an Explorer database removes only its derived local records.
  /// The generation also revokes writes already waiting on network metadata.
  public func setExcluded(_ excluded: Bool, scope: String) throws {
    if !excluded {
      if excludedScopes.remove(scope) != nil { generations[scope] = UUID() }
      return
    }
    excludedScopes.insert(scope); generations[scope] = UUID()
    guard handle != nil || FileManager.default.fileExists(atPath: url.path) else { return }
    try execute("BEGIN IMMEDIATE")
    do {
      try write("DELETE FROM objects WHERE scope=? OR substr(scope,1,length(?)+1)=?||':'",[scope,scope,scope])
      try write("DELETE FROM builds WHERE staging=? OR substr(staging,1,length(?)+1)=?||':'",[scope,scope,scope])
      try write("DELETE FROM source_definitions WHERE scope=?",[scope])
      try write("DELETE FROM scopes WHERE scope=?",[scope])
      try write("DELETE FROM editing_metadata WHERE scope=?",[scope])
      try write("DELETE FROM completion_snapshots WHERE scope=?",[scope])
      try execute("COMMIT")
    } catch { try? execute("ROLLBACK"); throw error }
  }
  public func generation(scope: String) throws -> UUID {
    try validate(scope: scope)
    if let value=generations[scope] { return value }
    let value=UUID(); generations[scope]=value; return value
  }
  func validate(scope: String, generation: UUID? = nil) throws {
    guard !excludedScopes.contains(scope), generation == nil || generations[scope] == generation else { throw CancellationError() }
  }
  public nonisolated static func scope(profile: ServerProfile, database: String) -> String {
    // JSON preserves field boundaries. Passwords never enter the file.
    let fields = [profile.id.uuidString, profile.host, String(profile.port), profile.login, String(profile.kerberos), database]
    let data = (try? JSONEncoder().encode(fields)) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  private nonisolated static func fold(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).replacingOccurrences(of: "ı", with: "i")
  }
  private func open() throws -> OpaquePointer {
    if let handle { return handle.value }
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var raw: OpaquePointer?
    guard sqlite3_open_v2(url.path, &raw, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let raw else {
      if let raw { sqlite3_close_v2(raw) }
      throw SQLFailure("Yerel katalog indeksi açılamadı.")
    }
    handle = CatalogSQLiteHandle(raw)
    sqlite3_busy_timeout(raw, 3000)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA cache_size=-4096; PRAGMA temp_store=FILE;")
    try execute("CREATE TABLE IF NOT EXISTS scopes(scope TEXT PRIMARY KEY, synced REAL NOT NULL, count INTEGER NOT NULL); CREATE TABLE IF NOT EXISTS builds(staging TEXT PRIMARY KEY, created REAL NOT NULL); CREATE TABLE IF NOT EXISTS objects(scope TEXT NOT NULL, id INTEGER NOT NULL, name TEXT NOT NULL, schema_name TEXT NOT NULL, kind TEXT NOT NULL, folded_name TEXT NOT NULL, folded_qualified TEXT NOT NULL, PRIMARY KEY(scope,id)) WITHOUT ROWID; CREATE INDEX IF NOT EXISTS catalog_name ON objects(scope,folded_name); CREATE INDEX IF NOT EXISTS catalog_qualified ON objects(scope,folded_qualified); CREATE INDEX IF NOT EXISTS catalog_kind ON objects(scope,kind);")
    try execute("CREATE TABLE IF NOT EXISTS editing_metadata(scope TEXT NOT NULL, fingerprint TEXT NOT NULL, saved REAL NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(scope,fingerprint)) WITHOUT ROWID;")
    try prepareDefinitionSchema()
    try execute("CREATE INDEX IF NOT EXISTS source_fetched ON source_definitions(fetched); CREATE TABLE IF NOT EXISTS source_budget(id INTEGER PRIMARY KEY,total INTEGER NOT NULL); INSERT OR IGNORE INTO source_budget SELECT 1,(SELECT COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM source_definitions) WHERE NOT EXISTS(SELECT 1 FROM source_budget WHERE id=1); CREATE TRIGGER IF NOT EXISTS source_insert AFTER INSERT ON source_definitions BEGIN UPDATE source_budget SET total=total+length(CAST(NEW.payload AS BLOB)) WHERE id=1; END; CREATE TRIGGER IF NOT EXISTS source_delete AFTER DELETE ON source_definitions BEGIN UPDATE source_budget SET total=total-length(CAST(OLD.payload AS BLOB)) WHERE id=1; END; CREATE TRIGGER IF NOT EXISTS source_update AFTER UPDATE OF payload ON source_definitions BEGIN UPDATE source_budget SET total=total+length(CAST(NEW.payload AS BLOB))-length(CAST(OLD.payload AS BLOB)) WHERE id=1; END;")
    try execute("CREATE TABLE IF NOT EXISTS completion_snapshots(scope TEXT PRIMARY KEY,payload TEXT NOT NULL)")
    try execute("DELETE FROM objects WHERE scope IN (SELECT staging FROM builds WHERE created<CAST(strftime('%s','now') AS REAL)-86400); DELETE FROM builds WHERE created<CAST(strftime('%s','now') AS REAL)-86400;")
    return raw
  }
  func execute(_ sql: String) throws {
    let db = try open()
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw SQLFailure("Yerel katalog indeksi yazılamadı (SQLite \(sqlite3_errcode(db))).") }
  }
  func statement(_ sql: String, _ args: [String] = []) throws -> OpaquePointer {
    let db = try open()
    var value: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &value, nil) == SQLITE_OK, let value else { throw SQLFailure("Yerel katalog sorgusu hazırlanamadı.") }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (i, arg) in args.enumerated() {
      let code = arg.withCString { sqlite3_bind_text(value, Int32(i+1), $0, -1, transient) }
      if code != SQLITE_OK { sqlite3_finalize(value); throw SQLFailure("Yerel katalog parametresi bağlanamadı.") }
    }
    return value
  }
  func write(_ sql: String, _ args: [String] = []) throws {
    let s = try statement(sql,args); defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_DONE else { throw SQLFailure("Yerel katalog güncellenemedi.") }
  }
  public nonisolated static func editingFingerprint(sql: String, fields: [Field]) -> String {
    let signature = [sql] + fields.flatMap { [$0.name, String($0.type), String($0.size), String($0.scale), $0.declaredType ?? ""] }
    return SHA256.hash(data:(try? JSONEncoder().encode(signature)) ?? Data()).map { String(format:"%02x",$0) }.joined()
  }
  public func invalidateEditingMetadata(scope: String) throws {
    try write("DELETE FROM editing_metadata WHERE scope=?",[scope])
  }
  public func editingMetadata(scope: String, fingerprint: String, now: Date = Date()) throws -> ResultEditingSnapshot? {
    guard !excludedScopes.contains(scope) else { return nil }
    let s = try statement("SELECT payload FROM editing_metadata WHERE scope=? AND fingerprint=? AND saved>=?",[scope,fingerprint,String(now.timeIntervalSince1970-86400)])
    defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW, let raw = sqlite3_column_text(s,0) else { return nil }
    return try JSONDecoder().decode(ResultEditingSnapshot.self,from:Data(String(cString:raw).utf8))
  }
  public func saveEditingMetadata(_ snapshot: ResultEditingSnapshot, scope: String, fingerprint: String, now: Date = Date(), generation: UUID? = nil) throws {
    try validate(scope:scope,generation:generation)
    let payload = String(decoding:try JSONEncoder().encode(snapshot),as:UTF8.self)
    guard payload.utf8.count <= 1_048_576 else { return }
    try write("INSERT OR REPLACE INTO editing_metadata VALUES(?,?,?,?)",[scope,fingerprint,String(now.timeIntervalSince1970),payload])
    try write("DELETE FROM editing_metadata WHERE scope=? AND fingerprint NOT IN (SELECT fingerprint FROM editing_metadata WHERE scope=? ORDER BY saved DESC LIMIT 128)",[scope,scope])
    try write("DELETE FROM editing_metadata WHERE saved<?",[String(now.timeIntervalSince1970-86400)])
    try execute("DELETE FROM editing_metadata WHERE (scope,fingerprint) NOT IN (SELECT scope,fingerprint FROM editing_metadata ORDER BY saved DESC LIMIT 4096)")
    try execute("DELETE FROM editing_metadata WHERE (scope,fingerprint) IN (SELECT scope,fingerprint FROM (SELECT scope,fingerprint,SUM(length(CAST(payload AS BLOB))) OVER(ORDER BY saved DESC,scope,fingerprint) AS bytes FROM editing_metadata) WHERE bytes>16777216)")
  }
  public func status(scope: String) throws -> CatalogIndexStatus? {
    guard !excludedScopes.contains(scope) else { return nil }
    let s = try statement("SELECT synced,count FROM scopes WHERE scope=?",[scope]); defer { sqlite3_finalize(s) }
    let code = sqlite3_step(s)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW else { throw SQLFailure("Yerel katalog durumu okunamadı.") }
    return CatalogIndexStatus(synchronizedAt: Date(timeIntervalSince1970: sqlite3_column_double(s,0)), count: Int(sqlite3_column_int64(s,1)))
  }
  public func append(scope: String, items: [CatalogItem], targetScope: String? = nil, generation: UUID? = nil) throws {
    try validate(scope:targetScope ?? scope,generation:generation)
    try execute("BEGIN IMMEDIATE")
    do {
      try write("INSERT OR IGNORE INTO builds VALUES(?,?)",[scope,String(Date().timeIntervalSince1970)])
      let s = try statement("INSERT OR REPLACE INTO objects VALUES(?,?,?,?,?,?,?)"); defer { sqlite3_finalize(s) }
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      for item in items {
        let fields = [scope,String(item.id),item.name,item.schema,item.detail,Self.fold(item.name),Self.fold(item.schema + "." + item.name)]
        sqlite3_reset(s); sqlite3_clear_bindings(s)
        for (i, field) in fields.enumerated() {
          guard field.withCString({ sqlite3_bind_text(s,Int32(i+1),$0,-1,transient) }) == SQLITE_OK else { throw SQLFailure("Katalog kayıt parametresi bağlanamadı.") }
        }
        guard sqlite3_step(s) == SQLITE_DONE else { throw SQLFailure("Katalog kaydı yazılamadı.") }
      }
      try execute("COMMIT")
    } catch { try? execute("ROLLBACK"); throw error }
  }
  public func finishBuild(staging: String, scope: String, at: Date = Date(), generation: UUID? = nil) throws {
    try validate(scope:scope,generation:generation)
    try execute("BEGIN IMMEDIATE")
    do {
      try write("DELETE FROM editing_metadata WHERE scope=?",[scope])
      try write("DELETE FROM objects WHERE scope=?",[scope])
      try write("UPDATE objects SET scope=? WHERE scope=?",[scope,staging])
      try write("DELETE FROM builds WHERE staging=?",[staging])
      try write("INSERT OR REPLACE INTO scopes SELECT ?,?,COUNT(*) FROM objects WHERE scope=?",[scope,String(at.timeIntervalSince1970),scope])
      try execute("COMMIT")
    } catch { try? execute("ROLLBACK"); throw error }
  }
  public func discard(staging: String) throws {
    try write("DELETE FROM objects WHERE scope=?",[staging])
    try write("DELETE FROM builds WHERE staging=?",[staging])
  }
  func invalidateEditingTarget(scope:String,name:String,kind:Folder)throws {
    if kind == .tables {
      // A preparation stores its authoritative base-table identity, never SQL.
      // JSON validity keeps a corrupt cache entry from aborting the DDL refresh.
      try write("DELETE FROM editing_metadata WHERE scope=? AND CASE WHEN json_valid(payload) THEN (json_extract(payload,'$.schema')||'.'||json_extract(payload,'$.name')=? OR json_extract(payload,'$.objectID') IN (SELECT CAST(id AS INTEGER) FROM objects WHERE scope=? AND kind='USER_TABLE' AND (folded_name=? OR folded_qualified=?))) ELSE 1 END",[scope,name,scope,Self.fold(name),Self.fold(name)])
    } else if kind == .views || kind == .synonyms {
      // View/synonym provenance can point to another base table. Without storing
      // user SQL/dependency graphs, retain conservative preparation invalidation.
      try write("DELETE FROM editing_metadata WHERE scope=?",[scope])
    }
  }
  public func replaceTarget(scope: String, name: String, kind: Folder, items: [CatalogItem], generation: UUID? = nil) throws {
    try validate(scope:scope,generation:generation)
    // Exact target replacement also removes dropped objects. Other records stay untouched.
    let kinds = Self.kinds(kind)
    try execute("BEGIN IMMEDIATE")
    do {
      try invalidateEditingTarget(scope:scope,name:name,kind:kind)
      try write("DELETE FROM objects WHERE scope=? AND kind IN (\(kinds)) AND (folded_name=? OR folded_qualified=?)",[scope,Self.fold(name),Self.fold(name)])
      // append has its own transaction, so insert here with one prepared statement per changed object.
      for item in items {
        try write("INSERT OR REPLACE INTO objects VALUES(?,?,?,?,?,?,?)",[scope,String(item.id),item.name,item.schema,item.detail,Self.fold(item.name),Self.fold(item.schema + "." + item.name)])
      }
      try write("UPDATE scopes SET count=(SELECT COUNT(*) FROM objects WHERE scope=?) WHERE scope=?",[scope,scope])
      try execute("COMMIT")
    } catch { try? execute("ROLLBACK"); throw error }
  }
  private nonisolated static func kinds(_ folder: Folder?) -> String {
    switch folder {
    case .tables: return "'USER_TABLE'"
    case .views: return "'VIEW'"
    case .procedures: return "'SQL_STORED_PROCEDURE','CLR_STORED_PROCEDURE'"
    case .functions: return "'SQL_SCALAR_FUNCTION','SQL_INLINE_TABLE_VALUED_FUNCTION','SQL_TABLE_VALUED_FUNCTION','CLR_SCALAR_FUNCTION','CLR_TABLE_VALUED_FUNCTION'"
    case .synonyms: return "'SYNONYM'"
    default: return "'USER_TABLE','VIEW','SQL_STORED_PROCEDURE','CLR_STORED_PROCEDURE','SQL_SCALAR_FUNCTION','SQL_INLINE_TABLE_VALUED_FUNCTION','SQL_TABLE_VALUED_FUNCTION','CLR_SCALAR_FUNCTION','CLR_TABLE_VALUED_FUNCTION','SYNONYM'"
    }
  }
  public func search(scope: String, text: String, operation: Int, folder: Folder?, limit: Int = 501) throws -> [CatalogItem] {
    guard !excludedScopes.contains(scope) else { return [] }
    try Task.checkCancellation()
    let folded = Self.fold(text), predicate: String, args: [String]
    switch operation {
    case 1: predicate = "(folded_name=? OR folded_qualified=?)"; args = [folded,folded]
    case 2: predicate = "((folded_name>=? AND folded_name<?) OR (folded_qualified>=? AND folded_qualified<?))"; args = [folded,folded+"\u{10ffff}",folded,folded+"\u{10ffff}"]
    case 3: predicate = "substr(folded_qualified,-length(?))=?"; args = [folded,folded]
    case 4: predicate = "instr(folded_qualified,?)=0"; args = [folded]
    default: predicate = "instr(folded_qualified,?)>0"; args = [folded]
    }
    let db = try open()
    sqlite3_progress_handler(db, 1000, { _ in Task.isCancelled ? 1 : 0 }, nil)
    defer { sqlite3_progress_handler(db, 0, nil, nil) }
    let s = try statement("SELECT id,name,schema_name,kind FROM objects WHERE scope=? AND kind IN (\(Self.kinds(folder))) AND \(predicate) ORDER BY schema_name,name LIMIT \(max(1,min(limit,501)))",[scope]+args)
    defer { sqlite3_finalize(s) }
    var result: [CatalogItem] = []
    while true {
      try Task.checkCancellation()
      let code = sqlite3_step(s)
      if code == SQLITE_DONE { break }
      if code == SQLITE_INTERRUPT { throw CancellationError() }
      guard code == SQLITE_ROW else { throw SQLFailure("Yerel katalog araması başarısız.") }
      func string(_ i: Int32) -> String { sqlite3_column_text(s,i).map { String(cString: $0) } ?? "" }
      result.append(CatalogItem(id: Int(sqlite3_column_int64(s,0)), name:string(1),schema:string(2),detail:string(3)))
    }
    return result
  }
}

/// Builds in bounded keyset pages. Existing committed index survives errors or cancellation.
public actor CatalogIndexService {
  public static let shared = CatalogIndexService(index: .shared)
  private let index: CatalogDiskIndex
  private struct Build { let id:UUID; let task:Task<Void,Error> }
  private var builds: [String: Build] = [:]
  private var lastAttempt: [String: Date] = [:]
  private let refreshFixture:(@Sendable (ServerProfile,String,String) async throws -> [CatalogItem])?
  private let exclusionFixture:(@Sendable () async -> Void)?
  public init(index: CatalogDiskIndex) { self.index = index; refreshFixture=nil;exclusionFixture=nil }
  init(index: CatalogDiskIndex, refreshFixture:@escaping @Sendable (ServerProfile,String,String) async throws -> [CatalogItem],exclusionFixture:(@Sendable () async -> Void)? = nil) {self.index=index;self.refreshFixture=refreshFixture;self.exclusionFixture=exclusionFixture}
  public func exclude(profile:ServerProfile,database:String) async throws {
    if let exclusionFixture {await exclusionFixture()}
    let scope=CatalogDiskIndex.scope(profile:profile,database:database)
    builds.removeValue(forKey:scope)?.task.cancel();lastAttempt[scope]=nil
    try await index.setExcluded(true,scope:scope)
  }
  @discardableResult public func refresh(profile: ServerProfile, password: String, database: String, force: Bool = false) async throws -> CatalogIndexStatus {
    guard profile.visibleDatabases?.contains(database) != false else {throw CancellationError()}
    let scope = CatalogDiskIndex.scope(profile: profile, database: database)
    try await index.registerCatalogOwner(profile.id,scope:scope)
    let generation=try await index.generation(scope:scope)
    if let build = builds[scope] {
      try await build.task.value
      guard try await index.generation(scope:scope)==generation else {throw CancellationError()}
      guard let status = try await index.status(scope: scope) else { throw SQLFailure("Katalog indeksi tamamlanmadı.") }
      return status
    }
    if !force, let status = try await index.status(scope: scope),
      Date().timeIntervalSince(status.synchronizedAt) < 300 || Date().timeIntervalSince(lastAttempt[scope] ?? .distantPast) < 60 { return status }
    lastAttempt[scope] = Date()
    let index = self.index
    let refreshFixture=self.refreshFixture
    let build = Task {
      let connection = ODBCConnection()
      var profile = profile; profile.database = database
      let staging = scope + ":" + UUID().uuidString
      do {
        if let refreshFixture {
          let items=try await refreshFixture(profile,password,database)
          try Task.checkCancellation()
          try await index.append(scope:staging,items:items,targetScope:scope,generation:generation)
          try await index.finishBuild(staging:staging,scope:scope,generation:generation)
          return
        }
        try await connection.connect(profile,password: password)
        var after = 0
        while true {
          try Task.checkCancellation()
          let output = try await withTaskCancellationHandler {try await connection.execute(Catalog.indexPage(after: after))} onCancel: {connection.cancel()}
          guard !output.partial else { throw SQLFailure("Katalog kısmi geldi; eski disk indeksi korundu.") }
          let items = Catalog.rows(output)
          if items.isEmpty { break }
          guard let last = items.last, last.id > after else { throw SQLFailure("Katalog sayfalaması ilerlemedi.") }
          try await index.append(scope: staging,items: items,targetScope:scope,generation:generation)
          after = last.id
          if items.count < 1000 { break }
        }
        try Task.checkCancellation()
        try await index.finishBuild(staging: staging,scope: scope,generation:generation)
        await connection.disconnect()
      } catch {
        try? await index.discard(staging: staging)
        await connection.disconnect()
        throw error
      }
    }
    let job=Build(id:UUID(),task:build)
    builds[scope] = job
    do {
      try await build.value
      if builds[scope]?.id==job.id {builds[scope] = nil}
      guard try await index.generation(scope:scope)==generation else {throw CancellationError()}
      guard let status = try await index.status(scope: scope) else { throw SQLFailure("Katalog indeksi tamamlanmadı.") }
      return status
    } catch { if builds[scope]?.id==job.id {builds[scope] = nil}; throw error }
  }
  public func replaceTarget(profile: ServerProfile, database: String, name: String, folder: Folder, items: [CatalogItem]) async throws {
    guard profile.visibleDatabases?.contains(database) != false else {return}
    let scope = CatalogDiskIndex.scope(profile: profile,database: database)
    try await index.registerCatalogOwner(profile.id,scope:scope)
    let generation=try await index.generation(scope:scope)
    // Publish targeted DDL after an in-flight full build, avoiding lost local updates.
    if let build = builds[scope] { _ = try? await build.task.value }
    guard try await index.status(scope: scope) != nil else {try await index.invalidateEditingTarget(scope:scope,name:name,kind:folder);return}
    try await index.replaceTarget(scope: scope,name: name,kind: folder,items: items,generation:generation)
  }
}

public struct SQLCatalogSnapshot: Codable, Sendable {
  public let symbols: [CatalogSymbol]
  public let synchronizedAt: Date
  public init(symbols: [CatalogSymbol], synchronizedAt: Date = Date()) { self.symbols = symbols; self.synchronizedAt = synchronizedAt }
}
extension CatalogDiskIndex {
  public func completionSnapshot(scope: String) throws -> SQLCatalogSnapshot? {
    guard !excludedScopes.contains(scope) else { return nil }
    try execute("CREATE TABLE IF NOT EXISTS completion_snapshots(scope TEXT PRIMARY KEY,payload TEXT NOT NULL)")
    let s = try statement("SELECT payload FROM completion_snapshots WHERE scope=?",[scope]); defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW, let value = sqlite3_column_text(s,0) else { return nil }
    return try JSONDecoder().decode(SQLCatalogSnapshot.self,from:Data(String(cString:value).utf8))
  }
  public func saveCompletionSnapshot(scope: String, snapshot: SQLCatalogSnapshot, generation: UUID? = nil) throws {
    try validate(scope:scope,generation:generation)
    try execute("CREATE TABLE IF NOT EXISTS completion_snapshots(scope TEXT PRIMARY KEY,payload TEXT NOT NULL)")
    let payload = String(decoding:try JSONEncoder().encode(snapshot),as:UTF8.self)
    try write("INSERT OR REPLACE INTO completion_snapshots VALUES(?,?)",[scope,payload])
  }
}
/// One bounded, deduplicated metadata job per login/database. No SQL definition or user row is stored.
public actor SQLCatalogService {
  public static let shared = SQLCatalogService(index:.shared)
  private let index: CatalogDiskIndex
  private struct RefreshJob {
    let id:UUID
    let task:Task<SQLIntelligence.Catalog,Error>
  }
  private struct TargetJob {
    let id:UUID
    let task:Task<SQLIntelligence.Catalog?,Error>
  }
  private var jobs: [String:RefreshJob] = [:]
  private var targets: [String:TargetJob] = [:]
  private var memory: [String:SQLIntelligence.Catalog] = [:]
  private let refreshFixture:(@Sendable (ServerProfile,String,String) async throws -> SQLCatalogSnapshot)?
  public init(index: CatalogDiskIndex) { self.index = index;refreshFixture=nil }
  init(index:CatalogDiskIndex,refreshFixture:@escaping @Sendable (ServerProfile,String,String) async throws -> SQLCatalogSnapshot) {self.index=index;self.refreshFixture=refreshFixture}
  func hasPendingTarget(profile:ServerProfile,database:String)->Bool {targets[CatalogDiskIndex.scope(profile:profile,database:database)] != nil}
  private func remember(_ value: SQLIntelligence.Catalog, scope: String) {
    if memory[scope] == nil && memory.count >= 8, let oldest = memory.min(by: { $0.value.snapshot.synchronizedAt < $1.value.snapshot.synchronizedAt })?.key { memory[oldest] = nil }
    memory[scope] = value
  }
  public func exclude(profile:ServerProfile,database:String) async throws {
    let scope=CatalogDiskIndex.scope(profile:profile,database:database)
    jobs.removeValue(forKey:scope)?.task.cancel()
    targets.removeValue(forKey:scope)?.task.cancel()
    memory[scope]=nil
    try await index.setExcluded(true,scope:scope)
  }
  public func cached(profile: ServerProfile, database: String) async throws -> SQLIntelligence.Catalog? {
    guard profile.visibleDatabases?.contains(database) != false else {return nil}
    let scope = CatalogDiskIndex.scope(profile:profile,database:database)
    try await index.registerCatalogOwner(profile.id,scope:scope)
    let generation=try await index.generation(scope:scope)
    if let value = memory[scope] { return value }
    if let snapshot = try await index.completionSnapshot(scope:scope) {
      guard try await index.generation(scope:scope)==generation else {throw CancellationError()}
      if let value=memory[scope] {return value}
      let value = SQLIntelligence.Catalog(snapshot:snapshot); remember(value,scope:scope); return value
    }
    return nil
  }
  private func finish(_ job:RefreshJob,scope:String,value:SQLIntelligence.Catalog) throws -> SQLIntelligence.Catalog {
    // Every waiter can finalize the same full refresh. A late waiter must not
    // overwrite a scoped update that already followed the completed refresh.
    if jobs[scope]?.id==job.id {remember(value,scope:scope);jobs[scope]=nil;return value}
    if let value=memory[scope] {return value}
    throw CancellationError()
  }
  /// Updates one already cached completion object without a connection or a
  /// whole-catalog freshness change. Names are exact, including case/Unicode.
  public func replaceTarget(profile:ServerProfile,database:String,schema:String,name:String,symbol:CatalogSymbol?) async throws -> SQLIntelligence.Catalog? {
    guard profile.visibleDatabases?.contains(database) != false else {return nil}
    func valid(_ text:String,empty:Bool=false)->Bool {(empty || !text.isEmpty) && text.utf16.count<=128 && !text.utf16.contains(0)}
    guard valid(database),valid(schema,empty:true),valid(name),symbol.map({
      $0.schema.utf8.elementsEqual(schema.utf8) && $0.name.utf8.elementsEqual(name.utf8) && valid($0.kind) && $0.columns.count<=250_000 && $0.columns.allSatisfy {valid($0)}
    }) ?? true else {throw SQLFailure("Hedef kolon indeksi bilgisi geçersiz veya boyut sınırını aşıyor.")}
    let scope=CatalogDiskIndex.scope(profile:profile,database:database)
    try await index.registerCatalogOwner(profile.id,scope:scope)
    let generation=try await index.generation(scope:scope)
    let previous=targets[scope]
    let id=UUID()
    let task=Task<SQLIntelligence.Catalog?,Error> {
      // Different DDL notifications for the same database preserve each
      // other's symbols, even while persistence suspends this actor.
      if let previous {_ = try? await previous.task.value}
      try Task.checkCancellation()
      if let job=jobs[scope] {
        do {_ = try finish(job,scope:scope,value:try await job.task.value)}
        catch {if jobs[scope]?.id==job.id {jobs[scope]=nil}}
      }
      guard let value=try await cached(profile:profile,database:database) else {return nil}
      var symbols=value.snapshot.symbols
      let matches:(CatalogSymbol)->Bool = {$0.schema.utf8.elementsEqual(schema.utf8) && $0.name.utf8.elementsEqual(name.utf8)}
      if let position=symbols.firstIndex(where:matches) {
        symbols.removeAll(where:matches)
        if let symbol {symbols.insert(symbol,at:position)}
      } else if let symbol {symbols.append(symbol)}
      guard symbols.count<=50_000,symbols.reduce(0,{$0+max(1,$1.columns.count)})<=250_000 else {throw SQLFailure("Akıllı editör indeks boyutu sınırına ulaştı; son tamamlanan indeks korundu.")}
      let snapshot=SQLCatalogSnapshot(symbols:symbols,synchronizedAt:value.snapshot.synchronizedAt)
      try Task.checkCancellation()
      try await index.saveCompletionSnapshot(scope:scope,snapshot:snapshot,generation:generation)
      try Task.checkCancellation()
      let updated=SQLIntelligence.Catalog(snapshot:snapshot)
      remember(updated,scope:scope)
      return updated
    }
    targets[scope]=TargetJob(id:id,task:task)
    do {let value=try await task.value;if targets[scope]?.id==id {targets[scope]=nil};return value}
    catch {if targets[scope]?.id==id {targets[scope]=nil};throw error}
  }
  public func refresh(profile: ServerProfile, password: String, database: String, force: Bool = false) async throws -> SQLIntelligence.Catalog {
    guard profile.visibleDatabases?.contains(database) != false else {throw CancellationError()}
    let scope = CatalogDiskIndex.scope(profile:profile,database:database)
    try await index.registerCatalogOwner(profile.id,scope:scope)
    let generation=try await index.generation(scope:scope)
    while true {
      while let target=targets[scope] {
        _ = try? await target.task.value
        if targets[scope]?.id==target.id {targets[scope]=nil}
      }
      if let job = jobs[scope] {
        do {return try finish(job,scope:scope,value:try await job.task.value)}
        catch {if jobs[scope]?.id==job.id {jobs[scope]=nil};throw error}
      }
      if force {break}
      let value=try await cached(profile:profile,database:database)
      // Reading a cold disk snapshot suspends the actor; another operation may
      // have established a full refresh or scoped update during that read.
      if targets[scope] != nil || jobs[scope] != nil {continue}
      if let value,value.fresh {return value}
      break
    }
    let index = self.index
    let refreshFixture=self.refreshFixture
    let job = Task<SQLIntelligence.Catalog,Error> {
      if let refreshFixture {
        let snapshot=try await refreshFixture(profile,password,database)
        try Task.checkCancellation()
        try await index.saveCompletionSnapshot(scope:scope,snapshot:snapshot,generation:generation)
        try Task.checkCancellation()
        return SQLIntelligence.Catalog(snapshot:snapshot)
      }
      let connection = ODBCConnection()
      var profile = profile; profile.database = database
      do {
        try await connection.connect(profile,password:password)
        var objectID = 0, columnID = -1, rows = 0
        var objects: [Int:(String,String,String,[String])] = [:]
        while true {
          try Task.checkCancellation()
          let sql = "SELECT TOP (2000) o.object_id,s.name,o.name,o.type_desc,ISNULL(c.column_id,0),c.name FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id LEFT JOIN sys.columns c ON c.object_id=o.object_id WHERE o.is_ms_shipped=0 AND o.type IN ('U','V','P','PC','FN','IF','TF','FS','FT','SN') AND (o.object_id>\(objectID) OR (o.object_id=\(objectID) AND ISNULL(c.column_id,0)>\(columnID))) ORDER BY o.object_id,ISNULL(c.column_id,0);"
          let result = try await withTaskCancellationHandler {try await connection.execute(sql)} onCancel: {connection.cancel()}
          guard !result.partial else { throw SQLFailure("Kolon indeksi kısmi geldi; son tamamlanan indeks korundu.") }
          let values = result.results.first?.values ?? []
          for row in values {
            guard row.count >= 6, let id = row[0].flatMap(Int.init), let schema = row[1], let name = row[2], let kind = row[3], let col = row[4].flatMap(Int.init) else { throw SQLFailure("Kolon indeksi satırı geçersiz.") }
            var value = objects[id] ?? (schema,name,kind,[])
            if let column = row[5] { value.3.append(column) }
            objects[id] = value; objectID = id; columnID = col; rows += 1
            guard objects.count <= 50_000, rows <= 250_000 else { throw SQLFailure("Akıllı editör indeks boyutu sınırına ulaştı; eksik metadata hata olarak işaretlenmez.") }
          }
          if values.count < 2000 { break }
        }
        let snapshot = SQLCatalogSnapshot(symbols:objects.values.map { CatalogSymbol(schema:$0.0,name:$0.1,columns:$0.3,kind:$0.2) })
        try Task.checkCancellation()
        try await index.saveCompletionSnapshot(scope:scope,snapshot:snapshot,generation:generation)
        try Task.checkCancellation()
        await connection.disconnect()
        return SQLIntelligence.Catalog(snapshot:snapshot)
      } catch { await connection.disconnect(); throw error }
    }
    let refresh=RefreshJob(id:UUID(),task:job)
    jobs[scope] = refresh
    do {return try finish(refresh,scope:scope,value:try await job.value)}
    catch {if jobs[scope]?.id==refresh.id {jobs[scope]=nil};throw error}
  }
}
