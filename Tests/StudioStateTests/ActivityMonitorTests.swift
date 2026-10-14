import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ActivityMonitorTests {
  private func overview(_ second:Int,health:Bool=true) -> Execution {
    let time=Date(timeIntervalSince1970:1_800_000_000+Double(second))
    let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
    let columns=["sampled_at","started_at","cpu_percent","waiting_tasks","io_bytes","batch_requests","active_requests","blocked_requests","backup_requests","open_transactions","idle_transactions","user_sessions","sql_memory_mb","available_memory_mb","memory_grants_pending","io_reads","io_writes","read_stall_ms","write_stall_ms","process_cpu_ms","logical_cpu_count"]
    var values:[String?]=[formatter.string(from:time),"start",nil,"3",String(second*1_048_576),String(second*100),"7","2","1","5","3","48","2048","8192","2",String(second*100),String(second*10),String(second*200),String(second*50),String(second*4000),"8"]
    if !health {for i in 6...14 {values[i]=nil}}
    var execution=Execution();execution.results=[Rows(fields:columns.map {Field($0)},values:[values]),Rows(values:[])]
    return execution
  }
  private func waitUntil(_ condition:()->Bool) async {
    for _ in 0..<200 where !condition() {await Task.yield()}
    #expect(condition())
  }
  @Test func hiddenPausedOfflineAndSingleFlightGuardsNeverStartExtraReads() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var reads=0,pending:CheckedContinuation<Execution,any Error>?
    let model=ActivityMonitorModel(server:server,reader:{_,_ in
      reads+=1
      return try await withCheckedThrowingContinuation {pending=$0}
    })
    model.setActivity(visible:false,paused:false);await model.load(automatic:true)
    model.setActivity(visible:true,paused:true);await model.load(automatic:true)
    #expect(reads == 0 && !model.loading)
    let first=Task {await model.load()}
    await waitUntil {pending != nil}
    await model.load();await model.load(includeDiagnostics:true)
    #expect(reads == 1 && model.loading)
    pending?.resume(returning:overview(5));pending=nil;await first.value
    #expect(model.samples.count == 1 && !model.loading)
    server.online=false;await model.load()
    #expect(reads == 1 && model.error.contains("çevrimdışı") && model.samples.count == 1)
    server.generation=UUID();await model.load()
    #expect(model.samples.isEmpty && model.diagnosticsTime == nil && reads == 1)
  }
  @Test func delayedReadsCannotPublishAfterHiddenGenerationChangeOrCancellation() async {
    for reason in 0..<3 {
      let server=ConnectedServer(profile:ServerProfile(),password:"")
      var pending:CheckedContinuation<Execution,any Error>?
      let model=ActivityMonitorModel(server:server,reader:{_,_ in try await withCheckedThrowingContinuation {pending=$0}})
      let task=Task {await model.load()}
      await waitUntil {pending != nil}
      if reason == 0 {model.setActivity(visible:false,paused:false)}
      if reason == 1 {server.generation=UUID()}
      if reason == 2 {task.cancel()}
      pending?.resume(returning:overview(5));pending=nil;await task.value
      #expect(model.samples.isEmpty && model.error.isEmpty && !model.loading)
    }
  }
  @Test func diagnosticsAreOptInBoundedAndFailureKeepsAnExplicitlyStaleTimestamp() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var sqls:[String]=[],tick=0,failDiagnostics=false
    let model=ActivityMonitorModel(server:server,reader:{sql,limits in
      sqls.append(sql)
      #expect(limits.timeout == 10 && limits.totalBytes <= 4_000_000)
      if sql == ActivityMonitoring.overviewSQL {tick+=5;#expect(limits.rows == 30 && limits.resultSets == 2);return overview(tick)}
      #expect(sql == ActivityMonitoring.diagnosticsSQL && limits.rows == 400 && limits.resultSets == 5)
      if failDiagnostics {throw SQLFailure("DBA permission denied")}
      return ObjectManagementUIFixture.catalog(sql)
    })
    await model.load()
    #expect(sqls == [ActivityMonitoring.overviewSQL] && model.diagnosticsTime == nil)
    await model.load(includeDiagnostics:true)
    #expect(model.diagnostics.blocked.count == 2 && model.diagnostics.longRunning.count == 1 && model.diagnostics.backups.count == 1)
    let oldTime=try #require(model.diagnosticsTime)
    #expect(model.diagnostics.backups.first?.percentComplete == 64.5)
    failDiagnostics=true;await model.load(includeDiagnostics:true)
    #expect(model.samples.count == 3 && model.error.isEmpty && model.diagnosticsError.contains("permission denied"))
    #expect(model.diagnosticsTime == oldTime && model.samples.last?.time != oldTime && model.diagnostics.blocked.count == 2)
    model.clearDiagnostics()
    #expect(model.diagnosticsTime == nil && model.diagnostics.blocked.isEmpty && model.diagnosticsError.isEmpty)
  }
  @Test func leavingDBADiscardsInFlightDiagnosticsWithoutLosingValidOverview() async {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var pending:CheckedContinuation<Execution,any Error>?,reads=0
    let model=ActivityMonitorModel(server:server,reader:{sql,_ in
      reads+=1
      if sql == ActivityMonitoring.overviewSQL {return overview(5)}
      return try await withCheckedThrowingContinuation {pending=$0}
    })
    let task=Task {await model.load(includeDiagnostics:true)}
    await waitUntil {pending != nil}
    model.clearDiagnostics()
    pending?.resume(returning:ObjectManagementUIFixture.catalog(ActivityMonitoring.diagnosticsSQL));pending=nil;await task.value
    #expect(reads == 2 && model.samples.count == 1 && model.diagnosticsTime == nil && model.diagnostics.backups.isEmpty)
  }
  @Test func disconnectReportedBeforeCatalogThrowsStillMarksOldDataAndClearsDBA() async {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var fail=false,reads=0
    let model=ActivityMonitorModel(server:server,reader:{sql,_ in
      reads+=1
      if fail {server.online=false;throw SQLFailure("[08S01] Communication link failure")}
      return sql == ActivityMonitoring.overviewSQL ? overview(5):ObjectManagementUIFixture.catalog(sql)
    })
    await model.load(includeDiagnostics:true)
    #expect(model.samples.count == 1 && model.diagnostics.blocked.count == 2)
    fail=true;await model.load(includeDiagnostics:true)
    #expect(!server.online && model.error.contains("08S01") && model.error.contains("güncel değil"))
    #expect(model.samples.count == 1 && model.diagnosticsTime == nil && model.diagnostics.blocked.isEmpty)
    await model.load(includeDiagnostics:true)
    #expect(reads == 3 && !model.loading)
  }
  @Test func explorerDisconnectWhilePausedInvalidatesDBAWithoutAnyRead() async {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var reads=0
    let model=ActivityMonitorModel(server:server,reader:{sql,_ in reads+=1;return sql == ActivityMonitoring.overviewSQL ? overview(5):ObjectManagementUIFixture.catalog(sql)})
    await model.load(includeDiagnostics:true)
    model.setActivity(visible:true,paused:true)
    #expect(model.diagnostics.blocked.count == 2 && reads == 2)
    server.online=false;model.connectionChanged()
    #expect(model.error.contains("çevrimdışı") && model.samples.count == 1 && model.diagnosticsTime == nil && model.diagnostics.blocked.isEmpty)
    #expect(reads == 2)
    server.generation=UUID();server.online=true;model.connectionChanged()
    #expect(model.samples.isEmpty && model.error.isEmpty && reads == 2 && model.paused)
  }
  @Test func generationChangesDuringReadClearPreviousEndpointHistoryImmediately() async {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var delay=false,pending:CheckedContinuation<Execution,any Error>?
    let model=ActivityMonitorModel(server:server,reader:{sql,_ in
      if delay {return try await withCheckedThrowingContinuation {pending=$0}}
      return sql == ActivityMonitoring.overviewSQL ? overview(5):ObjectManagementUIFixture.catalog(sql)
    })
    await model.load(includeDiagnostics:true)
    #expect(model.samples.count == 1 && model.diagnostics.blocked.count == 2)
    delay=true;let task=Task {await model.load()};await waitUntil {pending != nil}
    server.generation=UUID()
    pending?.resume(returning:overview(10));pending=nil;await task.value
    #expect(model.samples.isEmpty && model.diagnosticsTime == nil && model.diagnostics.blocked.isEmpty && model.error.isEmpty && !model.loading)
  }
  @Test func fullFifteenMinuteWindowRetainsFiveSecondSamplesAndMissingHealth() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var second=0
    let model=ActivityMonitorModel(server:server,reader:{sql,_ in
      #expect(sql == ActivityMonitoring.overviewSQL);second+=5;return overview(second,health:second != 1000)
    })
    for _ in 0..<200 {await model.load()}
    #expect(model.samples.count == 181)
    #expect(model.samples.last!.time.timeIntervalSince(model.samples.first!.time) == 900)
    #expect(ActivityChartPoint.window(model.samples,minutes:5).count == 61)
    #expect(ActivityChartPoint.window(model.samples,minutes:15).count == 181)
    #expect(model.samples.last?.health.openTransactions == nil && ActivityFormat.count(model.samples.last?.health.openTransactions) == "—")
    #expect(model.samples.last?.readLatencyMS == 2 && model.samples.last?.writeLatencyMS == 5)
    #expect(ActivityFormat.memory(nil) == "—" && ActivityFormat.memory(2048) == "2 GiB")
    #expect(ActivityFormat.number(.infinity) == "—" && ActivityFormat.number(.nan) == "—")
    #expect(ActivityFormat.duration(125000) == "2 dk 5 sn")
  }
  @Test func chartSegmentsAndHoverKeepExactSampleValuesAcrossMissingData() throws {
    let start=Date(timeIntervalSince1970:1_800_000_000)
    let values:[Double?]=[10,nil,30,40]
    let samples=values.enumerated().map {index,value in
      ActivityMonitoring.Sample(time:start.addingTimeInterval(Double(index*5)),beginsSequence:index == 0 || index == 3,cpu:value,waiting:nil,megabytesPerSecond:nil,batchesPerSecond:nil)
    }
    let points=ActivityChartPoint.points(samples,value:{$0.cpu})
    #expect(points.count == 3 && points[0].segment != points[1].segment && points[1].segment != points[2].segment)
    let hovered=try #require(ActivityChartPoint.nearest(points,to:start.addingTimeInterval(11)))
    #expect(hovered.value == 30 && hovered.time == start.addingTimeInterval(10))
    #expect(ActivityChartPoint.nearest([],to:start) == nil)
  }
  @Test func blockerChainIncludesSleepingHeadAndOfflineInvalidatesItsSQL() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var reads=0
    let model=ActivityMonitorModel(server:server,reader:{sql,_ in reads+=1;return sql == ActivityMonitoring.overviewSQL ? overview(5):ObjectManagementUIFixture.catalog(sql)})
    await model.load(includeDiagnostics:true)
    let blocked=try #require(model.diagnostics.blocked.last)
    let chain=model.diagnostics.blockingChain(for:blocked)
    #expect(chain.sessionIDs == [63,71,72] && chain.termination == .root)
    #expect(model.diagnostics.blockingContexts.first?.status == "sleeping")
    #expect(model.diagnostics.blockingContexts.first?.sqlSource == .recent)
    #expect(model.diagnostics.blockingContexts.first?.openTransactions == 1)
    server.online=false;model.connectionChanged()
    #expect(model.diagnostics.blockingContexts.isEmpty && model.diagnosticsTime == nil && reads == 2)
  }
  @Test func multipleActiveBlockerRequestsRequireAnExplicitSQLChoice() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    let model=ActivityMonitorModel(server:server,reader:{sql,_ in
      if sql == ActivityMonitoring.overviewSQL {return overview(5)}
      var result=ObjectManagementUIFixture.catalog(sql)
      let row:[String?]=["63","0","2","DemoDB","running","SELECT","0",nil,"0",nil,"1","user","host","app","current","SELECT N'explicit-first-request';"]
      var second=row;second[1]="1";second[15]="SELECT N'explicit-second-request';"
      result.results[3]=Rows(values:[row,second])
      return result
    })
    await model.load(includeDiagnostics:true)
    #expect(model.diagnostics.blockingContexts.count == 2)
    func descendants(_ view:NSView) -> [NSView] {[view]+view.subviews.flatMap(descendants)}
    for chosen in [nil,"63:1"] as [String?] {
      let panel=ActivityMonitorPanel(model:model,initialMode:2,initialSelectedRequest:"71:0",initialSelectedBlockingContext:chosen,openTable:{})
      let host=NSHostingController(rootView:panel);host.sizingOptions=[]
      let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:920,height:700))
      defer {window.close()}
      try await Task.sleep(for:.milliseconds(100));host.view.layoutSubtreeIfNeeded()
      let texts=descendants(host.view).compactMap {$0 as? SQLPreviewView}.compactMap {($0.textView as? NSTextView)?.string}
      #expect(texts.count == 2 && texts.contains(model.diagnostics.blocked.first!.sql))
      #expect(!texts.contains("SELECT N'explicit-first-request';"))
      if chosen == nil {#expect(texts.contains { $0.contains("Gösterilecek SQL yok") })}
      else {#expect(texts.contains("SELECT N'explicit-second-request';"))}
    }
  }
  @Test func populatedViewsAndSelectedDBAFitSupportedMinimumInBothThemes() async throws {
    _=NSApplication.shared
    let old=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(old ?? "light")}
    func descendants(_ view:NSView) -> [NSView] {[view]+view.subviews.flatMap(descendants)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      for state in 0..<8 {
        #expect(StudioTheme.dark == (theme == "dark"))
        let server=ConnectedServer(profile:ServerProfile(name:"Offline populated fixture"),password:"")
        var tick=0,failDiagnostics=false,failOverview=false
        let model=ActivityMonitorModel(server:server,reader:{sql,_ in
          if sql == ActivityMonitoring.overviewSQL {
            if failOverview {throw SQLFailure("[42000] Sunucu genel ölçümü doğrulanamadı; son ölçümler eski olabilir.")}
            tick+=5;var result=overview(tick)
            if state == 5 || state == 7 {result.results[1]=Rows(values:[["Bellek","VIEW SERVER PERFORMANCE STATE yetkisi gerekli."],["Dosya gecikmesi","Sunucu bu fiziksel dosyalar için okuma ve yazma gecikmesi bilgilerini sağlayamadı."]])}
            return result
          }
          if failDiagnostics {throw SQLFailure("DBA görüntüleme yetkisi doğrulanamadı.")}
          var result=ObjectManagementUIFixture.catalog(sql)
          if state == 5 || state == 7 {result.results[4]=Rows(values:[["Uzun süren","Bu bölüm için görüntüleme yetkisi eksik."]])}
          return result
        })
        for _ in 0..<3 {await model.load(includeDiagnostics:true)}
        if state >= 6 {failDiagnostics=true;await model.load(includeDiagnostics:true)}
        if state == 7 {failOverview=true;await model.load(includeDiagnostics:true)}
        let mode=state<2 ? state:2,kind=state == 3 ? 1:state>=4 ? 2:0
        let rows=kind == 0 ? model.diagnostics.blocked:kind == 1 ? model.diagnostics.longRunning:model.diagnostics.backups
        let panel=ActivityMonitorPanel(model:model,initialMode:mode,initialDiagnosticKind:kind,initialSelectedRequest:mode == 2 ? rows.first?.id:nil,openTable:{})
        let host=NSHostingController(rootView:panel);host.sizingOptions=[]
        let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
        window.appearance=NSAppearance(named:theme == "dark" ? .darkAqua:.aqua)
        let size=NSSize(width:920,height:700);window.setContentSize(size)
        defer {window.close()}
        try await Task.sleep(for:.milliseconds(100))
        host.view.frame=NSRect(origin:.zero,size:size);host.view.layoutSubtreeIfNeeded()
        host.view.displayIfNeeded()
        #expect(StudioTheme.dark == (theme == "dark"))
        #expect(host.view.bounds.size == size)
        let views=descendants(host.view)
        for control in views.compactMap({$0 as? NSControl}) where !control.isHiddenOrHasHiddenAncestor {
          let rect=host.view.convert(control.bounds,from:control)
          #expect(rect.minX>=0 && rect.maxX<=size.width+1 && rect.minY>=0 && rect.maxY<=size.height+1,"\(theme) state\(state) control \(rect)")
        }
        if mode == 2 {
          let preview=try #require(views.compactMap {$0 as? SQLPreviewView}.first)
          let previewRect=host.view.convert(preview.bounds,from:preview)
          #expect(previewRect.width>=(kind == 0 ? 350:700) && previewRect.height>=100)
          #expect(previewRect.minX>=0 && previewRect.maxX<=920 && previewRect.minY>=0 && previewRect.maxY<=700,"\(theme) state\(state) SQL \(previewRect)")
          let table=try #require(views.compactMap {$0 as? NSTableView}.first)
          #expect(table.numberOfRows == rows.count && table.selectedRowIndexes == IndexSet(integer:0))
          let tableScroll=try #require(table.enclosingScrollView)
          let tableRect=host.view.convert(tableScroll.bounds,from:tableScroll)
          #expect(tableRect.height>=120 && tableRect.minX>=0 && tableRect.maxX<=920 && tableRect.minY>=0 && tableRect.maxY<=700,"\(theme) state\(state) table \(tableRect)")
          #expect(previewRect.maxY<=tableRect.minY || tableRect.maxY<=previewRect.minY)
          #expect(views.compactMap {$0 as? SQLPreviewView}.contains {(($0.textView as? NSTextView)?.string) == rows.first?.sql})
        }
        if let rep=host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds) {
          host.view.cacheDisplay(in:host.view.bounds,to:rep)
          let corner=try #require(rep.colorAt(x:5,y:5)?.usingColorSpace(.deviceRGB))
          let brightness=(corner.redComponent+corner.greenComponent+corner.blueComponent)/3
          #expect(theme == "dark" ? brightness<0.4:brightness>0.7,"Bitmap must render the requested theme, not an old frame")
          var colors=Set<Int>()
          for y in stride(from:0,to:rep.pixelsHigh,by:16) {
            for x in stride(from:0,to:rep.pixelsWide,by:16) {
              if let color=rep.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) {
                colors.insert((Int(color.redComponent*255)<<16)|(Int(color.greenComponent*255)<<8)|Int(color.blueComponent*255))
              }
            }
          }
          #expect(colors.count>20,"Bitmap must contain populated controls/text rather than an empty surface")
          let data=try #require(rep.representation(using:.png,properties:[:]))
          try data.write(to:URL(fileURLWithPath:"/tmp/mssql-activity-state\(state)-\(theme).png"))
          if state == 0 || state == 4 {try data.write(to:URL(fileURLWithPath:"/tmp/mssql-activity-\(state == 0 ? "populated":"dba")-\(theme).png"))}
        }
      }
    }
  }
}
