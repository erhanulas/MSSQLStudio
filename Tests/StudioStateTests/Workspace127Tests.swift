import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct Workspace127Tests {
  private func event(_ key:String,flags:NSEvent.ModifierFlags = [.control,.option])->NSEvent {
    NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:0)!
  }
  private func resetShortcuts()->[String:Any] {
    var old:[String:Any]=[:]
    for action in GridShortcuts.Action.allCases {let key="shortcut."+action.rawValue;old[key]=UserDefaults.standard.object(forKey:key);UserDefaults.standard.removeObject(forKey:key)}
    return old
  }
  private func restore(_ old:[String:Any]) {
    for action in GridShortcuts.Action.allCases {let key="shortcut."+action.rawValue;if let value=old[key] {UserDefaults.standard.set(value,forKey:key)} else {UserDefaults.standard.removeObject(forKey:key)}}
  }
  @Test func searchableChoicesFilterWithoutChangingSelectionAndAcceptExactlyOnce() {
    _=NSApplication.shared
    var selected="Demo",commits=0,dismissals=0
    let picker=StudioSearchableChoices(values:["Demo","Archive2026","Demo_Archive"],selected:selected) {selected=$0;commits+=1}
    picker.dismiss={dismissals+=1}
    picker.filter("archive")
    #expect(picker.filtered==["Archive2026","Demo_Archive"] && selected=="Demo" && commits==0)
    _=picker.control(picker.search,textView:NSTextView(),doCommandBy:#selector(NSResponder.moveDown(_:)))
    picker.commit();#expect(selected=="Demo_Archive" && commits==1 && dismissals==1)
    picker.filter("missing");picker.commit();#expect(commits==1 && dismissals==1 && picker.filtered.isEmpty)
    _=picker.control(picker.search,textView:NSTextView(),doCommandBy:#selector(NSResponder.cancelOperation(_:)))
    #expect(commits==1 && dismissals==2)
  }
  @Test func menuShortcutsAreSharedCustomizableClearableAndConflictsRemainRejected() throws {
    _=NSApplication.shared
    let old=resetShortcuts();defer {restore(old)}
    var prepared=false
    #expect(!StudioCommandCatalog.dispatch(event("a",flags:[]),to:NSResponder(),menu:{prepared=true;return nil}) && !prepared)
    #expect(!StudioCommandCatalog.dispatch(event("s",flags:.command),to:NSResponder(),allowForwardedTarget:false,menu:{prepared=true;return nil}) && !prepared)
    #expect(GridShortcuts.binding(.revealExplorer).label=="Atanmamış")
    #expect(GridShortcuts.save(event("g"),action:.revealExplorer)==nil)
    #expect(GridShortcuts.save(event("g"),action:.definition) != nil)
    #expect(GridShortcuts.save(event("s",flags:.command),action:.definition) != nil)
    let menu=StudioMenu();let item=menu.addItem(withTitle:"Explorer’da Git",action:Selector(("revealExplorerObject:")),keyEquivalent:"")
    #expect(item.preferredImageVisibility == .visible && item.image != nil && item.keyEquivalent=="g" && item.keyEquivalentModifierMask==[.control,.option])
    GridShortcuts.clear(.revealExplorer);menu.update()
    #expect(item.keyEquivalent.isEmpty && !GridShortcuts.matches(.revealExplorer,event("")))
    #expect(GridShortcuts.save(event("g"),action:.definition)==nil)
    GridShortcuts.reset(.definition);#expect(GridShortcuts.binding(.definition).key=="b")
    let native=NSMenu();native.autoenablesItems=false
    let original=NSMenuItem(title:"Kopyala",action:Selector(("copy:")),keyEquivalent:"c")
    original.tag=7;original.representedObject=["fixture"];original.isEnabled=false;native.addItem(original)
    let child=NSMenu();child.addItem(withTitle:"Alt eylem",action:nil,keyEquivalent:"")
    let parent=NSMenuItem(title:"Alt menü",action:nil,keyEquivalent:"");parent.submenu=child;native.addItem(parent)
    let originalImage=original.image,originalVisibility=original.preferredImageVisibility
    let adopted=StudioMenu.adopting(native)
    #expect(native.items.count==2 && original.image === originalImage && original.preferredImageVisibility==originalVisibility)
    #expect(adopted.items[0] !== original && adopted.items[0].tag==7 && adopted.items[0].representedObject as? [String]==["fixture"])
    #expect(!adopted.items[0].isEnabled && adopted.items[0].keyEquivalent=="c" && adopted.items[1].submenu is StudioMenu)
  }
  @Test func editorContextShortcutUsesCurrentCaretAndCannotActWhenDisabled() throws {
    _=NSApplication.shared
    let old=resetShortcuts();defer {restore(old)}
    let editor=SQLTextView(usingTextLayoutManager:true);editor.string="SELECT * FROM dbo.Orders";editor.setSelectedRange(NSRange(location:20,length:0))
    var parts:[String]=[];editor.revealInExplorer={parts=$0}
    #expect(GridShortcuts.save(event("g"),action:.revealExplorer)==nil)
    #expect(StudioCommandCatalog.dispatch(event("g"),to:editor,menu:{editor.makeSQLMenu(at:editor.selectedRange().location)}))
    #expect(parts==["dbo","Orders"])
    parts=[];editor.revealInExplorer=nil
    #expect(!StudioCommandCatalog.dispatch(event("g"),to:editor,menu:{editor.makeSQLMenu(at:20)}) && parts.isEmpty)
    let menu=editor.makeSQLMenu(at:20)
    #expect(menu is StudioMenu && menu.items.filter {!$0.isSeparatorItem}.allSatisfy {$0.image != nil})
  }
  @Test func editorSelectionPreservesSyntaxInkAndSourceAcrossThemes() throws {
    _=NSApplication.shared
    let old=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(old ?? "light")}
    let doc=QueryDocument(server:ConnectedServer(profile:.init(),password:""),database:"master",title:"Selection")
    doc.server.online=false;doc.sql="SELECT SUM(Amount), N'İstanbul' -- comment"
    let editor=EditorController(document:doc)
    for theme in ["light","dark"] {
      StudioTheme.apply(theme);editor.applyTheme();editor.editor.setSelectedRange(NSRange(location:0,length:doc.sql.utf16.count))
      let selected=editor.editor.selectedTextAttributes
      #expect(selected[.foregroundColor]==nil && selected[.backgroundColor] as? NSColor == StudioTheme.editorSelection)
      #expect(editor.editor.backgroundColor==StudioTheme.editorCanvas && editor.editor.string==doc.sql)
      let storage=try #require(editor.editor.textContentStorage?.textStorage)
      #expect(storage.attribute(.foregroundColor,at:7,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.function))
    }
  }
  @Test func primaryButtonDrawsExplicitContrastingFillAndLabelInBothThemes() throws {
    _=NSApplication.shared
    let old=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(old ?? "light")}
    let button=StudioPrimaryActionButton(title:"Uygula",target:nil,action:nil);button.frame=NSRect(x:0,y:0,width:100,height:34);button.font = .systemFont(ofSize:12,weight:.medium);button.refreshStyle()
    for theme in ["light","dark"] {
      StudioTheme.apply(theme);button.needsDisplay=true
      let image=try #require(button.bitmapImageRepForCachingDisplay(in:button.bounds));button.cacheDisplay(in:button.bounds,to:image)
      let corner=try #require(image.colorAt(x:10,y:10)?.usingColorSpace(.sRGB)),accent=try #require(StudioTheme.accent.usingColorSpace(.sRGB))
      #expect(abs(corner.blueComponent-accent.blueComponent)<0.03 && abs(corner.redComponent-accent.redComponent)<0.03)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql127-primary-"+theme+".png"))
    }
  }
  @Test func hoverPlacementStaysInsideScreenAndFlipsAboveBottomEdge() {
    let screen=NSRect(x:100,y:100,width:800,height:600),size=NSSize(width:380,height:120)
    for anchor in [NSRect(x:100,y:105,width:20,height:20),NSRect(x:885,y:690,width:20,height:20)] {
      let rect=StudioHoverHelp.placement(anchor:anchor,size:size,screen:screen)
      #expect(screen.insetBy(dx:8,dy:8).contains(rect))
      if anchor.minY<200 {#expect(rect.minY>=anchor.maxY)} else {#expect(rect.maxY<anchor.minY)}
    }
  }
  @Test func connectionsFirstLayoutFitsNativeWindowAndToolbarTracksExplorerBoundary() async throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:1200,height:800));window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
    defer {host.sheet?.close();window.close()}
    let toolbar=NSToolbar(identifier:"127-layout");toolbar.delegate=host;window.toolbar=toolbar
    let ids=host.toolbarDefaultItemIdentifiers(toolbar).map(\.rawValue)
    #expect(!ids.contains("connect"))
    let boundary=try #require(ids.firstIndex(of:"explorerBoundary"))
    #expect(ids[boundary+1]=="run" && ids[boundary+2]=="cancel")
    #expect(host.toolbar(toolbar,itemForItemIdentifier:.init("explorerBoundary"),willBeInsertedIntoToolbar:true) is NSTrackingSeparatorToolbarItem)
    host.showConnect()
    let panel=try #require(host.sheet),root=try #require(panel.contentView)
    try await Task.sleep(for:.milliseconds(100));root.layoutSubtreeIfNeeded()
    #expect(root.bounds.width>=1020 && root.bounds.height>=620)
    func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
    for control in views(root).compactMap({$0 as? NSControl}) where !control.isHiddenOrHasHiddenAncestor {
      let rect=root.convert(control.bounds,from:control)
      #expect(rect.minX>=0 && rect.maxX<=root.bounds.maxX+1)
    }
    let image=try #require(root.bitmapImageRepForCachingDisplay(in:root.bounds));root.cacheDisplay(in:root.bounds,to:image)
    try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql127-connections-first.png"))
  }

  @Test func acceptingBuiltInCompletionKeepsCaretInsideAndOneUndoRestoresSQL() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Builtin completion");doc.sql="SELECT SUM"
    let controller=EditorController(document:doc),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.orderFront(nil);window.makeFirstResponder(editor)
    defer {editor.dismissSuggestions?();window.close()}
    editor.setSelectedRange(NSRange(location:doc.sql.utf16.count,length:0));editor.undoManager?.removeAllActions()
    controller.scheduleIntelligence(manual:true)
    let deadline=ContinuousClock.now.advanced(by:.seconds(3))
    while !controller.completionShown,ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(10))}
    #expect(controller.completionShown)
    let tab=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48))
    let undo=try #require(editor.undoManager);undo.beginUndoGrouping();editor.keyDown(with:tab);undo.endUndoGrouping()
    #expect(editor.string=="SELECT SUM()" && editor.selectedRange()==NSRange(location:11,length:0))
    undo.undo();#expect(editor.string=="SELECT SUM" && !undo.canUndo && doc.lastExecutedSQL==nil)
  }

  @Test func newGlobalTabCommandsNeverCloseBackgroundDocumentsFromAuxiliaryWindow() throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let host=WorkbenchController(state:state),main=NSWindow(contentViewController:host),panel=NSWindow()
    main.isReleasedWhenClosed=false;panel.isReleasedWhenClosed=false
    defer {main.close();panel.close()}
    _=state.newQuery(server:server,database:"master",text:"SELECT 1")
    _=state.newQuery(server:server,database:"master",text:"SELECT 2")
    host.focusedWindowProvider={panel}
    for action in [#selector(WorkbenchController.closeAllTabs),#selector(WorkbenchController.closeOtherTabs),#selector(WorkbenchController.closeLeftTabs),#selector(WorkbenchController.closeRightTabs),#selector(WorkbenchController.pinActiveTab)] {
      #expect(!host.validateUserInterfaceItem(NSMenuItem(title:"Tab",action:action,keyEquivalent:"")))
      #expect(NSApp.sendAction(action,to:host,from:nil))
    }
    #expect(state.documents.count==2 && state.documents.allSatisfy {!$0.pinned})
  }

  @Test func searchablePickerAccessibilityUsesSamePopupAndRejectsStaleContext() throws {
    _=NSApplication.shared
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:400,height:300),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;defer {window.close()}
    let root=NSView(frame:NSRect(x:0,y:0,width:400,height:300));window.contentView=root
    let button=StudioSearchablePopUpButton(frame:NSRect(x:20,y:150,width:170,height:26),pullsDown:false)
    button.addItems(withTitles:["Demo","Archive"]);button.selectItem(withTitle:"Demo");root.addSubview(button);window.orderFront(nil)
    #expect(button.accessibilityPerformPress())
    let choices=try #require(button.choices)
    #expect(choices.search.window != nil && choices.table.frame.width>=240)
    choices.filter("archive");#expect(button.titleOfSelectedItem=="Demo")
    button.contextID=UUID()
    #expect(choices.search.window?.isVisible != true)
    choices.commit();#expect(button.titleOfSelectedItem=="Demo")
    button.isEnabled=false
    #expect(!button.accessibilityPerformPress())
  }
  @Test func shortcutCaptureSupportsNativePressAndStopsWhenDetached() async throws {
    _=NSApplication.shared
    let model=DefinitionIndexStorageModel(disk:CatalogDiskIndex(url:URL(fileURLWithPath:"/tmp/shortcut127-"+UUID().uuidString+"/index.sqlite")))
    let host=NSHostingController(rootView:SettingsPanel(state:StudioState(),initialTab:.shortcuts,definitionStorage:model));host.sizingOptions=[]
    let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:960,height:720));window.orderFront(nil)
    defer {window.contentView=nil;window.close()}
    try await Task.sleep(for:.milliseconds(80));host.view.layoutSubtreeIfNeeded()
    func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
    let button=try #require(views(host.view).compactMap {$0 as? NSButton}.first {$0.accessibilityLabel()=="Sorgu sekmesini sabitle / kaldır kısayolunu değiştir"})
    #expect(button.accessibilityPerformPress() && button.title.hasPrefix("Tuşlara basın"))
    #expect(window.firstResponder === button)
    window.contentView=nil
    #expect(button.title.contains("Değiştir"))
  }

}
