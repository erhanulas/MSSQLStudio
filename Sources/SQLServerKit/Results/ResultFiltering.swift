import Foundation

public enum CellChoice: Hashable, Sendable {
  case null
  case text(String)
  public init(_ value: String?) { self = value.map(Self.text) ?? .null }
  public var title: String {
    switch self {
    case .null: return "NULL"
    case .text(let s): return s.isEmpty ? "(Boş metin)" : s
    }
  }
}
public enum ColumnOperation: String, CaseIterable, Sendable {
  case any = "Koşul yok"
  case contains = "İçerir"
  case notContains = "İçermez"
  case atLeast = "En az / Sonra veya eşit"
  case atMost = "En çok / Önce veya eşit"
  case starts = "İle başlar"
  case equal = "Eşittir"
  case unequal = "Eşit değildir"
  case greater = "Büyüktür / Sonra"
  case less = "Küçüktür / Önce"
  case between = "Arasında"
  case null = "NULL"
  case notNull = "NULL değil"
  case empty = "Boş metin"
  case notEmpty = "Boş metin değil"
  public var needsValue: Bool {
    [.contains, .notContains, .starts, .equal, .unequal, .greater, .less, .atLeast, .atMost, .between].contains(self)
  }
}
public struct ColumnRule: Equatable, Sendable {
  public var operation: ColumnOperation = .any
  public var first = ""
  public var second = ""
  /// nil means unrestricted; empty means match none. NULL differs from empty text.
  public var choices: Set<CellChoice>?
  public init() {}
  public var active: Bool { operation != .any || choices != nil }
  public var summary: String {
    (operation == .any
      ? ""
      : operation.rawValue + (operation.needsValue ? " \(first)" : "")
        + (operation == .between ? " – \(second)" : ""))
      + (choices.map { " · \($0.count) değer" } ?? "")
  }
}
public enum ResultFiltering {
  public static func isDate(_ field: Field) -> Bool {
    [Int16(9), 10, 11, 91, 92, 93, -154, -155].contains(field.type)
  }
  private enum Key {
    case null
    case number(Decimal)
    case date(Date)
    case text(String)
  }
  private static func date(_ text: String) -> Date? {
    var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let space = s.firstIndex(of: " ") { s.replaceSubrange(space...space, with: "T") }
    s = s.replacingOccurrences(of: " ", with: "")
    if s.count == 10 { s += "T00:00:00Z" }
    if s.count >= 8 && s[s.index(s.startIndex, offsetBy: 2)] == ":" { s = "1970-01-01T" + s }
    if !s.hasSuffix("Z")
      && s.range(of: "[+-][0-9]{2}:[0-9]{2}$", options: .regularExpression) == nil
    {
      s += "Z"
    }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let value = f.date(from: s) { return value }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
  }
  private static func key(_ text: String?, field: Field) -> Key {
    guard let text else { return .null }
    if field.numeric, let n = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) {
      return .number(n)
    }
    if isDate(field), let d = date(text) { return .date(d) }
    return .text(text)
  }
  private static func compare(_ a: Key, _ b: Key) -> ComparisonResult {
    switch (a, b) {
    case (.null, .null): return .orderedSame
    case (.null, _): return .orderedAscending
    case (_, .null): return .orderedDescending
    case (.number(let a), .number(let b)):
      return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
    case (.date(let a), .date(let b)):
      return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
    case (.text(let a), .text(let b)): return a.localizedStandardCompare(b)
    default: return .orderedSame
    }
  }
  public static func validate(_ rule: ColumnRule, field: Field) throws {
    guard rule.operation.needsValue else { return }
    for s in rule.operation == .between ? [rule.first, rule.second] : [rule.first] {
      if field.numeric
        && (s.range(
          of: "^[+-]?(?:[0-9]+(?:[.][0-9]*)?|[.][0-9]+)(?:[eE][+-]?[0-9]+)?$",
          options: .regularExpression) == nil
          || Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) == nil)
      {
        throw SQLFailure("Geçerli bir sayı girin; ondalık ayırıcı olarak nokta kullanın.")
      }
      if isDate(field) && date(s) == nil {
        throw SQLFailure("Tarihi YYYY-MM-DD veya ISO 8601 biçiminde girin.")
      }
    }
    if rule.operation == .between
      && compare(key(rule.first, field: field), key(rule.second, field: field))
        == .orderedDescending
    {
      throw SQLFailure("Aralığın başlangıcı bitişinden büyük olamaz.")
    }
  }
  public static func projection(
    _ rows: Rows, search: String, rules: [Int: ColumnRule], sortColumn: Int?, ascending: Bool
  ) throws -> [Int]? {
    let rules = rules.filter { rows.fields.indices.contains($0.key) && $0.value.active }
    let sort = sortColumn.flatMap { rows.fields.indices.contains($0) ? $0 : nil }
    guard !search.isEmpty || !rules.isEmpty || sort != nil else { return nil }
    for (i, r) in rules { try validate(r, field: rows.fields[i]) }
    let prepared = rules.map { (i, r) in
      (i, r, key(r.first, field: rows.fields[i]), key(r.second, field: rows.fields[i]))
    }
    var indices: [Int] = []
    indices.reserveCapacity(rows.values.count)
    var keys: [Key] = []
    if sort != nil { keys.reserveCapacity(rows.values.count) }
    for (index, row) in rows.values.enumerated() {
      if index % 1024 == 0 { try Task.checkCancellation() }
      if !search.isEmpty
        && !row.contains(where: { ($0 ?? "NULL").localizedCaseInsensitiveContains(search) })
      {
        continue
      }
      var matches = true
      for (i, rule, lower, upper) in prepared {
        let value = row.indices.contains(i) ? row[i] : nil
        if let choices = rule.choices, !choices.contains(CellChoice(value)) {
          matches = false
          break
        }
        let compares=[ColumnOperation.equal,.unequal,.greater,.less,.atLeast,.atMost,.between].contains(rule.operation)
        let actual=compares ? key(value,field:rows.fields[i]):.null
        let comparison=compares ? compare(actual,lower):.orderedSame
        let compatible:Bool
        switch (actual,lower) {
        case (.number,.number),(.date,.date),(.text,.text):compatible=true
        default:compatible=false
        }
        let yes: Bool
        switch rule.operation {
        case .any: yes = true
        case .null: yes = value == nil
        case .notNull: yes = value != nil
        case .empty: yes = value == ""
        case .notEmpty: yes = value != nil && value != ""
        case .contains: yes = value?.localizedCaseInsensitiveContains(rule.first) ?? false
        case .notContains: yes = !(value?.localizedCaseInsensitiveContains(rule.first) ?? false)
        case .atLeast: yes = value != nil && compatible && comparison != .orderedAscending
        case .atMost: yes = value != nil && compatible && comparison != .orderedDescending
        case .starts: yes = value?.lowercased().hasPrefix(rule.first.lowercased()) ?? false
        case .equal: yes = value != nil && comparison == .orderedSame
        case .unequal: yes = value != nil && comparison != .orderedSame
        case .greater: yes = value != nil && comparison == .orderedDescending
        case .less: yes = value != nil && comparison == .orderedAscending
        case .between:
          yes =
            value != nil && comparison != .orderedAscending
            && compare(key(value, field: rows.fields[i]), upper) != .orderedDescending
        }
        if !yes {
          matches = false
          break
        }
      }
      if matches {
        indices.append(index)
        if let sort {
          keys.append(key(row.indices.contains(sort) ? row[sort] : nil, field: rows.fields[sort]))
        }
      }
    }
    if let failure = rows.values.readFailure { throw SQLFailure(failure) }
    if sort != nil {
      // Sort cached keys, never random-read disk pages inside a comparison. Cancellable stable merge sort.
      var order = Array(indices.indices)
      var scratch = order
      var width = 1
      while width < order.count {
        try Task.checkCancellation()
        var base = 0
        while base < order.count {
          let mid = min(base + width, order.count)
          let end = min(base + width * 2, order.count)
          var a = base
          var b = mid
          var k = base
          while k < end {
            if k % 2048 == 0 { try Task.checkCancellation() }
            let takeA: Bool
            if a >= mid {
              takeA = false
            } else if b >= end {
              takeA = true
            } else {
              let c = compare(keys[order[a]], keys[order[b]])
              takeA =
                c == .orderedSame || (ascending ? c == .orderedAscending : c == .orderedDescending)
            }
            scratch[k] = takeA ? order[a] : order[b]
            if takeA { a += 1 } else { b += 1 }
            k += 1
          }
          base = end
        }
        swap(&order, &scratch)
        width *= 2
      }
      indices = order.map { indices[$0] }
    }
    return indices
  }
  public static func choices(_ rows: Rows, column: Int, search: String, limit: Int = 500) throws
    -> (values: [CellChoice], truncated: Bool)
  {
    var found = Set<CellChoice>()
    var truncated = false
    var bytes = 0
    for (i, row) in rows.values.enumerated() {
      if i % 1024 == 0 { try Task.checkCancellation() }
      let value = CellChoice(row.indices.contains(column) ? row[column] : nil)
      guard search.isEmpty || value.title.localizedCaseInsensitiveContains(search) else { continue }
      if found.contains(value) { continue }
      if found.count == limit || bytes + value.title.utf8.count > 4_194_304 {
        truncated = true
        break
      }
      found.insert(value)
      bytes += value.title.utf8.count
    }
    if let failure = rows.values.readFailure { throw SQLFailure(failure) }
    return (
      found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }, truncated
    )
  }
}

public enum ResultFileExport {
  /// Bounded serialization; writes a private sibling temp file, then atomically replaces destination.
  public static func write(_ rows: Rows, indices: [Int]?, json: Bool, to url: URL) throws {
    let temp = url.deletingLastPathComponent().appendingPathComponent(".MSSQL-export-\(UUID()).tmp")
    guard
      FileManager.default.createFile(
        atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600])
    else { throw SQLFailure("Dışa aktarma dosyası oluşturulamadı.") }
    defer { try? FileManager.default.removeItem(at: temp) }
    let file = try FileHandle(forWritingTo: temp)
    defer { try? file.close() }
    func write(_ text: String) throws { try file.write(contentsOf: Data(text.utf8)) }
    func quote(_ value: String) -> String {
      "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    if json {
      try write("{\"columns\":")
      try file.write(contentsOf: JSONSerialization.data(withJSONObject: rows.fields.map(\.name)))
      try write(",\"rows\":[\n")
    } else {
      try write(rows.fields.map { quote($0.name) }.joined(separator: ",") + "\r\n")
    }
    let count = indices?.count ?? rows.values.count
    var buffer = Data()
    for i in 0..<count {
      if i % 512 == 0 { try Task.checkCancellation() }
      let row = rows.values[indices?[i] ?? i]
      if json {
        if i > 0 { buffer.append(Data(",\n".utf8)) }
        buffer.append(
          try JSONSerialization.data(withJSONObject: row.map { $0 as Any? ?? NSNull() }))
      } else {
        let text =
          row.map { value -> String in
            guard let value else { return "\\N" }
            let clean = value.trimmingCharacters(in: .whitespaces)
            let safe = ["=", "+", "-", "@"].contains(String(clean.prefix(1))) ? "'" + value : value
            return quote(safe)
          }.joined(separator: ",") + "\r\n"
        buffer.append(Data(text.utf8))
      }
      if buffer.count >= 1_048_576 {
        try file.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
      }
    }
    try file.write(contentsOf: buffer)
    if let failure = rows.values.readFailure { throw SQLFailure(failure) }
    if json { try write("\n]}") }
    try Task.checkCancellation()
    try file.synchronize()
    try file.close()
    if FileManager.default.fileExists(atPath: url.path) {
      _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    } else {
      try FileManager.default.moveItem(at: temp, to: url)
    }
  }
}
