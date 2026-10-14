import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorPresentation134Tests {
  private func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
  @Test func longOfflinePreviewKeepsCRLinesAndVeryWideTailReachable() throws {
    _=NSApplication.shared
    let preview=SQLPreviewView(frame:NSRect(x:0,y:0,width:830,height:500))
    let window=NSWindow(contentRect:preview.bounds,styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=preview;window.orderFront(nil)
    defer {window.close()}
    for separator in ["\r","\r\n","\n","\u{2028}"] {
      let source=String(repeating:"SELECT 1;"+separator,count:2500)+"SELECT N'END_MARKER';"
      preview.display(source);preview.layoutSubtreeIfNeeded()
      let text=preview.textView
      #expect(text.string==source && preview.ruler.lineNumber?(source.utf16.count-2)==2501)
      #expect(text.frame.height>=50000)
      let tail=(source as NSString).range(of:"END_MARKER")
      text.setSelectedRange(tail);text.scrollRangeToVisible(tail)
      #expect((text.string as NSString).substring(with:text.selectedRange())=="END_MARKER")
    }
    let wide="SELECT N'"+String(repeating:"W",count:20000)+"WIDE_TAIL';"
    preview.display(wide);preview.layoutSubtreeIfNeeded()
    #expect(preview.textView.frame.width>100000 && preview.textView.string==wide)
    let tail=(wide as NSString).range(of:"WIDE_TAIL")
    preview.textView.scrollRangeToVisible(tail)
    #expect(preview.scroll.contentView.bounds.maxX>100000)
    preview.displayIfNeeded()
    if let image=preview.bitmapImageRepForCachingDisplay(in:preview.bounds) {
      preview.cacheDisplay(in:preview.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql134-wide-tail.png"))
    }
  }
  @Test func insertSelectPreviewSurvivesRepaintNotificationsAndDelayedSyntax() async throws {
    _=NSApplication.shared
    let sql="INSERT dbo.Events (Code, Amount, CreatedAt) SELECT s.Code, SUM(CASE WHEN s.Kind='G' THEN s.Amount ELSE -1*s.Amount END), CAST(GETDATE() AS DATE) FROM dbo.Source s GROUP BY s.Code;"
    let doc=QueryDocument(server:ConnectedServer(profile:.init(),password:""),database:"master",title:"Insert select")
    doc.sql=sql;doc.server.online=false
    let controller=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:100,y:100,width:950,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.orderFront(nil)
    defer {controller.insertPresentation.hidePreview();window.close()}
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport();window.makeFirstResponder(controller.editor)
    controller.editor.setSelectedRange(NSRange(location:(sql as NSString).range(of:"Amount").location+2,length:0))
    controller.editor.mouseSelectionEnded?()
    #expect(controller.insertPresentation.match?.ordinal==2 && controller.insertPresentation.isShown)
    NotificationCenter.default.post(name:NSView.boundsDidChangeNotification,object:controller.scroll.contentView)
    try await Task.sleep(for:.milliseconds(350))
    #expect(controller.insertPresentation.isShown && controller.occurrenceHighlights.insertRanges.count==2)
    #expect(controller.editor.string==sql && doc.lastExecutedSQL==nil)
  }
  @Test func expandingEditorResolvesNewViewportImmediatelyWithoutChangingColors() throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:.init(),password:""),database:"master",title:"Resize")
    doc.sql=String(repeating:"SELECT N'Visible text', 42;\n",count:300);doc.server.online=false
    let controller=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:100,y:100,width:830,height:180),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.orderFront(nil)
    defer {window.close()}
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    let before=controller.editor.visibleCharacterRanges.last.map {NSMaxRange($0.rangeValue)} ?? 0
    window.setContentSize(NSSize(width:830,height:700));controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    let after=controller.editor.visibleCharacterRanges.last.map {NSMaxRange($0.rangeValue)} ?? 0
    #expect(after>before)
    let storage=try #require(controller.editor.textContentStorage?.textStorage)
    #expect(storage.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.keyword))
    #expect(controller.editor.string==doc.sql)
  }
  @Test func rowLimitMenuIsFlatAndAllKeepsCachedRowsWithoutRunningSQL() throws {
    _=NSApplication.shared
    let defaults=UserDefaults.standard,old=defaults.object(forKey:"gridReadLimit")
    defer {defaults.set(old,forKey:"gridReadLimit")}
    let doc=QueryDocument(server:ConnectedServer(profile:.init(),password:""),database:"master",title:"Limits")
    doc.sql="SELECT * FROM dbo.Source";doc.limits=ResultReadPreferences.limits(rows:1000)
    doc.results=[Rows(fields:[Field("Id")],values:(0..<1200).map {[String($0)]})]
    let query=QueryController(document:doc);_=query.view
    let menu=try #require(descendants(query.view).compactMap {$0 as? NSPopUpButton}.first {$0.accessibilityIdentifier()=="gridRowOptions"}?.menu)
    #expect(menu.items.allSatisfy {$0.submenu==nil})
    let items=menu.items.filter {$0.identifier?.rawValue=="gridReadChoices"}
    #expect([10,100,250,500,1000,0].allSatisfy {value in items.contains {$0.tag==value}})
    let all=try #require(items.first {$0.tag==0})
    #expect(NSApp.sendAction(try #require(all.action),to:all.target,from:all))
    let grid=try #require(query.children.compactMap {$0 as? ResultController}.first)
    #expect(doc.limits.rows==Int.max && grid.result.values.count==1200 && doc.lastExecutedSQL==nil)
  }
}
