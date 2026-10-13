import AppKit
import SQLServerKit
import Testing

@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorInsertPresentationTests {
  @Test func singleCaretMapsColumnsAndValuesWithoutChangingSQLUndoOrFocus() async throws {
    _ = NSApplication.shared
    let sql =
      "INSERT INTO dbo.T (STOK, CARI, AD)\nVALUES (@stok, CONCAT(N'a,b', N'🦊'), DEFAULT),\n       (2, 3, N'x');"
    let doc = QueryDocument(
      server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master",
      title: "Insert mapping")
    doc.server.online = false
    doc.sql = sql
    let controller = EditorController(document: doc)
    let window = NSWindow(
      contentRect: NSRect(x: -3000, y: 0, width: 950, height: 400), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.surface
    window.orderFront(nil)
    window.makeFirstResponder(controller.editor)
    defer { window.close() }
    controller.surface.layoutSubtreeIfNeeded()
    controller.resizeToViewport()
    let editor = controller.editor
    let undo = try #require(editor.undoManager)
    let hadUndo = undo.canUndo
    let oldTheme = UserDefaults.standard.string(forKey: "ssmsTheme")
    defer {
      StudioTheme.apply(oldTheme ?? "light")
      if oldTheme == nil { UserDefaults.standard.removeObject(forKey: "ssmsTheme") }
    }
    for mode in ["light", "dark"] {
      StudioTheme.apply(mode)
      editor.setSelectedRange(
        NSRange(location: (sql as NSString).range(of: "N'a,b'").location + 2, length: 0))
      controller.updateOccurrences()
      #expect(!controller.insertPresentation.isShown)
      editor.mouseSelectionEnded?()
      #expect(controller.insertPresentation.match?.column == "CARI")
      #expect(controller.insertPresentation.isShown)
      #expect(controller.occurrenceHighlights.insertRanges.count == 2)
      #expect(
        window.firstResponder === editor && editor.string == sql && doc.sql == sql
          && undo.canUndo == hadUndo)
      editor.setSelectedRange(
        NSRange(location: (sql as NSString).range(of: "STOK").location + 1, length: 0))
      editor.mouseSelectionEnded?()
      #expect(controller.occurrenceHighlights.insertRanges.count == 3)
      try await Task.sleep(for: .milliseconds(50))
      controller.surface.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      #expect(
        !controller.occurrenceHighlights.highlightRects(
          in: controller.occurrenceHighlights.bounds,
          for: controller.occurrenceHighlights.insertRanges
        ).isEmpty)
      let image = try #require(
        controller.surface.bitmapImageRepForCachingDisplay(in: controller.surface.bounds))
      controller.surface.cacheDisplay(in: controller.surface.bounds, to: image)
      try image.representation(using: .png, properties: [:])?.write(
        to: URL(fileURLWithPath: "/tmp/MSSQLStudio-insert-mapping-\(mode).png"))
      let preview = controller.insertPresentation.previewView
      preview.layoutSubtreeIfNeeded()
      preview.window?.displayIfNeeded()
      preview.displayIfNeeded()
      #expect(
        preview.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "→ STOK" })
      StudioTheme.apply(mode == "light" ? "dark" : "light")
      #expect(
        preview.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "@stok" }?
          .textColor == StudioTheme.text)
      StudioTheme.apply(mode)
      let previewImage = try #require(preview.bitmapImageRepForCachingDisplay(in: preview.bounds))
      preview.cacheDisplay(in: preview.bounds, to: previewImage)
      try previewImage.representation(using: .png, properties: [:])?.write(
        to: URL(fileURLWithPath: "/tmp/MSSQLStudio-insert-preview-\(mode).png"))
      editor.dismissSuggestions?()
      controller.updateOccurrences()
      #expect(!controller.insertPresentation.isShown)
      editor.setSelectedRange(NSRange(location: 0, length: 0))
      controller.updateOccurrences()
      #expect(
        controller.insertPresentation.match == nil
          && controller.occurrenceHighlights.insertRanges.isEmpty)
    }
    #expect(doc.lastExecutedSQL == nil)
  }
  @Test func lateLargeSourceAnalysisCannotReplaceNewInsertMapping() async throws {
    _ = NSApplication.shared
    let doc = QueryDocument(
      server: ConnectedServer(profile: ServerProfile(), password: ""), database: "master",
      title: "Late insert")
    doc.server.online = false
    doc.sql = "/*" + String(repeating: "x", count: 51000) + "*/\nINSERT dbo.T(OldColumn) VALUES(1)"
    let controller = EditorController(document: doc)
    controller.editor.setSelectedRange(NSRange(location: doc.sql.utf16.count - 2, length: 0))
    controller.updateOccurrences()
    #expect(controller.insertPresentation.isAnalyzing)
    controller.replaceText("INSERT dbo.T(NewColumn) VALUES(2)")
    controller.editor.setSelectedRange(
      NSRange(location: (doc.sql as NSString).range(of: "2").location, length: 0))
    controller.updateOccurrences()
    try await Task.sleep(for: .milliseconds(100))
    #expect(controller.insertPresentation.match?.column == "NewColumn")
    #expect(!controller.insertPresentation.isAnalyzing && doc.lastExecutedSQL == nil)
  }

}
