import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct WorkbenchDesignTests {
  func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
  @Test func themesKeepWorkspaceReadableAndPreserveQueryState() async throws {
    _ = NSApplication.shared
    let oldTheme = UserDefaults.standard.string(forKey: "ssmsTheme")
    let oldCollapsed = UserDefaults.standard.object(forKey: "explorerCollapsed")
    defer {
      StudioTheme.apply(oldTheme ?? "light")
      if let oldCollapsed { UserDefaults.standard.set(oldCollapsed, forKey: "explorerCollapsed") }
      else { UserDefaults.standard.removeObject(forKey: "explorerCollapsed") }
    }
    UserDefaults.standard.set(false, forKey: "explorerCollapsed")
    let state = StudioState(); state.recoveryEnabled = false
    let server = ConnectedServer(profile: ServerProfile(name: "Commerce · Development"), password: "")
    server.catalogFixture = ObjectManagementUIFixture.catalog
    server.databases = [.init(id: 5, name: "Commerce")]
    state.servers = [server]
    let sql = "-- Recent orders\nSELECT OrderID, CustomerName, Total, Status\nFROM dbo.Orders\nWHERE Total > 100\nORDER BY OrderID DESC;"
    let query = QueryDocument(server: server, database: "Commerce", title: "Orders.sql")
    query.sql = sql; query.savedText = sql; query.state = .ready
    query.results = [Rows(fields: [Field("OrderID", type: 4), Field("CustomerName"), Field("Total", type: 3), Field("Status")], values: [
      ["1048", "Atlas Design", "1249.5000", "Completed"], ["1047", "Northwind", "840.0000", "Processing"],
      ["1046", "Studio North", "329.9000", "Completed"], ["1045", "Acme Labs", "1590.0000", "Pending"]])]
    query.rowCount = 4
    state.documents = [query, QueryDocument(server: server, database: "Commerce", title: "Customers.sql")]
    state.active = query
    let controller = WorkbenchController(state: state)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 880), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = controller; window.orderFront(nil)
    let split = try #require(controller.children.compactMap { $0 as? NSSplitViewController }.first)
    let editor = try #require(descendants(controller.view).compactMap { $0 as? SQLTextView }.first)
    editor.setSelectedRange(NSRange(location: 17, length: 6))
    let selection = editor.selectedRange()
    let search = try #require(descendants(controller.view).compactMap { $0 as? NSSearchField }.first)
    let searchFont = search.font
    for theme in ["light", "dark"] {
      StudioTheme.apply(theme)
      try await Task.sleep(for: .milliseconds(250))
      for width: CGFloat in [1100, 1440] {
        window.setContentSize(NSSize(width: width, height: 880))
        controller.view.frame.size = NSSize(width: width, height: 880)
        controller.view.layoutSubtreeIfNeeded()
        split.splitView.setPosition(240, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        #expect(split.splitViewItems[0].viewController.view.bounds.width >= 239)
        let bar = try #require(descendants(controller.view).first { $0.accessibilityIdentifier() == "gridToolbar" })
        for control in descendants(bar).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
          let rect = controller.view.convert(control.bounds, from: control)
          #expect(rect.minX >= 0 && rect.maxX <= width + 1)
        }
        for label in descendants(controller.view).compactMap({ $0 as? NSTextField }) where label.identifier?.rawValue == "studio.mutedLabel" {
          #expect(label.textColor == StudioTheme.muted)
        }
        #expect(search.font == searchFont)
        #expect(editor.string == sql && editor.selectedRange() == selection)
        #expect(query.results[0].values[0][2] == "1249.5000")
        if let rep = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
          controller.view.cacheDisplay(in: controller.view.bounds, to: rep)
          try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/mssql-design-\(theme)-\(Int(width)).png"))
        }
      }
    }
  }
}
