import Testing
@testable import SQLServerKit

struct ODBCExecutionTimeoutTests {
  @Test func zeroIsValidAndInvalidTimeoutsFailBeforeOpeningAStatement() async throws {
    let connection=ODBCConnection()
    for seconds in [-1,Int.max] {
      var limits=Limits();limits.timeout=seconds
      do {_=try await connection.execute("SELECT 1;",limits:limits);Issue.record("Invalid timeout accepted")}
      catch let failure as SQLFailure {#expect(failure.message=="Sorgu zaman aşımı geçersiz.")}
    }
    var limits=Limits();limits.timeout=0
    do {_=try await connection.execute("SELECT 1;",limits:limits);Issue.record("Disconnected execution accepted")}
    catch let failure as SQLFailure {#expect(failure.diagnostics.first?.state=="08003")}
  }
}
