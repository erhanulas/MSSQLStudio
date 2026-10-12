import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorPairFindParameterTests {
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
  @Test func findDoesNotDimAndNativeReplaceRemainsUndoable() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Find");doc.sql="SELECT N'İstanbul' AS City; SELECT 2;"
    let controller=EditorController(document:doc),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:800,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;defer {window.close()};window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location:0,length:6));editor.showSelectionFind()
    #expect(controller.scroll.isFindBarVisible && !editor.sqlFinder.incrementalSearchingShouldDimContentView)
    #expect(editor.sqlFinder.isIncrementalSearchingEnabled && editor.textLayoutManager != nil)
    #expect(editor.backgroundColor == StudioTheme.editorCanvas)
    let undo=try #require(editor.undoManager);undo.groupsByEvent=false;undo.beginUndoGrouping()
    #expect(editor.shouldReplaceCharacters(inRanges:[NSValue(range:NSRange(location:0,length:6))],with:["PRINT"]))
    editor.replaceCharacters(in:NSRange(location:0,length:6),with:"PRINT");editor.didReplaceCharacters();undo.endUndoGrouping()
    #expect(doc.sql.hasPrefix("PRINT"));undo.undo();#expect(editor.string.hasPrefix("SELECT"));undo.groupsByEvent=true
    editor.sqlFinder.performAction(.hideFindInterface)
    #expect(!controller.scroll.isFindBarVisible && editor.backgroundColor == StudioTheme.editorCanvas)
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
