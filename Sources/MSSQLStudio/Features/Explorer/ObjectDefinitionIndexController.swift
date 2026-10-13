import AppKit
import SQLServerKit

/// Owns opt-in source indexing independently from query sessions and completion.
@MainActor final class ObjectDefinitionIndexController {
  private weak var server: ConnectedServer?
  private let disk: CatalogDiskIndex
  private var lease: UUID?
  private var task: Task<Void, Never>?
  private var revision = UUID()
  private var synchronizedAt: [String: Date] = [:]
  private var configuration: Task<Void, Never>?
  private(set) var status = "Kapalı"
  init(server: ConnectedServer, disk: CatalogDiskIndex) {
    self.server = server
    self.disk = disk
  }
  func pause() {
    task?.cancel()
    if task != nil { status = "Eşitleme duraklatıldı" }
  }
  func configure(purge: Bool = false, enabled: Bool? = nil) async {
    let enabled = enabled ?? (server?.profile.indexObjectDefinitions == true)
    pause()
    revision = UUID()
    lease = nil
    synchronizedAt = [:]
    if let task { await task.value }
    let previous = configuration
    let token = revision
    let work = Task { [weak self] in
      if let previous { await previous.value }
      guard let self, let server else { return }
      do {
        let value = try await disk.configureDefinitions(
          owner: server.id, enabled: enabled, purge: purge)
        guard token == revision else { return }
        lease = value
        status = enabled ? "Hazır / eşitleme bekleniyor" : "Kapalı"
      } catch { if token == revision { status = error.localizedDescription } }
    }
    configuration = work
    await work.value
    if revision == token { configuration = nil }
  }
  func remove() async {
    pause()
    revision = UUID()
    lease = nil
    if let configuration { await configuration.value }
    guard let server else { return }
    do { _ = try await disk.configureDefinitions(owner: server.id, enabled: false) } catch {
      status = "Tanım indeksi silinemedi: " + error.localizedDescription
      server.startupError = status
    }
  }
  func refresh(force: Bool = false) {
    guard task == nil, let server, server.online, server.profile.indexObjectDefinitions == true,
      lease != nil
    else { return }
    let token = revision
    status = "Tanım indeksi hazırlanıyor…"
    NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: server)
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        task = nil
        NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: server)
      }
      for db in server.databases.map(\.name) where server.allowsCatalogIndex(db) {
        if !force, Date().timeIntervalSince(synchronizedAt[db] ?? .distantPast) < 300 { continue }
        do {
          try await withReader(database: db) { read in
            try await self.synchronize(database: db, token: token, force: force, read: read)
          }
        } catch {
          if Task.isCancelled || token != revision { return }
          status = "Tanım indeksi: " + error.localizedDescription
        }
      }
    }
  }
  private func withReader(
    database: String,
    operation: (@MainActor (String, Limits) async throws -> Execution) async throws -> Void
  ) async throws {
    guard let server else { throw CancellationError() }
    let expectedGeneration = server.generation
    if server.catalogFixture != nil || server.asyncCatalogFixture != nil {
      try await operation { sql, limits in
        let result = try await server.catalog(sql, database: database, limits: limits)
        guard server.generation == expectedGeneration else { throw CancellationError() }
        return result
      }
      return
    }
    let connection = ODBCConnection()
    let generation = server.generation
    var profile = server.profile
    profile.database = database
    do {
      try await withTaskCancellationHandler {
        try await connection.connect(profile, password: server.password)
        try await operation { sql, limits in
          try Task.checkCancellation()
          guard server.generation == generation, server.online else { throw CancellationError() }
          let result = try await connection.execute(sql, limits: limits)
          guard server.generation == generation else { throw CancellationError() }
          return result
        }
      } onCancel: {
        connection.cancel()
      }
      await connection.disconnect()
    } catch {
      await connection.disconnect()
      await server.recordCatalogFailure(error, generation: generation)
      throw error
    }
  }
  private func synchronize(
    database db: String, token: UUID, force: Bool,
    read: @MainActor (String, Limits) async throws -> Execution
  ) async throws {
    guard let server else { throw CancellationError() }
    try check(token)
    status = "\(db) · Tanımlar eşitleniyor…"
    var limits = Limits()
    limits.rows = 50_001
    limits.totalBytes = 16_777_216
    limits.timeout = 30
    let began = Date()
    let result = try await read(IndexedObjectDefinition.inventorySQL, limits)
    try check(token)
    guard !result.partial, !result.stoppedEarly, result.results.count == 1,
      let rows = result.results.first, rows.values.count <= 50_000
    else { throw SQLFailure("Tanım envanteri kısmi; eski indeks korundu.") }
    let scope = CatalogDiskIndex.scope(profile: server.profile, database: db)
    let generation = try await disk.generation(scope: scope)
    let stamps = try await disk.definitionStamps(scope: scope)
    var ids = Set<Int>()
    var unavailable = 0
    for (offset, row) in rows.values.enumerated() {
      if offset % 100 == 0 { await Task.yield() }
      try check(token)
      guard row.count == 6, let raw = row[0], let id = Int(raw), id > 0, let schema = row[1],
        let name = row[2], let type = row[3], let modified = row[4], ids.insert(id).inserted
      else { throw SQLFailure("Tanım envanteri doğrulanamadı.") }
      if !force,
        stamps[id]
          == IndexedObjectDefinition.stamp(
            schema: schema, name: name, type: type, modified: modified)
      {
        continue
      }
      let object = SchemaObject(
        key: .init(schema: schema, name: name, databaseTrigger: type == "TRD"), objectID: id,
        type: type, digest: nil)
      let fetched = Date()
      var detailLimits = Limits()
      detailLimits.timeout = 15
      detailLimits.totalBytes = 8_388_608
      let output = try await read(SchemaComparison.contentQuery(object), detailLimits)
      try check(token)
      guard !output.partial, !output.stoppedEarly, !output.results.contains(where: \.truncated)
      else { throw SQLFailure("Nesne tanımı kısmi; önceki kayıt korundu.") }
      do {
        let content = try await Task.detached(priority: .utility) {
          try SchemaComparison.decodeContent(output, object: object)
        }.value
        try await save(
          .init(
            id: id, schema: schema, name: name, type: type, sql: content.sql,
            original: content.definition, parentID: row[5].flatMap(Int.init),
            modified: IndexedObjectDefinition.stamp(
              schema: schema, name: name, type: type, modified: modified), fetchedAt: fetched),
          database: db, token: token)
      } catch {
        try check(token)
        unavailable += 1
        // An unreadable definition must not keep an old accessible body.
        if let lease {
          try await disk.removeDefinition(
            scope: scope, id: id, owner: server.id, lease: lease, generation: generation,
            before: Date())
        }
      }
      // One bounded metadata request at a time, yielding between objects.
      try await Task.sleep(for: .milliseconds(25))
    }
    try check(token)
    if let lease {
      try await disk.pruneDefinitions(
        scope: scope, ids: ids, owner: server.id, lease: lease, generation: generation,
        before: began)
    }
    synchronizedAt[db] = Date()
    status = "\(db) · Eşitleme tamamlandı · \(unavailable) okunamadı"
  }
  var isRefreshing: Bool { task != nil }
  private func check(_ token: UUID) throws {
    guard !Task.isCancelled, revision == token, let server, server.online,
      server.profile.indexObjectDefinitions == true
    else { throw CancellationError() }
  }
  private func save(_ value: IndexedObjectDefinition, database: String, token: UUID) async throws {
    try check(token)
    guard let server, let lease, server.allowsCatalogIndex(database) else { return }
    let scope = CatalogDiskIndex.scope(profile: server.profile, database: database)
    let generation = try await disk.generation(scope: scope)
    try check(token)
    try await disk.saveDefinition(
      value, owner: server.id, lease: lease, scope: scope, generation: generation)
  }
  func record(_ value: IndexedObjectDefinition, database: String, generation: UUID) async {
    guard server?.generation == generation, lease != nil else { return }
    do { try await save(value, database: database, token: revision) } catch {
      if !(error is CancellationError) {
        status = "Tanım indeksi güncellenemedi: " + error.localizedDescription
      }
    }
  }
  func cached(database: String, id: Int) async throws -> IndexedObjectDefinition {
    guard let server, !server.online, server.profile.indexObjectDefinitions == true,
      server.allowsCatalogIndex(database)
    else { throw SQLFailure("Çevrimdışı tanım indeksi etkin değil.") }
    let profile = server.profile
    guard
      let value = try await disk.definition(
        scope: CatalogDiskIndex.scope(profile: profile, database: database), id: id)
    else { throw SQLFailure("Bu nesnenin tanımı henüz indekslenmemiş veya okunamamış.") }
    guard !server.online, server.profile == profile else { throw CancellationError() }
    return value
  }
  func items(database: String, folder: Folder, parentID: Int? = nil) async throws -> [CatalogItem] {
    guard let server, !server.online, server.profile.indexObjectDefinitions == true,
      server.allowsCatalogIndex(database)
    else { return [] }
    let types: [String]
    switch folder {
    case .tables: types = ["U"]
    case .views: types = ["V"]
    case .procedures: types = ["P"]
    case .functions: types = ["FN", "IF", "TF"]
    case .synonyms: types = ["SN"]
    case .triggers: types = parentID == nil ? ["TRD"] : ["TR"]
    default: return []
    }
    return try await disk.definitions(
      scope: CatalogDiskIndex.scope(profile: server.profile, database: database), types: types,
      parentID: parentID)
  }
}
