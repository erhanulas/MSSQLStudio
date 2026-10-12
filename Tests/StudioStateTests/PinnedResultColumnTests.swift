import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct PinnedResultColumnTests {
  func fixture() -> (ResultController,NSWindow) {
    _ = NSApplication.shared
    let grid=ResultController()
    let window=NSWindow(contentRect:NSRect(x:-2000,y:0,width:900,height:420),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false; window.contentViewController=grid
    grid.view.frame=NSRect(x:0,y:0,width:900,height:420)
    grid.update(Rows(fields:[Field("ID",type:4),Field("Name"),Field("Amount",type:3,size:28,scale:8),Field("Missing"),Field("Enabled",type:-7)]+(5..<14).map {Field("Extra\($0)")},values:(0..<160).map {row in
      [String(row),"İstanbul \(row)","12345678901234567890.00000000",nil,row.isMultiple(of:2) ? "1":"0"]+(5..<14).map {"\(row):\($0)"}
    }))
    grid.view.layoutSubtreeIfNeeded()
    return (grid,window)
  }
  func invoke(_ title:String,ordinal:Int,grid:ResultController) throws {
    let item=try #require(grid.columnMenu(ordinal:ordinal).items.first {$0.title == title})
    #expect(item.image != nil)
    #expect(NSApp.sendAction(try #require(item.action),to:item.target,from:item))
    grid.view.layoutSubtreeIfNeeded()
  }
  func click(_ target:CopyTable,row:Int,column:Int,shift:Bool=false) throws {
    let rect=target.frameOfCell(atColumn:column,row:row)
    let point=target.convert(NSPoint(x:rect.midX,y:rect.midY),to:nil)
    let event=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:shift ? [.shift]:[],timestamp:0,windowNumber:target.window!.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))
    target.mouseDown(with:event)
  }
  func wait(_ grid:ResultController) async throws {
    for _ in 0..<200 where grid.isProcessing {try await Task.sleep(for:.milliseconds(10))}
    #expect(!grid.isProcessing)
  }
  @Test func menusFreezeArbitraryColumnsAndPreserveSharedSelectionCopyOrderAndResize() throws {
    let (grid,window)=fixture(); defer {window.close()}
    try invoke("Kolonu Sabitle",ordinal:2,grid:grid)
    try invoke("Kolonu Sabitle",ordinal:0,grid:grid)
    #expect(grid.pinnedColumns == [2,0])
    #expect(grid.visibleColumnOrdinals.prefix(4) == [2,0,1,3])
    #expect(!grid.isColumnHidden(2) && grid.table.tableColumns[3].isHidden)
    #expect(grid.frozenTable.tableColumns[1].headerToolTip?.contains("Sabitlenmiş") == true)
    #expect(grid.frozenTable.tableColumns[1].width >= GridColumnSizing.headerWidth("Amount")+16)
    #expect(grid.frozenTable.numberOfRows == grid.table.numberOfRows)
    let fixedFrame=grid.view.convert(grid.frozenScroll.bounds,from:grid.frozenScroll)
    let main=try #require(grid.table.enclosingScrollView)
    main.contentView.scroll(to:NSPoint(x:700,y:800)); main.reflectScrolledClipView(main.contentView)
    #expect(grid.view.convert(grid.frozenScroll.bounds,from:grid.frozenScroll) == fixedFrame)
    #expect(abs(grid.frozenScroll.contentView.bounds.minY-main.contentView.bounds.minY) < 1)
    grid.frozenScroll.contentView.scroll(to:NSPoint(x:0,y:400))
    #expect(abs(main.contentView.bounds.minY-grid.frozenScroll.contentView.bounds.minY) < 1)
    #expect(main.contentView.bounds.minX == 700)
    main.contentView.scroll(to:NSPoint(x:0,y:0))
    try click(grid.frozenTable,row:1,column:1)
    #expect(grid.table.selectedRowIndexes == grid.frozenTable.selectedRowIndexes)
    #expect(grid.table.cellColumns == IndexSet(integer:3))
    grid.frozenTable.copyWithHeaders()
    #expect(NSPasteboard.general.string(forType:.string) == "Amount\n12345678901234567890.00000000")
    try click(grid.table,row:2,column:2,shift:true)
    grid.table.copyWithHeaders()
    #expect(NSPasteboard.general.string(forType:.string) == "Amount\tID\tName\n12345678901234567890.00000000\t1\tİstanbul 1\n12345678901234567890.00000000\t2\tİstanbul 2")
    grid.table.selectGutterRow(0); grid.table.copyWithHeaders()
    #expect(NSPasteboard.general.string(forType:.string)?.hasPrefix("Amount\tID\tName\tMissing\tEnabled\t") == true)
    #expect(NSPasteboard.general.string(forType:.string)?.contains("\tNULL\t1\t") == true)
    grid.frozenTable.tableColumns[1].width=220
    grid.tableViewColumnDidResize(Notification(name:NSTableView.columnDidResizeNotification,object:grid.frozenTable))
    #expect(grid.table.tableColumns[3].width == 220)
    grid.frozenTable.moveColumn(2,toColumn:1)
    #expect(grid.pinnedColumns == [0,2] && grid.visibleColumnOrdinals.prefix(2) == [0,2])
    try invoke("Sabitlemeyi Kaldır",ordinal:2,grid:grid)
    #expect(grid.pinnedColumns == [0] && !grid.table.tableColumns[3].isHidden)
    try invoke("Kolonu Gizle",ordinal:0,grid:grid)
    #expect(grid.pinnedColumns.isEmpty && grid.isColumnHidden(0) && grid.frozenScroll.isHidden)
    grid.revealColumn(0); #expect(!grid.isColumnHidden(0))
    #expect(grid.result.values[0][2] == "12345678901234567890.00000000" && grid.result.values[0][3] == nil)
  }
  @Test func pinStateSurvivesFilterSortPageRefreshThemeAndCanAllBeRemovedInNarrowViewport() async throws {
    let (grid,window)=fixture(); defer {window.close()}
    let old=UserDefaults.standard.string(forKey:"ssmsTheme"); defer {StudioTheme.apply(old ?? "light")}
    grid.setPageSize(10)
    grid.setColumnPinned(2,pinned:true); grid.setColumnPinned(1,pinned:true)
    grid.frozenTable.sortDescriptors=[NSSortDescriptor(key:"0",ascending:false)]
    try await wait(grid)
    #expect(grid.visibleIndices?.first == 159 && grid.table.sortDescriptors.first?.key == "0")
    #expect(grid.tableView(grid.frozenTable,objectValueFor:grid.frozenTable.tableColumns[2],row:0) as? String == "İstanbul 159")
    grid.filter="İstanbul 150"; try await wait(grid)
    #expect(grid.frozenTable.numberOfRows == 1 && grid.table.numberOfRows == 1)
    grid.filter=""; try await wait(grid)
    let next=try #require(grid.toolbar.arrangedSubviews.compactMap {$0 as? NSButton}.first {$0.tag == 2})
    next.performClick(nil)
    #expect(grid.pageStart == 10 && grid.frozenTable.numberOfRows == 10)
    #expect(grid.rowGutter.label?(0).0 == "150")
    grid.revealColumn(2)
    #expect(grid.highlightedColumnOrdinal == 2 && grid.table.tableColumns[3].isHidden)
    #expect(grid.frozenTable.headerView?.accessibilityHelp()?.contains("Amount") == true)
    grid.update(grid.result,generation:1); try await wait(grid)
    #expect(grid.pinnedColumns == [2,1])
    for ordinal in grid.result.fields.indices {grid.setColumnPinned(ordinal,pinned:true)}
    #expect(grid.table.sortDescriptors.first?.ascending == false && grid.visibleIndices?.first == 159)
    #expect(grid.rowGutter.label?(0).0 == "150")
    grid.view.frame.size.width=600; grid.view.layoutSubtreeIfNeeded()
    #expect(grid.frozenScroll.frame.width <= 600-grid.rowGutter.frame.width-160)
    #expect(grid.table.enclosingScrollView!.frame.width >= 160)
    #expect(grid.frozenTable.bounds.width > grid.frozenScroll.contentView.bounds.width)
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      if let image=grid.view.bitmapImageRepForCachingDisplay(in:grid.view.bounds) {
        grid.view.cacheDisplay(in:grid.view.bounds,to:image)
        try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-pinned-columns-\(theme).png"))
      }
    }
    try invoke("Tüm Sabitlemeleri Kaldır",ordinal:1,grid:grid)
    #expect(grid.pinnedColumns.isEmpty && grid.frozenScroll.isHidden)
    #expect(grid.table.sortDescriptors.first?.ascending == false && grid.rowGutter.label?(0).0 == "150")
    grid.setColumnPinned(1,pinned:true)
    grid.update(Rows(fields:[Field("Different")],values:[["new"]]),generation:2)
    #expect(grid.pinnedColumns.isEmpty && grid.frozenScroll.isHidden)
  }
  @Test func pinnedNativeEditingNullEscapeAndKeyboardAcrossPaneBoundaryRetainCanonicalIdentity() throws {
    let (grid,window)=fixture(); defer {window.close()}
    grid.editDefinition=TableDefinition(schema:"dbo",name:"T",columns:grid.result.fields.enumerated().map {.init(id:$0.offset+1,name:$0.element.name,type:$0.offset == 0 ? "int":"nvarchar(100)")},primaryKey:["ID"])
    grid.editingAllowed={true}
    grid.setColumnPinned(1,pinned:true); grid.setColumnPinned(3,pinned:true)
    window.orderFront(nil); grid.view.layoutSubtreeIfNeeded()
    try click(grid.frozenTable,row:0,column:1)
    grid.frozenTable.editCell?(0,1)
    let editor=try #require(grid.frozenTable.currentEditor() as? NSTextView)
    editor.insertText("edited",replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    #expect(grid.hasDraftChanges && grid.pendingEdits.isEmpty)
    #expect(grid.frozenTable.textView(editor,doCommandBy:#selector(NSResponder.cancelOperation(_:))))
    #expect(!grid.hasDraftChanges && grid.pendingEdits.isEmpty)
    grid.frozenTable.editCell?(0,1)
    let committed=try #require(grid.frozenTable.currentEditor() as? NSTextView)
    committed.insertText("kept",replacementRange:NSRange(location:0,length:(committed.string as NSString).length))
    // Unpin commits the field editor before moving its presentation.
    grid.setColumnPinned(1,pinned:false)
    #expect(grid.pendingEdits[0]?.values[1] == "kept")
    grid.setColumnPinned(1,pinned:true)
    try click(grid.frozenTable,row:0,column:2)
    #expect(grid.canSetSelectedNull)
    grid.setSelectedNull(); #expect(grid.pendingEdits[0]?.values[1] == nil)
    #expect(grid.cellIdentity(row:0,position:2) == "0:1")
    let right=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:124))
    grid.frozenTable.keyDown(with:right)
    #expect(grid.table.cellColumns == IndexSet(integer:1) && window.firstResponder === grid.table)
    grid.discardEdits(); #expect(grid.pendingEdits.isEmpty && grid.result.values[0][1] == "İstanbul 0")
  }
}
