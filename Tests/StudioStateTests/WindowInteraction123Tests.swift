import AppKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct WindowInteraction123Tests {
  @Test func auxiliaryWindowRestoresMovedAndResizedFrameAfterRecreation() throws {
    _=NSApplication.shared
    let role="placement-test-\(UUID())"
    defer {NSWindow.removeFrame(usingName:StudioWindowPlacement.name(role))}
    func make()->StudioPanelWindow {
      let window=StudioPanelWindow(contentRect:NSRect(x:0,y:0,width:440,height:300),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.framePersistenceRole=role;window.minSize=NSSize(width:400,height:260)
      window.center();return window
    }
    let visible=try #require(NSScreen.main?.visibleFrame)
    let target=NSRect(x:visible.minX+40,y:visible.minY+40,width:min(700,visible.width-80),height:min(500,visible.height-80))
    let first=make();first.orderFront(nil);first.setFrame(target,display:false);first.close()
    let second=make();defer {second.close()};second.orderFront(nil)
    #expect(abs(second.frame.minX-target.minX)<1 && abs(second.frame.minY-target.minY)<1)
    #expect(abs(second.frame.width-target.width)<1 && abs(second.frame.height-target.height)<1)
    second.orderOut(nil);second.makeKeyAndOrderFront(nil)
    #expect(second.frame == target)
  }
  @Test func storedFramesRespectSecondaryScreensMinimumsAndDisconnectedDisplays() {
    let main=NSRect(x:0,y:0,width:1440,height:900),secondary=NSRect(x:-1920,y:0,width:1920,height:1080)
    let moved=NSRect(x:-1700,y:120,width:900,height:650)
    #expect(StudioWindowPlacement.fitted(moved,minimum:NSSize(width:500,height:400),screens:[main,secondary],preferred:main)==moved)
    let missing=NSRect(x:5000,y:4000,width:1600,height:1200)
    let fitted=StudioWindowPlacement.fitted(missing,minimum:NSSize(width:500,height:400),screens:[main],preferred:main)
    #expect(main.contains(fitted) && fitted.size==main.size)
    let small=StudioWindowPlacement.fitted(NSRect(x:100,y:100,width:100,height:80),minimum:NSSize(width:500,height:400),screens:[main],preferred:main)
    #expect(small.size==NSSize(width:500,height:400) && main.contains(small))
  }
  @Test func disclosureHeaderTracksEntireWidthAndLeavesContentControlsIndependent() throws {
    _=NSApplication.shared
    let button=StudioDisclosureButton(frame:NSRect(x:0,y:0,width:480,height:32))
    button.title="Sekmeler ve pencereler";button.symbol="square.stack";button.expanded=true
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:500,height:100),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView?.addSubview(button);defer {window.close()}
    var toggles=0;button.toggle={toggles+=1;button.expanded.toggle()}
    for x in [CGFloat(2),100,300,478] {
      let point=button.convert(NSPoint(x:x,y:16),to:nil)
      let event=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1))
      #expect(button.cell?.hitTest(for:event,in:button.bounds,of:button).contains(.trackableArea)==true)
      #expect(button.hitTest(NSPoint(x:x,y:16)) === button)
      #expect(NSApp.sendAction(try #require(button.action),to:button.target,from:button))
    }
    #expect(toggles==4 && button.expanded)
    button.isEnabled=false
    let event=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:button.convert(NSPoint(x:300,y:16),to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1))
    #expect(button.cell?.hitTest(for:event,in:button.bounds,of:button).isEmpty==true)
  }
  @Test func auxiliaryWindowsRemainIndependentAndDiscoverableAfterBackgroundOrdering() throws {
    _=NSApplication.shared
    let main=NSWindow(contentRect:NSRect(x:-20000,y:0,width:600,height:400),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    let panel=StudioPanelWindow(contentRect:NSRect(x:-20000,y:0,width:400,height:250),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    main.isReleasedWhenClosed=false;panel.isReleasedWhenClosed=false
    panel.title="Window fixture 123"
    let oldMenu=NSApp.windowsMenu,menu=NSMenu(title:"Window fixture")
    NSApp.windowsMenu=menu
    defer {panel.close();main.close();NSApp.windowsMenu=oldMenu}
    panel.associate(with:main);panel.orderFront(nil);main.orderFront(nil)
    #expect(panel.associatedOwner === main && panel.parent==nil && panel.level == .normal)
    #expect(panel.collectionBehavior.contains(.managed) && panel.collectionBehavior.contains(.participatesInCycle))
    #expect(!panel.collectionBehavior.contains(.transient) && !panel.isExcludedFromWindowsMenu)
    #expect(menu.items.contains {$0.title==panel.title})
    panel.makeKeyAndOrderFront(nil)
    #expect(panel.isVisible && panel.parent==nil && panel.associatedOwner === main)
    panel.close()
    #expect(panel.associatedOwner==nil && !menu.items.contains {$0.title==panel.title})
  }
  @Test func terminationFlushIsSingleFlightAndApprovalIsConsumedOnce() async throws {
    let coordinator=ApplicationTermination()
    var pending:CheckedContinuation<Bool,Never>?,flushes=0,exits=0,cancels=0
    let flush:() async -> Bool={flushes+=1;return await withCheckedContinuation {pending=$0}}
    let quit:()->Void={exits+=1;#expect(coordinator.consumeApproval());#expect(!coordinator.consumeApproval())}
    coordinator.prepare(flush:flush,discardHistory:{Issue.record("Unexpected history failure");return false},mayTerminate:{true},terminate:quit,cancelled:{cancels+=1})
    coordinator.prepare(flush:flush,discardHistory:{false},mayTerminate:{true},terminate:quit,cancelled:{cancels+=1})
    for _ in 0..<100 where pending==nil {try await Task.sleep(for:.milliseconds(2))}
    #expect(coordinator.preparing && flushes==1 && exits==0)
    pending?.resume(returning:true)
    for _ in 0..<100 where coordinator.preparing {try await Task.sleep(for:.milliseconds(2))}
    #expect(exits==1 && cancels==0 && !coordinator.consumeApproval())
  }
  @Test func terminationPreservesHistoryFailureAndLateBusyVeto() async throws {
    for (saved,discard,canQuit,expected) in [(false,false,true,false),(false,true,true,true),(true,false,false,false)] {
      let coordinator=ApplicationTermination();var exits=0,cancels=0,prompts=0
      coordinator.prepare(flush:{saved},discardHistory:{prompts+=1;return discard},mayTerminate:{canQuit},terminate:{exits+=1;#expect(coordinator.consumeApproval())},cancelled:{cancels+=1})
      for _ in 0..<100 where coordinator.preparing {try await Task.sleep(for:.milliseconds(2))}
      #expect(exits==(expected ? 1:0) && cancels==(expected ? 0:1) && prompts==(saved ? 0:1))
      #expect(!coordinator.consumeApproval())
    }
  }
}
