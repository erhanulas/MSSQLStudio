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
  @Test func routineDefinitionSignaturesAreNotCalls() {
    for prefix in ["CREATE", "ALTER", "CREATE OR ALTER"] {
      for name in ["dbo.Fn", "[dbo].[Fn]", "\"dbo\".\"Fn\""] {
        for parameters in ["(", "(@First int, ", "(@First decimal(28,8), @Second nvarchar(40) = N'AS RETURN (', "] {
          let sql="\(prefix) FUNCTION \(name)\(parameters)"
          #expect(context(sql) == nil, "Definition is not a call: \(sql)")
        }
      }
      for kind in ["PROC", "PROCEDURE"] {
        #expect(context("\(prefix) \(kind) dbo.Sample @First AS int, @Second int = dbo.Fn(") == nil)
      }
    }
    for sql in [
      "ALTER /* declaration */ FUNCTION [dbo].[Fn]\n(\n@First int, -- AS BEGIN\n",
      "CREATE FUNCTION dbo.Fn(@First int) RETURNS @Result TABLE (Value int DEFAULT dbo.Fn(",
      "ALTER FUNCTION dbo.Fn(@First int = N'EXEC Sample') RETURNS TABLE WITH EXECUTE AS OWNER",
      "ALTER FUNCTION dbo.Fn(@First dbo.GO, @Second int, ",
      "ALTER FUNCTION dbo.Fn(@First dbo.GO, @Second int = dbo.Fn(",
      "EXEC Sample 1; ALTER FUNCTION dbo.Fn(@First int, ",
      "ALTER FUNCTION dbo.Fn(@First int = /* AS RETURN */ dbo.Fn("
    ] { #expect(context(sql) == nil, "Unexpected definition help: \(sql)") }
  }
  @Test func callsInsideRoutineBodiesRemainAvailable() {
    let functionBodies=[
      "ALTER FUNCTION dbo.Fn(@First int) RETURNS int AS BEGIN RETURN dbo.Fn(",
      "CREATE OR ALTER FUNCTION [dbo].[Fn](@First int) RETURNS int BEGIN RETURN dbo.Fn(",
      "CREATE FUNCTION dbo.Fn(@First int) RETURNS TABLE AS RETURN (SELECT dbo.Fn(",
      "ALTER FUNCTION dbo.Fn(@First int) RETURNS @Result TABLE (Value int) AS BEGIN INSERT @Result SELECT dbo.Fn("
    ]
    for sql in functionBodies { #expect(context(sql)?.symbol.name == "Fn", "Body call missing: \(sql)") }
    #expect(context("ALTER PROCEDURE dbo.Sample @First AS int, @Second int WITH EXECUTE AS OWNER AS BEGIN EXEC dbo.Sample ")?.symbol.name == "Sample")
    #expect(context("CREATE OR ALTER PROC dbo.Sample @First int AS SELECT dbo.Fn(1, ")?.ordinal == 1)
    #expect(context("ALTER FUNCTION dbo.Fn(@First int\nGO\nSELECT dbo.Fn(")?.symbol.name == "Fn")
    #expect(context("ALTER FUNCTION dbo.Fn(@First dbo.GO,\nGO 2 -- actual batch separator\nSELECT dbo.Fn(")?.symbol.name == "Fn")
    #expect(context("SELECT dbo.Fn(t.GO, ")?.ordinal == 1)
    #expect(context("SELECT N'ALTER FUNCTION dbo.Fn(', dbo.Fn(")?.symbol.name == "Fn")
    #expect(context("-- ALTER FUNCTION dbo.Fn(\nSELECT dbo.Fn(")?.symbol.name == "Fn")
  }
  @Test func definitionHeaderFindsOnlyFormalParametersAndRecognizesOpaqueBodies() {
    func header(_ sql:String)->SQLRoutineDefinition.Header? {
      SQLRoutineDefinition.headers(in:TSQL.lex(sql).filter {$0.kind != .space && $0.kind != .comment},source:sql).first
    }
    let definitions=[
      "ALTER FUNCTION dbo.Fn(@First AS int, @Second decimal(28,8) = 2) RETURNS @Result TABLE (Value int, Derived AS (Value+1)) AS BEGIN RETURN END",
      "CREATE OR ALTER PROCEDURE [dbo].[Sample];2 @First AS int = 1, @Second dbo.CustomType READONLY WITH EXECUTE AS 'Owner' AS SELECT @First",
      "ALTER PROC dbo.Sample @First dbo.GO, @Second int AS SELECT 1",
      "ALTER PROC dbo.Sample @First GO, @Second int AS SELECT 1",
      "CREATE FUNCTION dbo.Fn(@First int, @Second nvarchar(20) = N'@Fake, AS RETURN') RETURNS int BEGIN RETURN 1 END"
    ]
    for sql in definitions {
      let header=header(sql)
      #expect(header?.parameters.map {(sql as NSString).substring(with:$0)} == ["@First","@Second"])
      #expect(header?.hasSQLBody == true)
    }
    for kind in ["FUNCTION dbo.Fn(@First int) RETURNS int", "PROC dbo.Sample @First int"] {
      let h=header("CREATE \(kind) AS EXTERNAL NAME Assembly.Type.Method")
      #expect(h?.parameters.isEmpty == true && h?.hasSQLBody == false)
    }
    #expect(header("ALTER FUNCTION dbo.Fn(@Unfinished")?.parameters.isEmpty == true)
    #expect(header("SELECT N'ALTER FUNCTION dbo.Fn(@Fake int)'") == nil)
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
