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
    #expect(model.differences.count==5 && model.visible.count==4)
    #expect(calls.filter {$0.contains("StudioSchemaInventory")}.count==2)
    #expect(calls.filter {$0.contains("StudioSchemaRefinement")}.count==2)
    #expect(!model.detailReady && !model.busy && model.error.isEmpty)
    model.search="Total";#expect(model.visible.count==1 && model.visible.first?.status == .sourceOnly)
    model.search="";model.kind="View";#expect(model.visible.isEmpty)
    model.onlyDifferences=false;#expect(model.visible.count==1)
    model.kind="Tüm türler";model.onlyDifferences=true
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
    let panel=SchemaComparisonPanel(model:model,review:{_,_,_,_ in},preview:{},openSQL:{_ in})
    let hosting=NSHostingView(rootView:panel)
    let window=NSWindow(contentRect:NSRect(x:-1800,y:-1800,width:1080,height:760),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.contentView=hosting;hosting.frame=NSRect(x:0,y:0,width:1080,height:760);hosting.layoutSubtreeIfNeeded()
    #expect(hosting.fittingSize.width<=1080)
    #expect(window.contentView?.bounds.height==760)
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
