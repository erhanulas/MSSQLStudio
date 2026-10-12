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
