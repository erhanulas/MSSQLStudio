import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorBlockGuideTests {
  private let sql = """
  DECLARE @ready bit = 1;
  IF @ready = 1
  BEGIN
      SELECT N'😀 BEGIN END' AS Label;
      IF @ready = 1
      BEGIN
          SELECT CASE WHEN (1) = 1 THEN 2 END AS Value;
      END
  END
  """

  private func fixture(_ source: String, width: CGFloat = 800, height: CGFloat = 360) -> (QueryDocument, EditorController, NSWindow) {
    _ = NSApplication.shared
    let server = ConnectedServer(profile: ServerProfile(), password: ""); server.online = false
    let document = QueryDocument(server: server, database: "master", title: "Block guides")
    document.sql = source
    let controller = EditorController(document: document)
    let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.surface
    controller.surface.layoutSubtreeIfNeeded(); controller.resizeToViewport()
    controller.editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
    return (document, controller, window)
  }

  @Test func nestedGuidesFollowCaretFoldsAndSourceChanges() throws {
    let (document, controller, window) = fixture(sql); defer { window.close() }
    let overlay = controller.occurrenceHighlights
    let text = sql as NSString
    controller.editor.setSelectedRange(NSRange(location: text.range(of: "SELECT CASE").location + 3, length: 0))
    controller.updateOccurrences()
    #expect(overlay.blockGuides.guides.count == 2)
    #expect(overlay.blockGuides.guides.filter(\.active).count == 1)
    #expect(overlay.blockGuides.guides.last?.active == true)
    #expect(overlay.blockRanges.isEmpty) // Body caret changes guides, not keyword matching.
    controller.editor.setSelectedRange(NSRange(location: text.range(of: "SELECT N").location, length: 6))
    controller.updateOccurrences()
    #expect(overlay.blockGuides.guides.count == 2 && overlay.blockGuides.guides.allSatisfy { !$0.active })
    let inner = try #require(controller.regions.last)
    controller.toggleFold(inner); controller.updateOccurrences()
    #expect(document.sql == sql && overlay.blockGuides.guides.count == 1)
    controller.toggleFold(try #require(controller.regions.first)); controller.updateOccurrences()
    #expect(overlay.blockGuides.guides.isEmpty)
    controller.expandAll(); controller.updateOccurrences()
    #expect(overlay.blockGuides.guides.count == 2 && controller.editor.string == sql)
    controller.replaceText("BEGIN TRAN;\nSELECT '[BEGIN] END';\n-- BEGIN\nEND CONVERSATION @h;")
    controller.updateOccurrences()
    #expect(overlay.blockGuides.guides.isEmpty)
    controller.replaceText("BEGIN\r\n SELECT 1;\r\nEND")
    controller.updateOccurrences()
    #expect(overlay.blockGuides.guides.count == 1)
    controller.replaceText("BEGIN SELECT 1 END")
    controller.updateOccurrences()
    #expect(overlay.blockGuides.guides.isEmpty)
  }

  @Test func nativeGuideGeometryAndThemeRenderingPreserveTextAndUndo() throws {
    let previous = UserDefaults.standard.string(forKey: "ssmsTheme")
    defer {
      StudioTheme.apply(previous ?? "light")
      if previous == nil { UserDefaults.standard.removeObject(forKey: "ssmsTheme") }
    }
    let (document, controller, window) = fixture(sql); defer { window.close() }
    let editor = controller.editor, overlay = controller.occurrenceHighlights
    editor.setSelectedRange(NSRange(location: (sql as NSString).range(of: "SELECT CASE").location, length: 0))
    controller.updateOccurrences()
    let undo = try #require(editor.undoManager), couldUndo = undo.canUndo
    for mode in ["light", "dark"] {
      StudioTheme.apply(mode); controller.applyTheme()
      editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
      let segments = overlay.blockGuides.segments(in: overlay, editor: editor, dirtyRect: overlay.bounds)
      #expect(segments.count == 2 && segments.filter(\.active).count == 1)
      let outer = try #require(segments.first), inner = try #require(segments.last)
      #expect(inner.rect.minX > outer.rect.minX && inner.rect.minY > outer.rect.minY && inner.rect.maxY < outer.rect.maxY)
      let opening = try #require(editor.rects(forCharacterRange: overlay.blockGuides.guides[0].opening)?.first?.rectValue)
      let closing = try #require(editor.rects(forCharacterRange: overlay.blockGuides.guides[0].closing)?.first?.rectValue)
      let first = overlay.convert(opening, from: editor), last = overlay.convert(closing, from: editor)
      #expect(abs(outer.rect.minY - first.maxY) < 1 && abs(outer.rect.maxY - last.minY) < 1)
      #expect(outer.rect.maxX < first.minX)
      #expect(overlay.hitTest(.zero) == nil)
      #expect(editor.textLayoutManager != nil && document.sql == sql && editor.string == sql && undo.canUndo == couldUndo)
      let storage = try #require(editor.textContentStorage?.textStorage)
      #expect(storage.attribute(.foregroundColor, at: overlay.blockGuides.guides[0].opening.location, effectiveRange: nil) as? NSColor == StudioTheme.syntax(.keyword))
      let bitmap = try #require(controller.surface.bitmapImageRepForCachingDisplay(in: controller.surface.bounds))
      controller.surface.cacheDisplay(in: controller.surface.bounds, to: bitmap)
      let data = try #require(bitmap.representation(using: .png, properties: [:]))
      try data.write(to: URL(fileURLWithPath: "/tmp/MSSQLStudio-block-guides-\(mode).png"))
    }
  }

  @Test func offscreenEndpointsContinueThroughViewportAndHorizontalScroll() throws {
    let source = "        BEGIN\n" + String(repeating: "            SELECT 123456789 AS A_Long_Column_Name;\n", count: 100) + "        END"
    let (_, controller, window) = fixture(source, width: 360, height: 200); defer { window.close() }
    let editor = controller.editor, overlay = controller.occurrenceHighlights
    editor.setSelectedRange(NSRange(location: 300, length: 0)); controller.updateOccurrences()
    let clip = controller.scroll.contentView
    func scroll(_ x: CGFloat) -> EditorBlockGuides.Segment? {
      clip.scroll(to: NSPoint(x: x, y: 300)); controller.scroll.reflectScrolledClipView(clip)
      editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
      return overlay.blockGuides.segments(in: overlay, editor: editor, dirtyRect: overlay.bounds).first
    }
    let first = try #require(scroll(0)), shifted = try #require(scroll(20))
    #expect(abs(first.rect.minX - shifted.rect.minX - 20) < 1)
    #expect(abs(shifted.rect.minY - overlay.bounds.minY) < 1 && abs(shifted.rect.maxY - overlay.bounds.maxY) < 1)
    #expect(shifted.active && overlay.frame.size == clip.bounds.size)
  }

  @Test func tabsAndSpacesShareIndentationAndBatchBoundariesStaySeparate() throws {
    let source = "BEGIN\nGO\nEND\n\tBEGIN\n\t SELECT 1\n\tEND\n    BEGIN\n     SELECT 2\n    END"
    let (_, controller, window) = fixture(source); defer { window.close() }
    let overlay = controller.occurrenceHighlights, guides = overlay.blockGuides
    controller.editor.setSelectedRange(NSRange(location: 0, length: 0)); controller.updateOccurrences()
    #expect(guides.guides.map(\.indentation) == ["\t", "    "])
    #expect(guides.guides.allSatisfy { !$0.active })
    let segments = guides.segments(in: overlay, editor: controller.editor, dirtyRect: overlay.bounds)
    #expect(segments.count == 2)
    if segments.count == 2 { #expect(abs(segments[0].rect.minX - segments[1].rect.minX) < 1) }
  }
}
