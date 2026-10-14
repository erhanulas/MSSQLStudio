import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ResultSourceUITests {
  func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
  @Test func tabHelpUsesExecutedSnapshotAndUpdatesWithoutChangingTabCount() throws {
    _ = NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Sources")
    doc.sql="SELECT 1; SELECT NULL;";doc.state = .ready
    doc.results=[Rows(fields:[Field("First")],values:[["1"]]),Rows(fields:[Field("Missing")],values:[[nil]])]
    let map=ResultSourceMap(sql:doc.sql),sources=map.sources(for:doc.results)
    for index in doc.results.indices {doc.results[index].source=sources[index]}
    let controller=QueryController(document:doc);_=controller.view
    let strip=try #require(descendants(controller.view).first {$0.accessibilityIdentifier()=="resultTabStrip"} as? NSStackView)
    let buttons=strip.arrangedSubviews.compactMap {$0 as? StudioResultTabButton}
    #expect(buttons.count==3)
    #expect(buttons[0].toolTip?.contains("SELECT 1;")==true)
    #expect(buttons[1].accessibilityHelp()?.contains("SELECT NULL;")==true)
    #expect(buttons[2].source==nil && buttons[2].toolTip==nil)
    doc.sql="DELETE FROM NeverExecute;";controller.update()
    #expect(buttons[0].source?.sql=="SELECT 1;" && buttons[1].source?.sql=="SELECT NULL;")
    doc.results[0].source=SQLResultSource(sql:"SELECT N'refreshed';",batch:2)
    controller.update()
    #expect(buttons[0].toolTip?.contains("refreshed")==true && buttons[0].toolTip?.contains("Grup 2")==true)
    buttons[1].performClick(nil)
    #expect(doc.results[1].values[0][0]==nil && doc.sql=="DELETE FROM NeverExecute;")
  }
  @Test func functionReturnPreviewFitsSingleRowAndKeepsLongNamesHorizontallyReachable() throws {
    _=NSApplication.shared
    var execution=Execution()
    let longName=String(repeating:"LongColumn",count:12)
    execution.results=[Rows(values:[["43","dbo","Projection","SQL_TABLE_VALUED_FUNCTION",longName,"nvarchar(4000) NULL","1"]])]
    let info=try #require(SQLObjectHover.decode(execution))
    let preview=FunctionReturnPreview(title:info.title,columns:info.columns,screen:NSSize(width:800,height:600))
    let window=NSWindow(contentRect:preview.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=preview;window.orderFront(nil)
    defer {window.close()}
    preview.layoutSubtreeIfNeeded();preview.displayIfNeeded()
    #expect(preview.table.visibleRect.height>=24)
    #expect(preview.table.tableColumns[1].width>preview.scroll.bounds.width)
    let cell=try #require(preview.tableView(preview.table,viewFor:preview.table.tableColumns[1],row:0) as? NSTextField)
    #expect(cell.stringValue==longName)
    preview.table.scrollColumnToVisible(2)
    #expect(preview.table.visibleRect.maxX>=preview.table.rect(ofColumn:2).maxX-1)
  }
  @Test func functionReturnPreviewShowsAllColumnsAndScrollsWithoutMovingEditorFocus() async throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    let window=NSWindow(contentRect:NSRect(x:100,y:100,width:830,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    let editor=NSTextView(frame:NSRect(x:20,y:350,width:700,height:200))
    editor.string="SELECT * FROM dbo.Projection()"
    window.contentView?.addSubview(editor);window.makeKeyAndOrderFront(nil);window.makeFirstResponder(editor)
    var execution=Execution()
    execution.results=[Rows(values:(1...80).map {["43","dbo","Projection","SQL_TABLE_VALUED_FUNCTION","Column_\($0)","CustomAmount (decimal(28,8)) NOT NULL",String($0)]})]
    let info=try #require(SQLObjectHover.decode(execution))
    let help=StudioHoverHelp.shared
    defer {help.hide();window.close();StudioTheme.apply(previous ?? "light")}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      help.schedule(for:editor,title:info.title,detail:info.detail,rect:NSRect(x:0,y:20,width:200,height:20),columns:info.columns)
      let deadline=ContinuousClock.now.advanced(by:.seconds(2))
      while help.visibleTitle==nil && ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(10))}
      let panel=try #require(window.childWindows?.first {$0.contentView is FunctionReturnPreview})
      let preview=try #require(panel.contentView as? FunctionReturnPreview)
      #expect(preview.table.numberOfRows==80 && !panel.ignoresMouseEvents)
      #expect(preview.frame.height<=440 && window.firstResponder === editor)
      #expect(preview.table.tableColumns[1].width>=120)
      preview.layoutSubtreeIfNeeded();preview.displayIfNeeded()
      if let bitmap=preview.bitmapImageRepForCachingDisplay(in:preview.bounds) {
        preview.cacheDisplay(in:preview.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-function-return-\(theme).png"))
      }
      preview.table.scrollRowToVisible(79)
      #expect(preview.table.rows(in:preview.table.visibleRect).contains(79))
      let last=try #require(preview.tableView(preview.table,viewFor:preview.table.tableColumns[2],row:79) as? NSTextField)
      #expect(last.stringValue=="CustomAmount (decimal(28,8)) NOT NULL")
      help.hide();#expect(editor.string=="SELECT * FROM dbo.Projection()" && window.firstResponder === editor)
    }
  }
  @Test func sqlHoverShowsPromptlyWithThemeColorsAndCancelsOnExitAndSourceReplacement() async throws {
    _ = NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    let button=StudioResultTabButton(title:"Results 1 (1)",target:nil,action:nil)
    button.frame=NSRect(x:540,y:10,width:150,height:32);button.setAccessibilityLabel(button.title)
    window.contentView?.addSubview(button);window.orderFront(nil)
    let source=SQLResultSource(sql:"SELECT N'İstanbul' AS City; -- kaynak\nSELECT 42;",kind:.batch)
    button.source=source
    let help=StudioHoverHelp.shared
    defer {help.hide();window.close();StudioTheme.apply(previous ?? "light")}
    let event=try #require(NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil))
    for theme in ["light","dark"] {
      StudioTheme.apply(theme);button.mouseEntered(with:event)
      let deadline=ContinuousClock.now.advanced(by:.seconds(2))
      while help.visibleTitle==nil && ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(25))}
      #expect(help.visibleTitle==button.title && help.visibleDetail==source.preview)
      let panel=try #require(window.childWindows?.first {$0 is NSPanel})
      let panelContent=try #require(panel.contentView)
      let code=try #require(descendants(panelContent).compactMap {$0 as? NSTextField}.first {$0.stringValue.contains("SELECT")})
      let keyword=try #require(code.attributedStringValue.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor)
      #expect(keyword==StudioTheme.syntax(.keyword))
      if let screen=window.screen {#expect(screen.visibleFrame.contains(panel.frame))}
      if let content=panel.contentView,let image=content.bitmapImageRepForCachingDisplay(in:content.bounds) {
        content.cacheDisplay(in:content.bounds,to:image)
        try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-result-source-hover-\(theme).png"))
      }
      button.mouseExited(with:event);#expect(help.visibleTitle==nil)
    }
    button.mouseEntered(with:event);button.source=SQLResultSource(sql:"SELECT 99;")
    try await Task.sleep(for:.milliseconds(250))
    #expect(help.visibleTitle==nil && button.toolTip?.contains("SELECT 99;")==true)
  }
}
