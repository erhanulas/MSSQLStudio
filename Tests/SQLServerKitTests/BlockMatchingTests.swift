import Foundation
import Testing
@testable import SQLServerKit

struct BlockMatchingTests {
  @Test func nestedBlocksCaseTransactionsAndLexicalExclusions() {
    let sql="-- BEGIN END\nSELECT N'😀 BEGIN END', [BEGIN]; BEGIN TRANSACTION; BEGIN /* BEGIN */ SELECT CASE WHEN 1=1 THEN CASE WHEN 2=2 THEN 3 END END; BEGIN TRY SELECT 1; END TRY BEGIN CATCH SELECT 2; END CATCH END; END CONVERSATION @h;"
    let tokens=TSQL.lex(sql).filter {$0.kind == .keyword}
    let outer=tokens.first {$0.text == "BEGIN" && $0.range.location > (sql as NSString).range(of:"TRANSACTION").location}!
    let last=tokens.last {$0.text == "END" && $0.range.location < (sql as NSString).range(of:"END CONVERSATION").location}!
    let expected=[outer.range,last.range]
    #expect(TSQL.matchingBlock(in:sql,at:outer.range.location+2) == expected)
    #expect(TSQL.matchingBlock(in:sql,at:last.range.location+1) == expected)
    for text in ["-- BEGIN", "😀 BEGIN", "[BEGIN]", "BEGIN TRANSACTION", "END CONVERSATION"] {
      let location=(sql as NSString).range(of:text).location + (text == "😀 BEGIN" ? 3 : text.hasPrefix("--") ? 3 : text.hasPrefix("[") ? 1:0)
      #expect(TSQL.matchingBlock(in:sql,at:location).isEmpty)
    }
    let beginTry=(sql as NSString).range(of:"BEGIN TRY").location,endTry=(sql as NSString).range(of:"END TRY").location
    #expect(TSQL.matchingBlock(in:sql,at:beginTry) == [NSRange(location:beginTry,length:5),NSRange(location:endTry,length:3)])
  }
  @Test func unmatchedBatchBoundaryAndBudget() {
    for sql in ["BEGIN SELECT 1", "END", "BEGIN\nGO\nEND", "BEGIN DISTRIBUTED TRANSACTION; END", "BEGIN DIALOG CONVERSATION @h; END CONVERSATION @h;"] {
      #expect(TSQL.matchingBlock(in:sql,at:0).isEmpty)
    }
    #expect(TSQL.matchingBlock(in:String(repeating:" ",count:250_001)+"BEGIN END",at:250_001).isEmpty)
    #expect(TSQL.matchingBlock(in:"BEGIN END",at:-1).isEmpty)
    #expect(TSQL.matchingBlock(in:"BEGIN END",at:9) == [NSRange(location:0,length:5),NSRange(location:6,length:3)])
    #expect(TSQL.matchingBlock(in:"BEGIN  END",at:6).isEmpty)
  }
}
