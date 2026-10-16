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
    owner.loadViewIfNeeded()
    return (state,owner,window)
  }
  private func event(_ window:NSWindow,key:UInt16,flags:NSEvent.ModifierFlags = .option,type:NSEvent.EventType = .keyDown)->NSEvent {
    NSEvent.keyEvent(with:type,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:key==48 ? "\t":"",charactersIgnoringModifiers:key==48 ? (flags.contains(.shift) ? "\u{19}":"\t"):"",isARepeat:false,keyCode:key)!
  }
  @Test func optionTabPreviewsWithoutChangingEditorAndReleaseCommits() throws {
    let (state,owner,window)=fixture();defer {owner.tabSwitcher.dismiss(commit:false);window.close()}
    let original=try #require(state.active),switcher=owner.tabSwitcher
    #expect(switcher.handle(event(window,key:48)))
    #expect(switcher.index==1 && state.active===original && switcher.panel != nil)
    #expect(switcher.handle(event(window,key:124)))
    #expect(switcher.index==2 && state.active===original)
    #expect(switcher.handle(event(window,key:123)))
    #expect(switcher.index==1)
    _=switcher.handle(event(window,key:58,flags:[],type:.flagsChanged))
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
  @Test func manyTabsHoverAndStripHighlightPreserveTheOriginalDocument() throws {
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
    switcher.preview(state.documents[39].id)
    #expect(switcher.index==39 && !surface.isSwitchPreview && state.active===original)
    _=switcher.handle(event(window,key:125))
    #expect(switcher.index==42)
    switcher.dismiss(commit:false)
    #expect(state.active===original && scroll.contentView.bounds.origin==origin)
    #expect(owner.tabs.arrangedSubviews.compactMap {$0 as? QueryTabSurface}.allSatisfy {!$0.isSwitchPreview})
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
      let image=try #require(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-tab-switcher-"+theme+".png"))
    }
  }
}
