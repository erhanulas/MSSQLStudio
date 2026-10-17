import AppKit
import SQLServerKit

/// Owns opt-in source indexing independently from query sessions and completion.
@MainActor final class ObjectDefinitionIndexController {
  private weak var server: ConnectedServer?
  private let disk: CatalogDiskIndex
  private var lease: UUID?
  private var task: Task<Void, Never>?
  private var retryTask:Task<Void,Never>?
  private var retryDates:[String:Date]=[:]
  private let retryDelay:TimeInterval
  private var revision = UUID()
  private var acceptingSince = Date.distantPast
  private(set) var activities: [String: DefinitionIndexActivity] = [:]
  private var lastProgress = Date.distantPast
  private var synchronizedAt: [String: Date] = [:]
  private var pendingDDLDatabases=Set<String>()
  private var configuration: Task<Void, Never>?
  private(set) var status = "Kapalı"
  init(server: ConnectedServer, disk: CatalogDiskIndex, retryDelay:TimeInterval = 30) {
    self.server = server
    self.disk = disk
    self.retryDelay=retryDelay
  }
  deinit {retryTask?.cancel();task?.cancel()}
  func pause() {
    retryTask?.cancel();retryTask=nil;retryDates.removeAll()
    for db in activities.keys where activities[db]?.retryAt != nil {activities[db]?.retryAt=nil;activities[db]?.phase = .paused;notify(db)}
    pendingDDLDatabases.removeAll()
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
  func refreshAfterDDL(database: String) {
    guard let server,server.online,server.allowsDefinitionIndex(database) else {return}
    synchronizedAt[database] = .distantPast
    if task != nil {pendingDDLDatabases.insert(database)}
    else {refresh(database:database)}
  }
  func refresh(force: Bool = false, database: String? = nil) {
    guard task == nil, let server, server.online, server.profile.hasDefinitionIndexes,
      lease != nil
    else { return }
    let targets = server.databases.map(\.name).filter { server.allowsDefinitionIndex($0) && (database == nil || database == $0) && (force || database == $0 || retryDates[$0].map {$0<=Date()} != false) }
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
        let pending=pendingDDLDatabases
        pendingDDLDatabases.removeAll()
        if !pending.isEmpty,!Task.isCancelled,revision==token {
          for db in pending {synchronizedAt[db] = .distantPast}
          refresh()
        }
        scheduleRetries()
      }
      for db in targets {
        if !force, Date().timeIntervalSince(synchronizedAt[db] ?? .distantPast) < 300 { continue }
        do {
          activities[db] = .init(phase: .building)
          notify(db)
          retryDates[db]=nil
          try await withReader(database: db) { read in
            try await self.synchronize(database: db, token: token, force: force, read: read)
          }
          retryDates[db]=nil
        } catch {
          if error is CancellationError || Task.isCancelled || token != revision {
            if token==revision {activities[db]?.phase = .paused;notify(db)}
            return
          }
          status = "Tanım indeksi: " + error.localizedDescription
          activities[db] = .init(phase: .failed, error: error.localizedDescription)
          if retryable(error) {
            let date=Date().addingTimeInterval(max(0.01,retryDelay))
            retryDates[db]=date;activities[db]?.retryAt=date
          }
          notify(db)
        }
      }
    }
  }
  private func retryable(_ error:Error)->Bool {
    guard let failure=error as? SQLFailure,!failure.diagnostics.isEmpty else {return false}
    return failure.diagnostics.allSatisfy {diagnostic in
      diagnostic.state=="HYT00" || diagnostic.state=="HYT01" || diagnostic.state.hasPrefix("08") || diagnostic.state=="40001"
    }
  }
  private func scheduleRetries() {
    guard task==nil,retryTask==nil,let first=retryDates.values.min(),let server,lease != nil else {return}
    let token=revision,generation=server.generation
    let delay=max(0.01,first.timeIntervalSinceNow)
    retryTask=Task { [weak self,weak server] in
      do {try await Task.sleep(for:.seconds(delay))} catch {return}
      guard let self,let server else {return}
      retryTask=nil
      guard revision==token,!Task.isCancelled else {return}
      guard server.generation==generation else {
        retryDates.removeAll()
        for db in activities.keys where activities[db]?.retryAt != nil {activities[db]?.retryAt=nil;activities[db]?.phase = .paused;notify(db)}
        return
      }
      let due=retryDates.filter {$0.value<=Date()}.map(\.key)
      for db in due {
        guard server.allowsDefinitionIndex(db),server.databases.contains(where:{$0.name==db}) else {retryDates[db]=nil;activities[db]=nil;continue}
        if !server.online {retryDates[db]=Date().addingTimeInterval(30);activities[db]?.retryAt=retryDates[db];notify(db);continue}
        retryDates[db]=nil;synchronizedAt[db] = .distantPast
        pendingDDLDatabases.insert(db)
      }
      if task==nil,!pendingDDLDatabases.isEmpty {
        pendingDDLDatabases.removeAll();refresh()
      }
      scheduleRetries()
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
    limits.timeout = 120
    let began = Date()
    activities[db]?.stage="Nesne envanteri"
    let result:Execution
    do {result=try await read(IndexedObjectDefinition.inventorySQL,limits);if let failure=result.failure {throw failure}}
    catch {throw readFailure(error,context:"\(db) · Nesne envanteri (120 sn)")}
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
      var size = 200
      var start = 0
      activities[db]?.stage = module ? "SQL modülleri" : "Tablo ve synonym metadata’sı"
      notify(db, progress: true)
      while start < subset.count {
        try check(token)
        let page = Array(subset[start..<min(start + size, subset.count)])
        let fetched = try await fetchPage(page, database: db, scope: scope,
          generation: generation, token: token, read: read)
        unavailable += fetched.unavailable
        size = min(200, fetched.nextSize)
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
    var limits = Limits(); limits.timeout = 120; limits.totalBytes = 8_388_608
    let output:Execution
    do {
      output=try await read(DefinitionIndexBatch.query(entries),limits)
      if let failure=output.failure {throw failure}
    } catch {
      try check(token)
      let target=entries.count==1 ? entries[0].object.key.schema+"."+entries[0].object.key.name:"\(entries.count) nesnelik okuma grubu"
      throw readFailure(error,context:"\(database) · \(entries[0].isModule ? "SQL modülleri":"Tablo/synonym metadata’sı") · \(target) (120 sn)")
    }
    try check(token)
    if output.partial || output.stoppedEarly || output.results.contains(where: \.truncated) {
      // Byte-heavy pages split adaptively. Never publish a partially fetched body.
      guard entries.count > 1 else { throw SQLFailure("Nesne tanımı kısmi; önceki kayıt korundu.") }
      return try await splitPage(entries,database:database,scope:scope,generation:generation,token:token,read:read)
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
    return (decoded.unavailable.count,entries.count)
  }
  private func splitPage(
    _ entries:[DefinitionIndexEntry],database:String,scope:String,generation:UUID,token:UUID,
    read:@MainActor (String,Limits) async throws -> Execution
  ) async throws -> (unavailable:Int,nextSize:Int) {
    let middle=entries.count/2
    let first=try await fetchPage(Array(entries[..<middle]),database:database,scope:scope,generation:generation,token:token,read:read)
    let second=try await fetchPage(Array(entries[middle...]),database:database,scope:scope,generation:generation,token:token,read:read)
    return (first.unavailable+second.unavailable,max(1,min(middle,first.nextSize,second.nextSize)))
  }
  private func readFailure(_ error:Error,context:String)->Error {
    guard !(error is CancellationError) else {return error}
    if let failure=error as? SQLFailure {return SQLFailure(context+": "+failure.message,diagnostics:failure.diagnostics,batchLine:failure.batchLine)}
    return SQLFailure(context+": "+error.localizedDescription)
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
    var result=value
    if value.type == "U" {
      let scope=CatalogDiskIndex.scope(profile:profile,database:database)
      let triggers=try await disk.definitions(scope:scope,types:["TR"],parentID:id)
      var scripts=[value.sql]
      for trigger in triggers {
        try Task.checkCancellation()
        if let definition=try await disk.definition(scope:scope,id:trigger.id) {scripts.append(definition.sql)}
      }
      if scripts.count>1 {result=IndexedObjectDefinition(id:value.id,schema:value.schema,name:value.name,type:value.type,sql:scripts.joined(separator:"\nGO\n"),original:value.original,parentID:value.parentID,modified:value.modified,fetchedAt:value.fetchedAt)}
    }
    guard !server.online, server.profile == profile else { throw CancellationError() }
    return result
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
