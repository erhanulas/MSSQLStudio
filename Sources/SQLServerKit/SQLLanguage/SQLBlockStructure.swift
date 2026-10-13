import Foundation

/// One bounded lexical snapshot shared by delimiter navigation and block guides.
public struct SQLBlockStructure: Sendable {
  public struct Pair: Equatable, Sendable {
    public enum Kind: Sendable { case block, caseExpression, parenthesis }
    public let opening: NSRange
    public let closing: NSRange
    public let kind: Kind
  }
  public let pairs: [Pair]
  private let length: Int

  public init(_ source: String) {
    length = source.utf16.count
    guard length <= 250_000 else { pairs = []; return }
    let tokens = TSQL.lex(source).filter { $0.kind != .space && $0.kind != .comment }
    var blocks: [(NSRange, Pair.Kind)] = []
    var parentheses: [NSRange] = []
    var found: [Pair] = []
    for (index, token) in tokens.enumerated() {
      if token.kind == .symbol {
        if token.text == "(" { parentheses.append(token.range) }
        if token.text == ")", let opening = parentheses.popLast() {
          found.append(Pair(opening: opening, closing: token.range, kind: .parenthesis))
        }
      }
      guard token.kind == .keyword else { continue }
      let next = index + 1 < tokens.count ? tokens[index + 1].text.uppercased() : ""
      switch token.text.uppercased() {
      case "GO": blocks.removeAll(); parentheses.removeAll()
      case "CASE": blocks.append((token.range, .caseExpression))
      case "BEGIN":
        if !["TRAN", "TRANSACTION", "DISTRIBUTED", "DIALOG", "CONVERSATION"].contains(next) {
          blocks.append((token.range, .block))
        }
      case "END":
        if next != "CONVERSATION", let opening = blocks.popLast() {
          found.append(Pair(opening: opening.0, closing: token.range, kind: opening.1))
        }
      default: break
      }
    }
    pairs = found.sorted { $0.opening.location < $1.opening.location }
  }

  public func matchingPair(at caret: Int) -> [NSRange] {
    guard (0...length).contains(caret) else { return [] }
    var preceding: Pair?
    var precedingLocation = -1
    for pair in pairs {
      for range in [pair.opening, pair.closing] {
        // Prefer the delimiter after the caret at adjacent parentheses.
        if NSLocationInRange(caret, range) { return [pair.opening, pair.closing] }
        if NSMaxRange(range) == caret, range.location > precedingLocation {
          preceding = pair; precedingLocation = range.location
        }
      }
    }
    return preceding.map { [$0.opening, $0.closing] } ?? []
  }
}
