import Foundation
import Testing
@testable import SQLServerKit

struct CompletionOptionsTests {
  private func complete(_ sql: String, symbols: [CatalogSymbol], caret: Int? = nil) throws -> SQLIntelligence.Analysis {
    try SQLIntelligence.analyze(source: sql, caret: caret ?? (sql as NSString).length,
      catalog: .init(snapshot: .init(symbols: symbols)), verified: true)
  }

  @Test func columnContainsMatchesPreserveActualAliasAndPreferPrefixes() throws {
    let symbols = [CatalogSymbol(schema: "dbo", name: "Products", columns: ["STOK_KODU", "KODU", "Product_Kodu_External", "Other"])]
    for (sql, expected) in [
      ("SELECT * FROM Products WHERE koDu", ["[KODU]", "[STOK_KODU]", "[Product_Kodu_External]"]),
      ("SELECT * FROM Products p WHERE koDu", ["[p].[KODU]", "[p].[STOK_KODU]", "[p].[Product_Kodu_External]"]),
      ("SELECT * FROM Products p WHERE p.koDu", ["[KODU]", "[STOK_KODU]", "[Product_Kodu_External]"])
    ] {
      #expect(try complete(sql, symbols: symbols).suggestions.filter { $0.kind == .column }.map(\.text) == expected)
    }
    #expect(try complete("SELECT * FROM Products WHERE fake.koDu", symbols: symbols).suggestions.isEmpty)
    #expect(try complete("SELECT * FROM Products WHERE 'koDu", symbols: symbols).suggestions.isEmpty)
  }

  @Test func derivedCTEAndTemporaryColumnsAlsoUseContains() throws {
    let cases = [
      "WITH q AS (SELECT 1 AS ExternalOrderId) SELECT q.Order FROM q",
      "WITH q (ExternalOrderId) AS (SELECT 1) SELECT q.Order FROM q",
      "SELECT q.Order FROM (SELECT 1 AS ExternalOrderId) q",
      "CREATE TABLE #t (ExternalOrderId int); SELECT t.Order FROM #t t",
      "DECLARE @t TABLE (ExternalOrderId int); SELECT t.Order FROM @t t"
    ]
    for sql in cases {
      let caret = NSMaxRange((sql as NSString).range(of: ".Order"))
      #expect(try complete(sql, symbols: [], caret: caret).suggestions.map(\.text) == ["[ExternalOrderId]"], "\(sql)")
    }
  }

  @Test func prefixColumnsFromLaterBindingsWinBeforeInteriorMatchesAndLimit() throws {
    let symbols = [
      CatalogSymbol(schema: "dbo", name: "A", columns: (0..<200).map { "OldCode\($0)" }),
      CatalogSymbol(schema: "dbo", name: "B", columns: ["CodeCurrent"])
    ]
    let result = try complete("SELECT * FROM A a JOIN B b ON 1=1 WHERE Code", symbols: symbols)
    #expect(result.suggestions.count == 100)
    #expect(result.suggestions.first?.text == "[b].[CodeCurrent]")
    #expect(result.suggestions.dropFirst().allSatisfy { $0.text.hasPrefix("[a].[OldCode") })
    #expect(try complete("SELECT * FROM A WHERE Missing", symbols: symbols).suggestions.isEmpty)
    #expect(try complete("SELECT * FROM ode", symbols: symbols).suggestions.isEmpty)
  }

  @Test func schemaAndBracketsAreIndependentAndPreserveTypedQualifiers() throws {
    let catalog = SQLIntelligence.Catalog(snapshot: .init(symbols: [
      CatalogSymbol(schema: "report", name: "Products", columns: ["ProductCode"])
    ]))
    func result(_ sql: String, schema: Bool, brackets: Bool) throws -> SQLIntelligence.Analysis {
      try SQLIntelligence.analyze(source: sql, caret: (sql as NSString).length,
        catalog: catalog, verified: true, automaticAliases: false,
        includeSchema: schema, quoteIdentifiers: brackets)
    }
    #expect(try result("SELECT * FROM Prod", schema: true, brackets: true).suggestions.first?.text == "[report].[Products]")
    #expect(try result("SELECT * FROM Prod", schema: true, brackets: false).suggestions.first?.text == "report.Products")
    #expect(try result("SELECT * FROM Prod", schema: false, brackets: true).suggestions.first?.text == "[Products]")
    #expect(try result("SELECT * FROM Prod", schema: false, brackets: false).suggestions.first?.text == "Products")
    #expect(try result("SELECT * FROM [report].Prod", schema: false, brackets: false).suggestions.first?.text == "Products")
    #expect(try result("SELECT * FROM report.Products p WHERE Code", schema: false, brackets: false).suggestions.first?.text == "p.ProductCode")
    #expect(try result("SELECT * FROM report.Products p WHERE p.Code", schema: false, brackets: false).suggestions.first?.text == "ProductCode")
    let suggestion = try #require(result("SELECT * FROM Prod", schema: false, brackets: false).suggestions.first)
    #expect(suggestion.label == "[report].[Products]" && suggestion.detail == "Products")
  }

  @Test func requiredIdentifierDelimitersRemainWhenOptionalBracketsAreDisabled() throws {
    let columns = ["Order", "Schema", "CONTAINS", "Table Name", "Gross]Value", "Ends]", "1stValue", "foo.bar", "@VariableLike", "#TempLike", "_Under", "Türkçe", "value$", "😀Value"]
    let catalog = SQLIntelligence.Catalog(snapshot: .init(symbols: [
      CatalogSymbol(schema: "sales area", name: "Table]Name", columns: columns)
    ]))
    let sql = "SELECT * FROM [sales area].[Table]]Name] t WHERE t."
    let result = try SQLIntelligence.analyze(source: sql, caret: (sql as NSString).length,
      catalog: catalog, verified: true, quoteIdentifiers: false)
    #expect(result.suggestions.map(\.text) == columns.map { ["_Under", "Türkçe", "value$"].contains($0) ? $0 : SQL.identifier($0) })
    let from = "SELECT * FROM [sales area].Tab"
    #expect(try SQLIntelligence.analyze(source: from, caret: (from as NSString).length,
      catalog: catalog, verified: true, automaticAliases: false, quoteIdentifiers: false).suggestions.first?.text == "[Table]]Name]")
    // Escaped terminal brackets must survive binding resolution and partial replacement.
    let ending = SQLIntelligence.Catalog(snapshot: .init(symbols: [CatalogSymbol(schema: "dbo", name: "Ends]", columns: ["Code"])]))
    let endingSQL = "SELECT * FROM [Ends]]] WHERE od"
    #expect(try SQLIntelligence.analyze(source: endingSQL, caret: (endingSQL as NSString).length,
      catalog: ending, verified: true, quoteIdentifiers: false).suggestions.first?.text == "Code")
  }

  @Test func duplicateObjectsAndScalarFunctionsRetainNecessarySchema() throws {
    let catalog = SQLIntelligence.Catalog(snapshot: .init(symbols: [
      CatalogSymbol(schema: "dbo", name: "Products", columns: []),
      CatalogSymbol(schema: "report", name: "Products", columns: []),
      CatalogSymbol(schema: "dbo", name: "ufn_Code", columns: [], kind: "SQL_SCALAR_FUNCTION"),
      CatalogSymbol(schema: "dbo", name: "usp_Code", columns: [], kind: "SQL_STORED_PROCEDURE")
    ]))
    func texts(_ sql: String) throws -> [String] {
      try SQLIntelligence.analyze(source: sql, caret: (sql as NSString).length,
        catalog: catalog, verified: true, automaticAliases: false,
        includeSchema: false, quoteIdentifiers: false).suggestions.map(\.text)
    }
    #expect(try texts("SELECT * FROM Prod") == ["dbo.Products", "report.Products"])
    #expect(try texts("EXEC Code") == ["dbo.ufn_Code", "usp_Code"])
    #expect(try texts("EXEC dbo.Code") == ["ufn_Code", "usp_Code"])
  }

  @Test func generatedAliasNoLockAndLiteralSuppressionRespectFormattingOptions() throws {
    let catalog = SQLIntelligence.Catalog(snapshot: .init(symbols: [CatalogSymbol(schema: "dbo", name: "Products", columns: ["ProductCode"])]))
    let source = "SELECT * FROM Prod"
    #expect(try SQLIntelligence.analyze(source: source, caret: (source as NSString).length,
      catalog: catalog, verified: true, automaticNoLock: true,
      includeSchema: false, quoteIdentifiers: false).suggestions.first?.text == "Products AS P WITH(NOLOCK)")
    for sql in ["SELECT 'Code", "-- Code", "SELECT * FROM Products WHERE /* Code"] {
      #expect(try SQLIntelligence.analyze(source: sql, caret: (sql as NSString).length,
        catalog: catalog, verified: true, includeSchema: false, quoteIdentifiers: false).suggestions.isEmpty)
    }
  }
}
