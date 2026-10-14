import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ProjectDesignTests {
  private func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
  private func inScrollView(_ view:NSView)->Bool {
    var parent=view.superview
    while let current=parent {
      if current is NSScrollView {return true}
      parent=current.superview
    }
    return false
  }
  @Test(arguments:StudioDesignFixture.Screen.allCases)
  func screenFitsMinimumAndWideInBothThemes(_ screen:StudioDesignFixture.Screen) async throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light");if previous == nil {UserDefaults.standard.removeObject(forKey:"ssmsTheme")}}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let root=try await StudioDesignFixture.make(screen)
      let host=NSHostingController(rootView:root);host.sizingOptions=[]
      let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
      window.setFrameOrigin(NSPoint(x:-4000,y:0));window.orderFront(nil)
      defer {window.close()}
      for wide in [false,true] {
        let size=wide ? NSSize(width:max(1100,screen.size.width+240),height:max(760,screen.size.height+140)):screen.size
        window.setContentSize(size);host.view.frame=NSRect(origin:.zero,size:size)
        try await Task.sleep(for:.milliseconds(wide ? 70:250));host.view.layoutSubtreeIfNeeded()
        #expect(abs(host.view.bounds.width-size.width)<1 && abs(host.view.bounds.height-size.height)<1)
        for control in views(host.view).compactMap({$0 as? NSControl}) where !control.isHiddenOrHasHiddenAncestor && !inScrollView(control) && control.bounds.width>1 && control.bounds.height>1 {
          let frame=host.view.convert(control.bounds,from:control)
          #expect(frame.minX >= -2 && frame.maxX <= size.width+2 && frame.minY >= -2 && frame.maxY <= size.height+2,"\(screen.rawValue) / \(theme) / \(wide) control \(control.description) outside \(size): \(frame)")
        }
        let image=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
        host.view.cacheDisplay(in:host.view.bounds,to:image)
        let path="/tmp/mssql-project-design-\(screen.rawValue)-\(theme)-\(wide ? "wide":"minimum").png"
        try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path))
      }
    }
  }
  @Test func nativeUpdateLongFailureKeepsCloseReachableAndDetailsScrollable() throws {
    _=NSApplication.shared
    let controller=UpdateProgressController()
    let window=try #require(controller.window),body=try #require(window.contentView)
    defer {controller.close()}
    let message=String(repeating:"Sunucuya ulaşılamadı. HTTP 503 · Ayrıntı\n",count:60)
    controller.finish(message);body.layoutSubtreeIfNeeded()
    #expect(controller.done.isEnabled && controller.status.stringValue==message)
    let button=body.convert(controller.done.bounds,from:controller.done)
    #expect(body.bounds.contains(button))
    let scroll=try #require(controller.status.enclosingScrollView)
    #expect(scroll.documentView!.bounds.height > scroll.contentSize.height)
    #expect(abs(scroll.documentVisibleRect.minY)<1)
  }

  @Test func auxiliaryMinimumsReserveContentInsteadOfConsumingTitleBarSpace() {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let workbench=WorkbenchController(state:state);workbench.loadViewIfNeeded()
    let window=workbench.present(Text("Fixture"),title:"Synthetic panel",width:800,height:600,minWidth:620,minHeight:480)
    defer {window.close()}
    window.setFrame(NSRect(origin:window.frame.origin,size:window.minSize),display:false)
    #expect(window.contentLayoutRect.width>=620 && window.contentLayoutRect.height>=480)
  }

  @Test func feedbackEscapeClosesOnlyThePopoverAndKeepsTheFormOpen() async throws {
    _=NSApplication.shared
    let controller=NSHostingController(rootView:StudioFeedback(message:String(repeating:"Synthetic error. ",count:100)).padding())
    controller.sizingOptions=[]
    let window=StudioPanelWindow(contentViewController:controller);window.isReleasedWhenClosed=false
    window.setContentSize(NSSize(width:620,height:200));window.setFrameOrigin(NSPoint(x:200,y:200));window.makeKeyAndOrderFront(nil)
    defer {window.close()}
    try await Task.sleep(for:.milliseconds(80));controller.view.layoutSubtreeIfNeeded()
    let button=try #require(views(controller.view).compactMap {$0 as? StudioFeedbackButton}.first)
    for routedToOwner in [false,true] {
      button.performClick(nil)
      #expect(button.popup.isShown)
      let popup=try #require(button.popup.contentViewController?.view.window)
      #expect(popup !== window && popup.firstResponder === button.popup.contentViewController)
      let recipient=routedToOwner ? window:popup
      let escape=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:recipient.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53))
      recipient.sendEvent(escape)
      for _ in 0..<30 where popup.isVisible {try await Task.sleep(for:.milliseconds(10))}
      #expect(!button.popup.isShown && window.isVisible)
    }
  }

  @Test func nativeDialogsAndPlanKeepActionsInBoundsInBothThemes() async throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light");if previous == nil {UserDefaults.standard.removeObject(forKey:"ssmsTheme")}}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let name=StudioNameWindowController(title:"Yeni klasör",value:"Synthetic",save:{_ in})
      let close=StudioCloseWindowController(title:"Sekmeleri kapat",count:3,decision:{_ in true})
      let notice=StudioNoticeWindowController(message:String(repeating:"Sentetik sunucu hatası.\n",count:60))
      let update=UpdateProgressController();update.finish(String(repeating:"HTTP 503 · Sentetik hata ayrıntısı\n",count:60))
      let plan=PlanController(plan:try ExecutionPlan.parse("<ShowPlanXML><RelOp NodeId='0' PhysicalOp='Select' LogicalOp='Select' EstimateRows='1000' EstimatedTotalSubtreeCost='0.25'/></ShowPlanXML>"))
      let planWindow=NSWindow(contentViewController:plan);planWindow.isReleasedWhenClosed=false;planWindow.setContentSize(NSSize(width:620,height:480))
      let controllers:[(String,NSWindowController)]=[("name",name),("close",close),("notice",notice),("update",update),("plan",NSWindowController(window:planWindow))]
      for (label,controller) in controllers {
        let window=try #require(controller.window),body=try #require(window.contentView)
        window.setFrameOrigin(NSPoint(x:-4000,y:0));window.orderFront(nil)
        defer {controller.close()}
        try await Task.sleep(for:.milliseconds(60));body.layoutSubtreeIfNeeded()
        for button in views(body).compactMap({$0 as? NSButton}) where !button.isHiddenOrHasHiddenAncestor {
          #expect(body.bounds.insetBy(dx:-1,dy:-1).contains(body.convert(button.bounds,from:button)),"\(label) action clipped")
        }
        let image=try #require(body.bitmapImageRepForCachingDisplay(in:body.bounds));body.cacheDisplay(in:body.bounds,to:image)
        try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-native-\(label)-\(theme).png"))
      }
    }
  }
}
