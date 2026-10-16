import Foundation
import Testing
@testable import SQLServerKit

@Suite struct ActivityRequestTerminationTests {
  func request()->ActivityMonitoring.Request {
    .init(sessionID:71,requestID:0,command:"SELECT",sql:"SELECT 1",sessionLoginTime:"2026-10-16 12:00:00.000",requestStartTime:"2026-10-16 12:01:02.003")
  }
  @Test func onlyValidatedIdentityCanProduceOneGuardedKill() throws {
    let sql=try ActivityRequestTermination.sql(for:request())
    #expect(sql.contains("KILL 71;") && sql.components(separatedBy:"KILL 71;").count==2)
    #expect(sql.contains("s.login_time=CONVERT(datetime") && sql.contains("r.start_time=CONVERT(datetime"))
    #expect(sql.contains("r.request_id=0") && sql.contains("s.is_user_process=1") && sql.contains("IF @@SPID = 71"))
    #expect(sql.contains("@@TRANCOUNT") && sql.contains("THROW 51081") && !sql.contains("WITH STATUSONLY"))
    for index in 0..<7 {
      var value=request()
      switch index {
      case 0:value.sessionID=1
      case 1:value.requestID = -1
      case 2:value.requestStartTime=nil
      case 3:value.sessionLoginTime="2026-10-16'; KILL 72;--"
      case 4:value.requestStartTime="2026-02-31 12:01:02.003"
      case 5:value.command="BACKUP DATABASE"
      default:value.command="KILLED/ROLLBACK"
      }
      #expect(throws:SQLFailure.self) {try ActivityRequestTermination.sql(for:value)}
    }
  }
  @Test func newDiagnosticsCarryTargetIdentityAndLegacyRowsCannotGenerateKill() throws {
    var execution=ActivityFavoriteTests().diagnosticExecution()
    let legacy=try #require(ActivityMonitoring.decodeDiagnostics(execution).blocked.first)
    #expect(throws:SQLFailure.self) {try ActivityRequestTermination.sql(for:legacy)}
    for index in 0..<3 {
      execution.results[index]=Rows(values:execution.results[index].values.map {$0+["2026-10-16 12:00:00.000","2026-10-16 12:01:02.003"]})
    }
    let decoded=try #require(ActivityMonitoring.decodeDiagnostics(execution).blocked.first)
    #expect(decoded.sessionLoginTime==request().sessionLoginTime && decoded.requestStartTime==request().requestStartTime)
    #expect(try ActivityRequestTermination.sql(for:decoded).contains("KILL 71;"))
    #expect(ActivityMonitoring.diagnosticsSQL.contains("CONVERT(varchar(23),s.login_time,121)"))
  }
  @Test func applicationLockTerminationSupportsIdleOwnersAndRejectsLegacyOrUnsafeTargets() throws {
    var execution=ActivityApplicationLocksTests.execution()
    let legacy=try #require(ActivityApplicationLocks.decode(execution).locks.first)
    #expect(throws:SQLFailure.self) {try ActivityRequestTermination.sql(for:.applicationLock(legacy))}
    execution.results[0]=Rows(values:execution.results[0].values.map {$0+["2026-10-16 12:00:00.000","5"]})
    let lock=try #require(ActivityApplicationLocks.decode(execution).locks.first)
    let sql=try ActivityRequestTermination.sql(for:.applicationLock(lock))
    #expect(sql.contains("KILL 71;") && sql.contains("s.login_time=CONVERT(datetime"))
    #expect(sql.contains("l.resource_type=N'APPLICATION'") && sql.contains("l.resource_database_id=5"))
    #expect(sql.contains("l.resource_lock_partition=0") && sql.contains("l.request_owner_type=N'SESSION'"))
    #expect(sql.contains("l.request_owner_id=0") && sql.contains("l.resource_description=N'[dbo].[ResourceHash]'"))
    #expect(!sql.contains("r.start_time") && !sql.contains("JOIN sys.dm_exec_requests"))
    #expect(sql.contains("command LIKE N'BACKUP%'") && sql.contains("IF @@SPID = 71"))
    for index in 0..<4 {
      var invalid=execution
      var row=invalid.results[0].values[0]
      switch index {
      case 0:row[1]="-2"
      case 1:row[0]="0x12'; KILL 72;--:0"
      case 2:row[7]="SHARED_TRANSACTION_WORKSPACE"
      default:row[14]="bad date"
      }
      invalid.results[0]=Rows(values:[row])
      let target=try #require(ActivityApplicationLocks.decode(invalid).locks.first)
      #expect(throws:SQLFailure.self) {try ActivityRequestTermination.sql(for:.applicationLock(target))}
    }
  }

}
