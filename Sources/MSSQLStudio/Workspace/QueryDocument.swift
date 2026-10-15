import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

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
  private var pendingDDLChanges:[ModuleEditing.Change]=[]
  private var pendingDDLGeneration:UUID?
  private(set) var lastExecutionSucceeded = false
  private(set) var resultGeneration = 0
  private(set) var repeating = false
  private(set) var lastExecutionDate: Date?
  private(set) var lastExecutedSQL: String?
  private(set) var lastExecutedDatabase: String?
  private(set) var lastExecutedReadLimit: Int?
  // In-process test injection; normal documents always use their independent ODBC session.
  var databaseChangeFixture: ((String) async throws -> Void)?
  var connectionFixture: ((ServerProfile, String) async throws -> Void)?
  var connectionError: String?
  var offlinePreviewRequest=UUID()
  var offlinePreview: OfflineDefinitionPreview? {didSet {offlinePreviewRequest=UUID()}}
  var openOfflineReference: (([String], ConnectedServer, String) -> Void)?
  var revealInExplorer: (([String],ConnectedServer,String) -> Void)?
  var openDefinitionNamed: (([String]) -> Void)?
  var canExecute: Bool { !busy && !definitionLoading && offlinePreview == nil && !server.updatingProfile }
  var executionFixture: ((String, Limits) async throws -> Execution)?
  var sessionProbeFixture: ((String, Limits) async throws -> Execution)?
  var refreshDisabledReason: String? {
    if offlinePreview != nil {return "SQL’e dönmeden sonuçlar yenilenemez."}
    switch state {
    case .running, .cancelling: return "Sorgu işlemi sürerken sonuçlar yenilenemez."
    case .connecting: return "Bağlantı kurulurken sonuçlar yenilenemez."
    case .disconnected: return "Sorgu bağlantısı kapalı. Çalıştır düğmesiyle bağlantıyı yeniden deneyin."
    case .ready: break
    }
    guard lastExecutionSucceeded, let lastExecutedSQL else { return "Önce bu sekmede bir okuma sorgusunu başarıyla çalıştırın." }
    guard transactionCount == 0 else { return "Açık transaction var (\(transactionCount)). Yenilemeden önce COMMIT veya ROLLBACK ile tamamlayın." }
    guard lastExecutedDatabase == database else { return "Veritabanı değişti. Bu veritabanında sorguyu yeniden çalıştırın." }
    guard TSQL.canRepeatRead(lastExecutedSQL) else { return "Bu sorgu güvenli bir salt okunur sorgu olarak tekrarlanamıyor. Çalıştır düğmesini kullanın." }
    return nil
  }
  var canRefresh: Bool { refreshDisabledReason == nil }
  var favoriteID: UUID?
  var file: URL?
  var state = State.disconnected
  var results: [Rows] = []
  var definitionLoading=false
  var definitionError:String?
  var definitionSymbol:CatalogSymbol?
  var definitionTask:Task<Void,Never>?
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
    guard intelligenceCatalog?.fresh != true, Date().timeIntervalSince(lastCatalogCheck) > 30, server.online,server.allowsCatalogIndex(database) else { return }
    lastCatalogCheck = Date()
    Task { [weak self] in await self?.loadSymbols() }
  }
  private var symbolRequest = UUID()
  func clearSymbols() {
    symbols = []; intelligenceCatalog = nil; catalogDatabase = nil; catalogVerified = false; symbolRequest = UUID()
    NotificationCenter.default.post(name:.init("sqlCatalogChanged"),object:self)
  }
  func applyTargetedCatalog(_ catalog:SQLIntelligence.Catalog,database:String,generation:UUID) {
    guard self.database==database,server.generation==generation,server.allowsCatalogIndex(database) else {return}
    symbolRequest=UUID()
    intelligenceCatalog=catalog;catalogDatabase=database;symbols=catalog.snapshot.symbols
    // A scoped change does not verify or extend the age of the whole catalog.
    catalogVerified=catalogVerified && catalog.fresh
    NotificationCenter.default.post(name:.init("sqlCatalogChanged"),object:self)
    changed?()
  }
  var elapsed = 0.0
  var rowCount = 0
  private(set) var resultReadStoppedEarly = false
  var canEditLoadedRows:Bool {canRefresh && !resultReadStoppedEarly && results.count == 1}
  var partial = false
  var initialRefreshSeconds: Int?
  var limits: Limits = ResultReadPreferences.limits(rows:ResultReadPreferences.readLimit)
  var actualPlan = false
  var task: Task<Void, Never>?
  var changed: (() -> Void)?
  var completed: ((String, Execution?, String?) -> Void)?
  var closeOperationBlocked:(()->Bool)?
  var hasResultEdits: (() -> Bool)?
  var confirmDiscardResultEdits: (() -> Bool)?
  private var acceptingEvents = false
  private var executionID = UUID()
  var runAfterConnect = false
  var selectedRange = NSRange(location: 0, length: 0)
  var dirty: Bool { sql != savedText }
  var hasPendingDatabaseChanges: Bool { moduleInitialSQL.map {sql != $0} ?? false }
  var canSubmitModule: Bool {
    server.online && canExecute && transactionCount == 0 &&
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
  func connect(afterConnected: (() -> Void)? = nil) {
    guard !busy else { return }
    guard !server.updatingProfile else { state = .disconnected; changed?(); return }
    state = .connecting
    connectionError = nil
    let generation = server.generation
    changed?()
    var profile = server.profile
    profile.database = database
    let password = server.password
    task = Task { [weak self] in
      guard let self else { return }
      do {
        if let connectionFixture {try await connectionFixture(profile, password)}
        else {try await connection.connect(profile, password: password)}
        guard !Task.isCancelled, server.generation == generation, database == profile.database else {
          await connection.disconnect(); state = .disconnected; task=nil; runAfterConnect=false; connectionError=Task.isCancelled ? "Bağlantı iptal edildi." : "Bağlantı hedefi değişti; tekrar çalıştırın."; changed?(); return
        }
        state = .ready
        messages = "Bağlandı: \(profile.host) / \(database)\n"
        changed?()
        Task { [weak self] in await self?.loadSymbols() }
      } catch {
        state = .disconnected
        connectionError = Task.isCancelled ? "Bağlantı iptal edildi." : error.localizedDescription
        messages = connectionError!
        if let failure=error as? SQLFailure,failure.diagnostics.contains(where:{$0.state.hasPrefix("08")}) {
          let server=self.server
          Task {if server.generation == generation {await server.checkExplorerHealth()}}
        }
        changed?()
      }
      task = nil
      if state == .ready, let afterConnected {afterConnected(); return}
      if state != .ready {runAfterConnect=false}
      if runAfterConnect && state == .ready {
        runAfterConnect = false
        execute()
      }
    }
  }
  func loadSymbols(force: Bool = false) async {
    guard server.allowsCatalogIndex(database) else {clearSymbols();catalogError=nil;return}
    let database = self.database, generation = server.generation, request = UUID(),indexRevision=server.catalogIndexRevision
    symbolRequest = request
    func publish(_ catalog: SQLIntelligence.Catalog, verified: Bool) {
      guard self.database == database, server.generation == generation, symbolRequest == request,server.catalogIndexRevision==indexRevision,server.allowsCatalogIndex(database) else { return }
      intelligenceCatalog = catalog; catalogDatabase = database; catalogVerified = verified; catalogError = nil
      symbols = catalog.snapshot.symbols
      NotificationCenter.default.post(name:.init("sqlCatalogChanged"),object:self)
      changed?()
    }
    do {
      if let cached = try await server.cachedCompletionCatalog(database:database) {
        publish(cached,verified:!force && cached.fresh)
        if !force && cached.fresh {return}
      }
      guard server.online,server.catalogIndexRevision==indexRevision,server.allowsCatalogIndex(database) else {return}
      let catalog = try await server.refreshCompletionCatalog(database:database,force:force)
      publish(catalog,verified:true)
    } catch {
      guard symbolRequest == request,server.generation==generation,server.catalogIndexRevision==indexRevision,server.allowsCatalogIndex(database) else { return }
      catalogVerified = false; catalogError = error.localizedDescription
      NotificationCenter.default.post(name:.init("sqlCatalogChanged"),object:self)
    }
  }
  func useDatabase(_ name: String) {
    if state == .disconnected {database=name;clearSymbols();connectionError=nil;changed?();Task {[weak self] in await self?.loadSymbols()};return}
    guard state == .ready else { return }
    state = .running
    changed?()
    task = Task { [weak self] in
      guard let self else { return }
      do {
        if let databaseChangeFixture {try await databaseChangeFixture(name)}
        else {_ = try await connection.execute("USE \(SQL.identifier(name));")}
        database = name
        clearSymbols()
        messages += "Veritabanı: \(name)\n"
        state = .ready
        task = nil
        changed?()
        Task { [weak self] in await self?.loadSymbols() }
        return
      } catch {
        await recordConnectionFailure(error)
        if state != .disconnected { state = .ready }
        messages += error.localizedDescription + "\n"
        task = nil
        changed?()
      }
    }
  }
  func execute(override: String? = nil, estimated: Bool = false, repeatRead: Bool = false) {
    guard canExecute, confirmDiscardResultEdits?() != false else { return }
    let source = sql as NSString
    let query =
      override
      ?? (selectedRange.length > 0 && NSMaxRange(selectedRange) <= source.length
        ? source.substring(with: selectedRange) : sql)
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    if state == .disconnected {
      connect { [weak self] in self?.execute(override:query,estimated:estimated,repeatRead:repeatRead) }
      return
    }
    let executionServer=server,executionServerGeneration=server.generation,executionDatabase=database
    var executionLimits=limits
    executionLimits.readOnlyRowLimit=true
    let appliesRowLimit=TSQL.usesResultRowLimit(query)
    if !appliesRowLimit {executionLimits.rows=Int.max}
    repeating = repeatRead
    resultGeneration += 1
    lastExecutionSucceeded = false
    lastExecutedSQL = estimated ? nil : query
    lastExecutedDatabase = database
    lastExecutedReadLimit = appliesRowLimit ? executionLimits.rows:nil
    lastExecutionDate=Date()
    state = .running
    results = []
    messages = "Çalıştırma: \(Date().formatted(date: .numeric, time: .standard)) · \(database)\n"
    partial = false
    resultReadStoppedEarly=false
    elapsed = 0
    rowCount = 0
    selectedResult = 0
    changed?()
    acceptingEvents = true
    executionID = UUID()
    let token = executionID
    let start = Date()
    let captureActual = actualPlan && !estimated
    let executionFixture = self.executionFixture
    let sessionProbeFixture = self.sessionProbeFixture
    task = Task { [weak self] in
      guard let self else { return }
      var ddlSessionVerified = executionFixture != nil && sessionProbeFixture == nil
      defer {
        task = nil
        if state != .disconnected {state = .ready}
        if applyingModule && lastExecutionSucceeded && !partial && transactionCount == 0 { moduleApplied?() }
        if !estimated,server === executionServer,server.generation==executionServerGeneration {
          if pendingDDLGeneration != executionServerGeneration {
            pendingDDLChanges=[];pendingDDLGeneration=executionServerGeneration
          }
          if lastExecutionSucceeded {
            for change in ModuleEditing.changes(query).map({$0.inDatabase(executionDatabase)}) where !pendingDDLChanges.contains(change) && pendingDDLChanges.count<128 {pendingDDLChanges.append(change)}
          }
          // Read live metadata after COMMIT or ROLLBACK; an open transaction must
          // never publish uncommitted DDL through a different metadata session.
          if ddlSessionVerified,transactionCount == 0,!pendingDDLChanges.isEmpty,state != .disconnected {
            NotificationCenter.default.post(name:.init("studioDDLCompleted"),object:self,userInfo:["changes":pendingDDLChanges,"database":executionDatabase,"generation":executionServerGeneration])
            pendingDDLChanges=[]
          }
        }
        if !estimated && lastExecutionSucceeded && !partial && transactionCount == 0 {managedObjectApplied?()}
        applyingModule = false
        changed?()
      }
      do {
        if estimated && executionFixture == nil {
          guard
            !TSQL.lex(query).contains(where: {
              $0.kind != .comment && $0.text.uppercased() == "SHOWPLAN_XML"
            })
          else { throw SQLFailure("Tahmini plana SHOWPLAN_XML komutu eklenemez.") }
          _ = try await connection.execute("SET SHOWPLAN_XML ON;")
        } else if captureActual && executionFixture == nil {
          _ = try await connection.execute("SET STATISTICS XML ON;")
        }
        let output: Execution
        if let executionFixture {
          output = try await executionFixture(query, executionLimits)
        } else {
          output = try await TSQL.run(
            query, on: connection, limits: executionLimits,
            events: { [weak self] event in
              Task { @MainActor [weak self] in
                guard let self, self.executionID == token,
                  self.state == .running || self.state == .cancelling
                else { return }
                self.receive(event)
              }
            })
        }
        acceptingEvents = false
        results = output.results
        messages += output.messages.joined(separator: "\n") + "\n"
        partial = output.partial
        resultReadStoppedEarly=output.stoppedEarly
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
      if state != .disconnected && (executionFixture == nil || sessionProbeFixture != nil) {
        if estimated && executionFixture == nil { _ = try? await connection.execute("SET SHOWPLAN_XML OFF;") }
        if captureActual && executionFixture == nil { _ = try? await connection.execute("SET STATISTICS XML OFF;") }
        do {
          var limits=Limits();limits.rows=1;limits.timeout=5
          let result:Execution
          if let sessionProbeFixture {result=try await sessionProbeFixture("SELECT @@TRANCOUNT, DB_NAME();",limits)}
          else {result=try await connection.execute("SELECT @@TRANCOUNT, DB_NAME();",limits:limits)}
          // This response belongs to the session that just executed the SQL.
          // A late reply must not authorize refresh or overwrite another target.
          guard executionID==token,server === executionServer,server.generation==executionServerGeneration,self.database==executionDatabase else {
            if executionID==token {lastExecutedDatabase=nil}
            return
          }
          if let row = result.results.first?.values.first, row.count > 1 {
            ddlSessionVerified = !result.partial && row[0].flatMap(Int.init).map {$0>=0} == true && row[1].map {!$0.isEmpty} == true
            transactionCount = row[0].flatMap(Int.init) ?? 0
            if let database = row[1] {
              // DB_NAME is the actual SQL session identity, not a case-insensitive
              // guess from profile text. Read-only SQL cannot change that identity.
              if lastExecutionSucceeded,!estimated,lastExecutedSQL==query,lastExecutedDatabase==executionDatabase,TSQL.canRepeatRead(query) {
                lastExecutedDatabase=database
              }
              if self.database != database {
                self.database = database
                clearSymbols()
                Task { [weak self] in await self?.loadSymbols() }
              }
            }
          }
        } catch {
          if executionID==token,server === executionServer,server.generation==executionServerGeneration,self.database==executionDatabase {await recordConnectionFailure(error)}
          else if executionID==token {lastExecutedDatabase=nil}
        }
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
    guard state == .running || state == .connecting else { return }
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
