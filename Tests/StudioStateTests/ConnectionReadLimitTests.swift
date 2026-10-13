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
  @Test func lowerReadLimitAppliesToRefreshAndRunAndExplainsTheExistingSnapshot() async throws {
    _=NSApplication.shared
    let doc=readDocument();doc.limits=ResultReadPreferences.limits(rows:100)
    var requests:[Int]=[]
    doc.executionFixture={_,limits in requests.append(limits.rows);return output(rows:limits.rows)}
    let controller=QueryController(document:doc);_=controller.view
    doc.execute();await doc.task?.value;controller.update()
    let popup=try #require(descendants(controller.view).compactMap {$0 as? NSPopUpButton}.first {$0.accessibilityIdentifier() == "gridRowOptions"})
    let limit=try #require(popup.itemArray.first {$0.identifier?.rawValue == "gridReadChoices"}?.submenu?.items.first {$0.tag == 10})
    #expect(NSApp.sendAction(try #require(limit.action),to:limit.target,from:limit))
    #expect(requests == [100] && doc.results.map {$0.values.count} == [100,100])
    #expect(doc.limits.rows == 10 && popup.toolTip?.contains("Son okuma sınırı: 100") == true)
    #expect(popup.accessibilityHelp() == popup.toolTip)
    let refresh=try #require(descendants(controller.view).compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier() == "refreshResults"})
    let action=try #require(refresh.action)
    #expect(refresh.isEnabled && NSApp.sendAction(action,to:refresh.target,from:refresh))
    await doc.task?.value;controller.update()
    #expect(requests == [100,10] && doc.results.map {$0.values.count} == [10,10])
    #expect(popup.toolTip?.contains("Son okuma sınırı:") == false)
    controller.applyLoadingPreferences(rows:5,page:100,refresh:0,save:false)
    doc.execute();await doc.task?.value;controller.update()
    #expect(requests == [100,10,5] && doc.results.map {$0.values.count} == [5,5])
    #expect(doc.rowCount == 10 && doc.lastExecutedReadLimit == 5 && doc.sql.contains("OtherNumbers"))
  }
}
