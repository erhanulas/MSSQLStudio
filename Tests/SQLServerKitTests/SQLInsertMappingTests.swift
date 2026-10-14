import Foundation
import Testing

@testable import SQLServerKit

struct SQLInsertMappingTests {
  @Test func explicitColumnsAndEveryValuesRowMapInBothDirections() throws {
    let sql =
      "INSERT INTO dbo.T (STOK, CARI, AD) VALUES (@stok, CONCAT(N'a,b', N'🦊'), DEFAULT), (2, 3, N'x');"
    let mapping = SQLInsertMapping(sql)
    #expect(mapping.statements.count == 1)
    let value = try #require(
      mapping.match(
        at: NSRange(location: (sql as NSString).range(of: "N'a,b'").location, length: 0)))
    #expect(value.column == "CARI" && value.ordinal == 2 && value.row == 1)
    #expect(value.value == "CONCAT(N'a,b', N'🦊')")
    #expect(
      value.ranges.map { (sql as NSString).substring(with: $0) } == [
        "CARI", "CONCAT(N'a,b', N'🦊')",
      ])
    let column = try #require(mapping.match(at: (sql as NSString).range(of: "STOK")))
    #expect(column.ranges.map { (sql as NSString).substring(with: $0) } == ["STOK", "@stok", "2"])
    #expect(column.row == nil && column.target == "dbo.T")
  }
  @Test func nestedExpressionsQuotedNamesHintsOutputAndBatchesStayScoped() throws {
    let sql =
      "INSERT TOP(1) INTO [sales].[T]]x] WITH(TABLOCK) ([Stock Code], [AD]) OUTPUT inserted.[AD] VALUES ((SELECT MAX(a) FROM dbo.U), CASE WHEN 1=1 THEN CONCAT('a,b','c') ELSE 'x' END);\nGO\nINSERT @t (X) VALUES (N'INSERT VALUES (,)' /* keep */);"
    let mapping = SQLInsertMapping(sql)
    #expect(mapping.statements.count == 2)
    let first = try #require(
      mapping.match(at: NSRange(location: (sql as NSString).range(of: "MAX").location, length: 0)))
    #expect(first.column == "Stock Code" && first.target == "[sales].[T]]x]")
    let second = try #require(
      mapping.match(
        at: NSRange(location: (sql as NSString).range(of: "N'INSERT").location + 5, length: 0)))
    #expect(second.column == "X" && second.target == "@t")
    #expect(mapping.match(at: (sql as NSString).range(of: "OUTPUT")) == nil)
  }
  @Test func selectProjectionsMapNestedExpressionsCaseAliasesAndUnionArms() throws {
    let sql="INSERT dbo.T(A,B) SELECT TOP(2) x AS X, CASE WHEN x=1 THEN CONCAT(N'a,b',N'🦊') ELSE (SELECT MAX(y) FROM U) END AS Y FROM S UNION ALL SELECT 2,3; SELECT 4,5;"
    let mapping=SQLInsertMapping(sql)
    let match=try #require(mapping.match(at:(sql as NSString).range(of:"CONCAT")))
    #expect(match.column=="B" && match.ordinal==2 && match.sourceKind == .select)
    #expect(match.value.hasPrefix("CASE") && match.value.hasSuffix("AS Y"))
    let a=try #require(mapping.match(at:(sql as NSString).range(of:"A")))
    #expect(a.ranges.map {(sql as NSString).substring(with:$0)} == ["A","x AS X","2"])
    #expect(mapping.match(at:(sql as NSString).range(of:"SELECT 4")) == nil)
    for text in ["INSERT T(A,B) SELECT s.*,x FROM S s", "INSERT T(A,B) SELECT x,y,z FROM S", "INSERT T(A,B) SELECT x, CASE WHEN 1=1 THEN 2", "INSERT T(A,B) SELECT x,y FROM S UNION SELECT * FROM S"] {
      #expect(SQLInsertMapping(text).statements.isEmpty)
    }
  }
  @Test func ambiguousOrImplicitMappingsAreNeverGuessed() {
    for sql in [
      "INSERT dbo.T VALUES (1,2)", "INSERT dbo.T(A,B) SELECT * FROM dbo.U",
      "INSERT dbo.T(A,B) SELECT x FROM dbo.U",
      "INSERT dbo.T(A) VALUES (1,2)", "-- INSERT dbo.T(A) VALUES(1)",
      "SELECT N'INSERT dbo.T(A) VALUES(1)'", "INSERT dbo.T(A) DEFAULT VALUES",
    ] {
      #expect(SQLInsertMapping(sql).statements.isEmpty, "\(sql)")
    }
    #expect(
      SQLInsertMapping("INSERT dbo.T(A) VALUES(1)").match(
        at: NSRange(location: NSNotFound, length: 1)) == nil)
    let empty = "INSERT dbo.T(A,B) VALUES(1,)"
    #expect(
      SQLInsertMapping(empty).match(at: NSRange(location: empty.utf16.count - 1, length: 0))?.column
        == "B")
    #expect(SQLInsertMapping(String(repeating: " ", count: 250001)).statements.isEmpty)
  }
}
