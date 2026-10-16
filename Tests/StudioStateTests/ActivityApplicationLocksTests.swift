import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ActivityApplicationLocksUITests {
  private func locks()->Execution {
    var result=Execution()
    result.results=[Rows(values:[["0x01:0","71","0","Demo","dbo:ApplicationResourceHash","X","GRANTED","SESSION","0","reader","HOST","App","recent","EXEC dbo.Work;"],["0x02:0","72","0","Demo","dbo:ApplicationResourceHash","X","WAIT","TRANSACTION","101","reader","HOST","App","current","EXEC sys.sp_getapplock;"]]),Rows()]
    result.results[0]=Rows(values:result.results[0].values.map {$0+["2026-10-16 12:00:00.000","5"]})
    return result
  }
  private func overview()->Execution {
    var result=Execution();result.results=[Rows(values:[["2026-10-16T12:00:00Z","start","20","1","1000","0"]])];return result
  }
  @Test func lockReadIsOptInAndAbandonedSelectionCannotPublishLateRows() async throws {
    let server=ConnectedServer(profile:.init(),password:"")
    var calls:[String]=[]
    var pending:CheckedContinuation<Execution,any Error>?
    let model=ActivityMonitorModel(server:server,reader:{sql,limits in
      calls.append(sql)
      if sql==ActivityApplicationLocks.sql {
        #expect(limits.rows==101 && limits.resultSets==2 && limits.totalBytes==1_000_000)
        return try await withCheckedThrowingContinuation {pending=$0}
      }
      return self.overview()
    })
    await model.load()
    #expect(!calls.contains(ActivityApplicationLocks.sql))
    let task=Task {await model.load(includeDiagnostics:true,includeApplicationLocks:true)}
    for _ in 0..<100 where pending==nil {await Task.yield()}
    #expect(pending != nil && !calls.contains(ActivityMonitoring.diagnosticsSQL))
    model.clearApplicationLocks()
    pending?.resume(returning:locks());pending=nil;await task.value
    #expect(model.applicationLocks.isEmpty && model.applicationLocksTime==nil && !model.loading)
  }
  @Test func applicationGridAndSharedTabsFitBothThemesAtMinimumWidth() async throws {
    let previous=StudioTheme.mode;defer {StudioTheme.apply(previous)}
    let server=ConnectedServer(profile:.init(),password:"")
    let model=ActivityMonitorModel(server:server,reader:{sql,_ in sql==ActivityApplicationLocks.sql ? self.locks():self.overview()})
    await model.load(includeDiagnostics:true,includeApplicationLocks:true)
    let row=try #require(model.applicationLocks.first)
    #expect(model.applicationLocks.count==2 && model.applicationLockError.isEmpty)
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let root=VStack {
        StudioTabBar(items:[.init(id:0,title:"Bloklanan",icon:"lock",count:2),.init(id:1,title:"Uzun süren",icon:"clock",count:1),.init(id:2,title:"Yedekleme",icon:"externaldrive",count:0),.init(id:3,title:"Uygulama kilitleri",icon:"app.badge",count:2)],selection:.constant(3))
        ActivityApplicationLocksPanel(model:model,initialSelection:row.id)
      }.padding(12).studioPanel()
      let host=NSHostingController(rootView:root);host.sizingOptions=[]
      let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false
      window.setContentSize(NSSize(width:920,height:480));window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
      try await Task.sleep(for:.milliseconds(80));host.view.layoutSubtreeIfNeeded()
      func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
      let table=try #require(descendants(host.view).compactMap {$0 as? NSTableView}.first)
      #expect(table.numberOfRows==2)
      let preview=try #require(descendants(host.view).compactMap {$0 as? SQLPreviewView}.first)
      #expect(host.view.convert(preview.bounds,from:preview).width>850)
      let bitmap=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds));host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-application-locks-"+theme+".png"))
      window.close()
    }
  }
}
