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
    SQLBlockStructure(source).matchingPair(at:caret)
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
    variableAnalysis(sql).unused
  }
  public struct VariableAnalysis:Sendable {
    public let unused:[NSRange]
    public let undeclared:[NSRange]
  }
  /// Bounded lexical analysis. Named EXEC argument labels are not local references.
  public static func variableAnalysis(_ sql:String)->VariableAnalysis {
    guard sql.utf16.count <= 250_000 else { return VariableAnalysis(unused:[],undeclared:[]) }
    let source = sql as NSString
    let tokens = lex(sql).filter { $0.kind != .space && $0.kind != .comment }
    var result: [NSRange] = [], missing:[NSRange]=[], batch: [Lexeme] = []
    func inspect() {
      let headers=SQLRoutineDefinition.headers(in:batch,source:sql)
      var signatureLocations=Set<Int>(),labels=Set<Int>()
      var outputNames:[Lexeme]=[]
      for header in headers {
        for index in header.tokenRange {
          let token=batch[index]
          signatureLocations.insert(token.range.location)
          if token.text.uppercased() == "RETURNS", index+1 < batch.count,batch[index+1].kind == .variable {
            outputNames.append(batch[index+1])
          }
        }
      }
      let boundaries=Set(["SELECT","SET","DECLARE","BEGIN","END","IF","ELSE","WHILE","RETURN","PRINT","EXEC","EXECUTE","INSERT","UPDATE","DELETE","MERGE","CREATE","ALTER","DROP","USE","FETCH","OPEN","CLOSE"])
      for index in batch.indices where batch[index].kind == .keyword && ["EXEC","EXECUTE"].contains(batch[index].text.uppercased()) && !signatureLocations.contains(batch[index].range.location) {
        var j=index+1
        if j+1 < batch.count,batch[j].kind == .variable,batch[j+1].text == "=" {j+=2}
        guard j < batch.count,batch[j].kind == .word || batch[j].kind == .variable else {continue}
        j+=1
        while j+1 < batch.count,batch[j].text == ".",batch[j+1].kind == .word {j+=2}
        var depth=0,argumentStart=true
        while j < batch.count {
          let token=batch[j]
          if depth == 0 && (token.text == ";" || token.kind == .keyword && boundaries.contains(token.text.uppercased())) {break}
          if argumentStart,token.kind == .variable,j+1 < batch.count,batch[j+1].text == "=" {labels.insert(token.range.location)}
          argumentStart=false
          if token.text == "(" {depth+=1}
          if token.text == ")" {depth=max(0,depth-1)}
          if token.text == ",",depth == 0 {argumentStart=true}
          j+=1
        }
      }
      var counts: [String:Int] = [:], declarations: [Lexeme] = []
      for token in batch where token.kind == .variable && !labels.contains(token.range.location) {
        counts[token.text.lowercased(),default:0] += 1
      }
      declarations=declaredVariables(in:batch,source:sql)
      for declaration in declarations where counts[declaration.text.lowercased()] == 1 {
        result.append(declaration.range)
      }
      var firstDeclaration:[String:Int]=[:]
      for token in declarations+outputNames {
        firstDeclaration[token.text.lowercased()]=min(firstDeclaration[token.text.lowercased()] ?? Int.max,token.range.location)
      }
      for token in batch where token.kind == .variable && token.text != "@" && !token.text.hasPrefix("@@") && !labels.contains(token.range.location) && !signatureLocations.contains(token.range.location) {
        if (firstDeclaration[token.text.lowercased()] ?? Int.max) > token.range.location {missing.append(token.range)}
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
    return VariableAnalysis(unused:result.sorted {$0.location < $1.location},undeclared:missing.sorted {$0.location < $1.location})
  }
  static func declaredVariables(in tokens:[Lexeme],source:String)->[Lexeme] {
      let formalLocations=Set(SQLRoutineDefinition.headers(in:tokens,source:source)
        .filter(\.hasSQLBody).flatMap(\.parameters).map(\.location))
      var declarations=tokens.filter {formalLocations.contains($0.range.location)}
      var i = 0
      while i < tokens.count {
        guard tokens[i].text.uppercased() == "DECLARE", i+2 < tokens.count,
          tokens[i+1].kind == .variable else { i += 1; continue }
        var j = i+1, depth = 0, caseDepth = 0
        var expectsName = true
        while j < tokens.count {
          let token = tokens[j], upper = token.text.uppercased()
          if depth == 0 && caseDepth == 0 && (token.text == ";" ||
            ["SELECT","SET","DECLARE","BEGIN","END","IF","WHILE","RETURN","PRINT","EXEC","EXECUTE","INSERT","UPDATE","DELETE","MERGE","CREATE","ALTER","DROP","FETCH","OPEN","CLOSE"].contains(upper)) { break }
          if expectsName {
            guard token.kind == .variable, !token.text.hasPrefix("@@"),
              j+1 < tokens.count else { break }
            let typeIndex = tokens[j+1].text.uppercased() == "AS" ? j+2 : j+1
            guard typeIndex < tokens.count,
              tokens[typeIndex].kind == .word || tokens[typeIndex].text.uppercased() == "TABLE" else { break }
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
      return declarations
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
