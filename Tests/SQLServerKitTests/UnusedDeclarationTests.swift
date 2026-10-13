import Foundation
import Testing
@testable import SQLServerKit

@Suite struct UnusedRoutineVariableTests {
  private func unused(_ sql:String) -> [String] {
    TSQL.unusedDeclaredVariables(sql).map { (sql as NSString).substring(with:$0) }
  }

  @Test func functionInputsAndLocalDeclarationsHaveTheSameUnusedPolicy() {
    let sql="""
    ALTER FUNCTION dbo.Calculate(@used int, @unused decimal(28,8) = 0)
    RETURNS int AS
    BEGIN
      DECLARE @local int;
      RETURN @used;
    END;
    """
    #expect(unused(sql) == ["@unused","@local"])
  }

  @Test func procedureParametersIncludeDefaultsOutputAndReadOnlyTableInputs() {
    let sql="""
    CREATE OR ALTER PROCEDURE [dbo].[Report]
      @used int,
      @defaulted nvarchar(20) = N'@used',
      @output int OUTPUT,
      @rows [dbo].[RowType] READONLY
    WITH RECOMPILE AS
    BEGIN
      SET @output=@used;
      SELECT * FROM @rows;
    END;
    """
    #expect(unused(sql) == ["@defaulted"])
    #expect(unused("CREATE PROC dbo.Empty @first int, @second int = 1 AS SELECT 1;") == ["@first","@second"])
    #expect(unused("ALTER PROC dbo.Empty @first dbo.GO, @second int AS SELECT @second;") == ["@first"])
  }

  @Test func returnedTableIsNotAnUnusedInputAndInlineFunctionsAreCovered() {
    let multi="CREATE FUNCTION dbo.Multi(@used int, @unused int) RETURNS @result TABLE (id int) AS BEGIN INSERT @result VALUES (@used); RETURN; END;"
    #expect(unused(multi) == ["@unused"])
    let inline="CREATE FUNCTION dbo.Inline(@unused int, @used int) RETURNS TABLE AS RETURN (SELECT @used AS id);"
    #expect(unused(inline) == ["@unused"])
  }

  @Test func caseInitializerDoesNotHideFollowingDeclarations() {
    let sql="DECLARE @first int = CASE WHEN 1=1 THEN 0 ELSE 1 END, @unused int, @used int; SELECT @used;"
    #expect(unused(sql) == ["@first","@unused"])
    #expect(unused("DECLARE @first int = CASE WHEN 1=1 THEN CASE WHEN 2=2 THEN 3 END ELSE 4 END, @unused int\nSELECT @first;") == ["@unused"])
  }

  @Test func commentsStringsAndAnotherBatchDoNotUseRoutineInputs() {
    let sql="""
    -- 😀
    ALTER PROCEDURE dbo.p @boş int, @used int AS
    SELECT @USED, '@boş', [@boş]; -- @boş
    GO 2 -- separate batch
    SELECT @boş;
    """
    #expect(unused(sql) == ["@boş"])
    #expect(unused("EXEC dbo.p @first=1, @second=2; SELECT dbo.f(1);").isEmpty)
    #expect(unused("SELECT 'ALTER FUNCTION dbo.f(@p int) RETURNS int AS BEGIN RETURN 1; END';").isEmpty)
  }

  @Test func incompleteHeadersDoNotInventDeclarationNames() {
    #expect(unused("ALTER FUNCTION dbo.f(@typing").isEmpty)
    #expect(unused("CREATE PROCEDURE dbo.p @typing AS").isEmpty)
    #expect(unused("ALTER FUNCTION dbo.f(@p int) RETURNS int AS BEGIN RETURN @p; END;").isEmpty)
  }

  @Test func externalImplementationsDoNotAppearToHaveUnusedInputs() {
    #expect(unused("CREATE PROCEDURE dbo.CLR @input int AS EXTERNAL NAME [Assembly].[Type].[Method];").isEmpty)
    #expect(unused("CREATE FUNCTION dbo.CLR(@input int) RETURNS int AS EXTERNAL NAME [Assembly].[Type].[Method];").isEmpty)
  }
}
