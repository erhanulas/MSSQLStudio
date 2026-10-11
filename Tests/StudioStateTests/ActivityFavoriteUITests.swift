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
  @Test func sharedPaginationMenuKeepsReadLimitSeparateAndNeverExecutes() throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Read prefs")
    doc.limits=ResultReadPreferences.limits(rows:1_234_567)
    doc.sql="SELECT 1";doc.state = .ready
    doc.results=[Rows(fields:[Field("Id",type:4)],values:(0..<1200).map {[String($0)]})]
    let controller=QueryController(document:doc)
    let window=NSWindow(contentViewController:controller);window.isReleasedWhenClosed=false
    defer {window.close()};controller.view.frame=NSRect(x:0,y:0,width:830,height:680);controller.view.layoutSubtreeIfNeeded()
    let popup=try #require(descendants(controller.view).compactMap {$0 as? NSPopUpButton}.first {$0.accessibilityIdentifier() == "gridRowOptions"})
    let toolbar=try #require(descendants(controller.view).first {$0.accessibilityIdentifier() == "gridToolbar"})
    #expect(popup.isDescendant(of:toolbar) && popup.title.contains(1_234_567.formatted()))
    #expect(!descendants(controller.view).contains {$0.accessibilityIdentifier() == "gridReadOptions"})
    let rect=controller.view.convert(popup.bounds,from:popup)
    #expect(rect.width == 128 && rect.maxX<=830 && rect.minX>=0)
    func choose(_ section:String,_ value:Int) throws {
      let item=try #require(popup.itemArray.first {$0.identifier?.rawValue == section}?.submenu?.items.first {$0.tag == value && !$0.isSeparatorItem})
      #expect(NSApp.sendAction(try #require(item.action),to:item.target,from:item))
    }
    try choose("gridPageChoices",100)
    let grid=try #require(controller.children.compactMap {$0 as? ResultController}.first)
    #expect(grid.pageCount == 100 && doc.limits.rows == 1_234_567)
    try choose("gridReadChoices",10)
    #expect(doc.limits.rows == 10 && grid.pageCount == 100 && grid.result.values.count == 1200)
    #expect(doc.lastExecutedSQL == nil && doc.sql == "SELECT 1")
    controller.applyLoadingPreferences(rows:5_000_000,page:77,refresh:10,save:false)
    #expect(doc.limits.rows == 5_000_000 && doc.initialRefreshSeconds == 10 && doc.lastExecutedSQL == nil)
    #expect(popup.itemArray.first {$0.identifier?.rawValue == "gridPageChoices"}?.submenu?.items.contains {$0.tag == 77 && $0.state == .on} == true)
    controller.applyLoadingPreferences(rows:0,page:100,refresh:10,save:false)
    #expect(doc.limits.rows == 5_000_000)
  }
  @Test func autoRefreshHasVisiblePresetsPendingStateAndEditingGuards() throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Auto refresh")
    doc.initialRefreshSeconds=0;doc.results=[Rows(fields:[Field("Id")],values:[["1"]])]
    let controller=QueryController(document:doc);_=controller.view
    let button=try #require(descendants(controller.view).compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier() == "gridAutoRefresh"})
    #expect(button.isEnabled && button.state == .off && button.toolTip?.contains("Kapalı") == true)
    let ten=try #require(button.menu?.items.first {$0.tag == 10})
    #expect(NSApp.sendAction(try #require(ten.action),to:ten.target,from:ten))
    #expect(doc.initialRefreshSeconds == 10 && doc.lastExecutedSQL == nil && button.state == .on)
    #expect(button.toolTip?.contains("Başarılı SELECT sonrası") == true)
    #expect(button.menu?.items.first {$0.tag == 10}?.state == .on)
    controller.setAutoRefresh(17)
    #expect(button.menu?.items.contains {$0.tag == 17 && $0.state == .on} == true)
    controller.setAutoRefresh(0)
    #expect(button.state == .off && doc.initialRefreshSeconds == 0)
    doc.state = .running;controller.update();controller.setAutoRefresh(5)
    #expect(!button.isEnabled && doc.initialRefreshSeconds == 0)
    doc.state = .ready
    let grid=try #require(controller.children.compactMap {$0 as? ResultController}.first)
    grid.editDefinition=TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int")],primaryKey:["Id"])
    controller.update();controller.setAutoRefresh(5)
    #expect(!button.isEnabled && doc.initialRefreshSeconds == 0)
    grid.discardEdits();controller.update();controller.setAutoRefresh(3601)
    #expect(doc.initialRefreshSeconds == 0)
  }
  @Test func editorFavoriteStarUsesItsOwnDocumentAndDisablesBlankSQL() throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"SavedDB",title:"Named SQL")
    let controller=QueryController(document:doc)
    var requested:QueryDocument?
    controller.favoriteRequested={requested=$0};_=controller.view
    let button=try #require(descendants(controller.view).compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier() == "queryFavorite"})
    #expect(!button.isEnabled && button.toolTip?.isEmpty == false && button.accessibilityLabel()?.isEmpty == false)
    doc.sql="SELECT .00000000, NULL";controller.update()
    #expect(button.isEnabled)
    #expect(NSApp.sendAction(try #require(button.action),to:button.target,from:button))
    #expect(requested === doc && requested?.database == "SavedDB" && requested?.sql == doc.sql && doc.lastExecutedSQL == nil)
    doc.sql=" \n  ";controller.update();#expect(!button.isEnabled)
  }
  @Test func explorerFavoritesAreScopedLocalAndUpdateWithoutLosingSelection() async throws {
    _=NSApplication.shared
    let directory=URL(fileURLWithPath:"/tmp/favorite-tree-\(UUID())");defer {try? FileManager.default.removeItem(at:directory)}
    let state=StudioState();state.recoveryEnabled=false;state.historyEnabled=false
    state.favorites=FavoriteQueriesModel(url:directory.appendingPathComponent("favorites.json"))
    let a=ConnectedServer(profile:ServerProfile(name:"A",database:"DefaultA"),password:""),b=ConnectedServer(profile:ServerProfile(name:"B"),password:"")
    a.online=false;b.online=false;state.servers=[a,b]
    var requests=0
    a.catalogFixture={_ in requests+=1;return Execution()};b.catalogFixture=a.catalogFixture
    let global=try FavoriteQuery(name:"Global",sql:"SELECT 1",scope:.global)
    let connection=try FavoriteQuery(name:"Connection",sql:"SELECT 2",scope:.connection,serverID:a.id)
    var database=try FavoriteQuery(name:"Saved DB",sql:"DELETE FROM dbo.Important;",scope:.database,serverID:a.id,database:"ExactDB")
    for item in [global,connection,database] {try await state.favorites.save(item)}
    let host=WorkbenchController(state:state);_=host.view
    let outline=try #require(descendants(host.view).compactMap {$0 as? NSOutlineView}.first)
    let rootA=try #require(outline.item(atRow:0) as? TreeNode)
    let folder=try #require(rootA.children.first {if case .favorites=$0.kind {return true};return false})
    outline.expandItem(folder)
    let dbGroup=try #require(folder.children.first {$0.favoriteScope == .database})
    outline.expandItem(dbGroup)
    let node=try #require(dbGroup.children.first)
    outline.selectRowIndexes(IndexSet(integer:outline.row(forItem:node)),byExtendingSelection:false)
    let rootB=try #require((0..<outline.numberOfRows).compactMap {outline.item(atRow:$0) as? TreeNode}.first {if case .server=$0.kind {return $0.server === b};return false})
    let folderB=try #require(rootB.children.first {if case .favorites=$0.kind {return true};return false})
    #expect(folderB.children.flatMap(\.children).compactMap(\.favorite).map(\.id) == [global.id])
    database.name="Renamed";database.sql="SELECT -0.25, NULL";try await state.favorites.save(database)
    #expect(dbGroup.children.first === node && node.title == "Renamed" && node.favorite?.sql == database.sql)
    #expect(outline.isItemExpanded(dbGroup) && outline.item(atRow:outline.selectedRow) as? TreeNode === node)
    host.openExplorerFavorite(node)
    let doc=try #require(state.active)
    #expect(doc.database == "ExactDB" && doc.server === a && doc.sql == database.sql && doc.savedText == database.sql)
    #expect(!doc.runAfterConnect && doc.lastExecutedSQL == nil && requests == 0)
    await state.favorites.remove(database.id)
    #expect(!folder.children.contains {$0.favoriteScope == .database} && requests == 0)
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
        let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;window.setContentSize(size)
        try await Task.sleep(for:.milliseconds(150))
        // Test the requested viewport without macOS shrinking it to the CI display's 642 pt height.
        // Keeping layout windows offscreen also avoids stealing a different suite's native field editor.
        host.view.frame=NSRect(origin:.zero,size:size);host.view.layoutSubtreeIfNeeded()
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
