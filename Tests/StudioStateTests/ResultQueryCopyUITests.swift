import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ResultQueryCopyUITests {
  private func ready(_ grid:ResultController) async throws {
    for _ in 0..<300 where grid.queryCopy.preparing || grid.isProcessing {try await Task.sleep(for:.milliseconds(10))}
    #expect(!grid.queryCopy.preparing && !grid.isProcessing)
  }
  private func item(_ table:CopyTable) throws -> NSMenuItem {
    try #require(table.makeSelectionMenu().items.first {$0.identifier?.rawValue=="gridCopyQuery"})
  }
  @Test func copyCelebrationStaysInOwnerAndDoesNotCaptureFocus() async throws {
    _=NSApplication.shared
    let grid=ResultController(),window=NSWindow(contentViewController:grid)
    window.isReleasedWhenClosed=false;window.makeKeyAndOrderFront(nil);defer {window.close()}
    let host=try #require(window.contentView)
    var rows=Rows(fields:[Field("ID",type:4)],values:[["1"]]);rows.source = .init(sql:"SELECT * FROM T")
    grid.update(rows);try await ready(grid);grid.table.selectCell(row:0,column:1)
    #expect(window.makeFirstResponder(grid.table))
    let action=try item(grid.table)
    #expect(NSApp.sendAction(try #require(action.action),to:action.target,from:action))
    let burst=try #require(host.subviews.compactMap {$0 as? StudioConfetti}.first)
    #expect(burst.hitTest(.zero)==nil && window.firstResponder === grid.table)
    #expect(abs(burst.frame.midX-host.bounds.midX)<1 && abs(burst.frame.midY-host.bounds.midY)<1)
    #expect(NSPasteboard.general.string(forType:.string)=="SELECT * FROM T WHERE ID = 1;")
    StudioConfetti.show(in:host,reduceMotion:true)
    #expect(host.subviews.compactMap {$0 as? StudioConfetti}.count==1 && burst.superview==nil)
    let reduced=try #require(host.subviews.compactMap {$0 as? StudioConfetti}.first)
    #expect(reduced.subviews.contains {$0 is NSImageView})
    try await Task.sleep(for:.milliseconds(1100))
    #expect(!host.subviews.contains {$0 is StudioConfetti})
    #expect(window.firstResponder === grid.table)
  }
  @Test func assignableShortcutUsesFocusedGridAndRespectsSelectionEligibility() async throws {
    _=NSApplication.shared
    var old:[String:Any]=[:]
    for action in GridShortcuts.Action.allCases {
      let key="shortcut."+action.rawValue;old[key]=UserDefaults.standard.object(forKey:key);UserDefaults.standard.removeObject(forKey:key)
    }
    defer {for action in GridShortcuts.Action.allCases {let key="shortcut."+action.rawValue;if let value=old[key] {UserDefaults.standard.set(value,forKey:key)} else {UserDefaults.standard.removeObject(forKey:key)}}}
    #expect(ShortcutCatalog.category(.gridCopyQuery) == .results)
    #expect(ShortcutCatalog.actions(category:.results,query:"değerlerle sorgu").contains(.gridCopyQuery))
    #expect(GridShortcuts.binding(.gridCopyQuery).key.isEmpty)
    var rows=Rows(fields:[Field("ID",type:4)],values:[["1"],["2"]]);rows.source = .init(sql:"SELECT * FROM T")
    let grid=ResultController(),window=NSWindow(contentViewController:grid)
    window.isReleasedWhenClosed=false;window.makeKeyAndOrderFront(nil);defer {window.close()}
    grid.update(rows);try await ready(grid)
    let event=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.control,.option],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"g",charactersIgnoringModifiers:"g",isARepeat:false,keyCode:5))
    #expect(GridShortcuts.save(event,action:.gridCopyQuery)==nil)
    #expect(GridShortcuts.save(event,action:.revealExplorer) != nil)
    grid.table.selectCell(row:0,column:1);grid.table.selectCell(row:1,column:1,extending:true)
    #expect(window.makeFirstResponder(grid.table))
    let menuItem=try item(grid.table)
    #expect(menuItem.keyEquivalent=="g" && menuItem.keyEquivalentModifierMask==[.control,.option])
    #expect(!menuItem.allowsAutomaticKeyEquivalentLocalization && !menuItem.allowsAutomaticKeyEquivalentMirroring)
    #expect(grid.table.performKeyEquivalent(with:event))
    #expect(NSPasteboard.general.string(forType:.string)=="SELECT * FROM T WHERE ID IN (1, 2);")
    grid.setColumnPinned(0,pinned:true)
    #expect(window.makeFirstResponder(grid.frozenTable))
    #expect(grid.frozenTable.performKeyEquivalent(with:event))
    grid.frozenTable.selectAllCells()
    #expect(window.firstResponder === grid.frozenTable)
    #expect(try !item(grid.frozenTable).isEnabled)
    NSPasteboard.general.clearContents();NSPasteboard.general.setString("unchanged",forType:.string)
    #expect(grid.frozenTable.performKeyEquivalent(with:event))
    #expect(NSPasteboard.general.string(forType:.string)=="unchanged")
    let copyKey=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.control,.option],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"c",charactersIgnoringModifiers:"c",isARepeat:false,keyCode:8))
    #expect(GridShortcuts.save(copyKey,action:.gridCopyQuery)==nil)
    grid.frozenTable.keyDown(with:copyKey)
    #expect(NSPasteboard.general.string(forType:.string)=="unchanged")
    GridShortcuts.clear(.gridCopyQuery)
    #expect(try item(grid.table).keyEquivalent.isEmpty)
  }
  @Test func menuCopiesTypedPredicatesUsingSortedPagedPinnedSelectionAndLateProvenance() async throws {
    _=NSApplication.shared
    let source="SELECT * FROM dbo.T AS T WITH(NOLOCK) WHERE T.ID = 99"
    var rows=Rows(fields:[Field("ID",type:4),Field("Name"),Field("Missing")],values:[["1","one",nil],["2","O'Brien",nil],["3","three",nil]])
    let grid=ResultController(),window=NSWindow(contentViewController:grid)
    window.isReleasedWhenClosed=false;defer {window.close()}
    grid.setPageSize(1);grid.update(rows,generation:1)
    grid.table.selectCell(row:0,column:1)
    #expect(try !item(grid.table).isEnabled)
    rows.source = .init(sql:source)
    grid.update(rows,generation:1) // Source events can arrive without changing row count/generation.
    grid.table.sortDescriptors=[NSSortDescriptor(key:"0",ascending:false)]
    grid.filter="O'Brien"
    grid.setColumnPinned(1,pinned:true)
    try await ready(grid)
    grid.table.selectCell(row:0,column:1)
    let single=try item(grid.table)
    #expect(single.isEnabled)
    #expect(NSApp.sendAction(try #require(single.action),to:single.target,from:single))
    #expect(NSPasteboard.general.string(forType:.string)=="SELECT * FROM dbo.T AS T WITH(NOLOCK) WHERE T.ID = 2;")
    grid.table.selectCell(row:0,column:2,extending:true)
    let multiple=try item(grid.frozenTable)
    #expect(multiple.isEnabled)
    #expect(NSApp.sendAction(try #require(multiple.action),to:multiple.target,from:multiple))
    #expect(NSPasteboard.general.string(forType:.string)=="SELECT * FROM dbo.T AS T WITH(NOLOCK) WHERE T.Name = N'O''Brien' AND T.ID = 2;")
    #expect(grid.result.source?.sql==source && grid.loadedRowCount==3 && grid.pendingEdits.isEmpty)
    grid.filter="";try await ready(grid);grid.setPageSize(0)
    grid.table.selectCell(row:0,column:1);grid.table.selectCell(row:1,column:1,extending:true)
    let vertical=try item(grid.table)
    #expect(vertical.isEnabled)
    #expect(NSApp.sendAction(try #require(vertical.action),to:vertical.target,from:vertical))
    #expect(NSPasteboard.general.string(forType:.string)=="SELECT * FROM dbo.T AS T WITH(NOLOCK) WHERE T.ID IN (3, 2);")
    grid.table.selectCell(row:0,column:2);grid.table.selectCell(row:1,column:2,extending:true)
    let pinnedVertical=try item(grid.frozenTable)
    #expect(pinnedVertical.isEnabled)
    #expect(NSApp.sendAction(try #require(pinnedVertical.action),to:pinnedVertical.target,from:pinnedVertical))
    #expect(NSPasteboard.general.string(forType:.string)=="SELECT * FROM dbo.T AS T WITH(NOLOCK) WHERE T.Name IN (N'three', N'O''Brien');")
    grid.table.selectCell(row:0,column:1);grid.table.selectCell(row:1,column:2,extending:true)
    #expect(try !item(grid.table).isEnabled)
    grid.table.selectCell(row:0,column:99)
    #expect(try !item(grid.table).isEnabled) // Stale column coordinates cannot index changed metadata.
  }
  @Test func currentSourceWinsAndUnsupportedSourcesDoNotProduceQueryCopies() async throws {
    let grid=ResultController();_=grid.view
    for source in ["SELECT * FROM A", "SELECT * FROM B", "EXEC dbo.P"] {
      var rows=Rows(fields:[Field("ID",type:4)],values:[["1"]]);rows.source = .init(sql:source)
      grid.update(rows,generation:source.count)
    }
    try await ready(grid)
    grid.table.selectCell(row:0,column:1)
    #expect(grid.queryCopy.template == nil)
    #expect(try !item(grid.table).isEnabled)
    var rows=Rows(fields:[Field("ID",type:4)],values:[["1"]]);rows.source = .init(sql:"SELECT * FROM CurrentTable")
    grid.update(rows,generation:20);try await ready(grid)
    #expect(try #require(grid.queryCopy.template).sql(cells:[(0,"1")])=="SELECT * FROM CurrentTable WHERE ID = 1;")
  }
}
