import Foundation
import Security

public struct SavedServer: Codable, Sendable {
  public var profile: ServerProfile
  public var password: String
}
public struct ServerVault: Sendable {
  private let service: String
  public init(service: String = "local.mssqlstudio.servers") { self.service = service }
  private func query(_ id: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
    ]
  }
  public func save(_ profile: ServerProfile, password: String) throws {
    let data = try JSONEncoder().encode(SavedServer(profile: profile, password: password))
    var attributes = query(profile.id)
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let result = SecItemAdd(attributes as CFDictionary, nil)
    if result == errSecDuplicateItem {
      try check(
        SecItemUpdate(
          query(profile.id) as CFDictionary, [kSecValueData as String: data] as CFDictionary))
    } else {
      try check(result)
    }
  }
  public func list() throws -> [SavedServer] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return [] }
    try check(status)
    var records: [SavedServer] = []
    for item in result as? [[String: Any]] ?? [] {
      guard let account = item[kSecAttrAccount as String] as? String,
        let id = UUID(uuidString: account)
      else { continue }
      query = self.query(id)
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
    let code = SecItemDelete(query(id) as CFDictionary)
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
