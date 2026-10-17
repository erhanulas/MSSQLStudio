import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ActivityRequestTerminationUITests {
  private func request()->ActivityMonitoring.Request {
    .init(sessionID:71,requestID:0,command:"SELECT",sessionLoginTime:"2026-10-16 12:00:00.000",requestStartTime:"2026-10-16 12:01:02.003")
  }
  @Test func validSessionLockActionRemainsEnabledDuringBackgroundSampling() async throws {
    var output=Execution()
    output.results=[Rows(values:[["0x01:0","71","0","Demo","Resource","X","GRANTED","SESSION","0","reader","Host","App","recent","SELECT 1","2026-10-16 12:00:00.000","5"]]),Rows()]
    let lock=try #require(ActivityApplicationLocks.decode(output).locks.first)
    let server=ConnectedServer(profile:.init(),password:"")
    var pending:CheckedContinuation<Execution,any Error>?
    let monitor=ActivityMonitorModel(server:server,reader:{_,_ in try await withCheckedThrowingContinuation {pending=$0}})
    let action=ActivityRequestTerminationAction(monitor:monitor,model:monitor.termination,applicationLock:lock,applicationLockMode:true)
    #expect(action.actionEnabled)
    let task=Task {await monitor.load()}
    for _ in 0..<100 where pending==nil {await Task.yield()}
    #expect(monitor.loading && action.actionEnabled)
    pending?.resume(throwing:CancellationError());pending=nil;await task.value
    #expect(!monitor.loading && action.actionEnabled)
  }
  @Test func preparationIsReadOnlyAndCompletedRequestsCannotReachConfirmation() async throws {
    let server=ConnectedServer(profile:.init(),password:"")
    var statements:[String]=[]
    server.catalogFixture={sql in
      statements.append(sql)
      var output=Execution();output.results=[Rows(fields:[Field("target_valid")],values:[["1"]])];return output
    }
    let model=ActivityRequestTerminationModel(server:server,writer:{_ in Issue.record("Preflight must never write");return Execution()})
    #expect(await model.prepare(.request(request()),generation:server.generation))
    #expect(statements.count==1 && !statements[0].contains("KILL 71;"))
    #expect(model.phase.contains("doğrulanıyor") && !model.busy)
    server.catalogFixture=nil
    server.asyncCatalogFixture={_ in throw SQLFailure("Request completed")}
    #expect(!(await model.prepare(.request(request()),generation:server.generation)))
    #expect(model.failed && model.message.contains("Request completed") && !model.needsRefresh)
    server.asyncCatalogFixture={_ in throw SQLFailure("Changed",diagnostics:[Diagnostic(state:"42000",code:51081,message:"Completed")])}
    #expect(!(await model.prepare(.request(request()),generation:server.generation)))
    #expect(model.needsRefresh)
  }
  @Test func confirmationShowsFullColoredSQLAndFitsBothThemes() async throws {
    _=NSApplication.shared
    let previous=StudioTheme.mode;defer {StudioTheme.apply(previous)}
    var value=request()
    value.sql=String(repeating:"SELECT N'Preview'; -- context\n",count:40)+"-- LAST_MARKER"
    value.database="DemoDB";value.host="HOST";value.login="reader";value.program="Client App"
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let host=NSHostingController(rootView:ActivityTerminationConfirmation(target:.request(value),serverName:"Development Server",cancel:{},confirm:{}))
      host.sizingOptions=[]
      let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
      window.setContentSize(NSSize(width:680,height:660));window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
      defer {window.close()}
      try await Task.sleep(for:.milliseconds(50));host.view.layoutSubtreeIfNeeded()
      func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
      let preview=try #require(descendants(host.view).compactMap {$0 as? SQLPreviewView}.first)
      #expect(preview.textView.string==value.sql && preview.textView.string.hasSuffix("-- LAST_MARKER"))
      #expect(!preview.textView.isEditable && preview.textView.textLayoutManager != nil)
      let color=preview.textView.textContentStorage?.textStorage?.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor
      #expect(color != StudioTheme.editorText)
      let rect=host.view.convert(preview.bounds,from:preview)
      #expect(rect.width>600 && rect.height>=160 && host.view.bounds.contains(rect))
      let image=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds));host.view.cacheDisplay(in:host.view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-termination-confirmation-"+theme+".png"))
    }
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
