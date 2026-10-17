import Foundation
import Testing
@testable import SQLServerKit

struct ActivitySQLTextTests {
  @Test func selectedSQLIsFullUnicodeAndInvalidOrPartialBytesFailVisibly() throws {
    let source=String(repeating:"SELECT N'uzun SQL 😀';\n",count:1200)+"-- END_MARKER"
    var execution=Execution();execution.results=[Rows(values:[[source,String(source.utf16.count*2)]])]
    #expect(try ActivitySQLText.decode(execution)==source)
    var failure=execution;failure.failure=SQLFailure("SQL metni önbellekten kaldırılmış.")
    do {_=try ActivitySQLText.decode(failure);Issue.record("Server error must remain visible")} catch {#expect(error.localizedDescription.contains("önbellekten"))}
    var partial=execution;partial.partial=true
    #expect(throws:SQLFailure.self) {try ActivitySQLText.decode(partial)}
    var short=execution;short.results[0].values=[[String(source.prefix(2000)),String(source.utf16.count*2)]]
    #expect(throws:SQLFailure.self) {try ActivitySQLText.decode(short)}
    let oversized=String(repeating:"x",count:ActivitySQLText.maximumBytes/2+1)
    execution.results=[Rows(values:[[oversized,String(oversized.utf16.count*2)]])]
    #expect(throws:SQLFailure.self) {try ActivitySQLText.decode(execution)}
  }
  @Test func sqlUsesOnlyValidatedSnapshotHandleAndLeavesSamplerBounded() throws {
    let sql=try ActivitySQLText.sql(handle:"0x0102ABCD")
    #expect(sql.contains("sys.dm_exec_sql_text(CONVERT(varbinary(64),N'0x0102ABCD',1))"))
    #expect(sql.contains("DATALENGTH(@sql)") && !sql.contains("LEFT(") && !sql.contains("KILL"))
    for invalid in ["", "0x", "0x123", "0x12'; KILL 51;--", "0x"+String(repeating:"A",count:130)] {
      #expect(throws:SQLFailure.self) {try ActivitySQLText.sql(handle:invalid)}
    }
    #expect(ActivityMonitoring.diagnosticsSQL.contains("TOP(30)") && ActivityMonitoring.diagnosticsSQL.contains("2000)"))
    #expect(ActivityMonitoring.diagnosticsSQL.contains("CONVERT(varchar(130),r.sql_handle,1)"))
    #expect(ActivityMonitoring.diagnosticsSQL.contains("ELSE c.most_recent_sql_handle END,1)"))
  }
  @Test func newHandleColumnsAndLegacyDiagnosticsDecodeWithoutChangingKillIdentity() throws {
    var row:[String?]=["72","0","Demo","suspended","SELECT","5000","0","0","0","73","LCK_M_X","1",nil,nil,"short","login","host","app","0","100","key","2026-10-18 00:00:00.000","2026-10-18 00:01:00.000","0x0102"]
    let context:[String?]=["73",nil,"0","Demo","sleeping",nil,nil,"",nil,"","1","login","host","app","recent","short","0x0304"]
    var execution=Execution();execution.results=[Rows(values:[row]),Rows(),Rows(),Rows(values:[context]),Rows()]
    let current=try ActivityMonitoring.decodeDiagnostics(execution)
    #expect(current.blocked.first?.sqlHandle=="0x0102" && current.blockingContexts.first?.sqlHandle=="0x0304")
    row.removeLast();execution.results[0]=Rows(values:[row]);execution.results[3]=Rows(values:[Array(context.prefix(16))])
    let legacy=try ActivityMonitoring.decodeDiagnostics(execution)
    #expect(legacy.blocked.first?.sqlHandle==nil && legacy.blockingContexts.first?.sqlHandle==nil)
    #expect(ActivityMonitoring.sameRequest(try #require(current.blocked.first),try #require(legacy.blocked.first)))
  }
}
