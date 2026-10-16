import AppKit
import SQLServerKit
import Testing

@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct CompactLayoutTests {
  @Test func resultSelectionAndCollapsePreserveQueryAndRestoreSpace() throws {
    _ = NSApplication.shared
    let server = ConnectedServer(profile: ServerProfile(), password: "")
    let doc = QueryDocument(server: server, database: "master", title: "Layout")
    doc.sql = "SELECT 1; SELECT 2;"
    doc.state = .ready
    doc.results = [
      Rows(fields: [Field("One")], values: [["1"]]), Rows(fields: [Field("Two")], values: [["2"]]),
    ]
    doc.messages = "Two results"
    let controller = QueryController(document: doc)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 850, height: 560), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 850, height: 560))
    controller.view.frame = NSRect(x: 0, y: 0, width: 850, height: 560)
    controller.view.layoutSubtreeIfNeeded()
    controller.viewDidLayout()
    controller.view.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let views = descendants(controller.view)
    let editor = try #require(views.compactMap { $0 as? SQLTextView }.first)
    let tabs = try #require(views.compactMap { $0 as? NSTabView }.first)
    #expect(tabs.tabViewType == .noTabsNoBorder)
    #expect(views.contains { $0.accessibilityIdentifier() == "resultTabStrip" })
    #expect(tabs.numberOfTabViewItems == 3)
    tabs.selectTabViewItem(at: 1)
    #expect(tabs.selectedTabViewItem?.label == "Results 2 (1)")
    let originalHeight = try #require(editor.enclosingScrollView).frame.height
    controller.toggleResults()
    controller.view.layoutSubtreeIfNeeded()
    #expect(controller.resultsHidden)
    let split = try #require(views.compactMap { $0 as? ResultSplitView }.first)
    #expect(split.subviews.count == 1)
    #expect(split.dividerThickness == 0)
    #expect(try #require(editor.enclosingScrollView).frame.height > originalHeight + 100)
    #expect(doc.sql == "SELECT 1; SELECT 2;")
    #expect(doc.results.count == 2)
    controller.toggleResults()
    controller.view.layoutSubtreeIfNeeded()
    #expect(!controller.resultsHidden)
    #expect(abs(try #require(editor.enclosingScrollView).frame.height - originalHeight) < 3)
    #expect(tabs.selectedTabViewItem?.label == "Results 2 (1)")
    let sqlScroll=try #require(editor.enclosingScrollView)
    for position in [180.0,320.0,400.0,240.0] {
      split.setPosition(position,ofDividerAt:0)
      controller.view.layoutSubtreeIfNeeded();controller.viewDidLayout()
      #expect(abs(editor.frame.height-sqlScroll.contentView.bounds.height)<1)
      let proposed=NSRect(origin:NSPoint(x:0,y:80),size:sqlScroll.contentView.bounds.size)
      sqlScroll.contentView.scroll(to:sqlScroll.contentView.constrainBoundsRect(proposed).origin)
      #expect(abs(sqlScroll.contentView.bounds.minY)<1)
      #expect(doc.sql=="SELECT 1; SELECT 2;" && doc.results.count==2)
    }
    tabs.selectTabViewItem(at: 2)
    #expect(tabs.selectedTabViewItem?.label == "Messages")
  }
  @Test func streamedResultsHaveVisibleClickableTabsAndScrollWithoutCompression() throws {
    _ = NSApplication.shared
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Multiple results")
    doc.state = .running
    let controller = QueryController(document: doc)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 850, height: 600))
    controller.view.frame = NSRect(x: 0, y: 0, width: 850, height: 600)
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let strip = try #require(descendants(controller.view).first { $0.accessibilityIdentifier() == "resultTabStrip" } as? NSStackView)
    let tabs = try #require(descendants(controller.view).compactMap { $0 as? NSTabView }.first)
    // Include affected-row tokens and an empty SELECT, as a real SQL batch can.
    doc.results = [Rows(affected: 3), Rows(fields: [Field("First")], values: [["0.00000000"]])]
    controller.update()
    doc.results += [Rows(affected: 1), Rows(fields: [Field("Empty")]), Rows(fields: [Field("Last")], values: [[nil]])]
    doc.results[1].truncated = true
    controller.update()
    controller.view.layoutSubtreeIfNeeded()
    let buttons = strip.arrangedSubviews.compactMap { $0 as? NSButton }
    #expect(buttons.count == 4)
    #expect(buttons[0].title.contains("KISMİ"))
    #expect(!buttons[1].title.contains("KISMİ"))
    for button in buttons {
      #expect(button.frame.width >= 60)
      #expect(button.frame.height >= 20)
      let rect = strip.convert(button.bounds, from: button)
      #expect(rect.minY >= 0 && rect.maxY <= strip.bounds.height + 1)
      #expect(!button.visibleRect.isEmpty)
      button.performClick(nil)
      #expect(tabs.selectedTabViewItem?.label == button.title)
    }
    #expect(controller.children.compactMap { $0 as? ResultController }.count == 3)
    doc.state = .ready; doc.partial = true; controller.update()
    let grids = controller.children.compactMap { $0 as? ResultController }
    #expect(grids.first { $0.result.fields.first?.name == "First" }?.partial == true)
    #expect(grids.first { $0.result.fields.first?.name == "Empty" }?.partial == false)
    #expect(grids.first { $0.result.fields.first?.name == "Last" }?.partial == false)
    #expect(tabs.selectedTabViewItem?.identifier as? String == "messages")
    #expect(doc.results[1].values[0][0] == "0.00000000")
    #expect(doc.results[4].values[0][0] == nil)
    doc.results += (0..<20).map { Rows(fields: [Field("More\($0)")], values: [[String($0)]]) }
    controller.update(); controller.view.layoutSubtreeIfNeeded()
    let scroll = try #require(strip.enclosingScrollView)
    #expect(strip.bounds.width > scroll.contentView.bounds.width)
    let last = try #require(strip.arrangedSubviews.last as? NSButton)
    strip.scrollToVisible(last.frame)
    #expect(scroll.contentView.bounds.minX > 0)
    #expect(!last.visibleRect.isEmpty)
    last.performClick(nil)
    #expect(tabs.selectedTabViewItem?.label == "Messages")
  }

  @Test func sixResultsAreReplacedByOnlyTheTwoFromFastNextExecution() async throws {
    _ = NSApplication.shared
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Rerun")
    doc.state = .ready
    doc.results = (0..<6).map { Rows(fields: [Field("Old\($0)")], values: [[String($0)]]) }
    let controller = QueryController(document: doc); _ = controller.view
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let tabs = try #require(descendants(controller.view).compactMap { $0 as? NSTabView }.first)
    tabs.selectTabViewItem(withIdentifier: NSNumber(value: 5))
    let oldGrids = controller.children.compactMap { $0 as? ResultController }
    // Simulate the 50ms debounce coalescing the empty state and new rows.
    // The disconnected ODBC handle performs no network access.
    doc.changed = nil
    doc.execute(override: "SELECT 1; SELECT 2;")
    let execution = doc.task; execution?.cancel()
    doc.results = [Rows(fields: [Field("NewFirst")], values: [["0.00000000"]]), Rows(fields: [Field("NewSecond")], values: [[nil]])]
    controller.update()
    #expect(tabs.numberOfTabViewItems == 3)
    #expect((tabs.selectedTabViewItem?.identifier as? NSNumber)?.intValue == 0)
    let grids = controller.children.compactMap { $0 as? ResultController }
    #expect(grids.count == 2)
    #expect(!grids.contains { grid in oldGrids.contains { $0 === grid } })
    #expect(grids.map { $0.result.fields[0].name } == ["NewFirst", "NewSecond"])
    doc.state = .ready; controller.update()
    #expect(tabs.tabViewItems.map(\.label) == ["Results 1 (1)", "Results 2 (1)", "Messages"])
    let strip = try #require(descendants(controller.view).first { $0.accessibilityIdentifier() == "resultTabStrip" } as? NSStackView)
    #expect(strip.arrangedSubviews.count == 3)
    #expect(doc.results[0].values[0][0] == "0.00000000" && doc.results[1].values[0][0] == nil)
    await execution?.value
  }
  @Test func newExecutionRemovesOldPlanAndAffectedRowOnlyOutputShowsMessages() async throws {
    _ = NSApplication.shared
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Plan rerun")
    doc.state = .ready
    let xml = "<ShowPlanXML><RelOp NodeId='0' PhysicalOp='Select' LogicalOp='Select' EstimateRows='1'/></ShowPlanXML>"
    doc.results = [Rows(fields: [Field("Plan")], values: [[xml]]), Rows(fields: [Field("Old")], values: [["old"]])]
    let controller = QueryController(document: doc); _ = controller.view
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let tabs = try #require(descendants(controller.view).compactMap { $0 as? NSTabView }.first)
    #expect(controller.children.contains { $0 is PlanController })
    doc.changed = nil; doc.execute(override: "SELECT 1;")
    let firstExecution = doc.task; firstExecution?.cancel()
    doc.results = [Rows(fields: [Field("New")], values: [["1"]])]
    doc.state = .ready; controller.update()
    #expect(tabs.numberOfTabViewItems == 2)
    #expect(!controller.children.contains { $0 is PlanController })
    #expect(controller.children.compactMap { $0 as? ResultController }.count == 1)
    await firstExecution?.value
    doc.state = .ready; doc.execute(override: "PRINT 'done';")
    let secondExecution = doc.task; secondExecution?.cancel()
    doc.results = [Rows(affected: 2)]; doc.state = .ready; controller.update()
    #expect(tabs.numberOfTabViewItems == 1)
    #expect(tabs.selectedTabViewItem?.identifier as? String == "messages")
    #expect(controller.children.isEmpty)
    await secondExecution?.value
  }
  @Test func refreshPrunesMissingTabsButKeepsSurvivingGridAndSelection() async throws {
    _ = NSApplication.shared
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Refresh")
    doc.state = .ready
    var rows = (0..<6).map { Rows(fields: [Field("Column\($0)")], values: [[String($0)]]) }
    rows[5] = Rows(fields: [Field("Plan")], values: [["<ShowPlanXML><RelOp NodeId='0' PhysicalOp='Select' LogicalOp='Select'/></ShowPlanXML>"]])
    doc.results = rows
    let controller = QueryController(document: doc); _ = controller.view
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let tabs = try #require(descendants(controller.view).compactMap { $0 as? NSTabView }.first)
    tabs.selectTabViewItem(withIdentifier: NSNumber(value: 1))
    let grid = try #require(controller.children.compactMap { $0 as? ResultController }.first { $0.result.fields[0].name == "Column1" })
    grid.table.tableColumns[1].width = 222
    doc.changed = nil; doc.execute(override: "SELECT 1;", repeatRead: true)
    let execution = doc.task; execution?.cancel()
    controller.update()
    #expect(tabs.numberOfTabViewItems == 7) // Keep snapshot while refreshing.
    doc.results = Array(rows.prefix(2)); doc.state = .ready; controller.update()
    #expect(tabs.numberOfTabViewItems == 3)
    #expect((tabs.selectedTabViewItem?.identifier as? NSNumber)?.intValue == 1)
    #expect(grid.parent === controller && grid.table.tableColumns[1].width == 222)
    #expect(controller.children.compactMap { $0 as? ResultController }.count == 2)
    #expect(!controller.children.contains { $0 is PlanController })
    await execution?.value
  }

  @Test func executionBoundaryClearsImmediatelyAndNewStreamKeepsOnlyCurrentGrids() async throws {
    _ = NSApplication.shared
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Boundary")
    doc.state = .ready
    doc.results = (0..<6).map { Rows(fields: [Field("Old\($0)")], values: [[String($0)]]) }
    let controller = QueryController(document: doc); _ = controller.view
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let tabs = try #require(descendants(controller.view).compactMap { $0 as? NSTabView }.first)
    let oldGrids = controller.children.compactMap { $0 as? ResultController }
    doc.execute(override: "SELECT 1; SELECT 2;")
    let execution = doc.task; execution?.cancel()
    // No sleep/run-loop advance: boundary cleanup is synchronous, before debounce.
    #expect(tabs.numberOfTabViewItems == 1)
    #expect(oldGrids.allSatisfy { $0.parent == nil })
    doc.results = [Rows(fields: [Field("First")], values: [["1"]])]
    controller.update()
    let first = try #require(controller.children.compactMap { $0 as? ResultController }.first)
    doc.results.append(Rows(fields: [Field("Second")], values: [["2"]]))
    controller.update()
    #expect(tabs.numberOfTabViewItems == 3)
    #expect(first.parent === controller)
    #expect(controller.children.compactMap { $0 as? ResultController }.count == 2)
    await execution?.value
  }

}
