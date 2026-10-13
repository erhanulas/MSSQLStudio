import AppKit
import SQLServerKit

/// A cached lexical mapping and a read-only preview. TextKit retains the source,
/// glyph layout, native selection and undo; decorations never become SQL text.
@MainActor final class EditorInsertPresentation {
  var didResolve: (() -> Void)?
  private var analysisTask: Task<Void, Never>?
  private var generation = UUID()
  var isAnalyzing: Bool { analysisTask != nil }
  private var source: String?
  private var mapping = SQLInsertMapping("")
  private let popover = NSPopover()
  private let panel = NSViewController()
  private let title = NSTextField(labelWithString: "")
  private let column = NSTextField(labelWithString: "")
  private let value = NSTextField(wrappingLabelWithString: "")
  private var wantsPreview = false
  private var lastSelection: NSRange?
  private var suppressedSelection: NSRange?
  private(set) var match: SQLInsertMapping.Match?
  var previewView: NSView { panel.view }
  var isShown: Bool { popover.isShown }
  init() {
    panel.view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 94))
    StudioTheme.surface(panel.view, card: true)
    title.font = .systemFont(ofSize: 10)
    column.font = .systemFont(ofSize: 12, weight: .semibold)
    value.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    title.lineBreakMode = .byTruncatingMiddle
    column.lineBreakMode = .byTruncatingMiddle
    value.maximumNumberOfLines = 2
    value.lineBreakMode = .byTruncatingTail
    for field in [title, column, value] {
      field.translatesAutoresizingMaskIntoConstraints = false
      panel.view.addSubview(field)
      field.leadingAnchor.constraint(equalTo: panel.view.leadingAnchor, constant: 12).isActive =
        true
      field.trailingAnchor.constraint(equalTo: panel.view.trailingAnchor, constant: -12).isActive =
        true
    }
    NSLayoutConstraint.activate([
      title.topAnchor.constraint(equalTo: panel.view.topAnchor, constant: 10),
      column.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
      value.topAnchor.constraint(equalTo: column.bottomAnchor, constant: 5),
      value.bottomAnchor.constraint(lessThanOrEqualTo: panel.view.bottomAnchor, constant: -10),
    ])
    popover.contentViewController = panel
    popover.contentSize = panel.view.frame.size
    popover.animates = false
    popover.behavior = .semitransient
    panel.view.setAccessibilityIdentifier("sqlInsertColumnPreview")
  }
  func refreshTheme() {
    StudioTheme.surface(panel.view, card: true)
    title.textColor = StudioTheme.muted
    column.textColor = StudioTheme.accent
    value.textColor = StudioTheme.text
  }
  func requestPreview() {
    wantsPreview = true
    suppressedSelection = nil
  }
  func hidePreview() {
    wantsPreview = false
    popover.close()
  }
  func dismissPreview() {
    suppressedSelection = lastSelection
    hidePreview()
  }
  deinit { analysisTask?.cancel() }
  func clear() {
    match = nil
    hidePreview()
    if analysisTask != nil {
      generation = UUID()
      analysisTask?.cancel()
      analysisTask = nil
      source = nil
    }
  }
  private func prepare(_ source: String) {
    guard self.source != source else { return }
    analysisTask?.cancel()
    generation = UUID()
    self.source = source
    suppressedSelection = nil
    if source.utf16.count <= 50000 {
      mapping = SQLInsertMapping(source)
      analysisTask = nil
      return
    }
    mapping = SQLInsertMapping("")
    let request = generation
    analysisTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) { SQLInsertMapping(source) }
      let resolved = await withTaskCancellationHandler(
        operation: { await worker.value }, onCancel: { worker.cancel() })
      guard let self, !Task.isCancelled, self.generation == request, self.source == source else {
        return
      }
      mapping = resolved
      analysisTask = nil
      didResolve?()
    }
  }
  func update(
    source: String, selection: NSRange, projection: SQLFolding.Projection?, editor: SQLTextView,
    allowPreview: Bool
  ) -> [NSRange] {
    prepare(source)
    lastSelection = selection
    match = mapping.match(at: selection)
    guard let match else {
      if analysisTask == nil { hidePreview() }
      return []
    }
    let ranges = match.ranges.compactMap { range -> NSRange? in
      guard let projection else { return range }
      guard
        !projection.regions.contains(where: { NSIntersectionRange($0.hidden, range).length > 0 })
      else { return nil }
      return NSRange(location: projection.displayOffset(range.location), length: range.length)
    }
    guard allowPreview, wantsPreview, selection != suppressedSelection,
      editor.window?.firstResponder === editor, !editor.hasMarkedText(),
      editor.selectedRanges.count == 1,
      let content = editor.textContentStorage, let layout = editor.textLayoutManager,
      let location = content.location(
        content.documentRange.location, offsetBy: editor.selectedRange().location),
      let caret = NSTextRange(location: location, end: location)
    else {
      hidePreview()
      return ranges
    }
    var anchor: NSRect?
    layout.enumerateTextSegments(in: caret, type: .selection, options: []) { _, rect, _, _ in
      anchor = rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
      return false
    }
    guard let anchor, anchor.intersects(editor.visibleRect) else {
      hidePreview()
      return ranges
    }
    title.stringValue =
      "INSERT \(match.target) · \(match.ordinal) / \(match.columnCount)"
      + (match.row.map { " · satır \($0)" } ?? "")
    column.stringValue = "→ \(match.column)"
    value.stringValue =
      match.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "Bu kolonun değerini girin." : String(match.value.prefix(400))
    refreshTheme()
    panel.view.setAccessibilityLabel(title.stringValue + " · " + column.stringValue)
    popover.show(relativeTo: anchor, of: editor, preferredEdge: .maxY)
    editor.window?.makeFirstResponder(editor)
    return ranges
  }
}
