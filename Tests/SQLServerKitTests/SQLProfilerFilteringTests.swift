import Foundation
import Testing
@testable import SQLServerKit

@Suite struct SQLProfilerFilteringTests {
  private func event(_ id:UInt64,host:String="HOST-A",pid:String="123",sql:String="SELECT * FROM Stock",duration:Double?=12.5,reads:String="40")->SQLProfiler.Event {
    .init(id:id,timestamp:"2026-10-16T12:00:00Z",kind:"rpc_completed",database:"Demo",application:"Warehouse",host:host,login:"operator",session:"71",clientPID:pid,durationMS:duration,cpu:"9007199254740993",reads:reads,writes:"3",sql:sql,message:"")
  }
  @Test func pidIsDistinctFromSpidAndCapturePredicatesAreEscapedAndNumeric() throws {
    var config=SQLProfiler.Configuration();config.clientPID="123";config.sessionID="71";config.host="O'Brien";config.sqlLike="%STOK_%";config.sqlNotLike="%SECRET%"
    let sql=try SQLProfiler.createSQL(name:SQLProfiler.sessionName(UUID()),configuration:config)
    #expect(sql.contains("sqlserver.client_pid") && sql.contains("[client_pid]=(123)") && sql.contains("[session_id]=(71)"))
    #expect(sql.contains("O''''Brien") && sql.contains("like_i_sql_unicode_string") && sql.contains("NOT ("))
    config.clientPID="123 OR 1=1"
    #expect(throws:(any Error).self) {try SQLProfiler.createSQL(name:SQLProfiler.sessionName(UUID()),configuration:config)}
    config.clientPID="0"
    #expect(throws:(any Error).self) {try SQLProfiler.createSQL(name:SQLProfiler.sessionName(UUID()),configuration:config)}
    config.clientPID="123";config.sessionID="40000"
    #expect(throws:(any Error).self) {try SQLProfiler.createSQL(name:SQLProfiler.sessionName(UUID()),configuration:config)}
    let source=SQLProfilerTests.execution().results[0].values[0][0]!
    var execution=Execution();execution.results=[Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[[source.replacingOccurrences(of:"</event>",with:"<action name=\"client_pid\"><value>123</value></action></event>"),"0"]])]
    let decoded=try SQLProfiler.decode(execution).events[0]
    #expect(decoded.clientPID=="123" && decoded.session=="71")
  }
  @Test func gridSearchAndMultipleConditionsCombineWithoutChangingSourceOrMatchingSpidAsPid() throws {
    let source=[event(0),event(1,host:"HOST-B"),event(2,pid:"71"),event(3,sql:"EXEC DeleteStock"),event(4,duration:1)]
    var filter=SQLProfilerFiltering.Filter();filter.sqlSearch="select"
    filter.rules=[.init(column:.clientPID,comparison:.equals,value:"123"),.init(column:.host,comparison:.equals,value:"host-a"),.init(column:.duration,comparison:.atLeast,value:"10")]
    #expect(try SQLProfilerFiltering.project(source,filter:filter).events.map(\.id)==[0])
    filter.sqlSearch=""
    filter.rules=[.init(column:.sql,comparison:.notContains,value:"delete"),.init(column:.clientPID,comparison:.notEquals,value:"71"),.init(column:.duration,comparison:.atMost,value:"2")]
    #expect(try SQLProfilerFiltering.project(source,filter:filter).events.map(\.id)==[4])
    #expect(source.count==5 && source[0].sql=="SELECT * FROM Stock")
    filter.rules=[.init(column:.cpu,comparison:.equals,value:"9007199254740992")]
    #expect(try SQLProfilerFiltering.project(source,filter:filter).events.isEmpty)
    filter.rules=[.init(column:.cpu,comparison:.equals,value:"9007199254740993")]
    #expect(try SQLProfilerFiltering.project(source,filter:filter).events.count==5)
  }
  @Test func busiestClientsSeparateSamePidOnDifferentHostsAndDoNotInventMissingIdentity() throws {
    let projection=try SQLProfilerFiltering.project([event(0),event(1),event(2,host:"HOST-B"),event(3,pid:""),event(4,host:"")],filter:.init())
    #expect(projection.events.count==5 && projection.clients.count==2 && projection.unknownClientEvents==2)
    #expect(projection.clients[0].id.host=="HOST-A" && projection.clients[0].id.pid=="123")
    #expect(projection.clients[0].count==2 && projection.clients[0].durationMS==25)
    #expect(projection.clients[1].id.host=="HOST-B" && projection.clients[1].count==1)
    #expect(try SQLProfilerFiltering.project([event(5,duration:nil)],filter:.init()).clients[0].durationMS==nil)
  }
  @Test func invalidNumericAndIncompatibleRulesAreVisibleErrorsAndSearchIsLiteral() throws {
    var filter=SQLProfilerFiltering.Filter()
    for value in ["1x","NaN","-1","1.2"] {
      filter.rules=[.init(column:.clientPID,comparison:.equals,value:value)]
      #expect(throws:(any Error).self) {try SQLProfilerFiltering.project([event(0)],filter:filter)}
    }
    filter.rules=[.init(column:.sql,comparison:.atLeast,value:"20")]
    #expect(throws:(any Error).self) {try SQLProfilerFiltering.project([event(0)],filter:filter)}
    filter.rules=[];filter.sqlSearch="%"
    #expect(try SQLProfilerFiltering.project([event(0),event(1,sql:"SELECT 50%")],filter:filter).events.map(\.id)==[1])
    filter.rules=Array(repeating:.init(value:"1"),count:21)
    #expect(throws:(any Error).self) {try SQLProfilerFiltering.project([],filter:filter)}
  }
}
