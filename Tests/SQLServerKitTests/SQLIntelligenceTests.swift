import Foundation
import Testing
@testable import SQLServerKit
struct SQLIntelligenceTests {
  let symbols = [CatalogSymbol(schema:"dbo",name:"Customers",columns:["CustomerID","Name","City"]),CatalogSymbol(schema:"dbo",name:"Orders",columns:["OrderID","CustomerID","Amount"]),CatalogSymbol(schema:"report",name:"CustomerSummary",columns:["Name","Total"],kind:"VIEW"),CatalogSymbol(schema:"dbo",name:"GetCustomers",columns:[],kind:"SQL_STORED_PROCEDURE")]
  func analyze(_ source: String, caret: Int? = nil, verified: Bool = true, aliases: Bool = true, date: Date = Date()) throws -> SQLIntelligence.Analysis {
    try SQLIntelligence.analyze(source:source,caret:caret ?? (source as NSString).length,catalog:.init(snapshot:.init(symbols:symbols,synchronizedAt:date)),verified:verified,automaticAliases:aliases)
  }
  func marked(_ sql: String) throws -> [String] { let value = try analyze(sql); return value.diagnostics.map { (sql as NSString).substring(with:$0.range) } }
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
  @Test func columnCompletionUsesAliasAndStatementScope() throws {
    let sql = "SELECT c. FROM dbo.Customers AS c JOIN dbo.Orders AS o ON c.CustomerID=o.CustomerID;"
    let value = try analyze(sql,caret:9)
    #expect(Set(value.suggestions.map(\.text)) == Set(["[CustomerID]","[Name]","[City]"]))
    let bare = "SELECT Na FROM dbo.Customers c;"
    #expect(try analyze(bare,caret:9).suggestions.first?.text == "[c].[Name]")
    let separate = "SELECT * FROM dbo.Customers c; SELECT c. FROM dbo.Orders o;"
    #expect(try analyze(separate,caret:(separate as NSString).range(of:"c. FROM").location+2).suggestions.isEmpty)
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
