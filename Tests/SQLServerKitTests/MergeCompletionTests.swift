import Foundation
import Testing
@testable import SQLServerKit

struct MergeCompletionTests {
  private let catalog=SQLIntelligence.Catalog(snapshot:.init(symbols:[
    CatalogSymbol(schema:"dbo",name:"Target",columns:["STOK_KODU","HUCREKODU","MIKTAR","KAYITTARIHI","DUZELTMETARIHI"]),
    CatalogSymbol(schema:"dbo",name:"Source",columns:["Stock","Amount"])
  ]))
  private func analyze(_ marked:String)throws->SQLIntelligence.Analysis {
    let caret=(marked as NSString).range(of:"§").location
    return try SQLIntelligence.analyze(source:marked.replacingOccurrences(of:"§",with:""),caret:caret,catalog:catalog,verified:true)
  }
  private func columns(_ marked:String)throws->[String] {try analyze(marked).suggestions.filter {$0.kind == .column}.map(\.text)}
  private func script(_ action:String)->String {
    """
    ALTER PROCEDURE dbo.p AS BEGIN
    SET NOCOUNT ON;
    DECLARE @HUCREKODU varchar(15) = 'ASRS-1001';
    DECLARE @BOX_TABLE TABLE (BoxRid int)
    INSERT INTO @BOX_TABLE (BoxRid) SELECT 1
    MERGE INTO dbo.Target AS T
    USING (
      SELECT STOK_KODU = B.ERPStockCode COLLATE DATABASE_DEFAULT,
             MIKTAR = SUM(A.[Count])
      FROM WCS.dbo.Stock AS A WITH(NOLOCK)
      JOIN WCS.dbo.Product AS B WITH(NOLOCK) ON B.Id=A.ProductRid
      JOIN @BOX_TABLE AS C ON C.BoxRid=A.BoxRid
      WHERE A.[Count]>0 GROUP BY B.ERPStockCode COLLATE DATABASE_DEFAULT
    ) AS S
    ON T.STOK_KODU=S.STOK_KODU AND T.HUCREKODU=@HUCREKODU
    \(action)
    WHEN NOT MATCHED BY SOURCE AND T.HUCREKODU=@HUCREKODU THEN DELETE;
    END;
    """
  }
  @Test func updateAssignmentsAndDerivedSourceKeepMergeScope() throws {
    let target=["[STOK_KODU]","[HUCREKODU]","[MIKTAR]","[KAYITTARIHI]","[DUZELTMETARIHI]"]
    #expect(try columns(script("WHEN MATCHED THEN UPDATE SET T.§ = S.MIKTAR"))==target)
    #expect(try columns(script("WHEN MATCHED THEN UPDATE SET §"))==target.map {"[T]."+$0})
    #expect(try columns(script("WHEN MATCHED THEN UPDATE SET T.MIKTAR=S.MIKTAR, T.DUZELT§=GETDATE()"))==["[DUZELTMETARIHI]"])
    #expect(try columns(script("WHEN MATCHED THEN UPDATE SET T.MIKTAR=S.§"))==["[STOK_KODU]","[MIKTAR]"])
    #expect(try columns(script("WHEN MATCHED THEN UPDATE SET S.§")).isEmpty)
    #expect(try analyze(script("WHEN MATCHED THEN UPDATE SET T.MIKTAR=S.§")).referenceBindings["t"]==["dbo","Target"])
  }
  @Test func insertListOffersUnusedTargetColumnsAndValuesOfferSourceAlias() throws {
    let action="WHEN MATCHED THEN UPDATE SET T.MIKTAR=S.MIKTAR\nWHEN NOT MATCHED BY TARGET THEN "
    #expect(try columns(script(action+"INSERT (STOK_KODU, §) VALUES (S.STOK_KODU, 1)"))==["[HUCREKODU]","[MIKTAR]","[KAYITTARIHI]","[DUZELTMETARIHI]"])
    #expect(try columns(script(action+"INSERT (STOK_KODU, mikt§, HUCREKODU) VALUES (S.STOK_KODU, S.MIKTAR, @HUCREKODU)"))==["[MIKTAR]"])
    #expect(try columns(script(action+"INSERT (STOK_KODU, MIKTAR) VALUES (S.STOK_KODU, S.§)"))==["[STOK_KODU]","[MIKTAR]"])
  }
  @Test func tableSourceHintsOptionalIntoAndStatementBoundaries() throws {
    for start in ["MERGE dbo.Target AS T","MERGE TOP (10) INTO dbo.Target WITH(HOLDLOCK) AS T"] {
      #expect(try columns(start+" USING dbo.Source AS S ON T.STOK_KODU=S.Stock WHEN MATCHED THEN UPDATE SET T.MIKTAR=S.§;")==["[Stock]","[Amount]"])
    }
    #expect(try columns("MERGE dbo.Target T USING dbo.Source S ON 1=1 WHEN MATCHED THEN UPDATE SET T.MIKTAR=S.Amount; SELECT S.§ FROM dbo.Target X;").isEmpty)
    #expect(try columns("MERGE dbo.Target T USING dbo.Source S ON 1=1 WHEN MATCHED THEN UPDATE SET T.MIKTAR=S.Amount;\nGO\nSELECT T.§ FROM dbo.Source S;").isEmpty)
    #expect(try columns("MERGE dbo.Target T USING dbo.Source S ON T.§=S.Stock WHEN MATCHED THEN DELETE;").count==5)
  }
  @Test func unavailableMergeSourcesAreNotInventedAndUsingCanCompleteRelations() throws {
    #expect(try columns("MERGE dbo.Target T USING (SELECT T.§ FROM dbo.Source X) S ON 1=1 WHEN MATCHED THEN DELETE;").isEmpty)
    #expect(try columns("MERGE dbo.Target T USING dbo.Source S ON 1=1 WHEN NOT MATCHED BY SOURCE AND S.§=1 THEN DELETE;").isEmpty)
    #expect(try columns("MERGE dbo.Target T USING dbo.Source S ON 1=1 WHEN NOT MATCHED THEN INSERT (STOK_KODU) VALUES(T.§);").isEmpty)
    #expect(try analyze("MERGE dbo.Target T USING Sou§ ON 1=1 WHEN MATCHED THEN DELETE;").suggestions.contains {$0.kind == .table && $0.text.contains("Source")})
    #expect(try analyze("MERGE Tar§ USING dbo.Source S ON 1=1 WHEN MATCHED THEN DELETE;").suggestions.contains {$0.kind == .table && $0.text.contains("Target")})
  }

}
