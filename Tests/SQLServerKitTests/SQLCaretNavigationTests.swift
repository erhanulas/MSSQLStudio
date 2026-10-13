import Foundation
import SQLServerKit
import Testing

struct SQLCaretNavigationTests {
  private func offset(_ text: String, _ fragment: String, end: Bool = false) -> Int {
    let range = (text as NSString).range(of: fragment)
    precondition(range.location != NSNotFound)
    return end ? NSMaxRange(range) : range.location
  }

  private func assertStops(_ text: String, _ tokens: [String]) {
    let source = text as NSString
    var after = 0
    for token in tokens {
      let range = source.range(of: token, range: NSRange(location: after, length: source.length - after))
      #expect(range.location != NSNotFound)
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: after, direction: .forward) == NSMaxRange(range), Comment(rawValue: "Forward stop: \(token)"))
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: NSMaxRange(range), direction: .backward) == range.location, Comment(rawValue: "Backward stop: \(token)"))
      after = NSMaxRange(range)
    }
    #expect(SQLCaretNavigation.wordBoundary(in: text, from: after, direction: .forward) == source.length)
    var before = source.length
    for token in tokens.reversed() {
      let range = source.range(of: token, options: .backwards, range: NSRange(location: 0, length: before))
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: before, direction: .backward) == range.location, Comment(rawValue: "Reverse stop: \(token)"))
      before = range.location
    }
    #expect(SQLCaretNavigation.wordBoundary(in: text, from: before, direction: .backward) == 0)
  }

  @Test func variablesAndTemporaryTablesStayWholeWhilePunctuationRemainsReachable() {
    assertStops("  SELECT @PARAM, @@SPID FROM #Temp_Table JOIN ##Global ON t.Id=@PARAM;  ",
      ["SELECT", "@PARAM", ",", "@@SPID", "FROM", "#Temp_Table", "JOIN", "##Global", "ON", "t", ".", "Id", "=", "@PARAM", ";"])
    let text = "SELECT @PARAM"
    for position in offset(text, "@PARAM")..<offset(text, "@PARAM", end: true) {
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: position, direction: .forward) == (text as NSString).length)
      if position > offset(text, "@PARAM") {
        #expect(SQLCaretNavigation.wordBoundary(in: text, from: position, direction: .backward) == offset(text, "@PARAM"))
      }
    }
  }

  @Test func compoundOperatorsAreStopsAndIndependentOperatorsAreNotSkipped() {
    assertStops("a<=b >=c<>d !=e !<f !>g +=h -=i *=j /=k %=l &=m ^=n |=o + - * / % & ^ | = < > ++ (x),y;",
      ["a", "<=", "b", ">=", "c", "<>", "d", "!=", "e", "!<", "f", "!>", "g", "+=", "h", "-=", "i", "*=", "j", "/=", "k", "%=", "l", "&=", "m", "^=", "n", "|=", "o", "+", "-", "*", "/", "%", "&", "^", "|", "=", "<", ">", "+", "+", "(", "x", ")", ",", "y", ";"])
  }

  @Test func decimalExponentAndBinaryLiteralsRemainUsefulWordStops() {
    assertStops("@n=-0.12500000+1.25e-10/.5; 12. 0xAB10 1e+2 1e-3 1e+ foo.bar",
      ["@n", "=", "-", "0.12500000", "+", "1.25e-10", "/", ".5", ";", "12.", "0xAB10", "1e+2", "1e-3", "1", "e", "+", "foo", ".", "bar"])
  }

  @Test func quotedNamesStringsAndCommentsRetainWordwiseMovement() {
    assertStops("[Order Detail].[Id] = N'hello world''s' -- useful comment\n/* multi line */ \"Quoted Name\"",
      ["[", "Order", "Detail", "]", ".", "[", "Id", "]", "=", "N", "'", "hello", "world", "''", "s", "'", "--", "useful", "comment", "/*", "multi", "line", "*/", "\"", "Quoted", "Name", "\""])
    assertStops("[escaped]]name]", ["[", "escaped", "]]", "name", "]"])
  }

  @Test func unicodeDestinationsNeverSplitSurrogatesOrComposedCharacters() {
    let text = "  @cafe\u{0301}_東京 = 👨‍👩‍👧‍👦 + 🇹🇷;  "
    assertStops(text, ["@cafe\u{0301}_東京", "=", "👨‍👩‍👧‍👦", "+", "🇹🇷", ";"])
    let source = text as NSString
    var legal: Set<Int> = [0]
    var position = 0
    for character in text { position += String(character).utf16.count; legal.insert(position) }
    for input in -2...(source.length + 2) {
      for direction in [SQLCaretNavigation.Direction.backward, .forward] {
        #expect(legal.contains(SQLCaretNavigation.wordBoundary(in: text, from: input, direction: direction)))
        #expect(legal.contains(SQLCaretNavigation.lineBoundary(in: text, from: input, direction: direction)))
      }
    }
  }

  @Test func smartLineEdgesRespectIndentationTrailingSpacesAndCRLF() {
    let text = "previous\r\n\t  SELECT @PARAM; \t \r\nnext"
    let lineStart = offset(text, "\t  SELECT")
    let codeStart = offset(text, "SELECT")
    let codeEnd = offset(text, ";", end: true)
    let physicalEnd = offset(text, "\r\nnext")
    #expect(SQLCaretNavigation.lineBoundary(in: text, from: codeEnd, direction: .backward) == codeStart)
    #expect(SQLCaretNavigation.lineBoundary(in: text, from: codeStart, direction: .backward) == lineStart)
    #expect(SQLCaretNavigation.lineBoundary(in: text, from: lineStart + 1, direction: .backward) == lineStart)
    #expect(SQLCaretNavigation.lineBoundary(in: text, from: codeStart, direction: .forward) == codeEnd)
    #expect(SQLCaretNavigation.lineBoundary(in: text, from: codeEnd, direction: .forward) == physicalEnd)
    #expect(SQLCaretNavigation.lineBoundary(in: text, from: physicalEnd, direction: .forward) == physicalEnd)
    #expect(SQLCaretNavigation.lineBoundary(in: text, from: physicalEnd + 1, direction: .forward) == physicalEnd)
    #expect(SQLCaretNavigation.wordBoundary(in: text, from: physicalEnd, direction: .forward) == (text as NSString).length)
    #expect(SQLCaretNavigation.wordBoundary(in: text, from: lineStart, direction: .backward) == 0)
  }

  @Test func emptyWhitespaceAndOutOfRangeInputsClampWithoutMutation() {
    for text in ["", " \t ", "\r\n", "\n\t \r\n"] {
      let length = (text as NSString).length
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: -100, direction: .backward) == 0)
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: length + 100, direction: .forward) == length)
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: 0, direction: .forward) == length)
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: length, direction: .backward) == 0)
    }
    #expect(SQLCaretNavigation.lineBoundary(in: " \t ", from: 1, direction: .backward) == 0)
    #expect(SQLCaretNavigation.lineBoundary(in: " \t ", from: 1, direction: .forward) == 3)
    #expect(SQLCaretNavigation.lineBoundary(in: "abc\n", from: 10, direction: .backward) == 4)
    #expect(SQLCaretNavigation.lineBoundary(in: "abc\n", from: -10, direction: .forward) == 3)
  }

  @Test func navigationInLargeSourcesDependsOnTheLocalLine() {
    let text = String(repeating: "SELECT @earlier FROM dbo.Previous;\r\n", count: 50_000)
      + "\t SELECT @PARAM>=1.25e-10;  \r\n"
      + String(repeating: "SELECT @later FROM dbo.Next;\n", count: 50_000)
    let variable = offset(text, "@PARAM")
    #expect(SQLCaretNavigation.wordBoundary(in: text, from: variable + 2, direction: .backward) == variable)
    #expect(SQLCaretNavigation.wordBoundary(in: text, from: variable + 2, direction: .forward) == variable + 6)
    #expect(SQLCaretNavigation.wordBoundary(in: text, from: variable + 6, direction: .forward) == variable + 8)
    #expect(SQLCaretNavigation.lineBoundary(in: text, from: variable, direction: .backward) == variable - 7)
  }

  @Test func megabyteSingleLinesUseBoundedWindowsInsteadOfWholeLineTokenArrays() {
    let padding = String(repeating: "x", count: 524_288)
    let text = padding + " @PARAM>=@OTHER + 1.25e-10; " + padding
    let variable = offset(text, "@PARAM")
    for _ in 0..<12 {
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: variable + 2, direction: .backward) == variable)
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: variable + 2, direction: .forward) == variable + 6)
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: variable + 6, direction: .forward) == variable + 8)
      #expect(SQLCaretNavigation.wordBoundary(in: text, from: variable + 7, direction: .backward) == variable + 6)
    }
    // Invalid, generated megabyte-long identifiers deliberately use intermediate
    // stops; this also proves that work is bounded, without a fragile time limit.
    let enormousToken = String(repeating: "a", count: 1_048_576)
    let middle = enormousToken.utf16.count / 2
    let left = SQLCaretNavigation.wordBoundary(in: enormousToken, from: middle, direction: .backward)
    let right = SQLCaretNavigation.wordBoundary(in: enormousToken, from: middle, direction: .forward)
    #expect((1...4_097).contains(middle - left))
    #expect((1...4_097).contains(right - middle))
  }

  @Test func boundedWindowEdgesAndDecoratedWhitespaceNeverSplitGraphemes() {
    let text = String(repeating: "a\u{0301}", count: 6_000)
    for input in [5_001, 8_193] {
      let left = SQLCaretNavigation.wordBoundary(in: text, from: input, direction: .backward)
      let right = SQLCaretNavigation.wordBoundary(in: text, from: input, direction: .forward)
      #expect(left % 2 == 0 && right % 2 == 0)
      #expect((1...4_098).contains(input - left))
      #expect((1...4_098).contains(right - input))
    }
    let decorated = "\t \u{0301} @PARAM \t"
    #expect(SQLCaretNavigation.lineBoundary(in: decorated, from: 7, direction: .backward) == 1)
    #expect(SQLCaretNavigation.wordBoundary(in: decorated, from: 0, direction: .forward) == 3)
    #expect(SQLCaretNavigation.wordBoundary(in: decorated, from: 3, direction: .backward) == 1)
    let emoji = String(repeating: "a", count: 4_094) + "👨‍👩‍👧‍👦" + String(repeating: "b", count: 4_200)
    #expect(SQLCaretNavigation.wordBoundary(in: emoji, from: 0, direction: .forward) == 4_094)
    #expect(SQLCaretNavigation.wordBoundary(in: emoji, from: 4_094, direction: .forward) == 4_105)
  }
}
