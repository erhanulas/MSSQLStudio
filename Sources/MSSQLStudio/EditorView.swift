import AppKit
import SwiftUI
import SQLServerKit

private final class SQLSuggestionKeyMonitor: @unchecked Sendable {
  let token:Any
  init(_ token:Any) {self.token=token}
  deinit {NSEvent.removeMonitor(token)}
}
@MainActor final class SuggestionTable: NSTableView {
  override var acceptsFirstResponder: Bool { false }
}
@MainActor enum SQLSuggestionStyle {
  static func title(_ kind: SQLIntelligence.Suggestion.Kind) -> String {
    switch kind {
    case .table: return "Tablo"
    case .view: return "Görünüm"
    case .procedure: return "Prosedür"
    case .synonym: return "Eş anlamlı"
    case .column: return "Kolon"
    case .variable: return "Değişken"
    case .keyword: return "Anahtar sözcük"
    case .function: return "Fonksiyon"
    }
  }
  static func symbol(_ kind: SQLIntelligence.Suggestion.Kind) -> String {
    switch kind {
    case .table: return "tablecells"
    case .view: return "rectangle.on.rectangle"
    case .procedure: return "terminal"
    case .synonym: return "link"
    case .column: return "rectangle.split.3x1"
    case .variable: return "at"
    case .keyword: return "curlybraces"
    case .function: return "function"
    }
  }
  static func color(_ kind: SQLIntelligence.Suggestion.Kind) -> NSColor {
    switch kind {
    case .table, .view: return StudioTheme.accent
    case .column: return StudioTheme.success
    case .variable: return StudioTheme.text
    case .procedure: return StudioTheme.syntax(.procedure)
    case .function: return StudioTheme.syntax(.function)
    case .synonym: return StudioTheme.warning
    case .keyword: return StudioTheme.syntax(.keyword)
    }
  }
}
@MainActor private final class SQLSuggestionRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    StudioTheme.selection.setFill()
    NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:7,yRadius:7).fill()
    StudioTheme.accent.withAlphaComponent(0.35).setStroke()
    let border=NSBezierPath(roundedRect:bounds.insetBy(dx:1.5,dy:1.5),xRadius:7,yRadius:7)
    border.lineWidth=1; border.stroke()
  }
}
@MainActor private final class SQLSuggestionCell: NSTableCellView {
  var item: SQLIntelligence.Suggestion?
  var prefix = ""
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    guard let item else { return }
    let color=SQLSuggestionStyle.color(item.kind)
    color.withAlphaComponent(StudioTheme.dark ? 0.16:0.08).setFill()
    NSBezierPath(roundedRect:NSRect(x:5,y:3,width:20,height:20),xRadius:4,yRadius:4).fill()
    NSImage(systemSymbolName:SQLSuggestionStyle.symbol(item.kind),accessibilityDescription:nil)?
      .withSymbolConfiguration(.init(paletteColors:[color]))?
      .draw(in:NSRect(x:8,y:6,width:14,height:14))
    let paragraph=NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
    let label=NSMutableAttributedString(string:item.label,attributes:[.font:NSFont.monospacedSystemFont(ofSize:12,weight:.medium),.foregroundColor:StudioTheme.text,.paragraphStyle:paragraph])
    if !prefix.isEmpty {
      let match=(item.label as NSString).range(of:prefix,options:.caseInsensitive)
      if match.location != NSNotFound { label.addAttributes([.foregroundColor:StudioTheme.accent,.font:NSFont.monospacedSystemFont(ofSize:12,weight:.bold)],range:match) }
    }
    label.draw(in:NSRect(x:34,y:5,width:max(0,bounds.width-140),height:17))
    paragraph.alignment = .right
    SQLSuggestionStyle.title(item.kind).draw(in:NSRect(x:bounds.width-100,y:6,width:90,height:14),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:StudioTheme.muted,.paragraphStyle:paragraph])
  }
}
@MainActor private final class SQLSuggestionSurface: NSView {
  let scroll=NSScrollView()
  var count=0 { didSet { needsDisplay=true } }
  override var isFlipped: Bool { true }
  override init(frame:NSRect) {
    super.init(frame:frame)
    addSubview(scroll); scroll.drawsBackground=false
    scroll.automaticallyAdjustsContentInsets=false; scroll.contentInsets = NSEdgeInsets(top:0,left:0,bottom:0,right:0)
    scroll.hasVerticalScroller=true; scroll.autohidesScrollers=true
    scroll.horizontalScrollElasticity = .none; scroll.verticalScrollElasticity = .none
  }
  required init?(coder:NSCoder) { fatalError() }
  override func layout() {
    super.layout()
    scroll.frame=NSRect(x:6,y:27,width:max(0,bounds.width-12),height:max(0,bounds.height-52))
    (scroll.documentView as? NSTableView)?.tableColumns.first?.width=max(0,scroll.contentSize.width)
  }
  override func draw(_ dirtyRect:NSRect) {
    StudioTheme.canvas.setFill(); bounds.fill()
    StudioTheme.panel.setFill()
    NSRect(x:0,y:0,width:bounds.width,height:25).fill()
    NSRect(x:0,y:bounds.height-23,width:bounds.width,height:23).fill()
    StudioTheme.border.setFill()
    NSRect(x:0,y:24,width:bounds.width,height:1).fill()
    NSRect(x:0,y:bounds.height-23,width:bounds.width,height:1).fill()
    "SQL TAMAMLAMA".draw(at:NSPoint(x:14,y:6),withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.semibold),.foregroundColor:StudioTheme.muted])
    let countLabel="\(count) öneri"
    let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:10,weight:.medium),.foregroundColor:StudioTheme.accent]
    countLabel.draw(at:NSPoint(x:bounds.width-countLabel.size(withAttributes:attributes).width-14,y:6),withAttributes:attributes)
    "↑ ↓  Gezin    PgUp / PgDn  Sayfa    ⇥ / ↵  Ekle    esc  Kapat".draw(at:NSPoint(x:14,y:bounds.height-18),withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.medium),.foregroundColor:StudioTheme.muted])
  }
}
@MainActor final class SQLSuggestionList: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  let table = SuggestionTable()
  private(set) var items: [SQLIntelligence.Suggestion] = []
  private var prefix = ""
  var accept: ((Int) -> Void)?
  override func loadView() {
    let surface=SQLSuggestionSurface(frame:NSRect(x:0,y:0,width:500,height:200))
    surface.autoresizingMask = [.width,.height]
    let column=NSTableColumn(identifier:.init("suggestion")); column.width=488
    table.addTableColumn(column); table.headerView=nil; table.rowHeight=26
    table.style = .plain
    table.intercellSpacing=NSSize(width:0,height:0); table.backgroundColor=StudioTheme.canvas
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.delegate=self; table.dataSource=self; table.target=self; table.doubleAction=#selector(commit)
    table.focusRingType = .none
    table.setAccessibilityIdentifier("sqlSuggestions")
    table.setAccessibilityLabel("SQL tamamlama önerileri")
    table.setAccessibilityHelp("Yukarı/aşağı ile gezin, Tab veya Enter ile ekleyin; Escape ile kapatın.")
    surface.scroll.documentView=table; view=surface
    NotificationCenter.default.addObserver(self,selector:#selector(refreshTheme),name:StudioTheme.changed,object:nil)
  }
  @objc private func refreshTheme() {
    table.backgroundColor=StudioTheme.canvas
    table.enumerateAvailableRowViews { row, _ in
      row.needsDisplay=true; for child in row.subviews { child.needsDisplay=true }
    }
    view.needsDisplay=true
  }
  @objc private func commit() { if table.selectedRow >= 0 { accept?(table.selectedRow) } }
  func numberOfRows(in tableView: NSTableView) -> Int { items.count }
  func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? { SQLSuggestionRowView() }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let identifier=NSUserInterfaceItemIdentifier("sqlSuggestionCell")
    let cell=tableView.makeView(withIdentifier:identifier,owner:self) as? SQLSuggestionCell ?? SQLSuggestionCell()
    cell.identifier=identifier; cell.item=items[row]; cell.prefix=prefix; cell.needsDisplay=true
    cell.toolTip=SQLSuggestionStyle.title(items[row].kind)+" · "+items[row].text+(items[row].detail.isEmpty ? "":"\n"+items[row].detail)+"\nTab/Enter ile ekle; Escape kapatır"
    cell.setAccessibilityElement(true); cell.setAccessibilityRole(.staticText)
    cell.setAccessibilityLabel(items[row].label+" · "+SQLSuggestionStyle.title(items[row].kind))
    cell.setAccessibilityHelp(items[row].text)
    return cell
  }
  func update(_ items: [SQLIntelligence.Suggestion], prefix:String = "") {
    self.items=items; self.prefix=prefix; _ = view
    (view as? SQLSuggestionSurface)?.count=items.count
    table.reloadData(); if !items.isEmpty { table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false) }
    preferredContentSize=NSSize(width:500,height:CGFloat(max(1,min(16,items.count)))*26+52)
    view.frame.size=preferredContentSize; view.needsLayout=true
    view.layoutSubtreeIfNeeded(); if !items.isEmpty { table.scrollRowToVisible(0) }
  }
  func fit(maximumHeight:CGFloat) {
    // Keep full rows between the fixed heading and keyboard hint footer.
    let rows=max(1,min(16,Int((maximumHeight-52)/26),max(1,items.count)))
    preferredContentSize=NSSize(width:500,height:CGFloat(rows)*26+52)
    view.frame.size=preferredContentSize; view.needsLayout=true; view.layoutSubtreeIfNeeded()
  }
  var visibleRowCount:Int {max(1,Int((view.bounds.height-52)/26))}
  static func placement(anchor:NSRect,screen:NSRect,preferredHeight:CGFloat) -> (below:Bool,height:CGFloat) {
    let above=max(0,screen.maxY-anchor.maxY-32), below=max(0,anchor.minY-screen.minY-32)
    let down=below >= preferredHeight || (above < preferredHeight && below >= above)
    return (down,down ? below:above)
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
  var findRanges:[NSRange]=[] {didSet {if oldValue != findRanges {needsDisplay=true}}}
  var blockRanges:[NSRange]=[] {didSet {if oldValue != blockRanges {needsDisplay=true}}}
  var ranges:[NSRange]=[] {didSet {if oldValue != ranges {needsDisplay=true}}}
  override var isFlipped: Bool {true}
  override func hitTest(_ point:NSPoint) -> NSView? {nil}
  func highlightRects(in dirtyRect:NSRect) -> [NSRect] {
    guard let editor,let content=editor.textContentStorage,let layout=editor.textLayoutManager else {return []}
    var rects:[NSRect]=[]
    let viewport=layout.textViewportLayoutController.viewportRange
    for range in ranges+blockRanges+findRanges where range != editor.selectedRange() {
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
  static let completionSchemaKey = "sqlCompletionIncludeSchema"
  static let completionBracketsKey = "sqlCompletionQuoteIdentifiers"
  static func includeSchema(in defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey:completionSchemaKey) as? Bool ?? true
  }
  static func quoteIdentifiers(in defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey:completionBracketsKey) as? Bool ?? true
  }
  static func completionDelay(in defaults: UserDefaults = .standard) -> Int {
    guard defaults.object(forKey:completionDelayKey) != nil else {return defaultCompletionDelay}
    return max(50,min(1000,defaults.integer(forKey:completionDelayKey)))
  }
}
@MainActor final class SQLTextView: NSTextView, @preconcurrency NSTextFinderClient {
  lazy var sqlFinder:NSTextFinder = {
    let finder=NSTextFinder();finder.client=self
    finder.isIncrementalSearchingEnabled=true;finder.incrementalSearchingShouldDimContentView=false
    return finder
  }()
  var findMatchesChanged:(([NSRange])->Void)?
  private var findObservation:NSKeyValueObservation?
  func configureFinder(in scroll:NSScrollView) {
    sqlFinder.findBarContainer=scroll
    findObservation=sqlFinder.observe(\.incrementalMatchRanges,options:[.new]) { [weak self] finder,_ in
      let ranges=finder.incrementalMatchRanges.map { $0.rangeValue }
      Task { @MainActor [weak self] in self?.findMatchesChanged?(ranges) }
    }
  }
  var firstSelectedRange:NSRange {selectedRange()}
  func contentView(at index:Int,effectiveCharacterRange range:NSRangePointer)->NSView {
    range.pointee=NSRange(location:0,length:string.utf16.count);return self
  }
  func rects(forCharacterRange range:NSRange)->[NSValue]? {
    guard let content=textContentStorage,let layout=textLayoutManager,NSMaxRange(range)<=string.utf16.count,
      let start=content.location(content.documentRange.location,offsetBy:range.location),let end=content.location(start,offsetBy:range.length),let textRange=NSTextRange(location:start,end:end) else {return []}
    var rects:[NSValue]=[]
    layout.enumerateTextSegments(in:textRange,type:.standard,options:[]) {_,rect,_,_ in
      rects.append(NSValue(rect:rect.offsetBy(dx:self.textContainerOrigin.x,dy:self.textContainerOrigin.y)));return true
    };return rects
  }
  var visibleCharacterRanges:[NSValue] {
    guard let content=textContentStorage,let range=textLayoutManager?.textViewportLayoutController.viewportRange else {return []}
    let start=content.offset(from:content.documentRange.location,to:range.location),end=content.offset(from:content.documentRange.location,to:range.endLocation)
    return [NSValue(range:NSRange(location:start,length:max(0,end-start)))]
  }
  func shouldReplaceCharacters(inRanges ranges:[NSValue],with strings:[String])->Bool {
    isEditable && ranges.count == strings.count && ranges.allSatisfy {NSMaxRange($0.rangeValue)<=string.utf16.count} && shouldChangeText(inRanges:ranges,replacementStrings:strings)
  }
  func didReplaceCharacters() {didChangeText()}
  override func validateUserInterfaceItem(_ item:any NSValidatedUserInterfaceItem)->Bool {
    if item.action == #selector(undoSQL(_:)) || item.action == #selector(undoFromMenu(_:)) {return isEditable && undoManager?.canUndo == true}
    if item.action == #selector(redoSQL(_:)) || item.action == #selector(redoFromMenu(_:)) {return isEditable && undoManager?.canRedo == true}
    if item.action == #selector(performFindPanelAction(_:)),let action=NSTextFinder.Action(rawValue:item.tag) {
      // Opening the bar must not depend on a previously initialized search session.
      if action == .showFindInterface {return isSelectable && sqlFinder.findBarContainer != nil}
      return sqlFinder.validateAction(action)
    }
    return super.validateUserInterfaceItem(item)
  }

  // Window-owned history mixes different query tabs and is lost on detach.
  private let sqlUndoManager=UndoManager()
  override var undoManager:UndoManager? {allowsUndo ? sqlUndoManager:nil}
  private struct UndoInput {
    var deleting:Bool
    var backward:Bool
    var space:Bool
    var caret:Int
    var time:TimeInterval
  }
  private var undoInput:UndoInput?
  private var atomicUndoInput=false
  // A native typing run otherwise coalesces across many words and long pauses.
  // Keep words (including their trailing spaces) together, and isolate bulk edits.
  func finishUndoInput() {
    breakUndoCoalescing();undoInput=nil;atomicUndoInput=false
  }
  private func noteUndoInput(in range:NSRange,replacement:String?) {
    guard !hasMarkedText(),undoManager?.isUndoing != true,undoManager?.isRedoing != true,
      let replacement,range.location != NSNotFound,NSMaxRange(range) <= (string as NSString).length
    else {undoInput=nil;atomicUndoInput=false;return}
    let deleting=replacement.isEmpty && range.length>0
    let text=deleting ? (string as NSString).substring(with:range):replacement
    let space=text == " " || text == "\t"
    let word=text.count == 1 && text.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0) || "_@#".unicodeScalars.contains($0)
    }
    let atomic=(!space && !word) || (!deleting && range.length>0)
    let now=ProcessInfo.processInfo.systemUptime
    let backward=deleting && range.location < selectedRange().location
    let caretBefore=backward ? NSMaxRange(range):range.location
    if atomic || undoInput == nil || undoInput.map({
      $0.deleting != deleting || $0.backward != backward || $0.caret != caretBefore || now-$0.time>1
        || (deleting ? $0.space != space : $0.space && !space)
    }) == true {breakUndoCoalescing()}
    undoInput=UndoInput(deleting:deleting,backward:backward,space:space,caret:range.location+(replacement as NSString).length,time:now)
    atomicUndoInput=atomic
  }
  private var nativeUndoInput=false
  private func withUndoInput(in range:NSRange,replacement:String?,edit:()->Void) {
    guard !nativeUndoInput,isEditable else {edit();return}
    nativeUndoInput=true;defer {nativeUndoInput=false}
    // Break before AppKit prepares the edit, not in shouldChangeText: that callback
    // is too late and would leave the first character in the preceding undo step.
    noteUndoInput(in:range,replacement:replacement)
    let atomic=atomicUndoInput
    edit()
    if atomic {finishUndoInput()}
  }
  override func insertText(_ value:Any,replacementRange:NSRange) {
    let text=(value as? String) ?? (value as? NSAttributedString)?.string
    let range=replacementRange.location == NSNotFound ? selectedRange():replacementRange
    withUndoInput(in:range,replacement:text) {super.insertText(value,replacementRange:replacementRange)}
  }
  override func deleteBackward(_ sender:Any?) {
    var range=selectedRange()
    if range.length == 0,range.location>0,range.location <= (string as NSString).length {
      range=(string as NSString).rangeOfComposedCharacterSequence(at:range.location-1)
    }
    withUndoInput(in:range,replacement:"") {super.deleteBackward(sender)}
  }
  override func deleteForward(_ sender:Any?) {
    var range=selectedRange()
    if range.length == 0,range.location < (string as NSString).length {
      range=(string as NSString).rangeOfComposedCharacterSequence(at:range.location)
    }
    withUndoInput(in:range,replacement:"") {super.deleteForward(sender)}
  }
  override func cut(_ sender:Any?) {
    finishUndoInput();super.cut(sender);finishUndoInput()
  }
  override func paste(_ sender:Any?) {
    finishUndoInput();super.paste(sender);finishUndoInput()
  }
  // NSWindow normally owns these responder actions. Route the Edit menu to this
  // editor too, so its validation and execution use the same per-query history.
  @objc(undo:) func undoFromMenu(_ sender:Any?) {undoSQL(sender)}
  @objc(redo:) func redoFromMenu(_ sender:Any?) {redoSQL(sender)}
  @objc func undoSQL(_ sender:Any?) {
    guard isEditable else {return}
    dismissSuggestions?();finishUndoInput();undoManager?.undo()
  }
  @objc func redoSQL(_ sender:Any?) {
    guard isEditable else {return}
    dismissSuggestions?();finishUndoInput();undoManager?.redo()
  }
  private func handleHistoryKey(_ event:NSEvent)->Bool {
    let flags=event.modifierFlags.intersection([.command,.control,.shift,.option])
    let key=event.charactersIgnoringModifiers?.lowercased()
    if GridShortcuts.matches(.undo,event) || (key == "z" && (flags == .control || flags == .command)) {undoSQL(nil);return true}
    if GridShortcuts.matches(.redo,event) || (key == "y" && flags == .control)
      || (key == "z" && (flags == [.control,.shift] || flags == [.command,.shift])) {redoSQL(nil);return true}
    return false
  }
  private enum CaretMovement { case word, line }
  @discardableResult private func navigateSQL(_ movement:CaretMovement,_ direction:SQLCaretNavigation.Direction,extending:Bool=false)->Bool {
    guard isSelectable,!hasMarkedText(),selectedRanges.count == 1 else {return false}
    let range=selectedRange(),length=(string as NSString).length
    guard range.location != NSNotFound,range.location <= length,range.length <= length-range.location else {return false}
    // TextKit 2 affinity describes the non-anchored edge of a nonempty
    // selection. Preserve it when Shift reverses or crosses the anchor.
    let upstream=selectionAffinity == .upstream
    let anchor=upstream ? NSMaxRange(range):range.location
    let head=extending ? (upstream ? range.location:NSMaxRange(range))
      : (direction == .backward ? range.location:NSMaxRange(range))
    let destination:Int
    if !extending,movement == .word,range.length > 0 {
      destination=head
    } else if movement == .word {
      destination=SQLCaretNavigation.wordBoundary(in:string,from:head,direction:direction)
    } else {
      destination=SQLCaretNavigation.lineBoundary(in:string,from:head,direction:direction)
    }
    dismissSuggestions?();finishUndoInput()
    let selection=extending ? NSRange(location:min(anchor,destination),length:abs(destination-anchor))
      : NSRange(location:destination,length:0)
    setSelectedRange(selection,affinity:extending && destination < anchor ? .upstream:.downstream,stillSelecting:false)
    scrollRangeToVisible(NSRange(location:destination,length:0))
    return true
  }
  private func handleSQLNavigationKey(_ event:NSEvent)->Bool {
    guard event.keyCode == 123 || event.keyCode == 124 else {return false}
    let flags=event.modifierFlags.intersection([.command,.control,.option,.shift])
    let modifiers=flags.subtracting(.shift)
    guard modifiers == .option || modifiers == .command else {return false}
    return navigateSQL(modifiers == .option ? .word:.line,event.keyCode == 123 ? .backward:.forward,extending:flags.contains(.shift))
  }
  override func moveWordLeft(_ sender:Any?) {if !navigateSQL(.word,.backward) {super.moveWordLeft(sender)}}
  override func moveWordRight(_ sender:Any?) {if !navigateSQL(.word,.forward) {super.moveWordRight(sender)}}
  override func moveWordBackward(_ sender:Any?) {if !navigateSQL(.word,.backward) {super.moveWordBackward(sender)}}
  override func moveWordForward(_ sender:Any?) {if !navigateSQL(.word,.forward) {super.moveWordForward(sender)}}
  override func moveWordLeftAndModifySelection(_ sender:Any?) {if !navigateSQL(.word,.backward,extending:true) {super.moveWordLeftAndModifySelection(sender)}}
  override func moveWordRightAndModifySelection(_ sender:Any?) {if !navigateSQL(.word,.forward,extending:true) {super.moveWordRightAndModifySelection(sender)}}
  override func moveWordBackwardAndModifySelection(_ sender:Any?) {if !navigateSQL(.word,.backward,extending:true) {super.moveWordBackwardAndModifySelection(sender)}}
  override func moveWordForwardAndModifySelection(_ sender:Any?) {if !navigateSQL(.word,.forward,extending:true) {super.moveWordForwardAndModifySelection(sender)}}
  override func moveToBeginningOfLine(_ sender:Any?) {if !navigateSQL(.line,.backward) {super.moveToBeginningOfLine(sender)}}
  override func moveToEndOfLine(_ sender:Any?) {if !navigateSQL(.line,.forward) {super.moveToEndOfLine(sender)}}
  override func moveToLeftEndOfLine(_ sender:Any?) {if !navigateSQL(.line,.backward) {super.moveToLeftEndOfLine(sender)}}
  override func moveToRightEndOfLine(_ sender:Any?) {if !navigateSQL(.line,.forward) {super.moveToRightEndOfLine(sender)}}
  override func moveToBeginningOfLineAndModifySelection(_ sender:Any?) {if !navigateSQL(.line,.backward,extending:true) {super.moveToBeginningOfLineAndModifySelection(sender)}}
  override func moveToEndOfLineAndModifySelection(_ sender:Any?) {if !navigateSQL(.line,.forward,extending:true) {super.moveToEndOfLineAndModifySelection(sender)}}
  override func moveToLeftEndOfLineAndModifySelection(_ sender:Any?) {if !navigateSQL(.line,.backward,extending:true) {super.moveToLeftEndOfLineAndModifySelection(sender)}}
  override func moveToRightEndOfLineAndModifySelection(_ sender:Any?) {if !navigateSQL(.line,.forward,extending:true) {super.moveToRightEndOfLineAndModifySelection(sender)}}
  private var quoteClosers:[Int:UInt16] = [:]
  private var quoteSource=""
  // Declared native edit ranges distinguish typing from replacing/pasting whole SQL.
  // Programmatic replacements and undo without an input callback invalidate markers.
  private func refreshQuoteClosers() {
    if quoteSource != string || string.utf16.count > 250_000 {quoteClosers=[:]}
    quoteSource=string
  }
  override func shouldChangeText(in range:NSRange,replacementString:String?) -> Bool {
    sqlFinder.noteClientStringWillChange()
    refreshQuoteClosers()
    guard super.shouldChangeText(in:range,replacementString:replacementString) else {return false}
    guard !quoteClosers.isEmpty,let replacementString,range.location != NSNotFound,
      NSMaxRange(range) <= (string as NSString).length else {quoteClosers=[:];return true}
    let delta=(replacementString as NSString).length-range.length
    quoteClosers=Dictionary(uniqueKeysWithValues:quoteClosers.compactMap {offset,quote in
      if offset < range.location {return (offset,quote)}
      if offset >= NSMaxRange(range) {return (offset+delta,quote)}
      return nil
    })
    quoteSource=(string as NSString).replacingCharacters(in:range,with:replacementString)
    return true
  }
  private func handleQuoteKey(_ event:NSEvent) -> Bool {
    guard isEditable,!hasMarkedText(),selectedRanges.count == 1,
      event.modifierFlags.intersection([.command,.control,.option]).isEmpty else {return false}
    let quote=event.characters == "'" ? UInt16(39):event.characters == "\"" ? UInt16(34):nil
    guard quote != nil || event.keyCode == 51 else {return false}
    prepareEdit?()
    refreshQuoteClosers()
    let range=selectedRange(),source=string as NSString
    let originalLength=source.length
    guard range.location != NSNotFound,NSMaxRange(range) <= source.length else {return false}
    if event.keyCode == 51 {
      guard range.length == 0,range.location > 0,let closing=quoteClosers[range.location],
        source.character(at:range.location-1) == closing else {return false}
      insertText("",replacementRange:NSRange(location:range.location-1,length:2))
      refreshQuoteClosers();return true
    }
    guard let quote else {return false}
    if range.length == 0,quoteClosers[range.location] == quote {
      quoteClosers.removeValue(forKey:range.location)
      setSelectedRange(NSRange(location:range.location+1,length:0));return true
    }
    guard TSQL.allowsQuotePair(in:string,at:range.location) else {return false}
    if range.length == 0,range.location < source.length {
      let next=source.character(at:range.location)
      // Do not manufacture a closer in the middle of existing text or escaped SQL.
      guard [9,10,13,32,41,44,59,61,43,45,42,47,60,62,33].contains(next) else {return false}
    }
    let mark=String(UnicodeScalar(quote)!)
    let selected=source.substring(with:range)
    insertText(mark+selected+mark,replacementRange:range)
    // A read-only delegate may reject the insertion.
    guard (string as NSString).length == originalLength+2 else {return true}
    refreshQuoteClosers()
    quoteClosers[range.location+range.length+1]=quote;quoteSource=string
    setSelectedRange(NSRange(location:range.location+1,length:range.length))
    return true
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if window?.firstResponder === self,handleHistoryKey(event) {return true}
    if GridShortcuts.matches(.matchingPair,event) {jumpToMatchingPair?();return true}
    if GridShortcuts.matches(.parameterInfo,event) {requestParameterInfo?();return true}
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers?.lowercased() == "b" { navigateDefinition?(); return true }
    if isFindShortcut(event) {showSelectionFind();return true}
    return super.performKeyEquivalent(with:event)
  }
  private func isFindShortcut(_ event:NSEvent)->Bool {
    let modifiers=event.modifierFlags.intersection([.command,.control,.option,.shift])
    return (modifiers == .command || modifiers == .control) && event.charactersIgnoringModifiers?.lowercased() == "f"
  }
  func showSelectionFind() {
    let item=NSMenuItem(); item.tag=NSTextFinder.Action.showFindInterface.rawValue
    performFindPanelAction(item)
  }
  override func performFindPanelAction(_ sender: Any?) {
    dismissSuggestions?()
    if (sender as? NSValidatedUserInterfaceItem)?.tag == NSTextFinder.Action.showFindInterface.rawValue {
      prepareEdit?()
      if selectedRange().length > 0 {sqlFinder.performAction(.setSearchString)}
    }
    if let item=sender as? NSValidatedUserInterfaceItem,let action=NSTextFinder.Action(rawValue:item.tag) {sqlFinder.performAction(action)}
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
  var jumpToMatchingPair:(()->Void)?
  var requestParameterInfo:(()->Void)?
  @objc private func goToMatchingPair(_ sender:Any?) {jumpToMatchingPair?()}
  @objc private func showParameterInfo(_ sender:Any?) {requestParameterInfo?()}
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
    for (title,action) in [("Geri Al ("+GridShortcuts.binding(.undo).label+")",#selector(undoSQL(_:))),("İleri Al ("+GridShortcuts.binding(.redo).label+")",#selector(redoSQL(_:)))] {
      let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;menu.addItem(item)
    }
    menu.addItem(.separator())
    for (title,action) in [("Eşleşen Ayırıcıya Git ("+GridShortcuts.binding(.matchingPair).label+")",#selector(goToMatchingPair(_:))),("Parametre Bilgisi ("+GridShortcuts.binding(.parameterInfo).label+")",#selector(showParameterInfo(_:)))] {
      let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;menu.addItem(item)
    }
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
    if handleHistoryKey(event) {return}
    if GridShortcuts.matches(.matchingPair,event) {jumpToMatchingPair?();return}
    if GridShortcuts.matches(.parameterInfo,event) {requestParameterInfo?();return}
    if isFindShortcut(event) {showSelectionFind();return}
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control, event.charactersIgnoringModifiers?.lowercased() == "a" { selectAll(nil); return }
    if handleSQLNavigationKey(event) {return}
    if suggestionKey?(event) == true { return }
    if event.keyCode == 49 && event.modifierFlags.contains(.control), let requestSuggestions { requestSuggestions(); return }
    if event.modifierFlags.contains([.command,.option]), event.keyCode == 33 { toggleOutline?(); return }
    if event.modifierFlags.contains([.command,.option]), event.keyCode == 30 { expandOutline?(); return }
    if event.keyCode == 96 || event.keyCode == 36 && event.modifierFlags.contains(.command) {
      run?()
    } else if event.keyCode == 53 || event.keyCode == 49 && event.modifierFlags.contains(.control) {
      dismissSuggestions?()
    } else {
      if handleQuoteKey(event) {return}
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
  var ruleThickness: CGFloat = 44
  static func width(lineCount:Int,font:NSFont) -> CGFloat {
    max(44,ceil((String(max(1,lineCount)) as NSString).size(withAttributes:[.font:font]).width)+28)
  }
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
private struct SQLParameterHelp:View {
  let name:String
  let parameters:[RoutineParameter]
  let active:Int?
  let status:String?
  var body:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Image(systemName:"list.number").foregroundStyle(Color(nsColor:StudioTheme.accent))
        Text(name).font(.system(size:12,weight:.semibold,design:.monospaced)).lineLimit(1).truncationMode(.middle)
        Spacer()
        Text(GridShortcuts.binding(.parameterInfo).label+" · esc").font(.system(size:10)).foregroundStyle(.secondary)
      }
      Divider()
      if let status {Text(status).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
      else if parameters.isEmpty {Text("Parametre almıyor").font(.system(size:12)).foregroundStyle(.secondary)}
      else {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment:.leading,spacing:2) {
              ForEach(Array(parameters.enumerated()),id: \.element.id) { index,p in
                HStack(spacing:8) {
                  Text(String(index+1)).frame(width:20).foregroundStyle(.secondary)
                  Text(p.name).fontWeight(active == index ? .bold:.medium)
                  Text(p.type+(p.output ? " OUTPUT":"")+(p.tableType ? " READONLY":"")).foregroundStyle(.secondary)
                  Spacer(minLength:0)
                }.font(.system(size:11,design:.monospaced)).padding(.horizontal,6).padding(.vertical,5)
                  .background(active == index ? Color(nsColor:StudioTheme.accent).opacity(0.16):.clear,in:RoundedRectangle(cornerRadius:5)).id(index)
              }
            }
          }.onAppear {if let active {proxy.scrollTo(active,anchor:.center)}}
            .onChange(of:active) {_,value in if let value {proxy.scrollTo(value,anchor:.center)}}
        }
      }
    }.padding(12).background(Color(nsColor:StudioTheme.panel)).accessibilityIdentifier("sqlParameterInfo")
  }
}
@MainActor final class EditorController: NSObject, NSTextViewDelegate, NSPopoverDelegate {
  let surface = NSView()
  let scroll = SQLEditorScrollView()
  let editor = SQLTextView(usingTextLayoutManager: true)
  let occurrenceHighlights = OccurrenceHighlights()
  private let ruler: LineNumbers
  private var rulerWidth:NSLayoutConstraint?
  private let document: QueryDocument
  var edited: (() -> Void)?
  var position: ((Int, Int) -> Void)?
  private var intelligenceTask: Task<Void,Never>?
  private var occurrenceTask: Task<Void,Never>?
  private var intelligenceGeneration = UUID()
  private let suggestionList = SQLSuggestionList()
  private let suggestionPopover = NSPopover()
  private let parameterPopover=NSPopover()
  private var parameterTask:Task<Void,Never>?
  private var parameterGeneration=UUID()
  private var parameterCache:[String:(Date,[RoutineParameter])]=[:]
  private(set) var parameterCall:SQLRoutineCall?
  private(set) var parameterValues:[RoutineParameter]=[]
  private(set) var parameterStatus:String?
  var parameterShown:Bool {parameterPopover.isShown}
  private var suggestionKeyMonitor: SQLSuggestionKeyMonitor?
  private var analysisCaret = -1
  var completionSize:NSSize {suggestionPopover.contentSize}
  var completionShown:Bool {suggestionPopover.isShown}
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
    editor.usesFindBar = false
    editor.configureFinder(in:scroll)
    editor.findMatchesChanged = { [weak self] ranges in self?.occurrenceHighlights.findRanges=Array(ranges.prefix(500)) }
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
    editor.requestParameterInfo = { [weak self] in self?.scheduleParameters(manual:true) }
    editor.jumpToMatchingPair = { [weak self] in self?.jumpToMatchingPair() }
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
    ruler.ruleThickness = 44
    surface.wantsLayer = true; surface.clipsToBounds = true
    surface.addSubview(ruler); surface.addSubview(scroll)
    ruler.translatesAutoresizingMaskIntoConstraints = false; scroll.translatesAutoresizingMaskIntoConstraints = false
    rulerWidth=ruler.widthAnchor.constraint(equalToConstant:44)
    NSLayoutConstraint.activate([
      ruler.leadingAnchor.constraint(equalTo:surface.leadingAnchor), ruler.topAnchor.constraint(equalTo:surface.topAnchor),
      ruler.bottomAnchor.constraint(equalTo:surface.bottomAnchor), rulerWidth!,
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
    suggestionPopover.delegate = self
    suggestionPopover.animates = false; suggestionPopover.behavior = .semitransient
    suggestionList.accept = { [weak self] in self?.acceptSuggestion($0) }
    editor.requestSuggestions = { [weak self] in self?.scheduleIntelligence(manual:true) }
    editor.dismissSuggestions = { [weak self] in self?.suggestionPopover.close();self?.dismissParameterHelp() }
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
    editor.finishUndoInput()
    editor.sqlFinder.noteClientStringWillChange()
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
    let gutterWidth=LineNumbers.width(lineCount:document.sql.utf16.reduce(1) {$1 == 10 ? $0+1:$0},font:StudioTheme.codeFont)
    if rulerWidth?.constant != gutterWidth {
      rulerWidth?.constant=gutterWidth;ruler.ruleThickness=gutterWidth
      surface.layoutSubtreeIfNeeded()
    }
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
    editor.finishUndoInput()
    editor.insertText(text,replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    editor.finishUndoInput()
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
      editor.finishUndoInput()
      editor.sqlFinder.noteClientStringWillChange()
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
    if !editor.hasMarkedText() {highlight()}
    updateOutline(refreshRegions:false)
    regions = []
    resizeToViewport()
    ruler.needsDisplay = true
    edited?()
    suggestionPopover.close()
    scheduleParameters()
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
    scheduleParameters()
    document.selectedRange = projection?.sourceRange(range) ?? range
    let prefix = (document.sql as NSString).substring(
      to: min(document.selectedRange.location, (document.sql as NSString).length))
    position?(
      prefix.filter { $0 == "\n" }.count + 1,
      (prefix.split(separator: "\n", omittingEmptySubsequences: false).last?.utf16.count ?? 0) + 1)
    if !changingPresentation && editor.string == analysisSource && range.location != analysisCaret { suggestionPopover.close(); scheduleIntelligence(allowPopup:false) }
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
    occurrenceHighlights.blockRanges=[]
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
    let sourceRange=projection?.sourceRange(range) ?? range
    let blocks=range.length == 0 ? TSQL.matchingBlock(in:document.sql,at:sourceRange.location):[]
    occurrenceHighlights.blockRanges=blocks.compactMap { block in
      guard let projection else {return block}
      guard !projection.regions.contains(where: {NSIntersectionRange($0.hidden,block).length > 0}) else {return nil}
      return NSRange(location:projection.displayOffset(block.location),length:block.length)
    }
    occurrenceRanges=updatedRanges
    occurrenceHighlights.ranges=updatedRanges
    // Also repaint when the selected occurrence changes within the same match set.
    // The selected word keeps its native selection color; the other matches get yellow.
    occurrenceHighlights.needsDisplay=true
  }
  func dismissParameterHelp() {
    parameterTask?.cancel();parameterGeneration=UUID();parameterPopover.close()
  }
  func scheduleParameters(manual:Bool=false) {
    parameterTask?.cancel()
    let generation=UUID();parameterGeneration=generation
    guard projection == nil,editor.selectedRange().length == 0,!editor.hasMarkedText(),editor.window == nil || editor.window?.firstResponder === editor else {parameterPopover.close();return}
    let source=editor.string,caret=editor.selectedRange().location,db=document.database,server=document.server,serverGeneration=document.server.generation
    let catalog=document.catalogDatabase == db ? document.intelligenceCatalog:nil
    parameterTask=Task { [weak self] in
      do {
        if !manual {try await Task.sleep(for:.milliseconds(180))}
        let call=await Task.detached(priority:.userInitiated) {SQLRoutineCall.context(source:source,caret:caret,catalog:catalog)}.value
        guard let self else {return}
        guard !Task.isCancelled,parameterGeneration == generation,editor.string == source,editor.selectedRange().location == caret,document.database == db,document.server === server,server.generation == serverGeneration else {return}
        guard let call else {parameterCall=nil;parameterValues=[];parameterStatus=nil;parameterPopover.close();return}
        parameterCall=call
        let key=server.id.uuidString+"|"+db+"|"+serverGeneration.uuidString+"|"+call.key
        if let cached=parameterCache[key],Date().timeIntervalSince(cached.0)<300 {
          parameterValues=cached.1;parameterStatus=nil;showParameterHelp();return
        }
        parameterValues=[];parameterStatus="Parametreler yükleniyor…";showParameterHelp()
        do {
          var limits=Limits();limits.rows=2100;limits.totalBytes=1_048_576;limits.timeout=15
          let ids=try await server.catalog("SELECT object_id FROM sys.objects WHERE schema_id=SCHEMA_ID(\(SQL.literal(call.symbol.schema))) AND name=\(SQL.literal(call.symbol.name));",database:db,limits:limits)
          try Task.checkCancellation()
          guard parameterGeneration == generation,document.database == db,server.generation == serverGeneration else {return}
          guard !ids.partial,let raw=ids.results.first?.values.first?.first,let raw,let id=Int(raw) else {throw SQLFailure("Nesne bulunamadı; indeksi yenileyin.")}
          let values=try RoutineScripts.decode(await server.catalog(RoutineScripts.parameters(id),database:db,limits:limits)).sorted {$0.id<$1.id}
          guard !Task.isCancelled else {return}
          guard server.generation == serverGeneration else {throw SQLFailure("Bağlantı değişti; parametre bilgisini yeniden açın.")}
          if parameterCache.count>=64 {parameterCache.removeAll()}
          parameterCache[key]=(Date(),values)
          guard parameterGeneration == generation,editor.string == source,editor.selectedRange().location == caret,document.database == db else {return}
          parameterValues=values;parameterStatus=nil;showParameterHelp()
        } catch {
          guard !Task.isCancelled,parameterGeneration == generation,editor.string == source,editor.selectedRange().location == caret,document.database == db else {return}
          parameterStatus="Parametre bilgisi alınamadı: "+error.localizedDescription;showParameterHelp()
        }
      } catch { /* Superseded caret/source never publishes old parameter metadata. */ }
    }
  }
  private func showParameterHelp() {
    guard let call=parameterCall,let window=editor.window,window.firstResponder === editor,let anchor=suggestionAnchor() else {return}
    suggestionPopover.close()
    let height=parameterStatus == nil && !parameterValues.isEmpty ? CGFloat(min(6,parameterValues.count))*28+62:104
    let content=SQLParameterHelp(name:call.symbol.schema+"."+call.symbol.name,parameters:parameterValues,active:call.activeIndex(in:parameterValues),status:parameterStatus)
    StudioPopover.show(parameterPopover,content:content,from:editor,rect:anchor,size:NSSize(width:480,height:height))
  }
  func jumpToMatchingPair() {
    let sourceRange=projection?.sourceRange(editor.selectedRange()) ?? editor.selectedRange()
    let pair=TSQL.matchingBlock(in:document.sql,at:sourceRange.location)
    guard pair.count == 2 else {NSSound.beep();return}
    let current=pair.firstIndex {$0.location <= sourceRange.location && sourceRange.location < NSMaxRange($0)} ?? pair.firstIndex {NSMaxRange($0) == sourceRange.location} ?? 0
    let destination=pair[1-current].location
    if projection != nil {expandAll()}
    editor.setSelectedRange(NSRange(location:destination,length:0));editor.scrollRangeToVisible(NSRange(location:destination,length:0))
    updateOccurrences()
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
    editor.sqlFinder.noteClientStringWillChange()
    dismissParameterHelp()
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
  @objc private func catalogChanged() {dismissParameterHelp();scheduleParameters();scheduleIntelligence(allowPopup:false)}
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
    let includeSchema = SQLEditorPreferences.includeSchema()
    let quoteIdentifiers = SQLEditorPreferences.quoteIdentifiers()
    let automatic = UserDefaults.standard.object(forKey:"sqlAutomaticCompletion") as? Bool ?? true
    let validate = UserDefaults.standard.object(forKey:"sqlValidateReferences") as? Bool ?? true
    let delay = SQLEditorPreferences.completionDelay()
    intelligenceTask = Task { [weak self] in
      do {
        if !manual { try await Task.sleep(for:.milliseconds(delay)) }
        let worker = Task.detached(priority:.userInitiated) {
          let analysis = try SQLIntelligence.analyze(source:source,caret:caret,catalog:catalog,verified:verified,automaticAliases:aliases,automaticNoLock:noLock,includeSchema:includeSchema,quoteIdentifiers:quoteIdentifiers)
          try Task.checkCancellation()
          return (analysis,SQLFolding.regions(source))
        }
        let (analysis,regions) = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
        guard !Task.isCancelled, let self, intelligenceGeneration == generation, editor.string == source, editor.selectedRange().location == caret else { return }
        self.regions = regions; ruler.needsDisplay = true
        diagnostics = validate ? analysis.diagnostics : []
        cachedTokens = analysis.tokens; cachedTokenSource = source
        currentAnalysis = analysis; analysisSource = source; analysisCaret = caret
        highlight()
        let prefixLength = caret-analysis.replacement.location
        let dot = analysis.replacement.location > 0 && (source as NSString).substring(with:NSRange(location:analysis.replacement.location-1,length:1)) == "."
        if !parameterPopover.isShown,(manual || automatic && allowPopup && (analysis.procedureCompletion || analysis.variableCompletion || prefixLength >= 2 || dot)), !analysis.suggestions.isEmpty, let window = editor.window, window.firstResponder === editor {
          guard let anchor = suggestionAnchor(), let host = window.contentView else { return }
          let hostAnchor = host.convert(anchor,from:editor)
          var below=true
          let preferredHeight=CGFloat(max(1,min(16,analysis.suggestions.count)))*26+52
          var maximumHeight=preferredHeight
          if let screen=window.screen {
            let screenAnchor=window.convertToScreen(host.convert(hostAnchor,to:nil))
            let placement=SQLSuggestionList.placement(anchor:screenAnchor,screen:screen.visibleFrame,preferredHeight:preferredHeight)
            below=placement.below
            maximumHeight=placement.height
          }
          let rows=max(1,min(16,Int((maximumHeight-52)/26),analysis.suggestions.count))
          // AppKit can retain the first content height after the list shrinks.
          // Reattach the sized controller to reset the native content container;
          // closing/reopening alone leaves count-dependent space above the heading.
          let resizing=suggestionPopover.contentSize.height != CGFloat(rows)*26+52
          if resizing {
            suggestionPopover.close()
            suggestionPopover.contentViewController=nil
          }
          suggestionList.update(analysis.suggestions,prefix:(source as NSString).substring(with:NSRange(location:analysis.replacement.location,length:prefixLength)))
          suggestionList.fit(maximumHeight:maximumHeight)
          if resizing {suggestionPopover.contentViewController=suggestionList}
          suggestionPopover.contentSize=suggestionList.preferredContentSize
          let edge:NSRectEdge=below ? (host.isFlipped ? .maxY:.minY):(host.isFlipped ? .minY:.maxY)
          suggestionPopover.show(relativeTo:hostAnchor,of:host,preferredEdge:edge)
          window.makeFirstResponder(editor)
          installSuggestionKeys()
        } else { suggestionPopover.close() }
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
  private func installSuggestionKeys() {
    guard suggestionKeyMonitor == nil else {return}
    let token=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
      let handled=MainActor.assumeIsolated {
        guard let self, self.suggestionPopover.isShown,
          let eventWindow=event.window,
          eventWindow === self.suggestionList.view.window || eventWindow === self.editor.window && self.editor.window?.firstResponder === self.editor else {return false}
        return self.handleSuggestionKey(event)
      }
      return handled ? nil:event
    }
    if let token {suggestionKeyMonitor=SQLSuggestionKeyMonitor(token)}
  }
  func popoverWillClose(_ notification:Notification) {
    suggestionKeyMonitor=nil
  }
  private func handleSuggestionKey(_ event: NSEvent) -> Bool {
    guard suggestionPopover.isShown, event.modifierFlags.intersection([.command,.control,.option]).isEmpty else { return false }
    switch event.keyCode {
    case 125: suggestionList.move(1); return true
    case 126: suggestionList.move(-1); return true
    case 116: suggestionList.move(-suggestionList.visibleRowCount); return true
    case 121: suggestionList.move(suggestionList.visibleRowCount); return true
    case 115: suggestionList.move(-suggestionList.items.count); return true
    case 119: suggestionList.move(suggestionList.items.count); return true
    case 48 where event.modifierFlags.contains(.shift): suggestionList.move(-1); return true
    case 48,36,76: acceptSuggestion(suggestionList.table.selectedRow); return true
    case 53: suggestionPopover.close(); intelligenceTask?.cancel(); return true
    default: return false
    }
  }
  private func acceptSuggestion(_ index: Int) {
    guard let analysis = currentAnalysis, analysisSource == editor.string, analysis.suggestions.indices.contains(index), projection == nil else { suggestionPopover.close(); return }
    suggestionPopover.close(); suppressNextPopup = true
    editor.window?.makeFirstResponder(editor)
    editor.finishUndoInput()
    editor.insertText(analysis.suggestions[index].text,replacementRange:analysis.replacement)
    editor.finishUndoInput()
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
    guard !editor.hasMarkedText() else {return}
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
    let caret=editor.selectedRange().location
    let token=tokens.first {$0.range.location < caret && NSMaxRange($0.range) > caret}
    editor.typingAttributes[.foregroundColor] = token.map {SQLSourceHighlighting.foreground($0,unused:false)} ?? StudioTheme.editorText
    scrolled()
    assert(editor.textLayoutManager != nil)
  }
}
