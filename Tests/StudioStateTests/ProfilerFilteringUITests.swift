import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

private actor ProfilerFilteringProbe {
  private var calls:[String]=[]
  func statements()->[String] {calls}
  func execute(_ sql:String) throws -> Execution {
    calls.append(sql)
    guard sql.contains("SELECT t.target_data") else {return Execution()}
    let rows=[("123","HOST-A","SELECT foo"),("123","HOST-A","UPDATE bar"),("123","HOST-B","SELECT foo"),("71","HOST-A","SELECT foo")]
    let events=rows.enumerated().map {index,value in
      "<event name=\"rpc_completed\" timestamp=\"2026-10-16T12:00:00Z\"><data name=\"statement\"><value>\(value.2)</value></data><action name=\"event_sequence\"><value>\(index)</value></action><action name=\"client_pid\"><value>\(value.0)</value></action><action name=\"client_hostname\"><value>\(value.1)</value></action><action name=\"session_id\"><value>71</value></action></event>"
    }.joined()
    var result=Execution();result.results=[Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[["<RingBufferTarget totalEventsProcessed=\"4\" droppedCount=\"0\">\(events)</RingBufferTarget>","0"]])];return result
  }
}
@MainActor @Suite(.serialized) struct ProfilerFilteringUITests {
  private func wait(_ condition:()->Bool) async throws {
    for _ in 0..<200 where !condition() {try await Task.sleep(for:.milliseconds(3))}
    #expect(condition())
  }
  private func fixture() async throws -> (ProfilerModel,ProfilerFilteringProbe) {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let probe=ProfilerFilteringProbe(),model=ProfilerModel(server:server,executor:{try await probe.execute($0)},disconnect:{},interval:.milliseconds(20))
    let name=SQLProfiler.sessionName(UUID());await model.start(name:name,confirmedSQL:try model.preview(name:name))
    try await wait {model.events.count==4 && model.visibleEvents.count==4 && !model.filtering}
    return (model,probe)
  }
  @Test func liveGridFiltersLatestSearchAndClientSelectionWithoutAdditionalDDLOrChangingCapturedRows() async throws {
    let (model,probe)=try await fixture()
    #expect(model.clients.count==3 && model.clients[0].id.pid=="123" && model.clients[0].count==2)
    model.focusClient(model.clients[0])
    model.displayFilter.sqlSearch="stale";model.displayFilter.sqlSearch="bar";model.displayFilter.sqlSearch="foo"
    try await wait {!model.filtering && model.visibleEvents.map(\.id)==[0]}
    #expect(model.events.count==4 && model.clients.count==1 && model.filterError.isEmpty)
    model.displayFilter.rules=[.init(column:.clientPID,comparison:.equals,value:"not a number")]
    try await wait {!model.filtering && !model.filterError.isEmpty}
    #expect(model.visibleEvents.isEmpty && model.events.count==4)
    model.displayFilter = .init()
    try await wait {!model.filtering && model.visibleEvents.count==4}
    let statements=await probe.statements()
    #expect(statements.filter {$0.contains("CREATE EVENT SESSION")}.count==1)
    #expect(statements.filter {$0.contains("DROP EVENT SESSION")}.isEmpty)
    #expect(!statements.contains {$0.contains("not a number")})
    #expect(await model.stop())
  }
  @Test func nativeGridContextActionsFilterClearAndStopItsOwnCapture() async throws {
    let (model,probe)=try await fixture()
    var selected:UInt64?
    let coordinator=ProfilerEventGrid.Coordinator(model:model,selection:Binding(get:{selected},set:{selected=$0}))
    coordinator.events=model.visibleEvents
    let menu=coordinator.menu(row:0)
    #expect(menu is StudioMenu && !menu.autoenablesItems)
    let client=try #require(menu.items.first {$0.title=="Bu İstemciyi Filtrele"})
    #expect(client.isEnabled && client.image != nil)
    #expect(NSApp.sendAction(try #require(client.action),to:client.target,from:client))
    try await wait {!model.filtering && model.visibleEvents.count==2}
    #expect(model.visibleEvents.allSatisfy {$0.clientPID=="123" && $0.host=="HOST-A"})
    let clear=try #require(menu.items.first {$0.title=="Listeyi Temizle"})
    #expect(NSApp.sendAction(try #require(clear.action),to:clear.target,from:clear))
    try await wait {!model.filtering && model.visibleEvents.isEmpty}
    let count=await probe.statements().count
    for _ in 0..<100 where await probe.statements().count<=count {try await Task.sleep(for:.milliseconds(3))}
    #expect(model.events.isEmpty && selected==nil && model.running)
    let stop=try #require(menu.items.first {$0.title=="İzlemeyi Durdur"})
    #expect(NSApp.sendAction(try #require(stop.action),to:stop.target,from:stop))
    try await wait {!model.hasSession && !model.busy}
    #expect((await probe.statements()).filter {$0.contains("DROP EVENT SESSION")}.count==1)
    let empty=coordinator.menu(row:-1)
    #expect(empty.items.first {$0.title=="Bu İstemciyi Filtrele"}?.isEnabled==false)
  }
}
