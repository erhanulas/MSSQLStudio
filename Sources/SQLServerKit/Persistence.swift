import Foundation
import Security

public struct SavedServer: Codable, Sendable {
  public var profile: ServerProfile
  public var password: String
}
public struct ServerVault: Sendable {
  private let service: String
  private let keychainPath: String?
  public init(service: String = "local.mssqlstudio.servers", keychainPath: String? = nil) {
    self.service = service; self.keychainPath = keychainPath
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
  public var seconds: Double
  public var status: String
  public init(server: String, database: String, text: String, seconds: Double, status: String) {
    self.server = server
    self.database = database
    self.text = text
    self.seconds = seconds
    self.status = status
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
  public static func selectedIDs(saved: [UUID], previous: [String]?) -> [UUID] {
    guard let previous else { return saved }
    let available = Set(saved)
    return previous.compactMap(UUID.init(uuidString:)).filter { available.contains($0) }
  }
}
