import Foundation
import Testing
@testable import SQLServerKit

struct RoutineParameterHelpTests {
  let catalog=SQLIntelligence.Catalog(snapshot:.init(symbols:[
    CatalogSymbol(schema:"dbo",name:"Sample",columns:[],kind:"SQL_STORED_PROCEDURE"),
    CatalogSymbol(schema:"dbo",name:"Fn",columns:[],kind:"SQL_SCALAR_FUNCTION"),
    CatalogSymbol(schema:"other",name:"Sample",columns:[],kind:"SQL_STORED_PROCEDURE"),
    CatalogSymbol(schema:"dbo",name:"Table",columns:[])]))
  func context(_ sql:String)->SQLRoutineCall? {SQLRoutineCall.context(source:sql,caret:sql.utf16.count,catalog:catalog)}
  @Test func execReturnValuesQualifiedNamesAndNamedArguments() throws {
    let params=[RoutineParameter(id:1,name:"@First",type:"int"),RoutineParameter(id:2,name:"@Other",type:"decimal(28,8)",output:true)]
    #expect(try #require(context("EXEC dbo.Sample")).activeIndex(in:params) == 0)
    #expect(try #require(context("EXECUTE @r = [other].[Sample] 12, ")).activeIndex(in:params) == 1)
    #expect(try #require(context("EXEC Sample @Other = 'a,b BEGIN END 😀'")).activeIndex(in:params) == 1)
    #expect(try #require(context("EXEC Sample 12, @First = 3")).activeIndex(in:params) == 0)
    #expect(try #require(context("EXEC Sample 1, 2, 3")).activeIndex(in:params) == nil)
    #expect(try #require(context("EXEC Sample @Missing = 3")).activeIndex(in:params) == nil)
    #expect(context("EXEC dbo.Fn 1,")?.ordinal == 1)
  }
  @Test func nestedFunctionArgumentsAndCallBoundaries() {
    #expect(context("SELECT dbo.Fn(COALESCE(1, 2), ")?.ordinal == 1)
    #expect(context("SELECT dbo.Fn(1, dbo.Fn(")?.ordinal == 0)
    #expect(context("SELECT dbo.Fn(1, dbo.Fn(2), ")?.ordinal == 2)
    #expect(context("EXEC Sample 'a,b', /* , */ ")?.ordinal == 1)
    for sql in ["EXEC @dynamic ","EXEC('text')","EXEC otherdb.dbo.Sample ","EXEC Sample; SELECT 1", "EXEC Sample\nSELECT 2", "EXEC Sample\nGO\n", "SELECT dbo.Fn(1);", "-- EXEC Sample", "EXEC Table", "SELECT 'dbo.Fn('", "EXEC Sample /* comment"] {
      #expect(context(sql) == nil,"Unexpected context: \(sql)")
    }
    #expect(context(String(repeating:" ",count:100_001)+"EXEC Sample") == nil)
  }
  @Test func caseAndParenthesesPairWithoutAffectingLiteralOrIdentifierContent() {
    let sql="BEGIN SELECT CASE WHEN (1+(2))=3 THEN '(END)' ELSE [END] END; END"
    let source=sql as NSString,caseRange=source.range(of:"CASE"),caseEnd=source.range(of:"END;")
    #expect(TSQL.matchingBlock(in:sql,at:caseRange.location) == [caseRange,NSRange(location:caseEnd.location,length:3)])
    let open=source.range(of:"(2)").location
    #expect(TSQL.matchingBlock(in:sql,at:open) == [NSRange(location:open,length:1),NSRange(location:open+2,length:1)])
    #expect(TSQL.matchingBlock(in:sql,at:source.range(of:"'(END)'").location+2).isEmpty)
    #expect(TSQL.matchingBlock(in:"SELECT (1\nGO\n)",at:7).isEmpty)
  }
}
