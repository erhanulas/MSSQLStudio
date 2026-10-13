import Foundation
import Testing
import SQLTextCore

struct SQLWhitespaceComparisonTests {
  @Test func externalWhitespaceAndCommentPaddingAreIgnored() {
    let a="SELECT\n    C.STHAR_GCMIK AS OrderQuantity, -- Siparis Miktari      \n    A.STHAR_GCMIK AS InvoiceQuantity -- Fatura  Miktari      \nFROM dbo.T AS A;\n"
    let b="\t SELECT\r\n C.STHAR_GCMIK\tAS\tOrderQuantity,    -- Siparis Miktari        \r\n\r\nA.STHAR_GCMIK AS InvoiceQuantity  -- Fatura  Miktari\t \r\nFROM dbo . T AS A ;"
    #expect(SQLWhitespaceComparison.key(a)==SQLWhitespaceComparison.key(b))
    #expect(SQLWhitespaceComparison.key("SELECT(a*- 1),.25,1.2e-3,0xAB;")==SQLWhitespaceComparison.key("SELECT ( a * -1 ) , .25 , 1.2e-3 , 0xAB ;"))
    #expect(SQLWhitespaceComparison.key("SELECT 1; -- final")==SQLWhitespaceComparison.key("SELECT 1; -- final  \r\n"))
    #expect(SQLWhitespaceComparison.key("SELECT /* outer\r\n/* nested\rtail */\r\nend */ 1;")==SQLWhitespaceComparison.key("SELECT /* outer\n/* nested\ntail */\nend */ 1;"))
  }

  @Test func literalIdentifierAndCommentContentRemainsExact() {
    for (a,b) in [
      ("SELECT N'a  b';","SELECT N'a b';"),
      ("SELECT 'a\r\nb';","SELECT 'a\nb';"),
      ("SELECT [a  b];","SELECT [a b];"),
      ("SELECT [a\r\nb];","SELECT [a\nb];"),
      ("SELECT \"a  b\";","SELECT \"a b\";"),
      ("SELECT \"a\r\nb\";","SELECT \"a\nb\";"),
      ("SELECT 1; -- alpha  beta\nSELECT 2;","SELECT 1; -- alpha beta\nSELECT 2;"),
      ("SELECT 1; /* alpha  beta */","SELECT 1; /* alpha beta */"),
      ("SELECT /* outer /* nested  text */ tail */ 1;","SELECT /* outer /* nested text */ tail */ 1;"),
      ("SELECT 1; -- note\nSELECT 2;","SELECT 1; -- note SELECT 2;"),
      ("SELECT N'é';","SELECT N'e\u{301}';")
    ] {
      #expect(!SQLWhitespaceComparison.key(a).utf8.elementsEqual(SQLWhitespaceComparison.key(b).utf8))
    }
    #expect(SQLWhitespaceComparison.key("SELECT N'it''s  [x]',[a]]b],\"a\"\"b\";")==SQLWhitespaceComparison.key(" SELECT\tN'it''s  [x]' , [a]]b] , \"a\"\"b\" ;"))
  }

  @Test func tokenBoundariesAndNumericOperatorsCannotCollapse() {
    for (a,b) in [
      ("SELECT a>=b;","SELECT a> =b;"),
      ("SELECT a!=b;","SELECT a! =b;"),
      ("SELECT a!<b;","SELECT a! <b;"),
      ("SELECT a<>b;","SELECT a< >b;"),
      ("SELECT a+=b;","SELECT a+ =b;"),
      ("SELECT a::b;","SELECT a: :b;"),
      ("SELECT 1.2;","SELECT 1 . 2;"),
      ("SELECT .25;","SELECT . 25;"),
      ("SELECT 1e-2;","SELECT 1e - 2;"),
      ("SELECT 1e+2;","SELECT 1e + 2;"),
      ("SELECT 0xAB;","SELECT 0 xAB;"),
      ("SELECT 1abc;","SELECT 1 abc;"),
      ("SELECT N'x';","SELECT N 'x';"),
      ("SELECT @@ROWCOUNT;","SELECT @ @ROWCOUNT;"),
      ("SELECT a--b\n;","SELECT a- -b\n;"),
      ("SELECT a/*b*/c;","SELECT a/ *b* /c;")
    ] {#expect(SQLWhitespaceComparison.key(a) != SQLWhitespaceComparison.key(b))}
  }

  @Test func tokenRangesRetainOriginalUTF16TextAndCommentTerminators() throws {
    let sql="\tSELECT N'🦊  x', [x]]y], \"x\"\"y\" /* nested /*x*/ tail */ -- note\t  \r\nFROM T -- end"
    let source=sql as NSString,tokens=SQLWhitespaceComparison.tokens(in:sql)
    for token in tokens {
      #expect(token.range.location>=0 && NSMaxRange(token.range)<=source.length)
      if token.text=="\n" {
        #expect(token.range.length==0 || source.substring(with:token.range)=="\r\n")
      } else if token.text.hasPrefix("--") {
        #expect(source.substring(with:token.range).hasPrefix(token.text))
      } else {#expect(source.substring(with:token.range)==token.text)}
    }
    #expect(tokens.filter {$0.text=="\n"}.map(\.range.length)==[2,0])
    #expect(tokens.first {$0.text=="N'🦊  x'"}?.range.length==8)
    #expect(tokens.contains {$0.text=="/* nested /*x*/ tail */"})
  }
}
