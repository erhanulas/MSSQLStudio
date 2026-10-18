import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ResultHeaderInteractionTests {
  private func fixture()->(ResultController,NSWindow) {
    _=NSApplication.shared
    let grid=ResultController(),window=NSWindow(contentViewController:grid)
    window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:800,height:500))
    window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
    grid.update(Rows(fields:[Field("ID",type:4),Field("Name"),Field("Other")],values:[["3","C","x"],["1","A","y"],["2","B","z"]]))
    grid.setPageSize(0);grid.view.layoutSubtreeIfNeeded()
    return (grid,window)
  }
  private func click(_ header:FilterHeader,point:NSPoint,flags:NSEvent.ModifierFlags=[]) throws {
    let window=try #require(header.window),location=header.convert(point,to:nil)
    let down=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:location,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))
    let up=try #require(NSEvent.mouseEvent(with:.leftMouseUp,location:location,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0))
    // SwiftPM has no application event loop; inject only the native tracking wait.
    header.trackingEventFixture={up};defer {header.trackingEventFixture=nil}
    header.mouseDown(with:down)
  }
  private func wait(_ grid:ResultController) async throws {
    for _ in 0..<200 where grid.isProcessing {try await Task.sleep(for:.milliseconds(10))}
    #expect(!grid.isProcessing)
  }
  @Test func titleSelectsWholeColumnAndCommandShiftUseCanonicalPinnedSelection() throws {
    let (grid,window)=fixture();defer {window.close()}
    let header=try #require(grid.table.headerView as? FilterHeader),rect=header.headerRect(ofColumn:1)
    try click(header,point:NSPoint(x:rect.minX+30,y:rect.midY))
    #expect(grid.table.selectedRowIndexes==IndexSet(integersIn:0..<3) && grid.table.cellColumns==IndexSet(integer:1))
    #expect(grid.table.sortDescriptors.isEmpty)
    grid.setColumnPinned(1,pinned:true);grid.view.layoutSubtreeIfNeeded()
    let frozen=try #require(grid.frozenTable.headerView as? FilterHeader),frozenRect=frozen.headerRect(ofColumn:1)
    try click(frozen,point:NSPoint(x:frozenRect.minX+30,y:frozenRect.midY),flags:.command)
    #expect(grid.table.cellColumns==IndexSet([1,2]) && grid.table.selectedRowIndexes.count==3)
    let third=header.headerRect(ofColumn:3)
    try click(header,point:NSPoint(x:third.minX+30,y:third.midY),flags:.shift)
    #expect(grid.table.cellColumns==IndexSet([1,2,3]))
    #expect(grid.frozenTable.selectedRowIndexes==grid.table.selectedRowIndexes)
    #expect((grid.frozenTable.tableColumns[1].headerCell as? FilterHeaderCell)?.showsSortControl==true)
  }
  @Test func hoverHighlightsOnlyExactActionAndActionSurfacesShareHitGeometry() throws {
    let (grid,window)=fixture();defer {window.close()}
    let header=try #require(grid.table.headerView as? FilterHeader)
    let cell=try #require(grid.table.tableColumns[1].headerCell as? FilterHeaderCell)
    let frame=header.headerRect(ofColumn:1)
    let sort=header.sortHitRect(column:1),filter=header.filterHitRect(column:1)
    #expect(sort.width==28 && filter.width==28 && !sort.intersects(filter))
    #expect(filter.maxX==frame.maxX-12)
    #expect(sort==GridHeaderActionLayout.rect(in:frame,sort:true) && filter==GridHeaderActionLayout.rect(in:frame,sort:false))
    func move(_ point:NSPoint) throws {
      let event=try #require(NSEvent.mouseEvent(with:.mouseMoved,location:header.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:0,pressure:0))
      header.mouseMoved(with:event)
    }
    try move(NSPoint(x:frame.minX+30,y:frame.midY))
    #expect(!cell.hovered && !cell.sortHovered)
    try move(NSPoint(x:filter.minX+1,y:filter.midY))
    #expect(cell.hovered && !cell.sortHovered)
    try move(NSPoint(x:sort.minX+1,y:sort.midY))
    #expect(!cell.hovered && cell.sortHovered)
    // The edge of each framed control is clickable, not just its glyph.
    var filtered=false;header.openFilter={_ in filtered=true}
    try click(header,point:NSPoint(x:filter.minX+1,y:filter.midY))
    #expect(filtered && grid.table.sortDescriptors.isEmpty)
    try click(header,point:NSPoint(x:sort.minX+1,y:sort.midY))
    #expect(grid.table.sortDescriptors.first?.ascending==true)
  }
  @Test func sortAndFilterHitsAreIndependentAndSortCyclesWithoutSelectingColumn() async throws {
    let (grid,window)=fixture();defer {window.close()}
    let header=try #require(grid.table.headerView as? FilterHeader)
    let sort=header.sortHitRect(column:1),filter=header.filterHitRect(column:1),rect=header.headerRect(ofColumn:1)
    #expect(!sort.intersects(filter) && filter.maxX<=rect.maxX-12)
    var filters=0;header.openFilter={position in #expect(position==1);filters+=1}
    try click(header,point:NSPoint(x:filter.midX,y:filter.midY))
    #expect(filters==1 && grid.table.selectedRowIndexes.isEmpty && grid.table.sortDescriptors.isEmpty)
    for state in 0..<3 {
      try click(header,point:NSPoint(x:sort.midX,y:sort.midY));try await wait(grid)
      #expect(grid.table.sortDescriptors.first?.ascending == (state==2 ? nil:state==0))
      #expect(grid.visibleIndices == (state==0 ? [1,2,0]:state==1 ? [0,2,1]:nil))
      #expect(grid.table.selectedRowIndexes.isEmpty && filters==1)
    }
    var rule=ColumnRule();rule.choices=[.text("2")]
    try grid.setRule(rule,column:0);try await wait(grid)
    try click(header,point:NSPoint(x:rect.minX+30,y:rect.midY))
    #expect(grid.table.selectedRowIndexes.count==1 && grid.table.isCellSelected(row:0,column:1))
    let copy=try #require(grid.table.tableColumns[1].headerCell.copy() as? FilterHeaderCell)
    #expect(copy.showsSortControl)
    let old=StudioTheme.mode;defer {StudioTheme.apply(old)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme);grid.view.layoutSubtreeIfNeeded()
      let bitmap=try #require(grid.view.bitmapImageRepForCachingDisplay(in:grid.view.bounds))
      grid.view.cacheDisplay(in:grid.view.bounds,to:bitmap)
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-header-select-sort-"+theme+".png"))
    }
  }
}
