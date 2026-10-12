import AppKit
import SwiftUI
import Testing
import SQLServerKit
@testable import MSSQLStudio

@MainActor struct SchemaComparisonPanelTests {
  private func model(reader:SchemaComparisonModel.Reader?=nil,writer:SchemaComparisonModel.Reader?=nil)->SchemaComparisonModel {
    let server=SchemaComparisonUIFixture.server()
    return .init(endpoints:[.init(server:server,database:"SourceDB"),.init(server:server,database:"TargetDB")],reader:reader,writer:writer)
  }
  @Test func compareFilterLazyDetailAndPlanUseIndependentMetadataOnly() async throws {
    var calls:[String]=[]
    let model=model(reader:{endpoint,sql in calls.append(sql);return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)})
    await model.compare()
    #expect(model.differences.count==10 && model.visible.count==6)
    #expect(model.differentCount==6 && model.sameCount==3 && model.unavailableCount==1)
    #expect(model.message.contains("1 karşılaştırılamadı"))
    #expect(calls.filter {$0.contains("StudioSchemaInventory")}.count==2)
    #expect(calls.filter {$0.contains("StudioSchemaRefinement")}.count==2)
    #expect(!model.detailReady && !model.busy && model.error.isEmpty)
    model.search="Total";#expect(model.visible.count==1 && model.visible.first?.status == .sourceOnly)
    model.search="";model.kind="View";#expect(model.visible.count==1)
    #expect(model.visible.first?.key.name=="v_ActiveBalance")
    model.kind="Tablo";#expect(Set(model.visible.map(\.key.name))==["Customers","CustomerHistory"])
    model.kind="Tüm türler"
    let row=try #require(model.differences.first {$0.key.name=="usp_Customers"})
    model.focused=row.key;await model.loadDetail()
    #expect(model.detailReady && model.sourceSQL.contains("[City]") && !model.targetSQL.contains("[City]"))
    let count=calls.count;await model.loadDetail();#expect(calls.count==count)
    model.marked=[row.key]
    let plan=try #require(await model.preparePlan())
    #expect(plan.sql.contains("ALTER PROCEDURE") && plan.sql.contains("[City]"))
    #expect(model.target?.database=="TargetDB" && !model.applying)
  }
  @Test func applyRevalidatesAndWritesOnlyToNamedTargetAndBlocksConcurrentDrift() async throws {
    var drift=false,writes:[String]=[]
    let model=model(reader:{endpoint,sql in
      var result=try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
      if drift,endpoint.database=="TargetDB",sql.contains("StudioSchemaInventory") {
        var rows=Array(result.results[1].values);rows[0][4]=String(repeating:"f",count:64);result.results[1]=Rows(values:rows)
      }
      return result
    },writer:{endpoint,sql in writes.append(endpoint.database+"|"+sql);return Execution()})
    await model.compare();let row=try #require(model.differences.first {$0.key.name=="usp_Customers"});model.marked=[row.key]
    let plan=try #require(await model.preparePlan()),source=model.sourceID,target=model.targetID
    drift=true;await model.apply(plan,sourceID:source,targetID:target)
    #expect(writes.isEmpty && model.error.contains("değişti") && !model.applying)
    drift=false;await model.compare();model.marked=[row.key]
    let fresh=try #require(await model.preparePlan());await model.apply(fresh,sourceID:source,targetID:target)
    #expect(writes.count==1 && writes[0].hasPrefix("TargetDB|"))
    #expect(writes[0].contains("ROLLBACK TRANSACTION") && !model.applying)
    #expect(SchemaComparisonModel.activeApplications==0)
    model.marked=[row.key];let stale=try #require(await model.preparePlan())
    model.target?.server.generation=UUID()
    await model.apply(stale,sourceID:source,targetID:target)
    #expect(writes.count==1 && model.error.contains("Bağlantı değişti"))
  }
  @Test func cancellationInvalidatesDelayedResultsAndPairChangesInvalidatePreview() async throws {
    let model=model(reader:{endpoint,sql in try await Task.sleep(for:.milliseconds(40));return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)})
    model.startComparison();try await Task.sleep(for:.milliseconds(10));model.cancel()
    try await Task.sleep(for:.milliseconds(100))
    #expect(model.differences.isEmpty && !model.busy)
    await model.compare();let row=try #require(model.differences.first {$0.canStage});model.marked=[row.key]
    let plan=try #require(await model.preparePlan()),oldSource=model.sourceID,oldTarget=model.targetID
    model.targetID=model.sourceID;model.invalidate()
    #expect(!model.validPair && model.marked.isEmpty && !model.detailReady)
    await model.apply(plan,sourceID:oldSource,targetID:oldTarget)
    #expect(model.error.contains("bağlamı değişti"))
  }
  @Test func tableAndViewColumnsAreLazyAndIndependentOfSafeMigrationScripting() async throws {
    var queries:[String]=[]
    let model=model(reader:{endpoint,sql in queries.append(sql);return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)})
    await model.compare()
    #expect(!queries.contains {$0.contains("StudioSchemaColumns")})
    let table=try #require(model.differences.first {$0.key.name=="Customers"})
    model.focused=table.key;await model.loadDetail()
    #expect(model.columnsReady && model.detailMode == .columns && model.columnChangeCount==3)
    let amount=try #require(model.columnDifferences.first {$0.name=="Amount"})
    #expect(amount.source?.dataType=="decimal(28,8)" && amount.target?.dataType=="decimal(18,2)")
    #expect(amount.changes.contains(.dataType) && amount.changes.contains(.nullability))
    #expect(model.columnDifferences.first {$0.name=="City"}?.changes.contains(.added)==true)
    #expect(model.detailComparison != nil && model.sourceSQL.contains("decimal(28,8)"))
    let reads=queries.count;await model.loadDetail();#expect(queries.count==reads)
    let special=try #require(model.differences.first {$0.key.name=="CustomerHistory"})
    #expect(special.status == .changed && !special.canStage)
    model.focused=special.key;await model.loadDetail()
    #expect(model.columnsReady && model.detailReady && model.columnChangeCount==3)
    #expect(model.detailComparison==nil && model.detailNotice.localizedCaseInsensitiveContains("özel tablo"))
    let view=try #require(model.differences.first {$0.key.name=="v_Balance"})
    #expect(view.status == .equal && !view.canStage && !view.migrationIssue.isEmpty)
    model.focused=view.key;await model.loadDetail()
    #expect(model.columnsReady && model.columnChangeCount==1)
    #expect(model.detailComparison?.added==0 && model.detailComparison?.removed==0)
    #expect(model.detailMode == .columns && model.detailNotice.contains("View kodu aynı"))
  }
  @Test func onlyVerifiedDifferencesAreListedEvenAfterChangingFiltersOrRecomparing() async throws {
    let model=model();await model.compare()
    let excluded:Set<String>=["v_Balance","v_Orders","CustomersIndexOnly","usp_Encrypted"]
    #expect(model.visible.allSatisfy {!excluded.contains($0.key.name)})
    model.search="IndexOnly";#expect(model.visible.isEmpty)
    model.search="";model.kind="View";#expect(model.visible.map(\.key.name)==["v_ActiveBalance"])
    await model.compare();#expect(model.visible.map(\.key.name)==["v_ActiveBalance"])
    let identical=self.model(reader:{_,sql in try SchemaComparisonUIFixture.catalog("SourceDB",sql)})
    await identical.compare()
    #expect(identical.visible.isEmpty && identical.differentCount==0 && identical.unavailableCount==1)
    #expect(identical.sameCount==identical.differences.count-1)
    #expect(identical.sourceSnapshot != nil && identical.error.isEmpty)
  }
  @Test func viewProjectionAdditionAppearsInFilteredListAndInlineCode() async throws {
    let model=model(reader:{endpoint,sql in
      var result=try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
      let definition="CREATE VIEW dbo.v_ActiveBalance AS\nSELECT A.CustomerID, C.InvoiceDate,\n"+(endpoint.database=="SourceDB" ? "    C.INCKEYNO AS ExternalOrderId,\n":"")+"    A.Amount\nFROM dbo.Customers A JOIN dbo.Orders C ON C.CustomerID=A.CustomerID;"
      if sql.contains("StudioSchemaRefinement") {
        var rows=Array(result.results[0].values)
        for i in rows.indices where rows[i][0]=="109" {rows[i][1]=definition;rows[i][6]=String(repeating:"0",count:64)}
        result.results[0]=Rows(values:rows)
      } else if sql.contains("sys.sql_modules"),sql.contains("=109") {
        result.results[0]=Rows(values:[[definition,"1","1","0",nil]])
      }
      return result
    })
    model.kind="View";await model.compare()
    let row=try #require(model.visible.first {$0.key.name=="v_ActiveBalance"})
    #expect(row.status == .changed && row.canStage)
    #expect(!model.visible.contains {$0.key.name=="v_Balance"})
    model.detailMode = .code;model.focused=row.key;await model.loadDetail()
    #expect(model.sourceSQL.contains("C.INCKEYNO AS ExternalOrderId"))
    #expect(!model.targetSQL.contains("ExternalOrderId") && !model.changedGroups.isEmpty)
    #expect(model.detailMode == .code && model.error.isEmpty)
  }
  @Test func readableViewWithMissingServerHashReportsFailureInsteadOfAnEmptyDifferenceList() async throws {
    let model=model(reader:{endpoint,sql in
      var result=try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
      if sql.contains("StudioSchemaInventory") {
        var rows=Array(result.results[1].values)
        for i in rows.indices where rows[i][0]=="109" {rows[i][4]=nil}
        result.results[1]=Rows(values:rows)
      }
      return result
    })
    model.kind="View";await model.compare()
    #expect(model.error.contains("DDL özeti hesaplanamadı") && model.error.contains("v_ActiveBalance"))
    #expect(model.visible.isEmpty && model.differences.isEmpty && model.sourceSnapshot==nil)
    #expect(model.message=="Karşılaştırma tamamlanamadı." && !model.busy)
  }
  @Test func detailModePersistsAcrossObjectsRecomparisonAndDelayedLoads() async throws {
    var delay=false
    let model=model(reader:{endpoint,sql in
      if delay,sql.contains("StudioSchemaColumns") {try await Task.sleep(for:.milliseconds(40))}
      return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
    })
    await model.compare()
    let table=try #require(model.visible.first {$0.key.name=="Customers"}).key
    let special=try #require(model.visible.first {$0.key.name=="CustomerHistory"}).key
    let view=try #require(model.visible.first {$0.key.name=="v_ActiveBalance"}).key
    let procedure=try #require(model.visible.first {$0.key.name=="usp_Customers"}).key
    model.detailMode = .code
    for key in [table,view,procedure,table] {
      model.focused=key;await model.loadDetail()
      #expect(model.detailMode == .code && model.effectiveDetailMode == .code)
    }
    model.detailMode = .columns
    model.focused=procedure;await model.loadDetail()
    #expect(model.detailMode == .columns && model.effectiveDetailMode == .code && model.detailComparison != nil)
    model.focused=view;await model.loadDetail()
    #expect(model.detailMode == .columns && model.effectiveDetailMode == .columns && model.columnsReady)
    await model.compare()
    #expect(model.detailMode == .columns)
    delay=true;model.focused=special
    let loading=Task {await model.loadDetail()};try await Task.sleep(for:.milliseconds(10))
    #expect(model.detailLoading)
    model.detailMode = .code;await loading.value
    #expect(model.detailMode == .code && model.effectiveDetailMode == .code)
    model.focused=nil;await model.loadDetail()
    #expect(model.detailMode == .code)
    model.invalidate();#expect(model.detailMode == .code)
  }
  @Test func clearingSelectionAndChangingConnectionDuringDetailNeverPublishesStalePreview() async throws {
    let model=model(reader:{endpoint,sql in
      if !sql.contains("StudioSchemaInventory") && !sql.contains("StudioSchemaRefinement") {try await Task.sleep(for:.milliseconds(40))}
      return try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
    })
    await model.compare();model.focused=model.differences.first {$0.key.name=="usp_Customers"}?.key
    let delayed=Task {await model.loadDetail()}
    try await Task.sleep(for:.milliseconds(10))
    #expect(model.detailLoading)
    model.focused=nil;await model.loadDetail();await delayed.value
    #expect(!model.detailLoading && !model.detailReady && model.sourceSQL.isEmpty && model.detailComparison==nil)
    model.focused=model.differences.first {$0.key.name=="Customers"}?.key
    let stale=Task {await model.loadDetail()};try await Task.sleep(for:.milliseconds(10))
    model.source?.server.generation=UUID();await stale.value
    #expect(!model.detailLoading && !model.detailReady && !model.columnsReady)
    #expect(model.sourceSQL.isEmpty && model.columnDifferences.isEmpty && model.detailNotice.contains("Bağlantı değişti"))
    await model.compare();model.marked=[try #require(model.differences.first {$0.key.name=="usp_Customers"}).key]
    let preview=Task {await model.preparePlan()};try await Task.sleep(for:.milliseconds(10))
    model.target?.server.generation=UUID()
    #expect(await preview.value==nil && model.error.contains("Bağlantı değişti"))
  }
  @Test func partialColumnMetadataDoesNotHideReadableViewCodeOrClaimEqualColumns() async throws {
    let model=model(reader:{endpoint,sql in
      var result=try SchemaComparisonUIFixture.catalog(endpoint.database,sql)
      if sql.contains("StudioSchemaColumns") {result.partial=true}
      return result
    })
    await model.compare();model.focused=model.visible.first {$0.key.name=="v_ActiveBalance"}?.key
    await model.loadDetail()
    #expect(!model.columnsReady && model.columnDifferences.isEmpty && model.columnSummary=="Kolonlar alınamadı")
    #expect(model.detailComparison != nil && model.detailReady && model.detailNotice.contains("Kolonlar:"))
  }
  @Test func explorerSelectsTwoDatabaseNodesAndRejectsMixedSelection() throws {
    _=NSApplication.shared
    let state=StudioState(),server=SchemaComparisonUIFixture.server();server.online=false;state.servers=[server]
    let controller=WorkbenchController(state:state);_ = controller.view
    func descendants(_ v:NSView)->[NSView] {[v]+v.subviews.flatMap(descendants)}
    let outline=try #require(descendants(controller.view).compactMap {$0 as? NSOutlineView}.first)
    let root=try #require(outline.item(atRow:0) as? TreeNode)
    let folder=try #require(root.children.first {if case .folder(.databases)=$0.kind {return true};return false})
    outline.expandItem(folder)
    let nodes=folder.children.filter {if case .database=$0.kind {return true};return false}
    #expect(nodes.count==2)
    let indexes=IndexSet(nodes.map {outline.row(forItem:$0)})
    #expect(outline.allowsMultipleSelection)
    #expect(controller.outlineView(outline,selectionIndexesForProposedSelection:indexes)==indexes)
    var mixed=indexes;mixed.insert(0)
    #expect(controller.outlineView(outline,selectionIndexesForProposedSelection:mixed).count==1)
    server.online=true
    #expect(controller.schemaEndpoints(for:nodes).map(\.database)==["SourceDB","TargetDB"])
    outline.selectRowIndexes(indexes,byExtendingSelection:false);state.changed?()
    #expect(outline.selectedRowIndexes.count==2)
    state.changed=nil
  }
  @Test func panelHasBoundedNativeLayoutAndAccessibleActions() async throws {
    _=NSApplication.shared
    let model=model();await model.compare()
    model.focused=model.differences.first {$0.key.name=="usp_Customers"}?.key;await model.loadDetail()
    let panel=SchemaComparisonPanel(model:model,preview:{},openSQL:{_ in})
    let hosting=NSHostingView(rootView:panel)
    let window=NSWindow(contentRect:NSRect(x:-1800,y:-1800,width:1000,height:680),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.contentView=hosting;hosting.frame=NSRect(x:0,y:0,width:1000,height:680);hosting.layoutSubtreeIfNeeded()
    #expect(hosting.fittingSize.width<=1000)
    #expect(window.contentView?.bounds.height==680)
    try await Task.sleep(for:.milliseconds(50));hosting.layoutSubtreeIfNeeded()
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let inline=try #require(descendants(hosting).compactMap {$0 as? SQLInlineDiffView}.first)
    let frame=hosting.convert(inline.bounds,from:inline)
    #expect(frame.minX>=0 && frame.maxX<=1000 && frame.minY>=0 && frame.maxY<=680)
    #expect(inline.leftText.string.contains("SELECT") && inline.rightText.string.contains("[City]"))
    window.contentView=nil
    let controller=SchemaComparisonWindow(model:model,openSQL:{_,_ in})
    let comparison=try #require(controller.window)
    let initialSize=try #require(comparison.contentView).bounds.size
    #expect(initialSize==NSSize(width:1280,height:850))
    model.focused=model.differences.first {$0.key.name=="usp_Customers"}?.key
    await model.loadDetail()
    comparison.contentView?.layoutSubtreeIfNeeded()
    #expect(comparison.contentView?.bounds.size==initialSize)
    controller.close()
  }
}
