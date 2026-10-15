import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct WorkflowImprovementsTests {
  private func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
  @Test func cancelledCatalogWorkDoesNotBecomeAnExplorerWarning() async {
    let server=ConnectedServer(profile:.init(),password:"")
    server.recordExplorerFailure(CancellationError())
    await server.recordCatalogFailure(CancellationError(),generation:server.generation)
    #expect(server.startupError==nil && server.online)
    server.recordExplorerFailure(SQLFailure("Permission denied"))
    #expect(server.startupError != nil && server.online)
  }
  @Test func manualQueryDuringConnectKeepsItsTextAndFocus() {
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let before=state.active
    let manual=state.newQuery(server:server,text:"SELECT writing_in_progress",startConnection:false)
    state.completeExplorerConnection(server,previousActive:before)
    #expect(state.documents.count==1 && state.active === manual && manual.sql=="SELECT writing_in_progress")
    let other=ConnectedServer(profile:.init(),password:"");other.online=false
    state.completeExplorerConnection(other,previousActive:before)
    #expect(state.documents.count==1 && state.active === manual)
  }
  @Test func resultMetadataFollowsQueryConnectionAndRejectsChangedContext() async throws {
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let document=QueryDocument(server:server,database:"master",title:"Independent")
    document.state = .ready;document.sql="SELECT * FROM dbo.T;"
    document.executionFixture={_,_ in
      var result=Execution();result.results=[Rows(fields:[Field("Id",type:4)],values:[["1"]])];return result
    }
    document.execute();await document.task?.value
    var reads=0
    server.catalogFixture={_ in reads+=1;return Execution()}
    _=try await document.resultEditingMetadata("SELECT metadata",database:"master")
    #expect(reads==1 && !server.online && document.canEditLoadedRows)
    document.state = .disconnected
    await #expect(throws:SQLFailure.self) {try await document.resultEditingMetadata("SELECT metadata",database:"master")}
    document.state = .ready;document.transactionCount=1
    await #expect(throws:SQLFailure.self) {try await document.resultEditingMetadata("SELECT metadata",database:"master")}
    document.transactionCount=0
    server.catalogFixture={_ in reads+=1;document.database="Changed";return Execution()}
    await #expect(throws:SQLFailure.self) {try await document.resultEditingMetadata("SELECT metadata",database:"master")}
    #expect(reads==2)
  }
  @Test func explorerDiskStatusRemainsAvailableForOfflineIndex() {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let emptyHost=WorkbenchController(state:state);_=emptyHost.view
    emptyHost.updateIndexStatus();#expect(emptyHost.indexStatus.isHidden)
    let server=ConnectedServer(profile:.init(name:"Offline"),password:"");server.online=false
    state.servers=[server]
    let host=WorkbenchController(state:state);_=host.view
    host.updateIndexStatus();#expect(!host.indexStatus.isHidden)
    server.online=true
    host.updateIndexStatus();#expect(!host.indexStatus.isHidden)
    server.online=false
    host.updateIndexStatus();#expect(!host.indexStatus.isHidden)
  }
  @Test func connectionFailureKeepsTooltipWithoutWarningSuffixOrOrangeName() throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:.init(name:"HARMAN"),password:"")
    server.online=false;server.startupError="Sentetik bağlantı hatası"
    state.servers=[server]
    let host=WorkbenchController(state:state);_=host.view
    let node=try #require(host.roots.first)
    let cell=try #require(host.outlineView(host.outline,viewFor:host.outline.tableColumns[0],item:node) as? NSTableCellView)
    #expect(cell.textField?.stringValue=="HARMAN")
    #expect(cell.textField?.textColor == NSColor.labelColor)
    #expect(cell.toolTip?.contains("Sentetik bağlantı hatası")==true)
    #expect(cell.imageView?.image != nil)
  }
  @Test func cappedSuccessfulSelectAllowsEditingButStoppedReadDoesNot() async {
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let document=QueryDocument(server:server,database:"master",title:"Capped")
    document.state = .ready;document.sql="SELECT * FROM dbo.T;"
    document.executionFixture={_,_ in
      var result=Execution();var rows=Rows(fields:[Field("Id",type:4)],values:[["1"]]);rows.truncated=true
      result.results=[rows];result.partial=true;return result
    }
    document.execute();await document.task?.value
    #expect(document.partial && document.canEditLoadedRows)
    document.executionFixture={_,_ in
      var result=Execution();result.results=[Rows(fields:[Field("Id",type:4)],values:[["1"]])];result.partial=true;result.stoppedEarly=true;return result
    }
    document.execute();await document.task?.value
    #expect(document.canRefresh && !document.canEditLoadedRows)
  }
  @Test func selectScriptUsesFreshColumnsAndRejectsPartialMetadata() async throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    server.catalogFixture={_ in var result=Execution();result.results=[Rows(values:[["2","Name","",""],["1","Id","",""]])];return result}
    let host=WorkbenchController(state:state)
    let node=TreeNode("dbo.T",kind:.object(.tables),server:server,database:"master",item:.init(id:42,name:"T",schema:"dbo"))
    #expect(try await host.selectScript(node,top:100)=="SELECT TOP (100)\n    [Id],\n    [Name]\nFROM [dbo].[T];")
    server.catalogFixture={_ in var result=Execution();result.partial=true;return result}
    await #expect(throws:SQLFailure.self) {try await host.selectScript(node)}
    #expect(state.documents.isEmpty)
  }
  @Test func finderEnterCyclesMatchesAndKeepsSearchFieldFocus() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let document=QueryDocument(server:server,database:"master",title:"Find");document.sql="SELECT 1;\nSELECT 2;\nSELECT 3;"
    let controller=EditorController(document:document),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:800,height:450),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.orderFront(nil)
    defer {editor.sqlFinder.performAction(.hideFindInterface);window.close()}
    editor.setSelectedRange(NSRange(location:0,length:6));window.makeFirstResponder(editor);editor.showSelectionFind()
    controller.surface.layoutSubtreeIfNeeded()
    let bar=try #require(controller.findContainer.findBarView)
    let field=try #require(views(bar).compactMap {$0 as? NSTextField}.first {$0.isEditable})
    #expect(window.makeFirstResponder(field))
    let enter=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36))
    var matches:[Int]=[]
    for _ in 0..<4 {
      #expect(editor.handleFindKey(enter))
      matches.append(editor.selectedRange().location)
      #expect((window.firstResponder as? NSTextView)?.isFieldEditor == true && controller.findContainer.isFindBarVisible)
    }
    #expect(Set(matches.prefix(3)).count==3 && matches.first==matches.last)
    #expect(editor.string==document.sql)
  }
  @Test func wildcardTabAcceptanceIsOneUndoAndNoArgumentCaretFinishesAfterCall() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let document=QueryDocument(server:server,database:"master",title:"Wildcard")
    document.intelligenceCatalog = .init(snapshot:.init(symbols:[.init(schema:"dbo",name:"T",columns:["Id","Name"])]))
    document.catalogDatabase="master";document.sql="SELECT * FROM T"
    let controller=EditorController(document:document),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:50,y:50,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.makeKeyAndOrderFront(nil)
    defer {controller.closeExecutionAssistance();window.close()}
    window.makeFirstResponder(editor);editor.setSelectedRange(NSRange(location:8,length:0));editor.undoManager?.removeAllActions()
    controller.scheduleIntelligence(manual:true)
    for _ in 0..<200 where !controller.completionShown {try await Task.sleep(for:.milliseconds(10))}
    #expect(controller.completionShown)
    let tab=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48))
    editor.keyDown(with:tab)
    #expect(!editor.string.contains("*") && editor.string.contains("Name") && editor.string.hasSuffix(" FROM T"))
    editor.undoManager?.undo();#expect(editor.string=="SELECT * FROM T")
    document.sql="SELECT GETDATE";controller.setText();editor.setSelectedRange(NSRange(location:14,length:0));window.makeFirstResponder(editor)
    controller.scheduleIntelligence(manual:true)
    for _ in 0..<200 where !controller.completionShown {try await Task.sleep(for:.milliseconds(10))}
    #expect(controller.completionShown)
    editor.keyDown(with:tab)
    #expect(editor.string=="SELECT GETDATE()" && editor.selectedRange().location==16)
  }
  @Test func searchHighlightsOnlyBoundedPresentationAndCopiesCellSafely() throws {
    _=NSApplication.shared
    let cell=GridDataCell(textCell:"Stok STOK stok");cell.searchTerm="stok"
    let value=cell.highlightedValue()
    #expect(value.string==cell.stringValue)
    #expect(value === cell.highlightedValue())
    cell.searchTerm="absent";#expect(cell.highlightedValue().attribute(.backgroundColor,at:0,effectiveRange:nil)==nil)
    cell.searchTerm="stok"
    for location in [0,5,10] {#expect(value.attribute(.backgroundColor,at:location,effectiveRange:nil) != nil)}
    let clone=try #require(cell.copy() as? GridDataCell)
    #expect(clone.searchTerm=="stok" && clone.stringValue==cell.stringValue)
    cell.stringValue=String(repeating:"x",count:100_000)+"stok"
    #expect(cell.highlightedValue().length==1000 && cell.stringValue.utf16.count==100004)
    #expect(NSImage(systemSymbolName:"externaldrive.badge.checkmark",accessibilityDescription:nil) != nil)
  }
  @Test func longExplorerNamesScrollWithoutEllipsisAndKeepIndexControlsVisible() throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let defaults=UserDefaults(suiteName:"WorkflowExplorer-"+UUID().uuidString)!
    state.explorerOrderDefaults=defaults;state.explorerTreeDefaults=defaults
    let database=String(repeating:"Database_",count:12)
    let server=ConnectedServer(profile:.init(name:"Fixture",visibleDatabases:[database]),password:"")
    server.online=false;server.databases=[.init(id:5,name:database)];state.servers=[server]
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.setContentSize(NSSize(width:1200,height:800));window.orderFront(nil)
    defer {window.close()}
    let node=try #require(host.explorerTree.databaseNode(server:server,database:database))
    var ancestors:[TreeNode]=[],parent=node.parent
    while let value=parent {ancestors.append(value);parent=value.parent}
    for value in ancestors.reversed() {host.outline.expandItem(value)}
    host.view.layoutSubtreeIfNeeded();host.outline.layoutSubtreeIfNeeded()
    let scroll=try #require(host.outline.enclosingScrollView as? ExplorerScrollView)
    scroll.tile()
    let row=host.outline.row(forItem:node)
    let name=try #require(host.outline.view(atColumn:0,row:row,makeIfNecessary:true) as? NSTableCellView)
    #expect(name.textField?.lineBreakMode == .byClipping && name.textField?.stringValue==database)
    #expect(scroll.hasHorizontalScroller && host.outline.frame.width>scroll.contentView.bounds.width)
    for x in [CGFloat(0),100,300] {
      scroll.contentView.scroll(to:NSPoint(x:x,y:scroll.contentView.bounds.minY));scroll.reflectScrolledClipView(scroll.contentView)
      let cell=try #require(host.outline.view(atColumn:1,row:row,makeIfNecessary:true) as? ExplorerIndexCell)
      cell.pinToViewport();cell.layoutSubtreeIfNeeded()
      for button in cell.subviews.compactMap({$0 as? DatabaseIndexButton}) {
        let rect=host.outline.convert(button.bounds,from:button)
        #expect(rect.minX>=host.outline.visibleRect.minX && rect.maxX<=host.outline.visibleRect.maxX+1)
      }
    }
  }
  @Test func indexCellNeverCoversObjectColumnDuringReattachment() {
    let outline=IndexViewportFixture(frame:NSRect(x:0,y:0,width:320,height:120))
    let objects=NSTableColumn(identifier:.init("object"));objects.width=264
    let indexes=NSTableColumn(identifier:.init("indexes"));indexes.width=56
    outline.addTableColumn(objects);outline.addTableColumn(indexes)
    let row=NSTableRowView(frame:outline.bounds)
    outline.addSubview(row)
    let cell=ExplorerIndexCell();cell.outline=outline;row.addSubview(cell)
    #expect(cell.clipsToBounds)
    for width in [CGFloat(320),640,1200,0,56] {
      cell.frame=NSRect(x:0,y:0,width:width,height:24)
      #expect(cell.frame.width==56)
      cell.setFrameSize(NSSize(width:width,height:24))
      #expect(cell.frame.width==56)
      #expect(cell.frame.minX==outline.bounds.maxX-56)
      #expect(cell.frame.maxX==outline.bounds.maxX)
    }
  }
  @Test func indexAreaPreservesConnectionTintAndSelectedRowBackground() throws {
    _=NSApplication.shared
    for selected in [false,true] {
      for hasIcons in [false,true] {
        let row=ConnectionTreeRow(frame:NSRect(x:0,y:0,width:320,height:24))
        row.color = .systemRed;row.isServer=true;row.isSelected=selected
        let cell=ExplorerIndexCell(frame:NSRect(x:264,y:0,width:56,height:24))
        row.addSubview(cell)
        if hasIcons {cell.addSubview(NSView(frame:NSRect(x:4,y:4,width:16,height:16)))}
        let image=NSImage(size:row.bounds.size)
        image.lockFocus()
        StudioTheme.explorerCanvas.setFill();row.bounds.fill()
        row.drawBackground(in:row.bounds)
        if selected {row.drawSelection(in:row.bounds)}
        NSGraphicsContext.saveGraphicsState()
        let transform=NSAffineTransform();transform.translateX(by:264,yBy:0);transform.concat()
        cell.draw(cell.bounds)
        NSGraphicsContext.restoreGraphicsState()
        image.unlockFocus()
        let data=try #require(image.tiffRepresentation)
        let bitmap=try #require(NSBitmapImageRep(data:data))
        let left=try #require(bitmap.colorAt(x:100,y:12)?.usingColorSpace(.sRGB))
        let right=try #require(bitmap.colorAt(x:280,y:12)?.usingColorSpace(.sRGB))
        #expect(abs(left.redComponent-right.redComponent)<0.02)
        #expect(abs(left.greenComponent-right.greenComponent)<0.02)
        #expect(abs(left.blueComponent-right.blueComponent)<0.02)
      }
    }
  }
  @Test func jobPropertiesLoadsLiveHeaderAndReusesWindowWithFreshRead() async throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let id=UUID().uuidString
    var reads=0
    server.catalogFixture={sql in
      reads+=1
      var output=Execution()
      output.results=[Rows(values:[[id,"Live job","1","Description","sa","Idle","2026-10-15T12:00:00","Category","2026-10-14T11:00:00","1","0","","0","0","2026-10-15 09:00:00","1","","3"]]),Rows(),Rows()]
      return output
    }
    let host=WorkbenchController(state:state)
    let node=TreeNode("Live job",kind:.object(.jobs),server:server,item:.init(name:"Live job"))
    host.showAgentProperties(node)
    let window=try #require(host.auxiliaryWindows.first?.window)
    defer {window.close()}
    for _ in 0..<200 where reads==0 {try await Task.sleep(for:.milliseconds(10))}
    var name:NSTextField?
    for _ in 0..<200 {
      name=views(try #require(window.contentView)).compactMap {$0 as? NSTextField}.first {$0.stringValue=="Live job" && $0.isEditable}
      if name != nil {break}
      try await Task.sleep(for:.milliseconds(10))
    }
    #expect(name != nil && reads==1)
    let previous=reads
    host.showAgentProperties(node)
    for _ in 0..<200 where reads==previous {try await Task.sleep(for:.milliseconds(10))}
    #expect(reads==previous+1 && host.auxiliaryWindows.count==1 && state.documents.isEmpty)
  }
  @Test func messageColorsPreserveContentAndMenusKeepValidationWithIcons() {
    _=NSApplication.shared
    let source="Çalıştırma: test\n[42000] SQL error\n500 satır sınırına ulaşıldı\n(1 satır etkilendi)\n"
    let text=ResultMessagesView();text.show(source)
    #expect(text.string==source)
    let location=(source as NSString).range(of:"[42000]").location
    #expect(text.textStorage?.attribute(.foregroundColor,at:location,effectiveRange:nil) as? NSColor == StudioTheme.danger)
    let menu=StudioMenu();menu.autoenablesItems=false
    let item=menu.addItem(withTitle:"Bağlantı ayarları",action:nil,keyEquivalent:"");item.isEnabled=false
    menu.addItem(.separator());menu.update()
    #expect(item.image != nil && !item.isEnabled && item.view==nil && menu.items[1].isSeparatorItem)
  }
}

@MainActor private final class IndexViewportFixture:NSOutlineView {
  override var visibleRect:NSRect {bounds}
}
