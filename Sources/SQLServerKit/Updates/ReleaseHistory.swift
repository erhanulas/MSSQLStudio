import Foundation

public struct ApplicationIdentity: Sendable, Equatable {
  public let version: String
  public let build: String
  public init(info: [String: Any]) {
    version = info["CFBundleShortVersionString"] as? String ?? "Bilinmiyor"
    build = info["CFBundleVersion"] as? String ?? "Bilinmiyor"
  }
}

public struct ReleaseNote: Codable, Sendable, Identifiable, Equatable {
  public var id: String { version }
  public let version: String
  public let date: String
  public let title: String
  public let changes: [String]
}

public enum ReleaseHistory {
  public static func bundled() throws -> [ReleaseNote] {
    guard let url = Bundle.module.url(forResource: "ReleaseNotes", withExtension: "json") else {
      throw SQLFailure("Sürüm değişiklikleri bu pakette bulunamadı.")
    }
    return try decode(Data(contentsOf: url))
  }
  public static func decode(_ data: Data) throws -> [ReleaseNote] {
    let notes = try JSONDecoder().decode([ReleaseNote].self, from: data)
    var versions = Set<String>()
    guard !notes.isEmpty else { throw SQLFailure("Sürüm geçmişi boş.") }
    for note in notes {
      let parts = note.version.split(separator: ".", omittingEmptySubsequences: false)
      guard (2...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
        versions.insert(note.version).inserted, !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !note.changes.isEmpty, note.changes.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
        throw SQLFailure("Sürüm geçmişi geçersiz.")
      }
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withFullDate]
      guard let date = formatter.date(from: note.date), formatter.string(from: date) == note.date else {
        throw SQLFailure("Sürüm tarihi geçersiz.")
      }
    }
    return notes.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
  }
}
