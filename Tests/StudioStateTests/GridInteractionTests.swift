import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct GridInteractionTests {
  @Test func cellRangeRowGutterCopyAndColumnReorder() throws {
    _ = NSApplication.shared
    let controller = ResultController()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = controller
    controller.update(Rows(fields: [Field("ID", type: 4), Field("Şehir", type: -9, size: 50)], values: [["1", "İstanbul"], ["2", nil]]))
    controller.view.frame=NSRect(x:0,y:0,width:1000,height:500)
    controller.view.layoutSubtreeIfNeeded()
    let table = controller.table
    func click(_ row: Int, _ column: Int, shift: Bool = false) throws {
      let target:NSView = column == 0 ? controller.rowGutter:table
      let rect = column == 0 ? controller.rowGutter.rowRect(row):table.frameOfCell(atColumn: column, row: row)
      let point = target.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
      let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
      target.mouseDown(with: event)
    }
    try click(0, 2)
    table.copySelection()
    #expect(NSPasteboard.general.string(forType: .string) == "İstanbul")
    table.copyWithHeaders()
    #expect(NSPasteboard.general.string(forType: .string) == "Şehir\nİstanbul")
    #expect(table.cellColumns == IndexSet(integer: 2))
    try click(1, 2, shift: true)
    table.copySelection()
    #expect(NSPasteboard.general.string(forType: .string) == "İstanbul\nNULL")
    try click(1, 0)
    table.copySelection()
    #expect(NSPasteboard.general.string(forType: .string) == "2\tNULL")
    table.copyWithHeaders()
    #expect(NSPasteboard.general.string(forType: .string) == "ID\tŞehir\n2\tNULL")
    table.moveColumn(2, toColumn: 1)
    try click(0, 1)
    table.copySelection()
    #expect(NSPasteboard.general.string(forType: .string) == "İstanbul")
    #expect(table.tableColumns[1].headerToolTip == "Şehir · nvarchar(50)")
  }
  @Test func pinnedTabsSurviveBulkClosingInEitherDirection() throws {
    _ = NSApplication.shared
    let state = StudioState()
    state.recoveryEnabled = false
    let server = ConnectedServer(profile: ServerProfile(), password: "")
    let documents = (0..<5).map { QueryDocument(server: server, database: "master", title: "Tab \($0)") }
    state.documents = documents; state.active = documents[2]
    let controller = WorkbenchController(state: state)
    _ = controller.view
    func invoke(_ index: Int, on doc: QueryDocument) throws {
      let menu = controller.tabMenu(for: doc)
      let item = try #require(menu.item(at: index))
      #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
    }
    try invoke(0, on: documents[4])
    #expect(documents[4].pinned)
    try invoke(2, on: documents[2])
    #expect(state.documents.map(\.title) == ["Tab 0", "Tab 1", "Tab 2", "Tab 4"])
    try invoke(3, on: documents[2])
    #expect(state.documents.map(\.title) == ["Tab 2", "Tab 4"])
    try invoke(4, on: documents[2])
    #expect(state.documents.count == 2)
    try invoke(1, on: documents[4])
    #expect(state.documents.count == 1)
  }
  @Test func repeatRejectsMutationAndKeepsQueryContext() {
    #expect(TSQL.canRepeatRead("SELECT 1; -- UPDATE ignored\nSELECT N'EXEC';"))
    #expect(TSQL.canRepeatRead("WITH c AS (SELECT 1 AS n) SELECT * FROM c"))
    for sql in ["SELECT * INTO backup FROM t", "SELECT 1; DELETE FROM t", "EXEC p", "SELECT NEXT VALUE FOR seq", "BEGIN TRAN; SELECT 1", "SELECT 1; KILL 42", "SELECT 1\nGO 20", "UPDATE t SET n = 1"] { #expect(!TSQL.canRepeatRead(sql)) }
    #expect(Field("n", type: 3, size: 18, scale: 2).dataType == "decimal(18,2)")
  }
}
