import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct CompactEditorTests {
  func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
  func key(_ text:String,code:UInt16 = 39,on editor:SQLTextView) throws {
    let event=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:editor.window?.windowNumber ?? 0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code))
    editor.keyDown(with:event)
  }
  @Test func typedQuotesPairSkipCloseDeleteAndKeepSQLAndUndoInSync() throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Quotes")
    doc.sql="SELECT N"
    let controller=EditorController(document:doc),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:900,height:650),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;defer {window.close()}
    window.makeFirstResponder(editor)
    let undo=try #require(editor.undoManager)
    undo.groupsByEvent=false
    editor.setSelectedRange(NSRange(location:8,length:0));editor.breakUndoCoalescing()
    undo.beginUndoGrouping()
    try key("'",on:editor)
    undo.endUndoGrouping()
    #expect(editor.string == "SELECT N''" && doc.sql == editor.string)
    #expect(editor.selectedRange() == NSRange(location:9,length:0))
    editor.breakUndoCoalescing();undo.beginUndoGrouping()
    editor.insertText("İstanbul 😀",replacementRange:editor.selectedRange())
    undo.endUndoGrouping();editor.breakUndoCoalescing()
    try key("'",on:editor)
    #expect(editor.string == "SELECT N'İstanbul 😀'" && editor.selectedRange().location == (editor.string as NSString).length)
    #expect(doc.sql == editor.string)
    editor.undoManager?.undo();#expect(editor.string == "SELECT N''" && doc.sql == editor.string)
    editor.undoManager?.undo();#expect(editor.string == "SELECT N" && doc.sql == editor.string)
    editor.undoManager?.redo();#expect(editor.string == "SELECT N''" && doc.sql == editor.string)
    undo.groupsByEvent=true
    // Pasting complete SQL uses the normal insertion path and is byte-for-byte unchanged.
    let pasted="SELECT 'O''Brien', N'İzmir', \"Name\"; -- 'unchanged'"
    editor.insertText(pasted,replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    #expect(editor.string == pasted && doc.sql == pasted)
    editor.insertText("SELECT ",replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    try key("\"",on:editor);#expect(editor.string == "SELECT \"\"")
    try key("\u{7f}",code:51,on:editor);#expect(editor.string == "SELECT " && doc.sql == editor.string)
    // SQL escaped apostrophes remain possible when a generated closer was skipped.
    try key("'",on:editor);editor.insertText("O",replacementRange:editor.selectedRange())
    try key("'",on:editor);try key("'",on:editor)
    editor.insertText("Brien",replacementRange:editor.selectedRange());try key("'",on:editor)
    #expect(editor.string == "SELECT 'O''Brien'" && doc.sql == editor.string)
    // Wrap selected Unicode text without changing its contents.
    editor.insertText("SELECT İstanbul 😀",replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    editor.setSelectedRange(NSRange(location:7,length:("İstanbul 😀" as NSString).length))
    try key("'",on:editor)
    #expect(editor.string == "SELECT 'İstanbul 😀'")
    #expect((editor.string as NSString).substring(with:editor.selectedRange()) == "İstanbul 😀")
    editor.insertText("SELECT ",replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    try key("'",on:editor)
    editor.insertText("SELECT 'pasted'",replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    editor.setSelectedRange(NSRange(location:(editor.string as NSString).length-1,length:0))
    try key("'",on:editor)
    #expect(editor.string == "SELECT 'pasted''") // The pasted closer has no generated marker.
  }
  @Test func quoteTypingInsideCommentsAndExistingLiteralsStaysLiteral() throws {
    _=NSApplication.shared
    let editor=SQLTextView(usingTextLayoutManager:true)
    for source in ["-- comment", "/* comment", "/* outer /* inner */", "SELECT 'abc", "SELECT \"abc", "SELECT [abc"] {
      editor.string=source;editor.setSelectedRange(NSRange(location:(source as NSString).length,length:0))
      try key("'",on:editor);#expect(editor.string == source+"'")
    }
    editor.string="SELECT 'OBrien'";editor.setSelectedRange(NSRange(location:9,length:0))
    try key("'",on:editor);try key("'",on:editor)
    #expect(editor.string == "SELECT 'O''Brien'")
    editor.isEditable=false;let old=editor.string;try key("'",on:editor);#expect(editor.string == old)
  }
  @Test func compactGuttersGrowForLargeNumbersAndKeepFoldingAndEdits() throws {
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Numbers")
    doc.sql="SELECT 1;"
    let editor=EditorController(document:doc);editor.surface.frame=NSRect(x:0,y:0,width:900,height:600)
    editor.surface.layoutSubtreeIfNeeded();editor.resizeToViewport()
    #expect(editor.scroll.frame.minX == 44)
    doc.sql=String(repeating:"SELECT 1;\n",count:9999);editor.setText();editor.surface.layoutSubtreeIfNeeded()
    let width=LineNumbers.width(lineCount:10000,font:StudioTheme.codeFont)
    #expect(editor.scroll.frame.minX == width && width > 44)
    #expect(width >= ("10000" as NSString).size(withAttributes:[.font:StudioTheme.codeFont]).width+25)
    doc.sql="SELECT 1";editor.setText();editor.surface.layoutSubtreeIfNeeded();#expect(editor.scroll.frame.minX == 44)
    #expect(ResultRowGutter.width(maxRow:150,editing:false,newRows:false) == 36)
    #expect(ResultRowGutter.width(maxRow:5_000_000,editing:false,newRows:false) > 50)
    #expect(ResultRowGutter.width(maxRow:150,editing:true,newRows:true) > 36)
  }
  @Test func databaseFavoritePlanAndPositionShareOneRowAcrossTabsAndDetachedWindows() throws {
    _=NSApplication.shared
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(name:"Explorer with a deliberately long connection name"),password:"");server.online=false
    let docs=(0..<2).map {QueryDocument(server:server,database:"master",title:"Q\($0)")}
    docs[0].sql="SELECT 1";docs[1].sql="SELECT 2";state.documents=docs;state.active=docs[0]
    let host=WorkbenchController(state:state)
    let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:1060,height:700),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=host;defer {host.redockQueries();window.close()}
    for size in [NSSize(width:1060,height:700),NSSize(width:1360,height:860)] {
      window.setContentSize(size);host.view.frame.size=size;host.view.layoutSubtreeIfNeeded()
      for doc in docs {
        state.active=doc;state.changed?();host.view.layoutSubtreeIfNeeded()
        let views=descendants(host.view)
        let row=try #require(views.first {$0.accessibilityIdentifier() == "queryContextToolbar"})
        let database=try #require(views.first {$0.accessibilityIdentifier() == "databaseSelector"})
        let star=try #require(views.first {$0.accessibilityIdentifier() == "queryFavorite"})
        let plan=try #require(views.compactMap {$0 as? NSButton}.first {$0.title == "Gerçek plan"})
        let editor=try #require(views.compactMap {$0 as? SQLTextView}.first)
        let rowFrame=host.view.convert(row.bounds,from:row)
        for item in [database,star,plan] {
          let frame=host.view.convert(item.bounds,from:item)
          #expect(abs(frame.midY-rowFrame.midY) <= 2 && frame.width > 0)
          #expect(frame.minX >= rowFrame.minX && frame.maxX <= rowFrame.maxX)
        }
        let surface=try #require(editor.enclosingScrollView?.superview)
        let editorFrame=host.view.convert(surface.bounds,from:surface)
        #expect(abs(editorFrame.maxY-rowFrame.minY) <= 2)
      }
    }
    let query=try #require(host.children.compactMap {$0 as? QueryController}.first {$0.document === state.active})
    let responder=try #require(descendants(query.view).compactMap {$0 as? SQLTextView}.first);window.makeFirstResponder(responder)
    state.changed?();#expect(window.firstResponder === responder)
    host.detachQuery()
    #expect(query.view.window !== window)
    #expect(descendants(query.view).contains {$0.accessibilityIdentifier() == "queryFavorite"})
    host.redockQueries();host.view.layoutSubtreeIfNeeded()
    #expect(query.view.window === window)
    let toolbar=try #require(descendants(host.view).first {$0.accessibilityIdentifier() == "queryToolbarHost"})
    #expect(descendants(toolbar).contains {$0.accessibilityIdentifier() == "queryFavorite"})
    #expect(state.active === query.document && query.document.sql == docs[1].sql)
  }
}
