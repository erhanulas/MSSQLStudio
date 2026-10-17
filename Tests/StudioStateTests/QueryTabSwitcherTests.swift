import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct QueryTabSwitcherTests {
  private func fixture(count:Int=8)->(StudioState,WorkbenchController,NSWindow) {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:ServerProfile(name:"Development",database:"Demo"),password:"");server.online=false
    state.servers=[server]
    for index in 0..<count {
      state.newQuery(server:server,text:"SELECT \(index) AS Result;\n-- Query preview\nFROM Example;",title:"SQLQuery\(index).sql")
    }
    state.active=state.documents[0]
    let owner=WorkbenchController(state:state),window=NSWindow(contentViewController:owner)
    window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:1060,height:680))
    window.setFrameOrigin(NSPoint(x:-20000,y:0));window.makeKeyAndOrderFront(nil)
    owner.tabSwitcher.placementRole="tabSwitcherTest-"+UUID().uuidString
    owner.loadViewIfNeeded()
    return (state,owner,window)
  }
  private func event(_ window:NSWindow,key:UInt16,flags:NSEvent.ModifierFlags = .option,type:NSEvent.EventType = .keyDown)->NSEvent {
    NSEvent.keyEvent(with:type,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:key==48 ? "\t":"",charactersIgnoringModifiers:key==48 ? (flags.contains(.shift) ? "\u{19}":"\t"):"",isARepeat:false,keyCode:key)!
  }
  @Test func optionReleaseKeepsSwitcherOpenAndOnlyEnterCommits() throws {
    let (state,owner,window)=fixture();defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
    let original=try #require(state.active),switcher=owner.tabSwitcher
    #expect(switcher.handle(event(window,key:48)))
    #expect(switcher.index==1 && state.active===original && switcher.panel != nil)
    #expect(switcher.handle(event(window,key:124)))
    #expect(switcher.index==2 && state.active===original)
    #expect(switcher.handle(event(window,key:123)))
    #expect(switcher.index==1)
    _=switcher.handle(event(window,key:58,flags:[],type:.flagsChanged))
    #expect(state.active===original && switcher.panel != nil)
    #expect(switcher.handle(event(window,key:36,flags:[])))
    #expect(state.active===state.documents[1] && switcher.panel==nil)
    #expect(!state.active!.busy && state.active!.sql.contains("SELECT 1"))
  }
  @Test func reverseWrapEscapeAndClosedCandidateAreSafe() throws {
    let (state,owner,window)=fixture();defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
    let switcher=owner.tabSwitcher,original=state.active
    #expect(switcher.handle(event(window,key:48,flags:[.option,.shift])))
    #expect(switcher.index==7)
    #expect(switcher.handle(event(window,key:124)))
    #expect(switcher.index==0)
    #expect(switcher.handle(event(window,key:53)))
    #expect(state.active===original && switcher.panel==nil)
    switcher.present(in:window)
    let removed=state.documents.remove(at:1)
    #expect(switcher.entries[switcher.index].id==removed.id)
    switcher.dismiss(commit:true)
    #expect(state.active===original)
  }
  @Test func windowClosureCancelsAndModifierChangesDoNotCommitEarly() throws {
    let (state,owner,window)=fixture();defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
    let original=state.active,switcher=owner.tabSwitcher
    switcher.present(in:window)
    _=switcher.handle(event(window,key:56,flags:[.option,.shift],type:.flagsChanged))
    #expect(switcher.panel != nil && state.active===original)
    NotificationCenter.default.post(name:NSWindow.willCloseNotification,object:window)
    #expect(switcher.panel==nil && state.active===original)
  }
  @Test func manyTabsClickAndStripHighlightPreserveTheOriginalDocument() throws {
    let (state,owner,window)=fixture(count:80);defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
    let original=state.active,switcher=owner.tabSwitcher
    let scroll=try #require(owner.tabs.enclosingScrollView)
    let origin=scroll.contentView.bounds.origin
    switcher.present(in:window)
    switcher.advance(70)
    #expect(switcher.index==71 && state.active===original)
    let candidate=state.documents[71]
    let surface=try #require(owner.tabs.arrangedSubviews.compactMap {$0 as? QueryTabSurface}.first {$0.primaryButton?.document===candidate})
    #expect(surface.isSwitchPreview && !surface.isActiveTab)
    let reveal=switcher.keyboardRevealRevision
    switcher.preview(state.documents[39].id)
    #expect(switcher.index==39 && !surface.isSwitchPreview && state.active===original)
    #expect(switcher.keyboardRevealRevision==reveal)
    _=switcher.handle(event(window,key:125))
    #expect(switcher.index==40 && switcher.keyboardRevealRevision>reveal)
    switcher.dismiss(commit:false)
    #expect(state.active===original && scroll.contentView.bounds.origin==origin)
    #expect(owner.tabs.arrangedSubviews.compactMap {$0 as? QueryTabSurface}.allSatisfy {!$0.isSwitchPreview})
  }
  @Test func resizedPanelRestoresSizeAcrossSwitcherInstances() throws {
    let (state,owner,window)=fixture();defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
    let role=owner.tabSwitcher.placementRole,key="NSWindow Frame "+StudioWindowPlacement.name(role)
    defer {UserDefaults.standard.removeObject(forKey:key)}
    owner.tabSwitcher.present(in:window)
    let panel=try #require(owner.tabSwitcher.panel),original=state.active
    #expect(panel.styleMask.contains(.resizable) && panel.styleMask.contains(.titled) && panel.styleMask.contains(.fullSizeContentView))
    #expect(panel.isOpaque && panel.backgroundColor != .clear)
    #expect(panel.contentMinSize==NSSize(width:680,height:400))
    panel.setContentSize(NSSize(width:880,height:480));panel.contentView?.layoutSubtreeIfNeeded()
    let saved=panel.frame.size
    owner.tabSwitcher.dismiss(commit:false)
    let next=QueryTabSwitcher(owner:owner);next.placementRole=role
    next.present(in:window);defer {next.dismiss(commit:false)}
    let reopened=try #require(next.panel)
    #expect(abs(reopened.frame.width-saved.width)<1 && abs(reopened.frame.height-saved.height)<1)
    #expect(!reopened.isKeyWindow && state.active === original)
  }
  @Test func movingPanelKeepsPreviewAndDocumentState() throws {
    let (state,owner,window)=fixture();defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
    let switcher=owner.tabSwitcher,original=state.active
    switcher.present(in:window)
    let panel=try #require(switcher.panel)
    panel.contentView?.layoutSubtreeIfNeeded()
    let dragArea=try #require(panel.contentView?.subviews.first {$0.identifier?.rawValue=="tabSwitcherDragArea"})
    #expect(dragArea.frame.height==44 && dragArea.frame.width==panel.contentView?.bounds.width)
    let selected=switcher.previewID,source=switcher.previewSQL,revision=switcher.keyboardRevealRevision,size=panel.frame.size
    let origin=panel.frame.origin,autosave=panel.frameAutosaveName
    func mouse(_ type:NSEvent.EventType,_ point:NSPoint)->NSEvent {
      NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:panel.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
    }
    dragArea.mouseDown(with:mouse(.leftMouseDown,NSPoint(x:100,y:100)))
    #expect(panel.frameAutosaveName.isEmpty)
    dragArea.mouseDragged(with:mouse(.leftMouseDragged,NSPoint(x:180,y:180)))
    dragArea.mouseUp(with:mouse(.leftMouseUp,NSPoint(x:100,y:100)))
    #expect(panel.frame.origin==NSPoint(x:origin.x+80,y:origin.y+80))
    #expect(panel.frameAutosaveName==autosave && !dragArea.mouseDownCanMoveWindow)
    for offset in 0..<60 {panel.setFrameOrigin(NSPoint(x:100+offset,y:100+offset))}
    #expect(panel.frame.origin==NSPoint(x:159,y:159) && panel.frame.size==size)
    #expect(switcher.previewID==selected && switcher.previewSQL==source && switcher.keyboardRevealRevision==revision)
    #expect(state.active === original)
  }
  @Test func pointerFocusOnPanelIsAllowedAndOtherWindowFocusCancels() async throws {
    let (state,owner,window)=fixture();defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
    let original=state.active,switcher=owner.tabSwitcher
    switcher.present(in:window)
    let panel=try #require(switcher.panel)
    panel.makeKey()
    try await Task.sleep(for:.milliseconds(40))
    #expect(switcher.panel === panel && state.active === original)
    let other=NSWindow(contentRect:NSRect(x:-22000,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false)
    other.isReleasedWhenClosed=false;defer {other.close()}
    other.makeKeyAndOrderFront(nil)
    try await Task.sleep(for:.milliseconds(40))
    #expect(switcher.panel==nil && state.active === original)
  }
  @Test func lateLexicalSnapshotRecolorsSameSourceWithoutMovingSelection() throws {
    let view=SQLPreviewView(frame:NSRect(x:0,y:0,width:600,height:300))
    let source=String(repeating:"SELECT 1;\n",count:1000)
    view.display(source,lexicalSnapshot:[])
    view.textView.setSelectedRange(NSRange(location:12,length:3))
    view.scroll.contentView.scroll(to:NSPoint(x:0,y:100))
    let origin=view.scroll.contentView.bounds.origin
    let storage=try #require(view.textView.textContentStorage?.textStorage)
    let plain=storage.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor
    view.display(source,lexicalSnapshot:TSQL.lex(source))
    #expect(storage.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor != plain)
    #expect(view.textView.selectedRange()==NSRange(location:12,length:3))
    #expect(view.scroll.contentView.bounds.origin==origin && view.textView.string==source)
  }
  @Test func fullLongSourceAndLatestColoredPreviewRemainConsistent() async throws {
    let (state,owner,window)=fixture();defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
    let long=String(repeating:"SELECT 1 AS n;\n",count:12000)+"-- LAST_LINE_MARKER"
    state.documents[1].sql=long
    owner.tabSwitcher.present(in:window)
    #expect(owner.tabSwitcher.previewSQL==long && owner.tabSwitcher.entries[1].sql==long)
    owner.tabSwitcher.preview(state.documents[0].id)
    for _ in 0..<300 where owner.tabSwitcher.previewBusy {try await Task.sleep(for:.milliseconds(3))}
    #expect(owner.tabSwitcher.previewSQL==state.documents[0].sql && !owner.tabSwitcher.previewTokens.isEmpty)
    owner.tabSwitcher.preview(state.documents[1].id)
    for _ in 0..<300 where owner.tabSwitcher.previewBusy {try await Task.sleep(for:.milliseconds(3))}
    #expect(owner.tabSwitcher.previewSQL.hasSuffix("-- LAST_LINE_MARKER") && !owner.tabSwitcher.previewTokens.isEmpty)
  }
  @Test func longPreviewScrollLaysOutFinalLinesAfterRecoloring() throws {
    _=NSApplication.shared
    let preview=SQLPreviewView(frame:NSRect(x:0,y:0,width:650,height:320))
    let window=NSWindow(contentRect:preview.bounds,styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=preview;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
    defer {window.close()}
    let source=String(repeating:"\t\tSELECT \t1 AS value, \t2 AS other;\n",count:12000)+"SELECT 'LAST_LINE_MARKER';"
    preview.display(source,lexicalSnapshot:[]);preview.layoutSubtreeIfNeeded()
    preview.display(source,lexicalSnapshot:TSQL.lex(source))
    let bottom=max(0,preview.textView.frame.height-preview.scroll.contentView.bounds.height)
    preview.scroll.contentView.scroll(to:NSPoint(x:0,y:bottom));preview.scroll.reflectScrolledClipView(preview.scroll.contentView)
    preview.displayIfNeeded()
    let content=try #require(preview.textView.textContentStorage)
    let viewport=try #require(preview.textView.textLayoutManager?.textViewportLayoutController.viewportRange)
    let end=content.offset(from:content.documentRange.location,to:viewport.endLocation)
    #expect(end>=source.utf16.count-30)
    #expect(preview.textView.string==source)
    let bitmap=try #require(preview.bitmapImageRepForCachingDisplay(in:preview.bounds))
    preview.cacheDisplay(in:preview.bounds,to:bitmap)
    try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-preview-last-lines.png"))
  }
  @Test func tabbedPreviewPhysicalLinesFitTheScrollableDocument() throws {
    let preview=SQLPreviewView(frame:NSRect(x:0,y:0,width:650,height:320))
    let window=NSWindow(contentRect:preview.bounds,styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=preview;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
    defer {window.close()}
    let line=String(repeating:"\t",count:20)+"SELECT 1 AS Value; -- "+String(repeating:"x",count:120)+"\r\n"
    let source=String(repeating:line,count:700)+"SELECT 'FINAL_SOURCE_LINE';"
    preview.display(source,lexicalSnapshot:[]);preview.layoutSubtreeIfNeeded()
    let content=try #require(preview.textView.textContentStorage),layout=try #require(preview.textView.textLayoutManager)
    layout.ensureLayout(for:content.documentRange)
    var bottom:CGFloat=0,visualLines=0
    layout.enumerateTextLayoutFragments(from:content.documentRange.location,options:[]) {fragment in
      bottom=max(bottom,fragment.layoutFragmentFrame.maxY)
      visualLines+=fragment.textLineFragments.count
      return true
    }
    #expect(visualLines==701)
    #expect(bottom+preview.textView.textContainerInset.height<=preview.textView.frame.height)
    #expect(preview.textView.string==source)
  }
  @Test func hostedTabbedPreviewCanScrollToTheExactFinalLine() async throws {
    let (state,owner,window)=fixture();defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
    let line=String(repeating:"\t",count:20)+"SELECT 1 AS Value; -- "+String(repeating:"x",count:120)+"\r\n"
    let source=String(repeating:line,count:700)+"SELECT 'FINAL_SOURCE_LINE';"
    state.documents[1].sql=source;owner.tabSwitcher.present(in:window)
    for _ in 0..<300 where owner.tabSwitcher.previewBusy {try await Task.sleep(for:.milliseconds(3))}
    let panel=try #require(owner.tabSwitcher.panel)
    panel.contentView?.layoutSubtreeIfNeeded()
    func children(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(children)}
    let host=try #require(panel.contentView)
    let preview=try #require(children(host).compactMap {$0 as? SQLPreviewView}.first)
    for row in stride(from:0,through:700,by:13) {
      preview.scroll.contentView.scroll(to:NSPoint(x:0,y:CGFloat(row)*20))
      preview.scroll.reflectScrolledClipView(preview.scroll.contentView)
      try await Task.sleep(for:.milliseconds(1))
    }
    let bottom=max(0,preview.textView.frame.height-preview.scroll.contentView.bounds.height)
    preview.scroll.contentView.scroll(to:NSPoint(x:0,y:bottom));preview.scroll.reflectScrolledClipView(preview.scroll.contentView)
    try await Task.sleep(for:.milliseconds(40))
    let content=try #require(preview.textView.textContentStorage),viewport=try #require(preview.textView.textLayoutManager?.textViewportLayoutController.viewportRange)
    let end=content.offset(from:content.documentRange.location,to:viewport.endLocation)
    #expect(end==source.utf16.count)
    let start=try #require(content.location(content.documentRange.location,offsetBy:source.utf16.count-26))
    let range=try #require(NSTextRange(location:start,end:content.documentRange.endLocation))
    var finalRect:NSRect = .zero
    preview.textView.textLayoutManager?.enumerateTextSegments(in:range,type:.standard,options:[]) {_,rect,_,_ in finalRect=finalRect.union(rect);return true}
    #expect(finalRect.maxY+preview.textView.textContainerOrigin.y<=preview.scroll.documentVisibleRect.maxY)
  }
  @Test func incrementalScrollPastLine430KeepsTextVisibleAfterRecoloringAndResize() throws {
    _=NSApplication.shared
    let mode=StudioTheme.mode;defer {StudioTheme.apply(mode)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let preview=SQLPreviewView(frame:NSRect(x:0,y:0,width:650,height:320))
      let window=NSPanel(contentRect:preview.bounds,styleMask:[.titled,.nonactivatingPanel],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=preview;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
      defer {window.close()}
      let line="SELECT 123 AS VisibleValue;\n",source=String(repeating:line,count:1600)
      preview.display(source,lexicalSnapshot:[]);preview.layoutSubtreeIfNeeded()
      let content=try #require(preview.textView.textContentStorage)
      for row in stride(from:0,through:1500,by:10) {
        preview.scroll.contentView.scroll(to:NSPoint(x:0,y:CGFloat(row)*20))
        preview.scroll.reflectScrolledClipView(preview.scroll.contentView)
        if row==430 {
          preview.display(source,lexicalSnapshot:TSQL.lex(source))
          window.setContentSize(NSSize(width:800,height:450));preview.layoutSubtreeIfNeeded()
        }
        let viewport=try #require(preview.textView.textLayoutManager?.textViewportLayoutController.viewportRange)
        let start=content.offset(from:content.documentRange.location,to:viewport.location)
        let end=content.offset(from:content.documentRange.location,to:viewport.endLocation)
        #expect(start<=row*line.utf16.count && end>=(row+10)*line.utf16.count)
      }
      let bitmap=try #require(preview.bitmapImageRepForCachingDisplay(in:preview.bounds))
      preview.cacheDisplay(in:preview.bounds,to:bitmap)
      var ink=0
      for y in 0..<bitmap.pixelsHigh {
        for x in (bitmap.pixelsWide/4)..<(bitmap.pixelsWide/2) {
          if let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),let canvas=StudioTheme.editorCanvas.usingColorSpace(.deviceRGB),abs(color.redComponent-canvas.redComponent)+abs(color.greenComponent-canvas.greenComponent)+abs(color.blueComponent-canvas.blueComponent)>0.3 {ink+=1}
        }
      }
      #expect(ink>100)
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-preview-line1500-"+theme+".png"))
    }
  }
  @Test func previewFitsBothThemesAndShortcutIsDiscoverable() throws {
    let previous=StudioTheme.mode;defer {StudioTheme.apply(previous)}
    #expect(GridShortcuts.binding(.tabSwitcher).key=="\t")
    #expect(ShortcutCatalog.category(.tabSwitcher) == .workspace)
    #expect(GridShortcuts.keyLabel("\t")=="⇥")
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let (_,owner,window)=fixture();defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
      owner.tabSwitcher.present(in:window)
      let panel=try #require(owner.tabSwitcher.panel),view=try #require(panel.contentView)
      #expect(!panel.isKeyWindow && window.childWindows?.contains(panel)==true)
      view.layoutSubtreeIfNeeded()
      func children(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(children)}
      let preview=try #require(children(view).compactMap {$0 as? SQLPreviewView}.first)
      #expect(preview.textView.string==owner.tabSwitcher.previewSQL)
      let storage=try #require(preview.textView.textContentStorage?.textStorage)
      #expect(storage.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.keyword))
      let split=try #require(children(view).compactMap {$0 as? NSSplitView}.first {$0.isVertical})
      #expect(split.arrangedSubviews.count==2 && split.arrangedSubviews[1].frame.width>split.arrangedSubviews[0].frame.width)
      let image=try #require(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-tab-switcher-"+theme+".png"))
    }
  }
}
