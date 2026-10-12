import Foundation
import SQLServerKit
import Testing

struct RepeatReadTests {
  @Test func literalScalarFilterParametersRemainRepeatableBeforeReadOnlyQueries() {
    for sql in [
      "DECLARE @OnlyBlocking BIT=0; DECLARE @DBNameFilter SYSNAME=NULL; ;WITH c AS (SELECT @OnlyBlocking AS n) SELECT * FROM c;",
      ";;DECLARE @a AS INT, @b BIGINT=-100, @c BIT=1; SELECT @a, @b, @c; SELECT 2;",
      "DECLARE @text NVARCHAR(MAX)=N'KILL 42; EXEC dbo.p; UPDATE t; GO'; SELECT @text;",
      "DECLARE @amount DECIMAL(28,8)=-.12500000, @ratio FLOAT(53)=1.25e-10, @bytes VARBINARY(8)=0xAB12; SELECT @amount, @ratio, @bytes;",
      "DECLARE @at DATETIME2(7)='2026-10-12T12:00:00', @id UNIQUEIDENTIFIER=NULL; SELECT @at, @id;",
      "DECLARE @a INT=1\nDECLARE @b INT=2\nSELECT @a, @b;",
      "DECLARE @a INT SELECT @a;",
      "DECLARE @a INT = /* filter */ + /* sign */ 1; SELECT @a;",
    ] { #expect(TSQL.canRepeatRead(sql), Comment(rawValue: sql)) }
  }

  @Test func parameterDeclarationsNeverAdmitExecutableOrUnsupportedInitializers() {
    for declaration in [
      "DECLARE @a INT=(SELECT COUNT(*) FROM t);",
      "DECLARE @a INT=dbo.SideEffect();", "DECLARE @a INT=NEXT VALUE FOR dbo.seq;",
      "DECLARE @a INT=GETDATE();", "DECLARE @a INT=CAST(1 AS INT);",
      "DECLARE @a INT=@other;", "DECLARE @a INT=@@SPID;", "DECLARE @a INT=1+2;",
      "DECLARE @a TABLE(n INT);", "DECLARE @a CURSOR;", "DECLARE @a dbo.CustomType;",
      "DECLARE @a [int]=1;", "DECLARE @a XML(dbo.Collection);", "DECLARE @a geography;",
      "DECLARE @@a INT=1;", "DECLARE @ INT=1;", "DECLARE @a INT=;",
      "DECLARE @a NVARCHAR(10)=N'unterminated", "DECLARE @a INT(1)=1;",
      "DECLARE @a DECIMAL(39,0)=1;", "DECLARE @a DECIMAL(10,11)=1;",
      "DECLARE @a DECIMAL(10,2,1)=1;", "DECLARE @a FLOAT(54)=1;",
      "DECLARE @a NCHAR(MAX)=N'a';", "DECLARE @a VARCHAR(0)='a';",
      "DECLARE @a NVARCHAR(4001)=N'a';", "DECLARE @a TIME(8)=NULL;",
      "DECLARE @a INT=0,;", "DECLARE @a INT COLLATE Latin1_General_CI_AS;",
    ] { #expect(!TSQL.canRepeatRead(declaration + " SELECT 1;"), Comment(rawValue: declaration)) }
    for suffix in [
      "SET @a=2; SELECT @a;", "EXEC dbo.p; SELECT 1;", "dbo.WriteData; SELECT 1;",
      ";WITH c AS (SELECT 1 AS n) DELETE FROM t;", "SELECT * INTO #new FROM t;",
      "SELECT * FROM t WITH (UPDLOCK);", "SELECT * FROM t WITH (HOLDLOCK);",
      "SELECT NEXT VALUE FOR dbo.seq;", "SELECT * FROM OPENQUERY(s, 'SELECT 1');",
      "SELECT 1\nGO 2\nSELECT 2;", "SELECT 1; DECLARE @b INT=2; SELECT @b;",
      "BEGIN TRAN; SELECT 1; COMMIT;",
    ] { #expect(!TSQL.canRepeatRead("DECLARE @a INT=1; " + suffix), Comment(rawValue: suffix)) }
    #expect(!TSQL.canRepeatRead("DECLARE @a INT=1;"))
  }

  @Test func pastedMonitoringScriptRetainsLiteralKillLabelsAndSafeParameters() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/ParameterizedMonitoring.sql")
    let sql = try String(contentsOf: url, encoding: .utf8)
    #expect(TSQL.lex(sql).filter { $0.text.uppercased() == "DECLARE" }.count == 6)
    #expect(sql.contains("SYSNAME = NULL") && sql.contains("CONCAT('kill ', es.session_id)"))
    #expect(sql.contains("BlockingChain AS") && sql.contains("JOIN BlockingChain bc"))
    #expect(TSQL.canRepeatRead(sql))
    #expect(!TSQL.canRepeatRead(sql + "\nKILL 42;"))
    #expect(!TSQL.canRepeatRead(sql.replacingOccurrences(of: "BIT     = 0;", with: "BIT     = dbo.SideEffect();")))
    #expect(throws: SQLFailure.self) { try ResultEditSource.metadata(sql) }
    #expect(throws: SQLFailure.self) { try ResultEditSource.metadata("DECLARE @id INT=1; SELECT * FROM dbo.T WHERE Id=@id;") }
  }

  @Test func leadingTerminatorsAndMultipleCTESelectsRemainRepeatable() {
    for sql in [
      ";WITH c AS (SELECT 1 AS n) SELECT * FROM c; SELECT 2 AS n;",
      "-- prior statement terminator\r\n ; /* CTE */ ;WITH c AS (SELECT 1 AS n), d AS (SELECT n FROM c) SELECT * FROM d;; SELECT 3; ;",
      ";WITH c AS (SELECT 1 AS n) SELECT * FROM c; ;WITH d AS (SELECT 2 AS n) SELECT * FROM d;",
      ";WITH c(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM c WHERE n < 3) SELECT * FROM c OPTION (MAXRECURSION 10); SELECT N'UPDATE; EXEC; GO' AS [DELETE];",
      "SELECT (SELECT 1) AS n; -- ; DELETE ignored\nSELECT N';WITH c AS ()' AS [WITH];",
    ] { #expect(TSQL.canRepeatRead(sql), Comment(rawValue: sql)) }
  }

  @Test func CTEAndStatementTerminatorsNeverAdmitWritesOrExecutableBatches() {
    for sql in [
      ";WITH c AS (SELECT 1 AS n) DELETE FROM t OUTPUT deleted.n; SELECT 2;",
      ";WITH c AS (SELECT 1 AS n) UPDATE t SET n=2; SELECT 2;",
      ";WITH c AS (SELECT 1 AS n) INSERT INTO t SELECT n FROM c;",
      ";WITH c AS (SELECT 1 AS n) MERGE t USING c ON 1=0 WHEN NOT MATCHED THEN INSERT(n) VALUES(c.n);",
      ";WITH c AS (SELECT 1 AS n) SELECT * INTO #new FROM c; SELECT 2;",
      ";WITH c AS (SELECT 1) SELECT 1; EXEC(N'DELETE FROM t');",
      ";SELECT 1; dbo.WriteData;", ";dbo.WriteData; SELECT 1;",
      ";SELECT 1\nGO\nSELECT 2;", ";SELECT 1\nGO 20\nSELECT 2;",
      ";WITH c AS (SELECT NEXT VALUE FOR dbo.seq AS n) SELECT n FROM c;",
      "SELECT * FROM OPENQUERY(server, 'DELETE FROM t');",
      "SELECT * FROM t WITH (UPDLOCK);", "BEGIN TRAN; SELECT 1; COMMIT;",
    ] { #expect(!TSQL.canRepeatRead(sql), Comment(rawValue: sql)) }
  }

  @Test func emptyAndIncompleteStatementShapesAreNotRepeatable() {
    for sql in ["", ";;; -- SELECT 1", ";WITH c AS (SELECT 1", ";SELECT 1);", "SELECT (1; SELECT 2);", ";WITH c; SELECT 1;"] {
      #expect(!TSQL.canRepeatRead(sql), Comment(rawValue: sql))
    }
  }
}
