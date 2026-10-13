import Foundation

/// In-memory execution provenance; never inferred from the current editor contents.
public struct SQLResultSource: Sendable, Equatable {
  public enum Kind: Sendable, Equatable { case statement, invocation, batch }
  public let sql: String
  public let batch: Int
  public let kind: Kind
  public init(sql: String, batch: Int = 1, kind: Kind = .statement) {
    self.sql = sql; self.batch = batch; self.kind = kind
  }
  public var heading: String {
    switch kind {
    case .statement: "Kaynak SQL · Grup \(batch)"
    case .invocation: "Çağrı SQL’i · Grup \(batch)"
    case .batch: "Kaynak SQL grubu · \(batch) (çoklu veya dinamik çıktı)"
    }
  }
  public var preview: String {
    let text = sql.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = String(text.prefix(2001))
    let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
    let clipped = lines.prefix(20).joined(separator: "\n")
    return String(clipped.prefix(2000)) + (lines.count > 20 || prefix.count > 2000 ? "\n… (SQL önizlemesi kısaltıldı)" : "")
  }
  public var help: String { heading + "\n\n" + preview }
}

/// Only straight-line, known rowset producers are matched by ordinal. Never split
/// execution itself: variables, transactions, procedures and session state stay intact.
public struct ResultSourceMap: Sendable {
  public let batchSource: SQLResultSource
  private let statements: [SQLResultSource]?
  private let invocation: SQLResultSource?
  public init(sql: String, batch: Int = 1) {
    batchSource = SQLResultSource(sql: sql, batch: batch, kind: .batch)
    guard sql.utf16.count <= 250_000 else { statements = nil; invocation = nil; return }
    let tokens = TSQL.lex(sql).filter { $0.kind != .space && $0.kind != .comment }
    func word(_ token: Lexeme) -> String {
      token.kind == .keyword || token.kind == .word && !token.text.hasPrefix("[") && !token.text.hasPrefix("\"") ? token.text.uppercased() : ""
    }
    let starters = Set(["SELECT", "DECLARE", "SET", "USE", "PRINT"])
    let compound = Set(["UNION", "ALL", "EXCEPT", "INTERSECT"])
    var segments: [[Lexeme]] = [], segment: [Lexeme] = [], depth = 0
    var hasSelect = false
    for token in tokens {
      let upper = word(token)
      if depth == 0, token.text == ";" {
        if !segment.isEmpty { segment.append(token); segments.append(segment) }
        segment = []; hasSelect = false; continue
      }
      if depth == 0, !segment.isEmpty, starters.contains(upper),
        (upper != "SELECT" || hasSelect || segment.first.map(word) != "WITH"),
        !compound.contains(segment.last.map(word) ?? "") {
        segments.append(segment); segment = []; hasSelect = false
      }
      segment.append(token)
      if depth == 0 && upper == "SELECT" { hasSelect = true }
      if token.text == "(" { depth += 1 }
      if token.text == ")" { depth -= 1 }
    }
    if !segment.isEmpty { segments.append(segment) }
    func source(_ segment: [Lexeme], kind: SQLResultSource.Kind = .statement) -> SQLResultSource {
      let start = segment[0].range.location, end = NSMaxRange(segment.last!.range)
      return SQLResultSource(sql: (sql as NSString).substring(with: NSRange(location: start, length: end-start)), batch: batch, kind: kind)
    }
    if segments.count == 1, let first = segments[0].first, ["EXEC", "EXECUTE"].contains(word(first)),
      tokens.filter({ ["EXEC", "EXECUTE"].contains(word($0)) }).count == 1 {
      statements = nil; invocation = source(segments[0], kind: .invocation); return
    }
    invocation = nil
    var producers: [SQLResultSource] = []
    let unsafe = Set(["EXEC", "EXECUTE", "IF", "ELSE", "WHILE", "GOTO", "RETURN", "CREATE", "ALTER", "DROP", "INSERT", "UPDATE", "DELETE", "MERGE", "DBCC", "FETCH", "OPEN", "CLOSE", "READTEXT", "COMPUTE", "RAISERROR", "THROW", "CURSOR", "BACKUP", "RESTORE"])
    for segment in segments {
      guard let first = segment.first, !segment.contains(where: { unsafe.contains(word($0)) }) else { statements = nil; return }
      let firstWord = word(first)
      guard ["SELECT", "WITH", "DECLARE", "SET", "USE", "PRINT"].contains(firstWord) else { statements = nil; return }
      if ["DECLARE", "SET", "USE", "PRINT"].contains(firstWord) { continue }
      // CTE bodies/subqueries do not create independent result sets.
      var nesting = 0, top: [Lexeme] = []
      for token in segment {
        if token.text == ")" { nesting -= 1; if nesting == 0 { top.append(token) }; continue }
        if nesting == 0 { top.append(token) }
        if token.text == "(" { nesting += 1 }
      }
      guard let select = top.firstIndex(where: { word($0) == "SELECT" }) else { statements = nil; return }
      if top.contains(where: { word($0) == "INTO" }) { continue }
      var projection = select + 1
      if projection < top.count && ["DISTINCT", "ALL"].contains(word(top[projection])) { projection += 1 }
      if projection < top.count && word(top[projection]) == "TOP" {
        projection += 1
        if projection+1 < top.count && top[projection].text == "(" && top[projection+1].text == ")" { projection += 2 }
        else if projection < top.count && (top[projection].kind == .number || top[projection].kind == .variable) { projection += 1 }
        while projection < top.count && ["PERCENT", "WITH", "TIES"].contains(word(top[projection])) { projection += 1 }
      }
      if projection + 1 < top.count, top[projection].kind == .variable,
        top[projection+1].text == "=" || projection+2 < top.count && ["+", "-", "*", "/", "%", "&", "|", "^"].contains(top[projection+1].text) && top[projection+2].text == "=" { continue }
      producers.append(source(segment))
    }
    statements = depth == 0 ? producers : nil
  }
  public func sources(for results: [Rows]) -> [SQLResultSource?] {
    let rowsets = results.filter { !$0.fields.isEmpty && !$0.isPlan }
    let exact = statements.flatMap { $0.count == rowsets.count ? $0 : nil }
    var ordinal = 0
    return results.map { rows in
      guard !rows.fields.isEmpty else { return nil }
      if let invocation { return invocation }
      if rows.isPlan { return exact?.count == 1 ? exact![0] : batchSource }
      defer { ordinal += 1 }
      return exact?[ordinal] ?? batchSource
    }
  }
}
