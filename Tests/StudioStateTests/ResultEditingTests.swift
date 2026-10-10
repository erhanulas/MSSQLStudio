import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ResultEditingTests {
  @Test func editsStageOriginalValuesProtectKeysAndInvalidateOnRefresh() throws {
    _ = NSApplication.shared
    let grid = ResultController()
    grid.update(Rows(fields: [Field("Id",type:4),Field("Name")], values:[["1","A"],["2","B"]]), generation: 1)
    grid.editDefinition = TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int"),.init(id:2,name:"Name",type:"nvarchar(50)")],primaryKey:["Id"])
    grid.editingAllowed = { true }
    grid.tableView(grid.table, setObjectValue:"A", for:grid.table.tableColumns[2], row:0)
    #expect(grid.pendingEdits.isEmpty)
    grid.setEditValue("999", row:0, column:0)
    #expect(grid.pendingEdits[0]?.values[0] == "999")
    grid.setEditValue("1", row:0, column:0)
    #expect(grid.pendingEdits.isEmpty)
    grid.setEditValue("Updated", row:1, column:1)
    #expect(grid.result.values[1][1] == "B")
    #expect(grid.pendingEdits[1]?.values[1] == "Updated")
    #expect(try grid.pendingSQL().contains("N'2'"))
    grid.setEditValue("B", row:1, column:1)
    #expect(grid.pendingEdits.isEmpty)
    grid.setEditValue(nil, row:0, column:1)
    #expect(try grid.pendingSQL().contains("SET [Name] = NULL"))
    grid.editingAllowed = { false }
    grid.setEditValue("Blocked",row:0,column:1)
    #expect(grid.pendingEdits[0]?.values[1] == nil)
    grid.update(Rows(fields: [Field("Id",type:4),Field("Name")],values:[["1","New"]]),generation:2)
    #expect(grid.pendingEdits.isEmpty && grid.editDefinition == nil)
  }
  @Test func nativeFieldEditorReceivesFullValueAndStagesOnCommit() async throws {
    _ = NSApplication.shared
    let grid = ResultController()
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:850,height:450),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false; window.contentViewController = grid; defer { window.close() }
    var requestedCell: (Int, Int)?
    grid.requestEditing = { requestedCell = ($0, $1); return true }
    let original = String(repeating:"x",count:1200)
    grid.update(Rows(fields:[Field("Id",type:4),Field("Name")],values:[["1",original]]),generation:1)
    grid.table.editCell?(0, 2)
    #expect(requestedCell?.0 == 0 && requestedCell?.1 == 2)
    grid.editDefinition = TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int"),.init(id:2,name:"Name",type:"nvarchar(max)")],primaryKey:["Id"])
    grid.editingAllowed = { true }
    window.orderFront(nil); grid.view.layoutSubtreeIfNeeded(); grid.table.reloadData()
    try await Task.sleep(for:.milliseconds(50))
    grid.table.editCell?(0, 2)
    let editor = try #require(window.firstResponder as? NSTextView)
    #expect(editor.string == original)
    var draftNotifications = 0
    grid.editsChanged = { draftNotifications += 1 }
    editor.string = "Changed"
    editor.didChangeText()
    #expect(draftNotifications > 0)
    #expect(grid.hasDraftChanges)
    #expect(grid.pendingEdits.isEmpty)
    window.makeFirstResponder(grid.table)
    #expect(!grid.hasDraftChanges)
    #expect(grid.pendingEdits[0]?.values[1] == "Changed")
    #expect(grid.result.values[0][1] == original)
  }
  @Test func cancelDraftLeavesSnapshotAndPendingChangesUntouched() async throws {
    _ = NSApplication.shared
    let grid = ResultController()
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:850,height:450),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false; window.contentViewController = grid; defer { window.close() }
    grid.update(Rows(fields:[Field("Id",type:4),Field("Name")],values:[["1","Original"]]),generation:1)
    grid.editDefinition = TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int",identity:true),.init(id:2,name:"Name",type:"nvarchar(50)")],primaryKey:["Id"])
    grid.editingAllowed = { true }
    #expect(grid.readOnlyReason(column:0)?.contains("IDENTITY") == true)
    #expect(grid.table.tableColumns[1].headerToolTip?.contains("IDENTITY") == true)
    #expect(grid.readOnlyReason(column:1) == nil)
    window.orderFront(nil); grid.view.layoutSubtreeIfNeeded(); grid.table.reloadData()
    try await Task.sleep(for:.milliseconds(50))
    grid.table.editColumn(2,row:0,with:nil,select:true)
    let editor = try #require(window.firstResponder as? NSTextView)
    editor.string = "Draft"; editor.didChangeText()
    #expect(grid.hasDraftChanges)
    let escape = try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53))
    editor.keyDown(with: escape)
    #expect(!grid.hasDraftChanges)
    #expect(grid.pendingEdits.isEmpty)
    #expect(grid.result.values[0][1] == "Original")
  }
  @Test func aliasTypeCellsAreEditableWithoutChangingDeclaredType() throws {
    _ = NSApplication.shared
    let grid = ResultController()
    grid.update(Rows(fields:[Field("Id",type:4),Field("Code")],values:[["1","A"]]),generation:1)
    grid.editDefinition = TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int"),.init(id:2,name:"Code",type:"[dbo].[TDBGRUPKOD]",baseType:"varchar(12)")],primaryKey:["Id"])
    grid.editingAllowed = { true }
    #expect(grid.readOnlyReason(column:1) == nil)
    grid.setEditValue("B",row:0,column:1)
    #expect(grid.pendingEdits[0]?.values[1] == "B")
    #expect(try grid.pendingSQL().contains("SET [Code] = CONVERT(varchar(12), N'B')"))
    #expect(grid.editDefinition?.columns[1].type == "[dbo].[TDBGRUPKOD]")
  }
  @Test func filtersAndReorderedColumnsKeepSourceRowIdentity() async throws {
    _ = NSApplication.shared
    let grid = ResultController()
    grid.update(Rows(fields:[Field("Id",type:4),Field("Name")],values:[["1","A"],["2","B"]]),generation:1)
    grid.filter = "B"
    for _ in 0..<100 where grid.isProcessing { try await Task.sleep(for:.milliseconds(10)) }
    #expect(grid.visibleCount == 1)
    grid.editDefinition = TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int"),.init(id:2,name:"Name",type:"nvarchar(50)")],primaryKey:["Id"])
    grid.editingAllowed = { true }
    grid.table.moveColumn(2,toColumn:1)
    grid.tableView(grid.table,setObjectValue:"Changed",for:grid.table.tableColumns[1],row:0)
    #expect(grid.pendingEdits[1]?.values == ["2","Changed"])
    #expect(grid.pendingEdits[0] == nil)
  }
}

@MainActor @Suite(.serialized) struct TimelinePreviewUITests {
  @Test func historyAndPreviewRenderWithoutOverflow() async throws {
    _ = NSApplication.shared
    let state = StudioState(); state.historyEnabled = true
    state.history = [QueryRecord(server:"Demo SQL", database:"DemoDB", text:"SELECT * FROM dbo.Customers;\n-- Timeline SQL önizlemesi", seconds:0.125, status:"Başarılı")]
    let history = NSHostingController(rootView: HistoryPanel(state:state,open:{ _ in }))
    let preview = NSHostingController(rootView: DataChangesPreview(sql:"BEGIN TRANSACTION;\nUPDATE [dbo].[Customers] SET [Name] = N'İstanbul' WHERE [Id] = 7;\nCOMMIT;",target:"Demo SQL / DemoDB",submit:{}))
    for (name, controller, size) in [("timeline",history as NSViewController,NSSize(width:1120,height:760)),("data-preview",preview as NSViewController,NSSize(width:1000,height:720))] {
      let window = NSWindow(contentViewController:controller); window.styleMask=[.titled,.closable,.resizable]; window.setContentSize(size); window.isReleasedWhenClosed=false
      window.orderFront(nil); controller.view.layoutSubtreeIfNeeded()
      try await Task.sleep(for:.milliseconds(100))
      #expect(controller.view.frame.width <= size.width + 1)
      if let image = controller.view.bitmapImageRepForCachingDisplay(in:controller.view.bounds) {
        controller.view.cacheDisplay(in:controller.view.bounds,to:image)
        try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-\(name)-ui.png"))
      }
      window.close()
    }
  }
}

@MainActor @Suite(.serialized) struct RowActionsTests {
  @Test func newCloneDeleteAndRevertKeepOriginalSnapshotAndDefaultFields() throws {
    _ = NSApplication.shared
    let grid = ResultController()
    grid.update(Rows(fields:[Field("Id",type:4),Field("Name")],values:[["1","A"],["2","B"]]),generation:1)
    grid.editDefinition = TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int"),.init(id:2,name:"Name",type:"nvarchar(50)")],primaryKey:["Id"])
    grid.editingAllowed = { true }
    #expect(grid.table.focusRingType == .none)
    grid.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
    grid.appendRow(cloning:true)
    #expect(grid.pageCount == 3)
    #expect(grid.pendingEdits[-1]?.values == [nil,"A"])
    #expect(grid.tableView(grid.table,objectValueFor:grid.table.tableColumns[1],row:2) as? String == "")
    grid.setEditValue("3",row:2,column:0)
    #expect(try grid.pendingSQL().contains("INSERT INTO [dbo].[T] ([Id], [Name])"))
    grid.appendRow()
    grid.setEditValue("4",row:3,column:0)
    grid.setEditValue(nil,row:3,column:1)
    #expect(grid.pendingEdits[-2]?.touched == [0,1])
    grid.table.selectRowIndexes(IndexSet(integersIn:2...3),byExtendingSelection:false)
    grid.toggleSelectedDeletion()
    #expect(grid.pageCount == 2 && grid.pendingEdits.isEmpty)
    grid.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
    grid.toggleSelectedDeletion()
    #expect(try grid.pendingSQL().contains("DELETE FROM [dbo].[T]"))
    #expect(grid.pendingEdits[1]?.original == ["2","B"])
    #expect(!grid.tableView(grid.table,shouldEdit:grid.table.tableColumns[2],row:1))
    grid.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
    grid.revertSelectedRows()
    #expect(grid.pendingEdits.isEmpty)
    #expect(grid.result.values.count == 2)
  }
}

@MainActor @Suite(.serialized) struct RowActionsLayoutTests {
  @Test func editingToolbarFitsAndNewRowsStayVisibleUnderFilters() async throws {
    _ = NSApplication.shared
    let doc = QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Rows")
    doc.state = .ready; doc.results = [Rows(fields:[Field("Id",type:4),Field("Name")],values:[["1","A"]])]
    let controller = QueryController(document:doc)
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:830,height:680),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false; window.contentViewController = controller; defer { window.close() }
    let grid = try #require(controller.children.compactMap { $0 as? ResultController }.first)
    grid.editDefinition = TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int",identity:true),.init(id:2,name:"Name",type:"nvarchar(50)")],primaryKey:["Id"])
    grid.editingAllowed = { true }; controller.update()
    window.setContentSize(NSSize(width:830,height:680)); controller.view.frame.size = NSSize(width:830,height:680)
    window.orderFront(nil); controller.view.layoutSubtreeIfNeeded()
    func descendants(_ view:NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let bars = descendants(controller.view).filter { ["gridToolbar", "gridDataActions"].contains($0.accessibilityIdentifier()) }
    #expect(bars.count == 2)
    for control in bars.flatMap(descendants).compactMap({ $0 as? NSControl }) where !control.isHidden {
      let rect = controller.view.convert(control.bounds,from:control)
      #expect(rect.minX >= 0 && rect.maxX <= 831, "Editing toolbar overflow: \(type(of:control)) / \(control.accessibilityLabel() ?? "") hidden=\(control.isHiddenOrHasHiddenAncestor) \(rect)")
    }
    if let image = controller.view.bitmapImageRepForCachingDisplay(in:controller.view.bounds) {
      controller.view.cacheDisplay(in:controller.view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-grid-direct-ui.png"))
    }
    grid.filter = "no match"
    for _ in 0..<100 where grid.isProcessing { try await Task.sleep(for:.milliseconds(10)) }
    grid.appendRow()
    #expect(grid.pageCount == 1)
    grid.setEditValue("New",row:0,column:1)
    #expect(grid.pendingEdits[-1]?.values == [nil,"New"])
    #expect(try grid.pendingSQL().contains("([Name]) VALUES"))
    #expect(grid.pageExportIndices?.isEmpty == true)
  }
}


@MainActor @Suite(.serialized) struct GridHeaderInteractionTests {
  @Test func longHeadersFitAndResizeEdgeNeverTargetsFilter() throws {
    _ = NSApplication.shared
    let grid = ResultController()
    let title = String(repeating:"UzunKolonAdı",count:12)
    grid.update(Rows(fields:[Field("False",type:-7),Field("True",type:-7),Field(title)],values:[["0","1","x"]]),generation:1)
    let window = NSWindow(contentViewController:grid); window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width:830,height:400)); window.orderFront(nil)
    defer { window.close() }
    grid.view.layoutSubtreeIfNeeded()
    if let image = grid.view.bitmapImageRepForCachingDisplay(in:grid.view.bounds) {
      grid.view.cacheDisplay(in:grid.view.bounds,to:image)
      try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-v55-header-checkbox.png"))
    }
    let column = grid.table.tableColumns[3]
    #expect(column.width >= GridColumnSizing.headerWidth(title))
    let header = try #require(grid.table.headerView as? FilterHeader)
    let rect = header.headerRect(ofColumn:3)
    let hit = header.filterHitRect(column:3)
    #expect(hit.contains(NSPoint(x:rect.maxX-22,y:rect.midY)))
    for distance in [0.0,2,5,8,11] {
      #expect(!hit.contains(NSPoint(x:rect.maxX-distance,y:rect.midY)))
    }
    #expect(header.filterHitRect(column:0) == .zero)
  }
}
