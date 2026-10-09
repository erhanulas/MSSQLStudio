import AppKit
import SQLServerKit
import Testing

@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ResultGridUITests {
  @Test func newestFilterWinsAndColumnRulesAreIndependent() async throws {
    _ = NSApplication.shared
    let spool = try ResultSpool()
    var rows = Rows(fields: [Field("ID", type: 4), Field("Value")])
    rows.values = try spool.append((0..<10_000).map { [String($0), $0 % 2 == 0 ? "even" : "odd"] })
    let controller = ResultController()
    controller.setPageSize(0)
    controller.update(rows)
    #expect(controller.table.enclosingScrollView?.usesPredominantAxisScrolling == true)
    var first = ColumnRule()
    first.operation = .greater
    first.first = "5000"
    try controller.setRule(first, column: 0)
    var second = ColumnRule()
    second.choices = [.text("even")]
    try controller.setRule(second, column: 1)
    controller.filter = "odd"
    controller.filter = "even"
    for _ in 0..<250 where controller.isProcessing { try await Task.sleep(for: .milliseconds(20)) }
    #expect(!controller.isProcessing)
    #expect(controller.visibleCount == 2499)
    #expect(controller.visibleIndices?.first == 5002)
    #expect(controller.rules.count == 2)
    #expect(controller.result.values.count == 10_000)
    try controller.setRule(ColumnRule(), column: 0)
    try controller.setRule(ColumnRule(), column: 1)
    controller.filter = ""
    #expect(controller.visibleIndices == nil)
    #expect(controller.table.numberOfRows == 10_000)
    #expect(controller.rules.isEmpty)
    #expect(controller.result.values.diskBacked)
  }
  @Test func millionRowsNativeScrollBenchmark() async throws {
    guard ProcessInfo.processInfo.environment["MSSQL_GRID_BENCHMARK"] == "1" else { return }
    _ = NSApplication.shared
    let spool = try ResultSpool()
    var rows = Rows(fields: [Field("ID", type: 4), Field("Value")])
    for base in stride(from: 0, to: 1_000_000, by: 512) {
      rows.values = try spool.append(
        (base..<min(base + 512, 1_000_000)).map { [String($0), "test"] })
    }
    let controller = ResultController()
    controller.setPageSize(0)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 850, height: 480), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 850, height: 480))
    controller.view.frame = NSRect(x: 0, y: 0, width: 850, height: 480)
    controller.update(rows)
    controller.view.layoutSubtreeIfNeeded()
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(50))
    let start = Date()
    controller.table.scrollRowToVisible(999_999)
    controller.view.layoutSubtreeIfNeeded()
    var rendered = 0
    window.displayIfNeeded()
    controller.table.enumerateAvailableRowViews { _, _ in rendered += 1 }
    #expect(controller.table.numberOfRows == 1_000_000)
    #expect(!controller.responds(to:#selector(NSTableViewDelegate.tableView(_:viewFor:row:))) && rendered == 0)
    #expect(controller.table.rows(in: controller.table.visibleRect).contains(999_999))
    print(
      "GRID_NATIVE_BENCHMARK rows=1000000 scrollSeconds=\(Date().timeIntervalSince(start)) renderedRows=\(rendered)"
    )
  }

  @Test func wideGridVerticalAndHorizontalScrollBenchmark() async throws {
    guard ProcessInfo.processInfo.environment["MSSQL_GRID_BENCHMARK"] == "1" else { return }
    _ = NSApplication.shared
    let spool = try ResultSpool()
    var rows = Rows(fields: (0..<64).map { Field("Column\($0)") })
    for base in stride(from:0,to:10_000,by:256) {
      rows.values = try spool.append((base..<min(base+256,10_000)).map { row in (0..<64).map { column in "\(row):\(column) · İstanbul" } })
    }
    let controller = ResultController(); controller.setPageSize(0)
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:850,height:480),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false; defer { window.close() }
    window.contentViewController = controller
    window.setContentSize(NSSize(width:850,height:480))
    controller.view.frame = NSRect(x:0,y:0,width:850,height:480)
    controller.update(rows)
    controller.view.layoutSubtreeIfNeeded(); window.orderFront(nil)
    try await Task.sleep(for:.milliseconds(30))
    var times: [Double] = []
    for step in 0..<80 {
      let start = Date()
      controller.table.scrollRowToVisible(step*120)
      controller.table.scrollColumnToVisible(step%64+1)
      controller.view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
      controller.table.display()
      times.append(Date().timeIntervalSince(start))
    }
    var rendered = 0; controller.table.enumerateAvailableRowViews { _,_ in rendered += 1 }
    #expect(!controller.responds(to:#selector(NSTableViewDelegate.tableView(_:viewFor:row:))) && rendered == 0)
    #expect(controller.table.enclosingScrollView!.contentView.bounds.minX > 0)
    print("GRID_WIDE_BENCHMARK rows=10000 columns=64 moves=80 totalSeconds=\(times.reduce(0,+)) p95Seconds=\(times.sorted()[75]) renderedRows=\(rendered)")
  }

}
