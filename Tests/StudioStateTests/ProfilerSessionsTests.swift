import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

private actor ProfilerSessionsProbe {
  let name=SQLProfiler.sessionName(UUID())
  var removed=false
  var calls:[String]=[]
  var fail=false
  func setFail() {fail=true}
  func statements()->[String] {calls}
  func execute(_ sql:String)throws->Execution {
    calls.append(sql)
    if fail {throw SQLFailure("permission denied")}
    if sql.contains("DROP EVENT SESSION") {removed=true;return Execution()}
    var result=Execution()
    result.results=[Rows(fields:[Field("session_name"),Field("is_running"),Field("started")],values:removed ? []:[[name,"1","2026-10-16 12:00:00.123"]])]
    return result
  }
}
@MainActor @Suite(.serialized) struct ProfilerSessionsTests {
  @Test func inspectionIsExplicitAndCurrentSessionCannotBeRemoved() async throws {
    let probe=ProfilerSessionsProbe(),server=ConnectedServer(profile:ServerProfile(),password:"")
    let model=ProfilerSessionsModel(server:server,reader:{try await probe.execute($0)})
    #expect(await probe.statements().isEmpty)
    await model.refresh()
    let session=try #require(model.sessions.first)
    await model.remove(session,currentSession:session.name)
    #expect(await probe.statements().count==1)
    await model.remove(session,currentSession:nil)
    #expect(model.sessions.isEmpty && !model.busy && model.error.isEmpty)
    #expect(await probe.statements().count==3)
  }
  @Test func openingSQLCreatesAnIdleQueryOnTheCapturedDatabase() throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    server.online=false
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false;state.servers=[server]
    let host=WorkbenchController(state:state);host.loadViewIfNeeded()
    var result=Execution()
    let xml="<RingBufferTarget totalEventsProcessed=\"1\" droppedCount=\"0\"><event name=\"sql_batch_completed\" timestamp=\"2026-10-16T12:00:00Z\"><data name=\"batch_text\"><value>SELECT 1;</value></data><action name=\"database_name\"><value>CapturedDB</value></action><action name=\"event_sequence\"><value>0</value></action></event></RingBufferTarget>"
    result.results=[Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[[xml,"0"]])]
    let events=try SQLProfiler.decode(result).events
    host.openProfilerSQL(events+events,server:server)
    let document=try #require(state.documents.first)
    #expect(document.database=="CapturedDB" && document.sql=="SELECT 1;\nGO\nSELECT 1;")
    #expect(!document.busy && state.documents.count==1 && !server.online)
  }
  @Test func openingRefreshesBadgeAndExcludesTheCurrentCapture() async throws {
    let probe=ProfilerSessionsProbe(),server=ConnectedServer(profile:ServerProfile(),password:"")
    let model=ProfilerSessionsModel(server:server,reader:{try await probe.execute($0)})
    model.refreshOnOpen();model.refreshOnOpen()
    for _ in 0..<200 where model.sessions.isEmpty {try await Task.sleep(for:.milliseconds(3))}
    let session=try #require(model.sessions.first)
    #expect(await probe.statements().count==1)
    #expect(model.activeCount(excluding:nil)==1 && model.activeCount(excluding:session.name)==0)
    let previous=StudioTheme.mode;defer {StudioTheme.apply(previous)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let host=NSHostingController(rootView:ProfilerSessionsButton(model:model,currentSession:nil));host.sizingOptions=[]
      let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
      window.setContentSize(NSSize(width:280,height:50));window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
      try await Task.sleep(for:.milliseconds(50));host.view.layoutSubtreeIfNeeded()
      let image=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds));host.view.cacheDisplay(in:host.view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-profiler-badge-"+theme+".png"))
      window.close()
    }
    model.forget(session.name);#expect(model.activeCount(excluding:nil)==0)
    server.online=false;model.refreshOnOpen();#expect(await probe.statements().count==1)
  }
  @Test func failedInspectionKeepsPreviousSnapshotAndShowsError() async throws {
    let probe=ProfilerSessionsProbe(),server=ConnectedServer(profile:ServerProfile(),password:"")
    let model=ProfilerSessionsModel(server:server,reader:{try await probe.execute($0)})
    await model.refresh();let previous=model.sessions
    await probe.setFail();await model.refresh()
    #expect(model.sessions==previous && !model.error.isEmpty && !model.busy)
  }
}
