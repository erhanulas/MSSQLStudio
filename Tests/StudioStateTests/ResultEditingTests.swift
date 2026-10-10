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
    grid.setEditValue("999", row:0, column:0)
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
    let original = String(repeating:"x",count:1200)
    grid.update(Rows(fields:[Field("Id",type:4),Field("Name")],values:[["1",original]]),generation:1)
    grid.editDefinition = TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int"),.init(id:2,name:"Name",type:"nvarchar(max)")],primaryKey:["Id"])
    grid.editingAllowed = { true }
    window.orderFront(nil); grid.view.layoutSubtreeIfNeeded(); grid.table.reloadData()
    try await Task.sleep(for:.milliseconds(50))
    grid.table.editColumn(2,row:0,with:nil,select:true)
    let editor = try #require(window.firstResponder as? NSTextView)
    #expect(editor.string == original)
    editor.string = "Changed"; window.makeFirstResponder(grid.table)
    #expect(grid.pendingEdits[0]?.values[1] == "Changed")
    #expect(grid.result.values[0][1] == original)
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
