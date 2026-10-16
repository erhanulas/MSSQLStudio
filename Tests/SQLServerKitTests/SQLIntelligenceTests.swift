import Foundation
import Testing
@testable import SQLServerKit
struct SQLIntelligenceTests {
  let symbols = [CatalogSymbol(schema:"dbo",name:"Customers",columns:["CustomerID","Name","City"]),CatalogSymbol(schema:"dbo",name:"Orders",columns:["OrderID","CustomerID","Amount"]),CatalogSymbol(schema:"report",name:"CustomerSummary",columns:["Name","Total"],kind:"VIEW"),CatalogSymbol(schema:"dbo",name:"GetCustomers",columns:[],kind:"SQL_STORED_PROCEDURE")]
  func analyze(_ source: String, caret: Int? = nil, verified: Bool = true, aliases: Bool = true, date: Date = Date()) throws -> SQLIntelligence.Analysis {
    try SQLIntelligence.analyze(source:source,caret:caret ?? (source as NSString).length,catalog:.init(snapshot:.init(symbols:symbols,synchronizedAt:date)),verified:verified,automaticAliases:aliases)
  }
  func marked(_ sql: String) throws -> [String] { let value = try analyze(sql); return value.diagnostics.map { (sql as NSString).substring(with:$0.range) } }
  @Test func triggerPseudoTablesResolveColumnsAndAliasesToTheTargetTable() throws {
    for source in [
      "ALTER TRIGGER dbo.tr ON dbo.Customers AFTER UPDATE AS SELECT inserted.",
      "CREATE OR ALTER TRIGGER dbo.tr ON dbo.Customers AFTER DELETE AS SELECT D. FROM deleted AS D"
    ] {
      let caret=source.hasSuffix(".") ? source.utf16.count:(source as NSString).range(of:"D.").location+2
      let result=try analyze(source,caret:caret)
      #expect(result.suggestions.contains {$0.kind == .column && $0.label.contains("CustomerID")})
      #expect(result.referenceBindings["inserted"] == ["dbo","Customers"])
      if source.contains("AS D") {#expect(result.referenceBindings["d"] == ["dbo","Customers"])}
    }
    let source="DECLARE @city nvarchar(20); EXEC dbo.GetCustomers @Name = @ci"
    #expect(try analyze(source).suggestions.contains {$0.text == "@city"})
  }
  @Test func explorerAliasBindingsRespectNestedAndSiblingStatementScopes() throws {
    let source="SELECT c.Name, (SELECT c.Amount FROM dbo.Orders c) FROM dbo.Customers c; SELECT c.City FROM report.CustomerSummary c;"
    let outer=try analyze(source,caret:(source as NSString).range(of:"c.Name").location+2)
    let inner=try analyze(source,caret:(source as NSString).range(of:"c.Amount").location+2)
    let sibling=try analyze(source,caret:(source as NSString).range(of:"c.City").location+2)
    #expect(outer.referenceBindings["c"]==["dbo","Customers"])
    #expect(inner.referenceBindings["c"]==["dbo","Orders"])
    #expect(sibling.referenceBindings["c"]==["report","CustomerSummary"])
    let literal=try analyze("SELECT 'c.Name' FROM dbo.Customers c",caret:12)
    #expect(literal.referenceBindings.isEmpty)
  }
  @Test func stockColumnsLeadHintedPredicatesAndWideTablesKeepTheirSlots() throws {
    let columns=(0..<110).map {String(format:"STOK_%03d",$0)}
    let catalog=SQLIntelligence.Catalog(snapshot:.init(symbols:[
      CatalogSymbol(schema:"dbo",name:"TBLSTSABIT",columns:columns),
      CatalogSymbol(schema:"dbo",name:"STOK_LOOKUP",columns:[],kind:"SQL_SCALAR_FUNCTION")]))
    for clause in ["WHERE", "ON", "GROUP BY", "ORDER BY", "HAVING"] {
      let sql="SELECT * FROM TBLSTSABIT AS T WITH(NOLOCK) "+clause+" STOK_"
      let result=try SQLIntelligence.analyze(source:sql,caret:sql.utf16.count,catalog:catalog,verified:true)
      #expect(result.suggestions.count == 100)
      #expect(result.suggestions.prefix(99).allSatisfy {$0.kind == .column && $0.text.hasPrefix("[T].[STOK_")})
    }
  }
  @Test func aliasesDoNotHideExpressionContextAndOperandsDoNotSuggestColumns() throws {
    let sql="SELECT Name AS DisplayName, COA FROM dbo.Customers AS c"
    let result=try analyze(sql,caret:(sql as NSString).range(of:"COA").location+3)
    #expect(result.suggestions.contains {$0.text == "COALESCE()" && $0.caretOffset == 9})
    for sql in ["SELECT Name AS Na FROM dbo.Customers c", "SELECT Name FR FROM dbo.Customers c"] {
      let marker=sql.contains(" AS ") ? "Na FROM":"FR FROM"
      let caret=(sql as NSString).range(of:marker).location+2
      #expect(try analyze(sql,caret:caret).suggestions.allSatisfy {$0.kind != .column && $0.kind != .function})
    }
  }
  @Test func relationAliasesAreVisibleAndRespectThePreferenceAndExistingAliases() throws {
    let withAlias=try #require(analyze("SELECT * FROM Cus").suggestions.first)
    #expect(withAlias.label.contains(" AS C") && withAlias.text.contains(" AS C"))
    let withoutAlias=try #require(analyze("SELECT * FROM Cus",aliases:false).suggestions.first)
    #expect(!withoutAlias.label.contains(" AS ") && !withoutAlias.text.contains(" AS "))
    let source="SELECT * FROM Cus AS Existing"
    let caret=(source as NSString).range(of:"Cus").location+3
    #expect(try analyze(source,caret:caret).suggestions.allSatisfy {!$0.label.contains(" AS ")})
    let comma=try analyze("SELECT * FROM dbo.Orders O, Cus")
    #expect(comma.suggestions.contains {$0.kind == .table && $0.label.contains(" AS C")})
  }
  @Test func typedPresentationMetadataNeverChangesCompletionSQL() throws {
    let table=try #require(analyze("SELECT * FROM Cus").suggestions.first)
    #expect(table.kind == .table && table.label == "[dbo].[Customers] AS C")
    #expect(table.text == "[dbo].[Customers] AS C" && table.detail == table.text)
    let view=try #require(analyze("SELECT * FROM report.Cus").suggestions.first)
    #expect(view.kind == .view && view.text == "[CustomerSummary] AS CS")
    let procedure=try #require(analyze("EXEC Customers").suggestions.first)
    #expect(procedure.kind == .procedure && procedure.text == "[dbo].[GetCustomers]")
    let source="SELECT c.Na FROM dbo.Customers c"
    let column=try #require(analyze(source,caret:NSMaxRange((source as NSString).range(of:"c.Na"))).suggestions.first)
    #expect(column.kind == .column && column.text == "[Name]" && column.detail == "dbo.Customers")
    #expect(try analyze("SEL").suggestions.first {$0.text == "SELECT"}?.kind == .keyword)
    #expect(try analyze("COU").suggestions.first {$0.text == "COUNT()" && $0.caretOffset == 6}?.kind == .function)
  }
  @Test func missingObjectsAndColumns() throws {
    #expect(try marked("SELECT c.Name, c.NotAColumn FROM dbo.Customers AS c; ") == ["NotAColumn"])
    #expect(try marked("SELECT * FROM dbo.DoesNotExist; ") == ["dbo.DoesNotExist"])
    #expect(try marked("SELECT Name, Nope FROM dbo.Customers; ") == ["Nope"])
    #expect(try marked("SELECT c.Name, o.Amount FROM dbo.Customers c JOIN dbo.Orders o ON c.CustomerID=o.CustomerID; ").isEmpty)
  }
  @Test func implicitOutputAliasesAndCommaSourcesAvoidFalseWarnings() throws {
    #expect(try marked("SELECT Name DisplayName, 1 Counter, 'literal' Description, GETDATE() Stamp FROM dbo.Customers; ").isEmpty)
    #expect(try marked("SELECT Amount FROM dbo.Customers c, dbo.Orders o; ").isEmpty)
  }
  @Test func suppressUncertainAndEditingReferences() throws {
    for sql in ["SELECT * FROM otherdb.dbo.Missing; ","SELECT * FROM sys.tables; ","SELECT * FROM #temp; ","USE Other; SELECT * FROM Missing; "] { #expect(try marked(sql).isEmpty) }
    #expect(try analyze("SELECT * FROM Missing").diagnostics.isEmpty)
    #expect(try analyze("SELECT * FROM Missing; ",verified:false).diagnostics.isEmpty)
    #expect(try analyze("SELECT * FROM Missing; ",date:Date(timeIntervalSinceNow:-301)).diagnostics.isEmpty)
    #expect(try marked("SELECT 'Missing', c.Name /* c.Nope */ FROM dbo.Customers c; ").isEmpty)
  }
  @Test func objectCompletionAliasAndSchemaPrefix() throws {
    #expect(try analyze("SELECT * FROM Cus").suggestions.first?.text == "[dbo].[Customers] AS C")
    #expect(try analyze("SELECT * FROM dbo.Cus").suggestions.first?.text == "[Customers] AS C")
    #expect(try analyze("SELECT * FROM Cus",aliases:false).suggestions.first?.text == "[dbo].[Customers]")
    let sql = "SELECT * FROM Cus AS existing;"
    #expect(try analyze(sql,caret:NSMaxRange((sql as NSString).range(of:"Cus"))).suggestions.first?.text == "[dbo].[Customers]")
    #expect(try analyze("SELECT * FROM dbo.Customers c JOIN Cus").suggestions.first?.text == "[dbo].[Customers] AS C2")
    #expect(try analyze("EXEC Get").suggestions.map(\.text) == ["[dbo].[GetCustomers]"])
  }
  @Test func execCompletionContainsProcedureNamesAndIgnoresUnrelatedRelations() throws {
    let crowded=(0..<500).map {CatalogSymbol(schema:"dbo",name:"CustomerTable\($0)",columns:[])}
    let procs=[CatalogSymbol(schema:"dbo",name:"CustomerFirst",columns:[],kind:"SQL_STORED_PROCEDURE"),CatalogSymbol(schema:"dbo",name:"usp_GetCustomerDetails",columns:[],kind:"SQL_STORED_PROCEDURE"),CatalogSymbol(schema:"other",name:"GetCustomer",columns:[],kind:"CLR_STORED_PROCEDURE")]
    let catalog=SQLIntelligence.Catalog(snapshot:.init(symbols:crowded+procs))
    func result(_ sql:String) throws -> SQLIntelligence.Analysis {try SQLIntelligence.analyze(source:sql,caret:(sql as NSString).length,catalog:catalog,verified:true)}
    #expect(try result("EXEC customer").suggestions.map(\.text) == ["[dbo].[CustomerFirst]","[other].[GetCustomer]","[dbo].[usp_GetCustomerDetails]"])
    #expect(try result("EXECUTE dbo.customer").suggestions.map(\.text) == ["[CustomerFirst]","[usp_GetCustomerDetails]"])
    #expect(try result("EXEC @returnCode = dbo.details").suggestions.map(\.text) == ["[usp_GetCustomerDetails]"])
    #expect(try result("EXEC ").procedureCompletion && result("EXEC ").suggestions.count == 3)
    #expect(try !result("EXEC @sql").procedureCompletion)
    #expect(try result("EXEC ('Customer").suggestions.isEmpty)
    #expect(try result("-- EXEC customer").suggestions.isEmpty)
    #expect(try result("SELECT * FROM details").suggestions.isEmpty)
    #expect(try result("EXEC OtherDB.dbo.customer").suggestions.isEmpty)
  }
  @Test func execCompletionIncludesFunctionsWithKindsSchemaAndContainsMatching() throws {
    let relations=(0..<500).map {CatalogSymbol(schema:"dbo",name:"CustomerTable\($0)",columns:[])}
    let functions=["SQL_SCALAR_FUNCTION","SQL_INLINE_TABLE_VALUED_FUNCTION","SQL_TABLE_VALUED_FUNCTION","CLR_SCALAR_FUNCTION","CLR_TABLE_VALUED_FUNCTION"].enumerated().map {
      CatalogSymbol(schema:$0.offset == 4 ? "other":"dbo",name:"ufn_GetCustomer\($0.offset)",columns:[],kind:$0.element)
    }
    let catalog=SQLIntelligence.Catalog(snapshot:.init(symbols:relations+functions+[
      CatalogSymbol(schema:"dbo",name:"CustomerProcedure",columns:[],kind:"SQL_STORED_PROCEDURE")]))
    func result(_ sql:String) throws -> SQLIntelligence.Analysis {try SQLIntelligence.analyze(source:sql,caret:(sql as NSString).length,catalog:catalog,verified:true,automaticAliases:true,automaticNoLock:true)}
    let items=try result("EXEC CUSTOMER").suggestions
    #expect(items.count == 3 && items.first?.kind == .procedure)
    #expect(items.dropFirst().allSatisfy {$0.kind == .function && !$0.text.contains(" AS ") && !$0.text.contains("NOLOCK")})
    #expect(try result("EXECUTE dbo.Customer").suggestions.count == 3)
    #expect(try result("EXEC @status = [other].Customer").suggestions.isEmpty)
    #expect(try result("EXEC dbo.ufn").suggestions.first?.text == "[ufn_GetCustomer0]")
    #expect(try result("EXEC ").suggestions.count == 3)
    #expect(try result("SELECT * FROM ufn").suggestions.map(\.text)==["[dbo].[ufn_GetCustomer1]()","[dbo].[ufn_GetCustomer2]()","[other].[ufn_GetCustomer4]()"])
    for sql in ["EXEC @sql", "EXEC ('Customer", "-- EXEC Customer", "EXEC OtherDB.dbo.Customer"] {
      #expect(try result(sql).suggestions.isEmpty, "\(sql)")
    }
    let crowded=SQLIntelligence.Catalog(snapshot:.init(symbols:(0..<200).map {CatalogSymbol(schema:"dbo",name:String(format:"ufn_%03d",$0),columns:[],kind:"SQL_SCALAR_FUNCTION")}))
    #expect(try crowded.matchingRoutines("ufn",limit:500).count == 100)
    #expect(try crowded.matchingRoutines("ufn",limit:0).isEmpty)
  }
  @Test func columnCompletionUsesAliasAndStatementScope() throws {
    let sql = "SELECT c. FROM dbo.Customers AS c JOIN dbo.Orders AS o ON c.CustomerID=o.CustomerID;"
    let value = try analyze(sql,caret:9)
    #expect(Set(value.suggestions.map(\.text)) == Set(["[CustomerID]","[Name]","[City]"]))
    let bare = "SELECT Na FROM dbo.Customers c;"
    #expect(try analyze(bare,caret:9).suggestions.first?.text == "[c].[Name]")
    let separate = "SELECT * FROM dbo.Customers c; SELECT c. FROM dbo.Orders o;"
    #expect(try analyze(separate,caret:(separate as NSString).range(of:"c. FROM").location+2).suggestions.isEmpty)
  }
  @Test func executionContextRetainsStructuredConnectionDiagnostics() async throws {
    do {
      _ = try await TSQL.run("SELECT 1;",on:ODBCConnection())
      Issue.record("A closed connection must fail")
    } catch let error as SQLFailure {
      #expect(error.message.contains("Batch başlangıç satırı 1"))
      #expect(error.diagnostics.first?.state == "08003")
    }
  }
  @Test func columnCompletionNeverInventsAliasesForUnaliasedRelations() throws {
    let catalog=SQLIntelligence.Catalog(snapshot:.init(symbols:[
      CatalogSymbol(schema:"dbo",name:"TBLSTSABIT",columns:["STOK_KODU","STOK_ADI"]),
      CatalogSymbol(schema:"dbo",name:"Other",columns:["STOK_KODU"])],synchronizedAt:Date()))
    func complete(_ sql:String) throws -> SQLIntelligence.Analysis {
      try SQLIntelligence.analyze(source:sql,caret:(sql as NSString).length,catalog:catalog,verified:true)
    }
    for sql in ["SELECT * FROM TBLSTSABIT where STOK_", "SELECT * FROM [dbo].[TBLSTSABIT] WITH(NOLOCK) WHERE STOK_"] {
      let items=try complete(sql).suggestions.filter {$0.kind == .column}
      #expect(Set(items.map(\.text)) == ["[STOK_KODU]","[STOK_ADI]"])
      #expect(!items.contains {$0.text.contains("[T].")})
    }
    #expect(try complete("SELECT * FROM TBLSTSABIT WHERE [T].STOK_").suggestions.isEmpty)
    #expect(try complete("SELECT * FROM TBLSTSABIT T WHERE STOK_").suggestions.first?.text == "[T].[STOK_KODU]")
    #expect(try complete("SELECT * FROM TBLSTSABIT AS [T] WHERE [T].STOK_").suggestions.first?.text == "[STOK_KODU]")
    #expect(try complete("SELECT * FROM TBLSTSABIT WHERE TBLSTSABIT.STOK_").suggestions.first?.text == "[STOK_KODU]")
    let joins=try complete("SELECT * FROM dbo.TBLSTSABIT JOIN dbo.Other ON 1=1 WHERE STOK_").suggestions.filter {$0.kind == .column}
    #expect(joins.contains {$0.text == "[dbo].[TBLSTSABIT].[STOK_KODU]"})
    #expect(joins.contains {$0.text == "[dbo].[Other].[STOK_KODU]"})
    #expect(try complete("SELECT * FROM TBLSTSABIT T; SELECT * FROM TBLSTSABIT WHERE STOK_").suggestions.first?.text == "[STOK_KODU]")
  }
  @Test func unseparatedSelectsAndUnionArmsDoNotLeakAliases() throws {
    let catalog=SQLIntelligence.Catalog(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"TBLSTSABIT",columns:["STOK_KODU"])]))
    for separator in ["\n","\r\n"," ","; ","\nGO\n"," UNION ALL "," UNION "] {
      for reverse in [false,true] {
        let bare="SELECT * FROM TBLSTSABIT WHERE STOK_"
        let aliased="SELECT * FROM TBLSTSABIT T WHERE [T].[STOK_KODU] = ''"
        let sql=reverse ? bare+separator+aliased:aliased+separator+bare
        let caret=NSMaxRange((sql as NSString).range(of:"WHERE STOK_"))
        let result=try SQLIntelligence.analyze(source:sql,caret:caret,catalog:catalog,verified:true)
        #expect(result.suggestions.first?.text == "[STOK_KODU]","\(separator) reverse=\(reverse)")
      }
    }
    let sql="SELECT * FROM TBLSTSABIT WHERE [T].[STOK_KODU] = ''"
    let result=try SQLIntelligence.analyze(source:sql,caret:(sql as NSString).range(of:"[STOK_KODU]").location+6,catalog:catalog,verified:true)
    #expect(result.suggestions.isEmpty)
  }
  @Test func localCTEAndTemporaryColumns() throws {
    let cte = "WITH q AS (SELECT CustomerID AS KeyID FROM dbo.Customers) SELECT q. FROM q;"
    #expect(try analyze(cte,caret:(cte as NSString).range(of:"q. FROM").location+2).suggestions.map(\.text) == ["[KeyID]"])
    let temp = "CREATE TABLE #t (One int, Two nvarchar(20)); SELECT t. FROM #t t;"
    #expect(Set(try analyze(temp,caret:(temp as NSString).range(of:"t. FROM").location+2).suggestions.map(\.text)) == Set(["[One]","[Two]"]))
    #expect(try analyze("SELECT 'Cus").suggestions.isEmpty)
  }
  @Test func persistentSnapshotIsScopedAndKeepsColumns() async throws {
    let url = URL(fileURLWithPath:"/tmp/StudioCompletion-\(UUID()).sqlite")
    defer { for suffix in ["","-wal","-shm"] { try? FileManager.default.removeItem(atPath:url.path+suffix) } }
    let index = CatalogDiskIndex(url:url)
    try await index.saveCompletionSnapshot(scope:"a",snapshot:.init(symbols:symbols))
    let reopened = CatalogDiskIndex(url:url)
    #expect(try await reopened.completionSnapshot(scope:"b") == nil)
    #expect(try await reopened.completionSnapshot(scope:"a")?.symbols.first?.columns == ["CustomerID","Name","City"])
    #expect(try await reopened.completionSnapshot(scope:"a")?.symbols.last?.kind == "SQL_STORED_PROCEDURE")
  }
  @Test func largeCatalogHasBoundedSuggestions() throws {
    let large = (0..<25_000).map { CatalogSymbol(schema:"dbo",name:"Table\($0)",columns:["ID","Name","Amount","CreatedAt","Active"]) }
    let start = Date()
    let catalog = SQLIntelligence.Catalog(snapshot:.init(symbols:large))
    let result = try SQLIntelligence.analyze(source:"SELECT * FROM Table24",caret:21,catalog:catalog,verified:true)
    #expect(result.suggestions.count <= 100)
    #expect(!result.suggestions.isEmpty)
    #expect(Date().timeIntervalSince(start) < 10)
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func liveReadOnlyCatalogSnapshotAndWarmDisk() async throws {
    let password = try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let url = URL(fileURLWithPath:"/tmp/StudioLiveCompletion-\(UUID())/catalog.sqlite")
    defer { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url:url), service = SQLCatalogService(index:disk)
    let profile = ServerProfile(trustCertificate:true)
    let live = try await service.refresh(profile:profile,password:password,database:"master",force:true)
    #expect(live.fresh)
    let reopened = SQLCatalogService(index:CatalogDiskIndex(url:url))
    let warm = try #require(try await reopened.cached(profile:profile,database:"master"))
    #expect(warm.snapshot.symbols.count == live.snapshot.symbols.count)
    #expect(warm.snapshot.symbols.map(\.columns) == live.snapshot.symbols.map(\.columns))
    #expect(try await reopened.cached(profile:profile,database:"another_database") == nil)
  }

  @Test func uppercaseAliasAndOptionalNoLockOnlyOnGeneratedRelationAlias() throws {
    let catalog = SQLIntelligence.Catalog(snapshot:.init(symbols:symbols))
    func values(_ sql: String, enabled: Bool = true) throws -> [String] {
      try SQLIntelligence.analyze(source:sql,caret:(sql as NSString).length,catalog:catalog,verified:true,automaticNoLock:enabled).suggestions.map(\.text)
    }
    #expect(try values("SELECT * FROM Cus").first == "[dbo].[Customers] AS C WITH(NOLOCK)")
    #expect(try values("SELECT * FROM Cus",enabled:false).first == "[dbo].[Customers] AS C")
    #expect(try values("INSERT INTO Cus").first == "[dbo].[Customers]")
    #expect(SQLIntelligence.alias(for:"TBLSTSABIT",occupied:[]) == "T")
    #expect(SQLIntelligence.alias(for:"Customers",occupied:["C"]) == "C2")
  }

}
