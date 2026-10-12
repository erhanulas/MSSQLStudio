import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct DatabaseFilesTests {
  private func waitUntil(_ condition:()->Bool) async {
    for _ in 0..<200 where !condition() {await Task.yield()}
    #expect(condition())
  }
  @Test func inventoryAndSelectedDatabaseReadsAreBoundedAndFilteredLocally() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var reads:[(String,String)]=[]
    let model=DatabaseFilesModel(server:server,reader:{sql,database,limits in
      reads.append((sql,database))
      #expect(limits.timeout == 10 && limits.totalBytes == 4_000_000)
      if sql == DatabaseFilesMonitoring.inventorySQL {#expect(database == "master" && limits.rows == 5002 && limits.resultSets == 2)}
      else {#expect(sql == DatabaseFilesMonitoring.detailSQL(database:database) && limits.rows == 5001 && limits.resultSets == 1)}
      return DatabaseFilesUIFixture.catalog(sql,database:database)
    })
    await model.refresh()
    #expect(model.files.count == 5 && model.databases == ["DemoDB","Reporting","tempdb"] && reads.count == 2)
    #expect(model.selected?.database == "DemoDB" && model.selected?.usedPages == 716800 && model.selected?.freePages == 331776)
    model.select("5:2");await model.loadSelection()
    #expect(reads.count == 2 && model.selected?.type == "LOG" && model.selected?.usedPages == nil && model.selected?.freePages == nil)
    model.databaseFilter="Reporting";model.filterChanged();await model.loadSelection()
    #expect(model.filtered.count == 2 && model.selected?.database == "Reporting" && reads.count == 3 && reads.last?.1 == "Reporting")
    model.search="reporting_log.ldf";model.filterChanged();await model.loadSelection()
    #expect(model.filtered.count == 1 && model.selected?.name == "Reporting_Log" && reads.count == 3)
    model.search="not present";model.filterChanged();await model.loadSelection()
    #expect(model.filtered.isEmpty && model.selected == nil && reads.count == 3)
    model.search="";model.databaseFilter="tempdb";model.filterChanged();await model.loadSelection()
    #expect(model.selected?.sizePages == 524288 && model.selected?.usedPages == 131072 && reads.count == 4)
  }
  @Test func failuresKeepLastVerifiedInventoryButDisconnectAndGenerationInvalidateDetails() async throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var reads=0,fail=false
    let model=DatabaseFilesModel(server:server,reader:{sql,database,_ in
      reads+=1
      if fail {throw SQLFailure("VIEW ANY DEFINITION permission denied")}
      return DatabaseFilesUIFixture.catalog(sql,database:database)
    })
    await model.refresh();let time=try #require(model.sampledAt)
    fail=true;await model.refresh()
    #expect(model.files.count == 5 && model.sampledAt == time && model.error.contains("permission denied"))
    server.online=false;model.connectionChanged();await model.refresh()
    #expect(reads == 3 && model.files.count == 5 && model.error.contains("güncel değil") && model.details.isEmpty)
    server.generation=UUID();server.online=true;model.connectionChanged()
    #expect(model.files.isEmpty && model.sampledAt == nil && model.selected == nil && model.error.isEmpty)
  }
  @Test func onlineGenerationChangeInvalidatesCachedSelectionBeforeItCanPublish() async {
    for selectCachedRow in [false,true] {
      let server=ConnectedServer(profile:ServerProfile(),password:"")
      var reads=0
      let model=DatabaseFilesModel(server:server,reader:{sql,database,_ in
        reads+=1;return DatabaseFilesUIFixture.catalog(sql,database:database)
      })
      await model.refresh()
      model.select("5:2");await model.loadSelection()
      #expect(reads == 2 && model.selected?.name == "DemoDB_Log" && !model.details.isEmpty)
      server.generation=UUID();#expect(server.online)
      if selectCachedRow {model.select("5:1")}
      await model.loadSelection()
      #expect(model.files.isEmpty && model.details.isEmpty && model.selectedID == nil && model.sampledAt == nil && reads == 2)
      await model.refresh()
      #expect(reads == 4 && model.selected?.name == "DemoDB_Data" && model.selected?.usedPages == 716800)
    }
  }
  @Test func hiddenOfflineAndInFlightReplacedContextsCannotPublishOrReconnect() async {
    for reason in 0..<3 {
      let server=ConnectedServer(profile:ServerProfile(),password:"")
      var reads=0,pending:CheckedContinuation<Execution,any Error>?
      let model=DatabaseFilesModel(server:server,reader:{_,_,_ in reads+=1;return try await withCheckedThrowingContinuation {pending=$0}})
      model.setVisible(false);await model.refresh();#expect(reads == 0)
      model.setVisible(true)
      let task=Task {await model.refresh()};await waitUntil {pending != nil}
      await model.refresh();#expect(reads == 1 && model.loading)
      if reason == 0 {model.setVisible(false)}
      if reason == 1 {server.generation=UUID()}
      if reason == 2 {server.online=false}
      pending?.resume(returning:DatabaseFilesUIFixture.catalog(DatabaseFilesMonitoring.inventorySQL));pending=nil;await task.value
      #expect(model.files.isEmpty && model.sampledAt == nil && !model.loading && reads == 1)
      if reason == 2 {#expect(model.error.contains("çevrimdışı"));await model.refresh();#expect(reads == 1)}
    }
  }
  @Test func rowChangesAndCancellationRejectDelayedDatabaseDetails() async {
    for reason in 0..<3 {
      let server=ConnectedServer(profile:ServerProfile(),password:"")
      var pending:CheckedContinuation<Execution,any Error>?,delay=false
      let model=DatabaseFilesModel(server:server,reader:{sql,database,_ in
        if delay {return try await withCheckedThrowingContinuation {pending=$0}}
        return DatabaseFilesUIFixture.catalog(sql,database:database)
      })
      await model.refresh();model.select("6:1");delay=true
      let task=Task {await model.loadSelection()};await waitUntil {pending != nil}
      if reason == 0 {model.select("5:2")}
      if reason == 1 {server.generation=UUID()}
      if reason == 2 {task.cancel()}
      pending?.resume(returning:DatabaseFilesUIFixture.catalog(DatabaseFilesMonitoring.detailSQL(database:"Reporting"),database:"Reporting"));pending=nil;await task.value
      #expect(!model.loadingDetails && model.details.isEmpty)
      if reason == 1 {#expect(model.files.isEmpty && model.selectedID == nil)}
      else {#expect(model.detailError.isEmpty && model.files.count == 5)}
    }
  }
  @Test func boundedDatabaseCacheEvictsBeforeNavigatingUnlimitedTargets() async {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    var detailReads=0
    let model=DatabaseFilesModel(server:server,reader:{sql,database,_ in
      let inventory=DatabaseFilesUIFixture.catalog(DatabaseFilesMonitoring.inventorySQL)
      let template=Array(inventory.results[0].values[0])
      func row(_ id:Int)->[String?] {var row=template;row[0]=String(id);row[2]="DB\(id)";return row}
      var result=Execution()
      if sql == DatabaseFilesMonitoring.inventorySQL {
        result.results=[Rows(fields:DatabaseFilesMonitoring.columns.map {Field($0)},values:(1...9).map(row)),Rows(fields:[Field("issue")],values:[])]
      } else {
        detailReads+=1
        let id=Int(database.dropFirst(2)) ?? 1
        result.results=[Rows(fields:(DatabaseFilesMonitoring.columns+["used_pages"]).map {Field($0)},values:[row(id)+["100"]])]
      }
      return result
    })
    await model.refresh()
    for id in 2...9 {model.select("\(id):1");await model.loadSelection()}
    #expect(detailReads == 9)
    model.select("1:1");await model.loadSelection()
    #expect(detailReads == 10 && model.selected?.database == "DB1")
  }
  @Test func dedicatedFileWindowsReuseTheirServerScopeAndDoNotChangeActiveSQL() throws {
    _=NSApplication.shared
    let state=StudioState();state.recoveryEnabled=false;state.historyEnabled=false
    let a=ConnectedServer(profile:ServerProfile(name:"Files A"),password:""),b=ConnectedServer(profile:ServerProfile(name:"Files B"),password:"")
    for server in [a,b] {server.online=false;server.catalogFixture=ObjectManagementUIFixture.catalog}
    let document=QueryDocument(server:a,database:"KeepDB",title:"Keep query");document.sql="SELECT N'keep me';";document.savedText=document.sql
    state.servers=[a,b];state.documents=[document];state.active=document
    let controller=WorkbenchController(state:state)
    controller.showDatabaseFiles(a)
    let first=try #require(NSApp.windows.first {$0.identifier?.rawValue == "files|\(a.id)" && $0.isVisible})
    #expect(first.contentMinSize == NSSize(width:920,height:620))
    defer {for window in NSApp.windows where ["files|\(a.id)","files|\(b.id)"].contains(window.identifier?.rawValue ?? "") {window.close()}}
    controller.showDatabaseFiles(a);controller.showDatabaseFiles(b)
    let windows=NSApp.windows.filter {$0.isVisible && ($0.identifier?.rawValue.hasPrefix("files|") ?? false)}
    #expect(windows.filter {$0.identifier?.rawValue == "files|\(a.id)"}.count == 1 && windows.contains {$0 === first})
    #expect(windows.contains {$0.identifier?.rawValue == "files|\(b.id)"})
    #expect(state.documents.count == 1 && state.active === document && document.sql == document.savedText && document.database == "KeepDB" && document.lastExecutedSQL == nil)
  }
  @Test func explorerDoubleClickActionOpensFileWindowWithoutCreatingAQuery() throws {
    _=NSApplication.shared
    let state=StudioState();state.recoveryEnabled=false;state.historyEnabled=false
    let server=ConnectedServer(profile:ServerProfile(name:"Double-click files fixture"),password:"")
    server.catalogFixture=ObjectManagementUIFixture.catalog
    server.online=false
    var reconnects=0
    server.reconnectFixture={reconnects+=1}
    let document=QueryDocument(server:server,database:"KeepDB",title:"Keep query");document.sql="SELECT N'keep me';";document.savedText=document.sql
    state.servers=[server];state.documents=[document];state.active=document
    let controller=WorkbenchController(state:state)
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let outline=try #require(descendants(controller.view).compactMap {$0 as? NSOutlineView}.first)
    let root=try #require(outline.item(atRow:0) as? TreeNode)
    outline.expandItem(root)
    let management=try #require(root.children.first {$0.title == "Management"})
    outline.expandItem(management)
    let files=try #require(management.children.first {if case .folder(.files)=$0.kind {return true};return false})
    let row=outline.row(forItem:files);#expect(row>=0)
    outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
    // Dispatch the real outline double-click selector; accessibility/keyboard activation has no clickedRow.
    #expect(NSApp.sendAction(try #require(outline.doubleAction),to:outline.target,from:outline))
    let window=try #require(NSApp.windows.first {$0.identifier?.rawValue == "files|\(server.id)" && $0.isVisible})
    defer {window.close()}
    #expect(state.documents.count == 1 && state.active === document && document.sql == document.savedText && document.lastExecutedSQL == nil)
    #expect(!server.online && reconnects == 0 && !server.reconnecting)
  }
  @Test func dataLogEmptyAndPermissionViewsFitMinimumInBothThemes() async throws {
    _=NSApplication.shared
    let old=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(old ?? "light")}
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      for state in 0..<4 {
        let server=ConnectedServer(profile:ServerProfile(name:"Offline files fixture"),password:"")
        let model=DatabaseFilesModel(server:server,reader:{sql,database,_ in
          var execution=DatabaseFilesUIFixture.catalog(sql,database:database)
          if state == 3,sql == DatabaseFilesMonitoring.inventorySQL {
            execution.results[1]=Rows(fields:[Field("issue")],values:[["Dosya görünürlüğü sunucu yetkileriyle sınırlı olabilir; VIEW ANY DEFINITION yetkisi gerekir."]])
          }
          return execution
        })
        await model.refresh()
        if state == 1 {model.select("5:2");await model.loadSelection()}
        if state == 2 {model.search="Empty fixture";model.filterChanged()}
        let host=NSHostingController(rootView:DatabaseFilesPanel(model:model,openQuery:{}));host.sizingOptions=[]
        let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;defer {window.close()}
        let size=NSSize(width:920,height:620);window.setContentSize(size)
        try await Task.sleep(for:.milliseconds(100))
        host.view.frame=NSRect(origin:.zero,size:size);host.view.layoutSubtreeIfNeeded()
        #expect(host.view.bounds.size == size)
        let views=descendants(host.view)
        for control in views.compactMap({$0 as? NSControl}) where !control.isHiddenOrHasHiddenAncestor {
          let rect=host.view.convert(control.bounds,from:control)
          #expect(rect.minX>=0 && rect.maxX<=size.width+1 && rect.minY>=0 && rect.maxY<=size.height+1,"\(theme) state\(state) control \(rect)")
        }
        let table=try #require(views.compactMap {$0 as? NSTableView}.first)
        #expect(table.numberOfRows == model.filtered.count)
        let scroll=try #require(table.enclosingScrollView),rect=host.view.convert(scroll.bounds,from:scroll)
        #expect(rect.height>=150 && rect.minX>=0 && rect.maxX<=920 && rect.minY>=0 && rect.maxY<=620,"\(theme) state\(state) table \(rect)")
        if state != 2 {#expect(table.selectedRowIndexes == IndexSet(integer:state == 1 ? 1:0))}
        let rep=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
        host.view.cacheDisplay(in:host.view.bounds,to:rep)
        let data=try #require(rep.representation(using:.png,properties:[:]))
        try data.write(to:URL(fileURLWithPath:"/tmp/mssql-database-files-state\(state)-\(theme).png"))
      }
    }
  }
}
