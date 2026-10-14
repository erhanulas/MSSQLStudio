import Foundation
import Security

public struct SavedServer: Codable, Sendable {
  public var profile: ServerProfile
  public var password: String
}
public struct ServerVault: Sendable {
  private let service: String
  private let keychainPath: String?
  private let credentialAgentURL: URL?
  public init(service: String = "local.mssqlstudio.servers", keychainPath: String? = nil, credentialAgentURL: URL? = nil) {
    self.service = service; self.keychainPath = keychainPath; self.credentialAgentURL = credentialAgentURL
  }
  private func agent() throws -> CredentialAgent? {
    if let credentialAgentURL {
      guard let keychainPath, service.hasPrefix("local.mssqlstudio.signing-test.") else {
        throw SQLFailure("Parola bileşeni test kapsamı geçersiz.")
      }
      return CredentialAgent(executable: credentialAgentURL, testService: service, testKeychain: keychainPath)
    }
    if service == "local.mssqlstudio.servers", keychainPath == nil,
      Bundle.main.bundleIdentifier == "local.mssqlstudio.app" {
      return try CredentialAgent.installed()
    }
    return nil // Explicit isolated fixtures/unsigned Swift test tools retain their own vault.
  }
  private func searchQuery() throws -> [String:Any] {
    var result:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service]
    if let keychainPath {
      var keychain:SecKeychain?
      try check(SecKeychainOpen(keychainPath,&keychain))
      if let keychain {result[kSecMatchSearchList as String] = [keychain]}
      result[kSecUseAuthenticationUI as String]=kSecUseAuthenticationUIFail
    }
    return result
  }
  private func applicationAccess() throws -> SecAccess {
    var access:SecAccess?
    // nil trusts only the calling signed application; never an empty trusted list.
    try check(SecAccessCreate("MSSQL Studio · Kayıtlı bağlantı" as CFString,nil,&access))
    guard let access else {throw SQLFailure("Keychain erişim kuralı oluşturulamadı.")}
    return access
  }
  private func query(_ id: UUID) throws -> [String: Any] {
    var result=try searchQuery();result[kSecAttrAccount as String]=id.uuidString
    return result
  }
  /// Renew only this vault's items. No password is read, deleted, or exported.
  /// The OS may request authorization for old ACLs; subsequent signed updates
  /// match the same designated requirement.
  public func renewApplicationAccess() throws -> Int {
    if let agent = try agent() { return try agent.request("renew").count }
    var code:SecCode?
    try check(SecCodeCopySelf([], &code))
    var requirement:SecRequirement?
    try check(SecRequirementCreateWithString(try PersonalSigningIdentity.requirement() as CFString,[],&requirement))
    guard let code,let requirement else {throw SQLFailure("Uygulama imzası doğrulanamadı.")}
    try check(SecCodeCheckValidity(code,[],requirement))
    var lookup=try searchQuery()
    lookup[kSecReturnAttributes as String]=true;lookup[kSecMatchLimit as String]=kSecMatchLimitAll
    var result:CFTypeRef?
    let status=SecItemCopyMatching(lookup as CFDictionary,&result)
    if status == errSecItemNotFound {return 0}
    try check(status)
    let access=try applicationAccess()
    var count=0
    for item in result as? [[String:Any]] ?? [] {
      guard let account=item[kSecAttrAccount as String] as? String,let id=UUID(uuidString:account) else {continue}
      try check(SecItemUpdate(try query(id) as CFDictionary,
        [kSecAttrAccess as String:access,kSecAttrLabel as String:"MSSQL Studio · Kayıtlı bağlantı"] as CFDictionary))
      count += 1
    }
    return count
  }
  public func save(_ profile: ServerProfile, password: String) throws {
    let data = try JSONEncoder().encode(SavedServer(profile: profile, password: password))
    if let agent = try agent() { _ = try agent.request("save", account: profile.id, data: data); return }
    var attributes = try query(profile.id)
    if let keychainPath {
      var keychain:SecKeychain?
      try check(SecKeychainOpen(keychainPath,&keychain))
      attributes[kSecUseKeychain as String]=keychain
    }
    let access=try applicationAccess()
    attributes[kSecAttrAccess as String]=access
    attributes[kSecAttrLabel as String]="MSSQL Studio · Kayıtlı bağlantı"
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let result = SecItemAdd(attributes as CFDictionary, nil)
    if result == errSecDuplicateItem {
      try check(
        SecItemUpdate(
          try query(profile.id) as CFDictionary, [kSecValueData as String: data,kSecAttrLabel as String:"MSSQL Studio · Kayıtlı bağlantı"] as CFDictionary))
    } else {
      try check(result)
    }
  }
  public func list() throws -> [SavedServer] {
    if let agent = try agent() {
      return try agent.request("list").records.map { try JSONDecoder().decode(SavedServer.self, from: $0) }
        .sorted { $0.profile.name < $1.profile.name }
    }
    var query = try searchQuery()
    query[kSecMatchLimit as String]=kSecMatchLimitAll
    query[kSecReturnAttributes as String]=true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return [] }
    try check(status)
    var records: [SavedServer] = []
    for item in result as? [[String: Any]] ?? [] {
      guard let account = item[kSecAttrAccount as String] as? String,
        let id = UUID(uuidString: account)
      else { continue }
      query = try self.query(id)
      query[kSecReturnData as String] = true
      var data: CFTypeRef?
      try check(SecItemCopyMatching(query as CFDictionary, &data))
      if let data = data as? Data {
        records.append(try JSONDecoder().decode(SavedServer.self, from: data))
      }
    }
    return records.sorted { $0.profile.name < $1.profile.name }
  }
  public func delete(_ id: UUID) throws {
    if let agent = try agent() { _ = try agent.request("delete", account: id); return }
    let code = SecItemDelete(try query(id) as CFDictionary)
    if code != errSecItemNotFound { try check(code) }
  }
  private func check(_ code: OSStatus) throws {
    guard code == errSecSuccess else {
      throw SQLFailure(
        "Keychain: \(SecCopyErrorMessageString(code, nil) as String? ?? String(code))")
    }
  }
}
public struct QueryRecord: Codable, Sendable, Identifiable {
  public var id: UUID = UUID()
  public var time = Date()
  public var server: String
  public var database: String
  public var text: String
  public var serverID: UUID?
  public var errorMessage: String?
  public var rowCount: Int?
  public var seconds: Double
  public var status: String
  public var tabTitle: String?
  public var caret: Int?
  public var selectionLength: Int?
  public var reopenedAt: Date?
  public init(server: String, database: String, text: String, serverID: UUID? = nil, errorMessage: String? = nil, rowCount: Int? = nil, seconds: Double, status: String) {
    self.server = server
    self.serverID = serverID; self.errorMessage = errorMessage; self.rowCount = rowCount
    self.database = database
    self.text = text
    self.seconds = seconds
    self.status = status
  }
}
public enum QueryHistoryPolicy {
  public static let defaultClosedTabLimit = 100
  public static func closedTabLimit(_ value:Int)->Int {min(1000,max(1,value))}
  /// Cheap in-memory closed-tab pruning; JSON byte enforcement stays on the disk actor.
  public static func closedTabs(_ records:[QueryRecord],limit:Int)->[QueryRecord] {
    var counts:[String:Int]=[:],bytes=0
    return records.sorted {$0.time>$1.time}.filter {record in
      let scope=(record.serverID?.uuidString ?? record.server)+"|"+record.database
      let size=record.text.utf8.count
      guard !record.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
        counts[scope,default:0]<closedTabLimit(limit),bytes+size<=16_000_000 else {return false}
      counts[scope,default:0]+=1;bytes+=size;return true
    }
  }
  public static let defaultDays = 30
  public static func days(_ value: Int) -> Int { min(3650, max(1, value)) }
  public static func retained(_ records: [QueryRecord], days: Int, closedTabLimit:Int = defaultClosedTabLimit, now: Date = Date()) -> [QueryRecord] {
    let cutoff = now.addingTimeInterval(-Double(self.days(days)) * 86400)
    // A byte budget keeps unusually large statements from making the history file unreadable.
    var bytes = 0
    var count = 0
    var scopes:[String:Int]=[:]
    return records.sorted { $0.time > $1.time }.filter {
      let scope=($0.serverID?.uuidString ?? $0.server)+"|"+$0.database
      if $0.tabTitle != nil {
        guard !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,scopes[scope,default:0]<self.closedTabLimit(closedTabLimit) else {return false}
      } else if $0.time < cutoff {return false}
      let size = (try? JSONEncoder().encode($0).count) ?? 16_000_001
      guard bytes + size <= 16_000_000, count < 20000 else { return false }
      if $0.tabTitle != nil {scopes[scope,default:0]+=1}
      bytes += size; count += 1
      return true
    }
  }
}

public enum Export {
  public static func csv(_ rows: Rows, safe: Bool = true) -> String {
    func quote(_ text: String) -> String {
      "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return
      ([rows.fields.map { quote($0.name) }.joined(separator: ",")]
      + rows.values.map { row in
        row.map { value in
          guard let value else { return "\\N" }
          let clean = value.trimmingCharacters(in: .whitespaces)
          let text =
            safe && ["=", "+", "-", "@"].contains(String(clean.prefix(1))) ? "'" + value : value
          return quote(text)
        }.joined(separator: ",")
      }).joined(separator: "\r\n") + "\r\n"
  }
  public static func json(_ rows: Rows) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: [
        "columns": rows.fields.map(\.name),
        "rows": rows.values.map { row in row.map { $0 as Any? ?? NSNull() } },
      ], options: [.prettyPrinted, .sortedKeys])
  }
}

public enum ExplorerPersistence {
  public static func orderedIDs(_ ids:[UUID], previous:[String]?) -> [UUID] {
    let available=Set(ids)
    var seen=Set<UUID>()
    return ((previous ?? []).compactMap(UUID.init(uuidString:))+ids).filter {available.contains($0) && seen.insert($0).inserted}
  }
  public static func selectedIDs(saved: [UUID], previous: [String]?) -> [UUID] {
    guard let previous else { return saved }
    let available = Set(saved)
    return previous.compactMap(UUID.init(uuidString:)).filter { available.contains($0) }
  }
}
