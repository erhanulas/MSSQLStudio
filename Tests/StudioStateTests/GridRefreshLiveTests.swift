import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct GridRefreshLiveTests {
  @Test func refreshRepeatsExecutedSelectionAndPreservesMessagesAndFilters() async throws {
    guard let password = ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] else { return }
    _ = NSApplication.shared
    let profile = ServerProfile(host: "localhost", port: 1433, database: "master", login: "sa", trustCertificate: true)
    let server = ConnectedServer(profile: profile, password: password)
    let doc = QueryDocument(server: server, database: "master", title: "Refresh test")
    let controller = QueryController(document: doc)
    _ = controller.view
    doc.connect()
    for _ in 0..<500 where doc.busy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(doc.state == .ready)
    doc.sql = "SELECT 17 AS n; SELECT 99 AS other;"
    doc.selectedRange = NSRange(location: 0, length: 15)
    doc.execute()
    for _ in 0..<500 where doc.busy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(doc.canRefresh)
    #expect(doc.results.count == 1)
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let views = descendants(controller.view)
    let tabs = try #require(views.compactMap { $0 as? NSTabView }.first)
    let refresh = try #require(views.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "refreshResults" })
    let grid = try #require(controller.children.compactMap { $0 as? ResultController }.first)
    var rule = ColumnRule(); rule.operation = .greater; rule.first = "10"
    try grid.setRule(rule, column: 0)
    grid.table.tableColumns[1].width = 222
    tabs.selectTabViewItem(withIdentifier: "messages")
    // Editor changes and a new selection must never replace the executed query snapshot.
    doc.sql = "DELETE FROM UserTable;"
    doc.selectedRange = NSRange(location: 0, length: doc.sql.utf16.count)
    #expect(NSApp.sendAction(try #require(refresh.action), to: refresh.target, from: refresh))
    for _ in 0..<500 where doc.busy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(doc.sql == "DELETE FROM UserTable;")
    #expect(doc.lastExecutedSQL == "SELECT 17 AS n;")
    #expect(doc.results.first?.values.first?.first == "17")
    #expect(tabs.selectedTabViewItem?.identifier as? String == "messages")
    #expect(grid.rules[0]?.first == "10")
    #expect(grid.table.tableColumns[1].width == 222)
    doc.execute(override: "SELECT * FROM dbo.__MSSQLStudio_nonexistent_refresh_fixture")
    for _ in 0..<500 where doc.busy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!doc.canRefresh)
    let metadata = try await doc.connection.execute("SELECT CAST(1.25 AS decimal(18,2)) AS Amount, CAST(SYSDATETIME() AS datetime2(3)) AS Moment, CAST(N'x' AS nvarchar(50)) AS Name")
    let fields = try #require(metadata.results.first).fields
    #expect(fields[0].dataType == "decimal(18,2)")
    #expect(fields[1].dataType == "datetime2(3)")
    #expect(fields[2].dataType == "nvarchar(50)")
    await doc.connection.disconnect()
    await server.metadata.disconnect()
  }
}
