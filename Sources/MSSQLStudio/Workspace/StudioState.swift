import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

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
  var explorerOrganization:ExplorerOrganization {(try? ExplorerOrganization.load(explorerTreeDefaults.data(forKey:"explorerOrganization"))) ?? ExplorerOrganization()}
  func changeExplorerOrganization(_ change:(inout ExplorerOrganization)throws->Void)throws {
    var value=try ExplorerOrganization.load(explorerTreeDefaults.data(forKey:"explorerOrganization"))
    try change(&value)
    explorerTreeDefaults.set(try JSONEncoder().encode(value),forKey:"explorerOrganization")
    changed?()
  }
  var profilePersistenceFixture:((ServerProfile,String) async throws->Void)?
  func saveConnectionProfile(_ server:ConnectedServer,profile input:ServerProfile,password:String,remember:Bool) async throws {
    guard servers.contains(where:{$0 === server}),input.id==server.id,!server.reconnecting,!server.updatingProfile else {throw SQLFailure("Bağlantı güncellenemiyor.")}
    var profile=input;profile.name=profile.name.trimmingCharacters(in:.whitespacesAndNewlines)
    guard !profile.name.isEmpty,profile.name.count<=120,!profile.name.contains("\0") else {throw SQLFailure("Bağlantı adını kontrol edin.")}
    if let appearance=profile.appearance {profile.appearance=try appearance.validated()}
    _ = try profile.connectionString(password:password)
    let reset = !server.profile.hasSameConnectionSettings(as:profile) || server.password != password
    let affected=documents.filter {$0.server === server}
    guard !reset || affected.allSatisfy({!$0.busy && $0.transactionCount==0 && $0.closeOperationBlocked?() != true}) else {throw SQLFailure("Bağlantı bilgilerini değiştirmeden önce çalışan sorguları ve açık transaction’ları tamamlayın.")}
    if reset,affected.contains(where:{$0.confirmDiscardResultEdits?() == false}) {throw CancellationError()}
    let previous=affected.map(\.state)
    server.updatingProfile=true
    if reset {for doc in affected {doc.state = .connecting;doc.changed?()}}
    defer {server.updatingProfile=false;changed?()}
    do {
      if remember || server.remembered {
        if let fixture=profilePersistenceFixture {try await fixture(profile,password)}
        else {let savedProfile=profile;try await Task.detached {try ServerVault().save(savedProfile,password:savedProfile.kerberos ? "":password)}.value}
      }
    } catch {
      if reset {for (doc,state) in zip(affected,previous) {doc.state=state;doc.changed?()}}
      throw error
    }
    if reset {
      server.online=false;server.pauseIndexing();server.generation=UUID()
      let metadata=server.metadata;server.metadata=ODBCConnection()
      for doc in affected {await doc.connection.disconnect();doc.state = .disconnected;doc.results=[];doc.rowCount=0;doc.clearSymbols();doc.changed?()}
      await metadata.disconnect()
    }
    let oldProfile=server.profile
    server.profile=profile;server.password=password;server.remembered = server.remembered || remember
    if server.remembered {rememberExplorer(server.id,selected:true)}
    if reset || oldProfile.visibleDatabases != profile.visibleDatabases {
      await server.synchronizeCatalogVisibility(available:server.databases,previousProfile:oldProfile)
      if server.online {server.prepareCatalogIndexes()}
    } else if oldProfile.indexObjectDefinitions != profile.indexObjectDefinitions || oldProfile.definitionIndexDatabases != profile.definitionIndexDatabases {
      await server.definitionIndex.configure()
      server.definitionIndex.refresh()
    }
    scheduleSnapshot()
  }
  func setDefinitionIndex(_ server: ConnectedServer, database: String, enabled: Bool) async throws {
    guard server.databases.contains(where: { $0.name == database }), server.allowsCatalogIndex(database) else {
      throw SQLFailure("Veritabanı Explorer kapsamında değil.")
    }
    var profile = server.profile
    profile.setDefinitionIndex(enabled, database: database, known: server.databases.map(\.name))
    try await saveConnectionProfile(server, profile: profile, password: server.password, remember: false)
    NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: server,
      userInfo: ["database": database, "definitionsOnly": true])
  }
  func deleteConnectionProfile(_ server:ConnectedServer) async throws {
    guard !server.reconnecting,!server.updatingProfile else {throw SQLFailure("Bağlantı işlemi sürüyor.")}
    if server.remembered {let id=server.id;try await Task.detached {try ServerVault().delete(id)}.value}
    try changeExplorerOrganization {try $0.assign(server.id,to:nil)}
    await removeExplorer(server)
  }
  var servers: [ConnectedServer] = []
  var documents: [QueryDocument] = []
  var active: QueryDocument?
  var editorCatalogTasks:[UUID:Task<Void,Never>]=[:]
  var editorCatalogRequests:[UUID:UUID]=[:]
  var changed: (() -> Void)?
  var history: [QueryRecord] = []
  var closedTabs: [QueryRecord] = []
  var closedTabLimit=QueryHistoryPolicy.closedTabLimit(UserDefaults.standard.object(forKey:"closedTabLimit") as? Int ?? QueryHistoryPolicy.defaultClosedTabLimit)
  let historyStore=QueryHistoryStore()
  var historySaveTask:Task<Bool,Never>?
  var historyWriteRevision=UUID()
  var historyWriteError:String?
  var historyLoadFailed=false
  lazy var favorites = FavoriteQueriesModel(url: (Bundle.main.bundleIdentifier == "local.mssqlstudio.uitest" || ProcessInfo.processInfo.arguments.contains("--ui-smoke") || ProcessInfo.processInfo.arguments.contains(where:{$0.contains(".xctest")})
    ? URL(fileURLWithPath:"/tmp/MSSQLStudio-UI-\(ProcessInfo.processInfo.processIdentifier)") : folder).appendingPathComponent("favorites.json"))
  private var nextQueryNumber = 1
  var warnOnTabClose=UserDefaults.standard.object(forKey:"warnOnTabClose") as? Bool ?? true
  var warnOnObjectClose=UserDefaults.standard.object(forKey:"warnOnObjectClose") as? Bool ?? true
  func requiresCloseConfirmation(_ doc:QueryDocument)->Bool {
    if doc.hasPendingDatabaseChanges {return warnOnObjectClose}
    return warnOnTabClose && doc.dirty
  }
  var historyEnabled = UserDefaults.standard.bool(forKey: "historyEnabled")
  var historyRetentionDays = QueryHistoryPolicy.days(UserDefaults.standard.object(forKey: "historyRetentionDays") as? Int ?? QueryHistoryPolicy.defaultDays)
  private var snapshotTask: Task<Void, Never>?
  var recoveryEnabled = UserDefaults.standard.bool(forKey: "recoveryEnabled")
  let folder:URL = {
    if Bundle.main.bundleIdentifier == "local.mssqlstudio.uitest" || ProcessInfo.processInfo.arguments.contains("--ui-smoke") || ProcessInfo.processInfo.arguments.contains(where:{$0.contains(".xctest")}) {
      return URL(fileURLWithPath:"/tmp/MSSQLStudio-UI-\(ProcessInfo.processInfo.processIdentifier)")
    }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MSSQLStudio")
  }()
  private static var discoveryLimits: Limits {
    var value=Limits();value.rows=50_001;value.totalBytes=16*1024*1024;value.timeout=10;return value
  }
  private static func discoverDatabases(using connection:ODBCConnection) async throws -> [CatalogItem] {
    let result=try await connection.execute(Catalog.databases,limits:discoveryLimits)
    guard !result.partial,!result.stoppedEarly,!result.results.contains(where:{$0.truncated}) else {throw SQLFailure("Veritabanı listesi tam okunamadı; mevcut Explorer kapsamı korundu.")}
    return Catalog.rows(result)
  }
  private(set) var connectionErrors:[UUID:String]=[:]
  private(set) var connectionActivities:[UUID:String]=[:]
  func connect(_ profile: ServerProfile, password: String, save: Bool) async throws
    -> ConnectedServer
  {
    guard connectionActivities[profile.id] == nil else {throw SQLFailure("Bu bağlantı için işlem sürüyor.")}
    connectionActivities[profile.id]="Explorer bağlanıyor: " + profile.name
    changed?()
    defer {connectionActivities[profile.id]=nil;changed?()}
    connectionErrors[profile.id]=nil
    do {return try await performConnect(profile,password:password,save:save)}
    catch is CancellationError {throw CancellationError()}
    catch {connectionErrors[profile.id]=error.localizedDescription;throw error}
  }
  private func performConnect(_ profile:ServerProfile,password:String,save:Bool) async throws -> ConnectedServer {
    if let old = servers.first(where: { $0.id == profile.id }) ?? documents.first(where:{$0.server.id==profile.id})?.server {
      guard !old.updatingProfile else {throw SQLFailure("Bağlantı bilgileri kaydediliyor.")}
      let previousProfile=old.profile,previousDatabases=old.databases
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
        let items = try await Self.discoverDatabases(using:candidate)
        if reconnect { try checkSessions() }
        if save || (old.remembered && (old.profile != profile || old.password != password)) {
          try await Task.detached {try ServerVault().save(profile,password:profile.kerberos ? "":password)}.value
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
            doc.changed?()
          }
        } else {
          let previous = old.metadata
          old.metadata = candidate
          old.profile = profile
          old.password = password
          await previous.disconnect()
        }
        old.databases = profile.visibleItems(from: items)
        await old.synchronizeCatalogVisibility(available:items,previousProfile:previousProfile,previousDatabases:previousDatabases)
        old.online = true; old.startupError = nil
        if !servers.contains(where:{$0 === old}) {servers.append(old)}
        synchronizeEditorCatalogs(old)
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
      let available=try await Self.discoverDatabases(using:server.metadata)
      server.databases = profile.visibleItems(from:available)
      await server.synchronizeCatalogVisibility(available:available)
      if save {try await Task.detached {try ServerVault().save(profile,password:profile.kerberos ? "":password)}.value}
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
    guard !server.reconnecting,!server.updatingProfile else { return }
    server.online = false
    connectionErrors[server.id]=nil
    server.startupError = nil
    server.pauseIndexing()
    let previous = server.metadata
    server.metadata = ODBCConnection()
    changed?()
    await previous.disconnect()
  }
  func removeExplorer(_ server: ConnectedServer) async {
    guard !server.reconnecting,!server.updatingProfile else { return }
    servers.removeAll { $0 === server }
    rememberExplorer(server.id, selected:false)
    await disconnectExplorer(server)
    await server.removeCatalogIndexes()
    if let error=server.startupError {showError(error)}
    changed?()
  }
  func reconnectExplorer(_ server: ConnectedServer) async {
    guard !server.reconnecting,!server.updatingProfile else { return }
    server.reconnecting = true
    server.startupError = nil
    changed?()
    defer { server.reconnecting = false; changed?() }
    do {
      if let reconnectFixture=server.reconnectFixture {
        try await reconnectFixture(); server.online=true; synchronizeEditorCatalogs(server); return
      }
      if !servers.contains(where:{$0 === server}) {servers.append(server)}
      _ = try await connect(server.profile, password: server.password, save: false)
    } catch is CancellationError {} catch {
      server.startupError = error.localizedDescription
    }
  }
  func rememberExplorer(_ id: UUID, selected: Bool) {
    var ids = explorerOrderDefaults.stringArray(forKey: "explorerActiveServerIDs") ?? servers.filter(\.remembered).map { $0.id.uuidString }
    ids.removeAll { $0 == id.uuidString }
    if selected { ids.append(id.uuidString) }
    explorerOrderDefaults.set(ids, forKey: "explorerActiveServerIDs")
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
      // Restore local documents before any server login or catalog discovery.
      if recoveryEnabled {
        let recoveryFolder = folder
        do {
          let tabs = try await Task.detached { try Self.readSavedTabs(in: recoveryFolder) }.value
          recover(for: servers, tabs: tabs)
        } catch { showError(error.localizedDescription) }
      }
      changed?()
      for server in servers where !server.online {
        connectionActivities[server.id]="Explorer bağlanıyor: " + server.profile.name;changed?()
        defer {connectionActivities[server.id]=nil;changed?()}
        let activeBefore=active
        do {
          try await server.metadata.connect(server.profile,password:server.password)
          let available=try await Self.discoverDatabases(using:server.metadata)
          server.databases = server.profile.visibleItems(from:available)
          await server.synchronizeCatalogVisibility(available:available)
          server.online = true; server.startupError = nil; server.generation = UUID()
          synchronizeEditorCatalogs(server)
          server.prepareCatalogIndexes()
          changed?()
          completeExplorerConnection(server,previousActive:activeBefore)
        } catch is CancellationError {await server.metadata.disconnect();server.online=false;changed?()}
        catch { server.startupError = error.localizedDescription; await server.metadata.disconnect(); changed?() }
      }
      return !chosen.isEmpty
    } catch { showError("Kayıtlı Explorer bağlantıları okunamadı: " + error.localizedDescription); return true }
  }
  func completeExplorerConnection(_ server:ConnectedServer,previousActive:QueryDocument?) {
    guard active === previousActive,!documents.contains(where:{$0.server.id == server.id}) else {return}
    recover(for:server)
    guard active === previousActive,!documents.contains(where:{$0.server.id == server.id}) else {return}
    newQuery(server:server,database:server.profile.database,text:"-- MSSQL Studio\nSELECT DB_NAME() AS [Database], @@SPID AS [Session], SYSDATETIME() AS [Server time];")
  }
  @discardableResult func newQuery(
    server: ConnectedServer, database: String? = nil, text: String = "", title: String? = nil,
    run: Bool = false, refreshSeconds: Int? = nil, startConnection:Bool = false, selection:NSRange? = nil, notifyChanges:Bool = true
  ) -> QueryDocument {
    let doc = QueryDocument(
      server: server, database: database ?? server.profile.database,
      title: title ?? "SQLQuery\(nextQueryNumber).sql")
    doc.connected = { [weak self, weak server] in
      guard let self,let server,self.servers.contains(where:{$0 === server}),!server.reconnecting,self.connectionActivities[server.id]==nil else {return}
      Task { [weak self,weak server] in
        guard let self,let server else {return}
        if server.online {await server.checkExplorerHealth()}
        guard self.servers.contains(where:{$0 === server}),!server.updatingProfile else {return}
        if !server.online {await self.reconnectExplorer(server)}
        else {self.synchronizeEditorCatalogs(server)}
      }
    }
    nextQueryNumber += 1
    doc.sql = text
    doc.savedText = text // Generated/opened text is the baseline, not a user edit.
    if let selection {
      let length=(text as NSString).length,start=min(max(0,selection.location),length)
      doc.selectedRange=NSRange(location:start,length:min(max(0,selection.length),length-start))
    }
    doc.completed = { [weak self, weak doc] sql, result, error in
      guard let self, let doc, self.historyEnabled else { return }
      self.history.insert(
        QueryRecord(
          server: doc.server.profile.name, database: doc.lastExecutedDatabase ?? doc.database, text: sql,
          serverID: doc.server.id, errorMessage: error, rowCount: result?.results.reduce(0) { $0 + $1.values.count },
          seconds: result?.elapsed ?? 0,
          status: error == nil ? (result?.partial == true ? "Kısmi" : "Başarılı") : "Hata"), at: 0)
      self.saveHistory()
    }
    documents.append(doc)
    active = doc
    doc.runAfterConnect = run
    doc.initialRefreshSeconds = refreshSeconds
    if notifyChanges { changed?() }
    if run {doc.runAfterConnect=false;doc.execute()} else if startConnection {doc.connect()}
    else {Task {[weak doc] in await doc?.loadSymbols()}}

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
  struct SavedTab: Codable, Sendable {
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
  nonisolated static func readSavedTabs(in folder: URL) throws -> [SavedTab] {
    let url = folder.appendingPathComponent("tabs.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let data = try Data(contentsOf: url)
    guard data.count < 20_000_000 else {
      throw SQLFailure("Kurtarma dosyası 20 MB okuma sınırını aşıyor; mevcut dosya korunuyor.")
    }
    return try JSONDecoder().decode([SavedTab].self, from: data)
  }
  func recover(for server: ConnectedServer) {
    guard recoveryEnabled else { return }
    do { recover(for: [server], tabs: try Self.readSavedTabs(in: folder)) }
    catch { showError(error.localizedDescription) }
  }
  func recover(for servers: [ConnectedServer], tabs: [SavedTab]) {
    guard recoveryEnabled else { return }
    let previousActive = active
    var restored = false
    for server in servers where !documents.contains(where: { $0.server.id == server.id }) {
      for tab in tabs.filter({ $0.serverID == server.id || $0.endpoint == endpoint(server.profile) }).prefix(30) {
        let doc = newQuery(server: server, database: tab.database, text: tab.sql, title: tab.title, notifyChanges: false)
        doc.pinned = tab.pinned ?? false
        doc.savedText = tab.saved
        doc.file = tab.path.map { URL(fileURLWithPath: $0) }
        if let key=tab.objectKey {doc.objectEditorKey=ObjectEditorKey(serverID:server.id,database:key.database,objectID:key.objectID);doc.moduleObjectID=key.objectID}
        doc.moduleOriginal=tab.moduleOriginal;doc.moduleInitialSQL=tab.moduleInitialSQL
        restored = true
      }
    }
    guard restored else { return }
    documents=documents.filter(\.pinned)+documents.filter {!$0.pinned}
    if let previousActive { active = previousActive }
    changed?()
  }
  func historyServer(_ record: QueryRecord) -> ConnectedServer? {
    if let id = record.serverID { return servers.first { $0.id == id } }
    let matching = servers.filter { $0.profile.name == record.server }
    return matching.count == 1 ? matching.first : nil
  }
  func loadHistory() {
    guard historySaveTask == nil,historyWriteError == nil else {return}
    do {
      let data = try Data(contentsOf: folder.appendingPathComponent("history.json"))
      guard data.count<20_000_000 else {throw SQLFailure("Sorgu geçmişi 20 MB okuma sınırını aşıyor; mevcut dosya korunuyor.")}
      history = QueryHistoryPolicy.retained(try JSONDecoder().decode([QueryRecord].self, from: data), days: historyRetentionDays,closedTabLimit:closedTabLimit)
      saveHistory()
    } catch {
      if FileManager.default.fileExists(atPath: folder.appendingPathComponent("history.json").path)
      {
        historyLoadFailed=true;historyWriteError=error.localizedDescription
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
  private var noticeWindows:[NSWindowController]=[]
  var errorFixture:((String)->Void)?
  func showError(_ message:String) {
    if let errorFixture {errorFixture(message);return}
    let owner=StudioNoticeWindowController(message:message)
    noticeWindows.append(owner)
    owner.closed={ [weak self,weak owner] in Task { @MainActor [weak self,weak owner] in self?.noticeWindows.removeAll {$0 === owner} } }
    owner.showWindow(nil);owner.window?.makeKeyAndOrderFront(nil)
  }
  func close(_ doc: QueryDocument,discardChanges:Bool=false) -> Bool {
    guard !doc.busy,doc.closeOperationBlocked?() != true else {
      showError("Önce çalışan sorguyu durdurun.")
      return false
    }
    guard doc.transactionCount == 0 else {
      showError("Önce COMMIT veya ROLLBACK çalıştırın.")
      return false
    }
    guard discardChanges || confirmSave(doc) else { return false }
    rememberClosedTab(doc)
    doc.definitionTask?.cancel();doc.definitionTask=nil
    doc.disconnect()
    documents.removeAll { $0.id == doc.id }
    if active === doc { active = documents.last }
    changed?()
    scheduleSnapshot()
    return true
  }
  func confirmSave(_ doc: QueryDocument) -> Bool {
    guard doc.confirmDiscardResultEdits?() != false else { return false }
    guard requiresCloseConfirmation(doc) else { return true }
    let alert = StudioAlert()
    alert.framePersistenceRole="queryCloseConfirmation"
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
        let alert = StudioAlert()
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
  enum BulkCloseChoice {case save,discard,cancel}
  var bulkCloseChoiceFixture:(()->BulkCloseChoice)?
  var closeErrorFixture:((String)->Void)?
  /// nil cancels, true authorizes a single discard pass (no per-tab dialogs).
  func confirmBulkClose()->Bool? {
    guard documents.allSatisfy({!$0.busy && $0.transactionCount==0 && $0.closeOperationBlocked?() != true}) else {
      if let fixture=closeErrorFixture {fixture("Çalışan sorguları ve açık transaction’ları tamamlayın.")}
      else {showError("Çalışan sorguları ve açık transaction’ları tamamlayın.")}
      return nil
    }
    guard documents.contains(where:{requiresCloseConfirmation($0) || $0.hasResultEdits?() == true}) else {return true}
    let choice:BulkCloseChoice
    if let fixture=bulkCloseChoiceFixture {choice=fixture()}
    else {
      let alert=StudioAlert();alert.framePersistenceRole="bulkCloseConfirmation";alert.messageText="Açık sorgulardaki değişiklikler kaydedilsin mi?"
      alert.informativeText="SQL dosyaları kaydedilebilir. Sonuç düzenlemeleri ve uygulanmamış DDL, dosya kaydıyla veritabanına gönderilmez."
      alert.addButton(withTitle:"Tümünü Kaydet");alert.addButton(withTitle:"Tümünü Kaydetmeden Kapat");alert.addButton(withTitle:"Vazgeç")
      alert.buttons[2].keyEquivalent="\u{1b}"
      switch alert.runModal() {case .alertFirstButtonReturn:choice = .save;case .alertSecondButtonReturn:choice = .discard;default:choice = .cancel}
    }
    return approveBulkClose(choice) ? true:nil
  }
  var needsBulkCloseConfirmation:Bool {documents.contains {requiresCloseConfirmation($0) || $0.hasResultEdits?() == true}}
  func canBeginBulkClose()->Bool {
    guard documents.allSatisfy({!$0.busy && $0.transactionCount==0 && $0.closeOperationBlocked?() != true}) else {
      if let fixture=closeErrorFixture {fixture("Çalışan sorguları ve açık transaction’ları tamamlayın.")}
      else {showError("Çalışan sorguları ve açık transaction’ları tamamlayın.")}
      return false
    }
    return true
  }
  func approveBulkClose(_ choice:BulkCloseChoice)->Bool {
    guard canBeginBulkClose() else {return false}
    switch choice {
    case .cancel:return false
    case .discard:return true
    case .save:
      for doc in documents {
        guard doc.confirmDiscardResultEdits?() != false else {return false}
        if doc.needsCloseConfirmation,!save(doc) {return false}
      }
      return true
    }
  }
  func canQuit(choice:BulkCloseChoice?=nil,preservingWorkspace:Bool=false) -> Bool {
    guard choice.map({approveBulkClose($0)}) ?? (confirmBulkClose() != nil) else {return false}
    // A discard decision must not resurrect earlier recovery drafts next launch.
    if !preservingWorkspace, documents.contains(where:{$0.needsCloseConfirmation || $0.hasResultEdits?() == true}) {
      for doc in documents {doc.disconnect()}
      documents=[];active=nil;changed?()
    }
    return !recoveryEnabled || saveSnapshot()
  }
}
