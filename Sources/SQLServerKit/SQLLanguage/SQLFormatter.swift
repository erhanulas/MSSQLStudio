import Foundation

public struct SQLFormattingOptions: Codable, Equatable, Sendable {
  public enum KeywordCase: String, Codable, CaseIterable, Sendable { case upper, lower, preserve }
  public enum CommaStyle: String, Codable, CaseIterable, Sendable { case trailing, leading }
  public var indentWidth: Int
  public var keywordCase: KeywordCase
  public var commaStyle: CommaStyle
  public var multilineLists: Bool
  public var breakConditions: Bool
  public init(indentWidth: Int = 4, keywordCase: KeywordCase = .upper,
              commaStyle: CommaStyle = .trailing, multilineLists: Bool = true, breakConditions: Bool = true) {
    self.indentWidth = max(2, min(8, indentWidth)); self.keywordCase = keywordCase
    self.commaStyle = commaStyle; self.multilineLists = multilineLists; self.breakConditions = breakConditions
  }
}

/// Whitespace/case-only T-SQL formatting. No alias, comma, comment or statement
/// token is inserted/removed. A lexical equivalence check rejects unsafe output.
public enum SQLFormatter {
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
    var frames = [Frame(query: true)], blockIndent = 0, caseIndent = 0
    var caseBases: [Int] = []
    var lines: [String] = [], current = "", pendingIndent = 0, between = false
    let width = max(2, min(8, options.indentWidth))
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
    for i in tokens.indices {
      let token = tokens[i], upper = token.text.uppercased()
      let previous = i > 0 ? tokens[i-1].text.uppercased() : ""
      let next = i+1 < tokens.count ? tokens[i+1].text.uppercased() : ""
      let qualified = previous == "." || next == "."
      let keyword = token.kind == .keyword && !qualified
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
      let isBlockEnd = keyword && upper == "END"
      if isBlockEnd {
        if let base = caseBases.popLast() { caseIndent -= 1; newline(base) }
        else { blockIndent = max(0,blockIndent-1); newline() }
      }
      if keyword && upper == "CASE" { caseBases.append(max(pendingIndent,blockIndent + frames[frameIndex].indent)); caseIndent += 1 }
      if keyword && ["WHEN","ELSE"].contains(upper), caseIndent > 0 { newline((caseBases.last ?? 0) + 1) }
      if keyword && queryLevel && caseIndent == 0 {
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
        let list = options.multilineLists && ["INTO","INSERT","VALUES"].contains(frames[frameIndex].clause)
        let base = frames[frameIndex].indent
        frames.append(Frame(clause: frames[frameIndex].clause, query: query, list: list, indent: base + (query || list ? 1 : 0)))
        if query || list { newline() }
      }
      if multilineComma && options.commaStyle == .trailing { newline(blockIndent + frames[frameIndex].indent + 1) }
      if keyword && upper == "BEGIN" && !["TRAN","TRANSACTION","DISTRIBUTED","DIALOG","CONVERSATION"].contains(next) {
        blockIndent += 1; newline()
      }
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
    return tokens.count == formatted.count && zip(tokens,formatted).allSatisfy { original, changed in
      if original.kind == .keyword { return original.text.caseInsensitiveCompare(changed.text) == .orderedSame }
      return original.text == changed.text
    } && batchLines(source) == batchLines(result)
  }
  private static func batchLines(_ source: String) -> [String] {
    let ns = source as NSString
    return TSQL.lex(source).filter { SQLRoutineDefinition.isBatchSeparator($0,source:ns) }.map { token in
      ns.substring(with: ns.lineRange(for:token.range)).trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
    }
  }
}
