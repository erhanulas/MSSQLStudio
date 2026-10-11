import Foundation
import Testing

@testable import SQLServerKit

struct LanguageTests {
  @Test func ssmsSyntaxKeepsQuotedNamesAndNumbersPlain() {
    let sql =
      "SELECT N'İstanbul', 42, @value, [SELECT], GETDATE(), sys.objects; -- green\nEXEC sp_help; DECLARE @n int;"
    let tokens = TSQL.lex(sql)
    func style(_ text: String) -> TSQL.SyntaxStyle? {
      tokens.first { $0.text == text }.map(TSQL.syntaxStyle)
    }
    #expect(style("SELECT") == .keyword)
    #expect(style("N'İstanbul'") == .string)
    #expect(style("42") == .plain)
    #expect(style("@value") == .plain)
    #expect(style("[SELECT]") == .plain)
    #expect(style("GETDATE") == .function)
    #expect(style("sys") == .systemObject)
    #expect(style("sp_help") == .procedure)
    #expect(style("int") == .keyword)
    #expect(style("-- green") == .comment)
    #expect(tokens.map(\.text).joined() == sql)
  }
  @Test func identifiersAndConnectionEscaping() throws {
    #expect(SQL.identifier("a]b") == "[a]]b]")
    #expect(SQL.literal("O'Brien") == "N'O''Brien'")
    let profile = ServerProfile(
      host: "localhost", database: "a};PWD=bad", login: "sa", trustCertificate: true)
    let string = try profile.connectionString(password: "x};UID=other")
    #expect(string.contains("Database={a}};PWD=bad};"))
    #expect(string.contains("PWD={x}};UID=other};"))
    #expect(string.contains("Encrypt=yes;"))
    #expect(throws: SQLFailure.self) { try ServerProfile(port: 0).connectionString(password: "") }
  }
  @Test func databaseVisibilityPersistsAndLegacyDecodes() throws {
    let all = [
      CatalogItem(id: 1, name: "master"), CatalogItem(id: 5, name: "İşler"),
      CatalogItem(id: 6, name: "Sales"),
    ]
    var profile = ServerProfile()
    #expect(profile.visibleItems(from: all).count == 3)
    try profile.selectDatabases(["İşler", "Sales", "missing"], available: all)
    #expect(profile.database == "İşler")
    #expect(profile.visibleItems(from: all).map(\.name) == ["İşler", "Sales"])
    let data = try JSONEncoder().encode(profile)
    #expect(try JSONDecoder().decode(ServerProfile.self, from: data) == profile)
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "visibleDatabases")
    let legacy = try JSONDecoder().decode(
      ServerProfile.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.visibleItems(from: all).count == 3)
    #expect(throws: SQLFailure.self) { try profile.selectDatabases([], available: all) }
    #expect(throws: SQLFailure.self) { try profile.selectDatabases(["missing"], available: all) }
    profile.visibleDatabases = []
    #expect(profile.visibleItems(from: all).isEmpty)
    profile.visibleDatabases = ["Sales"]
    #expect(profile.visibleItems(from: all.filter { $0.name != "Sales" }).isEmpty)
  }
  @Test func serverAppearancePersistenceAndConnectionIdentity() throws {
    var profile = ServerProfile()
    let initial = profile
    profile.name = "Production"
    profile.appearance = ServerAppearance(environment: .live, colorHex: " #ab12ef ")
    profile.database = "Sales"
    profile.visibleDatabases = ["Sales"]
    #expect(profile.hasSameConnectionSettings(as: initial))
    #expect(!profile.hasSameConnectionSettings(as: initial, includeDatabase: true))
    #expect(profile.appearance?.effectiveColorHex == "AB12EF")
    #expect(try profile.appearance?.validated().colorHex == "AB12EF")
    #expect(profile.appearance?.badge == "Canlı")
    #expect(
      try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(profile)) == profile)
    var json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    json.removeValue(forKey: "appearance")
    let legacy = try JSONDecoder().decode(
      ServerProfile.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.appearance == nil)
    #expect(
      ServerAppearance(environment: .test).effectiveColorHex
        != ServerAppearance(environment: .live).effectiveColorHex)
    #expect(
      ServerAppearance(environment: .custom, customLabel: "Reporting\nReplica").badge
        == "Reporting Replica")
    #expect(!ServerAppearance().isMarked)
    #expect(ServerAppearance(colorHex: "001122").isMarked)
    #expect(throws: SQLFailure.self) { try ServerAppearance(colorHex: "oops").validated() }
    #expect(
      ServerAppearance(environment: .attention, colorHex: "invalid").effectiveColorHex
        == ServerEnvironment.attention.defaultColorHex)
    #expect(ServerAppearance.normalizedHex("１２３４５６") == nil)
    profile.host = "other-server"
    #expect(!profile.hasSameConnectionSettings(as: initial))
  }
  @Test func kerberosOmitsCredentials() throws {
    #expect(
      !(try ServerProfile(kerberos: true).connectionString(password: "secret")).contains("PWD="))
  }
  @Test func goRespectsStringsAndNestedComments() throws {
    let script =
      "SELECT N'first\nGO\nlast';\n/* outer\nGO\n/* nested */ */\nGO 2 -- repeat\nSELECT 2;"
    let batches = try TSQL.batches(script)
    #expect(batches.count == 3)
    #expect(batches[0].text == batches[1].text)
    #expect(batches[2].line == 8)
    #expect(throws: SQLFailure.self) { try TSQL.batches("SELECT 1;\nGO 101\n") }
  }
  @Test func lexerUTF16AndEscapes() {
    let text = "SELECT [odd]]name], N'İstanbul 🦊''x' /*a/*b*/c*/ -- end"
    let tokens = TSQL.lex(text)
    #expect(tokens.map(\.text).joined() == text)
    #expect(tokens.filter { $0.kind == .string }.count == 1)
    #expect(tokens.filter { $0.kind == .comment }.count == 2)
  }
  @Test func formatPreservesLiteralsAndIdentifiers() {
    let sql = "select dbo.select, [where] from dbo.t where x=N'from select'"
    let result = TSQL.format(sql)
    #expect(result.contains("dbo.select"))
    #expect(result.contains("[where]"))
    #expect(result.contains("N'from select'"))
    #expect(result.contains("SELECT"))
    #expect(result.contains("\nFROM"))
  }
  @Test func aliasCompletion() {
    let symbols = [CatalogSymbol(schema: "dbo", name: "People", columns: ["Id", "Name"])]
    #expect(
      TSQL.completions(
        prefix: "N", before: "SELECT p.", script: "SELECT p. FROM dbo.People AS p", symbols: symbols
      ) == ["[Name]"])
  }
  @Test func tableVariableCompletion() {
    #expect(
      TSQL.completions(
        prefix: "", before: "SELECT p.",
        script: "DECLARE @t TABLE (Id int, Name nvarchar(100)); SELECT p. FROM @t p", symbols: [])
        == ["[Id]", "[Name]"])
  }
  @Test func cteAndDerivedCompletion() {
    #expect(
      TSQL.completions(
        prefix: "", before: "SELECT c.",
        script: "WITH c AS (SELECT Id AS CustomerId, Name FROM dbo.People) SELECT c. FROM c",
        symbols: []) == ["[CustomerId]", "[Name]"])
    #expect(
      TSQL.completions(
        prefix: "", before: "SELECT d.", script: "SELECT d. FROM (SELECT 1 AS Number) d",
        symbols: []) == ["[Number]"])
    #expect(
      TSQL.completions(
        prefix: "", before: "SELECT c.", script: "WITH c (A, B) AS (SELECT 1, 2) SELECT c. FROM c",
        symbols: []) == ["[A]", "[B]"])
  }
  @Test func exportsKeepNullAndDuplicateColumns() throws {
    let rows = Rows(
      fields: [Field("x"), Field("x")], values: [[nil, "=SUM(1,2)"], ["", "line\n\"quote\""]])
    let csv = Export.csv(rows)
    #expect(csv.contains("\\N"))
    #expect(csv.contains("'="))
    let json = try JSONSerialization.jsonObject(with: Export.json(rows)) as! [String: Any]
    #expect((json["columns"] as! [String]) == ["x", "x"])
    #expect((json["rows"] as! [[Any]])[0][0] is NSNull)
  }
  @Test func indexAndJobEscaping() throws {
    let index = try Scripts.index(
      table: "[dbo].[t]", name: "ix]a", keys: ["id"], included: ["value"], unique: true, filter: "")
    #expect(index.contains("[ix]]a]"))
    #expect(throws: SQLFailure.self) {
      try Scripts.index(
        table: "t", name: "i", keys: ["a"], included: ["a"], unique: false, filter: "")
    }
    let job = try Scripts.job(
      name: "O'Brien", database: "test", command: "SELECT 'x';", dailyTime: 93000)
    #expect(job.contains("N'O''Brien'"))
    #expect(job.contains("SELECT ''x'';"))
    #expect(throws: SQLFailure.self) {
      try Scripts.job(name: "job", database: "db", command: "SELECT 1", dailyTime: 240000)
    }
  }
  @Test func templateSizeAndShape() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("{\"id\":\"t\",\"name\":\"T\",\"description\":\"D\",\"sql\":\"SELECT 1\"}".utf8).write(
      to: file)
    #expect(try SQLTemplate.read(file).sql == "SELECT 1")
    try Data("{}".utf8).write(to: file)
    #expect(throws: (any Error).self) { try SQLTemplate.read(file) }
  }
  @Test func assistantSQLExtraction() {
    #expect(AssistantClient.sql(from: "Here\n```sql\nSELECT 1;\n```\nExplanation") == "SELECT 1;")
    #expect(AssistantClient.sql(from: "No SQL") == nil)
  }
  @Test func planTreeAndThreadCounters() throws {
    let xml =
      "<ShowPlanXML><RelOp NodeId='0' PhysicalOp='Select' LogicalOp='Select' EstimateRows='10' EstimatedTotalSubtreeCost='1'><RelOp NodeId='1' PhysicalOp='Scan' LogicalOp='Scan' EstimateRows='5' EstimatedTotalSubtreeCost='.1'><RunTimeCountersPerThread ActualRows='2'/><RunTimeCountersPerThread ActualRows='3'/><Warnings NoJoinPredicate='1'/></RelOp></RelOp></ShowPlanXML>"
    let plan = try ExecutionPlan.parse(xml)
    #expect(plan.operations.count == 2)
    #expect(plan.operations[1].depth == 1)
    #expect(plan.operations[1].actualRows == 5)
    #expect(!plan.operations[1].warnings.isEmpty)
  }
}

struct IntegrationToolsTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_MOCK_URL"] != nil))
  func assistantTransportAndRedirect() async throws {
    let endpoint = try #require(ProcessInfo.processInfo.environment["MSSQL_MOCK_URL"])
    let response = try await AssistantClient.request(
      endpoint: endpoint + "/chat/completions", key: "test-only-token", model: "test",
      prompt: "Generate SELECT 1")
    #expect(AssistantClient.sql(from: response) == "SELECT 1 AS Sample;")
    do {
      _ = try await AssistantClient.request(
        endpoint: endpoint + "/redirect", key: "test-only-token", model: "test", prompt: "test")
      Issue.record("Redirect should not be followed")
    } catch { #expect(error.localizedDescription.contains("HTTP 307")) }
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_KEYCHAIN_TEST"] == "1"))
  func keychainLifecycle() throws {
    let vault = ServerVault(service: "local.mssqlstudio.test." + UUID().uuidString)
    var profile = ServerProfile(name: "Keychain test", visibleDatabases: ["Sales", "İşler"])
    defer { try? vault.delete(profile.id) }
    try vault.save(profile, password: "test-only-secret")
    #expect(try vault.list().first?.password == "test-only-secret")
    #expect(try vault.list().first?.profile.visibleDatabases == ["Sales", "İşler"])
    profile.visibleDatabases = ["Sales"]
    profile.appearance = ServerAppearance(environment: .attention, colorHex: "C46A05")
    try vault.save(profile, password: "updated-test-secret")
    #expect(try vault.list().count == 1)
    #expect(try vault.list().first?.password == "updated-test-secret")
    #expect(try vault.list().first?.profile.visibleDatabases == ["Sales"])
    #expect(try vault.list().first?.profile.appearance == profile.appearance)
    try vault.delete(profile.id)
    #expect(try vault.list().isEmpty)
  }
}

struct UnusedDeclarationTests {
  private func unused(_ sql:String) -> [String] {
    TSQL.unusedDeclaredVariables(sql).map { (sql as NSString).substring(with:$0) }
  }
  @Test func commentsStringsCaseAndExactNames() {
    let sql = "DECLARE @unused int, @used int = 0, @prefix int; SELECT @USED, @prefixLong; -- @unused\nPRINT N'@unused'; SELECT [@unused];"
    #expect(unused(sql) == ["@unused","@prefix"])
    #expect(unused("DECLARE @x int; SET @x=1;").isEmpty)
    #expect(unused("DECLARE @x int; EXEC dbo.p @value=@x;").isEmpty)
    #expect(unused("DECLARE @@bad int;").isEmpty)
    #expect(unused("DECLARE @typing").isEmpty)
    #expect(unused("DECLARE @typing SELECT 1;").isEmpty)
    #expect(unused("DECLARE @x AS int;") == ["@x"])
  }
  @Test func multipleDeclarationsAndBatchIsolation() {
    #expect(unused("DECLARE @a decimal(18,2)=COALESCE(1,2), @b int, @t TABLE (a int,b int); SELECT @b;") == ["@a","@t"])
    #expect(unused("DECLARE @x int;\nGO -- next\nDECLARE @x int; SELECT @x;") == ["@x"])
    #expect(unused("DECLARE @x int;\nGO 2\nSELECT @x;") == ["@x"])
    #expect(unused("DECLARE @x int; SELECT 'GO', @x;").isEmpty)
  }
  @Test func routinesUnicodeAndHiddenReferences() {
    let sql="CREATE PROCEDURE dbo.p @input int AS BEGIN DECLARE @boş int, @used int; IF @input=1 BEGIN SELECT @used; END END;\nGO\nCREATE FUNCTION dbo.f(@input int) RETURNS int AS BEGIN DECLARE @local int; RETURN @input; END;"
    #expect(unused(sql) == ["@boş","@local"])
    let source="-- 😀\nDECLARE @değişken int;"
    #expect(unused(source) == ["@değişken"])
    #expect(TSQL.unusedDeclaredVariables(String(repeating:" ",count:250001)).isEmpty)
  }
}


@Suite struct BatchResultLimitTests {
  actor Trace {
    var budgets: [Limits] = []
    func record(_ budget: Limits) -> Int { budgets.append(budget); return budgets.count }
    func recorded() -> [Limits] { budgets }
  }
  final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var indexes: [Int] = []
    func receive(_ event: QueryEvent) {
      if case .result(let index, _) = event { lock.withLock { indexes.append(index) } }
    }
    func recorded() -> [Int] { lock.withLock { indexes } }
  }
  @Test func truncatedRowsetContinuesGOWithIndependentRowLimitAndSharedBudgets() async throws {
    var limits = Limits(); limits.rows = 2; limits.resultSets = 5; limits.totalBytes = 2048
    let trace = Trace(), events = Events()
    let result = try await TSQL.run("SELECT 1;\nGO 2\nSELECT NULL;", limits: limits, events: events.receive) { _, budget, emit in
      let call = await trace.record(budget)
      var output = Execution()
      var rows = Rows(fields: [Field("Value")], values: call < 3 ? [["1"], ["2"]] : [[nil]])
      rows.truncated = call == 1
      output.results = call == 1 ? [Rows(affected: 4), rows] : [rows]
      output.partial = rows.truncated; output.bytesRead = 100
      let index = output.results.count - 1
      emit?(.result(index, rows.fields)); emit?(.rows(index, Array(rows.values)))
      return output
    }
    let budgets = await trace.recorded()
    #expect(budgets.map(\.rows) == [2, 2, 2])
    #expect(budgets.map(\.resultSets) == [5, 3, 2])
    #expect(budgets.map(\.totalBytes) == [2048, 1948, 1848])
    #expect(events.recorded() == [1, 2, 3])
    #expect(result.results.count == 4 && result.partial && !result.stoppedEarly)
    #expect(result.results[1].truncated && !result.results[2].truncated)
    #expect(result.results[3].values[0][0] == nil)
  }
  @Test func hardStopPreventsLaterBatchesEvenAfterRowTruncation() async throws {
    let trace = Trace()
    let result = try await TSQL.run("SELECT 1;\nGO\nSELECT 2;\nGO\nSELECT 3;", limits: Limits()) { _, budget, _ in
      let call = await trace.record(budget)
      var output = Execution(); output.results = [Rows(fields: [Field("Value")], values: [["1"]])]
      output.partial = true
      output.results[0].truncated = call == 1
      output.stoppedEarly = call == 2
      return output
    }
    #expect(await trace.recorded().count == 2)
    #expect(result.partial && result.stoppedEarly && result.results.count == 2)
  }
  @Test func taskCancellationAfterTruncationNeverExecutesNextBatch() async throws {
    let trace = Trace()
    let task = Task {
      try await TSQL.run("SELECT 1;\nGO\nSELECT 2;", limits: Limits()) { _, budget, _ in
        _ = await trace.record(budget)
        var output = Execution(); output.partial = true
        var rows = Rows(fields: [Field("Value")], values: [["1"]]); rows.truncated = true
        output.results = [rows]
        withUnsafeCurrentTask { $0?.cancel() }
        return output
      }
    }
    let result = try await task.value
    #expect(await trace.recorded().count == 1)
    #expect(result.partial && result.stoppedEarly && result.results.count == 1)
  }
  @Test func sharedBudgetExhaustionStopsOnlyIfAnotherBatchRemains() async throws {
    for bytes in [false, true] {
      var limits = Limits(); limits.resultSets = bytes ? 100 : 1; limits.totalBytes = bytes ? 100 : 2048
      for sql in ["SELECT 1;", "SELECT 1;\nGO\nSELECT 2;"] {
        let trace = Trace()
        let result = try await TSQL.run(sql, limits: limits) { _, budget, _ in
          _ = await trace.record(budget)
          var output = Execution(); output.results = [Rows(fields: [Field("Value")], values: [["1"]])]
          output.bytesRead = 100; return output
        }
        #expect(await trace.recorded().count == 1)
        #expect(result.partial == sql.contains("GO"))
        #expect(result.stoppedEarly == sql.contains("GO"))
      }
    }
  }
  @Test func executionErrorAfterTruncationPreservesEarlierRowsAndStops() async throws {
    let trace = Trace()
    let result = try await TSQL.run("SELECT 1;\nGO\nTHROW 50000, 'failure', 1;\nGO\nSELECT 3;", limits: Limits()) { _, budget, _ in
      if await trace.record(budget) == 2 { throw SQLFailure("expected failure") }
      var output = Execution(); output.partial = true
      var rows = Rows(fields: [Field("Value")], values: [["0.00000000"], [nil]]); rows.truncated = true
      output.results = [rows]; return output
    }
    #expect(await trace.recorded().count == 2)
    #expect(result.partial && result.stoppedEarly && result.results.count == 1)
    #expect(result.results[0].values[0][0] == "0.00000000")
    #expect(result.messages.contains { $0.contains("expected failure") })
  }
}
