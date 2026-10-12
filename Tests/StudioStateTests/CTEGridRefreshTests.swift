import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct CTEGridRefreshTests {
  private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
  private func readDocument(database: String = "MASTER") -> QueryDocument {
    let server = ConnectedServer(profile: ServerProfile(visibleDatabases: []), password: "")
    // Even SQLSTATE08 checks use this fixture, never the real Explorer session.
    server.healthCheckFixture = {}
    let doc = QueryDocument(server: server, database: database, title: "Probe fixture")
    doc.state = .ready; doc.sql = "SELECT 1;"
    doc.executionFixture = { _, _ in
      var output = Execution(); output.results = [Rows(fields: [Field("n")], values: [["1"]])]; return output
    }
    return doc
  }
  private func probe(transaction: Int = 0, database: String) -> Execution {
    var output = Execution(); output.results = [Rows(values: [[String(transaction), database]])]; return output
  }
  private func refreshButton(_ controller: QueryController) throws -> NSButton {
    try #require(descendants(controller.view).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "refreshResults" })
  }
  private func expectDisabledExplanation(_ doc: QueryDocument, _ controller: QueryController, containing text: String) throws {
    controller.update()
    let refresh = try refreshButton(controller), reason = try #require(doc.refreshDisabledReason)
    #expect(!doc.canRefresh && !refresh.isEnabled && reason.contains(text))
    #expect(refresh.toolTip == "Sonuçları yenile · " + reason && refresh.accessibilityHelp() == refresh.toolTip)
    #expect(refresh.accessibilityLabel() == "Sonuçları yenile")
  }

  @Test func postExecutionProbeBindsFullMonitoringReadToCanonicalDatabase() async throws {
    _ = NSApplication.shared
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/ParameterizedMonitoring.sql")
    let script = "SET NOCOUNT ON;\n" + (try String(contentsOf: fixture, encoding: .utf8))
    // An empty visible list keeps all asynchronous metadata work offline.
    let server = ConnectedServer(profile: ServerProfile(visibleDatabases: []), password: "")
    let doc = QueryDocument(server: server, database: "MASTER", title: "Session identity")
    doc.state = .ready; doc.sql = script
    var executions = 0, probes = 0
    doc.executionFixture = { sql, _ in
      #expect(sql == script); executions += 1
      var output = Execution(); output.results = [Rows(fields: [Field("Sid")], values: [["kill 72"]])]
      return output
    }
    doc.sessionProbeFixture = { sql, limits in
      #expect(sql == "SELECT @@TRANCOUNT, DB_NAME();" && limits.rows == 1 && limits.timeout == 5)
      probes += 1
      var output = Execution(); output.results = [Rows(values: [["0", "master"]])]; return output
    }
    let controller = QueryController(document: doc); _ = controller.view
    doc.selectedRange = NSRange(location: 0, length: 0)
    doc.execute(); await doc.task?.value; controller.update()
    let refresh = try #require(descendants(controller.view).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "refreshResults" })
    #expect(executions == 1 && probes == 1 && doc.lastExecutionSucceeded && doc.state == .ready)
    #expect(doc.database == "master" && doc.lastExecutedDatabase == "master")
    #expect(doc.canRefresh && refresh.isEnabled)
    #expect(NSApp.sendAction(try #require(refresh.action), to: refresh.target, from: refresh))
    await doc.task?.value; controller.update()
    #expect(executions == 2 && probes == 2 && doc.canRefresh && refresh.isEnabled)
    #expect(refresh.accessibilityLabel() == "Sonuçları yenile" && refresh.accessibilityHelp() == refresh.toolTip)
  }

  @Test func postProbeTracksActualSessionIdentityAndKeepsDatabaseNamesExact() async throws {
    for (requested, actual) in [("master", "master"), ("RequestedDB", "SessionDB"), ("CaseDB", "CaseDB")] {
      let doc = readDocument(database: requested)
      doc.sessionProbeFixture = { _, _ in probe(database: actual) }
      doc.execute(); await doc.task?.value
      #expect(doc.database == actual && doc.lastExecutedDatabase == actual && doc.canRefresh && doc.refreshDisabledReason == nil)
      // Distinct names stay distinct on case-sensitive SQL Server instances.
      doc.database = actual == "CaseDB" ? "casedb" : "AnotherDB"
      #expect(!doc.canRefresh && doc.refreshDisabledReason?.contains("Veritabanı değişti") == true)
      doc.database = actual; #expect(doc.canRefresh)
    }
  }

  @Test func transactionAndProbeDisconnectKeepNativeRefreshDisabledWithExplanation() async throws {
    _ = NSApplication.shared
    let doc = readDocument(), controller = QueryController(document: doc); _ = controller.view
    doc.sessionProbeFixture = { _, _ in probe(transaction: 2, database: "master") }
    doc.execute(); await doc.task?.value
    #expect(doc.lastExecutionSucceeded && doc.state == .ready && doc.transactionCount == 2 && doc.lastExecutedDatabase == "master")
    try expectDisabledExplanation(doc, controller, containing: "Açık transaction")
    doc.transactionCount = 0
    doc.sessionProbeFixture = { _, _ in
      throw SQLFailure("Offline fixture", diagnostics: [.init(state: "08S01", code: 1, message: "Disconnected fixture")])
    }
    doc.execute(); await doc.task?.value
    #expect(doc.state == .disconnected)
    try expectDisabledExplanation(doc, controller, containing: "Sorgu bağlantısı kapalı")
  }

  @Test func probeDoesNotMakeWritesUseOrFailedExecutionsRepeatable() async throws {
    _ = NSApplication.shared
    let doc = readDocument(), controller = QueryController(document: doc); _ = controller.view
    doc.sessionProbeFixture = { _, _ in probe(database: "master") }
    for sql in ["UPDATE t SET n=1; SELECT 1;", "USE master; SELECT 1;", "EXEC dbo.p;", "SET XACT_ABORT ON; SELECT 1;"] {
      doc.database = "MASTER"
      doc.execute(override: sql); await doc.task?.value
      #expect(doc.lastExecutionSucceeded && doc.database == "master" && doc.lastExecutedDatabase == "MASTER")
      try expectDisabledExplanation(doc, controller, containing: "Veritabanı değişti")
      doc.database = "MASTER"
      try expectDisabledExplanation(doc, controller, containing: "salt okunur")
    }
    doc.executionFixture = { _, _ in throw SQLFailure("Failed read fixture") }
    doc.execute(override: "SELECT 1;"); await doc.task?.value
    #expect(!doc.lastExecutionSucceeded && !doc.canRefresh)
    try expectDisabledExplanation(doc, controller, containing: "başarıyla çalıştırın")
  }

  @Test func lateProbeCannotBindOrOverwriteChangedExecutionContext() async {
    for change in 0..<3 {
      let doc = readDocument()
      let originalServer = doc.server
      let replacement = ConnectedServer(profile: ServerProfile(visibleDatabases: []), password: "")
      doc.sessionProbeFixture = { [weak doc] _, _ in
        await Task.yield()
        if change == 0 { doc?.database = "UserSelectedDB" }
        if change == 1 { originalServer.generation = UUID() }
        if change == 2 { doc?.server = replacement }
        return probe(transaction: 7, database: "master")
      }
      doc.execute(); await doc.task?.value
      #expect(doc.lastExecutionSucceeded && doc.lastExecutedDatabase == nil && !doc.canRefresh)
      #expect(doc.transactionCount == 0 && doc.database == (change == 0 ? "UserSelectedDB" : "MASTER"))
      #expect(doc.server === (change == 2 ? replacement : originalServer))
    }
  }

  @Test func disabledReasonsPreserveBusyConnectingAndDatabaseGuards() async throws {
    _ = NSApplication.shared
    let doc = readDocument(database: "master"), controller = QueryController(document: doc); _ = controller.view
    try expectDisabledExplanation(doc, controller, containing: "başarıyla çalıştırın")
    doc.execute(); await doc.task?.value
    #expect(doc.canRefresh)
    doc.database = "OtherDB"; try expectDisabledExplanation(doc, controller, containing: "Veritabanı değişti")
    doc.database = "master"; doc.state = .running; try expectDisabledExplanation(doc, controller, containing: "işlemi sürerken")
    doc.state = .connecting; try expectDisabledExplanation(doc, controller, containing: "Bağlantı kurulurken")
    doc.state = .cancelling; try expectDisabledExplanation(doc, controller, containing: "işlemi sürerken")
    doc.state = .ready; controller.update(); #expect(doc.canRefresh && doc.refreshDisabledReason == nil)
  }

  @Test func pastedParameterizedMonitoringRefreshRepeatsCompleteExecutedSnapshot() async throws {
    _ = NSApplication.shared
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/ParameterizedMonitoring.sql")
    let script = "SET NOCOUNT ON;\n" + (try String(contentsOf: fixture, encoding: .utf8))
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Monitoring refresh")
    doc.state = .ready; doc.sql = script
    doc.limits.rows = 10; doc.limits.resultSets = 4; doc.limits.totalBytes = 8192; doc.limits.timeout = 9; doc.limits.diskResults = true
    var requests: [(String, Limits)] = []
    doc.executionFixture = { sql, limits in
      requests.append((sql, limits))
      var output = Execution()
      output.results = [Rows(fields: [Field("Sid"), Field("BlockingSid"), Field("SQLText")], values: [["kill 72", "kill 71", requests.count == 1 ? "SELECT 1" : "SELECT 2"]])]
      return output
    }
    let controller = QueryController(document: doc); _ = controller.view
    doc.selectedRange = NSRange(location: 0, length: 0)
    doc.execute(); await doc.task?.value; controller.update()
    let refresh = try #require(descendants(controller.view).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "refreshResults" })
    #expect(doc.canRefresh && refresh.isEnabled && doc.lastExecutedSQL == script)
    let grid = try #require(controller.children.compactMap { $0 as? ResultController }.first)
    // Edits to filter parameters belong to the next explicit Run, not Refresh.
    doc.sql = script.replacingOccurrences(of: "@OnlyBlocking            BIT     = 0", with: "@OnlyBlocking            BIT     = 1")
    doc.selectedRange = NSRange(location: 0, length: doc.sql.utf16.count)
    #expect(NSApp.sendAction(try #require(refresh.action), to: refresh.target, from: refresh))
    #expect(doc.busy && doc.repeating && !refresh.isEnabled && grid.parent === controller)
    await doc.task?.value; controller.update()
    #expect(requests.count == 2 && requests.allSatisfy { $0.0 == script })
    #expect(requests.allSatisfy { $0.1.rows == 10 && $0.1.resultSets == 4 && $0.1.totalBytes == 8192 && $0.1.timeout == 9 && $0.1.diskResults })
    #expect(doc.canRefresh && refresh.isEnabled && doc.lastExecutedSQL == script && doc.sql != script)
    #expect(grid.parent === controller && grid.result.values[0] == ["kill 72", "kill 71", "SELECT 2"])
    doc.transactionCount = 1; controller.update(); #expect(!doc.canRefresh && !refresh.isEnabled)
    doc.transactionCount = 0; doc.database = "other"; controller.update(); #expect(!doc.canRefresh && !refresh.isEnabled)
  }

  @Test func CTERefreshUsesExecutedSelectionAndPreservesMultiResultSnapshotAndLimits() async throws {
    _ = NSApplication.shared
    let script = ";WITH c AS (SELECT 1 AS n) SELECT * FROM c; SELECT 2 AS n; SELECT 3 AS n;"
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "CTE refresh")
    doc.state = .ready
    doc.sql = "DELETE FROM never_execute;\n" + script
    doc.selectedRange = NSRange(location: doc.sql.utf16.count - script.utf16.count, length: script.utf16.count)
    doc.limits.rows = 10; doc.limits.resultSets = 6; doc.limits.totalBytes = 4096; doc.limits.timeout = 7; doc.limits.diskResults = true
    var requests: [(String, Limits)] = []
    doc.executionFixture = { sql, limits in
      requests.append((sql, limits))
      var first = Rows(fields: [Field("n", type: 4)], values: (1...10).map { [String($0)] })
      first.truncated = true // A per-result read cap must still allow all result tabs and refresh.
      var output = Execution(); output.partial = true
      output.results = [first, Rows(fields: [Field("other", type: 4)], values: [[requests.count == 1 ? "2" : "20"]])]
      if requests.count == 1 { output.results.append(Rows(fields: [Field("removed", type: 4)], values: [["3"]])) }
      return output
    }
    let controller = QueryController(document: doc); _ = controller.view
    // Loading the editor restores its own initial caret. Set the execution
    // selection afterwards, just as a user does in the loaded text view.
    doc.selectedRange = NSRange(location: doc.sql.utf16.count - script.utf16.count, length: script.utf16.count)
    doc.execute(); await doc.task?.value
    controller.update()
    let views = descendants(controller.view)
    let refresh = try #require(views.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "refreshResults" })
    let tabs = try #require(views.compactMap { $0 as? NSTabView }.first)
    #expect(doc.canRefresh && refresh.isEnabled && doc.results.count == 3 && doc.partial)
    #expect(doc.lastExecutedSQL == script)
    tabs.selectTabViewItem(withIdentifier: NSNumber(value: 1))
    let selectedGrid = try #require(controller.children.compactMap { $0 as? ResultController }.first { $0.result.fields[0].name == "other" })
    var rule = ColumnRule(); rule.operation = .greater; rule.first = "0"
    try selectedGrid.setRule(rule, column: 0)
    selectedGrid.table.tableColumns[1].width = 222
    let oldGrids = controller.children.compactMap { $0 as? ResultController }
    // Current editor text and selection are unrelated to the successful result snapshot.
    doc.sql = "UPDATE never_execute SET n=1;"; doc.selectedRange = NSRange(location: 0, length: doc.sql.utf16.count)
    #expect(NSApp.sendAction(try #require(refresh.action), to: refresh.target, from: refresh))
    #expect(doc.busy && doc.repeating && !doc.canRefresh)
    #expect(controller.children.compactMap { $0 as? ResultController }.count == 3)
    #expect(oldGrids.allSatisfy { $0.parent === controller }) // Retain existing snapshot during refresh.
    await doc.task?.value
    controller.update()
    #expect(requests.count == 2 && requests.allSatisfy { $0.0 == script })
    #expect(requests.allSatisfy { $0.1.rows == 10 && $0.1.resultSets == 6 && $0.1.totalBytes == 4096 && $0.1.timeout == 7 && $0.1.diskResults })
    #expect(doc.canRefresh && refresh.isEnabled && doc.lastExecutedSQL == script && doc.sql.hasPrefix("UPDATE"))
    #expect(doc.results.count == 2 && tabs.numberOfTabViewItems == 3)
    #expect((tabs.selectedTabViewItem?.identifier as? NSNumber)?.intValue == 1)
    #expect(selectedGrid.parent === controller && selectedGrid.rules[0]?.first == "0")
    #expect(selectedGrid.table.tableColumns[1].width == 222 && selectedGrid.result.values[0][0] == "20")
  }

  @Test func successfulCTEReadStillRequiresReadyStateSameDatabaseAndNoTransaction() async {
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "CTE context")
    doc.state = .ready; doc.sql = ";WITH c AS (SELECT 1 AS n) SELECT n FROM c; SELECT 2;"
    doc.executionFixture = { _, _ in var output = Execution(); output.results = [Rows(fields: [Field("n")], values: [["1"]])]; return output }
    #expect(!doc.canRefresh)
    doc.execute(); await doc.task?.value
    #expect(doc.canRefresh)
    doc.transactionCount = 1; #expect(!doc.canRefresh)
    doc.transactionCount = 0; doc.database = "other"; #expect(!doc.canRefresh)
    doc.database = "master"; doc.state = .disconnected; #expect(!doc.canRefresh)
    doc.state = .ready; #expect(doc.canRefresh)
    doc.executionFixture = { _, _ in throw SQLFailure("Fixture execution failed") }
    doc.execute(); await doc.task?.value
    #expect(!doc.canRefresh && !doc.lastExecutionSucceeded)
  }

  @Test func refreshButtonRemainsDisabledForSuccessfulMixedOrWritingCTEScripts() async throws {
    _ = NSApplication.shared
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Unsafe refresh")
    doc.state = .ready
    doc.executionFixture = { _, _ in var output = Execution(); output.results = [Rows(fields: [Field("n")], values: [["1"]])]; return output }
    let controller = QueryController(document: doc); _ = controller.view
    let refresh = try #require(descendants(controller.view).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "refreshResults" })
    for script in [
      ";WITH c AS (SELECT 1 AS n) DELETE FROM t; SELECT 1;",
      ";WITH c AS (SELECT 1 AS n) SELECT * INTO #new FROM c;",
      ";SELECT 1; EXEC dbo.p;", "SELECT 1\nGO 2\nSELECT 2;",
      "DECLARE @n INT=0; SELECT 1; UPDATE t SET n=1;",
      "DECLARE @n INT=0; ;WITH c AS (SELECT 1 AS n) SELECT * INTO #new FROM c;",
      "DECLARE @n INT=dbo.SideEffect(); SELECT @n;",
      "DECLARE @n TABLE(n INT); SELECT 1;",
    ] {
      doc.execute(override: script); await doc.task?.value; controller.update()
      #expect(doc.lastExecutionSucceeded && !doc.canRefresh && !refresh.isEnabled)
    }
  }
}
