import Foundation
import Testing
@testable import SQLServerKit

@Suite struct SQLExecutionScopeTests {
  private func units(_ sql:String)->[String] {SQLExecutionScopes(sql).statements.map {(sql as NSString).substring(with:$0.range)}}
  @Test func straightStatementsAndQuotedDelimitersStayExact() {
    #expect(units("SELECT N'a; SELECT 😀'; SELECT [SELECT] FROM [dbo].[T];") == ["SELECT N'a; SELECT 😀';","SELECT [SELECT] FROM [dbo].[T];"])
    #expect(units("SELECT 1\nSELECT 2\nDECLARE @x int=3; SET @x=4; SELECT @x;").count == 5)
    #expect(units(";SELECT 1;;SELECT 2;") == ["SELECT 1;","SELECT 2;"])
  }
  @Test func nestedSelectCTEUnionInsertSelectAndCaseAreNeverSplit() {
    for source in ["WITH c AS (SELECT 1 AS n) SELECT * FROM c;", "WITH c AS (SELECT 1 AS n) UPDATE dbo.T SET n=c.n FROM c;", "SELECT 1 UNION ALL SELECT 2 EXCEPT SELECT 3;", "SELECT CASE WHEN 1=1 THEN (SELECT 1) ELSE 2 END;", "INSERT INTO dbo.T(a) SELECT a FROM dbo.S;", "UPDATE dbo.T SET a=(SELECT MAX(a) FROM dbo.S);"] {
      #expect(units(source) == [source],"\(source)")
    }
  }
  @Test func controlFlowRoutinesAndTransactionsStayInTheirBatch() {
    for source in ["IF 1=0 SELECT 1; ELSE SELECT 2; SELECT 3;", "BEGIN SELECT 1; SELECT 2; END;", "BEGIN TRY SELECT 1; END TRY BEGIN CATCH THROW; END CATCH;", "CREATE OR ALTER PROCEDURE dbo.P AS SELECT 1; SELECT 2;", "BEGIN TRAN; UPDATE dbo.T SET a=1; ROLLBACK;"] {
      #expect(units(source) == [source],"\(source)")
    }
  }
  @Test func independentBeginEndBlockKeepsItsInnerStatementsTogether() {
    let block="BEGIN SELECT 1; BEGIN SELECT 2; END; SELECT 3; END;"
    #expect(units(block+" SELECT 4;") == [block,"SELECT 4;"])
  }
  @Test func goScopePreservesRepeatAndDoesNotReadProtectedGo() {
    let sql="SELECT 'GO' AS [Go];\r\nGO 2 -- repeat\r\nSELECT 2; SELECT 3;"
    let values=SQLExecutionScopes(sql).statements
    #expect(values.count == 3)
    #expect((sql as NSString).substring(with:values[0].batch).hasSuffix("GO 2 -- repeat\r\n"))
    #expect(units("SELECT 'one\nGO\ntwo'; SELECT 2;").count == 2)
    #expect(units("/* outer /* GO */ SELECT */ SELECT 1; SELECT 2;").count == 2)
  }
  @Test func unfinishedAndBudgetedInputIsConservative() {
    #expect(units("SELECT (1; SELECT 2;").count == 1)
    #expect(SQLExecutionScopes(String(repeating:"SELECT 1;",count:30000)).statements.isEmpty)
  }
  @Test func selectAndDeclareSpacingIsConfigurableIdempotentAndTokenSafe() throws {
    let sql="DECLARE @a int=1; DECLARE @b decimal(10,2)=2; SELECT @a,(SELECT @b) AS n UNION ALL SELECT 3,4; SELECT 5;"
    let formatted=TSQL.format(sql)
    #expect(formatted.contains("DECLARE @a int = 1;\nDECLARE @b"))
    #expect(formatted.contains("= 2;\n\nSELECT"))
    #expect(formatted.contains("4;\n\nSELECT 5;"))
    #expect(!formatted.contains("UNION ALL\n\nSELECT"))
    #expect(SQLFormatter.preservesSQLTokens(sql,formatted:formatted) && TSQL.format(formatted) == formatted)
    let compact=TSQL.format(sql,options:.init(blankLineAfterSelect:false,blankLineAfterDeclare:false))
    #expect(!compact.contains("\n\n"))
    #expect(TSQL.format("WITH c AS (SELECT 1 AS n) SELECT * FROM c; SELECT 2;").contains(";\n\nSELECT"))
    let crlf=TSQL.format(sql.replacingOccurrences(of:"; ",with:";\r\n"))
    #expect(crlf.contains("\r\n\r\nSELECT"))
    let legacy=Data(#"{"indentWidth":2,"keywordCase":"lower","commaStyle":"leading","multilineLists":false,"breakConditions":false,"lineWidth":80}"#.utf8)
    let options=try JSONDecoder().decode(SQLFormattingOptions.self,from:legacy)
    #expect(options.indentWidth == 2 && options.blankLineAfterSelect == nil && options.blankLineAfterDeclare == nil)
    #expect(TSQL.format("declare @x int; select @x; select 2;",options:options).contains(";\n\nselect"))
  }
}
