import AppKit
import SQLServerKit

/// Owns opt-in source indexing independently from query sessions and completion.
@MainActor final class ObjectDefinitionIndexController {
  private weak var server: ConnectedServer?
  private let disk: CatalogDiskIndex
  private var lease: UUID?
  private var task: Task<Void, Never>?
  private var revision = UUID()
  private var acceptingSince = Date.distantPast
  private(set) var activities: [String: DefinitionIndexActivity] = [:]
  private var lastProgress = Date.distantPast
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
    for db in activities.keys
    where activities[db]?.phase == .building || activities[db]?.phase == .waiting {
      activities[db]?.phase = .paused
      notify(db)
    }
  }
  func configure(purge: Bool = false, enabled: Bool? = nil, disabledScopes: [String]? = nil) async {
    let enabled = enabled ?? (server?.profile.hasDefinitionIndexes == true)
    let disabledScopes = disabledScopes ?? server.map { server in
      Set(server.databases.map(\.name) + (server.profile.definitionIndexDatabases?.keys.map { $0 } ?? []))
        .filter { !server.profile.indexesDefinitions(in: $0) }
        .map { CatalogDiskIndex.scope(profile: server.profile, database: $0) }
    } ?? []
    pause()
    revision = UUID()
    acceptingSince = Date()
    lease = nil
    synchronizedAt = [:]
    activities = [:]
    if let task { await task.value }
    let previous = configuration
    let token = revision
    let work = Task { [weak self] in
      if let previous { await previous.value }
      guard let self, let server else { return }
      do {
        let value = try await disk.configureDefinitions(
          owner: server.id, enabled: enabled, purge: purge, disabledScopes: disabledScopes)
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
  func refresh(force: Bool = false, database: String? = nil) {
    guard task == nil, let server, server.online, server.profile.hasDefinitionIndexes,
      lease != nil
    else { return }
    let targets = server.databases.map(\.name).filter { server.allowsDefinitionIndex($0) && (database == nil || database == $0) }
    guard !targets.isEmpty else { return }
    let token = revision
    for db in targets {
      if force || Date().timeIntervalSince(synchronizedAt[db] ?? .distantPast) >= 300 {
        activities[db] = .init(phase: .waiting)
      }
    }
    status = "Tanım indeksi hazırlanıyor…"
    NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: server)
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        task = nil
        NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: server)
      }
      for db in targets {
        if !force, Date().timeIntervalSince(synchronizedAt[db] ?? .distantPast) < 300 { continue }
        do {
          activities[db] = .init(phase: .building)
          notify(db)
          try await withReader(database: db) { read in
            try await self.synchronize(database: db, token: token, force: force, read: read)
          }
        } catch {
          if Task.isCancelled || token != revision { return }
          status = "Tanım indeksi: " + error.localizedDescription
          activities[db] = .init(phase: .failed, error: error.localizedDescription)
          notify(db)
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
    activities[db]?.total = rows.values.count
    notify(db)
    let entries = try await Task.detached(priority: .utility) {
      try rows.values.map { try DefinitionIndexEntry($0) }
    }.value
    try check(token)
    let ids = Set(entries.map { $0.object.objectID })
    guard ids.count == entries.count else { throw SQLFailure("Yinelenen tanım kimliği.") }
    let changed = entries.filter { force || stamps[$0.object.objectID] != $0.stamp }
    var processed = entries.count - changed.count
    activities[db]?.processed = processed
    var unavailable = 0
    // Modules use a set-based catalog query. Complex table metadata shares one batch
    // while retaining the existing seven-result decoder and its safety checks.
    for module in [true, false] {
      let subset = changed.filter { $0.isModule == module }
      var size = module ? 64 : 32
      var start = 0
      activities[db]?.stage = module ? "SQL modülleri" : "Tablo ve synonym metadata’sı"
      notify(db, progress: true)
      while start < subset.count {
        try check(token)
        let page = Array(subset[start..<min(start + size, subset.count)])
        let fetched = try await fetchPage(page, database: db, scope: scope,
          generation: generation, token: token, read: read)
        unavailable += fetched.unavailable
        size = min(module ? 200 : 64, fetched.nextSize)
        start += page.count
        processed += page.count
        activities[db]?.processed = processed
        if Date().timeIntervalSince(lastProgress) >= 1 {
          lastProgress = Date(); notify(db, progress: true)
        }
        await Task.yield()
      }
    }
    try check(token)
    if let lease {
      try await disk.pruneDefinitions(
        scope: scope, ids: ids, owner: server.id, lease: lease, generation: generation,
        before: began)
    }
    if let lease {
      try await disk.finishDefinitionSync(
        scope: scope, owner: server.id, lease: lease, generation: generation, expected: ids.count,
        unavailable: unavailable)
    }
    try check(token)
    activities[db] = nil
    notify(db)
    synchronizedAt[db] = Date()
    status = "\(db) · Eşitleme tamamlandı"
  }
  private func fetchPage(
    _ entries: [DefinitionIndexEntry], database: String, scope: String, generation: UUID, token: UUID,
    read: @MainActor (String, Limits) async throws -> Execution
  ) async throws -> (unavailable: Int, nextSize: Int) {
    try check(token)
    let fetched = Date()
    var limits = Limits(); limits.timeout = 30; limits.totalBytes = 8_388_608
    let output = try await read(DefinitionIndexBatch.query(entries), limits)
    try check(token)
    if output.partial || output.stoppedEarly || output.results.contains(where: \.truncated) {
      // Byte-heavy pages split adaptively. Never publish a partially fetched body.
      guard entries.count > 1 else { throw SQLFailure("Nesne tanımı kısmi; önceki kayıt korundu.") }
      let middle = entries.count / 2
      let first = try await fetchPage(Array(entries[..<middle]), database: database, scope: scope,
        generation: generation, token: token, read: read)
      let second = try await fetchPage(Array(entries[middle...]), database: database, scope: scope,
        generation: generation, token: token, read: read)
      return (first.unavailable + second.unavailable, max(1, min(middle, first.nextSize, second.nextSize)))
    }
    let decoded = try await Task.detached(priority: .utility) {
      try DefinitionIndexBatch.decode(output, entries: entries, fetched: fetched)
    }.value
    try check(token)
    guard let server, let lease, server.allowsDefinitionIndex(database) else { throw CancellationError() }
    try await disk.saveDefinitions(decoded.values, owner: server.id, lease: lease,
      scope: scope, generation: generation)
    for id in decoded.unavailable {
      try check(token)
      try await disk.removeDefinition(scope: scope, id: id, owner: server.id, lease: lease,
        generation: generation, before: fetched)
    }
    let heavy = output.bytesRead >= 6_291_456 || Date().timeIntervalSince(fetched) > 2
    let nextSize = heavy ? max(1, entries.count / 2) : output.bytesRead < 2_097_152 ? entries.count * 2 : entries.count
    return (decoded.unavailable.count, nextSize)
  }
  private func notify(_ database: String, progress: Bool = false) {
    guard let server else { return }
    NotificationCenter.default.post(
      name: .init("catalogIndexUpdated"), object: server,
      userInfo: ["database": database, "definitionsOnly": true, "definitionProgress": progress])
  }
  func presentation(database: String) async throws -> DefinitionIndexPresentation {
    guard let server else { throw CancellationError() }
    let profile = server.profile
    let token = revision
    let enabled = server.allowsDefinitionIndex(database)
    let stored =
      enabled
      ? try await disk.definitionStatus(
        scope: CatalogDiskIndex.scope(profile: profile, database: database)) : nil
    guard token == revision, server.profile == profile else { throw CancellationError() }
    return .init(
      enabled: enabled, online: server.online, stored: stored, activity: activities[database])
  }
  var isRefreshing: Bool { task != nil }
  private func check(_ token: UUID) throws {
    guard !Task.isCancelled, revision == token, let server, server.online,
      server.profile.hasDefinitionIndexes
    else { throw CancellationError() }
  }
  private func save(_ value: IndexedObjectDefinition, database: String, token: UUID) async throws {
    try check(token)
    guard let server, let lease, server.allowsDefinitionIndex(database) else { return }
    let scope = CatalogDiskIndex.scope(profile: server.profile, database: database)
    let generation = try await disk.generation(scope: scope)
    try check(token)
    try await disk.saveDefinition(
      value, owner: server.id, lease: lease, scope: scope, generation: generation)
  }
  func record(_ value: IndexedObjectDefinition, database: String, generation: UUID) async {
    guard server?.generation == generation, lease != nil, value.fetchedAt >= acceptingSince else { return }
    do {try await save(value, database: database, token: revision);notify(database)} catch {
      if !(error is CancellationError) {
        status = "Tanım indeksi güncellenemedi: " + error.localizedDescription
        activities[database] = .init(phase: .failed, error: error.localizedDescription)
        notify(database)
      }
    }
  }
  func cached(database: String, id: Int) async throws -> IndexedObjectDefinition {
    guard let server, !server.online, server.profile.hasDefinitionIndexes,
      server.allowsDefinitionIndex(database)
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
    guard let server, !server.online, server.profile.hasDefinitionIndexes,
      server.allowsDefinitionIndex(database)
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
