import Foundation

/// Explicit INSERT column/value ordinals, resolved without SQL execution or
/// guessing physical table order (identity/computed columns may be omitted).
public struct SQLInsertMapping: Sendable {
  public struct Column: Sendable {
    public let name: String
    public let range: NSRange
  }
  public struct Statement: Sendable {
    public let target: String
    public let columns: [Column]
    public let rows: [[NSRange]]
  }
  public struct Match: Sendable {
    public let target: String
    public let column: String
    public let ordinal: Int
    public let columnCount: Int
    public let row: Int?
    public let ranges: [NSRange]
    public let value: String
  }
  public let statements: [Statement]
  private let source: String
  public init(_ source: String) {
    self.source = source
    guard source.utf16.count <= 250000 else {
      statements = []
      return
    }
    let tokens = TSQL.lex(source).filter { $0.kind != .space && $0.kind != .comment }
    guard tokens.count <= 30000 else {
      statements = []
      return
    }
    let ns = source as NSString
    var closes: [Int: Int] = [:]
    var stack: [Int] = []
    for i in tokens.indices {
      if tokens[i].text == "(" { stack.append(i) }
      if tokens[i].text == ")", let open = stack.popLast() { closes[open] = i }
      if SQLRoutineDefinition.isBatchSeparator(tokens[i], source: ns) { stack = [] }
    }
    func word(_ i: Int) -> String { i < tokens.count ? tokens[i].text.uppercased() : "" }
    func identifier(_ i: Int) -> Bool {
      i < tokens.count && [.word, .keyword, .variable].contains(tokens[i].kind)
    }
    func raw(_ name: String) -> String {
      if name.hasPrefix("["), name.hasSuffix("]") {
        return String(name.dropFirst().dropLast()).replacingOccurrences(of: "]]", with: "]")
      }
      if name.hasPrefix("\""), name.hasSuffix("\"") {
        return String(name.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
      }
      return name
    }
    func slots(_ open: Int, _ close: Int) -> [NSRange] {
      var result: [NSRange] = []
      var start = open + 1
      var depth = 0
      var boundary = NSMaxRange(tokens[open].range)
      func append(_ end: Int) {
        if start < end {
          result.append(
            NSRange(
              location: tokens[start].range.location,
              length: NSMaxRange(tokens[end - 1].range) - tokens[start].range.location))
        } else {
          result.append(
            NSRange(location: boundary, length: max(0, tokens[end].range.location - boundary)))
        }
      }
      for i in open + 1..<close {
        if word(i) == "(" { depth += 1 }
        if word(i) == ")" { depth -= 1 }
        if depth == 0 && word(i) == "," {
          append(i)
          start = i + 1
          boundary = NSMaxRange(tokens[i].range)
        }
      }
      append(close)
      return result
    }
    let byOffset = Dictionary(uniqueKeysWithValues: tokens.map { ($0.range.location, $0) })
    var result: [Statement] = []
    for index in tokens.indices where tokens[index].kind == .keyword && word(index) == "INSERT" {
      var i = index + 1
      if word(i) == "TOP" {
        i += 1
        if word(i) == "(", let close = closes[i] { i = close + 1 } else { i += 1 }
        if word(i) == "PERCENT" { i += 1 }
      }
      if word(i) == "INTO" { i += 1 }
      guard identifier(i), !["SELECT", "VALUES", "EXEC", "EXECUTE", "DEFAULT"].contains(word(i))
      else { continue }
      var names = [tokens[i].text]
      i += 1
      while word(i) == ".", identifier(i + 1), names.count < 4 {
        names.append(tokens[i + 1].text)
        i += 2
      }
      if word(i) == "WITH", word(i + 1) == "(", let close = closes[i + 1] { i = close + 1 }
      guard word(i) == "(", let columnsEnd = closes[i] else { continue }
      let columnSlots = slots(i, columnsEnd)
      guard columnSlots.count <= 2100 else { continue }
      var columns: [Column] = []
      for range in columnSlots {
        guard let token = byOffset[range.location], token.range == range,
          [.word, .keyword].contains(token.kind)
        else {
          columns = []
          break
        }
        columns.append(Column(name: raw(token.text), range: token.range))
      }
      guard !columns.isEmpty else { continue }
      i = columnsEnd + 1
      while i < tokens.count, word(i) != "VALUES" {
        if [";", "SELECT", "EXEC", "EXECUTE", "DEFAULT", "INSERT", "UPDATE", "DELETE"].contains(
          word(i)) || SQLRoutineDefinition.isBatchSeparator(tokens[i], source: ns)
        {
          break
        }
        if word(i) == "(", let close = closes[i] { i = close + 1 } else { i += 1 }
      }
      guard word(i) == "VALUES" else { continue }
      i += 1
      var rows: [[NSRange]] = []
      while word(i) == "(", let close = closes[i], rows.count < 1000 {
        let row = slots(i, close)
        if row.count <= columns.count { rows.append(row) }
        i = close + 1
        if word(i) == "," { i += 1 } else { break }
      }
      if !rows.isEmpty {
        result.append(Statement(target: names.joined(separator: "."), columns: columns, rows: rows))
      }
    }
    statements = result
  }
  public func match(at selection: NSRange) -> Match? {
    guard !statements.isEmpty, selection.location != NSNotFound,
      selection.location >= 0, selection.length >= 0,
      selection.location <= source.utf16.count,
      selection.length <= source.utf16.count - selection.location
    else { return nil }
    func hits(_ range: NSRange) -> Bool {
      selection.length == 0
        ? selection.location >= range.location && selection.location <= NSMaxRange(range)
        : selection.location >= range.location && NSMaxRange(selection) <= NSMaxRange(range)
    }
    let ns = source as NSString
    for statement in statements {
      for (ordinal, column) in statement.columns.enumerated() {
        if hits(column.range) {
          let values = statement.rows.compactMap {
            $0.indices.contains(ordinal) ? $0[ordinal] : nil
          }
          return Match(
            target: statement.target, column: column.name, ordinal: ordinal + 1,
            columnCount: statement.columns.count, row: nil, ranges: [column.range] + values,
            value: values.first.map { ns.substring(with: $0) } ?? "")
        }
      }
      for (rowIndex, row) in statement.rows.enumerated() {
        for (ordinal, value) in row.enumerated() where hits(value) {
          let column = statement.columns[ordinal]
          return Match(
            target: statement.target, column: column.name, ordinal: ordinal + 1,
            columnCount: statement.columns.count, row: rowIndex + 1, ranges: [column.range, value],
            value: ns.substring(with: value))
        }
      }
    }
    return nil
  }
}
