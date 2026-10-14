import Foundation

public struct ServerProfile: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var host: String
  public var port: Int
  public var database: String
  public var login: String
  public var kerberos: Bool
  public var trustCertificate: Bool
  /// nil preserves legacy profiles that show every accessible database.
  public var visibleDatabases: [String]?
  /// Explicit opt-in; absent legacy values remain disabled.
  public var indexObjectDefinitions: Bool?
  /// Explicit per-database choices. Nil preserves an existing legacy opt-in.
  public var definitionIndexDatabases: [String: Bool]?
  public func indexesDefinitions(in database: String) -> Bool {
    definitionIndexDatabases.map { $0[database] == true } ?? (indexObjectDefinitions == true)
  }
  public var hasDefinitionIndexes: Bool {
    definitionIndexDatabases.map { $0.values.contains(true) } ?? (indexObjectDefinitions == true)
  }
  public mutating func setDefinitionIndex(_ enabled: Bool, database: String, known: [String]) {
    if definitionIndexDatabases == nil {
      definitionIndexDatabases = Dictionary(uniqueKeysWithValues: Set(known + [database]).map { ($0, indexObjectDefinitions == true) })
    }
    definitionIndexDatabases?[database] = enabled
    indexObjectDefinitions = nil
  }
  public var appearance: ServerAppearance?
  public init(
    id: UUID = UUID(), name: String = "Local SQL Server", host: String = "localhost",
    port: Int = 1433, database: String = "master", login: String = "sa", kerberos: Bool = false,
    trustCertificate: Bool = false, visibleDatabases: [String]? = nil,
    appearance: ServerAppearance? = nil, indexObjectDefinitions: Bool? = nil,
    definitionIndexDatabases: [String: Bool]? = nil
  ) {
    self.id = id
    self.name = name
    self.host = host
    self.port = port
    self.database = database
    self.login = login
    self.kerberos = kerberos
    self.trustCertificate = trustCertificate
    self.visibleDatabases = visibleDatabases
    self.appearance = appearance
    self.indexObjectDefinitions = indexObjectDefinitions
    self.definitionIndexDatabases = definitionIndexDatabases
  }
  /// UI-only fields and the default database do not change existing SQL sessions.
  public func hasSameConnectionSettings(as other: ServerProfile, includeDatabase: Bool = false)
    -> Bool
  {
    host == other.host && port == other.port && login == other.login && kerberos == other.kerberos
      && trustCertificate == other.trustCertificate
      && (!includeDatabase || database == other.database)
  }
  public func visibleItems(from items: [CatalogItem]) -> [CatalogItem] {
    guard let visibleDatabases else { return items }
    let names = Set(visibleDatabases)
    return items.filter { names.contains($0.name) }
  }
  /// The default database must be one of the explicitly chosen, accessible databases.
  public mutating func selectDatabases(_ names: Set<String>, available: [CatalogItem]) throws {
    let chosen = available.filter { names.contains($0.name) }.map(\.name)
    guard !chosen.isEmpty else { throw SQLFailure("En az bir veritabanı seçin.") }
    visibleDatabases = chosen
    if !chosen.contains(database) { database = chosen[0] }
  }
  public func connectionString(password: String) throws -> String {
    guard !host.isEmpty, !database.isEmpty, (1...65535).contains(port), kerberos || !login.isEmpty,
      ![host, database, login, password].contains(where: { $0.contains("\0") }),
      host.utf16.count < 1024
    else { throw SQLFailure("Bağlantı alanlarını ve portu kontrol edin.") }
    func field(_ text: String) -> String {
      "{" + text.replacingOccurrences(of: "}", with: "}}") + "}"
    }
    let address = host.lowercased() == "localhost" && !kerberos ? "127.0.0.1" : host
    let auth = kerberos ? "Trusted_Connection=yes;" : "UID=\(field(login));PWD=\(field(password));"
    let result =
      "Driver={ODBC Driver 18 for SQL Server};Server=\(field("tcp:\(address),\(port)"));Database=\(field(database));\(auth)Encrypt=yes;TrustServerCertificate=\(trustCertificate ? "yes" : "no");APP=MSSQL Studio;"
    guard result.utf16.count < 32767 else { throw SQLFailure("Bağlantı bilgileri çok uzun.") }
    return result
  }
}
public struct Diagnostic: Sendable, Equatable {
  public let state: String
  public let code: Int
  public let message: String
  public var description: String { "[\(state)] \(code): \(message)" }
  public init(state: String, code: Int, message: String) {
    self.state = state
    self.code = code
    self.message = message
  }
}
public struct SQLFailure: LocalizedError, Sendable {
  public let message: String
  public let diagnostics: [Diagnostic]
  public init(_ message: String, diagnostics: [Diagnostic] = []) {
    self.message = message
    self.diagnostics = diagnostics
  }
  public var errorDescription: String? {
    message
      + (diagnostics.isEmpty ? "" : "\n" + diagnostics.map(\.description).joined(separator: "\n"))
  }
}
public struct Field: Sendable, Equatable {
  public let name: String
  public let type: Int16
  public let size: UInt
  public let scale: Int16
  public let declaredType: String?
  public init(_ name: String, type: Int16 = -9, size: UInt = 0, scale: Int16 = 0, declaredType: String? = nil) {
    self.name = name
    self.type = type
    self.size = size
    self.scale = scale
    self.declaredType = declaredType
  }
  public var dataType: String {
    let names: [Int16: String] = [-7:"bit", -6:"tinyint", -5:"bigint", 2:"numeric", 3:"decimal", 4:"int", 5:"smallint", 6:"float", 7:"real", 8:"float", 1:"char", 12:"varchar", -1:"varchar(max)", -8:"nchar", -9:"nvarchar", -10:"nvarchar(max)", -2:"binary", -3:"varbinary", -4:"varbinary(max)", 91:"date", 92:"time", 93:"datetime", -11:"uniqueidentifier", -151:"SQL Server UDT", -154:"time", -155:"datetimeoffset"]
    let name = declaredType ?? names[type] ?? "ODBC type \(type)"
    if [-1,-10,-4].contains(type), !name.contains("(max)") { return "\(name)(max)" }
    if ["datetime2", "datetimeoffset", "time"].contains(name.lowercased()) { return "\(name)(\(scale))" }
    if [2,3].contains(type) { return "\(name)(\(size),\(scale))" }
    if [1,12,-8,-9,-2,-3].contains(type), size > 0 { return "\(name)(\(size == UInt.max || size > 1_000_000_000 ? "max" : String(size)))" }
    return name
  }
  public var numeric: Bool { [Int16(-7), -6, -5, 2, 3, 4, 5, 6, 7, 8].contains(type) }

  /// ODBC numeric-to-text conversion may omit the zero before the decimal point.
  /// Use the ODBC base type, not the declared alias name (e.g. TDBFLOAT).
  /// Insert only that zero: parsing/reformatting could lose precision or scale.
  func normalizedResultValue(_ text: String?) -> String? {
    guard [Int16(2), 3, 6, 7, 8].contains(type), let text,
      text.hasPrefix(".") || text.hasPrefix("-.") || text.hasPrefix("+."),
      text.range(of: #"\A[+-]?\.[0-9]+(?:[eE][+-]?[0-9]+)?\z"#, options: .regularExpression) != nil
    else { return text }
    var result = text
    let position = text.first == "." ? text.startIndex : text.index(after: text.startIndex)
    result.insert("0", at: position)
    return result
  }
}
public struct Rows: Sendable {
  public var fields: [Field]
  public var values: RowCollection
  public var affected: Int
  public var source: SQLResultSource?
  /// This rowset is incomplete because of its row limit or a fetch failure.
  public var truncated = false
  public var isPlan: Bool {
    fields.count == 1 && values.first?.first.flatMap({ $0 })?.contains("<ShowPlanXML") == true
  }
  public init(fields: [Field] = [], values: [[String?]] = [], affected: Int = -1) {
    self.fields = fields
    self.values = RowCollection(values)
    self.affected = affected
  }
}
public struct Execution: Sendable {
  public var results: [Rows] = []
  public var messages: [String] = []
  public var bytesRead = 0
  public var elapsed: TimeInterval = 0
  public var partial = false
  /// Remaining results/batches were not processed (error, cancellation or shared budget).
  /// A per-rowset row limit alone does not stop subsequent results.
  public var stoppedEarly = false
  public init() {}
}
public struct Limits: Sendable {
  public var diskResults = false
  /// User result limits apply only to verified read-only queries.
  public var readOnlyRowLimit = false
  // Mixed batches preserve execution independently of an unlimited read limit.
  var preserveExecution = false
  /// Maximum retained rows per result set; byte and result-count budgets remain shared.
  public var rows = 50_000
  public var cellBytes = 2_097_152
  public var totalBytes = 67_108_864
  public var resultSets = 100
  public var timeout = 60
  public init() {}
}
public enum QueryEvent: Sendable {
  case source(Int, SQLResultSource)
  case result(Int, [Field])
  case rows(Int, [[String?]])
  case snapshot(Int, RowCollection)
  case message(String)
}
public enum SQL {
  public static func identifier(_ value: String) -> String {
    "[" + value.replacingOccurrences(of: "]", with: "]]") + "]"
  }
  public static func literal(_ value: String) -> String {
    "N'" + value.replacingOccurrences(of: "'", with: "''") + "'"
  }
}

public enum ServerEnvironment: String, Codable, CaseIterable, Sendable {
  case unspecified, live, test, attention, development, custom
  public var title: String {
    switch self {
    case .unspecified: return "Belirtilmedi"
    case .live: return "Canlı"
    case .test: return "Test"
    case .attention: return "Dikkat"
    case .development: return "Geliştirme"
    case .custom: return "Özel"
    }
  }
  public var defaultColorHex: String {
    switch self {
    case .live: return "D92D20"
    case .test: return "16804A"
    case .attention: return "C46A05"
    case .development: return "2563EB"
    case .unspecified, .custom: return "7C3AED"
    }
  }
}
public struct ServerAppearance: Codable, Equatable, Sendable {
  public var environment: ServerEnvironment
  public var customLabel: String
  public var colorHex: String?
  public init(
    environment: ServerEnvironment = .unspecified, customLabel: String = "", colorHex: String? = nil
  ) {
    self.environment = environment
    self.customLabel = customLabel
    self.colorHex = colorHex
  }
  public static func normalizedHex(_ input: String?) -> String? {
    guard let input else { return nil }
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.utf8.count == 6,
      text.utf8.allSatisfy({
        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
      })
    else { return nil }
    return text.uppercased()
  }
  public func validated() throws -> Self {
    var value = self
    if colorHex != nil {
      guard let hex = Self.normalizedHex(colorHex) else {
        throw SQLFailure("Renk kodu altı haneli olmalı: örneğin D92D20.")
      }
      value.colorHex = hex
    }
    if environment != .custom {value.customLabel=""}
    if value.customLabel.count > 40 {
      throw SQLFailure("Özel ortam etiketi en fazla 40 karakter olmalı.")
    }
    return value
  }
  public var effectiveColorHex: String {
    Self.normalizedHex(colorHex) ?? environment.defaultColorHex
  }
  public var isMarked: Bool { environment != .unspecified || Self.normalizedHex(colorHex) != nil }
  public var badge: String {
    if environment == .custom {
      let label = customLabel.components(separatedBy: .newlines).joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return label.isEmpty ? "Özel" : String(label.prefix(40))
    }
    return environment == .unspecified ? (isMarked ? "Özel renk" : "") : environment.title
  }
}
