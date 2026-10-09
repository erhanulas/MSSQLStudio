import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct PremiumLayoutTests {
  @Test func explorerCanStayNarrowWithoutDragCollapseAndButtonStillHides() throws {
    _ = NSApplication.shared
    let old=UserDefaults.standard.object(forKey:"explorerCollapsed")
    UserDefaults.standard.set(false,forKey:"explorerCollapsed")
    defer {if let old {UserDefaults.standard.set(old,forKey:"explorerCollapsed")}else {UserDefaults.standard.removeObject(forKey:"explorerCollapsed")}}
    let state=StudioState();state.recoveryEnabled=false
    let controller=WorkbenchController(state:state)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1060,height:680),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=controller
    defer {window.close()}
    let split=try #require(controller.children.compactMap {$0 as? NSSplitViewController}.first)
    let sidebar=try #require(split.splitViewItems.first)
    #expect(!sidebar.canCollapse && !sidebar.canCollapseFromWindowResize)
    controller.view.layoutSubtreeIfNeeded()
    split.splitView.setPosition(140,ofDividerAt:0)
    controller.view.layoutSubtreeIfNeeded()
    #expect(!sidebar.isCollapsed)
    #expect(sidebar.viewController.view.frame.width>=139 && sidebar.viewController.view.frame.width<=145)
    #expect(!split.splitView(split.splitView,canCollapseSubview:sidebar.viewController.view))
    #expect(NSApp.sendAction(NSSelectorFromString("toggleExplorer"),to:controller,from:nil))
    #expect(sidebar.isCollapsed)
    #expect(NSApp.sendAction(NSSelectorFromString("toggleExplorer"),to:controller,from:nil))
    #expect(!sidebar.isCollapsed)
  }
  @Test func switchingThemeKeepsSemanticTypographyAndGridState() async throws {
    _ = NSApplication.shared
    let old = UserDefaults.standard.string(forKey: "ssmsTheme")
    defer { StudioTheme.apply(old ?? "light") }
    let server = ConnectedServer(profile: ServerProfile(), password: "")
    let doc = QueryDocument(server: server, database: "master", title: "Visual check")
    doc.state = .ready
    doc.sql = "SELECT 1;"
    doc.results = [Rows(fields: [Field("Number", type: 4), Field("Text")], values: [["1", nil], ["2", "İstanbul"]])]
    let query = QueryController(document: doc)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = query
    query.view.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let views = descendants(query.view)
    let grid = try #require(views.compactMap { $0 as? CopyTable }.first)
    let heading = try #require(views.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "queryConnectionBadge" })
    let originalFont = heading.font
    grid.tableColumns[1].width = 214
    grid.tableColumns[2].isHidden = true
    grid.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    StudioTheme.apply("dark")
    #expect(heading.font == originalFont)
    #expect(grid.tableColumns[1].width == 214)
    #expect(grid.tableColumns[2].isHidden)
    #expect(grid.selectedRow == 1)
    #expect(doc.sql == "SELECT 1;")
    #expect(grid.numberOfRows == 2)
    #expect(grid.backgroundColor == StudioTheme.canvas)
    #expect(try #require(views.compactMap { $0 as? SQLTextView }.first).textLayoutManager != nil)
  }
  @Test func primaryControlsFitMinimumAndWideWorkspace() throws {
    _ = NSApplication.shared
    let state = StudioState()
    state.historyEnabled = false
    state.recoveryEnabled = false
    let server = ConnectedServer(profile: ServerProfile(), password: "")
    let doc = QueryDocument(server: server, database: "master", title: "Responsive")
    doc.state = .ready
    doc.results = [Rows(fields: [Field("Value")], values: [["test"]])]
    state.servers = [server]
    state.documents = [doc]
    state.active = doc
    let controller = WorkbenchController(state: state)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    defer { window.close() }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    for size in [NSSize(width: 1060, height: 680), NSSize(width: 1920, height: 1080)] {
      window.setContentSize(size)
      controller.view.frame.size = size
      controller.view.layoutSubtreeIfNeeded()
      let views = descendants(controller.view)
      for id in ["databaseSelector", "toggleResults", "resultSelector"] {
        let control = try #require(views.first { $0.accessibilityIdentifier() == id })
        let rect = controller.view.convert(control.bounds, from: control)
        #expect(rect.width > 15)
        #expect(rect.minX >= 0 && rect.maxX <= size.width + 1, "\(id): \(rect) in \(size)")
        #expect(rect.minY >= 0 && rect.maxY <= size.height + 1)
      }
      let grid = try #require(views.compactMap { $0 as? CopyTable }.first)
      #expect(try #require(grid.enclosingScrollView).frame.height > 100)
    }
  }

}
