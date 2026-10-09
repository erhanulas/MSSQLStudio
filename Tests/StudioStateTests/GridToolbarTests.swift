import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct GridToolbarTests {
  func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
  @Test func toolsShareOneBarAndSwitchWithResultTabs() throws {
    _ = NSApplication.shared
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Toolbar")
    doc.state = .ready
    doc.results = [Rows(fields: [Field("First")], values: [["A"]]), Rows(fields: [Field("Second")], values: [["B"]])]
    let controller = QueryController(document: doc)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 830, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = controller
    controller.view.frame.size = NSSize(width: 830, height: 680)
    controller.view.layoutSubtreeIfNeeded()
    let views = descendants(controller.view)
    let bar = try #require(views.first { $0.accessibilityIdentifier() == "gridToolbar" })
    let controls = descendants(bar)
    #expect(controls.contains { $0.accessibilityIdentifier() == "gridNavigation" })
    for control in controls.compactMap({ $0 as? NSControl }) where !control.isHidden {
      let rect = controller.view.convert(control.bounds, from: control)
      #expect(rect.minX >= 0 && rect.maxX <= 831, "Toolbar control overflow: \(rect)")
    }
    #expect(controls.contains { $0.accessibilityLabel() == "Page Size" })
    #expect(controls.contains { ($0 as? NSPopUpButton)?.itemTitles.contains("Geçerli sayfa · CSV…") == true })
    #expect(!views.contains { $0.accessibilityLabel() == "Kolon filtresi" })
    let tabs = try #require(views.compactMap { $0 as? NSTabView }.first)
    tabs.selectTabViewItem(withIdentifier: NSNumber(value: 1))
    let second = try #require(controller.children.compactMap { $0 as? ResultController }.first { $0.result.fields.first?.name == "Second" })
    #expect(descendants(bar).contains { $0 === second.toolbar })
    tabs.selectTabViewItem(withIdentifier: "messages")
    #expect(!descendants(bar).contains { $0.accessibilityIdentifier() == "gridNavigation" })
  }
  @Test func bitCellsRemainReadOnlyAndCopyWithHeadersKeepsRawData() throws {
    _ = NSApplication.shared
    let controller = ResultController()
    controller.update(Rows(fields: [Field("Enabled", type: -7)], values: [["1"], ["0"], [nil]]))
    let column = controller.table.tableColumns[1]
    let cell = try #require(column.dataCell as? GridDataCell)
    #expect(cell.isBit && !cell.isEditable && !cell.isSelectable)
    #expect(!controller.responds(to:#selector(NSTableViewDelegate.tableView(_:viewFor:row:))))
    #expect(controller.tableView(controller.table,objectValueFor:column,row:0) as? String == "1")
    #expect(controller.tableView(controller.table,objectValueFor:column,row:1) as? String == "0")
    #expect(controller.tableView(controller.table,objectValueFor:column,row:2) as? String == "NULL")
    controller.table.selectRowIndexes(IndexSet(integersIn: 0...2), byExtendingSelection: false)
    controller.copySelectionData(includeHeaders: true)
    #expect(NSPasteboard.general.string(forType: .string) == "Enabled\n1\n0\nNULL")
  }
  @Test func scrollingDoesNotReformatRangeAndHeaderShortcutIsConfigurable() throws {
    _ = NSApplication.shared
    let controller = ResultController()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = controller
    controller.setPageSize(500)
    controller.update(Rows(fields: [Field("N")], values: (0..<10_000).map { [String($0)] }))
    controller.view.layoutSubtreeIfNeeded()
    let label = try #require(descendants(controller.view).compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "gridRange" })
    let before = label.stringValue
    controller.table.scrollRowToVisible(400)
    controller.view.layoutSubtreeIfNeeded()
    #expect(label.stringValue == before)
    let last = try #require(controller.toolbar.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.tag == 3 })
    last.performClick(nil)
    #expect(label.stringValue == "9501–10000 / \(10_000.formatted())")
    let old = UserDefaults.standard.object(forKey: "gridCopyHeadersShortcut")
    defer { if let old { UserDefaults.standard.set(old, forKey: "gridCopyHeadersShortcut") } else { UserDefaults.standard.removeObject(forKey: "gridCopyHeadersShortcut") } }
    UserDefaults.standard.set("option", forKey: "gridCopyHeadersShortcut")
    controller.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command,.option], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
    controller.table.keyDown(with: event)
    #expect(NSPasteboard.general.string(forType: .string) == "N\n9500")
  }
}
