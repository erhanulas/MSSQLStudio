import AppKit
import Testing
@testable import MSSQLStudio
@testable import SQLServerKit

@MainActor @Suite(.serialized) struct Workspace119Tests {
  private func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
  private func fixture()->(StudioState,ConnectedServer) {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let disk=CatalogDiskIndex(url:state.folder.appendingPathComponent("catalog119-\(UUID()).sqlite"))
    let completion=SQLCatalogService(index:disk,refreshFixture:{_,_,_ in .init(symbols:[.init(schema:"dbo",name:"Example",columns:[],kind:"USER_TABLE")])})
    let server=ConnectedServer(profile:ServerProfile(name:"Workspace fixture",visibleDatabases:["DemoDB"]),password:"",diskIndex:disk,objectIndexService:CatalogIndexService(index:disk),completionIndexService:completion)
    server.online=false;server.databases=[.init(id:5,name:"DemoDB")];state.servers=[server]
    return (state,server)
  }
  @Test func executeKeepsEditorResponderSelectionAndViewport() async throws {
    let (state,server)=fixture()
    let doc=state.newQuery(server:server,database:"DemoDB",text:(1...100).map {"SELECT \($0);"}.joined(separator:"\n"))
    doc.state = .ready
    let controller=QueryController(document:doc),window=NSWindow(contentViewController:controller)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.setContentSize(NSSize(width:900,height:650));window.orderFront(nil);defer {window.close()}
    let editor=try #require(views(controller.view).compactMap {$0 as? SQLTextView}.first),selection=NSRange(location:350,length:8)
    let scroll=try #require(editor.enclosingScrollView)
    editor.setSelectedRange(selection);controller.focusEditor()
    let origin=scroll.contentView.bounds.origin
    var pending:CheckedContinuation<Execution,Never>?
    doc.executionFixture={_,_ in await withCheckedContinuation {pending=$0}}
    #expect(doc.lastExecutionDate==nil)
    let before=Date();doc.execute()
    #expect(doc.lastExecutionDate.map {$0>=before} == true)
    for _ in 0..<1000 where pending == nil {try await Task.sleep(for:.milliseconds(2))}
    #expect(window.firstResponder === editor && editor.selectedRange()==selection)
    var output=Execution();output.results=[Rows(fields:[Field("n")],values:[["1"]])]
    pending?.resume(returning:output)
    for _ in 0..<1000 where doc.busy {try await Task.sleep(for:.milliseconds(2))}
    #expect(!doc.busy && window.firstResponder === editor)
    #expect(editor.selectedRange()==selection && scroll.contentView.bounds.origin==origin)
  }
  @Test func emptyViewportClickShowsCaretWithoutInsertingBlankLines() throws {
    let (_,server)=fixture()
    let doc=QueryDocument(server:server,database:"DemoDB",title:"Blank"),controller=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:600,height:350),styleMask:[],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.orderFront(nil);defer {window.close()}
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    let editor=controller.editor
    let event=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:editor.convert(NSPoint(x:150,y:250),to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1))
    editor.mouseDown(with:event)
    let caret=editor.firstRect(forCharacterRange:NSRange(location:0,length:0),actualRange:nil)
    #expect(window.firstResponder === editor && editor.selectedRange()==NSRange(location:0,length:0))
    #expect(caret.height>0 && window.frame.intersects(caret))
    #expect(doc.sql.isEmpty && editor.undoManager?.canUndo != true)
  }
  @Test func initialSelectionAndClosedTabReopenPreserveSQLWithoutRunning() throws {
    let (state,server)=fixture(),text="SELECT 1;\nSELECT N'İstanbul';\nSELECT 3;"
    let first=state.newQuery(server:server,database:"DemoDB",text:text,title:"Original",selection:NSRange(location:22,length:4))
    let editor=EditorController(document:first)
    #expect(editor.editor.selectedRange()==NSRange(location:22,length:4))
    #expect(state.close(first,discardChanges:true))
    let record=try #require(state.lastClosedTab)
    #expect(record.text==text && record.tabTitle=="Original" && record.database=="DemoDB")
    let restored=try #require(state.reopenClosedTab(record))
    #expect(restored.sql==text && restored.state == .disconnected && restored.selectedRange==NSRange(location:22,length:4))
    #expect(state.lastClosedTab==nil && state.history.isEmpty)
    #expect(EditorController(document:restored).editor.selectedRange()==restored.selectedRange)
    let fresh=state.newQuery(server:server,text:"SELECT 10;")
    #expect(EditorController(document:fresh).editor.selectedRange().location==0)
  }
  @Test func closedTabsPersistInHistoryAndQueuedWritesKeepLatestSnapshot() async throws {
    let (state,server)=fixture()
    #expect(state.folder.path.hasPrefix("/tmp/"))
    let url=state.folder.appendingPathComponent("history.json"),previous=try? Data(contentsOf:url)
    defer {if let previous {try? previous.write(to:url,options:.atomic)} else {try? FileManager.default.removeItem(at:url)}}
    state.historyEnabled=true;state.history=[]
    let doc=state.newQuery(server:server,database:"DemoDB",text:"SELECT N'Kaybolmasın';",title:"Closed",selection:NSRange(location:10,length:0))
    #expect(state.close(doc,discardChanges:true))
    let record=try #require(state.lastClosedTab)
    #expect(await state.flushHistory())
    let loaded=try JSONDecoder().decode([QueryRecord].self,from:Data(contentsOf:url))
    #expect(loaded.first?.tabTitle=="Closed" && loaded.first?.caret==10 && loaded.first?.status=="Kapatılan Sekme")
    let other=StudioState();other.servers=[server];other.historyEnabled=true;other.loadHistory()
    #expect(await other.flushHistory())
    #expect(other.lastClosedTab?.id==record.id)
    _=state.reopenClosedTab(record)
    for index in 0..<20 {state.history[0].text="SELECT \(index);";state.saveHistory()}
    #expect(await state.flushHistory())
    let final=try JSONDecoder().decode([QueryRecord].self,from:Data(contentsOf:url))
    #expect(final[0].text=="SELECT 19;" && final[0].reopenedAt != nil)
  }
  @Test func closedTabLimitUsesActiveDatabaseAndEmptyTabsAreIgnored() {
    let (state,server)=fixture();state.closedTabLimit=2
    for db in ["DemoDB","Other"] {
      for index in 0..<3 {
        let doc=state.newQuery(server:server,database:db,text:"SELECT \(index);",title:"\(db) \(index)")
        #expect(state.close(doc,discardChanges:true))
      }
    }
    #expect(state.closedTabs.count==4)
    let current=state.newQuery(server:server,database:"DemoDB",text:" \n\t")
    #expect(state.lastClosedTab?.database=="DemoDB" && state.lastClosedTab?.text=="SELECT 2;")
    #expect(state.close(current,discardChanges:true) && state.closedTabs.count==4)
    let other=state.newQuery(server:server,database:"Other",text:"SELECT 100;")
    #expect(state.lastClosedTab(for:current)?.database=="DemoDB" && state.lastClosedTab?.database=="Other")
    let host=WorkbenchController(state:state)
    let item=host.tabMenu(for:current).items.first {$0.title=="Kapatılan Sekmeyi Aç"}
    #expect(item?.representedObject as? QueryDocument === current)
    host.reopenLastClosedTab(item)
    #expect(state.active?.database=="DemoDB" && state.active !== other)

  }
  @Test func explorerUsesActualViewTypeInsteadOfLegacyCompletionKindAndRetriesFailedBranch() async throws {
    let (state,server)=fixture();server.online=true
    server.asyncCatalogFixture={sql in
      var result=Execution()
      if sql.contains("sys.objects") || sql.contains("sys.views") {result.results=[Rows(values:[["12","Example","dbo","VIEW"]])]}
      return result
    }
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));defer {window.close()}
    let doc=state.newQuery(server:server,database:"DemoDB",text:"SELECT * FROM dbo.Example;")
    doc.applyTargetedCatalog(.init(snapshot:.init(symbols:[.init(schema:"dbo",name:"Example",columns:[])])),database:"DemoDB",generation:server.generation)
    let db=host.explorerTree.databaseNode(server:server,database:"DemoDB")
    let views=db?.children.first {if case .folder(.views)=$0.kind {return true};return false}
    views?.loaded=true;views?.error="Previous failure"
    var errors:[String]=[];state.errorFixture={errors.append($0)}
    host.revealExplorerObject(["dbo","Example"],document:doc);await host.explorerRevealTask?.value
    let selected=host.outline.item(atRow:host.outline.selectedRow) as? TreeNode
    #expect(errors.isEmpty && selected?.item?.name=="Example")
    if let selected {if case .object(.views)=selected.kind {} else {Issue.record("View must be selected in Views")}}
    #expect(doc.lastExecutionDate==nil && doc.state == .disconnected)
  }
  @Test func unreadableHistoryIsNeverReplacedByClosingATab() async throws {
    let (state,server)=fixture();state.historyEnabled=true
    let url=state.folder.appendingPathComponent("history.json"),previous=try? Data(contentsOf:url)
    defer {if let previous {try? previous.write(to:url,options:.atomic)} else {try? FileManager.default.removeItem(at:url)}}
    try FileManager.default.createDirectory(at:state.folder,withIntermediateDirectories:true)
    let damaged=Data("{damaged history".utf8);try damaged.write(to:url,options:.atomic)
    var errors:[String]=[];state.errorFixture={errors.append($0)}
    state.loadHistory()
    let doc=state.newQuery(server:server,text:"SELECT 1;")
    #expect(state.close(doc,discardChanges:true))
    #expect(!(await state.flushHistory()) && !errors.isEmpty)
    #expect(try Data(contentsOf:url)==damaged)
    #expect(state.lastClosedTab?.text=="SELECT 1;")
  }
  @Test func explorerMenusOfferOneRefreshAndNoConnectionRename() {
    let (state,server)=fixture();server.online=true;server.catalogFixture=ObjectManagementUIFixture.catalog
    let host=WorkbenchController(state:state)
    for kind in [TreeNode.Kind.server,.database] {
      let node=TreeNode("DemoDB",kind:kind,server:server,database:"DemoDB"),menu=StudioMenu()
      host.populateExplorerMenu(menu,for:node)
      #expect(menu.items.filter {$0.title=="Yenile"}.count==1)
      #expect(!menu.items.contains {$0.title.contains("Bağlantıyı Yeniden") || $0.title=="Yerel İndeksi Yenile"})
    }
    let doc=state.newQuery(server:server,text:"SELECT 1")
    let menu=host.tabMenu(for:doc)
    #expect(menu.items.contains {$0.title=="Kapatılan Sekmeyi Aç" && $0.keyEquivalent==GridShortcuts.binding(.reopenTab).key})
    #expect(menu.items.contains {$0.title=="History…"})
  }
  @Test func statusBarShowsPerDocumentExecutionDateWithThemedSurfaceAndConnectionIcon() async throws {
    let (state,server)=fixture()
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));defer {window.close()}
    let doc=state.newQuery(server:server,database:"DemoDB",text:"SELECT 1;")
    doc.state = .ready;doc.executionFixture={_,_ in Execution()}
    doc.execute()
    for _ in 0..<1000 where doc.busy {try await Task.sleep(for:.milliseconds(2))}
    host.updateControls()
    #expect(host.executionDate.stringValue.contains(try #require(doc.lastExecutionDate).formatted(date:.numeric,time:.standard)))
    #expect(host.statusStrip.subviews.contains {$0 is NSBox})
    #expect(host.statusStrip.layer?.backgroundColor==StudioTheme.statusCanvas.cgColor)
    #expect(host.roots.first?.displayTitle==server.profile.name)
    _=state.newQuery(server:server,database:"Other",text:"")
    host.updateControls();#expect(host.executionDate.stringValue=="Son çalıştırma: —")
  }
  @Test(arguments:[false,true]) func editorRevealsOnlyTheMatchingExplorerObjectAndKeepsSQL(searchOpen:Bool) async throws {
    let (state,server)=fixture();server.online=true
    server.asyncCatalogFixture={sql in
      var value=Execution()
      if sql.contains("sys.tables") || sql.contains("sys.objects") {value.results=[Rows(values:[["12","Example","dbo","USER_TABLE"]])]}
      return value
    }
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));defer {window.close()}
    let doc=state.newQuery(server:server,database:"DemoDB",text:"SELECT * FROM dbo.Example;")
    doc.applyTargetedCatalog(SQLIntelligence.Catalog(snapshot:.init(symbols:[.init(schema:"dbo",name:"Example",columns:[],kind:"USER_TABLE")])),database:"DemoDB",generation:server.generation)
    if searchOpen {host.showExplorerSearch(true)}
    var errors:[String]=[];state.errorFixture={errors.append($0)}
    host.revealExplorerObject(["dbo","Example"],document:doc)
    await host.explorerRevealTask?.value
    #expect(errors.isEmpty && !host.showingSearch && host.explorerTabs.selectedSegment==0)
    let selected=host.outline.item(atRow:host.outline.selectedRow) as? TreeNode
    #expect(selected?.item?.name=="Example" && selected?.database=="DemoDB")
    #expect(doc.sql=="SELECT * FROM dbo.Example;" && doc.state == .disconnected)
  }
  @Test func offlineExplorerNavigationUsesDefinitionIndexWithoutConnecting() async throws {
    let (state,server)=fixture()
    server.profile.indexObjectDefinitions=true;server.online=true
    await server.definitionIndex.configure()
    await server.definitionIndex.record(.init(id:12,schema:"dbo",name:"Example",type:"U",sql:"CREATE TABLE dbo.Example(n int);"),database:"DemoDB",generation:server.generation)
    server.online=false
    var reads=0;server.asyncCatalogFixture={_ in reads+=1;return Execution()}
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));defer {window.close()}
    let doc=state.newQuery(server:server,database:"DemoDB",text:"SELECT * FROM dbo.Example;")
    var errors:[String]=[];state.errorFixture={errors.append($0)}
    host.revealExplorerObject(["dbo","Example"],document:doc)
    await host.explorerRevealTask?.value
    #expect(errors.isEmpty && reads==0)
    #expect((host.outline.item(atRow:host.outline.selectedRow) as? TreeNode)?.item?.name=="Example")
    #expect(doc.state == .disconnected && doc.sql=="SELECT * FROM dbo.Example;")
  }
  @Test func delayedExplorerNavigationCannotStealFocusAfterEditing() async throws {
    let (state,server)=fixture();server.online=true
    var pending:CheckedContinuation<Execution,Never>?
    server.asyncCatalogFixture={_ in await withCheckedContinuation {pending=$0}}
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));defer {window.close()}
    let doc=state.newQuery(server:server,database:"DemoDB",text:"SELECT * FROM dbo.Example;")
    doc.applyTargetedCatalog(SQLIntelligence.Catalog(snapshot:.init(symbols:[.init(schema:"dbo",name:"Example",columns:[],kind:"USER_TABLE")])),database:"DemoDB",generation:server.generation)
    let editor=try #require(views(host.view).compactMap {$0 as? SQLTextView}.first)
    window.makeFirstResponder(editor)
    host.revealExplorerObject(["dbo","Example"],document:doc)
    let task=host.explorerRevealTask
    for _ in 0..<1000 where pending==nil {try await Task.sleep(for:.milliseconds(2))}
    #expect(pending != nil)
    doc.sql="SELECT 42;";doc.changed?()
    var output=Execution();output.results=[Rows(values:[["12","Example","dbo","USER_TABLE"]])]
    pending?.resume(returning:output)
    await task?.value
    #expect(window.firstResponder === editor && doc.sql=="SELECT 42;")
    #expect((host.outline.item(atRow:host.outline.selectedRow) as? TreeNode)?.item?.name != "Example")
  }
  @Test func readonlyRulerUsesTopOriginAndRemainsVisibleAfterScrollAndTheme() throws {
    let old=StudioTheme.mode;defer {StudioTheme.apply(old)}
    let scroll=SQLPreviewView(frame:NSRect(x:0,y:0,width:620,height:300))
    let window=NSWindow(contentRect:scroll.frame,styleMask:[],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.contentView=scroll;defer {window.close()}
    let sql=(1...100).map {"SELECT \($0);"}.joined(separator:"\n")
    scroll.display(sql);scroll.layoutSubtreeIfNeeded()
    let ruler=scroll.ruler
    #expect(ruler.isFlipped && !ruler.isHidden && ruler.frame.width>0)
    scroll.scroll.contentView.scroll(to:NSPoint(x:-scroll.scroll.contentView.contentInsets.left,y:400));scroll.scroll.reflectScrolledClipView(scroll.scroll.contentView)
    StudioTheme.apply("dark");scroll.layoutSubtreeIfNeeded()
    #expect(!ruler.isHidden && ruler.isFlipped && (scroll.textView as? NSTextView)?.string==sql)
    #expect(scroll.scroll.contentView.bounds.minY>=400)
    window.orderFront(nil);window.displayIfNeeded()
    #expect(ruler.bounds.origin == .zero)
    #expect(scroll.scroll.contentView.bounds.minX == -scroll.scroll.contentView.contentInsets.left)
    let text=try #require(scroll.textView as? NSTextView)
    #expect(text.convert(.zero,to:scroll).x >= ruler.frame.maxX)
    let bitmap=try #require(scroll.bitmapImageRepForCachingDisplay(in:scroll.bounds))
    scroll.cacheDisplay(in:scroll.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/MSSQLStudio-readonly119.png"))
    let diff=SQLInlineDiffView(frame:NSRect(x:0,y:0,width:900,height:300))
    #expect(diff.leftRuler.isFlipped && diff.rightRuler.isFlipped)
    window.contentView=diff;window.setContentSize(NSSize(width:900,height:300))
    let original="SELECT 1 AS n;\nSELECT 2 AS m;",edited="SELECT 1 AS n;\nSELECT 3 AS m;"
    diff.display(comparison:SQLTextDiff.compare(original,edited),original:original,edited:edited,changeIndex:0)
    diff.layoutSubtreeIfNeeded();window.displayIfNeeded()
    #expect(diff.left.frame.minX==diff.leftRuler.frame.maxX && diff.right.frame.minX==diff.rightRuler.frame.maxX)
    let diffBitmap=try #require(diff.bitmapImageRepForCachingDisplay(in:diff.bounds))
    diff.cacheDisplay(in:diff.bounds,to:diffBitmap)
    try diffBitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/MSSQLStudio-diff119.png"))
  }
}
