import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct TabPresentation137Tests {
  private func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
  @Test func pinningMovesTheActualDocumentAndDragKeepsPinnedPrefix() throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;defer {window.close()}
    host.focusedWindowProvider={window}
    let a=state.newQuery(server:server,database:"master",text:"SELECT 1")
    let b=state.newQuery(server:server,database:"master",text:"SELECT 2")
    let c=state.newQuery(server:server,database:"master",text:"SELECT 3")
    host.pinActiveTab()
    #expect(state.documents.map(\.id)==[c.id,a.id,b.id] && c.pinned && state.active === c)
    state.active=b;host.pinActiveTab()
    #expect(state.documents.map(\.id)==[b.id,c.id,a.id])
    host.moveQueryTab(a.id,to:0)
    #expect(state.documents.map(\.id)==[b.id,c.id,a.id])
    host.pinActiveTab()
    #expect(state.documents.map(\.id)==[c.id,b.id,a.id] && !b.pinned && c.pinned)
    let strip=try #require(descendants(host.view).compactMap {$0 as? QueryTabStrip}.first)
    let scroll=try #require(strip.enclosingScrollView)
    #expect(scroll.scrollerStyle == .overlay && scroll.horizontalScroller?.controlSize == .small)
    for name in [NSWindow.didEnterFullScreenNotification,NSWindow.didExitFullScreenNotification] {
      NotificationCenter.default.post(name:name,object:window)
      #expect(strip.documentIDs==state.documents.map(\.id))
      #expect(descendants(strip).compactMap {$0 as? QueryTabSurface}.allSatisfy {($0.layer?.backgroundColor?.alpha ?? 0)>0})
    }
    #expect(a.sql=="SELECT 1" && b.sql=="SELECT 2" && c.sql=="SELECT 3")
  }
  @Test func tabColorsAndLabelsSurviveWindowReattachmentAndAppearanceRefresh() throws {
    _=NSApplication.shared
    let old=StudioTheme.mode;defer {StudioTheme.apply(old)}
    let button=DocumentButton(title:"Visible query",target:nil,action:nil)
    button.font=StudioTheme.uiFont
    let tab=QueryTabSurface(views:[button]);tab.primaryButton=button
    let first=NSWindow(),second=NSWindow()
    first.isReleasedWhenClosed=false;second.isReleasedWhenClosed=false
    defer {first.close();second.close()}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      for active in [true,false] {
        tab.configure(active:active)
        first.contentView=tab;second.contentView=tab
        StudioTheme.decorate(tab);tab.viewDidChangeEffectiveAppearance()
        let color=try #require(button.attributedTitle.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor)
        #expect(color == (active ? StudioTheme.text:StudioTheme.muted))
        #expect((tab.layer?.backgroundColor?.alpha ?? 0) > 0 && tab.isActiveTab==active)
        #expect(button.title=="Visible query")
      }
    }
  }
}
