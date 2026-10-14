import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor private final class SelectionReadProbe {
  var continuations:[CheckedContinuation<ResultSelectionSummary,Never>]=[]
  var calls=0
  func read() async -> ResultSelectionSummary {
    calls+=1
    return await withCheckedContinuation {continuations.append($0)}
  }
}
@MainActor @Suite(.serialized) struct ResultSelectionUITests {
  private func fixture()->(ResultController,NSWindow) {
    _=NSApplication.shared
    let grid=ResultController(),window=NSWindow(contentRect:NSRect(x:-2000,y:0,width:780,height:350),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=grid
    grid.view.frame.size=NSSize(width:780,height:350)
    grid.update(Rows(fields:[Field("ID",type:4),Field("Amount",type:3,size:18,scale:2),Field("Text")],values:[["1","10.25","x"],["2","20.50",""],["3",nil,nil],["4","40.75","y"]]))
    grid.view.layoutSubtreeIfNeeded()
    return (grid,window)
  }
  private func wait(_ presentation:ResultSelectionPresentation,_ text:String) async throws {
    let deadline=ContinuousClock.now.advanced(by:.seconds(4))
    while presentation.label.stringValue != text,ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(5))}
    #expect(presentation.label.stringValue==text)
  }
  private func waitProjection(_ grid:ResultController) async throws {
    for _ in 0..<500 where grid.isProcessing {try await Task.sleep(for:.milliseconds(5))}
    #expect(!grid.isProcessing)
  }
  @Test func selectionChangesBetweenRowsInSameColumnAndRectangleUpdateFooter() async throws {
    let (grid,window)=fixture();defer {window.close()}
    grid.table.selectCell(row:0,column:2)
    try await wait(grid.selectionSummary,"Toplam: 10.25   ·   Sayı: 1")
    grid.table.selectCell(row:1,column:2)
    try await wait(grid.selectionSummary,"Toplam: 20.50   ·   Sayı: 1")
    grid.table.selectCell(row:2,column:2,extending:true)
    try await wait(grid.selectionSummary,"Toplam: 20.50   ·   Sayı: 1")
    grid.table.selectCell(row:0,column:3,extending:true)
    try await wait(grid.selectionSummary,"Toplam: 30.75   ·   Sayı: 4")
    grid.table.deselectAll(nil)
    #expect(grid.selectionSummary.label.stringValue=="Toplam: —   ·   Sayı: 0")
    #expect(grid.result.values[0][1]=="10.25" && grid.pendingEdits.isEmpty)
  }
  @Test func frozenHiddenColumnsPagingSortingFilteringAndRefreshUseCanonicalSnapshot() async throws {
    let (grid,window)=fixture();defer {window.close()}
    grid.setPageSize(2);grid.setColumnPinned(1,pinned:true)
    let rect=grid.frozenTable.frameOfCell(atColumn:1,row:0)
    let event=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:grid.frozenTable.convert(NSPoint(x:rect.midX,y:rect.midY),to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1))
    grid.frozenTable.mouseDown(with:event)
    try await wait(grid.selectionSummary,"Toplam: 10.25   ·   Sayı: 1")
    grid.table.sortDescriptors=[NSSortDescriptor(key:"0",ascending:false)];try await waitProjection(grid)
    grid.table.selectCell(row:0,column:2)
    try await wait(grid.selectionSummary,"Toplam: 40.75   ·   Sayı: 1")
    let next=try #require(grid.toolbar.arrangedSubviews.compactMap {$0 as? NSButton}.first {$0.tag==2})
    next.performClick(nil);grid.table.selectCell(row:0,column:2)
    try await wait(grid.selectionSummary,"Toplam: 20.50   ·   Sayı: 1")
    grid.filter="x";try await waitProjection(grid);grid.table.selectGutterRow(0)
    try await wait(grid.selectionSummary,"Toplam: 11.25   ·   Sayı: 3")
    let hide=try #require(grid.columnMenu(ordinal:0).items.first {$0.title=="Kolonu Gizle"})
    #expect(NSApp.sendAction(try #require(hide.action),to:hide.target,from:hide))
    try await wait(grid.selectionSummary,"Toplam: 10.25   ·   Sayı: 2")
    grid.update(Rows(fields:grid.result.fields,values:[["1","99.00","x"]]),generation:1);try await waitProjection(grid)
    grid.table.selectGutterRow(0)
    try await wait(grid.selectionSummary,"Toplam: 99.00   ·   Sayı: 2")
  }
  @Test func committedDraftValuesCountButDoNotMutateOriginalResult() async throws {
    let (grid,window)=fixture();defer {window.close()}
    grid.editDefinition = .init(schema:"dbo",name:"T",columns:[.init(id:1,name:"ID",type:"int"),.init(id:2,name:"Amount",type:"decimal(18,2)"),.init(id:3,name:"Text",type:"nvarchar(50)")],primaryKey:["ID"])
    grid.editingAllowed={true}
    grid.table.selectCell(row:0,column:2);grid.setEditValue("15.25",row:0,column:1)
    try await wait(grid.selectionSummary,"Toplam: 15.25   ·   Sayı: 1")
    #expect(grid.result.values[0][1]=="10.25")
    grid.setEditValue(nil,row:0,column:1)
    try await wait(grid.selectionSummary,"Toplam: —   ·   Sayı: 0")
  }
  @Test func latestOnlyWorkerCannotPublishStaleValuesAndFooterFitsBothThemes() async throws {
    let probe=SelectionReadProbe()
    let presentation=ResultSelectionPresentation(operation:{_ in await probe.read()})
    let rows=Rows(fields:[Field("N",type:4)],values:[["1"],["2"]])
    let first=ResultSelectionSummary.Request(rows:rows,selection:IndexSet(integer:0),columns:[0])
    let second=ResultSelectionSummary.Request(rows:rows,selection:IndexSet(integer:1),columns:[0])
    presentation.update(first)
    for _ in 0..<300 where probe.continuations.isEmpty {try await Task.sleep(for:.milliseconds(2))}
    #expect(probe.calls==1);presentation.update(second)
    try await Task.sleep(for:.milliseconds(150));#expect(probe.calls==1)
    try #require(!probe.continuations.isEmpty)
    probe.continuations.removeFirst().resume(returning:try ResultSelectionSummary.compute(first))
    for _ in 0..<300 where probe.continuations.isEmpty {try await Task.sleep(for:.milliseconds(2))}
    #expect(probe.calls==2 && presentation.label.stringValue=="Toplam: …   ·   Sayı: …")
    try #require(!probe.continuations.isEmpty)
    probe.continuations.removeFirst().resume(returning:try ResultSelectionSummary.compute(second))
    try await wait(presentation,"Toplam: 2   ·   Sayı: 1")
    let (grid,window)=fixture();defer {window.close()}
    let old=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(old ?? "light")}
    grid.table.selectCell(row:0,column:2);grid.table.selectCell(row:1,column:2,extending:true)
    try await wait(grid.selectionSummary,"Toplam: 30.75   ·   Sayı: 2")
    if let scroll=grid.table.enclosingScrollView {
      scroll.contentView.scroll(to:NSPoint(x:100,y:25));scroll.reflectScrolledClipView(scroll.contentView)
      #expect(grid.selectionSummary.label.stringValue=="Toplam: 30.75   ·   Sayı: 2")
      scroll.contentView.scroll(to:.zero)
    }
    for theme in ["light","dark"] {
      StudioTheme.apply(theme);window.appearance=NSAppearance(named:theme=="dark" ? .darkAqua:.aqua)
      grid.view.layoutSubtreeIfNeeded();grid.view.displayIfNeeded()
      let footer=grid.selectionSummary.bar,frame=grid.view.convert(footer.bounds,from:footer)
      #expect(frame.height==26 && frame.minX==0 && frame.maxX==780 && frame.minY==0)
      let scroll=try #require(grid.table.enclosingScrollView)
      #expect(grid.view.convert(scroll.bounds,from:scroll).minY==26)
      let image=try #require(grid.view.bitmapImageRepForCachingDisplay(in:grid.view.bounds))
      grid.view.cacheDisplay(in:grid.view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-selection-summary-\(theme).png"))
    }
  }
}
