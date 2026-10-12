import Testing
import SQLServerKit

struct QuoteEditingTests {
  @Test func quotePairingUsesSQLLexicalContextAndBounds() {
    for source in ["", "SELECT ", "SELECT N", "SELECT 'done'", "/* closed */", "-- done\n", "SELECT [Name]", "SELECT \"Name\"", "/* outer /* inner */ closed */"] {
      #expect(TSQL.allowsQuotePair(in:source,at:source.utf16.count),"Source: \(source)")
    }
    for source in ["-- comment", "/* comment", "/* outer /* inner */", "SELECT '", "SELECT N'", "SELECT 'O''", "SELECT \"", "SELECT [", "SELECT [escaped]]"] {
      #expect(!TSQL.allowsQuotePair(in:source,at:source.utf16.count),"Source: \(source)")
    }
    for source in ["SELECT 'O''Brien'", "SELECT \"a\"\"b\"", "SELECT [a]]b]", "-- test\nSELECT 1", "/* test */ SELECT 1"] {
      #expect(!TSQL.allowsQuotePair(in:source,at:source.hasPrefix("SELECT") ? 10:3))
    }
    #expect(!TSQL.allowsQuotePair(in:"SELECT",at:-1))
    #expect(!TSQL.allowsQuotePair(in:"SELECT",at:7))
    #expect(!TSQL.allowsQuotePair(in:String(repeating:" ",count:250001),at:250001))
  }
}
