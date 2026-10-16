import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ConnectionReadLimitTests {
  private var lost:SQLFailure {SQLFailure("Transport fixture",diagnostics:[.init(state:"08S01",code:10054,message:"Catalog transport failed")])}
  private func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
  private func readDocument()->QueryDocument {
    let server=ConnectedServer(profile:ServerProfile(visibleDatabases:[]),password:"")
    server.healthCheckFixture={}
    let doc=QueryDocument(server:server,database:"master",title:"Read limit fixture")
    doc.sql="SELECT n FROM dbo.Numbers; SELECT n FROM dbo.OtherNumbers;";doc.state = .ready
    return doc
  }
  private func output(rows:Int)->Execution {
    var value=Execution()
    value.results=(0..<2).map {_ in Rows(fields:[Field("n")],values:(0..<rows).map {[String($0)]})}
    return value
  }
  @Test func changedReadLimitReexecutesLastSelectWithNewBudgetAndPreservesEditorSQL() async throws {
    _=NSApplication.shared
    let doc=readDocument();doc.limits=ResultReadPreferences.limits(rows:10)
    let original=doc.sql
    var runs:[(String,Int)]=[]
    doc.executionFixture={sql,limits in runs.append((sql,limits.rows));return output(rows:min(30,limits.rows))}
    doc.sessionProbeFixture={_,_ in var result=Execution();result.results=[Rows(values:[["0","master"]])];return result}
    doc.execute();await doc.task?.value
    #expect(doc.canRefresh)
    let query=QueryController(document:doc);_=query.view
    doc.sql="DELETE dbo.DoNotExecute;";doc.selectedRange=NSRange(location:0,length:6)
    query.applyLoadingPreferences(rows:20,refresh:0,save:false);await doc.task?.value
    #expect(runs.count==2 && runs.last?.0==original && runs.last?.1==20)
    #expect(doc.sql=="DELETE dbo.DoNotExecute;" && doc.selectedRange==NSRange(location:0,length:6))
    query.applyLoadingPreferences(rows:20,refresh:0,save:false)
    #expect(runs.count==2)
    query.applyLoadingPreferences(rows:0,refresh:0,save:false);await doc.task?.value
    #expect(runs.count==3 && runs.last?.1==Int.max)
    doc.transactionCount=1
    query.applyLoadingPreferences(rows:100,refresh:0,save:false)
    #expect(runs.count==3 && !doc.busy)
  }
  @Test func insertSelectAndExecIgnoreChosenReadLimitAndKeepTheirCompleteOutput() async throws {
    _=NSApplication.shared
    for sql in ["INSERT dbo.Target(Code, Total) SELECT Code, SUM(Amount) FROM dbo.Source GROUP BY Code HAVING SUM(Amount)>0;", "EXEC dbo.GenerateRows;"] {
      let doc=readDocument();doc.sql=sql;doc.limits=ResultReadPreferences.limits(rows:2)
      var requested:Int?
      doc.executionFixture={_,limits in requested=limits.rows;return output(rows:20)}
      doc.execute();await doc.task?.value
      #expect(requested==Int.max && doc.lastExecutedReadLimit==nil && doc.rowCount==40)
      let query=QueryController(document:doc);_=query.view
      let grids=query.children.compactMap {$0 as? ResultController}
      #expect(grids.count==2 && grids.allSatisfy {$0.result.values.count==20 && $0.pageSize==0 && !$0.isReadLimited})
      query.applyLoadingPreferences(rows:1,refresh:0,save:false)
      #expect(grids.allSatisfy {$0.result.values.count==20} && requested==Int.max)
    }
  }
  @Test func failedIndependentCatalogConnectionKeepsHealthyExplorerAndQuerySessionsConnected() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    let doc=QueryDocument(server:server,database:"master",title:"Independent query");doc.state = .ready
    var healthChecks=0
    server.healthCheckFixture={healthChecks+=1}
    server.asyncCatalogFixture={_ in throw lost}
    await #expect(throws:SQLFailure.self) {try await server.catalog("SELECT 1;",database:"master")}
    #expect(healthChecks == 1 && server.online && doc.state == .ready)
    #expect(server.startupError?.contains("Catalog transport failed") == true)
    server.healthCheckFixture={healthChecks+=1;throw lost}
    await #expect(throws:SQLFailure.self) {try await server.catalog("SELECT 1;",database:"master")}
    #expect(healthChecks == 2 && !server.online && doc.state == .ready)
    await server.checkExplorerHealth();#expect(healthChecks == 2)
  }
  @Test func catalogPermissionAndStaleTransportErrorsDoNotProbeOrDisconnectReplacementSessions() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var checks=0;server.healthCheckFixture={checks+=1;throw lost}
    server.asyncCatalogFixture={_ in throw SQLFailure("Permission fixture",diagnostics:[.init(state:"42000",code:229,message:"Denied")])}
    await #expect(throws:SQLFailure.self) {try await server.catalog("SELECT 1;",database:"master")}
    #expect(server.online && checks == 0)
    server.startupError=nil
    server.asyncCatalogFixture={_ in server.generation=UUID();throw lost}
    await #expect(throws:SQLFailure.self) {try await server.catalog("SELECT 1;",database:"master")}
    #expect(server.online && checks == 0 && server.startupError == nil)
  }
  @Test func executionCapturesAllReadBudgetsBeforeTheAsyncTaskStarts() async throws {
    let doc=readDocument()
    doc.limits.rows=100;doc.limits.totalBytes=16384;doc.limits.cellBytes=2048
    doc.limits.resultSets=4;doc.limits.timeout=9;doc.limits.diskResults=true
    var budgets:[Limits]=[]
    doc.executionFixture={_,limits in budgets.append(limits);return output(rows:limits.rows)}
    doc.execute()
    // External observers/preferences can change while the execution task is queued.
    doc.limits=ResultReadPreferences.limits(rows:10)
    await doc.task?.value
    let first=try #require(budgets.first)
    #expect(first.rows == 100 && first.totalBytes == 16384 && first.cellBytes == 2048)
    #expect(first.resultSets == 4 && first.timeout == 9 && first.diskResults)
    #expect(doc.results.map { $0.values.count } == [100,100] && doc.lastExecutedReadLimit == 100)
    doc.execute(repeatRead:true);await doc.task?.value
    #expect(budgets.map(\.rows) == [100,10])
    #expect(doc.results.map { $0.values.count } == [10,10] && doc.lastExecutedReadLimit == 10)
  }
  @Test func limitMenuAndCustomReloadSelectWhileManualRunStillUsesNewLimit() async throws {
    _=NSApplication.shared
    let doc=readDocument();doc.limits=ResultReadPreferences.limits(rows:100)
    var requests:[Int]=[]
    doc.executionFixture={_,limits in requests.append(limits.rows);return output(rows:limits.rows)}
    let controller=QueryController(document:doc);_=controller.view
    doc.execute();await doc.task?.value;controller.update()
    let popup=try #require(descendants(controller.view).compactMap {$0 as? NSPopUpButton}.first {$0.accessibilityIdentifier() == "gridRowOptions"})
    let limit=try #require(popup.itemArray.first {$0.identifier?.rawValue == "gridReadChoices" && $0.tag == 10})
    #expect(NSApp.sendAction(try #require(limit.action),to:limit.target,from:limit))
    await doc.task?.value;controller.update()
    #expect(requests == [100,10] && doc.results.map {$0.values.count} == [10,10])
    #expect(doc.limits.rows == 10 && popup.accessibilityHelp() == popup.toolTip)
    controller.applyLoadingPreferences(rows:5,refresh:0,save:false)
    await doc.task?.value;controller.update()
    #expect(requests == [100,10,5] && doc.results.map {$0.values.count} == [5,5])
    #expect(doc.rowCount == 10 && doc.lastExecutedReadLimit == 5 && doc.sql.contains("OtherNumbers"))
    doc.execute();await doc.task?.value
    #expect(requests == [100,10,5,5])
  }
}
