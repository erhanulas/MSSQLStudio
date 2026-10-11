import AppKit
import SQLServerKit

@MainActor private final class SuggestionTable: NSTableView {
  override var acceptsFirstResponder: Bool { false }
}
@MainActor private final class SQLSuggestionList: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  let table = SuggestionTable()
  var items: [SQLIntelligence.Suggestion] = []
  var accept: ((Int) -> Void)?
  override func loadView() {
    let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:460,height:200))
    scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    let column = NSTableColumn(identifier:.init("suggestion")); column.width = 440
    table.addTableColumn(column); table.headerView = nil; table.rowHeight = 25
    table.delegate = self; table.dataSource = self; table.target = self; table.doubleAction = #selector(commit)
    table.setAccessibilityIdentifier("sqlSuggestions")
    scroll.documentView = table; view = scroll
  }
  @objc private func commit() { if table.selectedRow >= 0 { accept?(table.selectedRow) } }
  func numberOfRows(in tableView: NSTableView) -> Int { items.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let field = NSTextField(labelWithString:items[row].label)
    field.font = .systemFont(ofSize:12); field.lineBreakMode = .byTruncatingTail
    field.toolTip = items[row].text+" · Tab/Enter ile ekle; Escape kapatır"
    return field
  }
  func update(_ items: [SQLIntelligence.Suggestion]) {
    self.items = items; _ = view
    table.reloadData(); if !items.isEmpty { table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false) }
    preferredContentSize = NSSize(width:460,height:CGFloat(max(1,min(9,items.count)))*25)
  }
  func move(_ step: Int) {
    guard !items.isEmpty else { return }
    let row = max(0,min(items.count-1,table.selectedRow+step))
    table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false); table.scrollRowToVisible(row)
  }
}

@MainActor final class SQLEditorScrollView: NSScrollView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    let local = convert(point, from: superview)
    // An empty NSTextView may not expose a text hit region before its first edit.
    // The entire document viewport remains an editing surface; keep rulers/scrollers native.
    if contentView.frame.contains(local), !(hit is NSScroller), let text = documentView as? SQLTextView {
      return text
    }
    return hit
  }
}
@MainActor final class SQLClipView: NSClipView {
  var allowsHorizontalMovement = false
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var rect = super.constrainBoundsRect(proposedBounds)
    if !allowsHorizontalMovement { rect.origin.x = 0 }
    return rect
  }
}
/// A mouse-transparent decoration above the native text layers. Selection matches
/// must not edit text attributes or invalidate TextKit's cached paragraph fragments.
@MainActor final class OccurrenceHighlights: NSView {
  weak var editor: NSTextView?
  var ranges:[NSRange]=[] {didSet {if oldValue != ranges {needsDisplay=true}}}
  override var isFlipped: Bool {true}
  override func hitTest(_ point:NSPoint) -> NSView? {nil}
  func highlightRects(in dirtyRect:NSRect) -> [NSRect] {
    guard let editor,let content=editor.textContentStorage,let layout=editor.textLayoutManager else {return []}
    var rects:[NSRect]=[]
    let viewport=layout.textViewportLayoutController.viewportRange
    for range in ranges where range != editor.selectedRange() {
      guard NSMaxRange(range) <= (content.textStorage?.length ?? 0),
        let start=content.location(content.documentRange.location,offsetBy:range.location),
        let end=content.location(start,offsetBy:range.length),
        let textRange=NSTextRange(location:start,end:end),
        viewport == nil || viewport!.intersects(textRange) else {continue}
      layout.enumerateTextSegments(in:textRange,type:.standard,options:[]) { _,rect,_,_ in
        let frame=self.convert(rect.offsetBy(dx:editor.textContainerOrigin.x,dy:editor.textContainerOrigin.y),from:editor)
        if frame.intersects(dirtyRect) {rects.append(frame)}
        return true
      }
    }
    return rects
  }
  override func draw(_ dirtyRect:NSRect) {
    NSColor.systemYellow.withAlphaComponent(0.25).setFill()
    for rect in highlightRects(in:dirtyRect) {NSBezierPath(roundedRect:rect,xRadius:2,yRadius:2).fill()}
  }
}
@MainActor enum SQLEditorPreferences {
  static let completionDelayKey = "sqlCompletionDelayMilliseconds"
  static let defaultCompletionDelay = 260
  static func completionDelay(in defaults: UserDefaults = .standard) -> Int {
    guard defaults.object(forKey:completionDelayKey) != nil else {return defaultCompletionDelay}
    return max(50,min(1000,defaults.integer(forKey:completionDelayKey)))
  }
}
@MainActor final class SQLTextView: NSTextView {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers?.lowercased() == "b" { navigateDefinition?(); return true }
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control, event.charactersIgnoringModifiers?.lowercased() == "f" { showSelectionFind(); return true }
    return super.performKeyEquivalent(with:event)
  }
  func showSelectionFind() {
    let item=NSMenuItem(); item.tag=NSTextFinder.Action.showFindInterface.rawValue
    performFindPanelAction(item)
  }
  override func performFindPanelAction(_ sender: Any?) {
    dismissSuggestions?()
    if (sender as? NSValidatedUserInterfaceItem)?.tag == NSTextFinder.Action.showFindInterface.rawValue,
      selectedRange().length > 0 {
      let selection=NSMenuItem(); selection.tag=NSTextFinder.Action.setSearchString.rawValue
      super.performFindPanelAction(selection)
    }
    super.performFindPanelAction(sender)
  }
  override func selectAll(_ sender: Any?) { dismissSuggestions?(); super.selectAll(sender) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  private(set) var trackingMouseSelection=false
  var mouseSelectionEnded:(() -> Void)?
  override func mouseDown(with event: NSEvent) {
    trackingMouseSelection=true
    defer {trackingMouseSelection=false;mouseSelectionEnded?()}
    dismissSuggestions?()
    window?.makeFirstResponder(self)
    super.mouseDown(with: event)
    if event.clickCount == 2, unfoldSelection?(selectedRange()) == true {return}
    if event.clickCount == 2 { normalizeSQLWordSelection() }
    // Double-click belongs to word selection. Navigation must be deliberate.
    if event.modifierFlags.contains(.command) { navigateDefinition?() }
  }
  // AppKit may apply its own word boundaries after selectionRange; normalize the final
  // mouse selection as well, so SQL variable prefixes survive the native tracking loop.
  func normalizeSQLWordSelection() {
    let range=selectedRange(),text=string as NSString
    guard range.length > 0,range.location != NSNotFound,NSMaxRange(range) <= text.length else {return}
    for i in range.location..<NSMaxRange(range) {
      guard let scalar=UnicodeScalar(text.character(at:i)),
        CharacterSet.alphanumerics.contains(scalar) || "_@$#".unicodeScalars.contains(scalar) else {return}
    }
    let expanded=selectionRange(forProposedRange:range,granularity:.selectByWord)
    if expanded != range {setSelectedRange(expanded)}
  }
  override func selectionRange(forProposedRange range:NSRange,granularity:NSSelectionGranularity) -> NSRange {
    guard granularity == .selectByWord else {return super.selectionRange(forProposedRange:range,granularity:granularity)}
    let text=string as NSString
    guard text.length > 0,range.location < text.length else {return NSRange(location:min(range.location,text.length),length:0)}
    func word(at index:Int) -> NSRange {
      let index=min(index,text.length-1)
      func isWord(_ i:Int) -> Bool {
        guard i >= 0,i < text.length,let scalar=UnicodeScalar(text.character(at:i)) else {return false}
        return CharacterSet.alphanumerics.contains(scalar) || "_@$#".unicodeScalars.contains(scalar)
      }
      guard isWord(index) else {return text.rangeOfComposedCharacterSequence(at:index)}
      var start=index,end=index+1
      while isWord(start-1) {start-=1};while isWord(end) {end+=1}
      return NSRange(location:start,length:end-start)
    }
    let first=word(at:range.location),last=word(at:max(range.location,min(text.length-1,NSMaxRange(range)-1)))
    return NSUnionRange(first,last)
  }
  var navigateDefinition: (() -> Void)?
  var unfoldSelection: ((NSRange) -> Bool)?
  @objc private func goToDefinition(_ sender: Any?) { navigateDefinition?() }
  var requestSuggestions: (() -> Void)?
  var suggestionKey: ((NSEvent) -> Bool)?
  var dismissSuggestions: (() -> Void)?
  var toggleOutline: (() -> Void)?
  var expandOutline: (() -> Void)?
  @objc private func toggleCodeOutline(_ sender: Any?) { toggleOutline?() }
  @objc private func expandCodeOutline(_ sender: Any?) { expandOutline?() }
  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = super.menu(for:event) ?? NSMenu()
    menu.addItem(.separator())
    let definition = NSMenuItem(title:"Nesne Tanımına Git (⌘B / ⌘tık)",action:#selector(goToDefinition(_:)),keyEquivalent:""); definition.target = self; menu.addItem(definition)
    for (title, action) in [("Bloğu Daralt / Aç (⌥⌘[)", #selector(toggleCodeOutline(_:))), ("Tüm Blokları Aç (⌥⌘])", #selector(expandCodeOutline(_:)))] {
      let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; menu.addItem(item)
    }
    return menu
  }
  var prepareEdit: (() -> Void)?
  var sourceCopy: (() -> String?)?
  override func copy(_ sender: Any?) {
    guard let value = sourceCopy?() else { super.copy(sender); return }
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
  }
  var run: (() -> Void)?
  override var rangeForUserCompletion: NSRange {
    let selection = selectedRange()
    let units = Array(string.utf16)
    guard selection.length == 0, selection.location <= units.count else {
      return NSRange(location: NSNotFound, length: 0)
    }
    var start = selection.location
    while start > 0 {
      let c = units[start - 1]
      guard
        c >= 128 || (65...90).contains(c) || (97...122).contains(c) || (48...57).contains(c)
          || [95, 64, 35, 91].contains(c)
      else { break }
      start -= 1
    }
    return NSRange(location: start, length: selection.location - start)
  }
  override func insertTab(_ sender: Any?) {
    prepareEdit?()
    let range = selectedRange()
    if range.length == 0 { insertText("\t",replacementRange:range); return }
    indentLines(removing:false)
  }
  override func insertBacktab(_ sender: Any?) { prepareEdit?(); indentLines(removing:true) }
  private func indentLines(removing: Bool) {
    let source = string as NSString, selection = selectedRange()
    var selected = selection
    if selected.length > 0 && NSMaxRange(selected) <= source.length && source.substring(with:NSRange(location:NSMaxRange(selected)-1,length:1)) == "\n" { selected.length -= 1 }
    let lines = source.lineRange(for:selected)
    let original = source.substring(with:lines)
    let parts = original.components(separatedBy:"\n")
    let changed = parts.enumerated().map { index, line -> String in
      if index == parts.count-1 && line.isEmpty && original.hasSuffix("\n") { return line }
      if !removing { return "\t" + line }
      if line.hasPrefix("\t") { return String(line.dropFirst()) }
      return String(line.dropFirst(line.prefix(4).prefix(while: { $0 == " " }).count))
    }.joined(separator:"\n")
    guard changed != original else { return }
    insertText(changed,replacementRange:lines)
    setSelectedRange(NSRange(location:lines.location,length:(changed as NSString).length))
  }
  override func insertNewline(_ sender: Any?) {
    prepareEdit?()
    let source = string as NSString, selection = selectedRange()
    let line = source.lineRange(for:NSRange(location:selection.location,length:0))
    let before = source.substring(with:NSRange(location:line.location,length:selection.location-line.location))
    let indentation = String(before.prefix(while: { $0 == " " || $0 == "\t" }))
    insertText("\n" + indentation,replacementRange:selection)
  }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control, event.charactersIgnoringModifiers?.lowercased() == "f" { showSelectionFind(); return }
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control, event.charactersIgnoringModifiers?.lowercased() == "a" { selectAll(nil); return }
    if suggestionKey?(event) == true { return }
    if event.keyCode == 49 && event.modifierFlags.contains(.control), let requestSuggestions { requestSuggestions(); return }
    if event.modifierFlags.contains([.command,.option]), event.keyCode == 33 { toggleOutline?(); return }
    if event.modifierFlags.contains([.command,.option]), event.keyCode == 30 { expandOutline?(); return }
    if event.keyCode == 96 || event.keyCode == 36 && event.modifierFlags.contains(.command) {
      run?()
    } else if event.keyCode == 53 || event.keyCode == 49 && event.modifierFlags.contains(.control) {
      dismissSuggestions?()
    } else {
      super.keyDown(with: event)
    }
  }
}
@MainActor final class GutterAction: NSAccessibilityElement {
  var perform: (() -> Void)?
  override func accessibilityPerformPress() -> Bool { perform?(); return true }
}
@MainActor final class LineNumbers: NSView, NSViewToolTipOwner {
  weak var scrollView: NSScrollView?
  var ruleThickness: CGFloat = 68
  var sourceOffset: ((Int) -> Int)?
  var sourceText: (() -> String)?
  var lineNumber: ((Int) -> Int)?
  var foldRegions: (() -> [SQLFolding.Region])?
  var collapsed: ((SQLFolding.Region) -> Bool)?
  var toggle: ((SQLFolding.Region) -> Void)?
  var selectLine: ((NSRange) -> Void)?
  private var hits: [(CGFloat, NSRange, SQLFolding.Region?)] = []
  init(scrollView: NSScrollView) {
    self.scrollView = scrollView; super.init(frame:.zero)
    setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Satır numaraları ve bloklar")
  }
  private func updateAccessibility() {
    guard let window else { return }
    let original = (sourceText?() ?? "") as NSString
    var children: [GutterAction] = []
    for (top, range, region) in hits {
      let number = lineNumber?(range.location) ?? 1
      let line = GutterAction(); line.setAccessibilityRole(.button); line.setAccessibilityEnabled(true); line.setAccessibilityParent(self)
      line.setAccessibilityLabel("\(number). satırı seç")
      line.setAccessibilityFrame(window.convertToScreen(convert(NSRect(x:0,y:top,width:ruleThickness-20,height:18),to:nil)))
      line.perform = { [weak self] in self?.selectLine?(range) }; children.append(line)
      if let region, NSMaxRange(region.hidden) <= original.length {
        let fold = GutterAction(); fold.setAccessibilityRole(.button); fold.setAccessibilityEnabled(true); fold.setAccessibilityParent(self)
        fold.setAccessibilityLabel("Satır \(number): Bloğu \(collapsed?(region) == true ? "aç" : "daralt")")
        fold.setAccessibilityFrame(window.convertToScreen(convert(NSRect(x:ruleThickness-20,y:top,width:20,height:18),to:nil)))
        fold.perform = { [weak self] in self?.toggle?(region) }; children.append(fold)
      }
    }
    setAccessibilityChildren(children)
  }
  required init?(coder: NSCoder) { fatalError() }
  func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
    guard let region = hits.first(where: { point.y >= $0.0 && point.y < $0.0+18 })?.2 else { return "Satırın tamamını seç" }
    let source = (sourceText?() ?? "") as NSString
    let range = NSRange(location:region.header.location,length:min(4000,NSMaxRange(region.hidden)-region.header.location))
    return "\(collapsed?(region) == true ? "+ Bloğu aç" : "− Bloğu daralt") (⌥⌘[)\n" + source.substring(with:range)
  }
  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow,from:nil)
    guard let hit = hits.first(where: { point.y >= $0.0 && point.y < $0.0+18 }) else { return }
    if point.x >= ruleThickness-20, let region = hit.2 { toggle?(region) }
    else { selectLine?(hit.1) }
  }
  weak var editor: NSTextView?
  override var isFlipped: Bool { true }
  override func draw(_ rect: NSRect) {
    hits.removeAll(); removeAllToolTips()
    defer { updateAccessibility() }
    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }; bounds.clip()
    StudioTheme.panel.setFill()
    NSIntersectionRect(rect, bounds).fill()
    guard let editor, let clip = scrollView?.contentView else { return }
    guard let layout = editor.textLayoutManager, let content = editor.textContentStorage else {
      return
    }
    let font = StudioTheme.codeFont
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: StudioTheme.lineNumber,
    ]
    let offset = clip.bounds.minY
    let source = editor.string as NSString
    var number: Int?
    var lastBaseline: CGFloat?
    var lastHeight: CGFloat = 18
    var reachedEnd = false
    var drewEmptyLine = false
    let start = layout.textViewportLayoutController.viewportRange?.location
    layout.enumerateTextLayoutFragments(
      from: start, options: [.ensuresLayout, .ensuresExtraLineFragment]
    ) { fragment in
      let frame = fragment.layoutFragmentFrame
      if frame.minY > offset + clip.bounds.height { return false }
      if number == nil {
        let location = content.offset(
          from: content.documentRange.location, to: fragment.rangeInElement.location)
        number =
          source.substring(to: max(0, min(source.length, location))).filter { $0 == "\n" }.count + 1
      }
      reachedEnd =
        fragment.rangeInElement.endLocation.compare(content.documentRange.endLocation)
        == .orderedSame
      for line in fragment.textLineFragments {
        let visibleOffset = content.offset(from:content.documentRange.location,to:fragment.rangeInElement.location) + line.characterRange.location
        let original = (sourceText?() ?? editor.string) as NSString
        let originalOffset = max(0,min(original.length,sourceOffset?(visibleOffset) ?? visibleOffset))
        let originalLine = original.lineRange(for:NSRange(location:originalOffset,length:0))
        let lineNumber = lineNumber?(originalOffset) ?? 1
        let value = String(lineNumber) as NSString
        let size = value.size(withAttributes: attrs)
        let baseline =
          frame.minY + line.typographicBounds.minY + line.glyphOrigin.y
          + editor.textContainerInset.height - offset
        lastBaseline = baseline
        lastHeight = max(18, line.typographicBounds.height)
        drewEmptyLine = line.characterRange.length == 0
        value.draw(
          at: NSPoint(x: ruleThickness - size.width - 25, y: baseline - font.ascender),
          withAttributes: attrs)
        let region = foldRegions?().first(where: { $0.header.location == originalLine.location })
        let top = baseline-font.ascender
        hits.append((top,originalLine,region))
        if let region {
          addToolTip(NSRect(x:ruleThickness-20,y:top,width:20,height:18),owner:self,userData:nil)
          let isCollapsed=collapsed?(region) == true
          let box=NSRect(x:ruleThickness-18,y:top+2,width:13,height:13)
          (isCollapsed ? StudioTheme.accent : StudioTheme.editorCanvas).setFill()
          let path=NSBezierPath(roundedRect:box,xRadius:2,yRadius:2);path.fill()
          (isCollapsed ? StudioTheme.accent : NSColor.secondaryLabelColor).setStroke();path.lineWidth=1;path.stroke()
          (isCollapsed ? StudioTheme.editorCanvas : NSColor.secondaryLabelColor).setStroke()
          let lines=NSBezierPath();lines.move(to:NSPoint(x:box.minX+3,y:box.midY));lines.line(to:NSPoint(x:box.maxX-3,y:box.midY))
          if isCollapsed {lines.move(to:NSPoint(x:box.midX,y:box.minY+3));lines.line(to:NSPoint(x:box.midX,y:box.maxY-3))}
          lines.lineWidth=isCollapsed ? 1.5 : 1;lines.stroke()
        }
        number! += 1
      }
      return true
    }
    // TextKit may omit the trailing empty paragraph from viewport enumeration.
    if (source.length == 0 || (reachedEnd && editor.string.hasSuffix("\n"))) && !drewEmptyLine {
      let value = String(lineNumber?(((sourceText?() ?? editor.string) as NSString).length) ?? 1) as NSString
      let size = value.size(withAttributes: attrs)
      let baseline =
        lastBaseline.map { $0 + lastHeight }
        ?? (editor.textContainerInset.height + font.ascender - offset)
      let original = (sourceText?() ?? editor.string) as NSString
      hits.append((baseline-font.ascender,original.lineRange(for:NSRange(location:original.length,length:0)),nil))
      value.draw(
        at: NSPoint(x: ruleThickness - size.width - 25, y: baseline - font.ascender),
        withAttributes: attrs)
    }
  }
}
@MainActor final class EditorController: NSObject, NSTextViewDelegate {
  let surface = NSView()
  let scroll = SQLEditorScrollView()
  let editor = SQLTextView(usingTextLayoutManager: true)
  let occurrenceHighlights = OccurrenceHighlights()
  private let ruler: LineNumbers
  private let document: QueryDocument
  var edited: (() -> Void)?
  var position: ((Int, Int) -> Void)?
  private var intelligenceTask: Task<Void,Never>?
  private var occurrenceTask: Task<Void,Never>?
  private var intelligenceGeneration = UUID()
  private let suggestionList = SQLSuggestionList()
  private let suggestionPopover = NSPopover()
  private var currentAnalysis: SQLIntelligence.Analysis?
  private var analysisSource = ""
  private var cachedTokens: [Lexeme]?
  private var cachedTokenSource = ""
  private var unusedVariableSource = ""
  private var unusedVariableRanges: [NSRange] = []
  private var highlightedSource: String?
  private var highlightedDiagnostics: [SQLIntelligence.Diagnostic] = []
  private(set) var diagnostics: [SQLIntelligence.Diagnostic] = []
  private var suppressNextPopup = false
  private var initializedText = false
  private(set) var regions: [SQLFolding.Region] = []
  private var folded: [SQLFolding.Region] = []
  private var projection: SQLFolding.Projection?
  private var changingPresentation = false
  private var lineStarts = [0]
  private func updateOutline(refreshRegions: Bool = true) {
    if refreshRegions { regions = SQLFolding.regions(document.sql) }
    lineStarts = [0]
    for (index, unit) in document.sql.utf16.enumerated() where unit == 10 { lineStarts.append(index+1) }
  }
  private func sourceLineNumber(_ offset: Int) -> Int {
    var low = 0, high = lineStarts.count
    while low < high { let mid = (low+high)/2; if lineStarts[mid] <= offset { low = mid+1 } else { high = mid } }
    return max(1,low)
  }
  init(document: QueryDocument) {
    self.document = document
    ruler = LineNumbers(scrollView: scroll)
    super.init()
    scroll.contentView = SQLClipView()
    scroll.wantsLayer = true
    scroll.clipsToBounds = true
    editor.wantsLayer = true
    editor.clipsToBounds = true
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.horizontalScrollElasticity = .none
    scroll.autohidesScrollers = true
    editor.isEditable = true
    editor.isSelectable = true
    editor.isRichText = false
    editor.writingToolsBehavior = .none
    editor.allowsUndo = true
    editor.isAutomaticTextCompletionEnabled = false
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.isContinuousSpellCheckingEnabled = false
    editor.usesFindBar = true
    editor.isIncrementalSearchingEnabled = true
    editor.font = StudioTheme.codeFont
    editor.textColor = StudioTheme.editorText
    editor.backgroundColor = StudioTheme.editorCanvas
    let paragraph = Self.codeParagraph()
    editor.defaultParagraphStyle = paragraph
    editor.typingAttributes = [
      .font: editor.font!, .paragraphStyle: paragraph, .foregroundColor: StudioTheme.editorText,
    ]
    editor.textContainerInset = NSSize(width: 8, height: 8)
    // Frame geometry is explicit: lazy TextKit estimates must not shrink the scroll
    // range after a fold and move the line the user just clicked.
    editor.isVerticallyResizable = false
    editor.isHorizontallyResizable = false
    editor.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
    editor.minSize = NSSize(width: 100, height: 100)
    editor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.textContainer?.widthTracksTextView = false
    editor.textContainer?.containerSize = NSSize(
      width: 884, height: CGFloat.greatestFiniteMagnitude)
    editor.autoresizingMask = []
    editor.delegate = self
    editor.navigateDefinition = { [weak self] in self?.navigateDefinition() }
    editor.mouseSelectionEnded = { [weak self] in self?.occurrenceTask?.cancel();self?.updateOccurrences() }
    editor.unfoldSelection = { [weak self] range in
      guard let self,let marker=collapsedMarkers.first(where:{NSIntersectionRange($0.range,range).length > 0}) else {return false}
      toggleFold(marker.region);return true
    }
    editor.run = { [weak document] in document?.execute() }
    editor.setAccessibilityIdentifier("sqlEditor")
    scroll.documentView = editor
    occurrenceHighlights.editor=editor
    occurrenceHighlights.frame=scroll.contentView.bounds
    occurrenceHighlights.wantsLayer=true
    occurrenceHighlights.setAccessibilityElement(false)
    // Keep the backing layer viewport-sized even for very long documents.
    scroll.contentView.addSubview(occurrenceHighlights)
    ruler.wantsLayer = true
    ruler.clipsToBounds = true
    ruler.layer?.masksToBounds = true
    ruler.editor = editor
    ruler.ruleThickness = 68
    surface.wantsLayer = true; surface.clipsToBounds = true
    surface.addSubview(ruler); surface.addSubview(scroll)
    ruler.translatesAutoresizingMaskIntoConstraints = false; scroll.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      ruler.leadingAnchor.constraint(equalTo:surface.leadingAnchor), ruler.topAnchor.constraint(equalTo:surface.topAnchor),
      ruler.bottomAnchor.constraint(equalTo:surface.bottomAnchor), ruler.widthAnchor.constraint(equalToConstant:68),
      scroll.leadingAnchor.constraint(equalTo:ruler.trailingAnchor), scroll.trailingAnchor.constraint(equalTo:surface.trailingAnchor),
      scroll.topAnchor.constraint(equalTo:surface.topAnchor), scroll.bottomAnchor.constraint(equalTo:surface.bottomAnchor)
    ])
    ruler.lineNumber = { [weak self] in self?.sourceLineNumber($0) ?? 1 }
    ruler.sourceText = { [weak self] in self?.document.sql ?? "" }
    ruler.sourceOffset = { [weak self] in self?.projection?.sourceOffset($0) ?? $0 }
    ruler.foldRegions = { [weak self] in self?.regions ?? [] }
    ruler.collapsed = { [weak self] region in self?.folded.contains(region) == true }
    ruler.toggle = { [weak self] in self?.toggleFold($0) }
    ruler.selectLine = { [weak self] in self?.selectSourceLine($0) }
    suggestionPopover.contentViewController = suggestionList
    suggestionPopover.animates = false; suggestionPopover.behavior = .semitransient
    suggestionList.accept = { [weak self] in self?.acceptSuggestion($0) }
    editor.requestSuggestions = { [weak self] in self?.scheduleIntelligence(manual:true) }
    editor.dismissSuggestions = { [weak self] in self?.suggestionPopover.close() }
    editor.suggestionKey = { [weak self] in self?.handleSuggestionKey($0) ?? false }
    NotificationCenter.default.addObserver(self,selector:#selector(catalogChanged),name:.init("sqlCatalogChanged"),object:document)
    NotificationCenter.default.addObserver(self,selector:#selector(catalogChanged),name:.init("sqlEditorPreferencesChanged"),object:nil)
    editor.toggleOutline = { [weak self] in self?.toggleCurrentFold() }
    editor.expandOutline = { [weak self] in self?.expandAll() }
    editor.prepareEdit = { [weak self] in self?.expandAll() }
    editor.sourceCopy = { [weak self] in
      guard let self, projection != nil else { return nil }
      let range = projection!.sourceRange(editor.selectedRange())
      return (document.sql as NSString).substring(with:range)
    }
    scroll.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
      object: scroll.contentView)
    NotificationCenter.default.addObserver(
      self, selector: #selector(applyTheme), name: StudioTheme.changed, object: nil)
    for name in [
      Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(undoChanged(_:)), name: name, object: nil)
    }
    for name in [Notification.Name.NSUndoManagerWillUndoChange, Notification.Name.NSUndoManagerWillRedoChange] {
      NotificationCenter.default.addObserver(self,selector:#selector(willUndoChanged(_:)),name:name,object:nil)
    }
    applyTheme()
    setText()
  }
  @objc private func willUndoChanged(_ notification: Notification) {
    guard let manager = notification.object as? UndoManager, manager === editor.undoManager else { return }
    expandAll()
  }
  @objc private func undoChanged(_ notification: Notification) {
    guard let manager = notification.object as? UndoManager, manager === editor.undoManager else {
      return
    }
    // NSTextView can restore its storage without sending a delegate edit notification.
    // Keep execution/save/recovery bound to the visible text after undo and redo.
    if document.sql != editor.string {
      textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
    }
    highlightedSource=nil;highlight()
  }
  @objc func applyTheme() {
    highlightedSource = nil
    editor.backgroundColor = StudioTheme.editorCanvas
    editor.textColor = StudioTheme.editorText
    editor.insertionPointColor = StudioTheme.editorText
    editor.selectedTextAttributes = [
      .backgroundColor: StudioTheme.selection, .foregroundColor: StudioTheme.editorText,
    ]
    editor.typingAttributes[.font] = StudioTheme.codeFont
    editor.typingAttributes[.foregroundColor] = StudioTheme.editorText
    scroll.backgroundColor = StudioTheme.editorCanvas
    highlight()
    ruler.needsDisplay = true
  }
  func resizeToViewport() {
    scroll.tile()
    let metrics: [NSAttributedString.Key:Any] = [.font:editor.font ?? StudioTheme.codeFont,.paragraphStyle:Self.codeParagraph()]
    let longest = document.sql.components(separatedBy:"\n").map { ($0 as NSString).size(withAttributes:metrics).width }.max() ?? 0
    let textWidth = ceil(longest) + editor.textContainerInset.width * 2 + 10
    let horizontal = textWidth > scroll.contentView.bounds.width + 1
    (scroll.contentView as? SQLClipView)?.allowsHorizontalMovement = horizontal
    scroll.hasHorizontalScroller = horizontal
    let width = max(scroll.contentView.bounds.width,textWidth)
    let containerWidth = max(1,width - editor.textContainerInset.width * 2)
    if editor.textContainer?.containerSize.width != containerWidth {
      editor.textContainer?.containerSize = NSSize(width:containerWidth,height:CGFloat.greatestFiniteMagnitude)
    }
    // Resolve bounded documents before using TextKit's height: its lazy estimates
    // change as paragraphs enter the viewport. Font leading can exceed the configured
    // paragraph height, so counting lines is not an accurate scroll geometry.
    if editor.string.utf16.count <= 250_000,let content=editor.textContentStorage {
      editor.textLayoutManager?.ensureLayout(for:content.documentRange)
    }
    let lineCount=editor.string.utf16.reduce(1) {$1 == 10 ? $0+1 : $0}
    let measuredHeight=editor.textLayoutManager?.usageBoundsForTextContainer.maxY ?? 0
    let textHeight=max(measuredHeight,CGFloat(lineCount)*18)+editor.textContainerInset.height*2
    // Trailing space lets the final fold header stay under the pointer near EOF.
    let height=max(scroll.contentView.bounds.height,textHeight+scroll.contentView.bounds.height)
    if editor.frame.size != NSSize(width: width, height: height) {
      editor.setFrameSize(NSSize(width: width, height: height))
      editor.needsDisplay = true
    }
    if width <= scroll.contentView.bounds.width + 0.5 && scroll.contentView.bounds.origin.x != 0 {
      scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
      scroll.reflectScrolledClipView(scroll.contentView)
    }
    occurrenceHighlights.frame=scroll.contentView.bounds
    occurrenceHighlights.needsDisplay=true
  }
  func replaceText(_ text: String) {
    expandAll()
    guard text != editor.string else {return}
    // A full native replacement can inherit the first token's color. Invalidate the
    // attribute cache even when a later undo restores identical source text.
    highlightedSource=nil
    editor.typingAttributes[.foregroundColor]=StudioTheme.editorText
    editor.insertText(text,replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    highlight()
    resizeToViewport()
  }
  @objc private func scrolled() {
    let clip = scroll.contentView
    occurrenceHighlights.frame=clip.bounds
    occurrenceHighlights.needsDisplay=true
    if editor.frame.width <= clip.bounds.width + 1 && abs(clip.bounds.origin.x) > 0.5 {
      clip.scroll(to:NSPoint(x:0,y:clip.bounds.origin.y))
      scroll.reflectScrolledClipView(clip)
    }
    ruler.needsDisplay = true
  }
  func setText() {
    // A host refresh is not a request to unfold or replace an unchanged document.
    if initializedText && document.sql == (projection?.source ?? editor.string) { return }
    occurrenceTask?.cancel(); clearOccurrences(); highlightedSource=nil
    folded.removeAll(); projection = nil;collapsedMarkers=[]
    // Even an empty initial document must initialize NSTextView's text input/layout state.
    // Skipping the first assignment leaves a fresh blank TextKit 2 view without a click target.
    if editor.string != document.sql || !initializedText {
      editor.string = document.sql
      initializedText = true
    }
    if let storage = editor.textContentStorage?.textStorage {
      storage.removeAttribute(.backgroundColor,range:NSRange(location:0,length:storage.length))
      storage.addAttributes([.font:StudioTheme.codeFont,.paragraphStyle:Self.codeParagraph(),.foregroundColor:StudioTheme.editorText],range:NSRange(location:0,length:storage.length))
    }
    updateOutline()
    highlight()
    resizeToViewport()
    ruler.needsDisplay = true
    scheduleIntelligence()
  }
  func textDidChange(_ notification: Notification) {
    guard !changingPresentation else { return }
    clearOccurrences()
    document.sql = editor.string
    highlightedSource=nil
    updateOutline(refreshRegions:false)
    regions = []
    resizeToViewport()
    ruler.needsDisplay = true
    edited?()
    suggestionPopover.close()
    scheduleIntelligence(allowPopup:!suppressNextPopup)
    suppressNextPopup = false
  }
  func textViewDidChangeSelection(_ notification: Notification) {
    guard !paintingOccurrences, !changingPresentation else {return}
    let range = editor.selectedRange()
    occurrenceTask?.cancel()
    let selectedSource=editor.string
    occurrenceTask=Task { [weak self] in
      do {try await Task.sleep(for:.milliseconds(90))} catch {return}
      guard let self,!changingPresentation,editor.string == selectedSource,editor.selectedRange() == range else {return}
      updateOccurrences()
    }
    document.selectedRange = projection?.sourceRange(range) ?? range
    let prefix = (document.sql as NSString).substring(
      to: min(document.selectedRange.location, (document.sql as NSString).length))
    position?(
      prefix.filter { $0 == "\n" }.count + 1,
      (prefix.split(separator: "\n", omittingEmptySubsequences: false).last?.utf16.count ?? 0) + 1)
    if !changingPresentation && editor.string == analysisSource { suggestionPopover.close(); scheduleIntelligence(allowPopup:false) }
  }
  private var paintingOccurrences = false
  private(set) var occurrenceRanges: [NSRange] = []
  private func textRange(_ range: NSRange) -> NSTextRange? {
    guard let content=editor.textContentStorage, range.location != NSNotFound,
      NSMaxRange(range) <= (content.textStorage?.length ?? 0),
      let start=content.location(content.documentRange.location,offsetBy:range.location),
      let end=content.location(start,offsetBy:range.length) else {return nil}
    return NSTextRange(location:start,end:end)
  }
  private func clearOccurrences() {
    occurrenceRanges=[]
    occurrenceHighlights.ranges=[]
  }
  func updateOccurrences() {
    guard !paintingOccurrences,!editor.trackingMouseSelection else {return}
    paintingOccurrences=true;defer {paintingOccurrences=false}
    let source=editor.string as NSString,range=editor.selectedRange()
    var updatedRanges:[NSRange]=[]
    if source.length <= 250_000,range.length > 0,range.length <= 256,NSMaxRange(range) <= source.length {
      let selected=source.substring(with:range)
      if !selected.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,!selected.contains("\n") {
        var start=0
        while start < source.length,updatedRanges.count < 500 {
          let found=source.range(of:selected,options:[.caseInsensitive,.literal],range:NSRange(location:start,length:source.length-start))
          if found.location == NSNotFound {break}
          updatedRanges.append(found);start=NSMaxRange(found)
        }
      }
    }
    occurrenceRanges=updatedRanges
    occurrenceHighlights.ranges=updatedRanges
    // Also repaint when the selected occurrence changes within the same match set.
    // The selected word keeps its native selection color; the other matches get yellow.
    occurrenceHighlights.needsDisplay=true
  }
  func navigateDefinition() {
    guard projection == nil, editor.string.utf16.count <= 100_000, let catalog = document.intelligenceCatalog, document.catalogDatabase == document.database else { return }
    let caret = editor.selectedRange().location
    let tokens = TSQL.lex(editor.string).filter { ![.space,.comment,.string].contains($0.kind) }
    guard let i = tokens.firstIndex(where:{ caret >= $0.range.location && caret <= NSMaxRange($0.range) && $0.kind == .word }) else { return }
    func raw(_ value:String) -> String { value.hasPrefix("[") ? String(value.dropFirst().dropLast()).replacingOccurrences(of:"]]",with:"]") : value.hasPrefix("\"") ? String(value.dropFirst().dropLast()) : value }
    var parts = [raw(tokens[i].text)]
    if i >= 2, tokens[i-1].text == ".", tokens[i-2].kind == .word { parts.insert(raw(tokens[i-2].text),at:0) }
    else if i+2 < tokens.count, tokens[i+1].text == ".", tokens[i+2].kind == .word { parts.append(raw(tokens[i+2].text)) }
    if let symbol = catalog.resolve(parts) { document.openDefinition?(symbol) }
  }
  func selectSourceLine(_ range: NSRange) {
    let start = projection?.displayOffset(range.location) ?? range.location
    let end = projection?.displayOffset(NSMaxRange(range)) ?? NSMaxRange(range)
    editor.window?.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location:start,length:max(0,end-start)))
  }
  func toggleCurrentFold() {
    let offset = projection?.sourceOffset(editor.selectedRange().location) ?? editor.selectedRange().location
    let candidates = regions.filter { offset >= $0.header.location && offset <= NSMaxRange($0.hidden) }
    if let region = candidates.min(by: { $0.hidden.length < $1.hidden.length }) { toggleFold(region) }
  }
  func toggleFold(_ region: SQLFolding.Region) {
    guard regions.contains(region) else {return}
    var selection = projection?.sourceRange(editor.selectedRange()) ?? editor.selectedRange()
    if projection != nil,let marker=collapsedMarkers.first(where:{$0.region == region}),NSIntersectionRange(editor.selectedRange(),marker.range).length > 0 {
      // Expanding an ellipsis must not turn its small visual selection into a whole block selection.
      selection=NSRange(location:region.header.location,length:0)
    }
    let displayHeader=projection?.displayOffset(region.header.location) ?? region.header.location
    let oldOrigin=scroll.contentView.bounds.origin
    // Keyboard folding can target a block whose header is above the viewport.
    // Reveal that header; a visible gutter click keeps its exact screen position.
    let anchorY=max(0,min(displayLineTop(displayHeader)-oldOrigin.y,scroll.contentView.bounds.height-24))
    if let index=folded.firstIndex(of:region) {folded.remove(at:index)} else {
      folded.append(region)
      if NSIntersectionRange(selection,region.hidden).length > 0 ||
        (selection.length == 0 && NSLocationInRange(selection.location,region.hidden)) {
        selection=NSRange(location:region.header.location,length:0)
      }
    }
    presentFolds(selection:selection)
    let header=projection?.displayOffset(region.header.location) ?? region.header.location
    restoreViewport(NSPoint(x:oldOrigin.x,y:max(0,displayLineTop(header)-anchorY)))
  }
  private func displayLineTop(_ offset:Int) -> CGFloat {
    guard let range=textRange(NSRange(location:offset,length:0)),let layout=editor.textLayoutManager else {return 0}
    layout.ensureLayout(for:range)
    var top:CGFloat=0
    layout.enumerateTextSegments(in:range,type:.selection,options:[]) { _,rect,_,_ in
      top=rect.minY+self.editor.textContainerOrigin.y;return false
    }
    return top
  }
  private func viewportDisplayAnchor() -> Int {
    guard let content=editor.textContentStorage,let layout=editor.textLayoutManager else {return 0}
    var offset=editor.string.utf16.count
    layout.enumerateTextLayoutFragments(from:content.documentRange.location,options:[.ensuresLayout]) { fragment in
      if fragment.layoutFragmentFrame.maxY+self.editor.textContainerOrigin.y >= self.scroll.contentView.bounds.minY {
        offset=content.offset(from:content.documentRange.location,to:fragment.rangeInElement.location)
        return false
      }
      return true
    }
    return offset
  }
  private func restoreViewport(_ origin:NSPoint) {
    scroll.contentView.scroll(to:origin)
    scroll.reflectScrolledClipView(scroll.contentView)
    editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
    ruler.needsDisplay=true
  }
  private(set) var collapsedMarkers:[(region:SQLFolding.Region,range:NSRange)]=[]
  private func decorateCollapsedRegions() {
    guard let storage=editor.textContentStorage?.textStorage else {return}
    let source=document.sql as NSString
    for marker in collapsedMarkers where NSMaxRange(marker.range) <= storage.length {
      let region=marker.region,preview=NSRange(location:region.header.location,length:min(4000,NSMaxRange(region.hidden)-region.header.location))
      storage.addAttributes([.backgroundColor:NSColor.controlAccentColor.withAlphaComponent(0.16),.foregroundColor:NSColor.secondaryLabelColor,.toolTip:"Katlanmış blok · \(source.substring(with:region.hidden).utf16.filter {$0 == 10}.count) satır gizli · Çift tık veya + ile aç (⌥⌘[)\n"+source.substring(with:preview)],range:marker.range)
    }
  }
  func expandAll() {
    guard projection != nil else { return }
    let selection = projection!.sourceRange(editor.selectedRange())
    let oldOrigin=scroll.contentView.bounds.origin
    let offset=viewportDisplayAnchor()
    let sourceAnchor=projection!.sourceOffset(offset)
    let relativeY=displayLineTop(offset)-oldOrigin.y
    folded.removeAll();presentFolds(selection:selection)
    restoreViewport(NSPoint(x:oldOrigin.x,y:max(0,displayLineTop(sourceAnchor)-relativeY)))
  }
  private func presentFolds(selection: NSRange) {
    intelligenceTask?.cancel();occurrenceTask?.cancel();clearOccurrences();highlightedSource=nil; suggestionPopover.close(); diagnostics = []
    changingPresentation = true
    defer {changingPresentation=false; textViewDidChangeSelection(Notification(name:NSTextView.didChangeSelectionNotification,object:editor))}
    if let storage=editor.textContentStorage?.textStorage {
      storage.beginEditing()
      for marker in collapsedMarkers where NSMaxRange(marker.range) <= storage.length {
        storage.removeAttribute(.backgroundColor,range:marker.range)
        storage.removeAttribute(.toolTip,range:marker.range)
      }
      storage.endEditing()
    }
    projection = folded.isEmpty ? nil : SQLFolding.Projection(source:document.sql,collapsed:folded)
    collapsedMarkers=projection?.regions.map {($0,NSRange(location:projection!.displayOffset($0.hidden.location),length:2))} ?? []
    let presented=projection?.text ?? document.sql
    // Replace only the changed span. Reassigning .string destroys every paragraph
    // and its viewport fragments, even those above the block being toggled.
    if let content=editor.textContentStorage,let storage=content.textStorage {
      let old=Array(editor.string.utf16),new=Array(presented.utf16)
      var prefix=0,suffix=0
      while prefix < min(old.count,new.count),old[prefix] == new[prefix] {prefix+=1}
      if prefix > 0,prefix < old.count,(0xDC00...0xDFFF).contains(old[prefix]) {prefix-=1}
      while suffix < min(old.count,new.count)-prefix,old[old.count-1-suffix] == new[new.count-1-suffix] {suffix+=1}
      if suffix > 0,(0xDC00...0xDFFF).contains(old[old.count-suffix]) {suffix-=1}
      let replacement=(presented as NSString).substring(with:NSRange(location:prefix,length:new.count-prefix-suffix))
      content.performEditingTransaction {
        storage.replaceCharacters(in:NSRange(location:prefix,length:old.count-prefix-suffix),
          with:NSAttributedString(string:replacement,attributes:[.font:StudioTheme.codeFont,
            .paragraphStyle:Self.codeParagraph(),.foregroundColor:StudioTheme.editorText]))
      }
    }
    let start = projection?.displayOffset(selection.location) ?? selection.location
    let end = projection?.displayOffset(NSMaxRange(selection)) ?? NSMaxRange(selection)
    editor.setSelectedRange(NSRange(location:start,length:max(0,end-start)))
    highlight(); resizeToViewport()
    // Fold projections are capped at 250k UTF-16 units. Resolve their layout before
    // restoring the anchor, rather than letting estimates correct it a frame later.
    if let content=editor.textContentStorage {editor.textLayoutManager?.ensureLayout(for:content.documentRange)}
    ruler.needsDisplay = true
    if projection == nil { scheduleIntelligence(allowPopup:false) }
  }
  func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
    clearOccurrences()
    editor.typingAttributes.removeValue(forKey:.backgroundColor)
    guard let projection else { return true }
    let range = projection.sourceRange(affectedCharRange)
    expandAll()
    if let replacementString { editor.insertText(replacementString,replacementRange:range) }
    return false
  }
  func textView(
    _ textView: NSTextView, completions: [String], forPartialWordRange range: NSRange,
    indexOfSelectedItem index: UnsafeMutablePointer<Int>?
  ) -> [String] {
    let text = textView.string as NSString
    guard NSMaxRange(range) <= text.length else { return [] }
    let values = analysisSource == textView.string ? currentAnalysis?.suggestions.map(\.text) ?? [] : []
    index?.pointee = values.isEmpty ? -1 : 0
    return values
  }
  @objc private func catalogChanged() { scheduleIntelligence(allowPopup:false) }
  func scheduleIntelligence(manual: Bool = false, allowPopup: Bool = true) {
    intelligenceTask?.cancel()
    let generation = UUID(); intelligenceGeneration = generation
    guard projection == nil else { return }
    document.ensureCatalogFresh()
    let source = editor.string, caret = editor.selectedRange().location
    let catalog = document.catalogDatabase == document.database ? document.intelligenceCatalog : nil
    let verified = document.catalogVerified && document.catalogDatabase == document.database
    let aliases = UserDefaults.standard.object(forKey:"sqlAutomaticAliases") as? Bool ?? true
    let noLock = UserDefaults.standard.bool(forKey:"sqlAutomaticNoLock")
    let automatic = UserDefaults.standard.object(forKey:"sqlAutomaticCompletion") as? Bool ?? true
    let validate = UserDefaults.standard.object(forKey:"sqlValidateReferences") as? Bool ?? true
    let delay = SQLEditorPreferences.completionDelay()
    intelligenceTask = Task { [weak self] in
      do {
        if !manual { try await Task.sleep(for:.milliseconds(delay)) }
        let worker = Task.detached(priority:.userInitiated) {
          let analysis = try SQLIntelligence.analyze(source:source,caret:caret,catalog:catalog,verified:verified,automaticAliases:aliases,automaticNoLock:noLock)
          try Task.checkCancellation()
          return (analysis,SQLFolding.regions(source))
        }
        let (analysis,regions) = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
        guard !Task.isCancelled, let self, intelligenceGeneration == generation, editor.string == source, editor.selectedRange().location == caret else { return }
        self.regions = regions; ruler.needsDisplay = true
        diagnostics = validate ? analysis.diagnostics : []
        cachedTokens = analysis.tokens; cachedTokenSource = source
        currentAnalysis = analysis; analysisSource = source
        highlight()
        let prefixLength = caret-analysis.replacement.location
        let dot = analysis.replacement.location > 0 && (source as NSString).substring(with:NSRange(location:analysis.replacement.location-1,length:1)) == "."
        if (manual || automatic && allowPopup && (analysis.procedureCompletion || prefixLength >= 2 || dot)), !analysis.suggestions.isEmpty, let window = editor.window, window.firstResponder === editor {
          suggestionList.update(analysis.suggestions)
          guard let anchor = suggestionAnchor(), let host = window.contentView else { return }
          let hostAnchor = host.convert(anchor,from:editor)
          suggestionPopover.show(relativeTo:hostAnchor,of:host,preferredEdge:host.isFlipped ? .maxY : .minY)
          window.makeFirstResponder(editor)
        }
      } catch { /* Superseded edits never publish stale diagnostics or suggestions. */ }
    }
  }
  func suggestionAnchor() -> NSRect? {
    guard let content = editor.textContentStorage, let layout = editor.textLayoutManager,
      let location = content.location(content.documentRange.location,offsetBy:editor.selectedRange().location),
      let range = NSTextRange(location:location,end:location) else { return nil }
    layout.ensureLayout(for:range)
    var anchor: NSRect?
    layout.enumerateTextSegments(in:range,type:.selection,options:[]) { _, rect, _, _ in
      var caretRect = rect.offsetBy(dx:self.editor.textContainerOrigin.x,dy:self.editor.textContainerOrigin.y)
      caretRect.size.width = max(1,caretRect.width)
      anchor = caretRect
      return false
    }
    return anchor
  }
  private func handleSuggestionKey(_ event: NSEvent) -> Bool {
    guard suggestionPopover.isShown else { return false }
    switch event.keyCode {
    case 125: suggestionList.move(1); return true
    case 126: suggestionList.move(-1); return true
    case 48,36: acceptSuggestion(suggestionList.table.selectedRow); return true
    case 53: suggestionPopover.close(); intelligenceTask?.cancel(); return true
    default: return false
    }
  }
  private func acceptSuggestion(_ index: Int) {
    guard let analysis = currentAnalysis, analysisSource == editor.string, analysis.suggestions.indices.contains(index), projection == nil else { suggestionPopover.close(); return }
    suggestionPopover.close(); suppressNextPopup = true
    editor.window?.makeFirstResponder(editor)
    editor.insertText(analysis.suggestions[index].text,replacementRange:analysis.replacement)
  }
  static func codeParagraph() -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = 18; paragraph.maximumLineHeight = 18
    paragraph.lineBreakMode = .byClipping
    paragraph.tabStops = []
    paragraph.defaultTabInterval = (" " as NSString).size(withAttributes:[.font:StudioTheme.codeFont]).width * 4
    return paragraph
  }
  private func highlight() {
    guard let storage = editor.textContentStorage?.textStorage else { return }
    let source = editor.string
    let activeDiagnostics = cachedTokenSource == source && projection == nil ? diagnostics : []
    guard highlightedSource != source || highlightedDiagnostics != activeDiagnostics else {return}
    highlightedSource=source;highlightedDiagnostics=activeDiagnostics
    let tokens = cachedTokenSource == source ? cachedTokens ?? [] : source.utf16.count <= 250_000 ? TSQL.lex(source) : []
    let completeSource = projection?.source ?? source
    if unusedVariableSource != completeSource {
      unusedVariableSource = completeSource
      unusedVariableRanges = TSQL.unusedDeclaredVariables(completeSource)
    }
    let unused = Set(unusedVariableRanges.compactMap { range -> Int? in
      if let projection {
        guard !projection.regions.contains(where:{ NSIntersectionRange($0.hidden,range).length > 0 }) else { return nil }
        return projection.displayOffset(range.location)
      }
      return range.location
    })
    var changes: [(NSRange,NSColor)] = []
    func collect(_ range: NSRange, color: NSColor) {
      guard range.length > 0 else { return }
      storage.enumerateAttribute(.foregroundColor,in:range) { value, run, _ in
        if (value as? NSColor) != color { changes.append((run,color)) }
      }
    }
    if tokens.isEmpty { collect(NSRange(location:0,length:storage.length),color:StudioTheme.editorText) }
    else { for token in tokens { collect(token.range,color:SQLSourceHighlighting.foreground(token,unused:unused.contains(token.range.location))) } }
    let selection = editor.selectedRanges
    storage.beginEditing()
    for (range,color) in changes { storage.addAttribute(.foregroundColor,value:color,range:range) }
    let full = NSRange(location:0,length:storage.length)
    for key in [NSAttributedString.Key.underlineStyle,.underlineColor,.toolTip] {
      var ranges: [NSRange] = []
      storage.enumerateAttribute(key,in:full) { value, range, _ in if value != nil { ranges.append(range) } }
      for range in ranges { storage.removeAttribute(key,range:range) }
    }
    if cachedTokenSource == source, projection == nil {
      for diagnostic in diagnostics where NSMaxRange(diagnostic.range) <= storage.length {
        storage.addAttributes([.foregroundColor:NSColor.systemRed,.underlineColor:NSColor.systemRed,.underlineStyle:NSUnderlineStyle.single.rawValue,.toolTip:diagnostic.message],range:diagnostic.range)
      }
    }
    storage.endEditing()
    if editor.selectedRanges != selection { editor.selectedRanges = selection }
    decorateCollapsedRegions()
    editor.typingAttributes[.foregroundColor] = StudioTheme.editorText
    scrolled()
    assert(editor.textLayoutManager != nil)
  }
}
