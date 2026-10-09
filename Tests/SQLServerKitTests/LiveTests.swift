import Foundation
import Testing

@testable import SQLServerKit

@Suite(.serialized) struct LiveTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func connectionDiscoveryAndSelectedDatabases() async throws {
    let password = try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    var profile = ServerProfile(trustCertificate: true, visibleDatabases: [])
    #expect(try await ServerDiscovery.test(profile, password: password) == "master")
    let items = try await ServerDiscovery.databases(profile, password: password)
    #expect(items.contains { $0.name == "master" })
    try profile.selectDatabases(["master"], available: items)
    #expect(profile.visibleItems(from: items).map(\.name) == ["master"])
    // Exercise the failure path against a nonexistent login without locking a real account.
    profile.login = "StudioMissing_" + UUID().uuidString
    do {
      _ = try await ServerDiscovery.test(profile, password: "test-only-invalid-password")
      Issue.record("Nonexistent login must fail")
    } catch {
      #expect(!error.localizedDescription.contains("test-only-invalid-password"))
    }
    #expect(
      try await ServerDiscovery.test(ServerProfile(trustCertificate: true), password: password)
        == "master")
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func moduleAlterSearchAndDefinitionRollback() async throws {
    let c = try await connection()
    let name = "StudioAlter_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    do {
      _ = try await c.execute("BEGIN TRANSACTION;")
      _ = try await c.execute("CREATE PROCEDURE dbo." + SQL.identifier(name) + " AS SELECT 1 AS Sample;")
      let rows = Catalog.rows(try await c.execute(Catalog.searchObjects(name, operation: 1, folder: .procedures)))
      let item = try #require(rows.first)
      let original = try #require(try await c.execute(Catalog.definition(item.id)).results.first?.values.first?.first.flatMap { $0 })
      let edited = ModuleEditing.alter(original).replacingOccurrences(of: "SELECT 1", with: "SELECT 2")
      _ = try await c.execute(edited)
      let current = try #require(try await c.execute(Catalog.definition(item.id)).results.first?.values.first?.first.flatMap { $0 })
      #expect(current.contains("SELECT 2"))
      #expect(ModuleEditing.difference(original: original, edited: edited).contains("+ ALTER"))
      _ = try await c.execute("ROLLBACK;")
      #expect(Catalog.rows(try await c.execute(Catalog.searchObjects(name, operation: 1, folder: .procedures))).isEmpty)
      await c.disconnect()
    } catch { _ = try? await c.execute("IF @@TRANCOUNT>0 ROLLBACK;"); await c.disconnect(); throw error }
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func persistentCatalogServiceBuildAndWarmSearch() async throws {
    let password = try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let url = URL(fileURLWithPath: "/tmp").appendingPathComponent("StudioLiveIndex-" + UUID().uuidString + "/catalog.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url:url), service = CatalogIndexService(index:disk)
    let profile = ServerProfile(trustCertificate:true)
    let status = try await service.refresh(profile:profile,password:password,database:"master",force:true)
    let key = CatalogDiskIndex.scope(profile:profile,database:"master")
    let reopened = CatalogDiskIndex(url:url)
    #expect(try await reopened.status(scope:key)?.count == status.count)
    #expect(try await service.refresh(profile:profile,password:"unused-warm-cache",database:"master").synchronizedAt == status.synchronizedAt)
    let matches = try await reopened.search(scope:key,text:"",operation:0,folder:nil)
    #expect(matches.count == min(501,status.count))
  }
  private func connection() async throws -> ODBCConnection {
    guard let password = ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] else {
      throw SQLFailure("Live tests require MSSQL_TEST_PASSWORD")
    }
    let connection = ODBCConnection()
    try await connection.connect(ServerProfile(trustCertificate: true), password: password)
    return connection
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func typesLongValuesAndBinary() async throws {
    let c = try await connection()
    let sql =
      "SELECT CAST(9223372036854775807 AS bigint) AS big, CAST(12345678901234567890.123456789012345678 AS decimal(38,18)) AS exact, CAST(NULL AS nvarchar(20)) AS missing, N'' AS empty, REPLICATE(CAST(N'İ🦊' AS nvarchar(max)),3000) AS long_text, CAST(REPLICATE(CAST('ab' AS varchar(max)),3000) AS varbinary(max)) AS bytes;"
    let result = try await c.execute(sql)
    let row = try #require(result.results.first?.values.first)
    #expect(row[0] == "9223372036854775807")
    #expect(row[1] == "12345678901234567890.123456789012345678")
    #expect(row[2] == nil)
    #expect(row[3] == "")
    #expect(row[4] == String(repeating: "İ🦊", count: 3000))
    #expect(row[5] == "0x" + String(repeating: "6162", count: 3000))
    await c.disconnect()
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func batchAndMessages() async throws {
    let c = try await connection()
    let result = try await TSQL.run("PRINT N'Türkçe'; SELECT 1 AS a;\nGO 2\nSELECT 2 AS b;", on: c)
    #expect(result.results.filter { !$0.fields.isEmpty }.count == 3)
    #expect(result.messages.contains { $0.contains("Türkçe") })
    await c.disconnect()
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func cancellationAndReuse() async throws {
    let c = try await connection()
    let start = Date()
    let task = Task { try await c.execute("WAITFOR DELAY '00:00:15'; SELECT 1;") }
    try await Task.sleep(for: .milliseconds(300))
    c.cancel()
    do {
      _ = try await task.value
      Issue.record("WAITFOR should cancel")
    } catch { #expect(Date().timeIntervalSince(start) < 6) }
    let next = try await c.execute("SELECT 42;")
    #expect(next.results.first?.values.first?[0] == "42")
    await c.disconnect()
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func sessionsTransactionsAndIsolation() async throws {
    let a = try await connection()
    let b = try await connection()
    let aa = try await a.execute(
      "BEGIN TRAN; CREATE TABLE #StudioIsolation (id int); INSERT INTO #StudioIsolation VALUES (7); SELECT @@SPID, @@TRANCOUNT;"
    )
    let bb = try await b.execute(
      "SELECT @@SPID, @@TRANCOUNT, OBJECT_ID('tempdb..#StudioIsolation');")
    let ar = try #require(aa.results.last?.values.first)
    let br = try #require(bb.results.first?.values.first)
    #expect(ar[0] != br[0])
    #expect(ar[1] == "1")
    #expect(br[1] == "0")
    #expect(br[2] == nil)
    _ = try await a.execute("ROLLBACK;")
    await a.disconnect()
    await b.disconnect()
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func rowLimitAndPartialError() async throws {
    let c = try await connection()
    var limits = Limits()
    limits.rows = 10
    let result = try await TSQL.run(
      "SELECT TOP (100) object_id FROM sys.all_objects;\nGO\nSELECT 'later';", on: c, limits: limits
    )
    #expect(result.partial)
    #expect(result.results.flatMap(\.values).count == 10)
    let error = try await TSQL.run("SELECT 1;\nGO\nTHROW 50001,'expected failure',1;", on: c)
    #expect(error.partial)
    #expect(error.messages.contains { $0.contains("expected failure") })
    let next = try await c.execute("SELECT 9")
    #expect(next.results.first?.values.first?[0] == "9")
    await c.disconnect()
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func partialCellLimitRetainsRowsAndReuse() async throws {
    let c = try await connection()
    var limits = Limits()
    limits.cellBytes = 1024
    let result = try await c.execute(
      "WITH n AS (SELECT 1 AS i UNION ALL SELECT i+1 FROM n WHERE i<300) SELECT i, CASE WHEN i=270 THEN REPLICATE(CAST(N'x' AS nvarchar(max)),10000) ELSE N'ok' END AS value FROM n ORDER BY i OPTION (MAXRECURSION 0);",
      limits: limits)
    #expect(result.partial)
    #expect(result.results.first?.values.count == 269)
    #expect(result.messages.contains { $0.contains("boyut sınırı") })
    let next = try await c.execute("SELECT 42")
    #expect(next.results.first?.values.first?[0] == "42")
    await c.disconnect()
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func catalogCoverage() async throws {
    let c = try await connection()
    let dbs = Catalog.rows(try await c.execute(Catalog.databases))
    #expect(dbs.contains { $0.name == "master" })
    _ = try await c.execute(Catalog.symbols)
    for folder in [
      Folder.tables, .views, .procedures, .functions, .synonyms, .logins, .users, .roles,
      .linkedServers, .jobs, .schedules,
    ] { _ = try await c.execute(Catalog.objects(folder)) }
    for folder in [Folder.activity, .sessions, .locks, .files, .jobs, .jobHistory, .schedules] {
      _ = try await c.execute(Catalog.monitoring(folder))
    }
    await c.disconnect()
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func metadataIndexAndJobRollback() async throws {
    let c = try await connection()
    let name = "Studio_Test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    _ = try await c.execute(
      "BEGIN TRAN; CREATE TABLE dbo.\(SQL.identifier(name)) (Id int NOT NULL PRIMARY KEY, Name nvarchar(100));"
    )
    let idResult = try await c.execute("SELECT OBJECT_ID(\(SQL.literal("dbo."+name)));")
    let id = Int(try #require(idResult.results.first?.values.first?[0]))!
    for folder in [Folder.columns, .indexes, .keys, .constraints, .triggers] {
      _ = try await c.execute(Catalog.children(folder, object: id))
    }
    let index = try Scripts.index(
      table: "dbo." + SQL.identifier(name), name: "IX_Studio", keys: ["Name"], included: ["Id"],
      unique: false, filter: "")
    _ = try await c.execute(index)
    let procedure = name + "_Proc"
    _ = try await c.execute(
      "CREATE PROCEDURE dbo.\(SQL.identifier(procedure)) @Id int, @Name nvarchar(100) OUTPUT AS SELECT @Id AS Id, @Name AS Name;"
    )
    let procedureID = try await c.execute("SELECT OBJECT_ID(\(SQL.literal("dbo."+procedure)));")
    let parameters = Catalog.rows(
      try await c.execute(
        Catalog.children(
          .parameters, object: Int(try #require(procedureID.results.first?.values.first?[0]))!)))
    #expect(parameters.count == 2)
    #expect(parameters[1].detail.contains("output"))
    _ = try await c.execute("ROLLBACK;")
    let absent = try await c.execute("SELECT OBJECT_ID(\(SQL.literal("dbo."+name)));")
    #expect(absent.results.first?.values.first?[0] == nil)
    _ = try await c.execute("BEGIN TRAN;")
    let job = try Scripts.job(
      name: name, database: "master", command: "SELECT 1;", dailyTime: 90000)
    _ = try await c.execute(job)
    _ = try await c.execute("ROLLBACK;")
    let count = try await c.execute(
      "SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name=\(SQL.literal(name));")
    #expect(count.results.first?.values.first?[0] == "0")
    await c.disconnect()
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func estimatedAndActualPlan() async throws {
    let c = try await connection()
    _ = try await c.execute("SET SHOWPLAN_XML ON;")
    let estimate = try await c.execute("SELECT name FROM sys.databases;")
    _ = try await c.execute("SET SHOWPLAN_XML OFF;")
    let xml = try #require(estimate.results.first?.values.first?[0])
    #expect(!(try ExecutionPlan.parse(xml)).operations.isEmpty)
    _ = try await c.execute("SET STATISTICS XML ON;")
    let actual = try await c.execute("SELECT name FROM sys.databases;")
    _ = try await c.execute("SET STATISTICS XML OFF;")
    let actualXML = try #require(
      actual.results.flatMap(\.values).compactMap { $0.first.flatMap { $0 } }.first {
        $0.contains("<ShowPlanXML")
      })
    #expect((try ExecutionPlan.parse(actualXML)).operations.contains { $0.actualRows != nil })
    await c.disconnect()
  }
}
