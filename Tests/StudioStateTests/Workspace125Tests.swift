import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct Workspace125Tests {
  private func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
  private func fixture()->(StudioState,ConnectedServer,WorkbenchController,NSWindow) {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let defaults=UserDefaults(suiteName:"Workspace125-"+UUID().uuidString)!
    state.explorerOrderDefaults=defaults;state.explorerTreeDefaults=defaults
    let disk=CatalogDiskIndex(url:state.folder.appendingPathComponent("125-"+UUID().uuidString+".sqlite"))
    let server=ConnectedServer(profile:.init(name:"Fixture",visibleDatabases:["Demo"]),password:"",diskIndex:disk,objectIndexService:CatalogIndexService(index:disk),completionIndexService:SQLCatalogService(index:disk))
    server.online=false;server.databases=[.init(id:5,name:"Demo")];state.servers=[server]
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.setContentSize(NSSize(width:1200,height:800));window.orderFront(nil)
    return (state,server,host,window)
  }
  private func wait(_ predicate:()->Bool) async throws {
    let deadline=ContinuousClock.now.advanced(by:.seconds(4))
    while !predicate(),ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(5))}
    #expect(predicate())
  }
  @Test func aggregateLivesInReadyBarSwitchesResultsAndFollowsDetachedDocument() async throws {
    let (state,server,host,window)=fixture();defer {host.redockQueries();window.close()}
    let doc=state.newQuery(server:server,database:"Demo",text:"SELECT 1;")
    doc.state = .ready
    doc.results=[Rows(fields:[Field("Amount",type:3,size:18,scale:2),Field("ID",type:4)],values:[["10.25","1"],["20.50","2"],[nil,"3"]]),Rows(fields:[Field("Other",type:4)],values:[["100"]])]
    let query=try #require(host.children.compactMap {$0 as? QueryController}.first {$0.document === doc})
    query.update();host.updateControls();host.view.layoutSubtreeIfNeeded()
    let grid=try #require(query.children.compactMap {$0 as? ResultController}.first {$0.result.fields.first?.name=="Amount"})
    grid.table.selectCell(row:1,column:1);grid.table.selectCell(row:0,column:1,extending:true)
    try await wait {host.resultSelectionStatus.stringValue=="Toplam: 30.75   ·   Sayı: 2"}
    #expect(host.resultSelectionStatus.superview === host.statusStrip && host.status.stringValue.hasPrefix("Ready"))
    #expect(host.executionDate.stringValue == "Son çalıştırma: —" && grid.selectionSummary.label.superview==nil)
    let scroll=try #require(grid.table.enclosingScrollView)
    #expect(grid.view.convert(scroll.bounds,from:scroll).minY==0 && scroll.borderType == .noBorder && scroll.scrollerStyle == .overlay)
    grid.table.selectCell(row:0,column:2,extending:true)
    try await wait {host.resultSelectionStatus.stringValue=="Toplam: —   ·   Sayı: 4"}
    let tabs=try #require(descendants(query.view).compactMap {$0 as? NSTabView}.first)
    tabs.selectTabViewItem(withIdentifier:"messages");#expect(host.resultSelectionStatus.isHidden)
    tabs.selectTabViewItem(withIdentifier:NSNumber(value:1))
    let other=try #require(query.children.compactMap {$0 as? ResultController}.first {$0.result.fields.first?.name=="Other"})
    other.table.selectCell(row:0,column:1)
    try await wait {host.resultSelectionStatus.stringValue=="Toplam: 100   ·   Sayı: 1"}
    host.detachQuery()
    let detached=try #require(host.detached[doc.id])
    #expect(host.resultSelectionStatus.isHidden)
    detached.window?.contentView?.layoutSubtreeIfNeeded()
    let detachedRoot=try #require(detached.window?.contentView)
    let status=try #require(descendants(detachedRoot).compactMap {$0 as? NSTextField}.first {$0.accessibilityIdentifier()=="resultSelectionSummaryValues"})
    try await wait {status.stringValue=="Toplam: 100   ·   Sayı: 1"}
    detached.close();host.updateControls()
    try await wait {host.resultSelectionStatus.stringValue=="Toplam: 100   ·   Sayı: 1"}
    let old=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(old ?? "light")}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme);window.appearance=NSAppearance(named:theme=="dark" ? .darkAqua:.aqua)
      host.view.layoutSubtreeIfNeeded()
      try await wait {host.resultSelectionStatus.stringValue=="Toplam: 100   ·   Sayı: 1"}
      host.view.displayIfNeeded()
      let labelRect=host.statusStrip.convert(host.resultSelectionStatus.bounds,from:host.resultSelectionStatus)
      #expect(host.statusStrip.bounds.insetBy(dx:0,dy:-1).contains(labelRect))
      let image=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
      host.view.cacheDisplay(in:host.view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql125-status-\(theme).png"))
    }
  }
  @Test func hashHeaderSelectsAllAndReverseVerticalSelectionStillSums() async throws {
    _=NSApplication.shared
    let grid=ResultController(),window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:800,height:350),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=grid
    window.setContentSize(NSSize(width:800,height:350));grid.view.frame.size=NSSize(width:800,height:350)
    defer {window.close()}
    grid.update(Rows(fields:[Field("A",type:4),Field("B",type:4)],values:[["1","10"],["2","20"],["3","30"]]))
    window.orderFront(nil);grid.view.layoutSubtreeIfNeeded();grid.rowGutter.layoutSubtreeIfNeeded()
    grid.table.selectCell(row:2,column:1);grid.table.selectCell(row:0,column:1,extending:true)
    try await wait {grid.selectionSummary.label.stringValue=="Toplam: 6   ·   Sayı: 3"}
    grid.table.selectCell(row:0,column:2,extending:true)
    try await wait {grid.selectionSummary.label.stringValue=="Toplam: —   ·   Sayı: 6"}
    grid.table.selectCell(row:0,column:1)
    let button=grid.rowGutter.selectAllButton
    #expect(button.frame.height==40 && button.frame.width==grid.rowGutter.bounds.width)
    let point=grid.view.convert(NSPoint(x:button.bounds.midX,y:button.bounds.midY),from:button)
    #expect(grid.view.hitTest(point) === button,"hit=\(String(describing:grid.view.hitTest(point))), point=\(point), gutter=\(grid.rowGutter.frame), button=\(button.frame), header=\(String(describing:grid.table.headerView?.frame)), root=\(grid.view.bounds)")
    #expect(NSApp.sendAction(try #require(button.action),to:button.target,from:button))
    #expect(grid.table.selectedRowIndexes==IndexSet(integersIn:0..<3) && grid.table.cellColumns.isEmpty)
    try await wait {grid.selectionSummary.label.stringValue=="Toplam: —   ·   Sayı: 6"}
    #expect(grid.result.values[0]==["1","10"])
  }
  @Test func settingsFirstOpenFitsFooterWithoutManualResizeAndReusesWindow() async throws {
    let (_,_,host,main)=fixture();defer {main.close()}
    let model=DefinitionIndexStorageModel(disk:CatalogDiskIndex(url:URL(fileURLWithPath:"/tmp/settings125-"+UUID().uuidString+"/index.sqlite")))
    host.showSettingsWindow(definitionStorage:model)
    let window=try #require(host.auxiliaryWindows.compactMap(\.window).first {$0.identifier?.rawValue=="studio.settings"})
    defer {window.close()}
    let root=try #require(window.contentView)
    let requested=window.frameRect(forContentRect:NSRect(origin:window.frame.origin,size:NSSize(width:960,height:720)))
    let fitted=window.constrainFrameRect(requested,to:window.screen)
    let expected=window.contentRect(forFrameRect:fitted).size
    #expect(root.bounds.size==expected)
    #expect(root.bounds.width>=820 && root.bounds.height>=620)
    try await wait {descendants(root).contains {$0.accessibilityIdentifier()=="settingsApply"}}
    root.layoutSubtreeIfNeeded()
    let apply=try #require(descendants(root).compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier()=="settingsApply"})
    let rect=root.convert(apply.bounds,from:apply)
    #expect(rect.width>=90 && rect.height>=24 && rect.maxX<=root.bounds.maxX-20 && rect.minY>=20,"Apply frame=\(rect), root=\(root.bounds), native frame=\(apply.frame), insets=\(apply.alignmentRectInsets)")
    host.showSettingsWindow(definitionStorage:model)
    #expect(host.auxiliaryWindows.filter {$0.window?.identifier?.rawValue=="studio.settings"}.count==1)
    try await wait {!model.busy && apply.isEnabled}
    root.layoutSubtreeIfNeeded()
    let image=try #require(root.bitmapImageRepForCachingDisplay(in:root.bounds));root.cacheDisplay(in:root.bounds,to:image)
    try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql125-settings-first-open.png"))
  }
}
