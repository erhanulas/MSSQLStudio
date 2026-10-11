import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ActivityFavoriteUITests {
  func descendants(_ view:NSView) -> [NSView] {[view]+view.subviews.flatMap(descendants)}
  @Test func runButtonHasInsetContentAndNativeIconText() throws {
    let b=StudioToolbarButton(symbol:"play.fill",label:"Çalıştır",tone:.success,title:"Çalıştır",width:88,prominent:true)
    let cell=try #require(b.cell as? StudioToolbarButtonCell)
    let rect=cell.contentFrame(NSRect(x:0,y:0,width:88,height:26))
    #expect(rect.minX == 10 && rect.maxX == 78 && rect.minY == 3 && rect.maxY == 23)
    #expect(b.image != nil && b.title == "Çalıştır" && b.imagePosition == .imageLeading)
    #expect(b.toolTip == "Çalıştır" && b.accessibilityLabel() == "Çalıştır")
  }
  @Test func favoritesOpenTheirSavedTargetWithoutRunningSQL() throws {
    let state=StudioState();state.recoveryEnabled=false;state.historyEnabled=false
    let a=ConnectedServer(profile:ServerProfile(name:"A"),password:""),b=ConnectedServer(profile:ServerProfile(name:"B"),password:"")
    a.online=false;b.online=false;state.servers=[a,b]
    let sql="DELETE FROM dbo.Important; -- opening must not execute"
    let f=try FavoriteQuery(name:"Named query",sql:sql,scope:.database,serverID:a.id,database:"SavedDB")
    let doc=try state.openFavorite(f,contextServerID:b.id,contextDatabase:"WrongDB")
    #expect(doc.server === a && doc.database == "SavedDB" && doc.title == f.name)
    #expect(doc.sql == sql && doc.savedText == sql && !doc.runAfterConnect && doc.lastExecutedSQL == nil)
    let global=try FavoriteQuery(name:"Global",sql:"SELECT 1",scope:.global)
    let globalDoc=try state.openFavorite(global,contextServerID:b.id,contextDatabase:"ChosenDB")
    #expect(globalDoc.server === b && globalDoc.database == "ChosenDB")
    #expect(throws:SQLFailure.self) {try state.openFavorite(global,contextServerID:nil,contextDatabase:"ChosenDB")}
    state.servers=[b]
    #expect(throws:SQLFailure.self) {try state.openFavorite(f,contextServerID:b.id,contextDatabase:"Other")}
    #expect(state.documents.count == 2)
  }
  @Test func activityModelRetainsHistoryOnFailureAndStartsANewRateSequence() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var tick=0
    server.catalogFixture={_ in tick+=1;var e=Execution();e.results=[Rows(values:[["2026-10-11T08:00:\(String(format:"%02d",tick*5))Z","start","25","3",String(tick*10_485_760),String(tick*100)]])];return e}
    let model=ActivityMonitorModel(server:server)
    await model.load();await model.load()
    #expect(model.samples.count == 2 && model.samples.last?.megabytesPerSecond == 2)
    server.catalogFixture={_ in var e=Execution();e.partial=true;return e}
    await model.load();#expect(!model.error.isEmpty && !model.loading && model.samples.count == 2)
    server.catalogFixture={_ in var e=Execution();e.results=[Rows(values:[["2026-10-11T08:00:20Z","start",nil,nil,"40000000","400"]])];return e}
    await model.load()
    #expect(model.error.isEmpty && model.samples.last?.cpu == nil && model.samples.last?.batchesPerSecond == nil)
    #expect(model.samples.last?.beginsSequence == true)
    let points=ActivityChartPoint.points(model.samples,value:{$0.cpu})
    #expect(points.count == 2)
    model.breakSequence()
  }
  @Test func visibleReadLimitStaysAboveGridAndMatchesQueryWithoutExecuting() throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Read prefs")
    doc.limits=ResultReadPreferences.limits(rows:1_234_567)
    doc.sql="SELECT 1";doc.state = .ready
    let controller=QueryController(document:doc)
    let window=NSWindow(contentViewController:controller);window.isReleasedWhenClosed=false;window.setContentSize(.init(width:830,height:680))
    defer {window.close()};controller.view.layoutSubtreeIfNeeded()
    let button=try #require(descendants(controller.view).compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier() == "gridReadOptions"})
    #expect(button.title == "Okuma: \(1_234_567.formatted())")
    let toolbar=try #require(descendants(controller.view).first {$0.accessibilityIdentifier() == "gridToolbar"})
    #expect(!button.isDescendant(of:toolbar))
    let rect=controller.view.convert(button.bounds,from:button)
    #expect(rect.width == 160 && rect.maxX<=830 && rect.minX>=0)
    #expect(doc.lastExecutedSQL == nil && doc.sql == "SELECT 1")
    controller.applyPageSize(250)
    #expect(button.toolTip?.contains("250") == true && doc.limits.rows == 1_234_567)
    controller.applyLoadingPreferences(rows:5_000_000,page:100,refresh:10,save:false)
    #expect(doc.limits.rows == 5_000_000 && doc.initialRefreshSeconds == 10 && doc.lastExecutedSQL == nil)
    #expect(button.toolTip?.contains("10 sn") == true)
    controller.applyLoadingPreferences(rows:0,page:100,refresh:10,save:false)
    #expect(doc.limits.rows == 5_000_000)
  }
  @Test func chartsAndFavoriteFormsRenderAtSupportedMinimumInBothThemes() async throws {
    _=NSApplication.shared
    let old=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(old ?? "light")}
    let server=ConnectedServer(profile:ServerProfile(name:"Offline fixture"),password:"");server.online=false;server.catalogFixture=ObjectManagementUIFixture.catalog
    let dir=URL(fileURLWithPath:"/tmp/favorite-form-\(UUID())");defer {try? FileManager.default.removeItem(at:dir)}
    let state=StudioState();state.servers=[server];state.recoveryEnabled=false
    let model=FavoriteQueriesModel(url:dir.appendingPathComponent("favorites.json"))
    try await model.save(FavoriteQuery(name:"Günlük satış",sql:"SELECT N'İstanbul', 0.00000000;",scope:.database,serverID:server.id,database:"Sales"))
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let panels:[(String,AnyView,NSSize)]=[
        ("activity",AnyView(ActivityMonitorPanel(server:server,openTable:{})),.init(width:920,height:700)),
        ("favorites",AnyView(FavoriteQueriesPanel(state:state,model:model,contextServerID:server.id,contextDatabase:"Sales")),.init(width:900,height:660)),
        ("favorite-editor",AnyView(FavoriteQueryEditor(model:model,servers:[server],contextServerID:server.id,database:"Sales",sql:"SELECT 1",close:{})),.init(width:720,height:660))]
      for (name,panel,size) in panels {
        let host=NSHostingController(rootView:panel);host.sizingOptions=[]
        let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;window.setContentSize(size);window.orderFront(nil)
        try await Task.sleep(for:.milliseconds(150));host.view.layoutSubtreeIfNeeded()
        #expect(host.view.bounds.size == size)
        for control in descendants(host.view).compactMap({$0 as? NSControl}) where !control.isHiddenOrHasHiddenAncestor {
          let rect=host.view.convert(control.bounds,from:control)
          #expect(rect.minX>=0 && rect.maxX<=size.width+1 && rect.minY>=0 && rect.maxY<=size.height+1,"\(name): \(rect)")
        }
        if let rep=host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds) {
          host.view.cacheDisplay(in:host.view.bounds,to:rep)
          try rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-\(name)-\(theme).png"))
        }
        window.close()
      }
    }
  }
}
