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
