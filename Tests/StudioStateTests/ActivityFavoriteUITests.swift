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
  @Test func activityWindowsStayScopedToTheirServerWithoutChangingTheQuery() throws {
    _=NSApplication.shared
    let state=StudioState();state.recoveryEnabled=false;state.historyEnabled=false
    let a=ConnectedServer(profile:ServerProfile(name:"Monitor A"),password:"")
    let b=ConnectedServer(profile:ServerProfile(name:"Monitor B"),password:"")
    for server in [a,b] {server.online=false;server.catalogFixture=ObjectManagementUIFixture.catalog}
    let document=QueryDocument(server:a,database:"DemoDB",title:"Keep this query")
    document.sql="SELECT N'Existing query stays unchanged';";document.savedText=document.sql
    state.servers=[a,b];state.documents=[document];state.active=document
    let controller=WorkbenchController(state:state)
    controller.showPerformanceMonitor(a)
    let monitor=try #require(NSApp.windows.first {$0.identifier?.rawValue == "activity|\(a.id)"})
    #expect(monitor.contentMinSize.width >= 920 && monitor.contentMinSize.height >= 700)
    let first=try #require(NSApp.windows.first {$0.identifier?.rawValue == "activity|\(a.id)" && $0.isVisible})
    defer {for window in NSApp.windows where ["activity|\(a.id)","activity|\(b.id)"].contains(window.identifier?.rawValue ?? "") {window.close()}}
    controller.showPerformanceMonitor(a);controller.showPerformanceMonitor(b)
    let windows=NSApp.windows.filter {$0.isVisible && ($0.identifier?.rawValue.hasPrefix("activity|") ?? false)}
    #expect(windows.filter {$0.identifier?.rawValue == "activity|\(a.id)"}.count == 1)
    #expect(windows.contains {$0 === first} && windows.contains {$0.identifier?.rawValue == "activity|\(b.id)"})
    #expect(state.documents.count == 1 && state.active === document)
    #expect(document.sql == document.savedText && document.lastExecutedSQL == nil && document.database == "DemoDB")
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
    #expect(rect.width == 128 && rect.maxX<=830 && rect.minX>=0, "Pagination control frame: \(rect); alignment insets: \(popup.alignmentRectInsets)")
    func choose(_ section:String,_ value:Int) throws {
      let item=try #require(popup.itemArray.first {$0.identifier?.rawValue == section && $0.tag == value && !$0.isSeparatorItem})
      #expect(NSApp.sendAction(try #require(item.action),to:item.target,from:item))
    }
    #expect(!popup.itemArray.contains {$0.identifier?.rawValue == "gridPageChoices"})
    let grid=try #require(controller.children.compactMap {$0 as? ResultController}.first)
    #expect(grid.pageCount == 1200 && doc.limits.rows == 1_234_567)
    try choose("gridReadChoices",10)
    #expect(doc.limits.rows == 10 && grid.pageCount == 10 && grid.result.values.count == 10 && grid.loadedRowCount == 1200)
    #expect(doc.lastExecutedSQL == nil && doc.sql == "SELECT 1")
    controller.applyLoadingPreferences(rows:5_000_000,refresh:10,save:false)
    #expect(doc.limits.rows == 5_000_000 && doc.initialRefreshSeconds == 10 && doc.lastExecutedSQL == nil)
    #expect(grid.pageSize == 0 && !popup.title.contains(" · "))
    controller.applyLoadingPreferences(rows:-1,refresh:10,save:false)
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
    #expect(outline.item(atRow:outline.selectedRow) as? TreeNode === node)
    NotificationCenter.default.post(name:StudioTheme.changed,object:nil)
    #expect(outline.isItemExpanded(dbGroup) && outline.item(atRow:outline.selectedRow) as? TreeNode === node)
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
  @Test func filledFavoriteStarsRemoveOnlyTheirScopedMatchAndUpdateOtherWindows() async throws {
    _=NSApplication.shared
    let directory=URL(fileURLWithPath:"/tmp/favorite-star-\(UUID())");defer {try? FileManager.default.removeItem(at:directory)}
    let model=FavoriteQueriesModel(url:directory.appendingPathComponent("favorites.json"))
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let saved=try FavoriteQuery(name:"This DB",sql:"SELECT N'İstanbul'",scope:.database,serverID:server.id,database:"A")
    let other=try FavoriteQuery(name:"Other DB",sql:saved.sql,scope:.database,serverID:server.id,database:"B")
    try await model.save(saved);try await model.save(other)
    let doc=QueryDocument(server:server,database:"A",title:"Saved");doc.sql=saved.sql;doc.favoriteID=saved.id
    let first=QueryController(document:doc),second=QueryController(document:QueryDocument(server:server,database:"A",title:"Second"))
    second.document.sql="  "+saved.sql+" ";first.favorites=model;second.favorites=model
    func star(_ controller:QueryController) throws -> NSButton {try #require(descendants(controller.view).compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier() == "queryFavorite"})}
    let a=try star(first),b=try star(second)
    #expect(a.state == .on && b.state == .on && a.accessibilityLabel() == "Favorilerden çıkar")
    #expect(model.matching(sql:saved.sql,serverID:UUID(),database:"A") == nil)
    #expect(model.matching(sql:"SELECT N'istanbul'",serverID:server.id,database:"A") == nil)
    #expect(NSApp.sendAction(try #require(a.action),to:a.target,from:a))
    for _ in 0..<100 where model.items.contains(where:{$0.id == saved.id}) {try await Task.sleep(for:.milliseconds(10))}
    #expect(model.items.map(\.id) == [other.id] && a.state == .off && b.state == .off)
    #expect(doc.sql == saved.sql && doc.lastExecutedSQL == nil)
    let general=try FavoriteQuery(name:"General",sql:saved.sql,scope:.global)
    try await model.save(general);#expect(a.state == .on && b.state == .on)
    second.document.sql="SELECT 999";second.update();#expect(b.state == .off && a.state == .on)
  }
  @Test func favoriteContextMenuOffersOpenEditAndDeleteWithoutNetwork() async throws {
    _=NSApplication.shared
    let directory=URL(fileURLWithPath:"/tmp/favorite-menu-\(UUID())");defer {try? FileManager.default.removeItem(at:directory)}
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    state.historyEnabled=false;state.recoveryEnabled=false;state.servers=[server]
    state.favorites=FavoriteQueriesModel(url:directory.appendingPathComponent("favorites.json"))
    let node=TreeNode("Saved",kind:.favorite,server:server,database:"ExactDB")
    let favorite=try FavoriteQuery(name:"Saved",sql:"DELETE FROM dbo.T",scope:.database,serverID:server.id,database:"ExactDB")
    node.favorite=favorite;try await state.favorites.save(favorite)
    let host=WorkbenchController(state:state)
    let window=NSWindow(contentViewController:host)
    window.isReleasedWhenClosed=false;window.makeKeyAndOrderFront(nil)
    defer {for w in NSApp.windows where w.identifier?.rawValue == "favorite-editor|\(favorite.id)" {w.close()};window.close()}
    let menu=host.favoriteMenu(for:node)
    #expect(menu.items.map(\.title) == ["Sorguda Aç","Düzenle…","Sil…"])
    #expect(menu.items.allSatisfy {$0.image != nil && $0.target === host && $0.representedObject as? TreeNode === node})
    #expect(state.documents.isEmpty)
    let open=menu.items[0];#expect(NSApp.sendAction(try #require(open.action),to:open.target,from:open))
    #expect(state.active?.sql == favorite.sql && state.active?.database == "ExactDB" && state.active?.lastExecutedSQL == nil)
    let edit=menu.items[1];#expect(NSApp.sendAction(try #require(edit.action),to:edit.target,from:edit))
    let editorWindow=try #require(NSApp.windows.first {$0.identifier?.rawValue == "favorite-editor|\(favorite.id)"})
    #expect(editorWindow.title == "Favoriyi Düzenle");editorWindow.close()
    let delete=menu.items[2];#expect(NSApp.sendAction(try #require(delete.action),to:delete.target,from:delete))
    let cancel=try #require(window.attachedSheet);window.endSheet(cancel,returnCode:.alertSecondButtonReturn)
    for _ in 0..<100 where window.attachedSheet != nil {try await Task.sleep(for:.milliseconds(10))}
    #expect(state.favorites.items.map(\.id) == [favorite.id])
    #expect(NSApp.sendAction(try #require(delete.action),to:delete.target,from:delete))
    let confirm=try #require(window.attachedSheet);window.endSheet(confirm,returnCode:.alertFirstButtonReturn)
    for _ in 0..<100 where !state.favorites.items.isEmpty {try await Task.sleep(for:.milliseconds(10))}
    #expect(state.favorites.items.isEmpty && state.active?.sql == favorite.sql && state.active?.lastExecutedSQL == nil)
  }
  @Test func favoriteDatabaseChoicesUseCatalogKeepCachedOfflineAndReportPartialLists() async {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    server.databases=[CatalogItem(id:5,name:"Cached")]
    var requests:[String]=[]
    server.catalogFixture={sql in requests.append(sql);var e=Execution();e.results=[Rows(values:[["5","Sales",nil,nil],["6","HiddenFromExplorer",nil,nil]])];return e}
    let choices=FavoriteDatabaseChoices();await choices.load(server:server)
    #expect(choices.names == ["HiddenFromExplorer","Sales"] && requests == [Catalog.databases] && !choices.loading)
    server.catalogFixture={_ in var e=Execution();e.partial=true;e.results=[Rows(values:[["5","Sales",nil,nil]])];return e}
    await choices.load(server:server)
    #expect(choices.names == ["Sales"] && choices.message.contains("kısmi"))
    server.catalogFixture=nil;server.online=false;await choices.load(server:server)
    #expect(choices.names == ["Cached"] && choices.message.contains("Çevrimdışı"))
    await choices.load(server:nil);#expect(choices.names.isEmpty && !choices.loading)
  }
  @Test func popoverPlacementUsesAvailableSpaceForBothCoordinateDirections() {
    let viewport=NSRect(x:0,y:0,width:830,height:680),size=NSSize(width:420,height:420)
    for flipped in [false,true] {
      let low=StudioPopover.placement(anchor:NSRect(x:200,y:80,width:28,height:26),viewport:viewport,preferred:size,flipped:flipped)
      let high=StudioPopover.placement(anchor:NSRect(x:200,y:600,width:28,height:26),viewport:viewport,preferred:size,flipped:flipped)
      #expect(low.edge == .maxY && high.edge == .minY)
      #expect(low.size == size && high.size == size)
      let middle=StudioPopover.placement(anchor:NSRect(x:200,y:320,width:28,height:26),viewport:viewport,preferred:size,flipped:flipped)
      #expect(middle.size.height <= 320 && middle.size.width == 420)
    }
  }
  @Test func columnNavigationUsesOrdinalsRevealsHiddenMovedColumnsAndHighlightsHeader() throws {
    _=NSApplication.shared
    let controller=ResultController();controller.update(Rows(fields:(0..<24).map {Field("Column\($0)")},values:[(0..<24).map {String($0)}]))
    let window=NSWindow(contentViewController:controller);window.isReleasedWhenClosed=false;defer {window.close()}
    controller.view.frame=NSRect(x:0,y:0,width:600,height:300);controller.view.layoutSubtreeIfNeeded()
    let original=Array(controller.result.values[0])
    let target=try #require(controller.table.tableColumns.first {$0.identifier.rawValue == "18"})
    target.isHidden=true;controller.table.moveColumn(19,toColumn:3)
    controller.revealColumn(18)
    #expect(!target.isHidden && controller.highlightedColumnOrdinal == 18)
    #expect(controller.table.headerView?.accessibilityHelp() == "Gidilen kolon: Column18")
    #expect(Array(controller.result.values[0]) == original && controller.table.selectedRowIndexes.isEmpty)
    controller.revealColumn(999);#expect(controller.highlightedColumnOrdinal == 18)
    controller.revealColumn(2);#expect(controller.highlightedColumnOrdinal == 2)
    controller.update(controller.result,generation:1);#expect(controller.highlightedColumnOrdinal == nil)
    let columns=[ResultColumnChoice(id:9,name:"CustomerName",type:"nvarchar",hidden:false),.init(id:22,name:"CustomerID",type:"int",hidden:true),.init(id:3,name:"Amount",type:"money",hidden:false)]
    let found=ResultColumnNavigation.matches(columns,search:"  customer  ")
    #expect(found.map(\.id) == [9,22])
    #expect(ResultColumnNavigation.next(found,selected:9,step:1) == 22)
    #expect(ResultColumnNavigation.next(found,selected:22,step:1) == 22)
    #expect(ResultColumnNavigation.next([],selected:nil,step:1) == nil)
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
