import Foundation

public struct SQLFormattingOptions: Codable, Equatable, Sendable {
  public enum KeywordCase: String, Codable, CaseIterable, Sendable { case upper, lower, preserve }
  public enum CommaStyle: String, Codable, CaseIterable, Sendable { case trailing, leading }
  public var indentWidth: Int
  public var keywordCase: KeywordCase
  public var commaStyle: CommaStyle
  public var multilineLists: Bool
  public var lineWidth: Int?
  public var breakConditions: Bool
  public var blankLineAfterSelect: Bool?
  public var blankLineAfterDeclare: Bool?
  public init(indentWidth: Int = 4, keywordCase: KeywordCase = .upper,
              commaStyle: CommaStyle = .trailing, multilineLists: Bool = true, breakConditions: Bool = true, lineWidth: Int = 120, blankLineAfterSelect: Bool = true, blankLineAfterDeclare: Bool = true) {
    self.blankLineAfterSelect=blankLineAfterSelect;self.blankLineAfterDeclare=blankLineAfterDeclare
    self.indentWidth = max(2, min(8, indentWidth)); self.keywordCase = keywordCase
    self.lineWidth = lineWidth == 0 ? 0 : max(60,min(240,lineWidth))
    self.commaStyle = commaStyle; self.multilineLists = multilineLists; self.breakConditions = breakConditions
  }
}

/// Whitespace/case-only T-SQL formatting. No alias, comma, comment or statement
/// token is inserted/removed. A lexical equivalence check rejects unsafe output.
public enum SQLFormatter {
  /// Map a caret through whitespace/case-only formatting by lexical token ordinal.
  public static func correspondingOffset(_ offset:Int,in source:String,formatted:String)->Int {
    let before=TSQL.lex(source).filter {$0.kind != .space},after=TSQL.lex(formatted).filter {$0.kind != .space}
    let location=min(max(0,offset),source.utf16.count)
    guard before.count==after.count else {return min(location,formatted.utf16.count)}
    for (index,token) in before.enumerated() {
      if location<=NSMaxRange(token.range) {
        let target=after[index].range
        return target.location+min(target.length,max(0,location-token.range.location))
      }
    }
    return formatted.utf16.count
  }
  private static let clauseWords = Set("FROM WHERE JOIN LEFT RIGHT INNER FULL OUTER CROSS ON AS AND OR IS IN BETWEEN LIKE GROUP BY HAVING ORDER ASC DESC OFFSET FETCH UNION ALL EXCEPT INTERSECT WHEN THEN ELSE END OVER PARTITION WITH SET VALUES OUTPUT INTO BEGIN SELECT".split(separator:" ").map(String.init))
  private struct Frame {
    var clause = ""
    var query = false
    var list = false
    var indent = 0
  }
  public static func format(_ source: String, options: SQLFormattingOptions = .init()) -> String {
    guard source.utf16.count <= 250_000 else { return source }
    // SQLCMD directives and malformed/unfinished lexical constructs are retained.
    guard !source.split(whereSeparator: \.isNewline).contains(where: {
      let line = $0.trimmingCharacters(in: .whitespaces)
      return line.hasPrefix(":") || line.hasPrefix("!!")
    }) else { return source }
    let tokens = TSQL.lex(source).filter { $0.kind != .space }
    guard !tokens.isEmpty, tokens.count <= 30000 else { return source }
    let ns = source as NSString
    let statements=SQLExecutionScopes(source,protectControlFlow:false).statements
    var blankBefore=Set<Int>()
    for pair in zip(statements,statements.dropFirst()) {
      if pair.0.kind == "SELECT" && (options.blankLineAfterSelect ?? true) || pair.0.kind == "DECLARE" && pair.1.kind != "DECLARE" && (options.blankLineAfterDeclare ?? true) {
        blankBefore.insert(pair.1.range.location)
      }
    }
    var frames = [Frame(query: true)], blockIndent = 0, caseIndent = 0
    var caseBases: [Int] = []
    var lines: [String] = [], current = "", pendingIndent = 0, between = false
    let width = max(2, min(8, options.indentWidth))
    let lineWidth = options.lineWidth ?? 120
    func newline(_ indent: Int? = nil) {
      if !current.isEmpty { lines.append(current); current = "" }
      pendingIndent = max(0, min(40, indent ?? (blockIndent + caseIndent + frames.last!.indent)))
    }
    func write(_ text: String, space: Bool) {
      if current.isEmpty { current = String(repeating: " ", count: pendingIndent * width) + text }
      else { current += (space ? " " : "") + text }
    }
    func gap(_ index: Int) -> String {
      guard index > 0 else { return "" }
      let start = NSMaxRange(tokens[index-1].range)
      return ns.substring(with: NSRange(location: start, length: tokens[index].range.location-start))
    }
    func operandWidth(after index: Int) -> Int {
      var depth=0, length=0
      for j in index+1..<tokens.count {
        let token=tokens[j], word=token.text.uppercased()
        if depth == 0 && (["+","-","*","/",",",";"].contains(word) || token.kind == .keyword && clauseWords.contains(word)) { break }
        if word == "(" { depth += 1 }
        if word == ")" { if depth == 0 { break }; depth -= 1 }
        length += token.text.utf16.count+1
        if length > max(120,lineWidth) { break }
      }
      return length
    }
    for i in tokens.indices {
      let token = tokens[i], upper = token.text.uppercased()
      if blankBefore.contains(token.range.location) {
        newline()
        if !lines.isEmpty,lines.last != "" {lines.append("")}
      }
      let previous = i > 0 ? tokens[i-1].text.uppercased() : ""
      let next = i+1 < tokens.count ? tokens[i+1].text.uppercased() : ""
      let qualified = previous == "." || next == "."
      let keyword = token.kind == .keyword && !qualified && !isIdentifier(tokens,index:i,source:ns)
      let batch = SQLRoutineDefinition.isBatchSeparator(token, source: ns)
      if batch { blockIndent = 0; caseIndent = 0; caseBases = []; frames = [Frame(query: true)]; newline(0) }
      // GO count and its optional comment stay on the original separator line.
      if i > 0, tokens[i-1].kind != .comment, gap(i).contains(where: \.isNewline),
         (previous == "GO" || i > 1 && tokens[i-2].text.uppercased() == "GO") { newline() }
      if token.kind == .comment {
        if gap(i).contains(where: \.isNewline) { newline() }
        write(token.text, space: !current.isEmpty)
        if token.text.hasPrefix("--") || token.text.contains("\n") { newline() }
        continue
      }
      if upper == ")", frames.count > 1 {
        let frame = frames.removeLast()
        if frame.query || frame.list { newline() }
      }
      let frameIndex = frames.count-1
      let queryLevel = frames[frameIndex].query
      let isBlockEnd = keyword && upper == "END" && next != "CONVERSATION"
      if isBlockEnd {
        if let base = caseBases.popLast() { caseIndent -= 1; newline(base) }
        else { blockIndent = max(0,blockIndent-1); newline() }
      }
      if keyword && upper == "CASE" { caseBases.append(max(pendingIndent,blockIndent + frames[frameIndex].indent)); caseIndent += 1 }
      if keyword && ["WHEN","ELSE"].contains(upper), caseIndent > 0 { newline((caseBases.last ?? 0) + 1) }
      if keyword && queryLevel && caseIndent == 0 {
        let beginsBlock = upper == "BEGIN" && !["TRAN","TRANSACTION","DISTRIBUTED","DIALOG","CONVERSATION"].contains(next)
        if beginsBlock || ["IF","WHILE","ELSE","RETURN","PRINT","THROW","RAISERROR","DECLARE"].contains(upper) { newline() }
        let joinModifiers = ["LEFT","RIGHT","FULL","INNER","OUTER","CROSS"]
        let joinStart = joinModifiers.contains(upper) && !joinModifiers.contains(previous)
        let clauseStart = ["SELECT","FROM","WHERE","GROUP","HAVING","ORDER","UNION","EXCEPT","INTERSECT","SET","VALUES","OUTPUT"].contains(upper)
          || upper == "JOIN" && !joinModifiers.contains(previous) || joinStart
        if clauseStart {
          // Do not split DELETE FROM, INSERT INTO, GROUP BY or table hints.
          if !(upper == "FROM" && previous == "DELETE") { newline() }
          frames[frameIndex].clause = upper
          between = false
        }
        if upper == "WITH", i == 0 || previous == ";" || previous == "GO" { frames[frameIndex].clause = "WITH" }
        if ["INSERT","UPDATE","DELETE","MERGE"].contains(upper) {
          newline(); frames[frameIndex].clause = upper
        }
        if upper == "INTO" { frames[frameIndex].clause = "INTO" }
        if upper == "ON", previous != "NOCOUNT", frames[frameIndex].clause != "SET" {
          newline(blockIndent + frames[frameIndex].indent + 1); frames[frameIndex].clause = "ON"
        }
      }
      if keyword && upper == "BETWEEN" { between = true }
      if keyword && ["AND","OR"].contains(upper), ["WHERE","ON","HAVING"].contains(frames[frameIndex].clause), options.breakConditions {
        if upper == "AND" && between { between = false }
        else { newline(blockIndent + caseIndent + frames[frameIndex].indent + 1) }
      }
      let multilineComma = upper == "," && options.multilineLists && (frames[frameIndex].list || queryLevel && ["SELECT","SET","VALUES","WITH"].contains(frames[frameIndex].clause)) && caseIndent == 0
      if multilineComma && options.commaStyle == .leading { newline(blockIndent + frames[frameIndex].indent + 1) }
      if token.kind == .symbol, ["+","-","*","/"].contains(upper), frames.count == 1, i > 0 {
        let prior=tokens[i-1]
        let binary=[Lexeme.Kind.variable,.word,.number,.string].contains(prior.kind) || previous == ")"
        let exponent=prior.kind == .number && prior.text.lowercased().hasSuffix("e") && gap(i).isEmpty
        if binary && !exponent && (gap(i).contains(where:\.isNewline) || lineWidth > 0 && current.utf16.count+operandWidth(after:i)+2 > lineWidth) {
          newline(blockIndent+frames[frameIndex].indent+1)
        }
      }
      var text = token.text
      if keyword {
        switch options.keywordCase {
        case .upper: text = upper
        case .lower: text = token.text.lowercased()
        case .preserve: break
        }
      }
      var space = !current.isEmpty
      if [",", ";", ")", "."].contains(upper) || previous == "." || previous == "(" { space = false }
      if upper == "(" {
        space = !current.isEmpty && (token.kind == .keyword || ["IN","EXISTS","VALUES","WITH","OVER","AS","BY"].contains(previous))
      }
      // Preserve lexical symbol adjacency: >=, !=, ::, +=, decimals and unary
      // signs must not merge/split into a different operator or number.
      if i > 0, token.kind == .symbol && tokens[i-1].kind == .symbol { space = !gap(i).isEmpty }
      if i > 0, ["+","-",":"].contains(previous) || ["+","-",":"].contains(upper) { space = !gap(i).isEmpty }
      if upper == "," && options.commaStyle == .leading && multilineComma { space = false }
      write(text, space: space)
      if upper == "(" {
        let query = ["SELECT","WITH"].contains(next)
        // Only the outer DML list owns column/value line breaks. A nested
        // function call inherits the clause, but never its list layout.
        let list = options.multilineLists && frames.count == 1 && ["INTO","INSERT","VALUES"].contains(frames[frameIndex].clause)
        let base = frames[frameIndex].indent
        frames.append(Frame(clause: frames[frameIndex].clause, query: query, list: list, indent: base + (query || list ? 1 : 0)))
        if query || list { newline() }
      }
      if multilineComma && options.commaStyle == .trailing { newline(blockIndent + frames[frameIndex].indent + 1) }
      if keyword && upper == "BEGIN" && !["TRAN","TRANSACTION","DISTRIBUTED","DIALOG","CONVERSATION"].contains(next) {
        blockIndent += 1
        if !["TRY","CATCH"].contains(next) { newline() }
      }
      if keyword && ["TRY","CATCH"].contains(upper) && ["BEGIN","END"].contains(previous) { newline() }
      if isBlockEnd && ![";","TRY","CATCH","ELSE"].contains(next) { newline() }
      if upper == ";" { newline() }
      if batch, next != "" && tokens[i+1].kind != .number && tokens[i+1].kind != .comment { newline(0) }
    }
    if !current.isEmpty { lines.append(current) }
    let newlineStyle = source.contains("\r\n") ? "\r\n" : "\n"
    let result = lines.joined(separator: newlineStyle)
    return preservesSQLTokens(source,formatted:result) ? result : source
  }
  /// Also validate the full document when formatting only a selected fragment:
  /// a selection may start inside a literal, comment, identifier or GO line.
  public static func preservesSQLTokens(_ source: String, formatted result: String) -> Bool {
    guard source.utf16.count <= 250_000, result.utf16.count <= 500_000 else { return false }
    let tokens = TSQL.lex(source).filter { $0.kind != .space }
    let formatted = TSQL.lex(result).filter { $0.kind != .space }
    let ns = source as NSString
    return tokens.count == formatted.count && tokens.indices.allSatisfy { index in
      let original=tokens[index], changed=formatted[index]
      if original.kind == .keyword && !isIdentifier(tokens,index:index,source:ns) {
        return original.text.caseInsensitiveCompare(changed.text) == .orderedSame
      }
      return original.text == changed.text
    } && batchLines(source) == batchLines(result)
  }
  private static func isIdentifier(_ tokens: [Lexeme], index: Int, source: NSString) -> Bool {
    let token=tokens[index], word=token.text.uppercased()
    let previous=index > 0 ? tokens[index-1].text.uppercased():""
    let next=index+1 < tokens.count ? tokens[index+1].text.uppercased():""
    if previous == "." || next == "." { return true }
    // These palette words are not SQL Server reserved identifiers. Without a
    // full parser, preserve ambiguous names rather than change their meaning.
    // https://learn.microsoft.com/sql/t-sql/language-elements/reserved-keywords-transact-sql
    switch word {
    case "TRY", "CATCH": return !["BEGIN","END"].contains(previous)
    case "APPLY": return !["CROSS","OUTER"].contains(previous)
    case "PARTITION": return next != "BY"
    case "NEXT": return previous != "FETCH"
    case "OFFSET", "ROWS", "ONLY", "OUTPUT", "INCLUDE": return true
    default: break
    }
    // GO is a client separator only on its own physical line. In SQL it may be
    // a case-sensitive identifier, including AS Go / dbo.Go / SELECT 1 Go.
    if word == "GO" { return !SQLRoutineDefinition.isBatchSeparator(token,source:source) }
    if previous == "AS" { return !["BEGIN","SELECT","WITH","RETURN","EXTERNAL"].contains(word) }
    if ["FROM","JOIN","INTO","UPDATE","TABLE","VIEW","PROCEDURE","FUNCTION","EXEC","EXECUTE"].contains(previous),
       !["TOP","SELECT","WITH"].contains(word) { return true }
    if index > 0, !clauseWords.contains(word), [",","FROM","WHERE","GROUP","ORDER",";", ""].contains(next) {
      let prior=tokens[index-1]
      return [.word,.number,.string,.variable].contains(prior.kind) || previous == ")"
    }
    return false
  }
  private static func batchLines(_ source: String) -> [String] {
    let ns = source as NSString
    return TSQL.lex(source).filter { SQLRoutineDefinition.isBatchSeparator($0,source:ns) }.map { token in
      ns.substring(with: ns.lineRange(for:token.range)).trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
    }
  }
}
