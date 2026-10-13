import Foundation
import Testing
@testable import SQLServerKit

struct DMLCompletionTests {
  private let symbols = [CatalogSymbol(schema:"dbo",name:"News",columns:["ID","Title","STOK_KODU"]),CatalogSymbol(schema:"dbo",name:"Other",columns:["OtherID","NewsID"])]
  private func analyze(_ marked:String)throws->SQLIntelligence.Analysis {
    let caret=(marked as NSString).range(of:"§").location
    return try SQLIntelligence.analyze(source:marked.replacingOccurrences(of:"§",with:""),caret:caret,catalog:.init(snapshot:.init(symbols:symbols)),verified:true)
  }
  private func columns(_ sql:String)throws->[String] {try analyze(sql).suggestions.filter {$0.kind == .column}.map(\.text)}
  @Test func updateTargetAliasResolvesItsFromRelationInsteadOfShadowingIt() throws {
    for sql in ["UPDATE NWS SET NWS.§ FROM dbo.News AS NWS JOIN dbo.Other O ON O.NewsID=NWS.ID WHERE NWS.ID=1", "UPDATE [NWS]\nSET [NWS].§\nFROM [dbo].[News] AS [NWS] WITH(NOLOCK)\nJOIN dbo.Other O ON O.NewsID=NWS.ID"] {
      #expect(try columns(sql) == ["[ID]","[Title]","[STOK_KODU]"])
      #expect(try analyze(sql).diagnostics.allSatisfy {!$0.message.contains("NWS")})
    }
    #expect(try columns("UPDATE News SET News.§") == ["[ID]","[Title]","[STOK_KODU]"])
    #expect(try columns("UPDATE NWS SET KODU§=1 FROM dbo.News NWS") == ["[NWS].[STOK_KODU]"])
  }
  @Test func deleteAndInsertTargetsAndJoinedSourcesOfferTheirOwnColumns() throws {
    for sql in ["DELETE dbo.News WHERE News.§", "DELETE FROM NWS FROM dbo.News NWS JOIN dbo.Other O ON O.NewsID=NWS.ID WHERE NWS.§", "DELETE NWS FROM dbo.News NWS WHERE NWS.§", "INSERT dbo.News (§)", "INSERT INTO dbo.News (§) VALUES (1)"] {
      #expect(try columns(sql) == ["[ID]","[Title]","[STOK_KODU]"],"\(sql)")
    }
    #expect(try columns("INSERT INTO dbo.News (Title) SELECT O.§ FROM dbo.Other O") == ["[OtherID]","[NewsID]"])
  }
  @Test func outputPseudoRelationsUseTheActualDMLTargetAndNeverLeakToSelect() throws {
    #expect(try columns("UPDATE NWS SET Title=N'X' OUTPUT inserted.§ FROM dbo.News NWS") == ["[ID]","[Title]","[STOK_KODU]"])
    #expect(try columns("DELETE FROM dbo.News OUTPUT deleted.§") == ["[ID]","[Title]","[STOK_KODU]"])
    #expect(try columns("INSERT dbo.News (ID) OUTPUT inserted.§ VALUES (1)") == ["[ID]","[Title]","[STOK_KODU]"])
    #expect(try columns("SELECT inserted.§ FROM dbo.News") == [])
  }
  @Test func declaredVariablesCompleteAtOneAtSignOnlyAfterDeclarationInTheirBatch() throws {
    let result=try analyze("DECLARE @DEGISKEN int, @Other decimal(18,2)=CASE WHEN 1=1 THEN 1 ELSE 0 END; DECLARE @Rows TABLE(ID int); SELECT @§; DECLARE @Future int;")
    #expect(result.suggestions.map(\.text) == ["@DEGISKEN","@Other","@Rows"])
    #expect(try analyze("DECLARE @DEGISKEN int; SELECT @deg§").suggestions.map(\.text) == ["@DEGISKEN"])
    #expect(try analyze("DECLARE @Old int;\nGO\nDECLARE @New int; SELECT @§").suggestions.map(\.text) == ["@New"])
    #expect(try analyze("-- DECLARE @fake int\nSELECT '@§'").suggestions.isEmpty)
  }
  @Test func routineParametersAndDMLScopesRemainLocal() throws {
    #expect(try analyze("ALTER PROCEDURE dbo.p @Customer int, @Amount decimal(18,2) AS BEGIN SELECT @§; END").suggestions.map(\.text) == ["@Customer","@Amount"])
    #expect(try columns("UPDATE NWS SET ID=1 FROM dbo.News NWS; SELECT NWS.§ FROM dbo.Other O").isEmpty)
    #expect(try columns("DELETE FROM dbo.News WHERE EXISTS (SELECT 1 FROM dbo.Other O WHERE O.§)") == ["[OtherID]","[NewsID]"])
  }
}
