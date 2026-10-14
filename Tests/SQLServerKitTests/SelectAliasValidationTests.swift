import Foundation
import Testing
@testable import SQLServerKit

struct SelectAliasValidationTests {
  private let catalog=SQLIntelligence.Catalog(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"TBLSTHAR",columns:["STOK_KODU","STHAR_GCKOD","STHAR_GCMIK","YAPKOD","DEPO_KODU","SUBE_KODU"])]))
  private func marked(_ sql:String)throws->[String] {
    let result=try SQLIntelligence.analyze(source:sql,caret:sql.utf16.count,catalog:catalog,verified:true).diagnostics.map {(sql as NSString).substring(with:$0.range)}
    return result
  }
  @Test func stockInsertSelectAssignmentAndAsAliasesAreNotMissingColumns() throws {
    for expression in ["HUCREKODU = '1100'","'1100' AS HUCREKODU","'1100' HUCREKODU"] {
      let sql="""
      SELECT T.STOK_KODU, \(expression), 'G', CAST(GETDATE() AS DATE), 'A',
      BAKIYE = SUM(CASE WHEN T.STHAR_GCKOD = 'G' THEN T.STHAR_GCMIK ELSE -1 * T.STHAR_GCMIK END),
      NULL, 'CENTRALGECIS', 'SmartWM', GETDATE(), 0, T.YAPKOD
      FROM TBLSTHAR AS T WITH(NOLOCK) WHERE T.DEPO_KODU = 11 AND T.SUBE_KODU = 100
      GROUP BY T.STOK_KODU, T.YAPKOD
      HAVING SUM(CASE WHEN T.STHAR_GCKOD = 'G' THEN T.STHAR_GCMIK ELSE -1 * T.STHAR_GCMIK END) > 0;
      """
      #expect(try marked(sql).isEmpty,Comment(rawValue:sql))
    }
  }
  @Test func modifiersQuotedLabelsAndNestedSelectsPreserveAliasDefinitions() throws {
    for modifier in ["","DISTINCT ","TOP 10 ","TOP (10) PERCENT WITH TIES "] {
      #expect(try marked("SELECT \(modifier)[Cell Code] = '1100', [Amount] = SUM(T.STHAR_GCMIK) FROM TBLSTHAR T ORDER BY [Amount];").isEmpty)
    }
    #expect(try marked("SELECT x.BAKIYE FROM (SELECT BAKIYE=SUM(T.STHAR_GCMIK) FROM TBLSTHAR T) x;").isEmpty)
    #expect(try marked("WITH x AS (SELECT T.STOK_KODU AS Code FROM TBLSTHAR T) SELECT x.Code FROM x;").isEmpty)
  }
  @Test func aliasesNeverHideQualifiedMissingColumnsOrSeparateStatementErrors() throws {
    #expect(try marked("SELECT BAKIYE=1, T.BAKIYE FROM TBLSTHAR T;")==["BAKIYE"])
    #expect(try marked("SELECT T.STOK_KODU AS BAKIYE, T.BAKIYE FROM TBLSTHAR T;")==["BAKIYE"])
    #expect(try marked("SELECT BAKIYE=MissingSource FROM TBLSTHAR T;")==["MissingSource"])
    for separator in ["; ","\n"," UNION ALL ",";\nGO\n"] {
      #expect(try marked("SELECT BAKIYE=1 FROM TBLSTHAR T"+separator+"SELECT BAKIYE FROM TBLSTHAR T;")==["BAKIYE"])
    }
    #expect(try marked("SELECT * FROM TBLSTHAR T WHERE BAKIYE=1;")==["BAKIYE"])
    #expect(try marked("SELECT BAKIYE=1 FROM TBLSTHAR T WHERE BAKIYE=1;")==["BAKIYE"])
    #expect(try marked("SELECT T.STOK_KODU AS BAKIYE FROM TBLSTHAR T GROUP BY BAKIYE;")==["BAKIYE"])
    #expect(try marked("UPDATE TBLSTHAR SET BAKIYE=1;")==["BAKIYE"])
    #expect(try marked("SELECT (SELECT BAKIYE=1 FROM TBLSTHAR T) AS Nested, BAKIYE FROM TBLSTHAR T;")==["BAKIYE"])
  }
}
