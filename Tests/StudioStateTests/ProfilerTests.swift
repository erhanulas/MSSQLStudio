import AppKit
import SQLServerKit
import Testing
import SwiftUI
@testable import MSSQLStudio

private actor ProfilerProbe {
  var calls:[String]=[]
  var failDrop=false
  var held:CheckedContinuation<Void,Never>?
  var holdRead=false
  func setFailDrop(_ value:Bool) {failDrop=value}
  func setHoldRead() {holdRead=true}
  func release() {held?.resume();held=nil;holdRead=false}
  func count()->Int {calls.count}
  func readIsHeld()->Bool {held != nil}
  func execute(_ sql:String) async throws -> Execution {
    calls.append(sql)
    if sql.contains("DROP EVENT SESSION"),failDrop {throw SQLFailure("cleanup denied")}
    if sql.contains("SELECT t.target_data") {
      if holdRead {await withCheckedContinuation {held=$0}}
      var result=Execution();result.results=[Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[["<RingBufferTarget totalEventsProcessed=\"0\" droppedCount=\"0\"/>","0"]])];return result
    }
    return Execution()
  }
  func statements()->[String] {calls}
}
@MainActor @Suite(.serialized) struct ProfilerTests {
  private func server()->ConnectedServer {let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false;return server}
  @Test func openingAndEscapeDoNotConnectAndHiddenWindowContinuesCapture() async throws {
    _=NSApplication.shared
    let server=server(),probe=ProfilerProbe()
    let model=ProfilerModel(server:server,executor:{try await probe.execute($0)},disconnect:{},interval:.milliseconds(15))
    let owner=ProfilerWindowController(server:server,model:model)
    let window=try #require(owner.window)
    window.setFrameOrigin(NSPoint(x:-20000,y:0));owner.showWindow(nil)
    defer {window.close()}
    window.cancelOperation(nil)
    #expect(window.isVisible && !model.hasSession);#expect(await probe.count()==0)
    let name=SQLProfiler.sessionName(UUID()),sql=try model.preview(name:name)
    await model.start(name:name,confirmedSQL:sql)
    window.orderOut(nil)
    for _ in 0..<100 where model.lastRead==nil {try await Task.sleep(for:.milliseconds(5))}
    #expect(!window.isVisible && model.running && model.lastRead != nil)
    window.cancelOperation(nil);#expect(model.running)
    owner.showWindow(nil);#expect(window.isVisible && model.hasSession)
    #expect(await model.stop());#expect(!model.hasSession && !model.running)
    let statements=await probe.statements()
    #expect(statements.filter {$0.contains("CREATE EVENT SESSION")}.count==1)
    #expect(statements.last == (try SQLProfiler.dropSQL(name:name)))
  }
  @Test func stopWaitsForPhysicalReadAndFailedCleanupKeepsOwnershipForExplicitRetry() async throws {
    let server=server(),probe=ProfilerProbe()
    await probe.setHoldRead()
    let model=ProfilerModel(server:server,executor:{try await probe.execute($0)},disconnect:{},interval:.milliseconds(5))
    let name=SQLProfiler.sessionName(UUID()),sql=try model.preview(name:name)
    await model.start(name:name,confirmedSQL:sql)
    for _ in 0..<100 where !(await probe.readIsHeld()) {try await Task.sleep(for:.milliseconds(5))}
    #expect(await probe.readIsHeld())
    await probe.setFailDrop(true)
    let stopping=Task {await model.stop()}
    for _ in 0..<100 where !model.busy {try await Task.sleep(for:.milliseconds(2))}
    #expect(model.busy && model.hasSession)
    #expect(!(await probe.statements()).contains {$0.contains("DROP EVENT SESSION")})
    await probe.release()
    #expect(await stopping.value==false)
    #expect(model.hasSession && model.error.contains("cleanup denied") && model.lastRead==nil)
    await probe.setFailDrop(false)
    #expect(await model.stop());#expect(!model.hasSession)
  }
  @Test func toolbarReopensTheSameHiddenToolWithoutCreatingOrExecutingQueries() throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=server();state.servers=[server]
    let host=WorkbenchController(state:state)
    let main=NSWindow(contentViewController:host)
    main.isReleasedWhenClosed=false;defer {main.close()}
    host.loadViewIfNeeded()
    let ids=host.toolbarDefaultItemIdentifiers(NSToolbar(identifier:"fixture")).map(\.rawValue)
    #expect(ids.contains("profiler") && ids.firstIndex(of:"activity")!<ids.firstIndex(of:"profiler")!)
    host.profiler()
    let owner=try #require(host.profilerWindows[server.id]),window=try #require(owner.window)
    defer {window.close()}
    window.orderOut(nil);host.profiler()
    #expect(host.profilerWindows[server.id] === owner && window.isVisible)
    #expect(state.documents.isEmpty && !host.hasActiveProfilers)
    #expect(ShortcutCatalog.category(.profiler) == .application)
  }
  @Test func profilerFitsMinimumAndWideInBothThemes() async throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light")}
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let root=try await StudioDesignFixture.make(.profiler)
      let host=NSHostingController(rootView:root);host.sizingOptions=[]
      let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
      window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil);defer {window.close()}
      for size in [NSSize(width:960,height:640),NSSize(width:1380,height:900)] {
        window.setContentSize(size);host.view.frame=NSRect(origin:.zero,size:size)
        try await Task.sleep(for:.milliseconds(100));host.view.layoutSubtreeIfNeeded()
        for control in descendants(host.view).compactMap({$0 as? NSControl}) where !control.isHiddenOrHasHiddenAncestor && control.enclosingScrollView==nil && control.bounds.width>1 && control.bounds.height>1 {
          let rect=host.view.convert(control.bounds,from:control)
          #expect(rect.minX>=0 && rect.maxX<=size.width+1 && rect.minY>=0 && rect.maxY<=size.height+1)
        }
        for button in descendants(host.view).compactMap({$0 as? StudioDisclosureButton}) {
          #expect(button.visibleRect.height>=button.bounds.height-1)
        }
        let image=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
        host.view.cacheDisplay(in:host.view.bounds,to:image)
        try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-profiler-\(theme)-\(Int(size.width)).png"))
      }
    }
  }
  @Test func duplicateSessionCannotBeAdoptedOrDropped() async throws {
    let model=ProfilerModel(server:server(),executor:{_ in throw SQLFailure("existing",diagnostics:[Diagnostic(state:"42000",code:51071,message:"existing")])},disconnect:{})
    let name=SQLProfiler.sessionName(UUID())
    await model.start(name:name,confirmedSQL:try model.preview(name:name))
    #expect(!model.hasSession && !model.running && model.error=="existing\n[42000] 51071: existing")
    #expect(await model.stop())
  }
  @Test func changedConfigurationCannotSendStaleApprovalAndToolCleanupFailureCancelsQuit() async throws {
    let probe=ProfilerProbe(),model=ProfilerModel(server:server(),executor:{try await probe.execute($0)},disconnect:{})
    let name=SQLProfiler.sessionName(UUID()),sql=try model.preview(name:name)
    model.configuration.database="Changed"
    await model.start(name:name,confirmedSQL:sql)
    #expect(await probe.count()==0 && !model.hasSession && !model.error.isEmpty)
    let termination=ApplicationTermination();var flushes=0,discards=0,exits=0,cancels=0
    termination.prepare(prepareTools:{false},flush:{flushes+=1;return true},discardHistory:{discards+=1;return true},mayTerminate:{true},terminate:{exits+=1},cancelled:{cancels+=1})
    for _ in 0..<100 where termination.preparing {try await Task.sleep(for:.milliseconds(2))}
    #expect(flushes==0 && discards==0 && exits==0 && cancels==1 && !termination.consumeApproval())
  }
}
