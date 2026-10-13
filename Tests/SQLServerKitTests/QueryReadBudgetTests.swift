import Foundation
import Testing
@testable import SQLServerKit

struct QueryReadBudgetTests {
  @Test func fetchStopsAtTheLimitWithoutRequestingTheNextRow() throws {
    for available in [0,8,1000,5000] {
      var budget=ResultFetchBudget(rows:1000),calls=0,read=0
      while try budget.next(fetch:{calls+=1;return calls<=available}) {read+=1}
      #expect(read == min(available,1000))
      #expect(calls == (available<1000 ? available+1:1000))
      #expect(budget.reached == (available>=1000))
    }
  }
  @Test func everyResultGetsItsOwnBudgetAndErrorsAreNotSwallowed() throws {
    var counts:[Int]=[]
    for available in [20,2,30] {
      var budget=ResultFetchBudget(rows:10),remaining=available
      while try budget.next(fetch:{remaining-=1;return remaining>=0}) {}
      counts.append(budget.count)
    }
    #expect(counts == [10,2,10])
    var budget=ResultFetchBudget(rows:1000)
    #expect(throws:CancellationError.self) {try budget.next {throw CancellationError()}}
    #expect(budget.count == 0 && !budget.reached)
  }
  @Test func driverLimitIsRequiredAndVerifiedForReadOnlySQL() throws {
    for sql in ["SELECT * FROM TBLSTSABIT AS T WITH(NOLOCK)","SELECT 1; SELECT 2;", ";WITH q AS (SELECT 1 AS ID) SELECT * FROM q;"] {
      var applied=0
      #expect(try ServerReadLimit.configure(sql:sql,rows:1000,write:{applied=$0},read:{applied}))
      #expect(applied == 1000)
    }
    #expect(throws:SQLFailure.self) {try ServerReadLimit.configure(sql:"SELECT 1",rows:1000,write:{_ in},read:{0})}
  }
  @Test func driverRowcountCannotLimitWritesStoredProceduresOrSessionStatements() throws {
    for sql in ["UPDATE dbo.News SET Title=N'X'; SELECT * FROM dbo.News;", "DELETE FROM dbo.News;", "INSERT dbo.News VALUES(1);", "WITH q AS (SELECT 1 AS ID) DELETE FROM q;", "EXEC dbo.p;", "SET ROWCOUNT 20; SELECT 1;", "SELECT * INTO #t FROM dbo.News;"] {
      var changed=false
      #expect(try !ServerReadLimit.configure(sql:sql,rows:1000,write:{_ in changed=true},read:{1000}))
      #expect(!changed)
    }
  }
}
