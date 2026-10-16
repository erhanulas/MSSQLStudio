import AppKit
import SwiftUI
import SQLServerKit

private final class SQLFindKeyMonitor:@unchecked Sendable {
  let token:Any
  init(_ token:Any) {self.token=token}
  deinit {NSEvent.removeMonitor(token)}
}
@MainActor final class SQLTextView: StudioTextView, @preconcurrency NSTextFinderClient {
  lazy var sqlFinder:NSTextFinder = {
    let finder=NSTextFinder();finder.client=self
    finder.isIncrementalSearchingEnabled=true;finder.incrementalSearchingShouldDimContentView=false
    return finder
  }()
  private var batchEditDepth=0
  var isBatchEditing:Bool {batchEditDepth>0}
  var batchEditingEnded:(()->Void)?
  func performBatchEdit(_ edit:()->Void) {
    batchEditDepth+=1
    defer {batchEditDepth-=1;if batchEditDepth==0 {batchEditingEnded?()}}
    edit()
  }
  var dismissCaretSuggestions:(()->Void)?
  lazy var columnSelection=EditorColumnSelection(editor:self)
  override func draw(_ dirtyRect:NSRect) {super.draw(dirtyRect);columnSelection.draw(in:dirtyRect)}
  var hoverMoved:((NSPoint?)->Void)?
  private var hoverArea:NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas();if let hoverArea {removeTrackingArea(hoverArea)}
    let area=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
    addTrackingArea(area);hoverArea=area
  }
  override func mouseMoved(with event:NSEvent) {hoverMoved?(convert(event.locationInWindow,from:nil));super.mouseMoved(with:event)}
  override func mouseExited(with event:NSEvent) {hoverMoved?(nil);super.mouseExited(with:event)}
  override func viewWillMove(toWindow newWindow:NSWindow?) {if newWindow==nil {hoverMoved?(nil)};super.viewWillMove(toWindow:newWindow)}
  var findMatchesChanged:(([NSRange])->Void)?
  private var findObservation:NSKeyValueObservation?
  private var findKeyMonitor:SQLFindKeyMonitor?
  func configureFinder(in container:any NSTextFinderBarContainer) {
    sqlFinder.findBarContainer=container
    if findKeyMonitor == nil,let token=NSEvent.addLocalMonitorForEvents(matching:.keyDown,handler:{[weak self] event in
      let handled=MainActor.assumeIsolated {self?.handleFindKey(event) ?? false}
      return handled ? nil:event
    }) {findKeyMonitor=SQLFindKeyMonitor(token)}
    findObservation=sqlFinder.observe(\.incrementalMatchRanges,options:[.new]) { [weak self] finder,_ in
      let ranges=finder.incrementalMatchRanges.map { $0.rangeValue }
      Task { @MainActor [weak self] in self?.findMatchesChanged?(ranges) }
    }
  }
  func handleFindKey(_ event:NSEvent)->Bool {
    guard [36,76].contains(event.keyCode),event.modifierFlags.intersection([.command,.control,.option]).isEmpty,
      let window,event.window === window,let container=sqlFinder.findBarContainer,container.isFindBarVisible,
      let bar=container.findBarView,let editor=window.firstResponder as? NSTextView,editor.isFieldEditor,!editor.hasMarkedText(),
      let field=editor.delegate as? NSView,field.isDescendant(of:bar) else {return false}
    func fields(_ view:NSView)->[NSTextField] {(view as? NSTextField).map {[$0]} ?? view.subviews.flatMap(fields)}
    guard fields(bar).first(where:{$0.isEditable}) === field else {return false}
    let selection=editor.selectedRange()
    sqlFinder.performAction(event.modifierFlags.contains(.shift) ? .previousMatch:.nextMatch)
    window.makeFirstResponder(field)
    if let search=window.firstResponder as? NSTextView,search.isFieldEditor,NSMaxRange(selection)<=search.string.utf16.count {search.setSelectedRange(selection)}
    return true
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
    if item.action == #selector(revealExplorerObject(_:)) {return revealInExplorer != nil && ((item as? NSMenuItem)?.representedObject is [String] || DefinitionReference.parts(in:string,at:selectedRange().location,maxParts:3) != nil)}
    if item.action == #selector(showSQLCompletion(_:)) {return isEditable && !hasMarkedText() && requestSuggestions != nil}
    if item.action == #selector(goToDefinition(_:)) {return navigateDefinition != nil}
    if item.action == #selector(goToMatchingPair(_:)) {return jumpToMatchingPair != nil}
    if item.action == #selector(showParameterInfo(_:)) {return requestParameterInfo != nil}
    if item.action == #selector(toggleCodeOutline(_:)) {return toggleOutline != nil}
    if item.action == #selector(expandCodeOutline(_:)) {return expandOutline != nil}
    if item.action == #selector(runSQLStatement(_:)) {return isEditable && !hasMarkedText() && canRunStatement?() == true}
    if item.action == #selector(formatSQLText(_:)) {return isEditable && !hasMarkedText() && requestFormat != nil}
    if item.action == #selector(toggleSQLComment(_:)) || item.action == #selector(uncommentSQL(_:)) {return isEditable && !hasMarkedText() && selectedRanges.count == 1 && columnSelection.ranges.count<=1}
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
    if replacementRange.location == NSNotFound || replacementRange == selectedRange(),let text,columnSelection.replace(with:text) {return}
    let range=replacementRange.location == NSNotFound ? selectedRange():replacementRange
    withUndoInput(in:range,replacement:text) {super.insertText(value,replacementRange:replacementRange)}
  }
  override func deleteBackward(_ sender:Any?) {
    if columnSelection.replace(with:"",backward:true) {return}
    var range=selectedRange()
    if range.length == 0,range.location>0,range.location <= (string as NSString).length {
      range=(string as NSString).rangeOfComposedCharacterSequence(at:range.location-1)
    }
    withUndoInput(in:range,replacement:"") {super.deleteBackward(sender)}
  }
  override func deleteForward(_ sender:Any?) {
    if columnSelection.replace(with:"",backward:false) {return}
    var range=selectedRange()
    if range.length == 0,range.location < (string as NSString).length {
      range=(string as NSString).rangeOfComposedCharacterSequence(at:range.location)
    }
    withUndoInput(in:range,replacement:"") {super.deleteForward(sender)}
  }
  override func cut(_ sender:Any?) {
    if columnSelection.ranges.count>1 {copy(sender);_ = columnSelection.replace(with:"");return}
    finishUndoInput();super.cut(sender);finishUndoInput()
  }
  override func paste(_ sender:Any?) {
    if let text=NSPasteboard.general.string(forType:.string),columnSelection.replace(with:text) {return}
    finishUndoInput();super.paste(sender);finishUndoInput()
  }
  // NSWindow normally owns these responder actions. Route the Edit menu to this
  // editor too, so its validation and execution use the same per-query history.
  @objc(undo:) func undoFromMenu(_ sender:Any?) {undoSQL(sender)}
  @objc(redo:) func redoFromMenu(_ sender:Any?) {redoSQL(sender)}
  @objc func undoSQL(_ sender:Any?) {
    guard isEditable else {return}
    columnSelection.clear();dismissSuggestions?();finishUndoInput();undoManager?.undo()
  }
  @objc func redoSQL(_ sender:Any?) {
    guard isEditable else {return}
    columnSelection.clear();dismissSuggestions?();finishUndoInput();undoManager?.redo()
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
    guard isSelectable,!hasMarkedText(),!selectedRanges.isEmpty else {return false}
    let columnRanges=columnSelection.ranges
    let ranges=columnRanges.count>1 ? columnRanges:selectedRanges.map(\.rangeValue)
    let length=(string as NSString).length
    guard ranges.allSatisfy({$0.location != NSNotFound && $0.location <= length && $0.length <= length-$0.location}) else {return false}
    let upstream=(columnRanges.count>1 ? columnSelection.affinity:selectionAffinity) == .upstream
    var heads:[Int]=[]
    let selections=ranges.map { range -> NSValue in
      // TextKit 2 affinity describes the non-anchored edge of a nonempty
      // selection. Preserve it when Shift reverses or crosses the anchor.
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
      let selection=extending ? NSRange(location:min(anchor,destination),length:abs(destination-anchor))
        : NSRange(location:destination,length:0)
      heads.append(destination)
      return NSValue(range:selection)
    }
    dismissSuggestions?();finishUndoInput()
    let backwards=extending && zip(ranges,heads).contains { range,head in head < (upstream ? NSMaxRange(range):range.location) }
    if columnRanges.count>1 {columnSelection.set(selections.map(\.rangeValue),affinity:backwards ? .upstream:.downstream)}
    else {setSelectedRanges(selections,affinity:backwards ? .upstream:.downstream,stillSelecting:false)}
    if let head=heads.first {scrollRangeToVisible(NSRange(location:head,length:0))}
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
    guard isEditable,!hasMarkedText(),selectedRanges.count == 1,columnSelection.ranges.count<=1,
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
    if window?.firstResponder === self,GridShortcuts.matches(.runStatement,event) {runStatement?();return true}
    if window?.firstResponder === self,handleHistoryKey(event) {return true}
    if window?.firstResponder === self,handleCommentKey(event) {return true}
    if window?.firstResponder === self, GridShortcuts.matches(.format,event) {formatSQLText(nil);return true}
    if GridShortcuts.matches(.matchingPair,event) {jumpToMatchingPair?();return true}
    if GridShortcuts.matches(.parameterInfo,event) {requestParameterInfo?();return true}
    if window?.firstResponder === self,StudioCommandCatalog.dispatch(event,to:self,allowForwardedTarget:false,menu:{makeSQLMenu(at:selectedRange().location)}) {return true}
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
    var selectedSearch:String?
    if (sender as? NSValidatedUserInterfaceItem)?.tag == NSTextFinder.Action.showFindInterface.rawValue {
      prepareEdit?()
      let range=selectedRange(),source=string as NSString
      if range.length>0,NSMaxRange(range)<=source.length,columnSelection.ranges.count<=1 {
        selectedSearch=source.substring(with:range)
        sqlFinder.performAction(.setSearchString)
      }
    }
    if let item=sender as? NSValidatedUserInterfaceItem,let action=NSTextFinder.Action(rawValue:item.tag) {
      sqlFinder.performAction(action)
      if action == .showFindInterface || action == .showReplaceInterface {sqlFinder.findBarContainer?.isFindBarVisible=true}
      if let selectedSearch,let bar=sqlFinder.findBarContainer?.findBarView {
        func fields(_ view:NSView)->[NSTextField] {(view as? NSTextField).map {[$0]} ?? view.subviews.flatMap(fields)}
        if let field=fields(bar).first(where:{$0.isEditable}),field.stringValue != selectedSearch {
          // setSearchString updates the find pasteboard, but an already-open
          // native bar can keep its old field value. Commit through its action.
          field.stringValue=selectedSearch
          if let editor=field.currentEditor() as? NSTextView {editor.string=selectedSearch}
          if let action=field.action {_ = field.sendAction(action,to:field.target)}
          else {field.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:field))}
        }
      }
    }
  }
  override func selectAll(_ sender: Any?) { dismissSuggestions?(); super.selectAll(sender) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  private var lastWordClick:(source:String,word:NSRange,time:TimeInterval)?
  private(set) var trackingMouseSelection=false
  var mouseSelectionEnded:(() -> Void)?
  override func mouseDragged(with event:NSEvent) {
    if columnSelection.dragging {_ = autoscroll(with:event);columnSelection.update(to:convert(event.locationInWindow,from:nil));return}
    super.mouseDragged(with:event)
  }
  override func mouseUp(with event:NSEvent) {
    if columnSelection.dragging {columnSelection.update(to:convert(event.locationInWindow,from:nil));columnSelection.end();mouseSelectionEnded?();return}
    super.mouseUp(with:event)
  }
  override func mouseDown(with event: NSEvent) {
    if event.modifierFlags.intersection([.command,.control,.option]) == .option,isEditable,!hasMarkedText() {
      lastWordClick=nil
      window?.makeFirstResponder(self);dismissSuggestions?();finishUndoInput();prepareEdit?()
      columnSelection.begin(at:convert(event.locationInWindow,from:nil));return
    }
    columnSelection.clear()
    let clickPoint=convert(event.locationInWindow,from:nil)
    let clickedOffset=wordHitOffset(at:clickPoint)
    if let lastWordClick,!NSLocationInRange(clickedOffset,lastWordClick.word) {self.lastWordClick=nil}
    let navigationClick=DefinitionReference.isNavigationClick(event)
    trackingMouseSelection=true
    defer {trackingMouseSelection=false;if !navigationClick {mouseSelectionEnded?()}}
    if navigationClick {dismissSuggestions?()} else {dismissCaretSuggestions?()}
    window?.makeFirstResponder(self)
    if navigationClick {
      let point=convert(event.locationInWindow,from:nil)
      if let offset=DefinitionReference.clickedOffset(in:self,at:point) {
        setSelectedRange(NSRange(location:offset,length:0))
        navigateDefinition?()
      }
      return
    }
    if string.isEmpty,isEditable {
      setSelectedRange(NSRange(location:0,length:0))
      textLayoutManager?.textViewportLayoutController.layoutViewport()
      scrollRangeToVisible(selectedRange())
      updateInsertionPointStateAndRestartTimer(true)
      return
    }
    if event.clickCount>=3,selectSQLWord(at:clickedOffset,clickCount:event.clickCount,time:event.timestamp) {return}
    super.mouseDown(with: event)
    if event.clickCount == 2, unfoldSelection?(selectedRange()) == true {return}
    if event.clickCount == 2 {
      let pointer=window.map {convert($0.mouseLocationOutsideOfEventStream,from:nil)} ?? clickPoint
      let dragged=abs(pointer.x-clickPoint.x)>3 || abs(pointer.y-clickPoint.y)>3
      if dragged || !selectSQLWord(at:clickedOffset,clickCount:2,time:event.timestamp) {normalizeSQLWordSelection()}
    }
    // Double-click belongs to word selection. Navigation must be deliberate.
  }
  private func wordHitOffset(at point:NSPoint)->Int {
    let offset=characterIndexForInsertion(at:point)
    guard offset>0,let window else {return offset}
    let screen=firstRect(forCharacterRange:NSRange(location:offset,length:0),actualRange:nil)
    let caret=convert(window.convertFromScreen(screen),from:nil)
    if point.y>=caret.minY,point.y<=caret.maxY,point.x<caret.minX {
      return (string as NSString).rangeOfComposedCharacterSequence(at:offset-1).location
    }
    return offset
  }
  @discardableResult func selectSQLWord(at offset:Int,clickCount:Int,time:TimeInterval)->Bool {
    let text=string as NSString
    guard offset>=0,offset<text.length else {return false}
    func wordCharacter(_ index:Int)->Bool {
      guard index>=0,index<text.length,let scalar=UnicodeScalar(text.character(at:index)) else {return false}
      return CharacterSet.alphanumerics.contains(scalar) || "_@$#".unicodeScalars.contains(scalar)
    }
    guard wordCharacter(offset) else {return false}
    let word=selectionRange(forProposedRange:NSRange(location:offset,length:0),granularity:.selectByWord)
    func component(_ range:NSRange)->NSRange {
      if range.location>0,NSMaxRange(range)<text.length,text.character(at:range.location-1)==91,text.character(at:NSMaxRange(range))==93 {
        return NSRange(location:range.location-1,length:range.length+2)
      }
      return range
    }
    var qualified=component(word)
    for _ in 0..<3 {
      let dot=qualified.location-1
      guard dot>0,text.character(at:dot)==46 else {break}
      let index=text.character(at:dot-1)==93 ? dot-2:dot-1
      guard wordCharacter(index) else {break}
      let previous=component(selectionRange(forProposedRange:NSRange(location:index,length:0),granularity:.selectByWord))
      qualified=NSUnionRange(previous,qualified)
    }
    for _ in 0..<3 {
      let dot=NSMaxRange(qualified)
      guard dot+1<text.length,text.character(at:dot)==46 else {break}
      let index=text.character(at:dot+1)==91 ? dot+2:dot+1
      guard wordCharacter(index) else {break}
      let next=component(selectionRange(forProposedRange:NSRange(location:index,length:0),granularity:.selectByWord))
      qualified=NSUnionRange(qualified,next)
    }
    let repeated=lastWordClick.map {$0.source==string && $0.word==word && time >= $0.time && time-$0.time<=NSEvent.doubleClickInterval*2} ?? false
    if clickCount>=3,qualified==component(word) {return false}
    setSelectedRange(clickCount>=3 || repeated ? qualified:word)
    lastWordClick=(string,word,time)
    return true
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
  var requestFormat:(()->Void)?
  @objc func formatSQLText(_ sender: Any?) {
    guard isEditable, !hasMarkedText() else { return }
    requestFormat?()
  }
  var requestParameterInfo:(()->Void)?
  @objc private func goToMatchingPair(_ sender:Any?) {jumpToMatchingPair?()}
  @objc private func showParameterInfo(_ sender:Any?) {requestParameterInfo?()}
  var revealInExplorer: (([String]) -> Void)?
  @objc private func revealExplorerObject(_ item:NSMenuItem) {
    if let parts=item.representedObject as? [String] {revealInExplorer?(parts)}
    else if let item=makeSQLMenu(at:selectedRange().location).items.first(where:{$0.action == #selector(revealExplorerObject(_:))}),let parts=item.representedObject as? [String] {revealInExplorer?(parts)}
  }
  var navigateDefinition: (() -> Void)?
  var unfoldSelection: ((NSRange) -> Bool)?
  @objc private func goToDefinition(_ sender: Any?) { navigateDefinition?() }
  @objc func showSQLCompletion(_ sender:Any?) {guard isEditable,!hasMarkedText() else {return};requestSuggestions?()}
  var requestSuggestions: (() -> Void)?
  var suggestionKey: ((NSEvent) -> Bool)?
  var dismissSuggestions: (() -> Void)?
  var toggleOutline: (() -> Void)?
  var expandOutline: (() -> Void)?
  @objc private func toggleCodeOutline(_ sender: Any?) { toggleOutline?() }
  @objc private func expandCodeOutline(_ sender: Any?) { expandOutline?() }
  @objc func toggleSQLComment(_ sender:Any?) {changeSQLComment(uncomment:false)}
  @objc func uncommentSQL(_ sender:Any?) {changeSQLComment(uncomment:true)}
  private func changeSQLComment(uncomment:Bool) {
    guard isEditable,!hasMarkedText(),selectedRanges.count == 1,columnSelection.ranges.count<=1 else {return}
    window?.makeFirstResponder(self)
    dismissSuggestions?();prepareEdit?()
    guard let edit=SQLComments.edit(string,selection:selectedRange(),uncomment:uncomment) else {return}
    let old=string
    finishUndoInput()
    insertText(edit.replacement,replacementRange:edit.range)
    finishUndoInput()
    guard string != old else {return}
    setSelectedRange(edit.selection)
    undoManager?.setActionName(uncomment ? "Yorumu Kaldır":"Yorum Yap / Kaldır")
    scrollRangeToVisible(selectedRange())
  }
  private func handleCommentKey(_ event:NSEvent)->Bool {
    if GridShortcuts.matches(.comment,event) {toggleSQLComment(nil);return true}
    if GridShortcuts.matches(.uncomment,event) {uncommentSQL(nil);return true}
    return false
  }
  override func menu(for event: NSEvent) -> NSMenu? {
    let caret=characterIndexForInsertion(at:convert(event.locationInWindow,from:nil))
    return makeSQLMenu(at:caret,native:super.menu(for:event))
  }
  func makeSQLMenu(at caret:Int,native:NSMenu?=nil)->NSMenu {
    let menu=StudioMenu.adopting(native)
    menu.addItem(.separator())
    for (title,action) in [("Geri Al",#selector(undoSQL(_:))),("İleri Al",#selector(redoSQL(_:)))] {
      let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;menu.addItem(item)
    }
    menu.addItem(withTitle:"Tamamlamayı Göster",action:#selector(showSQLCompletion(_:)),keyEquivalent:"").target=self
    menu.addItem(.separator())
    let formatBinding = GridShortcuts.binding(.format)
    let formatItem = NSMenuItem(title: "SQL Formatla", action: #selector(formatSQLText(_:)), keyEquivalent: formatBinding.key)
    formatItem.target = self; formatItem.keyEquivalentModifierMask = formatBinding.flags; menu.addItem(formatItem)
    for (title,action,shortcut) in [("Yorum Yap / Kaldır",#selector(toggleSQLComment(_:)),GridShortcuts.Action.comment),("Yorumu Kaldır",#selector(uncommentSQL(_:)),.uncomment)] {
      let binding=GridShortcuts.binding(shortcut)
      let item=NSMenuItem(title:title,action:action,keyEquivalent:binding.key);item.target=self;item.keyEquivalentModifierMask=binding.flags;menu.addItem(item)
    }
    menu.addItem(.separator())
    for (title,action) in [("Eşleşen Ayırıcıya Git",#selector(goToMatchingPair(_:))),("Parametre Bilgisi",#selector(showParameterInfo(_:)))] {
      let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;menu.addItem(item)
    }
    var parts=DefinitionReference.parts(in:string,at:caret,maxParts:3)
    if let reference=parts,reference.count<=2,let alias=reference.first,
      let resolved=(try? SQLIntelligence.analyze(source:string,caret:caret,catalog:nil,verified:false))?.referenceBindings[alias.lowercased()] {parts=resolved}
    let reveal=NSMenuItem(title:"Explorer’da Git",action:#selector(revealExplorerObject(_:)),keyEquivalent:"")
    reveal.target=self;reveal.representedObject=parts;reveal.isEnabled=parts != nil && revealInExplorer != nil
    menu.addItem(reveal)
    let definition = NSMenuItem(title:"Nesne Tanımına Git",action:#selector(goToDefinition(_:)),keyEquivalent:""); definition.target = self; menu.addItem(definition)
    for (title, action) in [("Bloğu Daralt / Aç", #selector(toggleCodeOutline(_:))), ("Tüm Blokları Aç", #selector(expandCodeOutline(_:)))] {
      let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; menu.addItem(item)
    }
    return menu
  }
  var prepareEdit: (() -> Void)?
  var sourceCopy: (() -> String?)?
  override func copy(_ sender: Any?) {
    if columnSelection.ranges.count>1 {
      let source=string as NSString
      let selected=columnSelection.ranges.filter {$0.length>0}.map {source.substring(with:$0)}
      guard !selected.isEmpty else {return}
      NSPasteboard.general.clearContents();NSPasteboard.general.setString(selected.joined(separator:"\n"),forType:.string);return
    }
    guard let value = sourceCopy?() else { super.copy(sender); return }
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
  }
  var run: (() -> Void)?
  var runStatement:(()->Void)?
  var canRunStatement:(()->Bool)?
  @objc func runSQLStatement(_ sender:Any?) {runStatement?()}
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
    if columnSelection.replace(with:"\t") {return}
    let range = selectedRange()
    if selectedRanges.count == 1 && range.length == 0 { insertText("\t",replacementRange:range); return }
    indentLines(removing:false)
  }
  override func insertBacktab(_ sender: Any?) { prepareEdit?(); if columnSelection.removeIndent() {return}; indentLines(removing:true) }
  private func indentLines(removing: Bool) {
    guard isEditable,!hasMarkedText() else {return}
    let source=string as NSString
    var blocks:[NSRange]=[]
    for value in selectedRanges.sorted(by:{$0.rangeValue.location < $1.rangeValue.location}) {
      var range=value.rangeValue
      guard range.location != NSNotFound,range.location <= source.length,range.length <= source.length-range.location else {return}
      if range.length>0,source.substring(with:NSRange(location:NSMaxRange(range)-1,length:1)) == "\n" {range.length-=1}
      let lines=source.lineRange(for:range)
      if let last=blocks.last,lines.location <= NSMaxRange(last) {blocks[blocks.count-1]=NSUnionRange(last,lines)}
      else {blocks.append(lines)}
    }
    let edits=blocks.map { lines -> (NSRange,String) in
      let original=source.substring(with:lines),parts=original.components(separatedBy:"\n")
      let changed=parts.enumerated().map { index,line -> String in
        if index == parts.count-1 && line.isEmpty && original.hasSuffix("\n") {return line}
        if !removing {return "\t"+line}
        if line.hasPrefix("\t") {return String(line.dropFirst())}
        return String(line.dropFirst(line.prefix(4).prefix(while:{$0 == " "}).count))
      }.joined(separator:"\n")
      return (lines,changed)
    }
    guard edits.contains(where:{source.substring(with:$0.0) != $0.1}) else {return}
    finishUndoInput();undoManager?.beginUndoGrouping()
    performBatchEdit {for (range,text) in edits.reversed() {insertText(text,replacementRange:range)}}
    undoManager?.endUndoGrouping();finishUndoInput()
    var delta=0
    let selections=edits.map { range,text -> NSValue in
      let count=(text as NSString).length
      let selection=NSRange(location:range.location+delta,length:count)
      delta+=count-range.length
      return NSValue(range:selection)
    }
    setSelectedRanges(selections,affinity:.downstream,stillSelecting:false)
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
    lastWordClick=nil
    if handleHistoryKey(event) {return}
    if handleCommentKey(event) {return}
    if GridShortcuts.matches(.format,event) {formatSQLText(nil);return}
    if GridShortcuts.matches(.matchingPair,event) {jumpToMatchingPair?();return}
    if GridShortcuts.matches(.parameterInfo,event) {requestParameterInfo?();return}
    if isFindShortcut(event) {showSelectionFind();return}
    if StudioCommandCatalog.dispatch(event,to:self,allowForwardedTarget:false,menu:{makeSQLMenu(at:selectedRange().location)}) {return}
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control, event.charactersIgnoringModifiers?.lowercased() == "a" { selectAll(nil); return }
    if handleSQLNavigationKey(event) {return}
    if [123,124,125,126,115,119,53].contains(event.keyCode) {columnSelection.clear()}
    if suggestionKey?(event) == true { return }
    if GridShortcuts.matches(.completion,event),let requestSuggestions {requestSuggestions();return}
    if GridShortcuts.matches(.runStatement,event) {runStatement?();return}
    if event.keyCode == 96 {
      run?()
    } else if event.keyCode == 53 || event.keyCode == 49 && event.modifierFlags.contains(.control) {
      dismissSuggestions?()
    } else {
      if handleQuoteKey(event) {return}
      super.keyDown(with: event)
    }
  }
}
