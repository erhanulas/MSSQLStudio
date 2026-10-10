import Foundation
import Testing
@testable import SQLServerKit

struct TimelineEditingTests {
  @Test func retentionUsesDaysAndPreservesLegacyHistory() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    var recent = QueryRecord(server: "S", database: "D", text: "SELECT 1", seconds: 1, status: "Başarılı")
    recent.time = now.addingTimeInterval(-6 * 86400)
    var old = recent; old.id = UUID(); old.time = now.addingTimeInterval(-8 * 86400)
    #expect(QueryHistoryPolicy.retained([old, recent], days: 7, now: now).map(\.id) == [recent.id])
    #expect(QueryHistoryPolicy.retained([old, recent], days: 30, now: now).count == 2)
    #expect(QueryHistoryPolicy.days(0) == 1)
    #expect(QueryHistoryPolicy.days(9000) == 3650)
    let legacy = try JSONEncoder().encode(recent)
    let decoded = try JSONDecoder().decode(QueryRecord.self, from: legacy)
    #expect(decoded.serverID == nil && decoded.errorMessage == nil)
    recent.text = String(repeating: "\"\n", count: 5_000_000)
    #expect(QueryHistoryPolicy.retained([recent, old], days: 30, now: now).count == 1)
  }
  @Test func provenanceRejectsUnsafeSourcesAndMapsAliasesByOrdinal() throws {
    let fields = [Field("Label"), Field("Key")]
    func result(_ values: [[String?]]) -> Execution { var result = Execution(); result.results = [Rows(values: values)]; return result }
    let rows: [[String?]] = [["Label",nil,"D","dbo","T","Name",nil,nil,"1"],["Key",nil,"D","dbo","T","Id",nil,nil,"2"]]
    let source = try ResultEditSource.decode(result(rows), fields: fields, database: "D")
    let table = TableDefinition(schema: "dbo", name: "T", columns: [.init(id:1,name:"Id",type:"int"),.init(id:2,name:"Name",type:"nvarchar(50)")], primaryKey: ["Id"])
    let projected = try source.projected(table)
    #expect(projected.columns.map(\.name) == ["Name", "Id"])
    let sql = try DataEditScripts.changes(table: projected, rows: [.init(original: ["A","1"], values: ["B","1"])])
    #expect(sql.contains("UPDATE [dbo].[T] SET [Name]"))
    #expect(sql.contains("[Id] = CONVERT(int, N'1')"))
    var remote = rows; remote[0][1] = "Remote"
    #expect(throws: SQLFailure.self) { try ResultEditSource.decode(result(remote), fields: fields, database: "D") }
    var expression = rows; expression[0][5] = nil
    #expect(throws: SQLFailure.self) { try ResultEditSource.decode(result(expression), fields: fields, database: "D") }
    var wrongDB = rows; wrongDB[1][2] = "Other"
    #expect(throws: SQLFailure.self) { try ResultEditSource.decode(result(wrongDB), fields: fields, database: "D") }
    var missing = table; missing.columns.append(.init(id:3,name:"Other"))
    #expect(throws: SQLFailure.self) { try source.projected(missing) }
    #expect(try ResultEditSource.metadata("SELECT * FROM dbo.T WHERE Name=N'JOIN'").contains("dm_exec_describe_first_result_set"))
    for query in ["SELECT * FROM t; SELECT * FROM u", "SELECT * FROM t JOIN u ON t.id=u.id", "SELECT DISTINCT * FROM t", "SELECT * INTO u FROM t", "DELETE FROM t"] {
      #expect(throws: SQLFailure.self) { try ResultEditSource.metadata(query) }
    }
  }
}

@Suite(.serialized) struct ResultEditingLiveTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func serverProvenanceUpdateAndConflictRollback() async throws {
    let password = try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let connection = ODBCConnection()
    try await connection.connect(ServerProfile(host:"localhost",port:1433,database:"master",login:"sa",trustCertificate:true), password:password)
    let name = "StudioResultEdit_" + UUID().uuidString.replacingOccurrences(of:"-",with:"")
    let qualified = "[dbo]." + SQL.identifier(name)
    do {
      _ = try await connection.execute("CREATE TABLE \(qualified) (Id int NOT NULL PRIMARY KEY, Name nvarchar(50) NULL, Version rowversion); INSERT INTO \(qualified) (Id,Name) VALUES (1,N'A'),(2,N'B');")
      let query = "SELECT Name AS Label, Id AS RowId, Version FROM \(qualified) ORDER BY Id;"
      let rows = try #require(try await connection.execute(query).results.first)
      let source = try ResultEditSource.decode(try await connection.execute(ResultEditSource.metadata(query)),fields:rows.fields,database:"master")
      let id = try #require(try await connection.execute("SELECT OBJECT_ID(\(SQL.literal(qualified)));").results.first?.values.first?.first.flatMap { $0 }.flatMap(Int.init))
      let definition = try source.projected(ObjectMetadata.decode(try await connection.execute(ObjectMetadata.table(id)),schema:"dbo",name:name))
      var first = DataEditRow(original:Array(rows.values[0]),values:Array(rows.values[0])); first.values[0] = "O'Hara"
      _ = try await connection.execute(DataEditScripts.changes(table:definition,rows:[first],expectedObjectID:id))
      #expect(try await connection.execute("SELECT Name FROM \(qualified) WHERE Id=1;").results.first?.values.first?.first == "O'Hara")
      var second = DataEditRow(original:Array(rows.values[1]),values:Array(rows.values[1])); second.values[0] = "Should rollback"
      // Row 1's original rowversion is now stale. A successful update of row 2 must roll back with it.
      await #expect(throws:SQLFailure.self) { try await connection.execute(DataEditScripts.changes(table:definition,rows:[second,first],expectedObjectID:id)) }
      #expect(try await connection.execute("SELECT Name FROM \(qualified) WHERE Id=2;").results.first?.values.first?.first == "B")
      _ = try await connection.execute("DROP TABLE \(qualified);")
      await connection.disconnect()
    } catch {
      _ = try? await connection.execute("IF @@TRANCOUNT>0 ROLLBACK; DROP TABLE IF EXISTS \(qualified);")
      await connection.disconnect(); throw error
    }
  }
}

struct RowversionOptionalTests {
  @Test func legacyAndXMLValuesUseExplicitBinaryComparisonWithoutRowversion() throws {
    let table = TableDefinition(schema:"dbo", name:"T", columns:[.init(id:1,name:"Id",type:"int"),.init(id:2,name:"Body",type:"ntext"),.init(id:3,name:"Document",type:"xml"),.init(id:4,name:"Picture",type:"image"),.init(id:5,name:"Location",type:"geography")],primaryKey:["Id"])
    let row = DataEditRow(original:["1","old","<a />","0x0102","POINT(0 0)"], values:["1","new","<a />","0x0102","POINT(0 0)"])
    let sql = try DataEditScripts.changes(table:table,rows:[row])
    #expect(sql.contains("CONVERT(nvarchar(max),[Body])"))
    #expect(sql.contains("CONVERT(nvarchar(max),[Document])"))
    #expect(sql.contains("CONVERT(varbinary(max),[Picture]) = 0x0102"))
    #expect(!sql.contains("[Location]"))
    #expect(sql.contains("IF @@ROWCOUNT <> 1"))
    #expect(!table.columns[4].editableValue)
    var inserted = DataEditRow(original:nil,values:[nil,"copy",nil,nil,nil]); inserted.touched=[1]
    #expect(try DataEditScripts.changes(table:table,rows:[inserted]).contains("INSERT INTO [dbo].[T] ([Body]) VALUES (CONVERT(nvarchar(max), N'copy'))"))
    var deleted = row; deleted.deleted = true
    #expect(try DataEditScripts.changes(table:table,rows:[deleted]).contains("DELETE FROM [dbo].[T]"))
  }
}
