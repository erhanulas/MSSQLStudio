import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorPairFindParameterTests {
  @Test func parameterPopoverUpdatesItsHostWithoutClosing() throws {
    _=NSApplication.shared
    let window=NSWindow(contentRect:NSRect(x:100,y:100,width:900,height:700),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    let host=try #require(window.contentView),popup=NSPopover()
    defer {popup.close();window.close()}
    window.orderFront(nil)
    let anchor=NSRect(x:200,y:350,width:8,height:18)
    StudioPopover.show(popup,content:Text("@First"),from:host,rect:anchor,size:NSSize(width:480,height:118),updatingExisting:true,behavior:.semitransient)
    let original=try #require(popup.contentViewController)
    #expect(popup.isShown)
    for name in ["@Second","@Third","@First"] {
      StudioPopover.show(popup,content:Text(name),from:host,rect:anchor,size:NSSize(width:480,height:118),updatingExisting:true,behavior:.semitransient)
      #expect(popup.isShown && popup.contentViewController === original)
      #expect(popup.behavior == .semitransient)
      let parent=try #require(original.view.superview)
      parent.layoutSubtreeIfNeeded()
      let frame=original.view.frame
      #expect(abs(frame.minX-(parent.bounds.maxX-frame.maxX))<1)
      #expect(abs(frame.minY-(parent.bounds.maxY-frame.maxY))<1)
      #expect(frame.size == NSSize(width:480,height:118))
    }
  }
  @Test func shortcutJumpsBothDirectionsPreservingTextColorsAndUndo() throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Pairs");doc.sql="SELECT CASE WHEN (1+(2))=3 THEN 'END' END;"
    let controller=EditorController(document:doc),editor=controller.editor
    let original=editor.string
    editor.setSelectedRange(NSRange(location:7,length:0));controller.jumpToMatchingPair()
    #expect(editor.selectedRange().location == (original as NSString).range(of:"END;").location)
    controller.jumpToMatchingPair();#expect(editor.selectedRange().location == 7)
    editor.setSelectedRange(NSRange(location:17,length:0));controller.jumpToMatchingPair();#expect(editor.selectedRange().location == 23)
    controller.jumpToMatchingPair();#expect(editor.selectedRange().location == 17)
    #expect(editor.string == original && doc.sql == original && editor.textLayoutManager != nil)
    #expect(GridShortcuts.binding(.matchingPair).label == "⌃⇧M")
  }
  @Test func commandFindOpensFromFreshMenuAndKeyboardRoutes() throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Command Find")
    let controller=EditorController(document:doc),editor=controller.editor
    let item=NSMenuItem(title:"Bul…",action:#selector(NSTextView.performFindPanelAction(_:)),keyEquivalent:"f")
    item.tag=NSTextFinder.Action.showFindInterface.rawValue
    #expect(editor.validateUserInterfaceItem(item))
    var prepared=0;editor.prepareEdit={prepared+=1}
    editor.performFindPanelAction(item)
    #expect(controller.findContainer.isFindBarVisible && prepared == 1)
    editor.sqlFinder.performAction(.hideFindInterface)
    doc.sql="SELECT N'İstanbul'";controller.setText();editor.setSelectedRange(NSRange(location:0,length:6))
    func key(_ flags:NSEvent.ModifierFlags)->NSEvent {
      NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:"f",charactersIgnoringModifiers:"f",isARepeat:false,keyCode:3)!
    }
    #expect(editor.performKeyEquivalent(with:key(.command)))
    #expect(controller.findContainer.isFindBarVisible && prepared == 2 && NSPasteboard(name:.find).string(forType:.string) == "SELECT")
    editor.sqlFinder.performAction(.hideFindInterface)
    editor.keyDown(with:key(.command));#expect(controller.findContainer.isFindBarVisible && prepared == 3)
    editor.sqlFinder.performAction(.hideFindInterface)
    #expect(editor.performKeyEquivalent(with:key([.control,.capsLock])))
    #expect(controller.findContainer.isFindBarVisible && !editor.sqlFinder.incrementalSearchingShouldDimContentView)
    editor.sqlFinder.performAction(.hideFindInterface)
    #expect(!editor.performKeyEquivalent(with:key([.command,.shift])))
  }
  @Test func findDoesNotDimAndNativeReplaceRemainsUndoable() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Find");doc.sql="SELECT N'İstanbul' AS City; SELECT 2;"
    let controller=EditorController(document:doc),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:800,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;defer {window.close()};window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location:0,length:6));editor.showSelectionFind()
    #expect(controller.findContainer.isFindBarVisible && !editor.sqlFinder.incrementalSearchingShouldDimContentView)
    #expect(editor.sqlFinder.isIncrementalSearchingEnabled && editor.textLayoutManager != nil)
    #expect(editor.backgroundColor == StudioTheme.editorCanvas)
    let undo=try #require(editor.undoManager);undo.groupsByEvent=false;undo.beginUndoGrouping()
    #expect(editor.shouldReplaceCharacters(inRanges:[NSValue(range:NSRange(location:0,length:6))],with:["PRINT"]))
    editor.replaceCharacters(in:NSRange(location:0,length:6),with:"PRINT");editor.didReplaceCharacters();undo.endUndoGrouping()
    #expect(doc.sql.hasPrefix("PRINT"));undo.undo();#expect(editor.string.hasPrefix("SELECT"));undo.groupsByEvent=true
    editor.sqlFinder.performAction(.hideFindInterface)
    #expect(!controller.findContainer.isFindBarVisible && editor.backgroundColor == StudioTheme.editorCanvas)
  }
  @Test func commandFindReplacesExistingSearchWithNewEditorSelection() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Repeated find")
    doc.sql="SELECT City FROM dbo.T WHERE City = N'City';"
    let controller=EditorController(document:doc),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:100,y:100,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.orderFront(nil)
    defer {editor.sqlFinder.performAction(.hideFindInterface);window.close()}
    window.makeFirstResponder(editor);editor.setSelectedRange(NSRange(location:0,length:6));editor.showSelectionFind()
    let bar=try #require(controller.findContainer.findBarView)
    func fields(_ view:NSView)->[NSTextField] {(view as? NSTextField).map {[$0]} ?? view.subviews.flatMap(fields)}
    let field=try #require(fields(bar).first {$0.isEditable})
    #expect(field.stringValue=="SELECT")
    window.makeFirstResponder(editor);editor.setSelectedRange(NSRange(location:7,length:4))
    let event=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"f",charactersIgnoringModifiers:"f",isARepeat:false,keyCode:3))
    #expect(editor.performKeyEquivalent(with:event))
    #expect(controller.findContainer.findBarView === bar && controller.findContainer.isFindBarVisible)
    #expect(field.stringValue=="City" && NSPasteboard(name:.find).string(forType:.string)=="City")
    editor.sqlFinder.performAction(.nextMatch)
    #expect((editor.string as NSString).substring(with:editor.selectedRange())=="City")
    #expect(doc.sql=="SELECT City FROM dbo.T WHERE City = N'City';")
    window.makeFirstResponder(editor);editor.setSelectedRange(NSRange(location:0,length:0));editor.showSelectionFind()
    #expect(field.stringValue=="City")
  }
  @Test func findBarReservesSpaceAndSearchFieldKeepsNativeHitAndFocus() throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Find clicks");doc.sql="SELECT 1;\nSELECT 2;"
    let controller=EditorController(document:doc),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:800,height:450),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.orderFront(nil)
    defer {editor.sqlFinder.performAction(.hideFindInterface);window.close()}
    window.makeFirstResponder(editor);editor.showSelectionFind()
    controller.surface.layoutSubtreeIfNeeded();controller.scroll.layoutSubtreeIfNeeded()
    let bar=try #require(controller.findContainer.findBarView)

    let barRect=controller.findContainer.convert(bar.bounds,from:bar)
    let viewport=controller.findContainer.convert(controller.scroll.bounds,from:controller.scroll)
    #expect(barRect.intersection(viewport).height<=1,"Find \(barRect), viewport \(viewport)")
    func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
    let field=try #require(views(bar).compactMap {$0 as? NSTextField}.first {$0.isEditable})
    let point=controller.surface.convert(NSPoint(x:field.bounds.midX,y:field.bounds.midY),from:field)
    let hit=try #require(controller.findContainer.hitTest(point))
    #expect(hit !== editor && (hit === field || hit.isDescendant(of:field)))
    #expect(window.makeFirstResponder(field))
    #expect(window.firstResponder !== editor)
    #expect(doc.sql=="SELECT 1;\nSELECT 2;")
  }
  @Test func parameterMetadataOrderOutputNamedIndexCacheAndStaleRequest() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    var requests=0
    server.asyncCatalogFixture={sql in
      requests+=1;try await Task.sleep(for:.milliseconds(25))
      var e=Execution();e.results=[Rows(values:sql.contains("SELECT object_id") ? [["42"]]:[["2","@Other","decimal(28,8)","1","0"],["1","@First","int","0","0"]])];return e
    }
    let doc=QueryDocument(server:server,database:"master",title:"Parameters")
    doc.intelligenceCatalog=SQLIntelligence.Catalog(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"Sample",columns:[],kind:"SQL_STORED_PROCEDURE")]))
    doc.catalogDatabase="master";doc.sql="EXEC Sample @Other = "
    let controller=EditorController(document:doc),editor=controller.editor
    editor.setSelectedRange(NSRange(location:editor.string.utf16.count,length:0));controller.scheduleParameters(manual:true)
    for _ in 0..<100 where controller.parameterValues.isEmpty {try await Task.sleep(for:.milliseconds(10))}
    #expect(controller.parameterValues.map(\.name) == ["@First","@Other"])
    #expect(controller.parameterCall?.activeIndex(in:controller.parameterValues) == 1)
    #expect(controller.parameterValues.last?.output == true && requests == 2)
    controller.scheduleParameters(manual:true);try await Task.sleep(for:.milliseconds(50));#expect(requests == 2)
    doc.sql="SELECT 1";controller.setText();controller.scheduleParameters(manual:true)
    try await Task.sleep(for:.milliseconds(50));#expect(controller.parameterCall == nil && !controller.parameterShown)
  }
  @Test func delayedParameterResponseDoesNotOverwriteNewCaretContext() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    server.asyncCatalogFixture={sql in
      try? await Task.sleep(for:.milliseconds(100))
      var e=Execution();e.results=[Rows(values:sql.contains("SELECT object_id") ? [["42"]]:[["1","@Old","int","0","0"]])];return e
    }
    let doc=QueryDocument(server:server,database:"master",title:"Stale")
    doc.intelligenceCatalog=SQLIntelligence.Catalog(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"Sample",columns:[],kind:"SQL_STORED_PROCEDURE")]))
    doc.catalogDatabase="master";doc.sql="EXEC Sample "
    let controller=EditorController(document:doc)
    controller.editor.setSelectedRange(NSRange(location:12,length:0));controller.scheduleParameters(manual:true)
    try await Task.sleep(for:.milliseconds(30))
    doc.sql="SELECT 1";controller.setText();controller.scheduleParameters(manual:true)
    try await Task.sleep(for:.milliseconds(250))
    #expect(controller.parameterCall == nil && controller.parameterValues.isEmpty && !controller.parameterShown)
  }

}
