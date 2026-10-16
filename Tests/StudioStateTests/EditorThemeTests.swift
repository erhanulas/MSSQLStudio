import AppKit
import SQLServerKit
import Testing

@testable import MSSQLStudio

@MainActor private final class EditorStorageChanges: NSObject {
  var count=0
  @objc func changed(_ notification:Notification) {count+=1}
}

@MainActor @Suite(.serialized) struct EditorThemeTests {
  @Test func ssmsColorCategoriesStayCorrectInMainEditorAndPreviewsAcrossThemes() throws {
    _ = NSApplication.shared
    let previous = UserDefaults.standard.string(forKey: "ssmsTheme")
    defer { StudioTheme.apply(previous ?? "light") }
    let source = "-- SSMS colors\nSELECT COUNT(*), GETDATE(), N'İstanbul', [Customer], sys.objects\nFROM dbo.Orders WHERE Amount >= 42;\nEXEC sp_help;"
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "SSMS")
    doc.server.online = false; doc.sql = source
    let controller = EditorController(document: doc)
    controller.editor.setSelectedRange(NSRange(location: 3, length: 4))
    let selection = controller.editor.selectedRange()
    func hex(_ color: NSColor?) -> UInt32? {
      guard let value = color?.usingColorSpace(.sRGB) else { return nil }
      return UInt32((value.redComponent * 255).rounded()) << 16 | UInt32((value.greenComponent * 255).rounded()) << 8 | UInt32((value.blueComponent * 255).rounded())
    }
    for (theme, colors, background, lineNumber) in [
      ("light", [0x008000,0x0000FF,0xFF00FF,0xFF0000,0x000000,0x008000,0x808080,0x800000], 0xFFFFFF, 0x008080),
      ("dark", [0x6A9955,0x6CA0FF,0xE88BFF,0xFF8080,0xD4D4D4,0x72C77B,0xB4B4B4,0xD88585], 0x1E1E1E, 0x4EC9B0)
    ] {
      StudioTheme.apply(theme)
      let storage = try #require(controller.editor.textContentStorage?.textStorage)
      let preview = SQLSourceHighlighting.attributed(source)
      for (needle, expected) in zip(["-- SSMS", "SELECT", "COUNT", "N'İstanbul'", "[Customer]", "sys", ">", "sp_help"], colors) {
        let offset = (source as NSString).range(of: needle).location
        #expect(hex(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor) == UInt32(expected), "\(theme): \(needle)")
        #expect(hex(preview.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor) == UInt32(expected))
      }
      #expect(hex(controller.editor.backgroundColor) == UInt32(background))
      #expect(hex(StudioTheme.lineNumber) == UInt32(lineNumber))
      #expect(controller.editor.string == source && doc.sql == source)
      #expect(controller.editor.selectedRange() == selection)
      #expect(controller.editor.textLayoutManager != nil)
    }
  }
  @Test func formatPreservesEverySSMSCategoryImmediatelyOnRepeatUndoAndRedo() throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(previous ?? "light")}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let source="select count(*), N'İstanbul' as [Label], 42 from sys.objects where 1>=1; -- keep\nexec sp_help;"
      let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Format")
      doc.server.online=false;doc.sql=source
      let controller=QueryController(document:doc)
      let window=NSWindow(contentViewController:controller);window.isReleasedWhenClosed=false
      defer {window.close()}
      func views(_ v:NSView)->[NSView] {[v]+v.subviews.flatMap(views)}
      let editor=try #require(views(controller.view).compactMap {$0 as? SQLTextView}.first)
      window.makeKeyAndOrderFront(nil);window.makeFirstResponder(editor)
      let undo=try #require(editor.undoManager)
      func assertColors() throws {
        let storage=try #require(editor.textContentStorage?.textStorage)
        for (needle,kind) in [("COUNT",TSQL.SyntaxStyle.function),("N'İstanbul'",.string),("[Label]",.plain),("sys",.systemObject),("-- keep",.comment),(">=",.operatorSymbol),("sp_help",.procedure)] {
          let range=(editor.string as NSString).range(of:needle,options:.caseInsensitive)
          #expect(range.location != NSNotFound)
          #expect(storage.attribute(.foregroundColor,at:range.location,effectiveRange:nil) as? NSColor == StudioTheme.syntax(kind),"\(theme): \(needle)")
        }
        #expect(editor.textLayoutManager != nil && editor.string == doc.sql)
      }
      editor.typingAttributes[.foregroundColor]=StudioTheme.syntax(.keyword)
      undo.beginUndoGrouping();controller.format();undo.endUndoGrouping()
      let formatted=editor.string;#expect(formatted != source)
      try assertColors()
      controller.format();#expect(editor.string == formatted);try assertColors()
      undo.undo();#expect(editor.string == source);try assertColors()
      undo.redo();#expect(editor.string == formatted);try assertColors()
      #expect(doc.lastExecutedSQL == nil)
    }
  }
  @Test func formattingSelectionPreservesSurroundingSQLAndUsesIsolatedPreferences() throws {
    _=NSApplication.shared
    let source="-- outside\nselect a,b from dbo.t where a=1 and b=2\n-- suffix"
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Selection format")
    doc.server.online=false;doc.sql=source
    let controller=EditorController(document:doc)
    let range=(source as NSString).range(of:"select a,b from dbo.t where a=1 and b=2")
    controller.editor.setSelectedRange(range)
    let undo=try #require(controller.editor.undoManager)
    undo.beginUndoGrouping();controller.formatSQL(options:.init(indentWidth:2,keywordCase:.upper,commaStyle:.leading));undo.endUndoGrouping()
    #expect(doc.sql.hasPrefix("-- outside\nSELECT a\n  , b\nFROM"))
    #expect(doc.sql.hasSuffix("\n-- suffix") && controller.editor.selectedRange().length > range.length)
    undo.undo();#expect(doc.sql==source)
    undo.redo();#expect(doc.sql.contains("SELECT a"))
    let suite="local.mssqlstudio.format-test-"+UUID().uuidString
    let defaults=try #require(UserDefaults(suiteName:suite));defer {defaults.removePersistentDomain(forName:suite)}
    let options=SQLFormattingOptions(indentWidth:2,keywordCase:.preserve,commaStyle:.leading)
    SQLEditorPreferences.saveFormatting(options,in:defaults)
    #expect(SQLEditorPreferences.formatting(in:defaults)==options)
    #expect(SettingsSearch.results("formatter virgül").contains {$0.id=="formatComma"})
  }
  @Test func partialLiteralCommentAndIdentifierSelectionsCannotChangeSQLMeaning() {
    _=NSApplication.shared
    let source="SELECT N'from where', selectName FROM dbo.t; -- select from"
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Safe selection")
    doc.server.online=false;doc.sql=source
    let controller=EditorController(document:doc)
    for needle in ["from where","selectName","select from"] {
      controller.editor.setSelectedRange((source as NSString).range(of:needle))
      controller.formatSQL(options:.init())
      #expect(doc.sql == source)
    }
  }
  @Test func unusedDeclarationColorsUpdateWithoutChangingSourceAndSurviveFolds() throws {
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Unused variables")
    doc.server.online=false
    let source="DECLARE @unused int, @used int;\nIF 1=1\nBEGIN\n SELECT @used;\nEND;"
    doc.sql=source
    let controller=EditorController(document:doc)
    let storage=try #require(controller.editor.textContentStorage?.textStorage)
    func color(_ name:String) -> NSColor? {
      let range=(controller.editor.string as NSString).range(of:name)
      return storage.attribute(.foregroundColor,at:range.location,effectiveRange:nil) as? NSColor
    }
    #expect(color("@unused") == StudioTheme.unusedVariable)
    #expect(color("@used") == StudioTheme.editorText)
    let region=try #require(controller.regions.first)
    controller.toggleFold(region)
    #expect(color("@used") == StudioTheme.editorText)
    #expect(color("@unused") == StudioTheme.unusedVariable)
    controller.expandAll()
    #expect(doc.sql == source && controller.editor.string == source)
    doc.sql=source+"\nSELECT @unused;";controller.setText()
    #expect(color("@unused") == StudioTheme.editorText)
    doc.sql=source;controller.setText()
    #expect(color("@unused") == StudioTheme.unusedVariable)
    #expect(controller.editor.textLayoutManager != nil)
  }

  private func lineScreenY(_ controller:EditorController,offset:Int) throws -> CGFloat {
    let content=try #require(controller.editor.textContentStorage)
    let layout=try #require(controller.editor.textLayoutManager)
    let start=try #require(content.location(content.documentRange.location,offsetBy:offset))
    let end=try #require(content.location(start,offsetBy:1))
    let range=try #require(NSTextRange(location:start,end:end))
    layout.ensureLayout(for:range)
    var y:CGFloat?
    layout.enumerateTextSegments(in:range,type:.standard,options:[]) { _,rect,_,_ in
      y=rect.minY+controller.editor.textContainerOrigin.y-controller.scroll.contentView.bounds.minY
      return false
    }
    return try #require(y)
  }

  @Test func selectionHighlightNeverEditsStorageOrMovesViewport() async throws {
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Stable matches")
    doc.server.online=false
    doc.sql=String(repeating:"SELECT Customer_Name, Customer_ID; -- İstanbul 😀\n",count:120)
    let controller=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:320),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface
    defer {window.close()}
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    try await Task.sleep(for:.milliseconds(400))
    controller.scroll.contentView.scroll(to:NSPoint(x:0,y:800))
    // Let the clip-view bounds notification synchronize the overlay before observing.
    try await Task.sleep(for:.milliseconds(350))
    let origin=controller.scroll.contentView.bounds.origin
    let storage=try #require(controller.editor.textContentStorage?.textStorage)
    let counter=EditorStorageChanges()
    NotificationCenter.default.addObserver(counter,selector:#selector(EditorStorageChanges.changed(_:)),name:NSTextStorage.didProcessEditingNotification,object:storage)
    defer {NotificationCenter.default.removeObserver(counter)}
    let original=NSAttributedString(attributedString:storage)
    let source=doc.sql as NSString
    for word in ["Customer_Name","Customer_","Customer_ID"] {
      controller.editor.setSelectedRange(source.range(of:word,options:[],range:NSRange(location:2100,length:source.length-2100)))
      controller.updateOccurrences()
      // Keep storage observation synchronous: other suites can change the global
      // editor theme while this async test yields, legitimately restyling this view.
      #expect(controller.occurrenceRanges.count == (word == "Customer_" ? 240 : 120))
      #expect(controller.scroll.contentView.bounds.origin == origin)
      #expect(!controller.occurrenceHighlights.highlightRects(in:controller.occurrenceHighlights.bounds).isEmpty)
      #expect(controller.occurrenceHighlights.hitTest(.zero) == nil)
      #expect(controller.occurrenceHighlights.frame == controller.scroll.contentView.bounds)
    }
    controller.editor.setSelectedRange(NSRange(location:2100,length:0));controller.updateOccurrences()
    #expect(counter.count == 0)
    #expect(storage.isEqual(to:original))
    #expect(controller.editor.textLayoutManager != nil && controller.editor.string == doc.sql)
    #expect(controller.editor.undoManager?.canUndo != true)
  }

  @Test func repeatedEndOfDocumentFoldsKeepActualHeaderPositionAfterLayoutSettles() async throws {
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Stable fold")
    doc.server.online=false
    doc.sql=String(repeating:"SELECT 0;\n",count:1200)+"IF 1=1\nBEGIN\n"+String(repeating:" SELECT N'İstanbul 😀';\n",count:120)+"END"
    let controller=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:320),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface
    defer {window.close()}
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    let region=try #require(controller.regions.first)
    let content=try #require(controller.editor.textContentStorage)
    controller.editor.textLayoutManager?.ensureLayout(for:content.documentRange)
    let headerDocumentY=try lineScreenY(controller,offset:region.header.location)+controller.scroll.contentView.bounds.minY
    controller.scroll.contentView.scroll(to:NSPoint(x:0,y:headerDocumentY-140))
    let before=try lineScreenY(controller,offset:region.header.location)
    #expect(before >= 0)
    #expect(before < 320, "headerY=\(before), scrollY=\(controller.scroll.contentView.bounds.minY), height=\(controller.editor.frame.height)")
    controller.editor.setSelectedRange(NSRange(location:region.hidden.location+10,length:0))
    for _ in 0..<4 {
      controller.toggleFold(region)
      try await Task.sleep(for:.milliseconds(100))
      controller.resizeToViewport()
      #expect(abs(try lineScreenY(controller,offset:region.header.location)-before) < 1)
      #expect(controller.editor.selectedRange() == NSRange(location:region.header.location,length:0))
      controller.toggleFold(region)
      try await Task.sleep(for:.milliseconds(350))
      controller.resizeToViewport()
      #expect(abs(try lineScreenY(controller,offset:region.header.location)-before) < 1)
      #expect(controller.editor.string == doc.sql)
    }
    #expect(controller.editor.undoManager?.canUndo != true)
    let bodyOffset=region.hidden.location+1000
    controller.editor.setSelectedRange(NSRange(location:bodyOffset,length:0))
    let bodyY=try lineScreenY(controller,offset:bodyOffset)+controller.scroll.contentView.bounds.minY
    controller.scroll.contentView.scroll(to:NSPoint(x:0,y:bodyY-80))
    controller.toggleCurrentFold()
    let revealedY=try lineScreenY(controller,offset:region.header.location)
    #expect(revealedY >= 0 && revealedY < controller.scroll.contentView.bounds.height)
    #expect(controller.collapsedMarkers.first?.region == region)
  }

  @Test func expandAllKeepsVisibleSourceLineAndHorizontalScroll() throws {
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Expand anchor")
    doc.server.online=false
    doc.sql="IF 1=1\nBEGIN\n SELECT N'"+String(repeating:"wide",count:100)+"';\n"+String(repeating:" SELECT 1;\n",count:80)+"END\n"+String(repeating:"SELECT N'visible';\n",count:80)
    let controller=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:320),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;defer {window.close()}
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    let region=try #require(controller.regions.first)
    controller.scroll.contentView.scroll(to:NSPoint(x:160,y:0))
    let x=controller.scroll.contentView.bounds.minX
    controller.toggleFold(region)
    #expect(controller.scroll.contentView.bounds.minX == x)
    let folded=controller.editor.string as NSString
    let markerOffset=folded.range(of:"SELECT N'visible'").location
    let markerY=try lineScreenY(controller,offset:markerOffset)+controller.scroll.contentView.bounds.minY
    controller.scroll.contentView.scroll(to:NSPoint(x:x,y:markerY+240))
    let before=try lineScreenY(controller,offset:markerOffset)
    controller.expandAll()
    let sourceOffset=(doc.sql as NSString).range(of:"SELECT N'visible'").location
    #expect(abs(try lineScreenY(controller,offset:sourceOffset)-before) < 1)
    #expect(controller.scroll.contentView.bounds.minX == x)
    #expect(controller.editor.string == doc.sql)
  }

  @Test func doubleClickSelectsColumnBeforeRepeatedClickExpandsItsQualifier() {
    let editor=SQLTextView(usingTextLayoutManager:true)
    editor.string="SELECT * FROM TBLDEPMAS AS T WITH(NOLOCK) WHERE T.DEPO_KODU = 11;"
    let source=editor.string as NSString,column=source.range(of:"DEPO_KODU"),qualified=source.range(of:"T.DEPO_KODU")
    #expect(editor.selectSQLWord(at:column.location+2,clickCount:2,time:1))
    #expect(editor.selectedRange()==column)
    #expect(editor.selectSQLWord(at:column.location+2,clickCount:2,time:1+NSEvent.doubleClickInterval))
    #expect(editor.selectedRange()==qualified)
    #expect(editor.selectSQLWord(at:column.location+2,clickCount:2,time:10))
    #expect(editor.selectedRange()==column)
    #expect(editor.selectSQLWord(at:column.location+2,clickCount:4,time:10.1))
    #expect(editor.selectedRange()==qualified && editor.string==source as String)
    editor.string="SELECT [dbo].[T].[DEPO_KODU], @PARAM;"
    let quoted=editor.string as NSString,word=quoted.range(of:"DEPO_KODU")
    #expect(editor.selectSQLWord(at:word.location+1,clickCount:2,time:20))
    #expect(editor.selectedRange()==word)
    #expect(editor.selectSQLWord(at:word.location+1,clickCount:4,time:20.1))
    #expect(editor.selectedRange()==quoted.range(of:"[dbo].[T].[DEPO_KODU]"))
  }
  @Test func repeatedQualifiedClickUsesTheLastGlyphRatherThanTheFollowingSpace() throws {
    _=NSApplication.shared
    let editor=SQLTextView(usingTextLayoutManager:true)
    let window=NSWindow(contentRect:NSRect(x:100,y:100,width:900,height:450),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=editor;defer {window.close()}
    editor.string="SELECT T.DEPO_KODU FROM dbo.Cells T;"
    editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
    let text=editor.string as NSString,word=text.range(of:"DEPO_KODU")
    let glyph=try #require(editor.rects(forCharacterRange:NSRange(location:NSMaxRange(word)-1,length:1))?.first)
    let point=editor.convert(NSPoint(x:glyph.rectValue.maxX-0.5,y:glyph.rectValue.midY),to:nil)
    let event=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:1,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:4,pressure:1))
    editor.mouseDown(with:event)
    #expect(editor.selectedRange()==text.range(of:"T.DEPO_KODU"))
  }
  @Test func finalMouseSelectionRestoresSQLPrefixesWithoutExpandingMultipleWords() {
    let editor=SQLTextView(usingTextLayoutManager:true)
    editor.string="SELECT @STOK_KODU, @@ROWCOUNT, #Temp, @şehir; SELECT @STOK_KODU;"
    let text=editor.string as NSString
    for (partial,whole) in [("STOK_KODU","@STOK_KODU"),("ROWCOUNT","@@ROWCOUNT"),("Temp","#Temp"),("şehir","@şehir")] {
      editor.setSelectedRange(text.range(of:partial)); editor.normalizeSQLWordSelection()
      #expect(editor.selectedRange() == text.range(of:whole))
    }
    let multiple=text.range(of:"SELECT @STOK_KODU")
    editor.setSelectedRange(multiple);editor.normalizeSQLWordSelection()
    #expect(editor.selectedRange() == multiple && editor.string == text as String)
  }
  @Test func findShortcutUsesSelectionAndKeepsSQLAndUndo() async throws {
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Find")
    doc.server.online=false;doc.sql="SELECT @STOK_KODU; SELECT @STOK_KODU;"
    let controller=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.makeFirstResponder(controller.editor)
    defer {window.close()}
    controller.editor.setSelectedRange((doc.sql as NSString).range(of:"@STOK_KODU"))
    let event=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.control,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"f",charactersIgnoringModifiers:"f",isARepeat:false,keyCode:3))
    #expect(controller.editor.performKeyEquivalent(with:event))
    func all(_ view:NSView) -> [NSView] {[view]+view.subviews.flatMap(all)}
    #expect(controller.findContainer.isFindBarVisible)
    let bar=try #require(controller.findContainer.findBarView)
    let field=try #require(all(bar).compactMap {$0 as? NSTextField}.first {$0.stringValue == "@STOK_KODU"})
    #expect(field.stringValue == "@STOK_KODU")
    let hide=NSMenuItem();hide.tag=NSTextFinder.Action.hideFindInterface.rawValue
    controller.editor.performFindPanelAction(hide)
    controller.editor.setSelectedRange((doc.sql as NSString).range(of:"SELECT"))
    controller.editor.showSelectionFind()
    #expect(all(bar).compactMap {$0 as? NSTextField}.contains {$0.stringValue == "SELECT"})
    #expect(controller.editor.string == doc.sql && controller.editor.undoManager?.canUndo != true)
    controller.editor.performFindPanelAction(hide)
    window.makeFirstResponder(nil)
    // NSTextFinder schedules a delayed indicator update; retain its client until it settles.
    try await Task.sleep(for:.milliseconds(400))
    #expect(controller.editor.string == doc.sql)
  }
  @Test func completionDelayPersistsAndClampsInvalidPreferences() throws {
    let name="MSSQLStudio.EditorDelayTests.\(UUID().uuidString)"
    let defaults=try #require(UserDefaults(suiteName:name));defer {defaults.removePersistentDomain(forName:name)}
    #expect(SQLEditorPreferences.completionDelay(in:defaults) == 260)
    defaults.set(720,forKey:SQLEditorPreferences.completionDelayKey)
    #expect(SQLEditorPreferences.completionDelay(in:try #require(UserDefaults(suiteName:name))) == 720)
    defaults.set(-100,forKey:SQLEditorPreferences.completionDelayKey)
    #expect(SQLEditorPreferences.completionDelay(in:defaults) == 50)
    defaults.set(100000,forKey:SQLEditorPreferences.completionDelayKey)
    #expect(SQLEditorPreferences.completionDelay(in:defaults) == 1000)
  }
  @Test func wordSelectionNeverExpandsIntoNeighbouringStatements() {
    let editor=SQLTextView(usingTextLayoutManager:true)
    editor.string="SELECT [dbo].[Customer_Name], @şehir;\nSELECT Customer_Name; -- 😀"
    let text=editor.string as NSString
    for value in ["Customer_Name","@şehir","SELECT"] {
      let word=text.range(of:value),probe=NSRange(location:word.location+1,length:0)
      #expect(editor.selectionRange(forProposedRange:probe,granularity:.selectByWord) == word)
    }
    let punctuation=text.range(of:",")
    #expect(editor.selectionRange(forProposedRange:punctuation,granularity:.selectByWord) == punctuation)
    let emoji=text.range(of:"😀")
    #expect(editor.selectionRange(forProposedRange:NSRange(location:emoji.location+1,length:0),granularity:.selectByWord) == emoji)
    let caret=NSRange(location:2,length:0)
    #expect(editor.selectionRange(forProposedRange:caret,granularity:.selectByCharacter) == caret)
  }
  @Test func occurrencePaintingSurvivesAsyncSyntaxWithoutChangingSelectionOrUndo() async throws {
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Matches")
    doc.server.online=false;doc.sql="SELECT Customer_Name;\nSELECT Customer_Name; -- customer_name"
    let controller=EditorController(document:doc),source=doc.sql as NSString
    let chosen=source.range(of:"Customer_Name")
    controller.editor.setSelectedRange(chosen)
    try await Task.sleep(for:.milliseconds(450))
    #expect(controller.occurrenceRanges.count == 3)
    #expect(controller.editor.selectedRange() == chosen)
    #expect(doc.sql == source as String)
    let storage=try #require(controller.editor.textContentStorage?.textStorage)
    #expect(controller.occurrenceHighlights.ranges == controller.occurrenceRanges)
    #expect(storage.attribute(.backgroundColor,at:chosen.location,effectiveRange:nil) == nil)
    #expect(controller.editor.undoManager?.canUndo != true)
    controller.editor.setSelectedRange(NSRange(location:0,length:0))
    for _ in 0..<100 {
      if controller.occurrenceRanges.isEmpty {break}
      try await Task.sleep(for:.milliseconds(20))
    }
    #expect(controller.occurrenceRanges.isEmpty)
    #expect(storage.attribute(.backgroundColor,at:chosen.location,effectiveRange:nil) == nil)
    #expect(controller.occurrenceHighlights.ranges.isEmpty)
  }
  @Test func conditionAndElseFoldsHaveShadedMarkersAndUnchangedHostRefreshKeepsState() throws {
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"IF folds")
    doc.server.online=false;doc.sql="IF 1=1\nBEGIN\n SELECT 1;\nEND\nELSE\nBEGIN\n SELECT 2;\nEND\nSELECT 3;"
    let controller=EditorController(document:doc),original=doc.sql
    #expect(controller.regions.count == 2)
    let first=try #require(controller.regions.first)
    #expect((original as NSString).substring(with:first.header).hasPrefix("IF"))
    #expect((original as NSString).substring(with:controller.regions[1].header).hasPrefix("ELSE"))
    controller.toggleFold(first);controller.setText()
    #expect(controller.editor.string.hasPrefix("IF 1=1 …\nELSE"))
    let marker=try #require(controller.collapsedMarkers.first)
    let storage=try #require(controller.editor.textContentStorage?.textStorage)
    #expect(storage.attribute(.backgroundColor,at:marker.range.location,effectiveRange:nil) != nil)
    #expect((storage.attribute(.toolTip,at:marker.range.location,effectiveRange:nil) as? String)?.contains("SELECT 1") == true)
    controller.editor.setSelectedRange(marker.range)
    #expect(controller.editor.unfoldSelection?(marker.range) == true)
    #expect(controller.editor.selectedRange().length == 0)
    #expect(controller.editor.string == original && doc.sql == original)
  }
  @Test func nestedFoldsAndViewportAnchorRemainStable() throws {
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Fold anchor")
    doc.server.online=false;doc.sql=String(repeating:"SELECT 0;\n",count:30)+"BEGIN\n BEGIN\n  SELECT 1;\n END\n SELECT 2;\nEND\nSELECT 3;"
    let controller=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:300),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;defer {window.close()}
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    controller.scroll.contentView.scroll(to:NSPoint(x:0,y:420))
    let outer=try #require(controller.regions.first),inner=try #require(controller.regions.last)
    controller.toggleFold(inner)
    let before=controller.scroll.contentView.bounds.minY
    controller.toggleFold(outer);controller.toggleFold(outer)
    #expect(abs(controller.scroll.contentView.bounds.minY-before) < 2)
    #expect(controller.collapsedMarkers.count == 1 && controller.collapsedMarkers.first?.region == inner)
    #expect(!controller.editor.string.contains("SELECT 1"))
    controller.expandAll();#expect(controller.editor.string == doc.sql)
  }
  @Test func selectedTextHighlightsOccurrencesAndNavigationResolvesQualifiedObjects() {
    let doc = QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Navigation")
    doc.server.online = false
    doc.sql = "SELECT N'İstanbul'; SELECT * FROM [dbo].[Customers]; -- Customers customers"
    doc.intelligenceCatalog = .init(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"Customers",columns:["Name"])]))
    doc.catalogDatabase = "master"; doc.catalogVerified = true
    let controller = EditorController(document:doc)
    let source = doc.sql as NSString
    controller.editor.setSelectedRange(source.range(of:"Customers")); controller.updateOccurrences()
    #expect(controller.occurrenceRanges.count == 3)
    var opened: String?
    doc.openDefinitionNamed = {parts in #expect(parts == ["dbo","Customers"]);opened=parts.last}
    controller.navigateDefinition()
    #expect(opened == "Customers")
    opened = nil
    let object = source.range(of:"[Customers]")
    controller.editor.setSelectedRange(NSRange(location:NSMaxRange(object),length:0))
    controller.navigateDefinition()
    #expect(opened == "Customers")
    #expect(controller.editor.writingToolsBehavior == .none)
    controller.editor.setSelectedRange(NSRange(location:0,length:0)); controller.updateOccurrences()
    #expect(controller.occurrenceRanges.isEmpty)
    #expect(controller.editor.string == doc.sql)
    controller.editor.selectAll(nil)
    #expect(controller.editor.selectedRange().length == source.length)
  }
  @Test func completedBracketedMissingObjectIsMarkedWithoutMovingCaret() async throws {
    let doc = QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Validation")
    doc.server.online = false
    doc.intelligenceCatalog = .init(snapshot:.init(symbols:[])); doc.catalogDatabase = "master"; doc.catalogVerified = true
    doc.sql = "SELECT * FROM [dbo].[DefinitelyMissing]"
    let controller = EditorController(document:doc)
    controller.editor.setSelectedRange(NSRange(location:(doc.sql as NSString).length,length:0))
    controller.scheduleIntelligence(allowPopup:false)
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while controller.diagnostics.isEmpty && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(controller.diagnostics.count == 1)
    #expect(controller.editor.textLayoutManager != nil)
  }
  @Test func fixedGutterIsOutsideEditingViewportAndLineSelectionIncludesNewline() {
    let doc = QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Gutter")
    doc.sql = "SELECT N'İstanbul';\nSELECT 2;"
    let controller = EditorController(document:doc)
    controller.surface.frame = NSRect(x:0,y:0,width:1000,height:600)
    controller.surface.layoutSubtreeIfNeeded(); controller.resizeToViewport()
    #expect(controller.surface.convert(controller.scroll.bounds,from:controller.scroll).minX == 44)
    #expect(controller.scroll.verticalRulerView == nil)
    let line = (doc.sql as NSString).lineRange(for:NSRange(location:0,length:0))
    controller.selectSourceLine(line)
    #expect(controller.editor.selectedRange() == line)
    #expect((controller.editor.string as NSString).substring(with:line) == "SELECT N'İstanbul';\n")
  }
  @Test func outliningIgnoresCommentsStringsTransactionsAndBalancesCase() {
    let sql = "BEGIN TRAN;\nIF 1=1\nBEGIN\n SELECT CASE WHEN 1=1 THEN N'END BEGIN' ELSE N'x' END; -- END\n BEGIN TRY\n SELECT 1;\n END TRY\n BEGIN CATCH\n SELECT 2;\n END CATCH\nEND\nELSE\nBEGIN\n SELECT 3;\nEND"
    let regions = SQLFolding.regions(sql)
    #expect(regions.count == 4)
    #expect(SQLFolding.regions("BEGIN TRANSACTION;\nSELECT 1;\nCOMMIT;").isEmpty)
    #expect(SQLFolding.regions("/* BEGIN\nEND */\nSELECT N'BEGIN END';").isEmpty)
    let projection = SQLFolding.Projection(source:sql,collapsed:regions)
    #expect(!projection.text.contains("SELECT 1"))
    #expect(projection.text.contains("ELSE"))
    #expect(projection.sourceOffset((projection.text as NSString).length) == (sql as NSString).length)
  }
  @Test func foldingKeepsExecutableSourceAndEditsExpandWithoutLosingHiddenCode() {
    let doc = QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Folding")
    let original = "IF 1=1\nBEGIN\n SELECT N'İstanbul 😀';\nEND\nSELECT 2;"
    doc.sql = original; doc.savedText = original
    let controller = EditorController(document:doc)
    let region = controller.regions[0]
    controller.toggleFold(region)
    #expect(controller.editor.string.contains(" …"))
    #expect(!controller.editor.string.contains("İstanbul"))
    #expect(doc.sql == original && !doc.dirty)
    controller.editor.setSelectedRange(NSRange(location:0,length:(controller.editor.string as NSString).length))
    #expect(doc.selectedRange == NSRange(location:0,length:(original as NSString).length))
    controller.editor.setSelectedRange(NSRange(location:0,length:0))
    controller.editor.insertText("-- edited\n",replacementRange:controller.editor.selectedRange())
    #expect(doc.sql == "-- edited\n"+original)
    #expect(controller.editor.string == doc.sql)
  }
  @Test func foldExpandPreservesSelectionAndExistingUndoHistory() async throws {
    let doc = QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Undo fold")
    doc.sql = "BEGIN\n SELECT 1;\nEND"
    let controller = EditorController(document:doc)
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:500),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false; window.contentView = controller.surface; window.makeFirstResponder(controller.editor)
    defer { window.close() }
    controller.editor.insertText("\nSELECT 2;",replacementRange:NSRange(location:(doc.sql as NSString).length,length:0))
    // Analysis runs asynchronously; wait for its result rather than a fixed CI delay.
    for _ in 0..<250 {
      if !controller.regions.isEmpty { break }
      try await Task.sleep(for:.milliseconds(20))
    }
    controller.toggleFold(try #require(controller.regions.first))
    controller.editor.undoManager?.undo()
    try await Task.sleep(for:.milliseconds(150))
    #expect(doc.sql == "BEGIN\n SELECT 1;\nEND")
    #expect(controller.editor.string == doc.sql)
  }
  @Test func emptyTextHitRegionStillRoutesViewportClickToEditor() {
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Blank")
    let controller = EditorController(document: doc)
    controller.surface.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
    controller.surface.layoutSubtreeIfNeeded(); controller.resizeToViewport()
    // Model the empty native text hit region before the first edit.
    controller.editor.setFrameSize(NSSize(width: 800, height: 0))
    let point = NSPoint(x: controller.scroll.frame.minX+controller.scroll.contentView.frame.midX, y: controller.scroll.frame.minY+controller.scroll.contentView.frame.midY)
    #expect(controller.scroll.hitTest(point) === controller.editor)
  }
  @Test func shortEditorDoesNotOverflowAndLongLineDoes() {
    let doc = QueryDocument(server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master", title: "Width")
    doc.sql = "SELECT 1;"
    let controller = EditorController(document: doc)
    controller.surface.frame = NSRect(x: 0,y: 0,width: 800,height: 500)
    controller.surface.layoutSubtreeIfNeeded(); controller.resizeToViewport()
    #expect(controller.editor.frame.width <= controller.scroll.contentView.bounds.width + 1)
    controller.replaceText(String(repeating: "SELECT ", count: 300))
    controller.resizeToViewport()
    #expect(controller.editor.frame.width > controller.scroll.contentView.bounds.width)
    controller.replaceText("SELECT 1;"); controller.resizeToViewport()
    #expect(controller.editor.frame.width <= controller.scroll.contentView.bounds.width + 1)
  }
  @Test func tabsBlockIndentAndNewlinePreserveScriptAlignment() {
    let doc = QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Indent")
    doc.sql = "\tSELECT 1;\n    SELECT 2;"
    let original = doc.sql
    let controller = EditorController(document:doc), editor = controller.editor
    #expect(abs((editor.defaultParagraphStyle?.defaultTabInterval ?? 0) - (" " as NSString).size(withAttributes:[.font:StudioTheme.codeFont]).width * 4) < 0.1)
    editor.setSelectedRange(NSRange(location:0,length:(editor.string as NSString).length))
    editor.insertTab(nil)
    #expect(editor.string == "\t\tSELECT 1;\n\t    SELECT 2;")
    editor.insertBacktab(nil)
    #expect(editor.string == original)
    editor.setSelectedRange(NSRange(location:10,length:0))
    editor.insertNewline(nil)
    #expect(editor.string.hasPrefix("\tSELECT 1;\n\t"))
  }
  @Test func typingShortScriptKeepsViewportAndMetrics() async throws {
    let doc = QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Viewport")
    let controller = EditorController(document:doc)
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false; window.contentView = controller.surface
    defer { window.close() }
    controller.surface.layoutSubtreeIfNeeded(); controller.resizeToViewport()
    #expect(controller.scroll.hitTest(NSPoint(x:controller.scroll.frame.minX+200,y:controller.scroll.frame.minY+200)) is SQLTextView)
    #expect(controller.editor.isEditable)
    #expect(controller.editor.isSelectable)
    #expect(window.makeFirstResponder(controller.editor))
    controller.editor.insertText("SELECT\n\tGETDATE(), N'İstanbul';",replacementRange:NSRange(location:0,length:0))
    // Wait for asynchronous analysis instead of assuming CI scheduling latency.
    for _ in 0..<100 {
      if controller.editor.textContentStorage?.textStorage?.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.keyword) {break}
      try await Task.sleep(for:.milliseconds(50))
    }
    #expect(abs(controller.scroll.contentView.bounds.minX) < 1)
    let storage = try #require(controller.editor.textContentStorage?.textStorage)
    #expect(storage.attribute(.font,at:0,effectiveRange:nil) as? NSFont == StudioTheme.codeFont)
    #expect(storage.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.keyword))
  }
  @Test func themeSwitchPreservesUnicodeSelectionUndoAndTextKit2() async throws {
    _ = NSApplication.shared
    let previous = UserDefaults.standard.string(forKey: "ssmsTheme")
    defer {
      StudioTheme.apply(previous ?? "light")
      if previous == nil { UserDefaults.standard.removeObject(forKey: "ssmsTheme") }
    }
    StudioTheme.start()
    let server = ConnectedServer(profile: ServerProfile(), password: "")
    let doc = QueryDocument(server: server, database: "master", title: "Theme test")
    doc.sql = "SELECT N'İstanbul 😀', @n, 42, GETDATE(); -- comment"
    let controller = EditorController(document: doc)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.surface
    let editor = controller.editor
    window.makeFirstResponder(editor)
    defer { window.close() }
    #expect(editor.textLayoutManager != nil)
    let selection = NSRange(location: 7, length: 14)
    editor.setSelectedRange(selection)
    let original = editor.string
    StudioTheme.apply("dark")
    #expect(editor.string == original)
    #expect(editor.selectedRange() == selection)
    #expect(editor.textLayoutManager != nil)
    let storage = try #require(editor.textContentStorage?.textStorage)
    #expect(storage.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.keyword))
    let commentOffset = (original as NSString).range(of:"-- comment").location
    #expect(storage.attribute(.foregroundColor,at:commentOffset,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.comment))
    editor.setSelectedRange(NSRange(location: storage.length, length: 0))
    editor.insertText("\nSELECT 2;", replacementRange: editor.selectedRange())
    #expect(editor.undoManager?.canUndo == true)
    StudioTheme.apply("light")
    editor.undoManager?.undo()
    try await Task.sleep(for: .milliseconds(30))
    #expect(editor.string == original)
    #expect(doc.sql == original)
  }
  @Test func indexedDiagnosticsAreDebouncedAndStaleEditsDoNotPublish() async throws {
    let doc = QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Intelligence")
    doc.intelligenceCatalog = .init(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"Customers",columns:["Name"])]))
    doc.catalogDatabase = "master"; doc.catalogVerified = true
    let controller = EditorController(document:doc)
    controller.replaceText("SELECT c.Missing FROM dbo.Customers c; ")
    controller.editor.setSelectedRange(NSRange(location:(controller.editor.string as NSString).length,length:0))
    controller.scheduleIntelligence(allowPopup:false)
    for _ in 0..<100 {
      if controller.diagnostics.count == 1 {break}
      try await Task.sleep(for:.milliseconds(50))
    }
    #expect(controller.diagnostics.count == 1)
    let range = try #require(controller.diagnostics.first?.range)
    #expect(controller.editor.textContentStorage?.textStorage?.attribute(.foregroundColor,at:range.location,effectiveRange:nil) as? NSColor == .systemRed)
    controller.replaceText("SELECT * FROM Missing; ")
    controller.replaceText("SELECT c.Name FROM dbo.Customers c; ")
    controller.editor.setSelectedRange(NSRange(location:(controller.editor.string as NSString).length,length:0))
    controller.scheduleIntelligence(allowPopup:false)
    for _ in 0..<100 {
      if controller.diagnostics.isEmpty {break}
      try await Task.sleep(for:.milliseconds(50))
    }
    #expect(controller.diagnostics.isEmpty)
    #expect(controller.editor.string == doc.sql)
    #expect(controller.editor.textLayoutManager != nil)
  }

  @Test func completionAnchorUsesTextKit2CaretGeometry() throws {
    let doc = QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Anchor")
    doc.sql = "SELECT * FROM Customers c WHERE c."
    let controller = EditorController(document:doc)
    controller.surface.frame = NSRect(x:0,y:0,width:1000,height:600)
    controller.surface.layoutSubtreeIfNeeded(); controller.resizeToViewport()
    controller.editor.setSelectedRange(NSRange(location:(doc.sql as NSString).length,length:0))
    let anchor = try #require(controller.suggestionAnchor())
    #expect(anchor.minY >= 0 && anchor.minY < 40)
    #expect(anchor.minX > 150 && anchor.minX < 600)
    #expect(anchor.height > 0 && anchor.width >= 1)
  }

}
