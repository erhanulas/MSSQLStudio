import Foundation
import Testing
@testable import SQLServerKit

@Suite struct SQLProfilerMessageTests {
  static func execution(number:Int=5701,severity:String?="10",state:String="1",message:String="Changed database context.",sql:String="")->Execution {
    let severityXML=severity.map {"<data name=\"severity\"><value>\($0)</value></data>"} ?? ""
    let xml="""
    <RingBufferTarget totalEventsProcessed="1" droppedCount="0"><event name="error_reported" timestamp="2026-10-16T12:00:00Z">
    <data name="error_number"><value>\(number)</value></data>\(severityXML)
    <data name="state"><value>\(state)</value></data><data name="message"><value>\(message)</value></data>
    <action name="sql_text"><value>\(sql)</value></action><action name="event_sequence"><value>0</value></action>
    </event></RingBufferTarget>
    """
    var result=Execution();result.results=[Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[[xml,"0"]])];return result
  }
  @Test func informationalConnectionsWarningsAndErrorsUseServerMetadata() throws {
    for number in [5701,5703] {
      let event=try SQLProfiler.decode(Self.execution(number:number)).events[0]
      #expect(event.messageLevel == .info && event.errorNumber==number && event.severity==10 && event.errorState==1 && event.sql.isEmpty)
    }
    let warning=try SQLProfiler.decode(Self.execution(number:8153)).events[0]
    #expect(warning.messageLevel == .warning)
    for severity in ["11","16","20","25"] {
      let error=try SQLProfiler.decode(Self.execution(number:208,severity:severity)).events[0]
      #expect(error.messageLevel == .error)
    }
    let info=try SQLProfiler.decode(Self.execution(number:50000,severity:"0",message:"error in arbitrary text")).events[0]
    #expect(info.messageLevel == .info)
    let unknown=try SQLProfiler.decode(Self.execution(severity:nil)).events[0]
    #expect(unknown.messageLevel == .unknown)
    #expect(try SQLProfiler.decode(SQLProfilerTests.execution()).events[0].messageLevel==nil)
  }
  @Test func malformedMetadataIsNotSilentlyConvertedAndExportsRemainCompatible() throws {
    for severity in ["-1","26","invalid"] {
      #expect(throws:(any Error).self) {try SQLProfiler.decode(Self.execution(severity:severity))}
    }
    #expect(throws:(any Error).self) {try SQLProfiler.decode(Self.execution(state:"256"))}
    let event=try SQLProfiler.decode(Self.execution()).events[0]
    let data=try JSONEncoder().encode(event)
    #expect(try JSONDecoder().decode(SQLProfiler.Event.self,from:data)==event)
    var legacy=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
    for key in ["errorNumber","severity","errorState"] {legacy.removeValue(forKey:key)}
    let old=try JSONDecoder().decode(SQLProfiler.Event.self,from:JSONSerialization.data(withJSONObject:legacy))
    #expect(old.messageLevel == .unknown && old.message==event.message)
  }
  @Test func messageColumnsUseExistingNumericAndTextFiltering() throws {
    let info=try SQLProfiler.decode(Self.execution()).events[0]
    let error=try SQLProfiler.decode(Self.execution(number:208,severity:"16")).events[0]
    var filter=SQLProfilerFiltering.Filter();filter.rules=[.init(column:.severity,comparison:.atLeast,value:"11")]
    #expect(try SQLProfilerFiltering.project([info,error],filter:filter).events==[error])
    #expect(SQLProfilerFiltering.Column.messageLevel.value(info)=="Bilgi")
    #expect(SQLProfilerFiltering.Column.errorNumber.value(error)=="208")
  }
}
