import Foundation
import Testing
@testable import SQLServerKit

struct ResultSourceTests {
  func rows(_ count: Int) -> [Rows] { (0..<count).map { _ in Rows(fields: [Field("Value")], values: [[nil]]) } }
  @Test func independentSelectsKeepExactLiteralsAndIgnoreCommentsAndNestedQueries() {
    let sql = "-- SELECT fake; 😀\nSELECT N'a; SELECT b' AS [SELECT];\n/* outer /* nested */ SELECT; */\nSELECT (SELECT 2) AS [Two]; SELECT NULL AS Missing;"
    let sources = ResultSourceMap(sql: sql).sources(for: rows(3))
    #expect(sources.map { $0?.sql } == ["SELECT N'a; SELECT b' AS [SELECT];", "SELECT (SELECT 2) AS [Two];", "SELECT NULL AS Missing;"])
    #expect(sources.allSatisfy { $0?.kind == .statement })
  }
  @Test func optionalTerminatorsCteUnionAssignmentsAndNoCountDoNotShiftSources() {
    let sql = "SET NOCOUNT ON; DECLARE @n int = 1; SELECT @n = 2;\nSELECT @n AS First\nSELECT 2 AS Second; WITH c AS (SELECT 3 AS n) SELECT n FROM c UNION ALL SELECT 4; SELECT 5 INTO #t;"
    let sources = ResultSourceMap(sql: sql).sources(for: rows(3))
    #expect(sources[0]?.sql == "SELECT @n AS First")
    #expect(sources[1]?.sql == "SELECT 2 AS Second;")
    #expect(sources[2]?.sql == "WITH c AS (SELECT 3 AS n) SELECT n FROM c UNION ALL SELECT 4;")
    let top = ResultSourceMap(sql: "DECLARE @n int; SELECT TOP (1) @n = 7; SELECT TOP (5) @n AS n;").sources(for: rows(1))
    #expect(top[0]?.sql == "SELECT TOP (5) @n AS n;")
  }
  @Test func procedureInvocationMayOwnManyResultsButMixedAndConditionalBatchesStayExplicit() {
    let call = "EXEC dbo.usp_Report @Name=N'İstanbul';"
    #expect(ResultSourceMap(sql: call).sources(for: rows(3)).allSatisfy { $0?.sql == call && $0?.kind == .invocation })
    for sql in ["EXEC dbo.p EXEC dbo.q", "SELECT 1; EXEC dbo.p; SELECT 2;", "IF 1=1 SELECT 1; ELSE SELECT 2;", "DECLARE c CURSOR FOR SELECT 1; OPEN c; FETCH c;", "UPDATE t SET v=1 OUTPUT inserted.v; SELECT 2;"] {
      #expect(ResultSourceMap(sql: sql).sources(for: rows(2)).allSatisfy { $0?.sql == sql && $0?.kind == .batch })
    }
  }
  @Test func unexpectedCountsAndPlansNeverMislabelResultsAndAffectedCountsHaveNoSource() {
    let map = ResultSourceMap(sql: "SELECT 1; SELECT 2;")
    #expect(map.sources(for: rows(1))[0]?.kind == .batch)
    let xml = "<ShowPlanXML><RelOp NodeId='0'/></ShowPlanXML>"
    var result = rows(2); result.insert(Rows(affected: 7),at: 1); result.append(Rows(fields: [Field("Plan")], values: [[xml]]))
    let sources = map.sources(for: result)
    #expect(sources[0]?.sql == "SELECT 1;" && sources[1] == nil && sources[2]?.sql == "SELECT 2;")
    #expect(sources[3]?.kind == .batch)
    #expect(ResultSourceMap(sql: "SELECT 1;").sources(for: [result[3]])[0]?.kind == .batch)
  }
  @Test func goBatchAndRepeatCaptureSourcesInFinalRowsAndStreamingEvents() async throws {
    final class Captured: @unchecked Sendable {
      let lock = NSLock(); var items: [(Int,SQLResultSource)] = []
      func receive(_ event: QueryEvent) { if case .source(let index,let source)=event { lock.withLock {items.append((index,source))} } }
      func values() -> [(Int,SQLResultSource)] { lock.withLock {items} }
    }
    let captured=Captured()
    let result = try await TSQL.run("SELECT N'first';\nGO 2\nSELECT NULL;",limits:Limits(),events:captured.receive) { text, _, emit in
      var output=Execution();output.results=[Rows(affected:1),Rows(fields:[Field("Value")],values:[[text.contains("NULL") ? nil : "first"]])]
      emit?(.result(1,output.results[1].fields));return output
    }
    #expect(result.results[1].source?.sql == "SELECT N'first';")
    #expect(result.results[3].source?.batch == 2 && result.results[5].source?.batch == 3)
    #expect(result.results[5].source?.sql == "SELECT NULL;")
    #expect(captured.values().contains { $0.0 == 5 && $0.1.sql == "SELECT NULL;" && $0.1.kind == .statement })
    #expect(captured.values().contains { $0.0 == 1 && $0.1.kind == .batch })
  }
  @Test func previewIsBoundedAndNeverChangesStoredSql() {
    let sql = String(repeating: "SELECT N'😀 İstanbul';\n", count: 500)
    let source=SQLResultSource(sql:sql)
    #expect(source.preview.contains("kısaltıldı"))
    #expect(source.preview.count < 2100 && source.sql == sql)
    let huge=String(repeating:"SELECT 1;",count:30000)
    #expect(ResultSourceMap(sql:huge).sources(for:rows(1))[0]?.kind == .batch)
  }
}
