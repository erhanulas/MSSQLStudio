import AppKit
import Foundation
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct SnapshotReadLimitTests {
  private func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
  private func wait(_ grid:ResultController) async throws {
    for _ in 0..<250 where grid.isProcessing {try await Task.sleep(for:.milliseconds(10))}
    #expect(!grid.isProcessing)
  }
  private func choose(_ value:Int,controller:QueryController) throws {
    let popup=try #require(descendants(controller.view).compactMap {$0 as? NSPopUpButton}.first {$0.accessibilityIdentifier() == "gridRowOptions"})
    let item=try #require(popup.itemArray.first {$0.identifier?.rawValue == "gridReadChoices" && $0.tag == value})
    popup.select(item)
    #expect(NSApp.sendAction(try #require(popup.action),to:popup.target,from:popup))
  }
  private func rows(_ count:Int)throws->Rows {
    let spool=try ResultSpool()
    var rows=Rows(fields:[Field("ID",type:4),Field("Name"),Field("Exact",type:3,size:28,scale:8),Field("Missing")])
    rows.values=try spool.append((0..<count).map {[String($0),"Row \($0)","12345678901234567890.00000000",nil]})
    return rows
  }
  @Test func pickerImmediatelyLimitsEveryGridAndTabAndRestoresOnlyCachedRowsWithoutExecutingSQL() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Snapshot fixture")
    doc.sql="SELECT N'unchanged SQL';";doc.state = .ready;doc.limits=ResultReadPreferences.limits(rows:50_000)
    doc.results=[try rows(1200),try rows(700)];doc.rowCount=1900
    let state=StudioState();state.recoveryEnabled=false;state.historyEnabled=false;state.servers=[server];state.documents=[doc];state.active=doc
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;defer {window.close()}
    let controller=try #require(host.children.compactMap {$0 as? QueryController}.first)
    let grids=controller.children.compactMap {$0 as? ResultController}
    let generation=doc.resultGeneration
    try choose(10,controller:controller)
    #expect(grids.map {$0.result.values.count} == [10,10] && grids.allSatisfy {$0.table.numberOfRows == 10})
    #expect(grids.map(\.loadedRowCount) == [1200,700] && grids.allSatisfy {$0.isReadLimited && $0.result.values.diskBacked})
    #expect(doc.results.map {$0.values.count} == [1200,700] && doc.rowCount == 1900)
    #expect(doc.lastExecutedSQL == nil && doc.resultGeneration == generation && doc.task == nil)
    #expect(doc.sql == "SELECT N'unchanged SQL';")
    let tabs=try #require(descendants(controller.view).compactMap {$0 as? NSTabView}.first)
    #expect(tabs.tabViewItems.filter {$0.label.hasPrefix("Results")}.allSatisfy {$0.label.contains("(10)") && $0.label.contains("SINIRLI")})
    let status=try #require(descendants(host.view).compactMap {$0 as? NSTextField}.first {$0.accessibilityIdentifier() == "queryStatus"})
    #expect(status.stringValue.contains("20 gösterilen") && status.stringValue.contains("\(1900.formatted()) yüklenen"))
    try choose(500,controller:controller)
    #expect(grids.map {$0.result.values.count} == [500,500] && doc.task == nil)
    controller.applyLoadingPreferences(rows:2000,refresh:0,save:false)
    #expect(grids.map {$0.result.values.count} == [1200,700] && grids.allSatisfy {!$0.isReadLimited})
    #expect(grids[0].result.values[1199][0] == "1199" && doc.resultGeneration == generation)
    #expect(tabs.tabViewItems.filter {$0.label.hasPrefix("Results")}.allSatisfy {!$0.label.contains("SINIRLI")})
  }
  @Test func rowLimitSelectorTracksFilteredCountAndRestoresWithoutQueryExecution() async throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:.init(),password:""),database:"master",title:"Filtered count")
    doc.server.online=false;doc.state = .ready;doc.limits=ResultReadPreferences.limits(rows:1000)
    doc.results=[try rows(300)];doc.rowCount=300
    let controller=QueryController(document:doc),window=NSWindow(contentViewController:controller)
    window.isReleasedWhenClosed=false;defer {window.close()}
    let grid=try #require(controller.children.compactMap {$0 as? ResultController}.first)
    let popup=try #require(descendants(controller.view).compactMap {$0 as? StudioSearchablePopUpButton}.first {$0.accessibilityIdentifier()=="gridRowOptions"})
    #expect(popup.displayTitle=="300 satır")
    var rule=ColumnRule();rule.choices=[.text("42")];try grid.setRule(rule,column:0);try await wait(grid)
    #expect(grid.visibleCount==1 && popup.displayTitle=="1 satır")
    rule.choices=[];try grid.setRule(rule,column:0);try await wait(grid)
    #expect(grid.visibleCount==0 && popup.displayTitle=="0 satır")
    try grid.setRule(ColumnRule(),column:0);try await wait(grid)
    #expect(popup.displayTitle=="300 satır")
    grid.filter="Row 299";try await wait(grid)
    #expect(popup.displayTitle=="1 satır")
    grid.filter="";try await wait(grid)
    #expect(popup.displayTitle=="300 satır" && doc.task==nil && doc.results[0].values.count==300 && doc.limits.rows==1000)
  }
  @Test func capPrecedesSortAndFilterKeepsPinnedRowsGutterAndCopyInOneSourceMapping() async throws {
    _=NSApplication.shared
    let grid=ResultController(),window=NSWindow(contentViewController:grid);window.isReleasedWhenClosed=false;defer {window.close()}
    grid.update(try rows(300));grid.setPageSize(0);grid.setColumnPinned(0,pinned:true)
    grid.table.sortDescriptors=[NSSortDescriptor(key:"0",ascending:false)];try await wait(grid)
    #expect(grid.visibleIndices?.first == 299)
    #expect(grid.applyReadLimit(10));try await wait(grid)
    #expect(grid.visibleIndices == Array((0..<10).reversed()) && grid.pinnedColumns == [0])
    #expect(grid.table.numberOfRows == 10 && grid.frozenTable.numberOfRows == 10 && grid.rowGutter.label?(0).0 == "10")
    grid.table.selectRowIndexes(IndexSet(integersIn:0..<10),byExtendingSelection:false);grid.copySelectionData(includeHeaders:true)
    let copied=try #require(NSPasteboard.general.string(forType:.string))
    #expect(copied.components(separatedBy:"\n").count == 11 && copied.contains("9\tRow 9") && !copied.contains("299\t"))
    grid.filter="Row 299";try await wait(grid);#expect(grid.visibleCount == 0)
    #expect(grid.applyReadLimit(500));try await wait(grid)
    #expect(grid.visibleCount == 1 && grid.loadedRowCount == 300 && grid.rowGutter.label?(0).0 == "300")
    grid.filter="";try await wait(grid);grid.setPageSize(10)
    let last=try #require(grid.toolbar.arrangedSubviews.compactMap {$0 as? NSButton}.first {$0.tag == 3})
    last.performClick(nil);#expect(grid.pageStart == 290)
    #expect(grid.applyReadLimit(5));try await wait(grid)
    #expect(grid.pageStart == 0 && grid.pageCount == 5 && grid.table.selectedRowIndexes.isEmpty && grid.pinnedColumns == [0])
    #expect(grid.pageExportIndices == [4,3,2,1,0])
    #expect(grid.result.values[4][2] == "12345678901234567890.00000000" && grid.result.values[4][3] == nil)
  }
  @Test func editingModeRejectsReadLimitChangesWithoutDiscardingPendingEditsOrNativeDraft() async throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Editing cap fixture")
    doc.server.online=false
    doc.state = .ready;doc.results=[try rows(100)];doc.limits=ResultReadPreferences.limits(rows:100)
    let controller=QueryController(document:doc),window=NSWindow(contentViewController:controller);window.isReleasedWhenClosed=false;defer {window.close()}
    let grid=try #require(controller.children.compactMap {$0 as? ResultController}.first)
    grid.setPageSize(0)
    grid.editDefinition=TableDefinition(schema:"dbo",name:"Numbers",columns:[.init(id:1,name:"ID",type:"int"),.init(id:2,name:"Name",type:"nvarchar(100)"),.init(id:3,name:"Exact",type:"decimal(28,8)"),.init(id:4,name:"Missing",type:"nvarchar(100)")],primaryKey:["ID"])
    grid.editingAllowed={true};grid.setEditValue("kept",row:99,column:1)
    controller.update()
    #expect(!grid.applyReadLimit(10) && grid.result.values.count == 100 && grid.pendingEdits[99]?.values[1] == "kept")
    controller.applyLoadingPreferences(rows:10,refresh:0,save:false)
    #expect(doc.limits.rows == 100 && grid.pendingEdits[99]?.values[1] == "kept")
    let popup=try #require(descendants(controller.view).compactMap {$0 as? NSPopUpButton}.first {$0.accessibilityIdentifier() == "gridRowOptions"})
    #expect(popup.itemArray.first {$0.identifier?.rawValue == "gridReadChoices"}?.isEnabled == false)
    try choose(10,controller:controller)
    #expect(doc.limits.rows == 100 && grid.pendingEdits.count == 1)
    window.orderFront(nil);grid.table.editColumn(2,row:99,with:nil,select:true)
    let editor=try #require(grid.table.currentEditor() as? NSTextView)
    editor.insertText("draft",replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    #expect(grid.hasDraftChanges && !grid.applyReadLimit(5) && grid.hasDraftChanges)
    #expect(grid.table.textView(editor,doCommandBy:#selector(NSResponder.cancelOperation(_:))))
    grid.discardEdits();controller.update();try choose(10,controller:controller)
    #expect(doc.limits.rows == 10 && grid.result.values.count == 10 && grid.loadedRowCount == 100 && grid.pendingEdits.isEmpty)
  }
  @Test func changingLimitCancelsStaleFilterProjectionAndRefreshStillUsesTheNewServerLimit() async throws {
    _=NSApplication.shared
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Repeat cap fixture")
    doc.server.online=false
    doc.state = .ready;doc.sql="SELECT n FROM dbo.Numbers;";doc.limits=ResultReadPreferences.limits(rows:100)
    var calls:[Int]=[]
    doc.executionFixture={_,limits in calls.append(limits.rows);var execution=Execution();execution.results=[try rows(limits.rows)];return execution}
    let controller=QueryController(document:doc);_=controller.view
    doc.execute();await doc.task?.value;controller.update()
    let grid=try #require(controller.children.compactMap {$0 as? ResultController}.first)
    let search=try #require(descendants(controller.view).compactMap {$0 as? NSSearchField}.first {$0.placeholderString == "Sonuç ara"})
    search.stringValue="Row 99"
    #expect(NSApp.sendAction(try #require(search.action),to:search.target,from:search))
    try choose(10,controller:controller)
    #expect(grid.result.values.count == 10 && calls == [100])
    try await wait(grid)
    #expect(grid.visibleCount == 0 && grid.visibleIndices == [])
    search.stringValue=""
    #expect(NSApp.sendAction(try #require(search.action),to:search.target,from:search))
    await doc.task?.value;controller.update();try await wait(grid)
    #expect(calls == [100,10])
    let refresh=try #require(descendants(controller.view).compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier() == "refreshResults"})
    #expect(NSApp.sendAction(try #require(refresh.action),to:refresh.target,from:refresh))
    await doc.task?.value;controller.update()
    #expect(calls == [100,10,10] && doc.results.first?.values.count == 10 && grid.loadedRowCount == 10)
    controller.applyLoadingPreferences(rows:1000,refresh:0,save:false)
    await doc.task?.value;controller.update()
    #expect(grid.result.values.count == 1000 && !grid.isReadLimited && calls == [100,10,10,1000])
  }
}
