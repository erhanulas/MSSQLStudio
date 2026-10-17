import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorViewportResizeTests {
  @Test func childViewportResizeImmediatelyCoversSurfaceAndPreservesScrollAnchor() throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(previous ?? "light")}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let server=ConnectedServer(profile:.init(),password:"");server.online=false
      let doc=QueryDocument(server:server,database:"master",title:"Resize")
      doc.sql="SELECT 1;"
      let controller=EditorController(document:doc)
      let window=NSWindow(contentRect:NSRect(x:-2000,y:0,width:850,height:220),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=controller.surface;defer {window.close()}
      controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
      StudioTheme.decorate(controller.surface)
      #expect(controller.scroll.backgroundColor==StudioTheme.editorCanvas)
      for height:CGFloat in [600,180,650,220,500] {
        controller.surface.setFrameSize(NSSize(width:850,height:height));controller.surface.layoutSubtreeIfNeeded()
        // No owner viewDidLayout/explicit resize: the native viewport must be ready now.
        #expect(controller.editor.frame.height>=controller.scroll.contentView.bounds.height)
        #expect(controller.scroll.contentView.bounds.origin == .zero)
      }
      controller.replaceText(String(repeating:"SELECT N'Visible SQL', 42;\n",count:500))
      let clip=controller.scroll.contentView
      clip.scroll(to:NSPoint(x:0,y:1200));controller.scroll.reflectScrolledClipView(clip)
      controller.resizeToViewport()
      let anchor=clip.bounds.origin,selection=controller.editor.selectedRange(),source=doc.sql
      for height:CGFloat in [180,650,200,580,220] {
        controller.surface.setFrameSize(NSSize(width:850,height:height));controller.surface.layoutSubtreeIfNeeded()
        #expect(abs(clip.bounds.origin.y-anchor.y)<1)
        #expect(controller.editor.frame.height>=clip.bounds.maxY)
        let viewport=try #require(controller.editor.textLayoutManager?.textViewportLayoutController.viewportRange)
        let content=try #require(controller.editor.textContentStorage)
        #expect(content.offset(from:viewport.location,to:viewport.endLocation)>0)
      }
      #expect(doc.sql==source && controller.editor.selectedRange()==selection)
      let bitmap=try #require(controller.surface.bitmapImageRepForCachingDisplay(in:controller.surface.bounds))
      controller.surface.cacheDisplay(in:controller.surface.bounds,to:bitmap)
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-viewport-resize-"+theme+".png"))
    }
  }
  @Test func resultDividerAndHideShowKeepVisibleSQLPositionAndSelection() throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Result divider")
    doc.sql=String(repeating:"SELECT N'Visible SQL', 42;\n",count:500)
    doc.results=[Rows(fields:[Field("ID",type:4)],values:[["1"]])]
    let controller=QueryController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:-2000,y:0,width:1000,height:720),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=controller;defer {window.close()}
    controller.view.layoutSubtreeIfNeeded()
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let split=try #require(descendants(controller.view).compactMap {$0 as? ResultSplitView}.first)
    let text=try #require(descendants(controller.view).compactMap {$0 as? SQLTextView}.first)
    let scroll=try #require(text.enclosingScrollView),clip=scroll.contentView
    clip.scroll(to:NSPoint(x:0,y:1200));scroll.reflectScrolledClipView(clip)
    let anchor=clip.bounds.origin,selection=text.selectedRange(),source=doc.sql
    for position:CGFloat in [160,500,210,550,180,450] {
      split.setPosition(position,ofDividerAt:0);split.layoutSubtreeIfNeeded()
      #expect(abs(clip.bounds.origin.y-anchor.y)<1)
      #expect(text.frame.height>=clip.bounds.maxY && text.string==source && text.selectedRange()==selection)
    }
    controller.toggleResults();controller.view.layoutSubtreeIfNeeded()
    #expect(abs(clip.bounds.origin.y-anchor.y)<1)
    controller.toggleResults();controller.view.layoutSubtreeIfNeeded()
    #expect(abs(clip.bounds.origin.y-anchor.y)<1 && text.selectedRange()==selection)
  }

}
