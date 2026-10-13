import Foundation

public struct Lexeme: Sendable {
  public enum Kind: Sendable {
    case word, keyword, string, comment, number, variable, symbol, space
  }
  public let text: String
  public let range: NSRange
  public let kind: Kind
}
public struct ScriptBatch: Sendable {
  public let text: String
  public let line: Int
}
public struct CatalogSymbol: Sendable, Codable {
  public let schema: String
  public let name: String
  public let columns: [String]
  public let kind: String
  public init(schema: String, name: String, columns: [String], kind: String = "USER_TABLE") {
    self.schema = schema
    self.name = name
    self.columns = columns
    self.kind = kind
  }
}
public enum TSQL {
  /// Lexical block pairing: CASE consumes its own END; transaction BEGIN is not a block.
  /// Work is bounded on the native selection path and ranges remain UTF-16.
  public static func matchingBlock(in source:String,at caret:Int) -> [NSRange] {
    guard source.utf16.count <= 250_000,caret >= 0,caret <= source.utf16.count else {return []}
    let tokens=lex(source).filter {$0.kind != .space && $0.kind != .comment}
    var stack:[Int]=[],parentheses:[Int]=[],pairs:[Int:Int]=[:]
    for (i,token) in tokens.enumerated() {
      if token.kind == .symbol {
        if token.text == "(" {parentheses.append(i)}
        if token.text == ")",let start=parentheses.popLast() {pairs[start]=i;pairs[i]=start}
      }
      guard token.kind == .keyword else {continue}
      switch token.text.uppercased() {
      case "GO": stack.removeAll();parentheses.removeAll()
      case "CASE": stack.append(i)
      case "BEGIN":
        let next=i+1 < tokens.count ? tokens[i+1].text.uppercased():""
        if !["TRAN","TRANSACTION","DISTRIBUTED","DIALOG","CONVERSATION"].contains(next) {stack.append(i)}
      case "END":
        // END CONVERSATION is an independent statement, never a block closer.
        if i+1 < tokens.count,tokens[i+1].text.uppercased() == "CONVERSATION" {continue}
        if let start=stack.popLast() {pairs[start]=i;pairs[i]=start}
      default: break
      }
    }
    // At adjacent parentheses prefer the delimiter immediately after the caret.
    let selected=tokens.indices.first {pairs[$0] != nil && tokens[$0].range.location <= caret && caret < NSMaxRange(tokens[$0].range)} ?? tokens.indices.last {pairs[$0] != nil && NSMaxRange(tokens[$0].range) == caret}
    guard let i=selected,
      let other=pairs[i] else {return []}
    return [tokens[min(i,other)].range,tokens[max(i,other)].range]
  }
  /// Quote pairing belongs to typed code, never to comments or existing literals.
  /// Bound synchronous work on the editor's input path.
  public static func allowsQuotePair(in source:String,at caret:Int) -> Bool {
    let length=source.utf16.count
    guard length <= 250_000, (0...length).contains(caret) else {return false}
    guard let token=lex(source).first(where: {$0.range.location < caret && NSMaxRange($0.range) >= caret}) else {return true}
    let quoted=token.kind == .string || token.kind == .word && (token.text.hasPrefix("[") || token.text.hasPrefix("\""))
    if NSMaxRange(token.range) > caret {return token.kind != .comment && !quoted}
    if token.kind == .comment {
      if token.text.hasPrefix("--") {return false}
      let units=Array(token.text.utf16);var depth=0,index=0
      while index+1 < units.count {
        if units[index] == 47 && units[index+1] == 42 {depth+=1;index+=2}
        else if units[index] == 42 && units[index+1] == 47 {depth-=1;index+=2}
        else {index+=1}
      }
      return depth == 0
    }
    if token.kind == .string {return token.text.utf16.filter {$0 == 39}.count.isMultiple(of:2)}
    if token.text.hasPrefix("\"") {return token.text.utf16.filter {$0 == 34}.count.isMultiple(of:2)}
    if token.text.hasPrefix("[") {return !token.text.utf16.filter {$0 == 93}.count.isMultiple(of:2)}
    return true
  }
  /// Conservative eligibility for unattended repetition; this is not a SQL authorization boundary.
  public static func canRepeatRead(_ sql: String) -> Bool {
    let allTokens = lex(sql).filter { $0.kind != .space && $0.kind != .comment }
    // Monitoring scripts often start with local filter parameters. Parse only
    // built-in scalar declarations with literal/NULL initializers and the
    // count-message setting SET NOCOUNT ON/OFF, then apply
    // the existing read-only policy to the complete remaining script. Merely
    // removing DECLARE from the forbidden words would also admit table/cursor
    // variables, executable expressions and arbitrary user-defined types.
    guard let tokens = repeatReadBody(afterParameters: allTokens) else { return false }
    let forbidden = Set("KILL SHUTDOWN RECONFIGURE BULK RECEIVE SEND MOVE PRINT THROW RAISERROR DECLARE INSERT UPDATE DELETE MERGE INTO EXEC EXECUTE CREATE ALTER DROP TRUNCATE GRANT REVOKE DENY BACKUP RESTORE DBCC USE SET BEGIN COMMIT ROLLBACK SAVE TRAN TRANSACTION WAITFOR GO OPENROWSET OPENQUERY OPENDATASOURCE NEXT UPDLOCK XLOCK HOLDLOCK TABLOCKX".split(separator: " ").map(String.init))
    guard !tokens.contains(where: { token in
      token.kind != .string && forbidden.contains(token.text.uppercased())
    }) else { return false }
    // SQL Server commonly requires ;WITH after another statement. Empty statement
    // terminators must not make an otherwise read-only CTE ineligible. Check each
    // statement head so this does not admit a bare procedure invocation or a
    // non-SELECT CTE tail. GO (including repeat counts) remains explicitly blocked.
    var starting = true, hasSelect = false, anySelect = false, depth = 0
    for token in tokens {
      if token.text == ";" {
        guard depth == 0, starting || hasSelect else { return false }
        starting = true; hasSelect = false
        continue
      }
      if starting {
        guard ["SELECT", "WITH"].contains(token.text.uppercased()) else { return false }
        starting = false
      }
      if token.text == "(" { depth += 1 }
      if token.text == ")" { depth -= 1; if depth < 0 { return false } }
      if token.text.uppercased() == "SELECT" { hasSelect = true; anySelect = true }
    }
    return depth == 0 && anySelect && (starting || hasSelect)
  }

  private static func repeatReadBody(afterParameters tokens: [Lexeme]) -> ArraySlice<Lexeme>? {
    let scalarTypes = Set("BIT TINYINT SMALLINT INT INTEGER BIGINT MONEY SMALLMONEY REAL DATE DATETIME SMALLDATETIME UNIQUEIDENTIFIER SYSNAME SQL_VARIANT BINARY VARBINARY CHAR VARCHAR NCHAR NVARCHAR DEC DECIMAL NUMERIC FLOAT TIME DATETIME2 DATETIMEOFFSET".split(separator: " ").map(String.init))
    var i = 0
    func text(_ index: Int) -> String { index < tokens.count ? tokens[index].text.uppercased() : "" }
    func validTypeArguments(_ type: String, _ arguments: [String]) -> Bool {
      switch type {
      case "DEC", "DECIMAL", "NUMERIC":
        guard (1...2).contains(arguments.count), let precision = Int(arguments[0]), (1...38).contains(precision) else { return false }
        return arguments.count == 1 || Int(arguments[1]).map { (0...precision).contains($0) } == true
      case "FLOAT": return arguments.count == 1 && Int(arguments[0]).map { (1...53).contains($0) } == true
      case "TIME", "DATETIME2", "DATETIMEOFFSET": return arguments.count == 1 && Int(arguments[0]).map { (0...7).contains($0) } == true
      case "BINARY", "VARBINARY", "CHAR", "VARCHAR", "NCHAR", "NVARCHAR":
        guard arguments.count == 1 else { return false }
        if arguments[0] == "MAX" { return ["VARBINARY", "VARCHAR", "NVARCHAR"].contains(type) }
        return Int(arguments[0]).map { (1...(["NCHAR", "NVARCHAR"].contains(type) ? 4000 : 8000)).contains($0) } == true
      default: return false
      }
    }
    while true {
      while text(i) == ";" { i += 1 }
      if text(i) == "SET" {
        // Only the literal row-count-message option is harmless to repeat.
        // Keep every other SET, and all settings after the SELECT body, blocked.
        guard text(i+1) == "NOCOUNT", ["ON", "OFF"].contains(text(i+2)) else { return nil }
        i += 3
        continue
      }
      guard text(i) == "DECLARE" else { return tokens[i...] }
      i += 1
      while true {
        guard i < tokens.count, tokens[i].kind == .variable,
          !tokens[i].text.hasPrefix("@@"), tokens[i].text.count > 1 else { return nil }
        i += 1
        if text(i) == "AS" { i += 1 }
        let type = text(i)
        guard scalarTypes.contains(type) else { return nil }
        i += 1
        if text(i) == "(" {
          i += 1
          var arguments: [String] = []
          while true {
            guard i < tokens.count, tokens[i].kind == .number || text(i) == "MAX" else { return nil }
            arguments.append(text(i)); i += 1
            if text(i) != "," { break }
            i += 1
          }
          guard text(i) == ")", validTypeArguments(type, arguments) else { return nil }
          i += 1
        }
        if text(i) == "=" {
          i += 1
          guard i < tokens.count else { return nil }
          if tokens[i].kind == .string {
            // Reject an unterminated literal; embedded quotes remain untouched.
            guard tokens[i].text.range(of: #"(?is)^N?'(?:[^']|'')*'$"#, options: .regularExpression) != nil else { return nil }
            i += 1
          } else if text(i) == "NULL" {
            i += 1
          } else {
            let first = i
            while i < tokens.count, ![",", ";", "DECLARE", "SET", "SELECT", "WITH"].contains(text(i)) { i += 1 }
            let literal = tokens[first..<i].map(\.text).joined()
            // Deliberately no variable, function, subquery or expression calls.
            guard literal.range(of: #"^(?:0[xX][0-9A-Fa-f]*|[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)$"#, options: .regularExpression) != nil else { return nil }
          }
        }
        if text(i) == "," { i += 1; continue }
        // SQL Server permits an omitted terminator before the next statement.
        guard i == tokens.count || [";", "DECLARE", "SET", "SELECT", "WITH"].contains(text(i)) else { return nil }
        break
      }
    }
  }

  public static let keywords = Set(
    "SELECT FROM WHERE JOIN INNER LEFT RIGHT FULL OUTER CROSS APPLY ON AS AND OR NOT IS NULL IN EXISTS BETWEEN LIKE GROUP BY HAVING ORDER ASC DESC OFFSET FETCH NEXT ROWS ONLY TOP DISTINCT UNION ALL EXCEPT INTERSECT WITH INSERT INTO VALUES UPDATE SET DELETE MERGE OUTPUT CREATE ALTER DROP TABLE VIEW PROCEDURE FUNCTION TRIGGER INDEX DECLARE BEGIN END TRY CATCH TRAN TRANSACTION COMMIT ROLLBACK IF ELSE CASE WHEN THEN USE EXEC EXECUTE RETURN THROW RAISERROR PRINT GO OVER PARTITION GRANT REVOKE DENY PRIMARY KEY FOREIGN REFERENCES CHECK DEFAULT CONSTRAINT UNIQUE CLUSTERED NONCLUSTERED INCLUDE"
      .split(separator: " ").map(String.init))
  public static let functions = [
    "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "ISNULL", "NULLIF", "CAST", "CONVERT",
    "TRY_CAST", "TRY_CONVERT", "ROW_NUMBER", "RANK", "DENSE_RANK", "GETDATE", "SYSDATETIME",
    "SYSUTCDATETIME", "DATEADD", "DATEDIFF", "DATETRUNC", "STRING_AGG", "STRING_SPLIT",
    "JSON_VALUE", "JSON_QUERY", "OPENJSON", "DB_NAME", "OBJECT_ID", "SUSER_SNAME", "NEWID", "LEN",
    "DATALENGTH", "CONCAT", "TRIM", "SUBSTRING", "REPLACE",
  ]
  public static func lex(_ sql: String) -> [Lexeme] {
    let units = Array(sql.utf16)
    var index = 0
    var result: [Lexeme] = []
    func word(_ c: UInt16) -> Bool {
      c >= 128 || (65...90).contains(c) || (97...122).contains(c) || (48...57).contains(c)
        || [95, 64, 35, 36].contains(c)
    }
    while index < units.count {
      let start = index
      let c = units[index]
      var kind = Lexeme.Kind.symbol
      if [9, 10, 13, 32].contains(c) {
        kind = .space
        index += 1
        while index < units.count && [9, 10, 13, 32].contains(units[index]) { index += 1 }
      } else if c == 45 && index + 1 < units.count && units[index + 1] == 45 {
        kind = .comment
        index += 2
        while index < units.count && ![10, 13].contains(units[index]) { index += 1 }
      } else if c == 47 && index + 1 < units.count && units[index + 1] == 42 {
        kind = .comment
        index += 2
        var depth = 1
        while index < units.count && depth > 0 {
          if index + 1 < units.count && units[index] == 47 && units[index + 1] == 42 {
            depth += 1
            index += 2
          } else if index + 1 < units.count && units[index] == 42 && units[index + 1] == 47 {
            depth -= 1
            index += 2
          } else {
            index += 1
          }
        }
      } else if [39, 91, 34].contains(c)
        || ([78, 110].contains(c) && index + 1 < units.count && units[index + 1] == 39)
      {
        if [78, 110].contains(c) { index += 1 }
        let closing: UInt16 = units[index] == 91 ? 93 : units[index]
        kind = closing == 39 ? .string : .word
        index += 1
        while index < units.count {
          if units[index] == closing {
            index += 1
            if index < units.count && units[index] == closing { index += 1 } else { break }
          } else {
            index += 1
          }
        }
      } else if word(c) {
        index += 1
        while index < units.count && word(units[index]) { index += 1 }
        let text = String(decoding: units[start..<index], as: UTF16.self)
        kind =
          c == 64
          ? .variable
          : ((48...57).contains(c)
            ? .number : (keywords.contains(text.uppercased()) ? .keyword : .word))
      } else {
        index += 1
      }
      result.append(
        Lexeme(
          text: String(decoding: units[start..<index], as: UTF16.self),
          range: NSRange(location: start, length: index - start), kind: kind))
    }
    return result
  }
  /// Local DECLARE and SQL routine input names with no other lexical reference in their batch.
  /// Assignments count as references; this does not attempt dead-store/data-flow analysis.
  public static func unusedDeclaredVariables(_ sql: String) -> [NSRange] {
    guard sql.utf16.count <= 250_000 else { return [] }
    let source = sql as NSString
    let tokens = lex(sql).filter { $0.kind != .space && $0.kind != .comment }
    var result: [NSRange] = [], batch: [Lexeme] = []
    func inspect() {
      var counts: [String:Int] = [:], declarations: [Lexeme] = []
      for token in batch where token.kind == .variable {
        counts[token.text.lowercased(),default:0] += 1
      }
      let formalLocations=Set(SQLRoutineDefinition.headers(in:batch,source:sql)
        .filter(\.hasSQLBody).flatMap(\.parameters).map(\.location))
      declarations=batch.filter {formalLocations.contains($0.range.location)}
      var i = 0
      while i < batch.count {
        guard batch[i].text.uppercased() == "DECLARE", i+2 < batch.count,
          batch[i+1].kind == .variable else { i += 1; continue }
        var j = i+1, depth = 0, caseDepth = 0
        var expectsName = true
        while j < batch.count {
          let token = batch[j], upper = token.text.uppercased()
          if depth == 0 && caseDepth == 0 && (token.text == ";" ||
            ["SELECT","SET","DECLARE","BEGIN","END","IF","WHILE","RETURN","PRINT","EXEC","EXECUTE","INSERT","UPDATE","DELETE","MERGE","CREATE","ALTER","DROP","FETCH","OPEN","CLOSE"].contains(upper)) { break }
          if expectsName {
            guard token.kind == .variable, !token.text.hasPrefix("@@"),
              j+1 < batch.count else { break }
            let typeIndex = batch[j+1].text.uppercased() == "AS" ? j+2 : j+1
            guard typeIndex < batch.count,
              batch[typeIndex].kind == .word || batch[typeIndex].text.uppercased() == "TABLE" else { break }
            declarations.append(token); expectsName = false
          }
          if token.text == "(" { depth += 1 }
          if token.text == ")" { depth = max(0,depth-1) }
          if token.kind == .keyword && upper == "CASE" { caseDepth += 1 }
          if token.kind == .keyword && upper == "END" { caseDepth = max(0,caseDepth-1) }
          if token.text == "," && depth == 0 && caseDepth == 0 { expectsName = true }
          j += 1
        }
        i = max(i+1,j)
      }
      for declaration in declarations where counts[declaration.text.lowercased()] == 1 {
        result.append(declaration.range)
      }
    }
    for token in tokens {
      // GO is a separator only on its own line, optionally followed by a count/comment.
      if SQLRoutineDefinition.isBatchSeparator(token,source:source) {
        inspect(); batch=[]; continue
      }
      batch.append(token)
    }
    inspect()
    return result.sorted {$0.location < $1.location}
  }
  public static func batches(_ sql: String) throws -> [ScriptBatch] {
    let ns = sql as NSString
    let protected = lex(sql).filter {
      [.string, .comment, .word].contains($0.kind)
        && ($0.kind != .word || $0.text.hasPrefix("[") || $0.text.hasPrefix("\""))
    }
    let regex = try NSRegularExpression(
      pattern: "(?im)^[\\t ]*GO(?:[\\t ]+(\\d+))?[\\t ]*(?:--[^\\r\\n]*)?(?:\\r?\\n|$)")
    var result: [ScriptBatch] = []
    var beginning = 0
    for match in regex.matches(in: sql, range: NSRange(location: 0, length: ns.length)) {
      guard
        !protected.contains(where: {
          NSIntersectionRange($0.range, match.range).length > 0 && !$0.text.hasPrefix("--")
        })
      else { continue }
      let repetitions =
        match.range(at: 1).location == NSNotFound
        ? 1 : Int(ns.substring(with: match.range(at: 1))) ?? 0
      guard (1...100).contains(repetitions) else {
        throw SQLFailure("GO tekrar sayısı 1–100 arasında olmalı.")
      }
      let text = ns.substring(
        with: NSRange(location: beginning, length: match.range.location - beginning))
      let line = ns.substring(to: beginning).filter { $0 == "\n" }.count + 1
      if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        for _ in 0..<repetitions { result.append(ScriptBatch(text: text, line: line)) }
      }
      beginning = NSMaxRange(match.range)
      guard result.count <= 1000 else { throw SQLFailure("En fazla 1.000 batch çalıştırılabilir.") }
    }
    let text = ns.substring(from: beginning)
    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result.append(
        ScriptBatch(text: text, line: ns.substring(to: beginning).filter { $0 == "\n" }.count + 1))
    }
    return result
  }
  public static func run(
    _ sql: String, on connection: ODBCConnection, limits: Limits = Limits(),
    events: (@Sendable (QueryEvent) -> Void)? = nil
  ) async throws -> Execution {
    try await run(sql, limits: limits, events: events) { text, budget, events in
      try await connection.execute(text, limits: budget, events: events)
    }
  }
  // Shared batch orchestration also permits deterministic budget/streaming tests
  // without connecting to a user's database.
  static func run(
    _ sql: String, limits: Limits,
    events: (@Sendable (QueryEvent) -> Void)? = nil,
    execute: @Sendable (String, Limits, (@Sendable (QueryEvent) -> Void)?) async throws -> Execution
  ) async throws -> Execution {
    let start = Date()
    var output = Execution()
    var budget = limits
    for (batchIndex, batch) in try batches(sql).enumerated() {
      if budget.resultSets <= 0 || budget.totalBytes <= 0 {
        output.partial = true
        output.stoppedEarly = true
        output.messages.append("Sorgu bütçesi doldu; sonraki batch'ler çalıştırılmadı.")
        break
      }
      do {
        try Task.checkCancellation()
        let offset = output.results.count
        let sourceMap = ResultSourceMap(sql: batch.text, batch: batchIndex + 1)
        var result = try await execute(
          batch.text, budget,
          { event in
            switch event {
            case .source(let index, let source): events?(.source(offset + index, source))
            case .result(let index, let fields):
              events?(.source(offset + index, sourceMap.batchSource))
              events?(.result(offset + index, fields))
            case .rows(let index, let rows): events?(.rows(offset + index, rows))
            case .snapshot(let index, let rows): events?(.snapshot(offset + index, rows))
            case .message(let text): events?(.message(text))
            }
          })
        let sources = sourceMap.sources(for: result.results)
        for index in result.results.indices {
          result.results[index].source = sources[index]
          if let source = sources[index] { events?(.source(offset + index, source)) }
        }
        output.results += result.results
        output.messages += result.messages
        output.partial = output.partial || result.partial
        output.stoppedEarly = result.stoppedEarly
        budget.resultSets -= result.results.count
        budget.totalBytes -= result.bytesRead
        output.bytesRead += result.bytesRead
        if output.stoppedEarly { break }
      } catch {
        let message = "Batch başlangıç satırı \(batch.line): \(error.localizedDescription)"
        guard !output.results.isEmpty else {
          let failure=error as? SQLFailure
          throw SQLFailure("Batch başlangıç satırı \(batch.line): \(failure?.message ?? error.localizedDescription)",diagnostics:failure?.diagnostics ?? [])
        }
        output.partial = true
        output.stoppedEarly = true
        output.messages.append(message)
        break
      }
    }
    output.elapsed = Date().timeIntervalSince(start)
    return output
  }
  public static func format(_ sql: String) -> String {
    let tokens = lex(sql)
    var text = ""
    var depth = 0
    var previous = [String?](repeating: nil, count: tokens.count)
    var next = previous
    var last: String?
    for i in tokens.indices {
      previous[i] = last
      if tokens[i].kind != .space { last = tokens[i].text }
    }
    last = nil
    for i in tokens.indices.reversed() {
      next[i] = last
      if tokens[i].kind != .space { last = tokens[i].text }
    }
    let clauses: Set<String> = [
      "SELECT", "FROM", "WHERE", "GROUP", "HAVING", "ORDER", "UNION", "JOIN", "LEFT", "RIGHT",
      "INNER", "OUTER", "CROSS",
    ]
    for (i, token) in tokens.enumerated() {
      let word =
        token.kind == .keyword && previous[i] != "." && next[i] != "."
        ? token.text.uppercased() : token.text
      if word == ")" { depth = max(0, depth - 1) }
      if token.kind == .keyword && depth == 0 && clauses.contains(word) && !text.isEmpty
        && text.last != "\n"
      {
        text += "\n"
      }
      if text.isEmpty || text.last == "\n" {
        if token.kind != .space { text += String(repeating: "    ", count: min(depth, 10)) }
      }
      text += word
      if word == "(" { depth += 1 }
    }
    return text
  }
  public static func completions(
    prefix: String, before: String, script: String, symbols: [CatalogSymbol]
  ) -> [String] {
    let tokens = lex(script).filter { ![.comment, .space, .string].contains($0.kind) }
    func name(_ text: String) -> String {
      text.trimmingCharacters(in: CharacterSet(charactersIn: "[]\"")).lowercased()
    }
    var aliases: [String: String] = [:]
    var local = CompletionSymbols.collect(tokens, catalog: symbols)
    // DECLARE @table TABLE(...) and CREATE TABLE #temporary(...).
    for i in tokens.indices where ["TABLE"].contains(tokens[i].text.uppercased()) {
      var tableName = ""
      var open = i + 1
      if i > 0 && tokens[i - 1].kind == .variable {
        tableName = name(tokens[i - 1].text)
      } else if open < tokens.count {
        tableName = name(tokens[open].text)
        open += 1
      }
      if open < tokens.count && tokens[open].text == "(" {
        var columns: [String] = []
        var depth = 1
        var first = true
        var j = open + 1
        while j < tokens.count && depth > 0 {
          let token = tokens[j]
          if token.text == "(" { depth += 1 }
          if token.text == ")" { depth -= 1 }
          if depth == 1 && first && token.kind == .word {
            columns.append(
              SQL.identifier(
                token.text.hasPrefix("[")
                  ? String(token.text.dropFirst().dropLast()).replacingOccurrences(
                    of: "]]", with: "]") : token.text))
            first = false
          }
          if depth == 1 && token.text == "," { first = true }
          j += 1
        }
        local[tableName] = columns
      }
    }
    for i in tokens.indices
    where ["FROM", "JOIN", "UPDATE", "INTO"].contains(tokens[i].text.uppercased()) {
      var j = i + 1
      var parts: [String] = []
      while j < tokens.count && [.word, .variable].contains(tokens[j].kind) {
        parts.append(name(tokens[j].text))
        j += 1
        if j < tokens.count && tokens[j].text == "." { j += 1 } else { break }
      }
      guard let last = parts.last else { continue }
      let table = parts.joined(separator: ".")
      aliases[last] = table
      if j < tokens.count && tokens[j].text.uppercased() == "AS" { j += 1 }
      if j < tokens.count && tokens[j].kind == .word { aliases[name(tokens[j].text)] = table }
    }
    let context = before.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidates =
      Array(keywords) + functions + tokens.filter { $0.kind == .variable }.map(\.text)
    if context.hasSuffix(".") {
      let qualifier = name(
        lex(String(context.dropLast())).last(where: { $0.kind != .space })?.text ?? "")
      let table = aliases[qualifier] ?? qualifier
      if let columns = local[table] {
        candidates = columns
      } else if let object = symbols.first(where: {
        "\($0.schema).\($0.name)".lowercased() == table || $0.name.lowercased() == table
      }) {
        candidates = object.columns.map(SQL.identifier)
      } else {
        candidates = symbols.filter { $0.schema.lowercased() == qualifier }.map {
          SQL.identifier($0.name)
        }
      }
    } else {
      candidates += symbols.map { SQL.identifier($0.schema) + "." + SQL.identifier($0.name) }
      candidates += symbols.flatMap { $0.columns }.map(SQL.identifier)
    }
    let needle = name(prefix)
    return Array(Set(candidates)).filter {
      needle.isEmpty || name($0).hasPrefix(needle) || $0.lowercased().hasPrefix(needle)
    }.sorted().prefix(100).map { $0 }
  }
}

extension TSQL {
  public enum SyntaxStyle: Sendable {
    case plain, keyword, string, comment, function, systemObject, procedure, operatorSymbol
  }
  /// Styling is independent of lexing: batch splitting and completion retain their grammar.
  public static func syntaxStyle(_ token: Lexeme) -> SyntaxStyle {
    switch token.kind {
    case .string: return .string
    case .comment: return .comment
    case .keyword: return .keyword
    case .symbol: return .operatorSymbol
    case .word:
      let word = token.text.uppercased()
      if functions.contains(word) { return .function }
      if ["SYS", "INFORMATION_SCHEMA"].contains(word) { return .systemObject }
      if word.hasPrefix("SP_") || word.hasPrefix("XP_") { return .procedure }
      if Set(
        "INT BIGINT SMALLINT TINYINT BIT DECIMAL NUMERIC MONEY FLOAT REAL DATE DATETIME DATETIME2 DATETIMEOFFSET TIME CHAR VARCHAR NCHAR NVARCHAR TEXT NTEXT BINARY VARBINARY UNIQUEIDENTIFIER XML SQL_VARIANT SYSNAME"
          .split(separator: " ").map(String.init)
      ).contains(word) {
        return .keyword
      }
      return .plain
    default: return .plain
    }
  }
}

public enum ModuleEditing {
  public static func changedObjects(_ sql: String) -> [(name: String, folder: Folder)] {
    let t = TSQL.lex(sql).filter { $0.kind != .space && $0.kind != .comment && $0.kind != .string }
    var result: [(String, Folder)] = []
    for i in t.indices where ["CREATE", "ALTER", "DROP"].contains(t[i].text.uppercased()) {
      var j = i + 1
      if j + 1 < t.count && t[j].text.uppercased() == "OR" && t[j+1].text.uppercased() == "ALTER" { j += 2 }
      guard j + 1 < t.count else { continue }
      let folder: Folder
      switch t[j].text.uppercased() {
      case "TABLE": folder = .tables
      case "VIEW": folder = .views
      case "PROC", "PROCEDURE": folder = .procedures
      case "FUNCTION": folder = .functions
      case "SYNONYM": folder = .synonyms
      case "TRIGGER": folder = .triggers
      default: continue
      }
      j += 1
      if t[j].text.uppercased() == "IF", j + 2 < t.count { j += 2 }
      guard t[j].kind == .word || t[j].kind == .keyword else { continue }
      func unquote(_ value: String) -> String {
        if value.hasPrefix("[") && value.hasSuffix("]") { return String(value.dropFirst().dropLast()).replacingOccurrences(of: "]]", with: "]") }
        if value.hasPrefix("\"") && value.hasSuffix("\"") { return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"") }
        return value
      }
      var name = unquote(t[j].text)
      if j + 2 < t.count && t[j+1].text == "." { name += "." + unquote(t[j+2].text) }
      result.append((name,folder))
    }
    return result
  }
  public static func alter(_ source: String) -> String {
    let tokens = TSQL.lex(source).filter { $0.kind != .space && $0.kind != .comment }
    guard let first = tokens.first, first.text.uppercased() == "CREATE" else { return source }
    let length: Int
    if tokens.count > 3 && tokens[1].text.uppercased() == "OR" && tokens[2].text.uppercased() == "ALTER" {
      length = NSMaxRange(tokens[2].range) - first.range.location
    } else { length = first.range.length }
    return (source as NSString).replacingCharacters(in: NSRange(location: first.range.location, length: length), with: "ALTER")
  }
  /// Linear prefix/suffix comparison: no quadratic diff allocation for large modules.
  public static func difference(original: String, edited: String) -> String {
    let a = alter(original).components(separatedBy: "\n"), b = edited.components(separatedBy: "\n")
    var prefix = 0
    while prefix < min(a.count,b.count), a[prefix] == b[prefix] { prefix += 1 }
    if prefix == a.count && prefix == b.count { return "Değişiklik yok." }
    var suffix = 0
    while suffix < min(a.count,b.count) - prefix, a[a.count - suffix - 1] == b[b.count - suffix - 1] { suffix += 1 }
    let old = a[prefix..<(a.count-suffix)].prefix(1000).map { "− " + String($0.prefix(2000)) }
    let new = b[prefix..<(b.count-suffix)].prefix(1000).map { "+ " + String($0.prefix(2000)) }
    return "@@ Satır \(prefix + 1) · −\(a.count-prefix-suffix) / +\(b.count-prefix-suffix) @@\n" + (old + new).joined(separator: "\n") + "\n(Önizleme: her tarafta en fazla 1.000 satır; aradaki değişmeyen satırlar da blokta olabilir.)"
  }
}

/// Conservative structural outlining. Strings, comments, CASE and BEGIN TRAN cannot close a code block.
public enum SQLFolding {
  public struct Region: Equatable, Sendable {
    public let header: NSRange
    public let hidden: NSRange
  }
  public static func regions(_ source: String) -> [Region] {
    let text = source as NSString
    guard text.length <= 250_000 else { return [] }
    let tokens = TSQL.lex(source).filter { $0.kind != .space && $0.kind != .comment && $0.kind != .string }
    let tokensByLine=Dictionary(grouping:tokens,by:{text.lineRange(for:$0.range).location})
    var stack: [(String, NSRange)] = [], result: [Region] = []
    for (index, token) in tokens.enumerated() {
      let word = token.text.uppercased()
      if token.kind != .keyword && token.kind != .word { continue }
      if word == "CASE" { stack.append(("CASE", token.range)) }
      if word == "BEGIN" {
        let next = index+1 < tokens.count ? tokens[index+1].text.uppercased() : ""
        if ["TRAN", "TRANSACTION", "DISTRIBUTED", "DIALOG", "CONVERSATION"].contains(next) { continue }
        stack.append(("BEGIN", token.range))
      }
      if word == "END", let opener = stack.popLast(), opener.0 == "BEGIN" {
        var header = text.lineRange(for: opener.1)
        // Keep the condition/ELSE visible as the fold header when BEGIN is on the next line.
        if header.location > 0 {
          let previous=text.lineRange(for:NSRange(location:header.location-1,length:0))
          let words=tokensByLine[previous.location] ?? []
          if let first=words.first,["IF","ELSE"].contains(first.text.uppercased()),!words.contains(where:{$0.text == ";" || $0.text.uppercased() == "END"}) {header=previous}
        }
        let closing = text.lineRange(for: token.range)
        var start = NSMaxRange(header), end = NSMaxRange(closing)
        while start > header.location && [10,13].contains(text.character(at:start-1)) { start -= 1 }
        while end > closing.location && [10,13].contains(text.character(at:end-1)) { end -= 1 }
        if closing.location > header.location, end > start {
          result.append(Region(header:header,hidden:NSRange(location:start,length:end-start)))
        }
      }
      if word == "GO" { stack.removeAll() }
    }
    return result.sorted { $0.hidden.location < $1.hidden.location }
  }
  public struct Projection: Sendable {
    public let source: String
    public let text: String
    public let regions: [Region]
    public init(source: String, collapsed: [Region]) {
      self.source=source
      let original = source as NSString
      var chosen: [Region] = [], end = 0
      for region in collapsed.sorted(by: { $0.hidden.location < $1.hidden.location }) {
        guard region.hidden.location >= end, NSMaxRange(region.hidden) <= original.length else { continue }
        chosen.append(region); end = NSMaxRange(region.hidden)
      }
      regions = chosen
      var value = "", cursor = 0
      for region in chosen {
        value += original.substring(with:NSRange(location:cursor,length:region.hidden.location-cursor)) + " …"
        cursor = NSMaxRange(region.hidden)
      }
      text = value + original.substring(from:cursor)
    }
    public func sourceOffset(_ offset: Int, end: Bool = false) -> Int {
      var delta = 0
      for region in regions {
        let start = region.hidden.location-delta
        if offset < start { break }
        if offset <= start+2 { return end || offset == start+2 ? NSMaxRange(region.hidden) : region.hidden.location }
        delta += region.hidden.length-2
      }
      return offset+delta
    }
    public func displayOffset(_ offset: Int) -> Int {
      var delta = 0
      for region in regions {
        if offset < region.hidden.location { break }
        if offset < NSMaxRange(region.hidden) { return region.hidden.location-delta }
        delta += region.hidden.length-2
      }
      return offset-delta
    }
    public func sourceRange(_ range: NSRange) -> NSRange {
      let start = sourceOffset(range.location)
      let finish = range.length == 0 ? start : sourceOffset(NSMaxRange(range),end:true)
      return NSRange(location:start,length:max(0,finish-start))
    }
  }
}
