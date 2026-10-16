import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ProfilerLauncherTests {
  private func fixture()->(StudioState,ConnectedServer,WorkbenchController,NSWindow) {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    server.catalogFixture={_ in Execution()};state.servers=[server]
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
    host.loadViewIfNeeded();return (state,server,host,window)
  }
  private func wait(_ condition:()->Bool) async throws {
    for _ in 0..<300 where !condition() {try await Task.sleep(for:.milliseconds(3))}
    #expect(condition())
  }
  @Test func openingWaitsForOneReconnectAndDoesNotStartCapture() async throws {
    let (state,server,host,window)=fixture();defer {host.profilerWindows.values.forEach {$0.window?.close()};window.close()}
    var calls=0,continuation:CheckedContinuation<Void,Never>?
    server.reconnectFixture={calls+=1;await withCheckedContinuation {continuation=$0}}
    host.profiler();host.profiler()
    try await wait {continuation != nil}
    #expect(calls==1 && host.profilerWindows.isEmpty && state.documents.isEmpty)
    continuation?.resume();continuation=nil
    try await wait {!host.profilerLauncher.opening}
    let owner=try #require(host.profilerWindows[server.id])
    #expect(server.online && !owner.model.hasSession && !owner.model.running)
  }
  @Test func failureKeepsProfilerClosedAndShowsConnectionReason() async throws {
    let (state,server,host,window)=fixture();defer {window.close()}
    var message="";state.errorFixture={message=$0}
    server.reconnectFixture={throw SQLFailure("fixture connection refused")}
    host.profiler();try await wait {!host.profilerLauncher.opening}
    #expect(host.profilerWindows.isEmpty && message.contains("fixture connection refused") && !server.online)
  }
  @Test func ownedWindowIndicatorsFollowOpenCloseAndBackgroundProfiler() async throws {
    let (_,server,host,window)=fixture();defer {window.close()}
    let toolbar=NSToolbar(identifier:"tool-window-test");toolbar.delegate=host;window.toolbar=toolbar
    func button(_ id:String)throws->StudioToolbarButton {
      try #require(toolbar.items.first {$0.itemIdentifier.rawValue==id}?.view as? StudioToolbarButton)
    }
    for (id,identity) in [("activity","activity|fixture"),("history","studio.timeline"),("favorites","favorite-picker|fixture")] {
      let control=try button(id);#expect(control.state == .off)
      let panel=host.present(Text("Fixture"),title:"Fixture",identity:identity)
      #expect(host.toolWindowIsOpen(id) && control.state == .on && control.tone == .success)
      panel.close();try await wait {!host.toolWindowIsOpen(id)}
      #expect(control.state == .off && control.tone == .neutral)
    }
    host.presentProfiler(server)
    let profiler=try #require(host.profilerWindows[server.id]),control=try button("profiler")
    #expect(control.state == .on)
    profiler.window?.orderOut(nil);#expect(control.state == .on)
    profiler.window?.close();#expect(control.state == .off && !host.toolWindowIsOpen("profiler"))
  }
}
