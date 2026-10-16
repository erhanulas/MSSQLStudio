import Foundation
import Testing
@testable import SQLServerKit

@Suite struct SQLProfilerCorrelationTests {
  private func events(_ kinds:[String],gap:Bool=false,otherConnection:Bool=false) throws -> [SQLProfiler.Event] {
    let connection="11111111-1111-1111-1111-111111111111"
    let activity="22222222-2222-2222-2222-222222222222"
    let body=kinds.enumerated().map { index,kind in
      let sequence=index+(gap && index>0 ? 1:0)
      let sql=kind.hasSuffix("starting") ? "EXEC dbo.Fail;":""
      let client=otherConnection && kind=="error_reported" ? "33333333-3333-3333-3333-333333333333":connection
      return """
      <event name="\(kind)" timestamp="2026-10-16T12:00:00.123Z">
      <data name="statement"><value>\(sql)</value></data>
      <data name="message"><value>Deliberate error</value></data>
      <action name="event_sequence"><value>\(sequence)</value></action>
      <action name="session_id"><value>71</value></action>
      <action name="client_connection_id"><value>\(client)</value></action>
      <action name="attach_activity_id"><value>\(activity)-\(sequence)</value></action>
      </event>
      """
    }.joined()
    let xml="<RingBufferTarget totalEventsProcessed=\"\(kinds.count)\">\(body)</RingBufferTarget>"
    var execution=Execution()
    execution.results=[Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[[xml,"0"]])]
    var buffer=SQLProfiler.Buffer();buffer.beginSession(name:"Capture-A")
    buffer.append(try SQLProfiler.decode(execution))
    return buffer.events
  }
  @Test func linksErrorAndCompletionToCapturedCallWithoutMutatingRawSQL() throws {
    let events=try events(["rpc_starting","error_reported","rpc_completed"])
    let links=SQLProfilerCorrelation.relations(events)
    #expect(events[1].sql.isEmpty && events[2].sql.isEmpty)
    #expect(links[events[1].id]?.source.sql=="EXEC dbo.Fail;")
    #expect(links[events[2].id]?.messages.map(\.id)==[events[1].id])
    let projection=try SQLProfilerFiltering.project(events,filter:.init())
    #expect(projection.events.map(\.kind)==["error_reported","rpc_completed"])
    #expect(projection.relations[events[2].id]?.messages.count==1)
    let pending=SQLProfilerCorrelation.relations(Array(events.prefix(2)))
    #expect(pending[events[1].id]?.source.id==events[0].id)
    let encoded=try JSONEncoder().encode(events)
    #expect(try JSONDecoder().decode([SQLProfiler.Event].self,from:encoded)==events)
  }
  @Test func doesNotBorrowErrorsAcrossSequentialCallsOrConnectionsOrMissingBoundaries() throws {
    let sequential=try events(["rpc_starting","error_reported","rpc_completed","rpc_starting","rpc_completed"])
    let links=SQLProfilerCorrelation.relations(sequential)
    #expect(links[sequential[4].id]?.messages.isEmpty==true)
    let different=try events(["rpc_starting","error_reported","rpc_completed"],otherConnection:true)
    #expect(SQLProfilerCorrelation.relations(different)[different[1].id]==nil)
    let missing=try events(["error_reported","rpc_completed"])
    #expect(SQLProfilerCorrelation.relations(missing).isEmpty)
    let gap=try events(["rpc_starting","error_reported","rpc_completed"],gap:true)
    #expect(SQLProfilerCorrelation.relations(gap).isEmpty)
    var legacy=sequential;legacy[1].activityID=nil
    #expect(SQLProfilerCorrelation.relations(legacy)[legacy[1].id]==nil)
  }
}
