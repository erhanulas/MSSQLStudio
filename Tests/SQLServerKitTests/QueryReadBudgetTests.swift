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
  @Test func affectedRowNotificationsDoNotConsumeRealResultSetBudget() {
    var results:[Rows]=[]
    for _ in 0..<7000 {ResultStreamBudget.append(Rows(affected:1),to:&results)}
    #expect(results.count==1 && results[0].affected==7000 && ResultStreamBudget.rowsetCount(results)==0)
    ResultStreamBudget.append(Rows(fields:[Field("Value")],values:[["1"]]),to:&results)
    ResultStreamBudget.append(Rows(affected:5),to:&results)
    #expect(ResultStreamBudget.rowsetCount(results)==1 && results.count==3 && results[2].affected==5)
  }
  actor Calls {
    var budgets:[Limits]=[]
    func add(_ limits:Limits) {budgets.append(limits)}
  }
  @Test func mixedWriteBatchContinuesAfterDisplayBudgetsAndRemovesChosenRowLimit() async throws {
    #expect(TSQL.usesResultRowLimit("SELECT 1;\nGO\nSELECT 2;"))
    #expect(!TSQL.usesResultRowLimit("INSERT dbo.Target SELECT 1;"))
    #expect(!TSQL.usesResultRowLimit("EXEC dbo.p;"))
    let calls=Calls()
    var limits=Limits();limits.rows=1;limits.resultSets=1;limits.totalBytes=1;limits.readOnlyRowLimit=true
    let sql="SELECT 1;\nGO\nINSERT dbo.Target SELECT 1;"
    let result=try await TSQL.run(sql,limits:limits) {_,budget,_ in
      await calls.add(budget)
      var result=Execution();result.results=[Rows(fields:[Field("Value")],values:[["1"]])];result.bytesRead=2;return result
    }
    let budgets=await calls.budgets
    #expect(budgets.count==2 && budgets.allSatisfy {$0.rows==Int.max})
    #expect(!result.stoppedEarly)
    var wrote=false
    #expect(try !ServerReadLimit.configure(sql:"SELECT 1",rows:Int.max,write:{_ in wrote=true},read:{1}))
    #expect(!wrote)
  }
  @Test func unlimitedReadDoesNotBecomeMutationDrainMode() async throws {
    let calls=Calls()
    var limits=Limits();limits.rows=Int.max;limits.resultSets=1;limits.readOnlyRowLimit=true
    let result=try await TSQL.run("SELECT 1;\nGO\nSELECT 2;",limits:limits) {_,budget,_ in
      await calls.add(budget)
      var output=Execution();output.results=[Rows(fields:[Field("Value")],values:[["1"]])];return output
    }
    let budgets=await calls.budgets
    #expect(budgets.count==1 && budgets[0].rows==Int.max && !budgets[0].preserveExecution)
    #expect(result.partial && result.stoppedEarly)
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
