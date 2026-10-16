import Foundation
import Testing
@testable import SQLServerKit

@Suite struct SQLProfilerTests {
  static func execution(sequence:UInt64=0,processed:UInt64=1,truncated:Bool=false,text:String="SELECT &lt;tag&gt;;")->Execution {
    let xml="""
    <RingBufferTarget totalEventsProcessed="\(processed)" droppedCount="0" truncated="\(truncated ? 1:0)">
    <event name="sql_batch_completed" timestamp="2026-10-16T12:00:00.123Z">
    <data name="duration"><value>1500</value></data><data name="cpu_time"><value>42</value></data>
    <data name="batch_text"><value>\(text)</value></data>
    <action name="event_sequence"><value>\(sequence)</value></action>
    <action name="database_name"><value>Demo</value></action>
    <action name="session_id"><value>71</value></action>
    </event></RingBufferTarget>
    """
    var result=Execution();result.results=[Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[[xml,"0"]])];return result
  }
  @Test func createEscapesFiltersAndOnlyUsesOwnedSessionWithBoundedNonblockingTarget() throws {
    let name=SQLProfiler.sessionName(UUID())
    var config=SQLProfiler.Configuration();config.database="O'Brien";config.application="App]; DROP TABLE x;--";config.minimumDurationMS=25
    let sql=try SQLProfiler.createSQL(name:name,configuration:config)
    #expect(sql.contains("sql_batch_completed") && sql.contains("rpc_completed") && sql.contains("error_reported"))
    #expect(sql.contains("O''''Brien") && sql.contains("[duration]>=(25000)"))
    #expect(sql.contains("STARTUP_STATE=OFF") && sql.contains("max_memory=1024,max_events_limit=5000"))
    #expect(sql.contains("MAX_MEMORY=4096 KB") && sql.contains("MAX_DISPATCH_LATENCY=1 SECONDS") && !sql.contains("event_file"))
    #expect(sql.contains("ALLOW_SINGLE_EVENT_LOSS") && !sql.contains("NO_EVENT_LOSS"))
    #expect(sql.contains("event_sequence") && sql.contains("@@SPID"))
    #expect(throws:(any Error).self) {try SQLProfiler.dropSQL(name:"system_health")}
    #expect(throws:(any Error).self) {try SQLProfiler.readSQL(name:name+"];DROP TABLE x")}
    config.minimumDurationMS = -1
    #expect(throws:(any Error).self) {try SQLProfiler.createSQL(name:name,configuration:config)}
  }
  @Test func decodePreservesSQLAndRejectsMissingPartialMalformedOrOversizedPayloads() throws {
    let snapshot=try SQLProfiler.decode(Self.execution())
    #expect(snapshot.events.count==1 && snapshot.events[0].id==0)
    #expect(snapshot.events[0].sql=="SELECT <tag>;" && snapshot.events[0].durationMS==1.5)
    #expect(snapshot.events[0].cpu=="42" && snapshot.events[0].database=="Demo")
    let cdata=try SQLProfiler.decode(Self.execution(text:"<![CDATA[SELECT N'<a> & b';\nSELECT 2;]]>"))
    #expect(cdata.events[0].sql=="SELECT N'<a> & b';\nSELECT 2;")
    var partial=Self.execution();partial.partial=true
    #expect(throws:(any Error).self) {try SQLProfiler.decode(partial)}
    partial=Self.execution();partial.results[0].truncated=true
    #expect(throws:(any Error).self) {try SQLProfiler.decode(partial)}
    #expect(throws:(any Error).self) {try SQLProfiler.decode(Execution())}
    var bad=Self.execution();bad.results[0]=Rows(fields:[Field("profiler_xml"),Field("dropped_events")],values:[["<bad>","0"]])
    #expect(throws:(any Error).self) {try SQLProfiler.decode(bad)}
    #expect(throws:(any Error).self) {try SQLProfiler.decode(Self.execution(text:String(repeating:"a",count:4_194_305)))}
  }
  @Test func retentionDeduplicatesZeroBasedSequenceAndReportsGapsWithoutReplayingClearedRows() throws {
    var buffer=SQLProfiler.Buffer()
    let first=try SQLProfiler.decode(Self.execution())
    buffer.append(first);buffer.append(first)
    #expect(buffer.events.count==1 && !buffer.possibleLoss)
    buffer.clearDisplay();buffer.append(first);#expect(buffer.events.isEmpty)
    buffer.append(try SQLProfiler.decode(Self.execution(sequence:5,processed:6,truncated:true)))
    #expect(buffer.events.map(\.id)==[5] && buffer.possibleLoss)
    for index in 6...5106 {buffer.append(try SQLProfiler.decode(Self.execution(sequence:UInt64(index),processed:UInt64(index+1))))}
    #expect(buffer.events.count==5000 && buffer.discarded==102 && buffer.lastSequence==5106)
  }
  @Test func restartedSessionsRetainRowsAndIndependentSequences() throws {
    var buffer=SQLProfiler.Buffer()
    let first=try SQLProfiler.decode(Self.execution())
    buffer.beginSession(name:"first");buffer.append(first);buffer.append(first)
    let retained=buffer.events[0]
    buffer.beginSession(name:"second");buffer.append(first);buffer.append(first)
    #expect(buffer.events.count==2 && buffer.events[0]==retained)
    #expect(buffer.events.map(\.id)==[0,1])
    #expect(buffer.events.map(\.sourceSequence)==[0,0])
    #expect(buffer.events.map(\.captureSession)==["first","second"])
    #expect(!buffer.possibleLoss)
    let decoded=try JSONDecoder().decode([SQLProfiler.Event].self,from:JSONEncoder().encode(buffer.events))
    #expect(decoded==buffer.events)
    buffer.clearDisplay();buffer.append(first);#expect(buffer.events.isEmpty)
    buffer.beginSession(name:"third");buffer.append(first)
    #expect(buffer.events.count==1 && buffer.events[0].id==2)
  }
  @Test func byteRetentionKeepsMemoryBoundedEvenForLongSQL() throws {
    var buffer=SQLProfiler.Buffer()
    let text=String(repeating:"X",count:1_000_000)
    for index in 0..<12 {buffer.append(try SQLProfiler.decode(Self.execution(sequence:UInt64(index),processed:UInt64(index+1),text:text)))}
    #expect(buffer.events.count<=8 && buffer.discarded>=4)
    #expect(buffer.events.reduce(0) {$0+$1.retainedBytes}<=8_388_608)
  }
}
