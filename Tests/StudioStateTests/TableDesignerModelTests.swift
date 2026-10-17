import AppKit
import SwiftUI
import Testing
import SQLServerKit
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct TableDesignerModelTests {
  private func table()->TableDefinition {
    var value=TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"A",type:"int",nullable:false),.init(id:2,name:"B",type:"int",nullable:false),.init(id:3,name:"Name",type:"nvarchar(50)")],primaryKey:["B","A"],primaryKeyName:"PK_T",definitions:[.init(name:"IX_Name",kind:"INDEX",sql:"CREATE NONCLUSTERED INDEX [IX_Name] ON [dbo].[T] ([Name] DESC) WITH (FILLFACTOR = 80) ON [PRIMARY];")])
    value.objectID=42;return value
  }
  @Test func unchangedCompositeKeyOrderAndExistingObjectSelectionDoNotEnableApply() async throws {
    let original=table(),model=TableDesignerModel(load:{original},apply:{_ in original})
    await model.load()
    #expect(model.primaryNames==["B","A"] && !model.hasChanges && !model.canPrepare && !model.canApply)
    model.select(original.definitions[0])
    #expect(model.structure.keys==["Name"] && model.structure.descending==["Name"] && !model.hasChanges)
    model.structure.name="IX_Changed"
    let plan=try model.prepare()
    #expect(model.canApply && plan.sql.contains("DROP INDEX [IX_Name]") && plan.sql.contains("INDEX [IX_Changed]"))
    #expect(plan.sql.contains("FILLFACTOR = 80") && plan.sql.contains("OBJECT_ID"))
    model.newStructure()
    #expect(model.selectedDefinition==nil && model.structure.keys.isEmpty && !model.hasChanges)
  }
  @Test func approvalIsSingleUseBlocksCloseAndRefreshesTheBaselineAfterSuccess() async throws {
    let original=table()
    var updated=original;updated.columns[2].type="nvarchar(100)"
    var continuation:CheckedContinuation<Void,Never>?,writes=0
    let model=TableDesignerModel(load:{original},apply:{_ in
      writes+=1;await withCheckedContinuation {continuation=$0};return updated
    })
    await model.load();model.columns[2].type="nvarchar(100)"
    let plan=try model.prepare(),window=NSWindow()
    let operation=Task {await model.apply(plan)}
    for _ in 0..<100 where continuation==nil {try await Task.sleep(for:.milliseconds(2))}
    #expect(model.busy && !model.canApply && TableDesignerModel.activeApplications==1 && !model.windowShouldClose(window))
    continuation?.resume();#expect(await operation.value)
    #expect(model.columns==updated.columns && !model.hasChanges && !model.canPrepare && model.windowShouldClose(window))
    let repeated=await model.apply(plan)
    #expect(TableDesignerModel.activeApplications==0 && !repeated && writes==1)
  }
  @Test func staleApprovalAndUncertainWriteCannotSendAgainUntilExplicitReload() async throws {
    let original=table();var writes=0
    let model=TableDesignerModel(load:{original},reload:{_,_ in original},apply:{_ in writes+=1;throw SQLFailure("Communication link failure")})
    await model.load();model.columns[2].type="nvarchar(100)"
    let stale=try model.prepare();model.columns[2].type="nvarchar(120)"
    #expect(!(await model.apply(stale)) && writes==0)
    let fresh=try model.prepare()
    #expect(!(await model.apply(fresh)) && model.unverified && writes==1)
    #expect(!(await model.apply(fresh)) && !model.canApply && writes==1)
    await model.reload()
    #expect(!model.unverified && !model.hasChanges && model.columns==original.columns)
  }
  @Test func newTableReadbackAllowsFurtherGuardedEditsAndSelectsNewStructure() async throws {
    var created=table();created.name="NewTable";created.definitions=[];created.primaryKey=["Id"];created.columns=[.init(id:1,name:"Id",type:"int",nullable:false,identity:true)]
    let model=TableDesignerModel(apply:{_ in created})
    await model.load();let plan=try model.prepare()
    let applied=await model.apply(plan)
    #expect(plan.sql.contains("CREATE TABLE") && applied)
    model.columns.append(.init(id:-2,name:"Added",type:"int"))
    #expect(try model.prepare().sql.contains("<> 42"))
  }
  @Test func nativeDesignerUsesSearchableDataTypeControlAndDisablesUnchangedActions() async throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    StudioTheme.apply("light")
    defer {StudioTheme.apply(previous ?? "light");if previous==nil {UserDefaults.standard.removeObject(forKey:"ssmsTheme")}}
    let original=table(),model=TableDesignerModel(load:{original},apply:{_ in original})
    await model.load()
    let host=NSHostingController(rootView:TableDesignerPanel(server:"Fixture",database:"Demo",model:model,open:{_ in}))
    host.sizingOptions=[]
    let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:1000,height:700));window.center();window.orderFront(nil)
    defer {window.close()}
    try await Task.sleep(for:.milliseconds(120));host.view.layoutSubtreeIfNeeded()
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    func capture(_ suffix:String) throws {
      let image=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
      host.view.cacheDisplay(in:host.view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-table-designer-"+suffix+".png"))
    }
    try capture("unchanged")
    let children=descendants(host.view)
    func footerAccentPixels() throws -> Int {
      let bounds=host.view.bounds
      let rect=NSRect(x:bounds.maxX-260,y:host.view.isFlipped ? bounds.maxY-60:bounds.minY,width:260,height:60)
      let image=try #require(host.view.bitmapImageRepForCachingDisplay(in:rect))
      host.view.cacheDisplay(in:rect,to:image)
      var count=0
      for y in 0..<image.pixelsHigh {for x in 0..<image.pixelsWide {
        if let color=image.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),color.blueComponent>color.redComponent+0.12,color.blueComponent>color.greenComponent+0.05 {count+=1}
      }}
      return count
    }
    let disabledAccent=try footerAccentPixels()
    #expect(!model.canApply && !model.canPrepare)
    #expect(children.compactMap {$0 as? StudioSearchablePopUpButton}.contains {$0.accessibilityLabel()=="Veri tipi"})
    let typePicker=try #require(children.compactMap {$0 as? StudioSearchablePopUpButton}.first {$0.titleOfSelectedItem=="nvarchar"})
    #expect(NSApp.sendAction(try #require(typePicker.action),to:typePicker.target,from:typePicker))
    #expect(model.columns[2].type=="nvarchar(50)" && !model.canPrepare)
    model.columns[2].type="nvarchar(100)"
    try await Task.sleep(for:.milliseconds(60))
    try capture("changed")
    #expect(model.canApply && model.canPrepare)
    #expect(try footerAccentPixels()>disabledAccent+100)
  }
  @Test func selectedIndexFieldsAlignAndFitBothThemes() async throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light");if previous==nil {UserDefaults.standard.removeObject(forKey:"ssmsTheme")}}
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let original=table(),model=TableDesignerModel(load:{original},apply:{_ in original})
      await model.load();model.select(original.definitions[0])
      let host=NSHostingController(rootView:TableDesignerPanel(server:"Fixture",database:"Demo",initialKind:"INDEX",model:model,open:{_ in}))
      host.sizingOptions=[]
      let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:1100,height:800));window.orderFront(nil)
      defer {window.close()}
      try await Task.sleep(for:.milliseconds(100));host.view.layoutSubtreeIfNeeded()
      let fields=descendants(host.view).compactMap {$0 as? NSTextField}
      let name=try #require(fields.first {$0.stringValue=="IX_Name"})
      let filter=try #require(fields.first {$0.placeholderString=="İsteğe bağlı WHERE koşulu"})
      #expect(abs(host.view.convert(name.bounds,from:name).minX-host.view.convert(filter.bounds,from:filter).minX)<1)
      #expect(model.structure.keys==["Name"] && model.structure.descending==["Name"] && !model.canApply)
      let image=try #require(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds));host.view.cacheDisplay(in:host.view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-table-designer-selected-"+theme+".png"))
    }
  }

}
