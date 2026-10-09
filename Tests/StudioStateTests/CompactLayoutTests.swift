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
    tabs.selectTabViewItem(at: 2)
    #expect(tabs.selectedTabViewItem?.label == "Messages")
  }
}
