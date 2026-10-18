import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

private actor ImportedProfiles122 {
  var profiles:[ServerProfile]=[]
  func save(_ value:ServerProfile) {profiles.append(value)}
}
@MainActor @Suite(.serialized) struct Workspace122Tests {
  private func fixture()->(StudioState,ConnectedServer,WorkbenchController,NSWindow) {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let defaults=UserDefaults(suiteName:"Studio122-"+UUID().uuidString)!
    state.explorerOrderDefaults=defaults;state.explorerTreeDefaults=defaults
    let server=ConnectedServer(profile:.init(name:"Fixture",visibleDatabases:["Demo"]),password:"")
    server.online=false;server.databases=[.init(id:5,name:"Demo")];state.servers=[server]
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.setContentSize(NSSize(width:1200,height:800))
    window.makeKeyAndOrderFront(nil)
    return (state,server,host,window)
  }
  @Test func commandWClosesAssociatedFrontPanelWithoutEditingBackgroundQuery() async throws {
    let (state,server,host,main)=fixture();defer {main.close()}
    state.warnOnTabClose=false
    let doc=state.newQuery(server:server,database:"Demo",text:"select 1;")
    let panel=host.present(Text("Fixture panel"),title:"Fixture",width:500,height:300)
    // SwiftPM has no active application/key window in this environment. Inject
    // only the OS focus boundary; native target/action and close/delegate remain real.
    host.focusedWindowProvider={ [weak panel] in panel }
    #expect((panel as? StudioAssociatedWindow)?.associatedOwner === main && panel.parent == nil && host.focusedWindowProvider() === panel)
    #expect(host.commandDocument==nil)
    host.formatSQL();#expect(doc.sql=="select 1;")
    #expect(NSApp.sendAction(#selector(WorkbenchController.closeFocusedWindow),to:host,from:nil))
    #expect(!panel.isVisible && state.documents.contains {$0 === doc})
    for _ in 0..<100 where host.auxiliaryWindows.contains(where:{$0.window === panel}) {try await Task.sleep(for:.milliseconds(2))}
    #expect(!host.auxiliaryWindows.contains {$0.window === panel} && panel.parent==nil)
  }
  @Test func objectCloseWarningIsIndependentAndKeepsDatabaseSafetyGuards() {
    let (state,server,_,window)=fixture();defer {window.close()}
    state.errorFixture={_ in};state.transactionCloseConfirmationFixture={_ in false}
    let doc=state.newQuery(server:server,text:"ALTER PROCEDURE dbo.P AS SELECT 2;")
    doc.savedText="";doc.moduleInitialSQL="ALTER PROCEDURE dbo.P AS SELECT 1;"
    for sqlWarning in [false,true] {
      state.warnOnTabClose=sqlWarning
      state.warnOnObjectClose=true
      #expect(state.requiresCloseConfirmation(doc) && state.needsBulkCloseConfirmation)
      state.warnOnObjectClose=false
      #expect(!state.requiresCloseConfirmation(doc) && !state.needsBulkCloseConfirmation)
    }
    doc.transactionCount=1;#expect(!state.close(doc));doc.transactionCount=0
    doc.confirmDiscardResultEdits={false};#expect(!state.close(doc));doc.confirmDiscardResultEdits=nil
    #expect(state.close(doc))
    #expect(SettingsSearch.entries.contains {$0.id == "objectCloseWarning"})
  }
  @Test func disabledSQLCloseWarningKeepsTransactionAndResultDraftGuards() {
    let (state,server,_,window)=fixture();defer {window.close()}
    state.warnOnTabClose=false;state.errorFixture={_ in};state.transactionCloseConfirmationFixture={_ in false}
    let doc=state.newQuery(server:server,text:"SELECT 1;")
    doc.savedText="";#expect(doc.dirty && !state.requiresCloseConfirmation(doc) && !state.needsBulkCloseConfirmation)
    doc.moduleInitialSQL="SELECT 2;";#expect(state.requiresCloseConfirmation(doc));doc.moduleInitialSQL=nil
    doc.transactionCount=1;#expect(!state.close(doc));doc.transactionCount=0
    doc.confirmDiscardResultEdits={false};#expect(!state.close(doc));doc.confirmDiscardResultEdits=nil
    #expect(state.close(doc) && state.lastClosedTab?.text=="SELECT 1;")
  }
  @Test func probeFailureClosesNormallyAndKnownOpenTransactionNeedsDisconnectApproval() async {
    let (state,server,_,window)=fixture();defer {window.close()}
    state.warnOnTabClose=false
    for known in [false,true] {
      let doc=state.newQuery(server:server,text:"SELECT 1;")
      doc.state = .ready
      doc.executionFixture={_,_ in Execution()}
      doc.sessionProbeFixture={_,_ in
        if !known {throw SQLFailure("Probe unavailable")}
        var result=Execution();result.results=[Rows(values:[["1","Demo","1"]])];return result
      }
      doc.execute();await doc.task?.value
      #expect(doc.transactionStatusKnown == known && doc.hasClosedTransaction == !known)
      var confirmations=0
      state.transactionCloseConfirmationFixture={_ in confirmations+=1;return false}
      if known {
        #expect(!state.close(doc) && state.documents.contains {$0 === doc} && doc.state == .ready)
        #expect(confirmations==1)
      }
      state.transactionCloseConfirmationFixture={_ in true}
      doc.confirmDiscardResultEdits={false}
      #expect(!state.close(doc))
      doc.confirmDiscardResultEdits=nil
      #expect(state.close(doc) && doc.state == .disconnected && !state.documents.contains {$0 === doc})
      if !known {#expect(confirmations==0)}
    }
  }
  @Test func importsStayOfflineNeverOverwriteExistingProfileAndPersistOnlyNewProfiles() async throws {
    let (state,server,_,window)=fixture();defer {window.close()}
    let doc=state.newQuery(server:server,database:"Demo",text:"SELECT 1;")
    var profile=server.profile;profile.name="Imported";profile.host="import.fixture"
    let archive=ExplorerArchive(profiles:[profile],organization:.init()),saved=ImportedProfiles122()
    #expect(try await state.importExplorer(archive,saveProfile:{await saved.save($0)})==1)
    #expect(state.servers.count==2 && state.servers[1].id != server.id && !state.servers[1].online && state.servers[1].remembered)
    #expect(server.profile.name=="Fixture" && doc.server === server && doc.sql=="SELECT 1;")
    #expect(try await state.importExplorer(archive,saveProfile:{await saved.save($0)})==0)
    #expect(await saved.profiles.count==1)
  }
  @Test func hoverMetadataIsSingleFlightCachedAndInvalidatedByConnectionGeneration() async throws {
    let server=ConnectedServer(profile:.init(),password:"");server.online=true
    var reads=0,pending:CheckedContinuation<Execution,Never>?
    server.asyncCatalogFixture={_ in reads+=1;return await withCheckedContinuation {pending=$0}}
    let first=Task {try await server.hoverMetadata.lookup(targets:[["dbo","Fn"]],database:"Demo")}
    for _ in 0..<1000 where pending==nil {try await Task.sleep(for:.milliseconds(2))}
    let second=Task {try await server.hoverMetadata.lookup(targets:[["dbo","Other"]],database:"Demo")}
    await Task.yield();second.cancel()
    #expect(reads==1)
    var e=Execution();e.results=[Rows(values:[["42","dbo","Fn","SQL_SCALAR_FUNCTION","Return Value","int"]])]
    pending?.resume(returning:e)
    #expect(try await first.value?.detail=="Scalar Function → int")
    do {_=try await second.value;Issue.record("Cancelled hover must not execute")} catch is CancellationError {} catch {Issue.record("Unexpected error")}
    #expect(try await server.hoverMetadata.lookup(targets:[["dbo","Fn"]],database:"Demo")?.detail=="Scalar Function → int" && reads==1)
    server.generation=UUID();server.asyncCatalogFixture={_ in reads+=1;return e}
    _=try await server.hoverMetadata.lookup(targets:[["dbo","Fn"]],database:"Demo");#expect(reads==2)
  }
  @Test func editorColumnHoverShowsTypeWithoutChangingSQLAndDismissesOnInteraction() async throws {
    let (state,server,_,main)=fixture();defer {main.close();StudioHoverHelp.shared.hide()}
    server.online=true
    var reads=0
    server.asyncCatalogFixture={_ in
      reads+=1;var e=Execution();e.results=[Rows(values:[["42","dbo","T","USER_TABLE","Amount","AmountType (decimal(18,2)) NOT NULL"]])];return e
    }
    let source="SELECT t.Amount FROM dbo.T t JOIN dbo.V v ON t.Amount=v.Amount;"
    let doc=state.newQuery(server:server,database:"Demo",text:source),controller=EditorController(document:doc),editor=controller.editor
    doc.intelligenceCatalog = .init(snapshot:.init(symbols:[.init(schema:"dbo",name:"T",columns:["Amount"]),.init(schema:"dbo",name:"V",columns:["Amount"],kind:"VIEW")]))
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:800,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.makeKeyAndOrderFront(nil);defer {window.close()}
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    let range=(source as NSString).range(of:"Amount"),selection=editor.selectedRange(),hadUndo=editor.undoManager?.canUndo
    let rect=editor.firstRect(forCharacterRange:NSRange(location:range.location+2,length:0),actualRange:nil)
    let local=editor.convert(window.convertFromScreen(rect),from:nil)
    let point=NSPoint(x:local.minX+1,y:local.midY)
    editor.hoverMoved?(point)
    let deadline=ContinuousClock.now.advanced(by:.seconds(3))
    while StudioHoverHelp.shared.visibleTitle==nil,ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(5))}
    #expect(StudioHoverHelp.shared.visibleTitle=="dbo.T.Amount" && StudioHoverHelp.shared.visibleDetail=="AmountType (decimal(18,2)) NOT NULL")
    #expect(reads==1 && editor.string==source && editor.selectedRange()==selection && editor.undoManager?.canUndo==hadUndo)
    if let popup=window.childWindows?.first(where:{$0 is NSPanel}),let view=popup.contentView {
      view.layoutSubtreeIfNeeded();popup.displayIfNeeded()
      let bitmap=try #require(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/MSSQLStudio-type-hover122.png"))
    }
    editor.dismissSuggestions?();#expect(StudioHoverHelp.shared.visibleTitle==nil && doc.sql==source)
    for object in ["dbo.T","dbo.V"] {
      let objectRange=(source as NSString).range(of:object)
      let rect=editor.firstRect(forCharacterRange:NSRange(location:NSMaxRange(objectRange)-1,length:0),actualRange:nil)
      let local=editor.convert(window.convertFromScreen(rect),from:nil)
      editor.hoverMoved?(NSPoint(x:local.minX+1,y:local.midY))
      let deadline=ContinuousClock.now.advanced(by:.milliseconds(600))
      while ContinuousClock.now<deadline,reads==1,StudioHoverHelp.shared.visibleTitle==nil {try await Task.sleep(for:.milliseconds(5))}
      #expect(reads==1 && StudioHoverHelp.shared.visibleTitle==nil)
    }
  }
  @Test func indexIconsStayVisibleAfterSidebarResizeWithoutCollapsingTree() throws {
    let (_,server,host,window)=fixture();defer {window.close()}
    let db=try #require(host.explorerTree.databaseNode(server:server,database:"Demo"))
    var ancestors:[TreeNode]=[],parent=db.parent
    while let node=parent {ancestors.append(node);parent=node.parent}
    for node in ancestors.reversed() {host.outline.expandItem(node)}
    for width in [CGFloat(300),140,230] {
      host.split.splitView.setPosition(width,ofDividerAt:0);host.view.layoutSubtreeIfNeeded();host.outline.layoutSubtreeIfNeeded()
      let row=host.outline.row(forItem:db);#expect(row>=0)
      let index=try #require(host.outline.tableColumns.firstIndex {$0.identifier.rawValue=="indexes"})
      let cell=try #require(host.outline.view(atColumn:index,row:row,makeIfNecessary:true));cell.layoutSubtreeIfNeeded()
      let icons=cell.subviews.compactMap {$0 as? DatabaseIndexButton}
      #expect(icons.count==2)
      for icon in icons {
        let frame=host.outline.convert(icon.bounds,from:icon)
        #expect(frame.width>0 && frame.minX>=host.outline.visibleRect.minX && frame.maxX<=host.outline.visibleRect.maxX+1,"Icon \(frame), viewport \(host.outline.visibleRect)")
      }
    }
    let menu=StudioMenu();host.populateExplorerMenu(menu,for:db)
    #expect(!menu.items.contains {$0.title=="Yerel İndeks Durumu…"})
  }
}
