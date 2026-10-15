import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct TabPresentation137Tests {
  @Test func horizontalTabViewportSurvivesResizeAndFullscreenNotifications() async throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    state.documents=(0..<18).map {QueryDocument(server:server,database:"master",title:"Query \($0) — long document title")}
    state.active=state.documents.last
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
    defer {window.close()}
    let strip=try #require(descendants(host.view).compactMap {$0 as? QueryTabStrip}.first)
    let scroll=try #require(strip.enclosingScrollView as? QueryTabScrollView)
    for width in [1060,2400,1200,3000,1060] {
      window.setContentSize(NSSize(width:width,height:800));host.view.layoutSubtreeIfNeeded()
      // Simulate the stale clip origin of a document reparented during a Space change.
      scroll.contentView.setBoundsOrigin(NSPoint(x:50000,y:90))
      NotificationCenter.default.post(name:NSWindow.didEnterFullScreenNotification,object:window)
      NotificationCenter.default.post(name:NSWindow.didExitFullScreenNotification,object:window)
      host.view.layoutSubtreeIfNeeded();scroll.layoutSubtreeIfNeeded()
      #expect(scroll.contentView.bounds.minY==0)
      #expect(scroll.contentView.bounds.maxX<=strip.frame.width+1)
      #expect(strip.frame.height>=34 && strip.frame.width>=scroll.contentView.bounds.width)
      let active=try #require(strip.arrangedSubviews.compactMap {$0 as? QueryTabSurface}.first {$0.isActiveTab})
      #expect(active.frame.intersects(scroll.contentView.bounds) && active.superview === strip)
      #expect(strip.arrangedSubviews.count==19 && strip.documentIDs==state.documents.map(\.id))
      #expect(strip.arrangedSubviews.last?.superview === strip)
    }
  }
  @Test func semanticTabColorsRemainReadableAcrossContrastAndWindowFocus() async throws {
    _=NSApplication.shared
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:600,height:100),styleMask:[.titled],backing:.buffered,defer:false)
    let other=NSWindow(contentRect:NSRect(x:-21000,y:0,width:200,height:100),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;other.isReleasedWhenClosed=false
    defer {window.close();other.close()}
    let title=DocumentButton(title:"Visible query",target:nil,action:nil)
    let close=QueryTabCloseButton(image:NSImage(systemSymbolName:"xmark",accessibilityDescription:"Kapat")!,target:nil,action:nil)
    let tab=QueryTabSurface(views:[title,close]);tab.primaryButton=title
    window.contentView=tab;window.orderFront(nil)
    for name in [NSAppearance.Name.aqua,.darkAqua,.accessibilityHighContrastAqua,.accessibilityHighContrastDarkAqua] {
      window.appearance=try #require(NSAppearance(named:name))
      for focused in [true,false] {
        if focused {window.makeKeyAndOrderFront(nil)} else {other.makeKeyAndOrderFront(nil)}
        for active in [true,false] {
          tab.configure(active:active);close.refreshStyle();tab.layoutSubtreeIfNeeded()
          let background=NSColor(cgColor:try #require(tab.layer?.backgroundColor))!
          var foreground:NSColor = .clear
          tab.effectiveAppearance.performAsCurrentDrawingAppearance {foreground=NSColor.labelColor.usingColorSpace(.sRGB)!}
          #expect(contrast(foreground,background)>=4.5)
          #expect(background.alphaComponent==1 && tab.alphaValue==1 && !tab.isHidden)
          #expect(tab.layer?.borderWidth == (active ? 1:0))
          #expect(close.contentTintColor == NSColor.labelColor)
          #expect(title.title=="Visible query" && title.frame.width>0 && close.frame.width>0)
        }
      }
    }
  }
  private func contrast(_ a:NSColor,_ b:NSColor)->Double {
    func luminance(_ color:NSColor)->Double {
      let c=color.usingColorSpace(.sRGB)!
      func linear(_ v:CGFloat)->Double {let d=Double(v);return d<=0.04045 ? d/12.92:pow((d+0.055)/1.055,2.4)}
      return 0.2126*linear(c.redComponent)+0.7152*linear(c.greenComponent)+0.0722*linear(c.blueComponent)
    }
    let x=luminance(a),y=luminance(b)
    return (max(x,y)+0.05)/(min(x,y)+0.05)
  }
  @Test func repeatedTabSwitchingKeepsTitleWidthsAndNeverOverlaysAScroller() async throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    state.documents=(0..<15).map {QueryDocument(server:server,database:"master",title:"ALTER · NTS_WM_SEVKIYAT_DURUMU_DEGISTIR_\($0)")}
    state.active=state.documents.first
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.setContentSize(NSSize(width:1060,height:800));window.orderFront(nil)
    defer {window.close()}
    host.focusedWindowProvider={window}
    let strip=try #require(descendants(host.view).compactMap {$0 as? QueryTabStrip}.first)
    let scroll=try #require(strip.enclosingScrollView as? QueryTabScrollView)
    var expected:[UUID:CGFloat]=[:]
    for turn in 0..<30 {
      host.view.layoutSubtreeIfNeeded();scroll.layoutSubtreeIfNeeded()
      let surfaces=strip.arrangedSubviews.compactMap {$0 as? QueryTabSurface}
      #expect(surfaces.count==15 && !scroll.hasHorizontalScroller)
      for surface in surfaces {
        let button=try #require(surface.primaryButton),doc=try #require(button.document)
        let width=ceil((button.title as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.medium)]).width)+12
        #expect(button.frame.width>=width-1)
        if let previous=expected[doc.id] {#expect(abs(surface.frame.width-previous)<1)}
        expected[doc.id]=surface.frame.width
        #expect(surface.frame.height>=24 && surface.superview === strip)
      }
      let target=try #require((turn.isMultiple(of:2) ? surfaces.last:surfaces.first)?.primaryButton)
      #expect(NSApp.sendAction(try #require(target.action),to:target.target,from:target))
    }
    #expect(state.documents.count==15 && state.documents.allSatisfy {$0.sql.isEmpty})
    host.closeAllWithoutSaving()
    #expect(state.documents.isEmpty)
  }
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
    #expect(!scroll.hasHorizontalScroller && scroll.scrollerStyle == .overlay)
    for name in [NSWindow.didEnterFullScreenNotification,NSWindow.didExitFullScreenNotification] {
      NotificationCenter.default.post(name:name,object:window)
      #expect(strip.documentIDs==state.documents.map(\.id))
      #expect(descendants(strip).compactMap {$0 as? QueryTabSurface}.allSatisfy {($0.layer?.backgroundColor?.alpha ?? 0)>0})
    }
    #expect(a.sql=="SELECT 1" && b.sql=="SELECT 2" && c.sql=="SELECT 3")
  }
  @Test func tabColorsAndLabelsSurviveWindowReattachmentAndAppearanceRefresh() async throws {
    _=NSApplication.shared
    let old=StudioTheme.mode;defer {StudioTheme.apply(old)}
    let button=DocumentButton(title:"Visible query",target:nil,action:nil)
    button.font=StudioTheme.uiFont
    let tab=QueryTabSurface(views:[button]);tab.primaryButton=button
    let first=NSWindow(),second=NSWindow()
    first.isReleasedWhenClosed=false;second.isReleasedWhenClosed=false
    defer {first.contentView=nil;second.contentView=nil;first.close();second.close()}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      for active in [true,false] {
        tab.configure(active:active)
        second.contentView=nil
        first.contentView=tab
        first.contentView=nil
        second.contentView=tab
        StudioTheme.decorate(tab);tab.viewDidChangeEffectiveAppearance()
        let color=try #require(button.attributedTitle.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor)
        #expect(color == NSColor.labelColor)
        #expect((tab.layer?.backgroundColor?.alpha ?? 0) > 0 && tab.isActiveTab==active)
        #expect(button.title=="Visible query")
      }
    }
  }
}
