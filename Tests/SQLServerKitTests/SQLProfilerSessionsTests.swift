import Foundation
import Testing
@testable import SQLServerKit

@Suite struct SQLProfilerSessionsTests {
  @Test func listIncludesStoppedDefinitionsAndValidatesBoundaries() throws {
    #expect(SQLProfiler.sessionsSQL.contains("LEFT(e.name,21)"))
    #expect(SQLProfiler.sessionsSQL.contains("LEFT JOIN sys.dm_xe_sessions"))
    let name=SQLProfiler.sessionName(UUID())
    var result=Execution()
    result.results=[Rows(fields:[Field("session_name"),Field("is_running"),Field("started")],values:[[name,"1","2026-10-16 12:00:00.123"]])]
    let sessions=try SQLProfiler.decodeSessions(result)
    #expect(sessions.count==1 && sessions[0].running && sessions[0].name==name)
    result.results=[Rows(fields:result.results[0].fields,values:[["system_health","0",nil]])]
    #expect(throws:(any Error).self) {try SQLProfiler.decodeSessions(result)}
    result.results=[Rows(fields:result.results[0].fields,values:[[name,"0",nil]])]
    result.partial=true
    #expect(throws:(any Error).self) {try SQLProfiler.decodeSessions(result)}
    result.partial=false;result.results=[Rows(fields:result.results[0].fields,values:Array(repeating:[name,"0",nil],count:501))]
    #expect(throws:(any Error).self) {try SQLProfiler.decodeSessions(result)}
    #expect(throws:(any Error).self) {try SQLProfiler.dropSQL(name:name+"]; DROP TABLE x")}
    #expect(try SQLProfiler.dropSQL(name:name).contains("DROP EVENT SESSION ["+name+"] ON SERVER"))
  }
}
