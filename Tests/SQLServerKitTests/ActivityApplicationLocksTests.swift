import Foundation
import Testing
@testable import SQLServerKit

@Suite struct ActivityApplicationLocksTests {
  static func execution()->Execution {
    var result=Execution()
    result.results=[Rows(values:[["0x01:0","71","0","Demo","[dbo].[ResourceHash]","X","GRANTED","SESSION","0","reader","HOST","App","recent","EXEC dbo.Work;"],["0x02:0","72","0","Demo","[dbo].[ResourceHash]","X","WAIT","TRANSACTION","101","reader","HOST","App","current","EXEC sys.sp_getapplock;"]]),Rows()]
    return result
  }
  @Test func preservesGrantedWaitingAndHistoricalContextWithBoundedRead() throws {
    let snapshot=try ActivityApplicationLocks.decode(Self.execution())
    #expect(snapshot.locks.count==2 && snapshot.locks[0].status=="GRANTED" && snapshot.locks[1].status=="WAIT")
    #expect(snapshot.locks[0].sqlSource=="recent" && snapshot.locks[1].ownerType=="TRANSACTION")
    let sql=ActivityApplicationLocks.sql
    #expect(sql.contains("TOP(101)") && sql.contains("TOP(100)") && sql.contains("resource_type=N'APPLICATION'"))
    #expect(sql.contains("LEFT JOIN sys.dm_exec_sessions") && sql.contains("most_recent_sql_handle"))
    #expect(!sql.contains("KILL ") && !sql.contains("EXEC sys.sp_getapplock") && !sql.contains("sp_releaseapplock"))
  }
  @Test func retainsSignedRequestAndMissingAddressWithoutAllowingTermination() throws {
    var execution=Self.execution()
    var row=execution.results[0].values[0]
    row[0]=nil;row[2]="-1"
    execution.results[0]=Rows(values:[row])
    let lock=try #require(ActivityApplicationLocks.decode(execution).locks.first)
    #expect(lock.requestID == -1)
    #expect(throws:SQLFailure.self) {try ActivityRequestTermination.sql(for:.applicationLock(lock))}
  }
  @Test func rejectsPartialDuplicateAndMalformedCapturesButRetainsPermissionIssues() throws {
    var partial=Self.execution();partial.partial=true
    #expect(throws:SQLFailure.self) {try ActivityApplicationLocks.decode(partial)}
    var duplicate=Self.execution();duplicate.results[0]=Rows(values:[duplicate.results[0].values[0],duplicate.results[0].values[0]])
    #expect(throws:SQLFailure.self) {try ActivityApplicationLocks.decode(duplicate)}
    var bad=Self.execution();bad.results[0]=Rows(values:[["bad"]])
    #expect(throws:SQLFailure.self) {try ActivityApplicationLocks.decode(bad)}
    var denied=Execution();denied.results=[Rows(),Rows(values:[["Application locks","Permission denied"]])]
    let snapshot=try ActivityApplicationLocks.decode(denied)
    #expect(snapshot.locks.isEmpty && snapshot.issues==["Application locks: Permission denied"])
  }
}
