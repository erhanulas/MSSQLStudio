import SQLServerKit
import Testing

struct RepeatReadTests {
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
