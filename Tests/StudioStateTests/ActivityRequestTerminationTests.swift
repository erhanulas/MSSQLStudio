import Foundation
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ActivityRequestTerminationUITests {
  private func request()->ActivityMonitoring.Request {
    .init(sessionID:71,requestID:0,command:"SELECT",sessionLoginTime:"2026-10-16 12:00:00.000",requestStartTime:"2026-10-16 12:01:02.003")
  }
  @Test func offlineChangedAndInvalidTargetsNeverReachWriter() async {
    let server=ConnectedServer(profile:.init(),password:"")
    var calls=0
    let model=ActivityRequestTerminationModel(server:server,writer:{_ in calls+=1;return Execution()})
    let generation=server.generation
    server.online=false
    #expect(!(await model.terminate(request(),generation:generation)))
    server.online=true
    #expect(!(await model.terminate(request(),generation:UUID())))
    var invalid=request();invalid.requestStartTime=nil
    #expect(!(await model.terminate(invalid,generation:server.generation)))
    #expect(calls==0 && model.failed && !model.busy)
  }
  @Test func explicitTerminationIsSingleFlightAndNeverAutomaticallyRetried() async {
    let server=ConnectedServer(profile:.init(),password:"")
    var pending:CheckedContinuation<Execution,any Error>?,calls=0
    let model=ActivityRequestTerminationModel(server:server,writer:{sql in
      #expect(sql.contains("KILL 71;"));calls+=1
      return try await withCheckedThrowingContinuation {pending=$0}
    })
    let first=Task {await model.terminate(request(),generation:server.generation)}
    for _ in 0..<100 where pending==nil {try? await Task.sleep(for:.milliseconds(2))}
    #expect(model.busy && pending != nil)
    #expect(!(await model.terminate(request(),generation:server.generation)))
    pending?.resume(throwing:SQLFailure("Permission denied"));pending=nil
    #expect(!(await first.value))
    #expect(calls==1 && model.failed && model.message.contains("Permission denied") && !model.busy)
    let success=ActivityRequestTerminationModel(server:server,writer:{_ in Execution()})
    #expect(await success.terminate(request(),generation:server.generation))
    #expect(!success.failed && success.message.contains("geri alınması sürebilir"))
    let partial=ActivityRequestTerminationModel(server:server,writer:{_ in var result=Execution();result.partial=true;return result})
    #expect(!(await partial.terminate(request(),generation:server.generation)))
    #expect(partial.failed && partial.message.contains("doğrulanamadı"))
  }
  @Test func lateResultCannotReportSuccessInAnotherConnectionGeneration() async {
    let server=ConnectedServer(profile:.init(),password:"")
    let model=ActivityRequestTerminationModel(server:server,writer:{_ in server.generation=UUID();return Execution()})
    #expect(!(await model.terminate(request(),generation:server.generation)))
    #expect(model.message.isEmpty && !model.busy)
  }
  @Test func applicationLockOwnerUsesTheSameGuardedSingleFlightWriter() async throws {
    var execution=Execution()
    execution.results=[Rows(values:[["0x01:0","71","0","Demo","Resource","X","GRANTED","SESSION","0","reader","Host","App","recent","EXEC dbo.Work;","2026-10-16 12:00:00.000","5"]]),Rows()]
    let lock=try #require(ActivityApplicationLocks.decode(execution).locks.first)
    let server=ConnectedServer(profile:.init(),password:"")
    var calls=0
    let model=ActivityRequestTerminationModel(server:server,writer:{sql in
      calls+=1
      #expect(sql.contains("sys.dm_tran_locks") && sql.contains("KILL 71;"))
      #expect(!sql.contains("r.start_time"))
      return Execution()
    })
    #expect(await model.terminate(.applicationLock(lock),generation:server.generation))
    #expect(calls==1 && model.message.contains("Oturum 71") && !model.busy)
  }

}
