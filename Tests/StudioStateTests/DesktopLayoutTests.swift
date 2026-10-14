import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct DesktopLayoutTests {
  private func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}

  @Test func historyFiltersStayCompactAndWhitespaceIsNotASelectorInBothThemes() async throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      for size in [NSSize(width:820,height:560),NSSize(width:1400,height:900)] {
        let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
        state.history=(0..<40).map {QueryRecord(server:"Fixture",database:$0 % 2 == 0 ? "DemoDB":"Reporting",text:"SELECT \($0) AS Value;",seconds:0.125,status:"Başarılı")}
        let host=NSHostingController(rootView:HistoryPanel(state:state,open:{_ in}));host.sizingOptions=[]
        let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
        window.setContentSize(size);host.view.frame=NSRect(origin:.zero,size:size)
        defer {window.close()}
        for _ in 0..<20 where !views(host.view).contains(where:{$0 is StudioSearchablePopUpButton}) {try await Task.sleep(for:.milliseconds(10));host.view.layoutSubtreeIfNeeded()}
        try await Task.sleep(for:.milliseconds(90));host.view.layoutSubtreeIfNeeded()
        let pickers=views(host.view).compactMap {$0 as? StudioSearchablePopUpButton}
        #expect(pickers.count==2)
        for picker in pickers {
          let rect=host.view.convert(picker.bounds,from:picker)
          #expect(abs(rect.height-26)<1 && rect.width<=280 && rect.minX>=0 && rect.maxX<=size.width)
          let outside=NSPoint(x:rect.midX,y:rect.maxY+8)
          #expect(!(host.view.hitTest(outside) is StudioSearchablePopUpButton))
        }
        let split=try #require(views(host.view).compactMap {$0 as? NSSplitView}.first)
        #expect(!split.isVertical && split.arrangedSubviews.count==2 && split.bounds.height>size.height-210)
        let table=try #require(views(host.view).compactMap {$0 as? NSTableView}.first {$0.tableColumns.count==6})
        let tableWidth=table.tableColumns.reduce(CGFloat(0)) {$0+$1.width+table.intercellSpacing.width}
        #expect(tableWidth<=table.enclosingScrollView!.contentSize.width+2)
        let firstHeight=split.arrangedSubviews[0].frame.height
        split.setPosition(firstHeight+25,ofDividerAt:0);host.view.layoutSubtreeIfNeeded()
        #expect(abs(split.arrangedSubviews[0].frame.height-firstHeight)>10)
        for picker in pickers {#expect(picker.choices==nil)}
        let image=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
        host.view.cacheDisplay(in:host.view.bounds,to:image)
        try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-desktop-history-\(theme)-\(Int(size.width)).png"))
      }
    }
  }

  @Test func choicePopupUsesContentWidthAndBoundedScrolling() {
    _=NSApplication.shared
    let short=StudioSearchablePopUpButton.choicesSize(["DemoDB","master"])
    #expect(short.width==160 && short.height==60)
    let many=StudioSearchablePopUpButton.choicesSize((0..<1000).map {"Database_\($0)"},searching:true)
    #expect(many.height==360 && many.width<260)
    let long=StudioSearchablePopUpButton.choicesSize([String(repeating:"W",count:200)])
    #expect(long.width==360 && long.height==44)
  }

  @Test func popupShowsCompleteRowsAndSearchRevealsItsFirstMatch() throws {
    _=NSApplication.shared
    let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:500,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    let picker=StudioSearchablePopUpButton(frame:NSRect(x:20,y:220,width:170,height:26))
    window.contentView?.addSubview(picker);window.orderFront(nil)
    defer {picker.removeFromSuperview();window.close()}
    picker.updateChoices(["master","DemoDB"],selected:"master",contextID:nil,enabled:true)
    picker.showChoices()
    let choices=try #require(picker.choices);choices.view.layoutSubtreeIfNeeded()
    let table=choices.table
    #expect(table.visibleRect.contains(table.rect(ofRow:0)))
    #expect(table.visibleRect.contains(table.rect(ofRow:1)))
    let values=(0..<1000).map {"Database_\($0)"}
    picker.updateChoices(values,selected:values.last,contextID:nil,enabled:true);picker.showChoices()
    let long=try #require(picker.choices);long.view.layoutSubtreeIfNeeded()
    #expect(long.table.visibleRect.contains(long.table.rect(ofRow:999)))
    long.beginSearch("Database_1");long.view.layoutSubtreeIfNeeded()
    #expect(long.table.visibleRect.contains(long.table.rect(ofRow:0)) && long.filtered.count==111)
    #expect(picker.titleOfSelectedItem=="Database_999")
  }

  @Test func explorerDensityAndSearchChromePreserveTreeIdentityAndSelection() throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:.init(name:"Fixture"),password:"");server.online=false
    server.databases=[CatalogItem(id:5,name:"DemoDB")];state.servers=[server]
    let host=WorkbenchController(state:state);host.loadViewIfNeeded()
    let node=try #require(host.roots.first)
    host.outline.selectRowIndexes(IndexSet(integer:host.outline.row(forItem:node)),byExtendingSelection:false)
    #expect(host.searchFilters.isHidden && host.outline.rowHeight==24)
    state.explorerTreeDefaults.set("comfortable",forKey:ExplorerDensity.key)
    host.updateExplorerDensity()
    #expect(host.outline.rowHeight==28 && host.roots.first === node && host.outline.item(atRow:host.outline.selectedRow) as? TreeNode === node)
    host.showExplorerSearch(true);#expect(!host.searchFilters.isHidden)
    host.showExplorerSearch(false);#expect(host.searchFilters.isHidden && host.roots.first === node)
    #expect(SettingsSearch.results("explorer yoğunluğu").contains {$0.id=="explorerDensity"})
  }
}
