import Testing
@testable import SQLServerKit

struct ResultQueryCopyTests {
  private let source="SELECT * FROM NTS_WM_SEVKPLAN AS NWS WITH(NOLOCK) WHERE NWS.SIPINCKEY = 13834905"
  @Test func replacesOriginalWhereAndPreservesAliasAndHints() throws {
    let template=try ResultQueryCopy(source:.init(sql:source),fields:[Field("TOPLAMA_ID",type:4),Field("Name"),Field("Missing")])
    #expect(try template.sql(cells:[(0,"1245")]) == "SELECT * FROM NTS_WM_SEVKPLAN AS NWS WITH(NOLOCK) WHERE NWS.TOPLAMA_ID = 1245;")
    #expect(try template.sql(cells:[(0,"1245"),(1,"O'Brien İstanbul"),(2,nil)]) == "SELECT * FROM NTS_WM_SEVKPLAN AS NWS WITH(NOLOCK) WHERE NWS.TOPLAMA_ID = 1245 AND NWS.Name = N'O''Brien İstanbul' AND NWS.Missing IS NULL;")
  }
  @Test func literalsKeepExactDecimalsBitsBinaryDatesAndStrings() throws {
    let fields=[Field("N",type:3,size:28,scale:8),Field("B",type:-7),Field("Bytes",type:-3),Field("Date",type:93),Field("Text")]
    let template=try ResultQueryCopy(source:.init(sql:"SELECT * FROM dbo.T"),fields:fields)
    let sql=try template.sql(cells:[(0,"12345678901234567890.12345678"),(1,"true"),(2,"0x00FF"),(3,"2026-10-17 10:11:12.123"),(4,"' OR 1=1 --")])
    #expect(sql.contains("N = 12345678901234567890.12345678 AND B = 1 AND Bytes = 0x00FF"))
    #expect(sql.contains("Date = N'2026-10-17 10:11:12.123'"))
    #expect(sql.contains("Text = N''' OR 1=1 --'"))
    #expect(throws:SQLFailure.self) {try template.sql(cells:[(0,"1; DELETE FROM T")])}
    #expect(throws:SQLFailure.self) {try template.sql(cells:[(2,"0xFF;--")])}
  }
  @Test func usesSourceColumnsInsteadOfProjectionAliasesAndPreservesTail() throws {
    let template=try ResultQueryCopy(source:.init(sql:"SELECT TOP (10) t.[Stock Code] AS Code, NewName = t.Name, t.N + 1 AS Calculated FROM [dbo].[T] t WHERE t.N IN (SELECT N FROM Other WHERE N>2) ORDER BY t.N OPTION(RECOMPILE); -- done"),fields:[Field("Code"),Field("NewName"),Field("Calculated",type:4)])
    let sql=try template.sql(cells:[(0,"A"),(1,"B")])
    #expect(sql.contains("WHERE t.[Stock Code] = N'A' AND t.Name = N'B' ORDER BY t.N OPTION(RECOMPILE); -- done"))
    #expect(!sql.contains("SELECT N FROM Other"))
    #expect(throws:SQLFailure.self) {try template.sql(cells:[(2,"2")])}
  }
  @Test func handlesWhereWordsInStringsAndCommentsAndQuotedNames() throws {
    let template=try ResultQueryCopy(source:.init(sql:"SELECT [x].* FROM [dbo].[T] AS [x] -- WHERE is a comment\nORDER BY [x].[a b];"),fields:[Field("a b"),Field("a]b"),Field("WHERE")])
    #expect(try template.sql(cells:[(0,"WHERE ' 😄"),(1,nil),(2,"value")]).contains("\nWHERE [x].[a b] = N'WHERE '' 😄' AND [x].[a]]b] IS NULL AND [x].[WHERE] = N'value' ORDER BY"))
  }
  @Test(arguments:["SELECT * FROM A JOIN B ON A.N=B.N","SELECT * FROM A, B","SELECT * FROM (SELECT * FROM A) t","SELECT * INTO X FROM T","SELECT * FROM T UNION SELECT * FROM U","SELECT * FROM T; DELETE FROM T;","EXEC dbo.P","WITH C AS (SELECT * FROM T) SELECT * FROM C"])
  func rejectsAmbiguousOrNonSelectSources(_ sql:String) {
    #expect(throws:SQLFailure.self) {try ResultQueryCopy(source:.init(sql:sql),fields:[Field("N")])}
  }
  @Test func verticalSelectionUsesInDeduplicatesAndHandlesNull() throws {
    let template=try ResultQueryCopy(source:.init(sql:source),fields:[Field("TOPLAMA_ID",type:4),Field("Name")])
    #expect(try template.sql(cells:[(0,"1245"),(0,"1246"),(0,"1245")])=="SELECT * FROM NTS_WM_SEVKPLAN AS NWS WITH(NOLOCK) WHERE NWS.TOPLAMA_ID IN (1245, 1246);")
    #expect(try template.sql(cells:[(0,"1245"),(0,nil),(0,"1246")]).contains("WHERE (NWS.TOPLAMA_ID IN (1245, 1246) OR NWS.TOPLAMA_ID IS NULL);"))
    #expect(try template.sql(cells:[(0,nil),(0,nil)]).contains("WHERE NWS.TOPLAMA_ID IS NULL;"))
    #expect(try template.sql(cells:[(1,"O'Brien"),(1,"İstanbul"),(1,"O'Brien")]).contains("NWS.Name IN (N'O''Brien', N'İstanbul')"))
    #expect(throws:SQLFailure.self) {try template.sql(cells:[(0,"1"),(1,"A"),(0,"2"),(1,"B")])}
    #expect(throws:SQLFailure.self) {try template.sql(cells:Array(repeating:(0,"1"),count:1001))}
  }
  @Test func rejectsInvocationAndUnsupportedTypesAndDuplicateColumns() throws {
    #expect(throws:SQLFailure.self) {try ResultQueryCopy(source:.init(sql:source,kind:.batch),fields:[Field("N")])}
    let template=try ResultQueryCopy(source:.init(sql:"SELECT * FROM T"),fields:[Field("Xml",declaredType:"xml")])
    #expect(throws:SQLFailure.self) {try template.sql(cells:[(0,"<x/>")])}
    #expect(try template.sql(cells:[(0,nil),(0,nil)])=="SELECT * FROM T WHERE Xml IS NULL;")
  }
}
