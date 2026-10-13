import Foundation

/// SQL-aware caret destinations expressed in the UTF-16 offsets used by AppKit.
/// Word navigation scans a small composed-character-aligned window around the
/// caret. Exceptionally long tokens have intermediate stops at the window edge;
/// a generated single-line statement must not allocate a document-sized lexer.
public enum SQLCaretNavigation {
  public enum Direction: Sendable { case backward, forward }
  private static let wordWindowRadius = 4_096
  private static let nonWhitespace = CharacterSet.whitespacesAndNewlines.inverted
  private static let nonIndentation = CharacterSet(charactersIn: " \t").inverted

  public static func wordBoundary(in text: String, from offset: Int, direction: Direction) -> Int {
    let source = text as NSString
    let position = max(0, min(offset, source.length))
    let candidate: Int
    switch direction {
    case .forward:
      guard position < source.length else { return source.length }
      let next = source.rangeOfCharacter(from: nonWhitespace,
        range: NSRange(location: position, length: source.length - position))
      guard next.location != NSNotFound else { return source.length }
      candidate = next.location
    case .backward:
      guard position > 0 else { return 0 }
      let previous = source.rangeOfCharacter(from: nonWhitespace, options: .backwards,
        range: NSRange(location: 0, length: position))
      guard previous.location != NSNotFound else { return 0 }
      candidate = NSMaxRange(previous) - 1
    }

    let window = wordWindow(in: source, at: candidate)
    for range in tokens(in: source.substring(with: window), startingAt: window.location) {
      if NSLocationInRange(candidate, range) {
        return direction == .forward ? NSMaxRange(range) : range.location
      }
    }
    // Every non-whitespace grapheme has a token. Keep a safe destination even
    // if Foundation encounters an unusual line separator at the caret.
    let range = source.rangeOfComposedCharacterSequence(at: candidate)
    return direction == .forward ? NSMaxRange(range) : range.location
  }

  /// Smart Home/End: stop at the visible code before the physical line edge.
  /// Repeating at that destination then includes indentation/trailing spaces.
  public static func lineBoundary(in text: String, from offset: Int, direction: Direction) -> Int {
    let source = text as NSString
    let position = max(0, min(offset, source.length))
    let line = lineRange(in: source, at: position)
    let physicalEnd = NSMaxRange(line)
    let first = source.rangeOfCharacter(from: nonIndentation, range: line)
    guard first.location != NSNotFound else { return direction == .backward ? line.location : physicalEnd }
    let last = source.rangeOfCharacter(from: nonIndentation, options: .backwards, range: line)
    let codeStart = source.rangeOfComposedCharacterSequence(at: first.location).location
    let codeEnd = NSMaxRange(source.rangeOfComposedCharacterSequence(at: last.location))
    switch direction {
    case .backward: return position > codeStart ? codeStart : line.location
    case .forward: return position < codeEnd ? codeEnd : physicalEnd
    }
  }

  private static func lineRange(in source: NSString, at position: Int) -> NSRange {
    var start = 0
    var contentEnd = 0
    source.getLineStart(&start, end: nil, contentsEnd: &contentEnd,
      for: NSRange(location: position, length: 0))
    return NSRange(location: start, length: contentEnd - start)
  }

  private static func wordWindow(in source: NSString, at candidate: Int) -> NSRange {
    let rawStart = max(0, candidate - wordWindowRadius)
    let rawEnd = min(source.length, candidate + wordWindowRadius + 1)
    let composed = source.rangeOfComposedCharacterSequences(
      for: NSRange(location: rawStart, length: rawEnd - rawStart))
    var start = composed.location
    var end = NSMaxRange(composed)
    let previousBreak = source.rangeOfCharacter(from: .newlines, options: .backwards,
      range: NSRange(location: start, length: candidate - start))
    if previousBreak.location != NSNotFound {
      start = NSMaxRange(source.rangeOfComposedCharacterSequence(at: previousBreak.location))
    }
    let nextBreak = source.rangeOfCharacter(from: .newlines,
      range: NSRange(location: candidate, length: end - candidate))
    if nextBreak.location != NSNotFound {
      end = source.rangeOfComposedCharacterSequence(at: nextBreak.location).location
    }
    return NSRange(location: start, length: end - start)
  }

  private struct Glyph {
    let text: String
    let range: NSRange
    var isWord: Bool {
      text == "_" || text.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
      }
    }
    var isDigit: Bool { text.utf8.count == 1 && ("0"..."9").contains(text) }
    var isHexDigit: Bool {
      isDigit || text.utf8.count == 1 && ("a"..."f").contains(text.lowercased())
    }
    var isWhitespace: Bool { text.allSatisfy(\.isWhitespace) }
  }

  private static let pairedStops: Set<String> = [
    "<=", ">=", "<>", "!=", "!<", "!>", "+=", "-=", "*=", "/=", "%=", "&=", "^=", "|=",
    "--", "/*", "*/", "''", "\"\"", "]]",
  ]

  private static func tokens(in line: String, startingAt start: Int) -> [NSRange] {
    var glyphs: [Glyph] = []
    glyphs.reserveCapacity(min(line.utf8.count, 4_096))
    var location = start
    for character in line {
      let text = String(character)
      let range = NSRange(location: location, length: text.utf16.count)
      glyphs.append(Glyph(text: text, range: range))
      location = NSMaxRange(range)
    }
    var result: [NSRange] = []
    var index = 0
    while index < glyphs.count {
      if glyphs[index].isWhitespace { index += 1; continue }
      let begin = index
      if glyphs[index].isDigit || glyphs[index].text == "." && index + 1 < glyphs.count && glyphs[index + 1].isDigit {
        index = numberEnd(in: glyphs, from: index)
      } else if glyphs[index].text == "@" || glyphs[index].text == "#" {
        let prefix = glyphs[index].text
        index += 1
        if index < glyphs.count, glyphs[index].text == prefix { index += 1 }
        while index < glyphs.count, glyphs[index].isWord { index += 1 }
      } else if glyphs[index].isWord {
        index += 1
        while index < glyphs.count, glyphs[index].isWord { index += 1 }
      } else if index + 1 < glyphs.count, pairedStops.contains(glyphs[index].text + glyphs[index + 1].text) {
        index += 2
      } else {
        index += 1
      }
      let end = NSMaxRange(glyphs[index - 1].range)
      result.append(NSRange(location: glyphs[begin].range.location, length: end - glyphs[begin].range.location))
    }
    return result
  }

  private static func numberEnd(in glyphs: [Glyph], from start: Int) -> Int {
    if glyphs[start].text == "0", start + 2 < glyphs.count,
       glyphs[start + 1].text.lowercased() == "x", glyphs[start + 2].isHexDigit {
      var index = start + 3
      while index < glyphs.count, glyphs[index].isHexDigit { index += 1 }
      return index
    }
    var index = start
    while index < glyphs.count, glyphs[index].isDigit { index += 1 }
    if index < glyphs.count, glyphs[index].text == "." {
      index += 1
      while index < glyphs.count, glyphs[index].isDigit { index += 1 }
    }
    if index < glyphs.count, glyphs[index].text.lowercased() == "e" {
      var exponent = index + 1
      if exponent < glyphs.count, glyphs[exponent].text == "+" || glyphs[exponent].text == "-" { exponent += 1 }
      let digits = exponent
      while exponent < glyphs.count, glyphs[exponent].isDigit { exponent += 1 }
      if exponent > digits { index = exponent }
    }
    return index
  }
}
