import Foundation
import Testing
@testable import SQLServerKit

struct InsertColumnCompletionTests {
  private let symbols = [CatalogSymbol(schema: "dbo", name: "Products", columns: ["STOK", "CARI", "AD", "ExternalCode"]),
    CatalogSymbol(schema: "dbo", name: "Other", columns: ["OtherID"])]
  private func analyze(_ marked: String) throws -> SQLIntelligence.Analysis {
    let caret = (marked as NSString).range(of: "§").location
    return try SQLIntelligence.analyze(source: marked.replacingOccurrences(of: "§", with: ""), caret: caret,
      catalog: .init(snapshot: .init(symbols: symbols)), verified: true)
  }
  @Test func insertColumnListsContinueAfterEveryCommaAndOnlyOfferUnusedTargetColumns() throws {
    for sql in ["INSERT INTO dbo.Products (STOK, §)", "INSERT dbo.Products (STOK, §",
      "INSERT TOP (10) INTO [dbo].[Products] WITH(TABLOCK) (STOK, §) VALUES (1, 2)",
      "INSERT INTO Products (STOK, -- next\n §)"] {
      let result = try analyze(sql)
      #expect(result.objectCompletion)
      #expect(result.suggestions.map(\.text) == ["[CARI]", "[AD]", "[ExternalCode]"], "\(sql)")
      #expect(result.suggestions.allSatisfy { $0.kind == .column })
    }
    #expect(try analyze("INSERT INTO dbo.Products (STOK, ca§, AD) VALUES (1,2,3)").suggestions.map(\.text) == ["[CARI]"])
    #expect(try analyze("INSERT INTO dbo.Products (STOK, CARI, od§)").suggestions.map(\.text) == ["[ExternalCode]"])
    #expect(try analyze("INSERT INTO Other (OtherID); INSERT INTO Products (STOK, §)").suggestions.map(\.text) == ["[CARI]", "[AD]", "[ExternalCode]"])
    #expect(try analyze("INSERT INTO Products (STOK, 'ca§'").suggestions.isEmpty)
    #expect(try analyze("INSERT INTO Products (STOK, -- ca§\n").suggestions.isEmpty)
  }
  @Test func localTablesAndEditingExistingColumnsRetainReplacementRanges() throws {
    let result = try analyze("CREATE TABLE #t (A int, ExternalCode int); INSERT INTO #t (A, od§)")
    #expect(result.suggestions.map(\.text) == ["[ExternalCode]"])
    let marked = "INSERT INTO Products (STOK, [CARI§], AD) VALUES (1,2,3)"
    let editing = try analyze(marked)
    #expect(editing.suggestions.map(\.text) == ["[CARI]"])
    let source = marked.replacingOccurrences(of: "§", with: "") as NSString
    #expect(source.substring(with: editing.replacement) == "[CARI]")
  }
  @Test func relationRoutineVariableAndKeywordSuggestionsMatchInteriorText() throws {
    for sql in ["SELECT * FROM odu§", "SELECT * FROM dbo.odu§", "UPDATE odu§", "INSERT INTO odu§"] {
      let label=sql.hasPrefix("SELECT") ? "[dbo].[Products] AS P":"[dbo].[Products]"
      #expect(try analyze(sql).suggestions.contains { $0.label == label }, "\(sql)")
    }
    #expect(try analyze("DECLARE @ExternalOrder int; SELECT @order§").suggestions.map(\.text) == ["@ExternalOrder"])
    #expect(try analyze("SELECT LEC§").suggestions.contains { $0.text == "SELECT" })
    let sql = "EXEC der"
    let catalog = SQLIntelligence.Catalog(snapshot: .init(symbols: [CatalogSymbol(schema: "dbo", name: "ReadOrders", columns: [], kind: "SQL_STORED_PROCEDURE")]))
    #expect(try SQLIntelligence.analyze(source: sql, caret: sql.utf16.count, catalog: catalog, verified: true).suggestions.first?.text == "[dbo].[ReadOrders]")
  }
}
