import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct QueryStatusPresentationTests {
  @Test func statusIconsAndOnlyPhaseTextUseSemanticColorsInBothThemes() throws {
    _=NSApplication.shared
    let previous=StudioTheme.mode;defer {StudioTheme.apply(previous)}
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"Demo",title:"Status");doc.state = .ready
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false;state.servers=[server];state.documents=[doc];state.active=doc
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:1060,height:680));window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil);defer {window.close()}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      for (phase,color) in [(QueryDocument.State.ready,StudioTheme.success),(.running,StudioTheme.accent),(.connecting,StudioTheme.accent),(.cancelling,StudioTheme.warning),(.disconnected,StudioTheme.muted)] {
        doc.state=phase;host.updateControls();host.view.layoutSubtreeIfNeeded()
        #expect(host.statusIcon.image != nil && host.statusIcon.contentTintColor==color)
        #expect(host.status.attributedStringValue.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor==color)
        let detail=(host.status.stringValue as NSString).range(of:"Demo")
        #expect(detail.location != NSNotFound)
        #expect(host.status.attributedStringValue.attribute(.foregroundColor,at:detail.location,effectiveRange:nil) as? NSColor==StudioTheme.muted)
        #expect(host.statusIcon.alignmentRect(forFrame:host.statusIcon.frame).size==NSSize(width:14,height:14))
        if phase == .ready,let bitmap=host.statusStrip.bitmapImageRepForCachingDisplay(in:host.statusStrip.bounds) {
          host.statusStrip.cacheDisplay(in:host.statusStrip.bounds,to:bitmap)
          try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-query-status-"+theme+".png"))
        }
      }
      doc.state = .ready;doc.executionFailed=true;host.updateControls()
      #expect(host.status.stringValue.hasPrefix("Hata") && host.statusIcon.contentTintColor==StudioTheme.danger)
      doc.executionFailed=false;doc.partial=true;host.updateControls()
      #expect(host.status.stringValue.hasPrefix("Ready") && host.statusIcon.contentTintColor==StudioTheme.success)
      #expect(!host.status.stringValue.contains("PARTIAL"))
      doc.transactionCount=1;host.updateControls()
      #expect(host.statusIcon.contentTintColor==StudioTheme.warning)
      doc.transactionCount=0;doc.partial=false
    }
  }
  @Test func detachedWindowUsesTheSameStatusAppearance() throws {
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"Demo",title:"Detached");doc.state = .ready
    let owner=DetachedQueryWindow(query:QueryController(document:doc));defer {owner.close()}
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let views=descendants(try #require(owner.window?.contentView))
    let icon=try #require(views.compactMap {$0 as? NSImageView}.first {$0.accessibilityIdentifier()=="queryStatusIcon"})
    let label=try #require(views.compactMap {$0 as? NSTextField}.first {$0.accessibilityIdentifier()=="queryStatus"})
    owner.updateStatus()
    #expect(icon.image != nil && icon.contentTintColor==StudioTheme.success && label.stringValue.hasPrefix("Ready"))
    doc.state = .running;owner.updateStatus()
    #expect(icon.contentTintColor==StudioTheme.accent && label.stringValue.hasPrefix("Executing"))
    doc.state = .ready;doc.partial=true;owner.updateStatus()
    #expect(icon.contentTintColor==StudioTheme.success && label.stringValue.hasPrefix("Ready"))
  }
}
