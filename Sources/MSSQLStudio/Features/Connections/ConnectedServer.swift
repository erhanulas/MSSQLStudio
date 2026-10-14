import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class ConnectedServer: Identifiable {
  let id: UUID
  var profile: ServerProfile
  var password: String
  var metadata = ODBCConnection()
  var generation = UUID()
  var databases: [CatalogItem] = []
  var remembered = false
  lazy var hoverMetadata=SQLHoverMetadata(server:self)
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
  var updatingProfile=false
  var reconnecting = false
  func pauseIndexing() { indexPreparation?.cancel(); definitionIndex.pause() }
  func recordExplorerFailure(_ error: Error) {
    startupError = error.localizedDescription
    if let failure = error as? SQLFailure,
      failure.diagnostics.contains(where: { $0.state.hasPrefix("08") }) {
      online = false
      pauseIndexing()
    }
  }
  func recordCatalogFailure(_ error:Error,generation token:UUID) async {
    guard generation == token else {return}
    startupError=error.localizedDescription
    guard let failure=error as? SQLFailure,
      failure.diagnostics.contains(where:{$0.state.hasPrefix("08")}) else {return}
    // Catalog work opens its own short-lived connection. Its transport failure
    // does not prove that the persistent Explorer session has disconnected.
    await checkExplorerHealth()
  }
  var startupError: String?
  var schemaComparisonFixture: ((String,String) throws -> Execution)?
  var catalogFixture: ((String) -> Execution)?
  var asyncCatalogFixture: ((String) async throws -> Execution)?
  var indexingDatabases = Set<String>()
  var indexErrors: [String:String] = [:]
  private var indexPreparation: Task<Void, Never>?
  private var indexPreparationID=UUID()
  private(set) var catalogIndexRevision=UUID()
  private var visibilityApplication:(revision:UUID,task:Task<Void,Never>)?
  lazy var definitionIndex=ObjectDefinitionIndexController(server:self,disk:diskIndex)
  private let diskIndex:CatalogDiskIndex
  private let objectIndexService:CatalogIndexService
  private let completionIndexService:SQLCatalogService
  func allowsDefinitionIndex(_ database: String) -> Bool { allowsCatalogIndex(database) && profile.indexesDefinitions(in: database) }
  func allowsCatalogIndex(_ database:String) -> Bool {profile.visibleDatabases?.contains(database) != false}
  func catalogIndexStatus(database: String) async throws -> CatalogIndexStatus? {
    try await diskIndex.status(scope: CatalogDiskIndex.scope(profile: profile, database: database))
  }
  func completionIndexDate(database:String) async throws -> Date? {
    if let application=visibilityApplication {await application.task.value}
    guard allowsCatalogIndex(database) else {return nil}
    return try await diskIndex.completionDate(scope:CatalogDiskIndex.scope(profile:profile,database:database))
  }
  func catalogScopeUsage(database:String) async throws -> CatalogScopeUsage {
    if let application=visibilityApplication {await application.task.value}
    return try await diskIndex.scopeUsage(scope:CatalogDiskIndex.scope(profile:profile,database:database))
  }
  func cachedCompletionCatalog(database:String) async throws -> SQLIntelligence.Catalog? {
    if let application=visibilityApplication {await application.task.value}
    return try await completionIndexService.cached(profile:profile,database:database)
  }
  func refreshCompletionCatalog(database:String,force:Bool) async throws -> SQLIntelligence.Catalog {
    if let application=visibilityApplication {await application.task.value}
    return try await completionIndexService.refresh(profile:profile,password:password,database:database,force:force)
  }
  /// Called with the full accessible list, before starting any background work.
  /// This also cleans old hidden scopes after restoring a persisted profile.
  func synchronizeCatalogVisibility(available:[CatalogItem],previousProfile:ServerProfile?=nil,previousDatabases:[CatalogItem]=[]) async {
    indexPreparation?.cancel();indexPreparationID=UUID();catalogIndexRevision=UUID()
    let profile=profile,revision=catalogIndexRevision
    let purgeDefinitions=previousProfile.map { !$0.hasSameConnectionSettings(as:profile) } ?? false
    let known=Set(available.map(\.name)).union(previousDatabases.map(\.name)).union(previousProfile?.visibleDatabases ?? []).union(profile.definitionIndexDatabases?.keys.map { $0 } ?? []).union(previousProfile?.definitionIndexDatabases?.keys.map { $0 } ?? [])
    let previous=visibilityApplication?.task
    // MainActor isolation does not order calls across service/index actor hops.
    // Finish every prior eviction before allowing the next snapshot to reinclude
    // a scope, even when the caller has already changed the visible profile.
    let application=Task { [weak self] in
      if let previous {await previous.value}
      guard let self else {return}
      await applyCatalogVisibility(profile:profile,known:known,revision:revision,purgeDefinitions:purgeDefinitions)
    }
    visibilityApplication=(revision,application)
    await application.value
    if visibilityApplication?.revision==revision {visibilityApplication=nil}
  }
  private func applyCatalogVisibility(profile:ServerProfile,known:Set<String>,revision:UUID,purgeDefinitions:Bool) async {
    await definitionIndex.configure(purge:purgeDefinitions,enabled:profile.hasDefinitionIndexes,
      disabledScopes: known.filter { !profile.indexesDefinitions(in: $0) }.map { CatalogDiskIndex.scope(profile: profile, database: $0) })
    let excluded=known.filter {profile.visibleDatabases?.contains($0) == false}
    for database in excluded.sorted() {
      if catalogIndexRevision==revision {indexingDatabases.remove(database);indexErrors[database]=nil}
      var failure:String?
      do {try await objectIndexService.exclude(profile:profile,database:database)}
      catch {failure=error.localizedDescription}
      // A failed disk deletion must not leave the other service's jobs or
      // completion memory alive. Both evictions finish before the successor.
      do {try await completionIndexService.exclude(profile:profile,database:database)}
      catch {failure=error.localizedDescription}
      if catalogIndexRevision==revision {
        indexErrors[database]=failure
        NotificationCenter.default.post(name:.init("catalogIndexUpdated"),object:self,userInfo:["database":database,"excluded":true])
      }
    }
    for database in known where profile.visibleDatabases?.contains(database) != false {
      do {try await diskIndex.setExcluded(false,scope:CatalogDiskIndex.scope(profile:profile,database:database))}
      catch {if catalogIndexRevision==revision {indexErrors[database]=error.localizedDescription}}
    }
  }
  func removeCatalogIndexes() async {
    pauseIndexing();catalogIndexRevision=UUID();indexPreparationID=UUID()
    if let visibilityApplication {await visibilityApplication.task.value}
    do {try await diskIndex.removeOwnedCatalogs(id)}
    catch {startupError="Yerel indeksler silinemedi: "+error.localizedDescription}
    await definitionIndex.remove()
    let names=Set(databases.map(\.name)).union(profile.visibleDatabases ?? [profile.database])
    for database in names {
      do {
        try await objectIndexService.exclude(profile:profile,database:database)
      } catch {startupError="Yerel indeksler silinemedi: "+error.localizedDescription}
      do {try await completionIndexService.exclude(profile:profile,database:database)}
      catch {startupError="Yerel indeksler silinemedi: "+error.localizedDescription}
    }
  }
  func prepareCatalogIndexes(force: Bool = false) {
    guard visibilityApplication == nil else {return}
    indexPreparation?.cancel()
    let preparationID=UUID();indexPreparationID=preparationID
    let profile = profile, password = password, databases = databases.map(\.name)
    definitionIndex.refresh(force:force)
    indexPreparation = Task { [weak self] in
      for database in databases {
        guard !Task.isCancelled, let self, self.online,self.indexPreparationID==preparationID else { return }
        guard self.allowsCatalogIndex(database) else {continue}
        indexingDatabases.insert(database); indexErrors[database] = nil
        NotificationCenter.default.post(name:.init("catalogIndexUpdated"),object:self,userInfo:["database":database])
        do {
          _ = try await objectIndexService.refresh(profile: profile, password: password, database: database, force: force)
          guard !Task.isCancelled,indexPreparationID==preparationID,allowsCatalogIndex(database) else {return}
          _ = try await completionIndexService.refresh(profile:profile,password:password,database:database,force:force)
          guard !Task.isCancelled,indexPreparationID==preparationID,allowsCatalogIndex(database) else {return}
          indexingDatabases.remove(database)
          NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: self, userInfo: ["database": database])
        } catch {
          guard !Task.isCancelled,indexPreparationID==preparationID,allowsCatalogIndex(database) else {return}
          indexingDatabases.remove(database); indexErrors[database] = error.localizedDescription
          NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: self, userInfo: ["database": database, "error": error.localizedDescription])
        }
      }
    }
  }
  init(profile: ServerProfile, password: String,diskIndex:CatalogDiskIndex = .shared,objectIndexService:CatalogIndexService = .shared,completionIndexService:SQLCatalogService = .shared) {
    self.id = profile.id
    self.profile = profile
    self.password = password
    self.diskIndex=diskIndex;self.objectIndexService=objectIndexService;self.completionIndexService=completionIndexService
  }
  func catalog(_ sql: String, database: String, limits: Limits = Limits()) async throws -> Execution {
    if let asyncCatalogFixture {
      let token=generation
      do {return try await asyncCatalogFixture(sql)}
      catch {await recordCatalogFailure(error,generation:token);throw error}
    }
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
      await recordCatalogFailure(error,generation:token)
      throw error
    }
  }
}
