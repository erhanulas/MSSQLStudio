import Foundation
import Testing
@testable import SQLServerKit

@Suite struct UndeclaredVariableTests {
  private func missing(_ sql:String)->[String] {TSQL.variableAnalysis(sql).undeclared.map {(sql as NSString).substring(with:$0)}}
  @Test func declarationsAreCaseInsensitiveOrderedAndBatchScoped() {
    #expect(missing("SELECT @before; DECLARE @before int, @known int; SELECT @BEFORE, @known, @missing;")==["@before","@missing"])
    #expect(missing("DECLARE @x int; SELECT @x;\nGO 2 -- batch\nSELECT @x, @@ROWCOUNT, @@SPID;")==["@x"])
    #expect(missing("SELECT N'@string', [@identifier], \"@quoted\"; -- @comment\n/* @nested /* @deep */ */ SELECT @gerçek;")==["@gerçek"])
  }
  @Test func procedureFunctionAndReturnTableNamesAreKnown() {
    #expect(missing("CREATE OR ALTER PROCEDURE dbo.p @p int, @rows dbo.RowType READONLY AS BEGIN DECLARE @local int=@p; SELECT @local FROM @rows; SELECT @unknown; END;")==["@unknown"])
    #expect(missing("CREATE FUNCTION dbo.f(@p int) RETURNS @result TABLE (id int) AS BEGIN INSERT @result VALUES (@p); RETURN; END;").isEmpty)
    #expect(missing("CREATE FUNCTION dbo.f(@p int) RETURNS int AS BEGIN RETURN @notThere; END;")==["@notThere"])
  }
  @Test func execArgumentLabelsAreExcludedButValuesAndReturnVariablesAreChecked() {
    let sql="DECLARE @value int; EXEC @return = dbo.p @label=@value, @other=@missing OUTPUT; SELECT @label; EXEC sys.sp_executesql N'SELECT @dynamic', N'@dynamic int', @dynamic=2;"
    #expect(missing(sql)==["@return","@missing","@label"])
    #expect(missing("DECLARE @sql nvarchar(max); EXEC(@sql); EXEC @proc @arg=@value;")==["@proc","@value"])
    #expect(missing("DECLARE @label int; EXEC dbo.p @label=1; SELECT @label;").isEmpty)
  }
  @Test func namedArgumentIsNotAUseOfAnUnrelatedLocalDeclaration() {
    let sql="DECLARE @value int; EXEC dbo.p @value=1;"
    #expect(TSQL.variableAnalysis(sql).unused.map {(sql as NSString).substring(with:$0)}==["@value"])
  }
  @Test func incompleteAndExternalSignaturesDoNotProduceFalseErrors() {
    for sql in ["ALTER FUNCTION dbo.f(@typing", "CREATE PROCEDURE dbo.p @typing AS", "CREATE PROCEDURE dbo.p @p int AS EXTERNAL NAME [A].[T].[M];", "SELECT @", String(repeating:" ",count:250_001)+"@missing"] {
      #expect(missing(sql).isEmpty)
    }
  }
}
