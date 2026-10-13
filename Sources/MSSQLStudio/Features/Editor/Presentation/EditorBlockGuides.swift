import AppKit
import SQLServerKit

/// Caches lexical structure by source; caret and fold changes only project it.
@MainActor final class EditorBlockGuides {
  struct Guide: Equatable {
    let opening: NSRange
    let closing: NSRange
    let indentation: String
    let active: Bool
  }
  struct Segment {
    let rect: NSRect
    let active: Bool
  }
  private var source: String?
  private var structure = SQLBlockStructure("")
  private var blocks: [(SQLBlockStructure.Pair, String)] = []
  private(set) var guides: [Guide] = []

  func clear() { guides = [] }

  func update(source: String, selection: NSRange, projection: SQLFolding.Projection?) -> [NSRange] {
    if self.source != source {
      self.source = source
      structure = SQLBlockStructure(source)
      let text = source as NSString
      blocks = structure.pairs.compactMap { pair in
        guard pair.kind == .block else { return nil }
        let line = text.lineRange(for: pair.opening)
        guard text.lineRange(for: pair.closing).location != line.location else { return nil }
        let prefix = text.substring(with: NSRange(location: line.location, length: pair.opening.location - line.location))
        return (pair, String(prefix.prefix { $0 == " " || $0 == "\t" }))
      }
    }
    let active = selection.length == 0 ? blocks.last(where: {
      $0.0.opening.location <= selection.location && selection.location <= NSMaxRange($0.0.closing)
    })?.0 : nil
    func visible(_ range: NSRange) -> NSRange? {
      guard let projection else { return range }
      guard !projection.regions.contains(where: { NSIntersectionRange($0.hidden, range).length > 0 }) else { return nil }
      return NSRange(location: projection.displayOffset(range.location), length: range.length)
    }
    guides = blocks.compactMap { pair, indentation in
      guard let opening = visible(pair.opening), let closing = visible(pair.closing) else { return nil }
      return Guide(opening: opening, closing: closing, indentation: indentation, active: pair == active)
    }
    return selection.length == 0 ? structure.matchingPair(at: selection.location).compactMap(visible) : []
  }

  func segments(in overlay: NSView, editor: NSTextView, dirtyRect: NSRect) -> [Segment] {
    guard let content = editor.textContentStorage, let layout = editor.textLayoutManager else { return [] }
    let viewport = layout.textViewportLayoutController.viewportRange ?? content.documentRange
    let start = content.offset(from: content.documentRange.location, to: viewport.location)
    let end = content.offset(from: content.documentRange.location, to: viewport.endLocation)
    let visible = NSRange(location: start, length: max(0, end - start))
    let font = editor.font ?? StudioTheme.codeFont
    let space = (" " as NSString).size(withAttributes: [.font: font]).width
    let tab = editor.defaultParagraphStyle?.defaultTabInterval ?? space * 4
    let pixel = 1 / (overlay.window?.backingScaleFactor ?? 2)
    func rect(for range: NSRange) -> NSRect? {
      guard let start = content.location(content.documentRange.location, offsetBy: range.location),
        let end = content.location(start, offsetBy: range.length),
        let textRange = NSTextRange(location: start, end: end) else { return nil }
      var result: NSRect?
      layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
        result = overlay.convert(rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y), from: editor)
        return false
      }
      return result
    }
    var result: [Segment] = []
    for guide in guides {
      guard guide.opening.location < end, NSMaxRange(guide.closing) > start else { continue }
      var top = overlay.bounds.minY, bottom = overlay.bounds.maxY
      if NSIntersectionRange(guide.opening, visible).length > 0 {
        guard let opening = rect(for: guide.opening) else { continue }
        top = max(top, opening.maxY)
      }
      if NSIntersectionRange(guide.closing, visible).length > 0 {
        guard let closing = rect(for: guide.closing) else { continue }
        bottom = min(bottom, closing.minY)
      }
      var indent: CGFloat = 0
      for character in guide.indentation {
        indent = character == "\t" && tab > 0 ? (floor(indent / tab) + 1) * tab : indent + space
      }
      let padding = editor.textContainer?.lineFragmentPadding ?? 0
      let point = overlay.convert(NSPoint(x: editor.textContainerOrigin.x + padding + indent - space / 2, y: 0), from: editor)
      let frame = NSRect(x: (point.x / pixel).rounded() * pixel, y: top, width: pixel, height: max(0, bottom - top))
      if frame.height > 0, frame.intersects(overlay.bounds), frame.intersects(dirtyRect) {
        result.append(Segment(rect: frame, active: guide.active))
      }
    }
    return result
  }
}
