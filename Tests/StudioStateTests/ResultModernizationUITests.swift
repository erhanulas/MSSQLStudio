import AppKit
import SQLServerKit
import SwiftUI
import Testing
@testable import MSSQLStudio

private actor PreparationCalls {
  var count = 0
  var active = 0
  var maximumActive = 0
  func started() { count += 1; active += 1; maximumActive = max(maximumActive, active) }
  func finished() { active -= 1 }
}

@MainActor @Suite(.serialized) struct ResultModernizationUITests {
  private func context(_ generation: Int) -> ResultEditingCoordinator.Context {
    .init(serverID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, serverGeneration: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, resultGeneration: generation, database: "D", sql: "SELECT * FROM dbo.T", fields: [Field("Id", type: 4)])
  }
  private func snapshot(_ id: Int) -> ResultEditingSnapshot {
    .init(objectID: id, table: .init(schema: "dbo", name: "T", columns: [.init(id: 1, name: "Id", type: "int")], primaryKey: ["Id"]))
  }
  @Test func prewarmingAndOpeningShareOnePreparationAndCachedMemoryResult() async throws {
    let coordinator = ResultEditingCoordinator(), calls = PreparationCalls(), key = context(1), prepared = snapshot(42)
    coordinator.warm(key) { await calls.started(); try await Task.sleep(for: .milliseconds(30)); return (prepared, false) }
    let first = try await coordinator.prepared(key) { throw SQLFailure("Must reuse the in-flight preparation") }
    let second = try await coordinator.prepared(key) { throw SQLFailure("Must reuse memory without disk/network") }
    #expect(first.snapshot.objectID == 42 && second.snapshot.objectID == 42 && !second.cached)
    #expect(await calls.count == 1)
  }
  @Test func cancelledLatePreparationCannotReplaceNewResultAndExplicitRetryWorks() async throws {
    let coordinator = ResultEditingCoordinator(), oldKey = context(1), newKey = context(2), oldValue = snapshot(41), newValue = snapshot(42)
    let calls = PreparationCalls()
    let stale = Task { try await coordinator.prepared(oldKey) {
      await calls.started()
      await withCheckedContinuation { continuation in DispatchQueue.global().asyncAfter(deadline: .now() + 0.06) { continuation.resume() } }
      await calls.finished()
      return (oldValue, false)
    } }
    try await Task.sleep(for: .milliseconds(5))
    let fresh = try await coordinator.prepared(newKey) { await calls.started(); await calls.finished(); return (newValue, false) }
    #expect(await calls.maximumActive == 1)
    #expect(fresh.snapshot.objectID == 42)
    do { _ = try await stale.value; Issue.record("Stale preparation was accepted") } catch { #expect(error is CancellationError) }
    let failureKey = context(3)
    do { _ = try await coordinator.prepared(failureKey) { throw SQLFailure("Synthetic network failure") }; Issue.record("Failure was swallowed") } catch { #expect(error is SQLFailure) }
    let retry = try await coordinator.prepared(failureKey) { (newValue, false) }
    #expect(retry.snapshot.objectID == 42)
  }
  @Test func nativeIntegerDraftCannotCommitOrEnterSQLAndValidAliasValueCan() async throws {
    let grid = ResultController()
    grid.update(Rows(fields: [Field("Id", type: 4), Field("Count", type: 4)], values: [["1", "10"]]), generation: 1)
    grid.editDefinition = .init(schema: "dbo", name: "T", columns: [.init(id: 1, name: "Id", type: "int", nullable: false), .init(id: 2, name: "Count", type: "[dbo].[Counter]", baseType: "int")], primaryKey: ["Id"])
    grid.editingAllowed = { true }
    let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 850, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = grid; window.setContentSize(NSSize(width: 850, height: 420)); grid.view.frame.size = NSSize(width: 850, height: 420); defer { window.close() }
    window.orderFront(nil); grid.view.layoutSubtreeIfNeeded(); grid.table.reloadData()
    try await Task.sleep(for: .milliseconds(50))
    grid.table.selectCell(row:0,column:2)
    grid.table.editCell?(0, 2)
    let editor = try #require(window.firstResponder as? NSTextView)
    editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
    editor.insertText("abc", replacementRange: editor.selectedRange())
    #expect(!editor.string.contains("abc"))
    editor.string = "not an integer"; editor.didChangeText()
    #expect(grid.editValidationMessage?.contains("Tam sayı") == true)
    let invalidCommitted = window.makeFirstResponder(grid.table)
    #expect(!invalidCommitted)
    let columns=grid.table.cellColumns
    grid.table.selectAllCells(nil)
    #expect(grid.table.cellColumns==columns && window.firstResponder === editor)
    #expect(grid.pendingEdits.isEmpty && grid.result.values[0][1] == "10")
    grid.setEditValue("2147483648", row: 0, column: 1)
    #expect(grid.pendingEdits.isEmpty)
    editor.string = "25"; editor.didChangeText()
    let validCommitted = window.makeFirstResponder(grid.table)
    #expect(validCommitted)
    #expect(grid.editValidationMessage == nil && grid.pendingEdits[0]?.values[1] == "25")
    let sql = try grid.pendingSQL()
    #expect(sql.contains("SET [Count] = 25 WHERE [Id] = 1;"))
    #expect(!sql.contains("not an integer") && !sql.contains("N'10'"))
    grid.setColumnPinned(1, pinned: true)
    grid.frozenTable.editCell?(0, 1)
    let frozenEditor = try #require(window.firstResponder as? ResultFieldEditor)
    frozenEditor.string = "invalid"; frozenEditor.didChangeText()
    let frozenCommitted = window.makeFirstResponder(grid.table)
    #expect(!frozenCommitted && grid.pendingEdits[0]?.values[1] == "25")
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    frozenEditor.keyDown(with: escape)
    #expect(grid.editValidationMessage == nil && grid.pendingEdits[0]?.values[1] == "25")
    grid.discardEdits(); #expect(grid.editValidationMessage == nil)
  }
  @Test func readyQueryWarmsMetadataAndEditButtonDoesNotStartAnotherNetworkRead() async throws {
    let folder = URL(fileURLWithPath: "/tmp/MSSQLStudio-ready-edit-fixture-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let index = CatalogDiskIndex(url: folder.appendingPathComponent("catalog.sqlite"))
    let server = ConnectedServer(profile: ServerProfile(), password: ""); server.online = true
    var requests = 0
    server.asyncCatalogFixture = { sql in
      requests += 1
      try await Task.sleep(for: .milliseconds(10))
      var result = Execution()
      if sql.contains("dm_exec_describe_first_result_set") { result.results = [Rows(values: [["Id", nil, "D", "dbo", "T", "Id", nil, nil, "1"]])] }
      else { result.results = [Rows(values: [["42"]]), Rows(values: [["1", "Id", "int", "0", "0", nil, nil, nil, "0", nil, nil, nil, "0", "0", "0", "int"]]), Rows(values: [["Id", "PK_T"]]), Rows(values: [["0", nil]])] }
      return result
    }
    let document = QueryDocument(server: server, database: "D", title: "Prepared editing")
    document.sql = "SELECT * FROM dbo.T;"; document.state = .ready
    document.executionFixture = { _, _ in var result = Execution(); result.results = [Rows(fields: [Field("Id", type: 4)], values: [["1"]])]; return result }
    document.sessionProbeFixture = { _, _ in var result = Execution(); result.results = [Rows(values: [["0", "D"]])]; return result }
    let controller = QueryController(document: document, editingIndex: index)
    document.execute()
    for _ in 0..<300 where document.task != nil { try await Task.sleep(for: .milliseconds(5)) }
    controller.update()
    for _ in 0..<100 where requests < 2 { try await Task.sleep(for: .milliseconds(5)) }
    try await Task.sleep(for: .milliseconds(20))
    #expect(requests == 2 && document.canRefresh)
    let grid = try #require(controller.children.compactMap { $0 as? ResultController }.first)
    #expect(grid.editDefinition == nil)
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let button = try #require(descendants(controller.view).first { $0.accessibilityIdentifier() == "gridEdit" } as? NSButton)
    #expect(button.isEnabled); button.performClick(nil)
    for _ in 0..<100 where grid.editDefinition == nil { try await Task.sleep(for: .milliseconds(5)) }
    #expect(grid.editDefinition?.primaryKey == ["Id"] && requests == 2)
    #expect((grid.table.tableColumns[1].headerCell as? FilterHeaderCell)?.primaryKey == true)
  }
  @Test func whiteGridAndLocalFilterRenderInBothThemesWithoutCellViews() async throws {
    let previous = UserDefaults.standard.string(forKey: "ssmsTheme")
    defer { StudioTheme.apply(previous ?? "light"); if previous == nil { UserDefaults.standard.removeObject(forKey: "ssmsTheme") } }
    for mode in ["light", "dark"] {
      StudioTheme.apply(mode)
      let grid = ResultController()
      let fields = [Field("CustomerID", type: 4), Field("CustomerName", size: 80), Field("City", size: 40), Field("Balance", type: 3, size: 18, scale: 2), Field("Active", type: -7)]
      let rows = Rows(fields: fields, values: (1...40).map { [String($0), "Customer \($0)", $0.isMultiple(of: 2) ? "İstanbul" : "Ankara", "1250.50", "1"] })
      grid.update(rows, generation: 1)
      let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 1000, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentViewController = grid; window.setContentSize(NSSize(width: 1000, height: 420)); grid.view.frame.size = NSSize(width: 1000, height: 420); window.orderFront(nil)
      defer { window.close() }
      var rule = ColumnRule(); rule.choices = [.text("İstanbul")]
      try grid.setRule(rule, column: 2)
      for _ in 0..<100 where grid.isProcessing { try await Task.sleep(for: .milliseconds(5)) }
      grid.setColumnPinned(0, pinned: true)
      grid.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
      grid.view.layoutSubtreeIfNeeded()
      #expect(abs(grid.rowGutter.rowRect(0).minY - grid.rowGutter.viewport.minY) < 1)
      let fixedRow = grid.rowGutter.convert(grid.frozenTable.rect(ofRow: 0), from: grid.frozenTable)
      #expect(abs(fixedRow.minY - grid.rowGutter.rowRect(0).minY) < 1)
      window.displayIfNeeded()
      #expect(grid.visibleCount == 20 && grid.result.values.count == 40)
      #expect(grid.table.backgroundColor == StudioTheme.resultCanvas && grid.table.gridColor == StudioTheme.resultBorder)
      #expect((grid.table.tableColumns[3].headerCell as? FilterHeaderCell)?.active == true)
      #expect(!grid.responds(to: #selector(NSTableViewDelegate.tableView(_:viewFor:row:))))
      let bitmap = try #require(grid.view.bitmapImageRepForCachingDisplay(in: grid.view.bounds))
      grid.view.cacheDisplay(in: grid.view.bounds, to: bitmap)
      try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/MSSQLStudio-results-modern-\(mode).png"))
      let panel = NSHostingController(rootView: ColumnFilterPanel(rows: rows, column: 2, initial: rule, apply: { _ in }))
      let popup = NSWindow(contentViewController: panel); popup.isReleasedWhenClosed = false
      popup.setContentSize(NSSize(width: 400, height: 540)); popup.setFrameOrigin(NSPoint(x: -3000, y: 0)); popup.orderFront(nil)
      try await Task.sleep(for: .milliseconds(80)); panel.view.layoutSubtreeIfNeeded()
      let image = try #require(panel.view.bitmapImageRepForCachingDisplay(in: panel.view.bounds))
      panel.view.cacheDisplay(in: panel.view.bounds, to: image)
      try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/MSSQLStudio-result-filter-modern-\(mode).png"))
      popup.close()
    }
  }
}
