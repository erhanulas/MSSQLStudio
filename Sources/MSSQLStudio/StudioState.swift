import AppKit
import SQLServerKit

@MainActor final class ConnectedServer: Identifiable {
  let id: UUID
  var profile: ServerProfile
  var password: String
  var metadata = ODBCConnection()
  var generation = UUID()
  var databases: [CatalogItem] = []
  var remembered = false
  static let explorerConnectionChanged = Notification.Name("explorerConnectionChanged")
  var online = true {
    didSet {
      if online != oldValue { NotificationCenter.default.post(name:Self.explorerConnectionChanged,object:self) }
    }
  }
  var healthCheckFixture: (() async throws -> Void)?
  var reconnectFixture: (() async throws -> Void)?
  private var checkingHealth = false
  func checkExplorerHealth() async {
    guard online, !reconnecting, !checkingHealth, catalogFixture == nil || healthCheckFixture != nil else {return}
    checkingHealth=true
    defer {checkingHealth=false}
    let token=generation, connection=metadata
    do {
      if let healthCheckFixture {try await healthCheckFixture()}
      else {
        var limits=Limits();limits.rows=1;limits.timeout=5
        _ = try await connection.execute("SELECT 1;",limits:limits)
      }
    } catch {
      guard generation == token, metadata === connection, online, !reconnecting else {return}
      recordExplorerFailure(error)
    }
  }
  var reconnecting = false
  func pauseIndexing() { indexPreparation?.cancel() }
  func recordExplorerFailure(_ error: Error) {
    startupError = error.localizedDescription
    if let failure = error as? SQLFailure,
      failure.diagnostics.contains(where: { $0.state.hasPrefix("08") }) {
      online = false
      pauseIndexing()
    }
  }
  var startupError: String?
  var catalogFixture: ((String) -> Execution)?
  var indexingDatabases = Set<String>()
  var indexErrors: [String:String] = [:]
  private var indexPreparation: Task<Void, Never>?
  func prepareCatalogIndexes(force: Bool = false) {
    indexPreparation?.cancel()
    let profile = profile, password = password, databases = databases.map(\.name)
    indexPreparation = Task { [weak self] in
      for database in databases {
        guard !Task.isCancelled, let self, self.online else { return }
        indexingDatabases.insert(database); indexErrors[database] = nil
        NotificationCenter.default.post(name:.init("catalogIndexUpdated"),object:self,userInfo:["database":database])
        do {
          _ = try await CatalogIndexService.shared.refresh(profile: profile, password: password, database: database, force: force)
          _ = try await SQLCatalogService.shared.refresh(profile:profile,password:password,database:database,force:force)
          indexingDatabases.remove(database)
          NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: self, userInfo: ["database": database])
        } catch {
          indexingDatabases.remove(database); indexErrors[database] = error.localizedDescription
          NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: self, userInfo: ["database": database, "error": error.localizedDescription])
        }
      }
    }
  }
  init(profile: ServerProfile, password: String) {
    self.id = profile.id
    self.profile = profile
    self.password = password
  }
  func catalog(_ sql: String, database: String, limits: Limits = Limits()) async throws -> Execution {
    if let catalogFixture { return catalogFixture(sql) }
    guard online else { throw SQLFailure("Bağlantı çevrimdışı. Bağlantı ayarlarından yeniden bağlanın.") }
    var profile = self.profile
    profile.database = database
    let token = generation
    let password = self.password
    let connection = ODBCConnection()
    do {
      let result = try await withTaskCancellationHandler {
        try Task.checkCancellation()
        try await connection.connect(profile, password: password)
        try Task.checkCancellation()
        let result = try await connection.execute(sql, limits: limits)
        try Task.checkCancellation()
        return result
      } onCancel: {connection.cancel()}
      await connection.disconnect()
      guard generation == token else { throw CancellationError() }
      return result
    } catch {
      await connection.disconnect()
      if generation == token {recordExplorerFailure(error)}
      throw error
    }
  }
}
struct ObjectEditorKey: Codable, Equatable {
  let serverID: UUID
  let database: String
  let objectID: Int
}
@MainActor final class QueryDocument {
  enum State { case disconnected, connecting, ready, running, cancelling }
  let id = UUID()
  let connection = ODBCConnection()
  var server: ConnectedServer
  var database: String
  var title: String
  var sql = ""
  var savedText = ""
  var pinned = false
  private(set) var lastExecutionSucceeded = false
  private(set) var resultGeneration = 0
  private(set) var repeating = false
  private(set) var lastExecutedSQL: String?
  private(set) var lastExecutedDatabase: String?
  var canRefresh: Bool {
    lastExecutionSucceeded && state == .ready && transactionCount == 0 && lastExecutedDatabase == database
      && lastExecutedSQL.map(TSQL.canRepeatRead) == true
  }
  var favoriteID: UUID?
  var file: URL?
  var state = State.disconnected
  var results: [Rows] = []
  var objectEditorKey: ObjectEditorKey?
  var moduleInitialSQL: String?
  var moduleOriginal: String?
  var moduleObjectID: Int?
  var moduleApplied: (() -> Void)?
  var managedObjectApplied: (() -> Void)?
  var applyingModule = false
  var messages = ""
  var selectedResult = 0
  var transactionCount = 0
  var symbols: [CatalogSymbol] = []
  var intelligenceCatalog: SQLIntelligence.Catalog?
  var catalogDatabase: String?
  var catalogVerified = false
  var catalogError: String?
  var openDefinition: ((CatalogSymbol) -> Void)?
  private var lastCatalogCheck = Date.distantPast
  func ensureCatalogFresh() {
    guard intelligenceCatalog?.fresh != true, Date().timeIntervalSince(lastCatalogCheck) > 30, server.online else { return }
    lastCatalogCheck = Date()
    Task { [weak self] in await self?.loadSymbols() }
  }
  private var symbolRequest = UUID()
  func clearSymbols() {
    symbols = []; intelligenceCatalog = nil; catalogDatabase = nil; catalogVerified = false; symbolRequest = UUID()
    NotificationCenter.default.post(name:.init("sqlCatalogChanged"),object:self)
  }
  var elapsed = 0.0
  var rowCount = 0
  var partial = false
  var initialRefreshSeconds: Int?
  var limits: Limits = ResultReadPreferences.limits(rows:ResultReadPreferences.readLimit)
  var actualPlan = false
  var task: Task<Void, Never>?
  var changed: (() -> Void)?
  var completed: ((String, Execution?, String?) -> Void)?
  var confirmDiscardResultEdits: (() -> Bool)?
  private var acceptingEvents = false
  private var executionID = UUID()
  var runAfterConnect = false
  var selectedRange = NSRange(location: 0, length: 0)
  var dirty: Bool { sql != savedText }
  var hasPendingDatabaseChanges: Bool { moduleInitialSQL.map {sql != $0} ?? false }
  var canSubmitModule: Bool {
    server.online && state == .ready && !busy && transactionCount == 0 &&
      moduleObjectID != nil && objectEditorKey?.database == database &&
      moduleOriginal != nil && hasPendingDatabaseChanges
  }
  var needsCloseConfirmation: Bool { dirty || hasPendingDatabaseChanges }
  func acceptAppliedModule(sql executed: String, original: String) {
    moduleOriginal=original; moduleInitialSQL=executed
    if file == nil {savedText=executed}
    changed?()
  }
  var busy: Bool { [.connecting, .running, .cancelling].contains(state) }
  init(server: ConnectedServer, database: String, title: String) {
    self.server = server
    self.database = database
    self.title = title
  }
  func connect() {
    guard !busy else { return }
    guard server.online else { state = .disconnected; changed?(); return }
    state = .connecting
    changed?()
    var profile = server.profile
    profile.database = database
    let password = server.password
    task = Task { [weak self] in
      guard let self else { return }
      do {
        try await connection.connect(profile, password: password)
        state = .ready
        messages = "Bağlandı: \(profile.host) / \(database)\n"
        changed?()
        Task { [weak self] in await self?.loadSymbols() }
      } catch {
        state = .disconnected
        await recordConnectionFailure(error)
        messages = error.localizedDescription
        changed?()
      }
      task = nil
      if runAfterConnect && state == .ready {
        runAfterConnect = false
        execute()
      }
    }
  }
  func loadSymbols(force: Bool = false) async {
    let database = self.database, generation = server.generation, request = UUID()
    symbolRequest = request
    let profile = server.profile, password = server.password
    func publish(_ catalog: SQLIntelligence.Catalog, verified: Bool) {
      guard self.database == database, server.generation == generation, symbolRequest == request else { return }
      intelligenceCatalog = catalog; catalogDatabase = database; catalogVerified = verified; catalogError = nil
      symbols = catalog.snapshot.symbols
      NotificationCenter.default.post(name:.init("sqlCatalogChanged"),object:self)
      changed?()
    }
    do {
      if let cached = try await SQLCatalogService.shared.cached(profile:profile,database:database) { publish(cached,verified:!force && cached.fresh) }
      let catalog = try await SQLCatalogService.shared.refresh(profile:profile,password:password,database:database,force:force)
      publish(catalog,verified:true)
    } catch {
      guard symbolRequest == request else { return }
      catalogVerified = false; catalogError = error.localizedDescription
      NotificationCenter.default.post(name:.init("sqlCatalogChanged"),object:self)
    }
  }
  func useDatabase(_ name: String) {
    guard state == .ready else { return }
    state = .running
    changed?()
    task = Task { [weak self] in
      guard let self else { return }
      do {
        _ = try await connection.execute("USE \(SQL.identifier(name));")
        database = name
        clearSymbols()
        messages += "Veritabanı: \(name)\n"
        changed?()
        await loadSymbols()
        state = .ready
        changed?()
      } catch {
        state = .ready
        await recordConnectionFailure(error)
        messages += error.localizedDescription + "\n"
        changed?()
      }
      task = nil
    }
  }
  func execute(override: String? = nil, estimated: Bool = false, repeatRead: Bool = false) {
    guard state == .ready, confirmDiscardResultEdits?() != false else { return }
    let source = sql as NSString
    let query =
      override
      ?? (selectedRange.length > 0 && NSMaxRange(selectedRange) <= source.length
        ? source.substring(with: selectedRange) : sql)
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    repeating = repeatRead
    resultGeneration += 1
    lastExecutionSucceeded = false
    lastExecutedSQL = estimated ? nil : query
    lastExecutedDatabase = database
    state = .running
    results = []
    messages = "Çalıştırma: \(Date().formatted(date: .numeric, time: .standard)) · \(database)\n"
    partial = false
    elapsed = 0
    rowCount = 0
    selectedResult = 0
    changed?()
    acceptingEvents = true
    executionID = UUID()
    let token = executionID
    let start = Date()
    let captureActual = actualPlan && !estimated
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        task = nil
        if state != .disconnected {state = .ready}
        if applyingModule && lastExecutionSucceeded && !partial && transactionCount == 0 { moduleApplied?() }
        if !estimated && lastExecutionSucceeded && !partial && transactionCount == 0 && !ModuleEditing.changedObjects(query).isEmpty {
          NotificationCenter.default.post(name: .init("studioDDLCompleted"), object: self)
        }
        if !estimated && lastExecutionSucceeded && !partial && transactionCount == 0 {managedObjectApplied?()}
        applyingModule = false
        changed?()
      }
      do {
        if estimated {
          guard
            !TSQL.lex(query).contains(where: {
              $0.kind != .comment && $0.text.uppercased() == "SHOWPLAN_XML"
            })
          else { throw SQLFailure("Tahmini plana SHOWPLAN_XML komutu eklenemez.") }
          _ = try await connection.execute("SET SHOWPLAN_XML ON;")
        } else if captureActual {
          _ = try await connection.execute("SET STATISTICS XML ON;")
        }
        let output = try await TSQL.run(
          query, on: connection, limits: limits,
          events: { [weak self] event in
            Task { @MainActor [weak self] in
              guard let self, self.executionID == token,
                self.state == .running || self.state == .cancelling
              else { return }
              self.receive(event)
            }
          })
        acceptingEvents = false
        results = output.results
        messages += output.messages.joined(separator: "\n") + "\n"
        partial = output.partial
        rowCount = output.results.filter { !$0.isPlan }.reduce(0) { $0 + $1.values.count }
        elapsed = output.elapsed
        for result in output.results where result.fields.isEmpty && result.affected >= 0 {
          messages += "(\(result.affected) satır etkilendi)\n"
        }
        if estimated { messages += "Tahmini plan alındı; sorgu çalıştırılmadı.\n" }
        messages += String(
          format: "%.3f sn · %d satır%@\n", elapsed, rowCount, partial ? " · KISMİ SONUÇ" : "")
        lastExecutionSucceeded = true
        completed?(query, output, nil)

      } catch {
        acceptingEvents = false
        elapsed = Date().timeIntervalSince(start)
        messages += error.localizedDescription + "\n"
        partial = !results.isEmpty
        if let index = results.lastIndex(where: { !$0.fields.isEmpty }) { results[index].truncated = true }
        completed?(query, nil, error.localizedDescription)
        await recordConnectionFailure(error)
      }
      if state != .disconnected {
        if estimated { _ = try? await connection.execute("SET SHOWPLAN_XML OFF;") }
        if captureActual { _ = try? await connection.execute("SET STATISTICS XML OFF;") }
        do {
          var limits=Limits();limits.rows=1;limits.timeout=5
          let result = try await connection.execute("SELECT @@TRANCOUNT, DB_NAME();",limits:limits)
          if let row = result.results.first?.values.first, row.count > 1 {
            transactionCount = row[0].flatMap(Int.init) ?? 0
            if let database = row[1], self.database != database {
              self.database = database
              clearSymbols()
              Task { [weak self] in await self?.loadSymbols() }
            }
          }
        } catch {await recordConnectionFailure(error)}
      }
    }
  }
  private func recordConnectionFailure(_ error:Error) async {
    guard let failure=error as? SQLFailure,
      failure.diagnostics.contains(where:{$0.state.hasPrefix("08")}) else {return}
    state = .disconnected
    // Query sessions are independent: verify the Explorer session itself.
    await server.checkExplorerHealth()
  }
  private func receive(_ event: QueryEvent) {
    guard acceptingEvents else { return }
    switch event {
    case .source(let index, let source):
      while results.count <= index { results.append(Rows()) }
      results[index].source = source
    case .result(let index, let fields):
      while results.count <= index { results.append(Rows()) }
      results[index].fields = fields
    case .rows(let index, let rows):
      while results.count <= index { results.append(Rows()) }
      results[index].values.append(contentsOf: rows)
      rowCount += rows.count
    case .snapshot(let index, let rows):
      while results.count <= index { results.append(Rows()) }
      rowCount += rows.count - results[index].values.count
      results[index].values = rows
    case .message(let text): messages += text + "\n"
    }
    changed?()
  }
  func cancel() {
    guard state == .running else { return }
    state = .cancelling
    task?.cancel()
    connection.cancel()
    changed?()
  }
  func disconnect() {
    guard !busy else { return }
    Task { await connection.disconnect() }
    state = .disconnected
    changed?()
  }
}
@MainActor final class StudioState {
  var explorerTreeDefaults:UserDefaults = {
    if Bundle.main.bundleIdentifier == "local.mssqlstudio.uitest" {return .standard}
    if ProcessInfo.processInfo.arguments.contains(where:{$0.contains(".xctest")}) || ProcessInfo.processInfo.arguments.contains("--ui-smoke") {
      return UserDefaults(suiteName:"local.mssqlstudio.tree-test-"+UUID().uuidString)!
    }
    return .standard
  }()
  var explorerOrderDefaults=UserDefaults.standard
  @discardableResult func moveExplorer(_ id:UUID,to insertionIndex:Int) -> Bool {
    guard (0...servers.count).contains(insertionIndex),let old=servers.firstIndex(where:{$0.id == id}) else {return false}
    let destination=insertionIndex > old ? insertionIndex-1:insertionIndex
    guard destination != old else {return false}
    let server=servers.remove(at:old);servers.insert(server,at:destination)
    explorerOrderDefaults.set(servers.map {$0.id.uuidString},forKey:"explorerServerOrder")
    changed?()
    return true
  }
  var servers: [ConnectedServer] = []
  var documents: [QueryDocument] = []
  var active: QueryDocument?
  var changed: (() -> Void)?
  var history: [QueryRecord] = []
  lazy var favorites = FavoriteQueriesModel(url: (Bundle.main.bundleIdentifier == "local.mssqlstudio.uitest" || ProcessInfo.processInfo.arguments.contains("--ui-smoke") || ProcessInfo.processInfo.arguments.contains(where:{$0.contains(".xctest")})
    ? URL(fileURLWithPath:"/tmp/MSSQLStudio-UI-\(ProcessInfo.processInfo.processIdentifier)") : folder).appendingPathComponent("favorites.json"))
  private var nextQueryNumber = 1
  var historyEnabled = UserDefaults.standard.bool(forKey: "historyEnabled")
  var historyRetentionDays = QueryHistoryPolicy.days(UserDefaults.standard.object(forKey: "historyRetentionDays") as? Int ?? QueryHistoryPolicy.defaultDays)
  private var snapshotTask: Task<Void, Never>?
  var recoveryEnabled = UserDefaults.standard.bool(forKey: "recoveryEnabled")
  let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("MSSQLStudio")
  func connect(_ profile: ServerProfile, password: String, save: Bool) async throws
    -> ConnectedServer
  {
    if let old = servers.first(where: { $0.id == profile.id }) {
      let reconnect =
        !old.profile.hasSameConnectionSettings(as: profile) || old.password != password
      func checkSessions() throws {
        guard
          !self.documents.contains(where: {
            $0.server === old && ($0.busy || $0.transactionCount > 0)
          })
        else {
          throw SQLFailure(
            "Bağlantı bilgilerini değiştirmeden önce çalışan sorguları ve açık transaction’ları tamamlayın."
          )
        }
      }
      if reconnect { try checkSessions() }
      let candidate = ODBCConnection()
      do {
        try await candidate.connect(profile, password: password)
        let items = Catalog.rows(try await candidate.execute(Catalog.databases))
        if reconnect { try checkSessions() }
        if save || old.remembered {
          try ServerVault().save(profile, password: profile.kerberos ? "" : password)
          UserDefaults.standard.set(profile.id.uuidString, forKey: "lastSavedServer")
        }
        if reconnect {
          let documents = self.documents.filter { $0.server === old }
          // Mark every affected tab busy before yielding so detached windows cannot start SQL.
          for doc in documents {
            doc.state = .connecting
            doc.changed?()
          }
          old.generation = UUID()
          let previous = old.metadata
          old.metadata = candidate
          old.profile = profile
          old.password = password
          for doc in documents { await doc.connection.disconnect() }
          await previous.disconnect()
          for doc in documents {
            doc.database = profile.database
            doc.results = []
            doc.clearSymbols()
            doc.selectedResult = 0
            doc.rowCount = 0
            doc.elapsed = 0
            doc.partial = false
            doc.runAfterConnect = false
            doc.state = .disconnected
            doc.connect()
          }
        } else {
          let previous = old.metadata
          old.metadata = candidate
          old.profile = profile
          old.password = password
          await previous.disconnect()
        }
        old.databases = profile.visibleItems(from: items)
        old.online = true; old.startupError = nil
        old.prepareCatalogIndexes()
        if save || old.remembered { rememberExplorer(profile.id, selected: true) }
        old.remembered = old.remembered || save
        changed?()
        return old
      } catch {
        await candidate.disconnect()
        throw error
      }
    }
    let server = ConnectedServer(profile: profile, password: password)
    do {
      try await server.metadata.connect(profile, password: password)
      server.databases = profile.visibleItems(
        from: Catalog.rows(try await server.metadata.execute(Catalog.databases)))
      if save { try ServerVault().save(profile, password: profile.kerberos ? "" : password) }
      server.remembered = save
      if save { UserDefaults.standard.set(profile.id.uuidString, forKey: "lastSavedServer") }
    } catch {
      await server.metadata.disconnect()
      throw error
    }
    servers.removeAll { $0.id == server.id && !$0.online }
    servers.append(server)
    server.prepareCatalogIndexes()
    if save { rememberExplorer(profile.id, selected: true) }
    changed?()
    return server
  }
  // Explorer metadata is independent of each query's session and transaction.
  func disconnectExplorer(_ server: ConnectedServer) async {
    guard !server.reconnecting else { return }
    server.online = false
    server.startupError = nil
    server.pauseIndexing()
    let previous = server.metadata
    server.metadata = ODBCConnection()
    changed?()
    await previous.disconnect()
  }
  func removeExplorer(_ server: ConnectedServer) async {
    guard !server.reconnecting else { return }
    servers.removeAll { $0 === server }
    rememberExplorer(server.id, selected:false)
    await disconnectExplorer(server)
    changed?()
  }
  func reconnectExplorer(_ server: ConnectedServer) async {
    guard !server.reconnecting else { return }
    server.reconnecting = true
    server.startupError = nil
    changed?()
    defer { server.reconnecting = false; changed?() }
    do {
      if let reconnectFixture=server.reconnectFixture {
        try await reconnectFixture(); server.online=true; return
      }
      if !servers.contains(where:{$0 === server}) {servers.append(server)}
      _ = try await connect(server.profile, password: server.password, save: false)
    } catch {
      server.startupError = error.localizedDescription
    }
  }
  func prepareExplorerForNewQuery(_ server:ConnectedServer) async -> Bool {
    guard !server.reconnecting else {return false}
    if !server.online {await reconnectExplorer(server)}
    return server.online
  }
  func rememberExplorer(_ id: UUID, selected: Bool) {
    var ids = UserDefaults.standard.stringArray(forKey: "explorerActiveServerIDs") ?? servers.filter(\.remembered).map { $0.id.uuidString }
    ids.removeAll { $0 == id.uuidString }
    if selected { ids.append(id.uuidString) }
    UserDefaults.standard.set(ids, forKey: "explorerActiveServerIDs")
  }
  func restoreExplorers() async -> Bool {
    do {
      let saved = try await Task.detached { try ServerVault().list() }.value
      let selected = ExplorerPersistence.selectedIDs(saved: saved.map { $0.profile.id }, previous: UserDefaults.standard.stringArray(forKey: "explorerActiveServerIDs"))
      let ids=ExplorerPersistence.orderedIDs(selected,previous:explorerOrderDefaults.stringArray(forKey:"explorerServerOrder"))
      UserDefaults.standard.set(ids.map(\.uuidString), forKey: "explorerActiveServerIDs")
      let chosen = ids.compactMap { id in saved.first { $0.profile.id == id } }
      for record in chosen where !servers.contains(where: { $0.id == record.profile.id }) {
        let server = ConnectedServer(profile: record.profile,password: record.password)
        server.online = false; server.remembered = true
        server.databases = (record.profile.visibleDatabases ?? [record.profile.database]).map { name in
          CatalogItem(id: ["master":1,"tempdb":2,"model":3,"msdb":4][name] ?? 10,name:name)
        }
        servers.append(server)
      }
      changed?()
      for server in servers where !server.online {
        do {
          try await server.metadata.connect(server.profile,password:server.password)
          server.databases = server.profile.visibleItems(from: Catalog.rows(try await server.metadata.execute(Catalog.databases)))
          server.online = true; server.startupError = nil; server.generation = UUID()
          server.prepareCatalogIndexes()
          changed?()
          recover(for:server)
          if !documents.contains(where: { $0.server === server }) { newQuery(server:server) }
        } catch { server.startupError = error.localizedDescription; changed?() }
      }
      return !chosen.isEmpty
    } catch { showError("Kayıtlı Explorer bağlantıları okunamadı: " + error.localizedDescription); return true }
  }
  @discardableResult func newQuery(
    server: ConnectedServer, database: String? = nil, text: String = "", title: String? = nil,
    run: Bool = false, refreshSeconds: Int? = nil
  ) -> QueryDocument {
    let doc = QueryDocument(
      server: server, database: database ?? server.profile.database,
      title: title ?? "SQLQuery\(nextQueryNumber).sql")
    nextQueryNumber += 1
    doc.sql = text
    doc.savedText = text // Generated/opened text is the baseline, not a user edit.
    doc.completed = { [weak self, weak doc] sql, result, error in
      guard let self, let doc, self.historyEnabled else { return }
      self.history.insert(
        QueryRecord(
          server: doc.server.profile.name, database: doc.lastExecutedDatabase ?? doc.database, text: sql,
          serverID: doc.server.id, errorMessage: error, rowCount: result?.results.reduce(0) { $0 + $1.values.count },
          seconds: result?.elapsed ?? 0,
          status: error == nil ? (result?.partial == true ? "Kısmi" : "Başarılı") : "Hata"), at: 0)
      self.history = QueryHistoryPolicy.retained(self.history, days: self.historyRetentionDays)
      self.saveHistory()
    }
    documents.append(doc)
    active = doc
    doc.runAfterConnect = run
    doc.initialRefreshSeconds = refreshSeconds
    changed?()
    doc.connect()

    return doc
  }
  func scheduleSnapshot() {
    guard recoveryEnabled else { return }
    snapshotTask?.cancel()
    snapshotTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      self?.saveSnapshot()
    }
  }
  struct SavedTab: Codable {
    var title: String
    var sql: String
    var saved: String
    var path: String?
    var serverID: UUID
    var database: String
    var endpoint: String?
    var pinned: Bool? = nil
    var objectKey: ObjectEditorKey? = nil
    var moduleOriginal: String? = nil
    var moduleInitialSQL: String? = nil
  }
  @discardableResult func saveSnapshot() -> Bool {
    guard recoveryEnabled else { return true }
    do {
      try write(
        documents.map {
          SavedTab(
            title: $0.title, sql: $0.sql, saved: $0.savedText, path: $0.file?.path,
            serverID: $0.server.id, database: $0.database, endpoint: endpoint($0.server.profile), pinned: $0.pinned, objectKey:$0.objectEditorKey, moduleOriginal:$0.moduleOriginal, moduleInitialSQL:$0.moduleInitialSQL)
        }, name: "tabs.json")
      return true
    } catch {
      showError(error.localizedDescription)
      return false
    }
  }
  private func endpoint(_ profile: ServerProfile) -> String {
    "\(profile.host.lowercased()):\(profile.port)|\(profile.login)|\(profile.kerberos)"
  }
  func recover(for server: ConnectedServer) {
    guard recoveryEnabled else { return }
    do {
      let url = folder.appendingPathComponent("tabs.json")
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      let data = try Data(contentsOf: url)
      guard data.count < 20_000_000 else { return }
      for tab in try JSONDecoder().decode([SavedTab].self, from: data).filter({
        $0.serverID == server.id || $0.endpoint == endpoint(server.profile)
      }).prefix(30) {
        let doc = newQuery(server: server, database: tab.database, text: tab.sql, title: tab.title)
        doc.pinned = tab.pinned ?? false
        doc.savedText = tab.saved
        doc.file = tab.path.map { URL(fileURLWithPath: $0) }
        if let key=tab.objectKey {doc.objectEditorKey=ObjectEditorKey(serverID:server.id,database:key.database,objectID:key.objectID);doc.moduleObjectID=key.objectID}
        doc.moduleOriginal=tab.moduleOriginal;doc.moduleInitialSQL=tab.moduleInitialSQL
      }
    } catch { showError(error.localizedDescription) }
  }
  func historyServer(_ record: QueryRecord) -> ConnectedServer? {
    if let id = record.serverID { return servers.first { $0.id == id } }
    let matching = servers.filter { $0.profile.name == record.server }
    return matching.count == 1 ? matching.first : nil
  }
  func saveHistory() {
    history = QueryHistoryPolicy.retained(history, days: historyRetentionDays)
    do { try write(history, name: "history.json"); NotificationCenter.default.post(name: .init("queryHistoryChanged"), object: self) } catch { showError(error.localizedDescription) }
  }
  func loadHistory() {
    do {
      let data = try Data(contentsOf: folder.appendingPathComponent("history.json"))
      if data.count < 20_000_000 {
        history = QueryHistoryPolicy.retained(try JSONDecoder().decode([QueryRecord].self, from: data), days: historyRetentionDays)
        saveHistory()
      }
    } catch {
      if FileManager.default.fileExists(atPath: folder.appendingPathComponent("history.json").path)
      {
        showError(error.localizedDescription)
      }
    }
  }
  private func write<T: Encodable>(_ value: T, name: String) throws {
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let data = try JSONEncoder().encode(value)
    guard data.count < 20_000_000 else { throw SQLFailure("Yerel kayıt 20 MB sınırını aştı.") }
    let url = folder.appendingPathComponent(name)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
  func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "MSSQL Studio"
    alert.informativeText = message
    alert.runModal()
  }
  func close(_ doc: QueryDocument) -> Bool {
    guard !doc.busy else {
      showError("Önce çalışan sorguyu durdurun.")
      return false
    }
    guard doc.transactionCount == 0 else {
      showError("Önce COMMIT veya ROLLBACK çalıştırın.")
      return false
    }
    guard confirmSave(doc) else { return false }
    doc.disconnect()
    documents.removeAll { $0.id == doc.id }
    if active === doc { active = documents.last }
    changed?()
    scheduleSnapshot()
    return true
  }
  func confirmSave(_ doc: QueryDocument) -> Bool {
    guard doc.confirmDiscardResultEdits?() != false else { return false }
    guard doc.needsCloseConfirmation else { return true }
    let alert = NSAlert()
    alert.messageText = "\(doc.title) kaydedilsin mi?"
    if doc.hasPendingDatabaseChanges {alert.informativeText="Bu nesnede veritabanına uygulanmamış düzenlemeler var. Dosyaya kaydetmek veritabanına uygulamaz."}
    alert.addButton(withTitle: "Kaydet")
    alert.addButton(withTitle: "Vazgeç")
    alert.addButton(withTitle: "Kaydetmeden kapat")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return save(doc)
    case .alertThirdButtonReturn: return true
    default: return false
    }
  }
  @discardableResult func save(_ doc: QueryDocument, asNew: Bool = false) -> Bool {
    var target = doc.file
    if target == nil || asNew {
      let panel = NSSavePanel()
      panel.nameFieldStringValue = doc.title
      guard panel.runModal() == .OK else { return false }
      target = panel.url
    }
    guard let target else { return false }
    do {
      if target == doc.file, let disk = try? String(contentsOf: target, encoding: .utf8),
        disk != doc.savedText
      {
        let alert = NSAlert()
        alert.messageText = "Dosya diskte değişmiş"
        alert.informativeText = "Diskteki değişikliklerin üzerine yazılsın mı?"
        alert.addButton(withTitle: "Vazgeç")
        alert.addButton(withTitle: "Üzerine yaz")
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
      }
      try doc.sql.write(to: target, atomically: true, encoding: .utf8)
      doc.file = target
      doc.title = target.lastPathComponent
      doc.savedText = doc.sql
      changed?()
      scheduleSnapshot()
      return true
    } catch {
      showError(error.localizedDescription)
      return false
    }
  }
  func canQuit() -> Bool {
    guard documents.allSatisfy({ !$0.busy && $0.transactionCount == 0 }) else {
      showError("Çalışan sorguları ve açık transaction'ları tamamlayın.")
      return false
    }
    if recoveryEnabled { return saveSnapshot() }
    return documents.allSatisfy(confirmSave)
  }
}
