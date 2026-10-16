import AppKit
import SwiftUI
import SQLServerKit

@MainActor final class EditorController: NSObject, NSTextViewDelegate {
  let surface = NSView()
  let scroll = SQLEditorScrollView()
  lazy var findContainer=EditorFindContainer(scroll:scroll)
  private var rulerTop:NSLayoutConstraint?
  let editor = SQLTextView(usingTextLayoutManager: true)
  let occurrenceHighlights = OccurrenceHighlights()
  let insertPresentation = EditorInsertPresentation()
  lazy var objectHover=EditorObjectHover(document:document,editor:editor)
  let commentHint=StudioToolbarButton(symbol:"text.bubble",label:"Seçili satırları yorum yap / kaldır",title:"",width:28)
  private let ruler: LineNumbers
  private var rulerWidth:NSLayoutConstraint?
  let document: QueryDocument
  var edited: (() -> Void)?
  var position: ((Int, Int) -> Void)?
  private var measuredSource:String?
  private var measuredDisplaySource:String?
  private var measuredFont:NSFont?
  private var longestLineWidth:CGFloat=0
  private var sourceLineCount=1
  private var displayLineCount=1
  private var lastClipOrigin=NSPoint.zero
  private var occurrenceTask: Task<Void,Never>?
  private let parameterPopover=NSPopover()
  private var parameterTask:Task<Void,Never>?
  private var parameterGeneration=UUID()
  private var parameterCache:[String:(Date,[RoutineParameter])]=[:]
  private(set) var parameterCall:SQLRoutineCall?
  private(set) var parameterValues:[RoutineParameter]=[]
  private(set) var parameterStatus:String?
  var parameterShown:Bool {parameterPopover.isShown}
  private lazy var completion = EditorCompletionController(document:document,editor:editor)
  var completionSize:NSSize {completion.contentSize}
  var completionShown:Bool {completion.isShown}
  private var cachedTokens: [Lexeme]?
  private var cachedTokenSource = ""
  private var unusedVariableSource = ""
  private var unusedVariableRanges: [NSRange] = []
  private var undeclaredVariableRanges:[NSRange]=[]
  private var highlightedSource: String?
  private var highlightedDiagnostics: [SQLIntelligence.Diagnostic] = []
  private(set) var diagnostics: [SQLIntelligence.Diagnostic] = []
  private var suppressNextPopup = false
  private var initializedText = false
  private(set) var regions: [SQLFolding.Region] = []
  private var folded: [SQLFolding.Region] = []
  private var projection: SQLFolding.Projection?
  private var changingPresentation = false
  private var formattingTask: Task<Void,Never>?
  private var textRevision = UUID()
  var executionRequest=UUID()
  var executionChoiceFixture: (([NSRange]) -> Int?)?
  func previewExecutionRange(_ range:NSRange?) {
    guard let range else {occurrenceHighlights.executionRange=nil;return}
    let length=(document.sql as NSString).length
    guard range.location != NSNotFound,range.location<=length,range.length<=length-range.location else {occurrenceHighlights.executionRange=nil;return}
    let start=projection?.displayOffset(range.location) ?? range.location
    let end=projection?.displayOffset(NSMaxRange(range)) ?? NSMaxRange(range)
    occurrenceHighlights.executionRange=NSRange(location:start,length:max(0,end-start))
    editor.scrollRangeToVisible(NSRange(location:start,length:0))
    occurrenceHighlights.needsDisplay=true
  }
  func closeExecutionAssistance() {completion.close();parameterPopover.close();insertPresentation.hidePreview()}
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
    editor.configureFinder(in:findContainer)
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
    editor.requestFormat = { [weak self] in self?.formatSQL(options: SQLEditorPreferences.formatting()) }
    editor.requestParameterInfo = { [weak self] in self?.scheduleParameters(manual:true) }
    editor.jumpToMatchingPair = { [weak self] in self?.jumpToMatchingPair() }
    editor.revealInExplorer = { [weak document] parts in guard let document else {return};document.revealInExplorer?(parts,document.server,document.database) }
    editor.navigateDefinition = { [weak self] in self?.navigateDefinition() }
    editor.mouseSelectionEnded = { [weak self] in self?.occurrenceTask?.cancel();self?.lastClipOrigin=self?.scroll.contentView.bounds.origin ?? .zero;self?.insertPresentation.requestPreview();self?.updateOccurrences();self?.updateCommentHint() }
    editor.unfoldSelection = { [weak self] range in
      guard let self,let marker=collapsedMarkers.first(where:{NSIntersectionRange($0.range,range).length > 0}) else {return false}
      toggleFold(marker.region);return true
    }
    editor.run = { [weak document] in document?.execute() }
    editor.runStatement = { [weak self] in self?.requestStatementExecution() }
    editor.canRunStatement = { [weak document] in document?.canExecute == true }
    editor.setAccessibilityIdentifier("sqlEditor")
    scroll.documentView = editor
    insertPresentation.didResolve = { [weak self] in self?.updateOccurrences() }
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
    surface.addSubview(ruler); surface.addSubview(findContainer)
    surface.addSubview(commentHint)
    commentHint.isHidden=true;commentHint.target=editor;commentHint.action=#selector(SQLTextView.toggleSQLComment(_:))
    commentHint.setAccessibilityIdentifier("sqlSelectionComment")
    ruler.translatesAutoresizingMaskIntoConstraints = false; findContainer.translatesAutoresizingMaskIntoConstraints = false
    rulerTop=ruler.topAnchor.constraint(equalTo:surface.topAnchor)
    findContainer.heightChanged = { [weak self] height in self?.rulerTop?.constant=height }
    rulerWidth=ruler.widthAnchor.constraint(equalToConstant:44)
    NSLayoutConstraint.activate([
      ruler.leadingAnchor.constraint(equalTo:surface.leadingAnchor), rulerTop!,
      ruler.bottomAnchor.constraint(equalTo:surface.bottomAnchor), rulerWidth!,
      findContainer.leadingAnchor.constraint(equalTo:ruler.trailingAnchor), findContainer.trailingAnchor.constraint(equalTo:surface.trailingAnchor),
      findContainer.topAnchor.constraint(equalTo:surface.topAnchor), findContainer.bottomAnchor.constraint(equalTo:surface.bottomAnchor)
    ])
    ruler.lineNumber = { [weak self] in self?.sourceLineNumber($0) ?? 1 }
    ruler.sourceText = { [weak self] in self?.document.sql ?? "" }
    ruler.sourceOffset = { [weak self] in self?.projection?.sourceOffset($0) ?? $0 }
    ruler.foldRegions = { [weak self] in self?.regions ?? [] }
    ruler.collapsed = { [weak self] region in self?.folded.contains(region) == true }
    ruler.toggle = { [weak self] in self?.toggleFold($0) }
    ruler.selectLine = { [weak self] in self?.selectSourceLine($0) }
    completion.isProjected = { [weak self] in self?.projection != nil }
    completion.willShow = { [weak self] in self?.insertPresentation.hidePreview(); self?.dismissParameterHelp() }
    completion.parametersShown = { [weak self] in self?.parameterPopover.isShown ?? false }
    completion.anchor = { [weak self] in self?.suggestionAnchor() }
    completion.willAccept = { [weak self] in self?.suppressNextPopup = true }
    completion.publish = { [weak self] analysis,regions,source,validate in
      guard let self else {return}
      self.regions=regions;ruler.needsDisplay=true
      diagnostics=validate ? analysis.diagnostics:[]
      cachedTokens=analysis.tokens;cachedTokenSource=source
      highlight()
    }
    editor.requestSuggestions = { [weak self] in self?.scheduleIntelligence(manual:true) }
    editor.hoverMoved = { [weak self] point in guard let self else {return};if completionShown || parameterShown || insertPresentation.isShown {objectHover.hide()} else {objectHover.move(point)} }
    editor.dismissSuggestions = { [weak self] in self?.objectHover.hide(); self?.completion.close();self?.dismissParameterHelp();self?.insertPresentation.dismissPreview() }
    editor.suggestionKey = { [weak self] in self?.completion.handleSuggestionKey($0) ?? false }
    NotificationCenter.default.addObserver(self,selector:#selector(catalogChanged),name:.init("sqlCatalogChanged"),object:document)
    NotificationCenter.default.addObserver(self,selector:#selector(catalogChanged),name:.init("sqlEditorPreferencesChanged"),object:nil)
    editor.toggleOutline = { [weak self] in self?.toggleCurrentFold() }
    editor.expandOutline = { [weak self] in self?.expandAll() }
    editor.batchEditingEnded = { [weak self] in
      guard let self else {return}
      textDidChange(Notification(name:NSText.didChangeNotification,object:editor))
      textViewDidChangeSelection(Notification(name:NSTextView.didChangeSelectionNotification,object:editor))
    }
    editor.dismissCaretSuggestions = { [weak self] in
      self?.objectHover.hide();self?.completion.close();self?.insertPresentation.dismissPreview()
    }
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
    NotificationCenter.default.addObserver(self,selector:#selector(updateCommentHint),name:GridShortcuts.changed,object:nil)
    NotificationCenter.default.addObserver(self,selector:#selector(hideCommentHint),name:NSWindow.didResignKeyNotification,object:nil)
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
  private var historyBatchActive=false
  @objc private func willUndoChanged(_ notification: Notification) {
    guard let manager = notification.object as? UndoManager, manager === editor.undoManager else { return }
    editor.finishUndoInput()
    editor.sqlFinder.noteClientStringWillChange()
    expandAll()
    guard !historyBatchActive else {return}
    historyBatchActive=true
    editor.beginBatchEdit()
  }
  @objc private func undoChanged(_ notification: Notification) {
    guard let manager = notification.object as? UndoManager, manager === editor.undoManager else {
      return
    }
    // Native history restores every row separately. Publish and paint only once,
    // after the complete group; this also covers restoration without didChangeText.
    if historyBatchActive {
      historyBatchActive=false
      editor.endBatchEdit()
    } else if document.sql != editor.string {
      textDidChange(Notification(name:NSText.didChangeNotification,object:editor))
    }
  }
  @objc func applyTheme() {
    insertPresentation.refreshTheme()
    highlightedSource = nil
    editor.backgroundColor = StudioTheme.editorCanvas
    editor.textColor = StudioTheme.editorText
    editor.insertionPointColor = StudioTheme.editorText
    editor.selectedTextAttributes = [
      .backgroundColor: StudioTheme.editorSelection,
    ]
    editor.typingAttributes[.font] = StudioTheme.codeFont
    editor.typingAttributes[.foregroundColor] = StudioTheme.editorText
    scroll.backgroundColor = StudioTheme.editorCanvas
    highlight()
    ruler.needsDisplay = true
  }
  func resizeToViewport() {
    let font=editor.font ?? StudioTheme.codeFont
    var geometryChanged=false
    if measuredSource != document.sql || measuredFont != font {
      measuredSource=document.sql;measuredFont=font;geometryChanged=true
      sourceLineCount=document.sql.utf16.reduce(1) {$1 == 10 ? $0+1:$0}
      let metrics:[NSAttributedString.Key:Any]=[.font:font,.paragraphStyle:Self.codeParagraph()]
      longestLineWidth=document.sql.components(separatedBy:"\n").map {($0 as NSString).size(withAttributes:metrics).width}.max() ?? 0
    }
    if measuredDisplaySource != editor.string {
      measuredDisplaySource=editor.string;geometryChanged=true
      displayLineCount=editor.string.utf16.reduce(1) {$1 == 10 ? $0+1:$0}
    }
    let gutterWidth=LineNumbers.width(lineCount:sourceLineCount,font:StudioTheme.codeFont)
    if rulerWidth?.constant != gutterWidth {
      rulerWidth?.constant=gutterWidth;ruler.ruleThickness=gutterWidth
      surface.layoutSubtreeIfNeeded()
    }
    scroll.tile()
    let textWidth = ceil(longestLineWidth) + editor.textContainerInset.width * 2 + 10
    let horizontal = textWidth > scroll.contentView.bounds.width + 1
    (scroll.contentView as? SQLClipView)?.allowsHorizontalMovement = horizontal
    scroll.hasHorizontalScroller = horizontal
    let width = max(scroll.contentView.bounds.width,textWidth)
    let containerWidth = max(1,width - editor.textContainerInset.width * 2)
    if editor.textContainer?.containerSize.width != containerWidth {
      geometryChanged=true
      editor.textContainer?.containerSize = NSSize(width:containerWidth,height:CGFloat.greatestFiniteMagnitude)
    }
    // Resolve bounded documents before using TextKit's height: its lazy estimates
    // change as paragraphs enter the viewport. Font leading can exceed the configured
    // paragraph height, so counting lines is not an accurate scroll geometry.
    if geometryChanged,editor.string.utf16.count <= 250_000,let content=editor.textContentStorage {
      editor.textLayoutManager?.ensureLayout(for:content.documentRange)
    }
    let measuredHeight=editor.textLayoutManager?.usageBoundsForTextContainer.maxY ?? 0
    let textHeight=max(measuredHeight,CGFloat(displayLineCount)*18)+editor.textContainerInset.height*2
    // Trailing space lets the final fold header stay under the pointer near EOF.
    let height=max(scroll.contentView.bounds.height,textHeight+scroll.contentView.bounds.height)
    if editor.frame.size != NSSize(width: width, height: height) {
      editor.setFrameSize(NSSize(width: width, height: height))
      editor.needsDisplay = true
    }
    // Populate newly exposed TextKit fragments within this resize transaction.
    editor.layoutSubtreeIfNeeded()
    editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
    if width <= scroll.contentView.bounds.width + 0.5 && scroll.contentView.bounds.origin.x != 0 {
      scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
      scroll.reflectScrolledClipView(scroll.contentView)
    }
    occurrenceHighlights.frame=scroll.contentView.bounds
    occurrenceHighlights.needsDisplay=true
  }
  func formatSQL(options: SQLFormattingOptions) {
    guard editor.isEditable, !editor.hasMarkedText() else { return }
    let selection = editor.selectedRange()
    let source = projection?.source ?? editor.string
    let range = projection?.sourceRange(selection) ?? selection
    let target = range.length > 0 ? range : NSRange(location:0,length:source.utf16.count)
    let input = (source as NSString).substring(with:target)
    let visibleOrigin=scroll.contentView.bounds.origin
    let oldCaretScreen=editor.firstRect(forCharacterRange:NSRange(location:selection.location,length:0),actualRange:nil)
    let caretViewportY=editor.window.map {editor.convert($0.convertFromScreen(oldCaretScreen),from:nil).minY-visibleOrigin.y}
    let revision = textRevision
    formattingTask?.cancel()
    func apply(_ text: String) {
      guard text != input, textRevision == revision, (projection?.source ?? editor.string) == source,
        editor.selectedRange() == selection, !editor.hasMarkedText() else { return }
      let candidate = (source as NSString).replacingCharacters(in:target,with:text)
      guard SQLFormatter.preservesSQLTokens(source,formatted:candidate) else { return }
      expandAll(); highlightedSource = nil
      editor.finishUndoInput()
      editor.insertText(text,replacementRange:target)
      editor.finishUndoInput()
      let newSelection: NSRange
      if range.length > 0 {newSelection=NSRange(location:target.location,length:text.utf16.count)}
      else {newSelection=NSRange(location:SQLFormatter.correspondingOffset(range.location,in:source,formatted:candidate),length:0)}
      editor.setSelectedRange(newSelection)
      highlight(); resizeToViewport()
      editor.scrollRangeToVisible(NSRange(location:newSelection.location,length:0))
      let screen=editor.firstRect(forCharacterRange:NSRange(location:newSelection.location,length:0),actualRange:nil)
      if let window=editor.window,let caretViewportY,screen.height>0 {
        let local=editor.convert(window.convertFromScreen(screen),from:nil)
        scroll.contentView.scroll(to:NSPoint(x:visibleOrigin.x,y:max(0,local.minY-caretViewportY)))
        scroll.reflectScrolledClipView(scroll.contentView)
      }
      document.selectedRange=newSelection
      editor.updateInsertionPointStateAndRestartTimer(true)
    }
    if input.utf16.count <= 50000 { apply(TSQL.format(input,options:options)) }
    else {
      formattingTask = Task { [weak self] in
        let worker = Task.detached(priority:.userInitiated) { TSQL.format(input,options:options) }
        let formatted = await worker.value
        guard !Task.isCancelled, self != nil else {return}
        apply(formatted)
      }
    }
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
    objectHover.hide()
    let clip = scroll.contentView
    if clip.bounds.origin != lastClipOrigin {insertPresentation.hidePreview()}
    lastClipOrigin=clip.bounds.origin
    occurrenceHighlights.frame=clip.bounds
    occurrenceHighlights.needsDisplay=true
    if editor.frame.width <= clip.bounds.width + 1 && abs(clip.bounds.origin.x) > 0.5 {
      clip.scroll(to:NSPoint(x:0,y:clip.bounds.origin.y))
      scroll.reflectScrolledClipView(clip)
    }
    ruler.needsDisplay = true
    updateCommentHint()
  }
  @objc private func hideCommentHint() {commentHint.isHidden=true}
  @objc func updateCommentHint() {
    let selection=editor.selectedRange(),source=projection?.source ?? editor.string
    guard !changingPresentation,editor.isEditable,!editor.hasMarkedText(),!editor.trackingMouseSelection,
      editor.window?.isKeyWindow == true,editor.window?.firstResponder === editor,selection.length>0,
      editor.selectedRanges.count == 1,source.utf16.count <= 250_000, !completionShown, !parameterShown,
      let layout=editor.textLayoutManager else {hideCommentHint();return}
    // A word selection is for navigation/copying. Offer the compact action only
    // for complete physical lines or a selection spanning more than one line.
    let selected = (editor.string as NSString).substring(with:selection)
    let line = (editor.string as NSString).lineRange(for:selection)
    let ns = editor.string as NSString
    let remainder = ns.substring(with:NSRange(location:line.location,length:selection.location-line.location))
      + ns.substring(with:NSRange(location:NSMaxRange(selection),length:NSMaxRange(line)-NSMaxRange(selection)))
    guard !selected.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
      selected.contains("\n") || selected.contains("\r") || remainder.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {hideCommentHint();return}
    func caretRect(_ offset:Int)->NSRect? {
      guard let range=textRange(NSRange(location:offset,length:0)) else {return nil}
      var result:NSRect?
      layout.enumerateTextSegments(in:range,type:.selection,options:[]) {_,rect,_,_ in
        result=self.surface.convert(rect.offsetBy(dx:self.editor.textContainerOrigin.x,dy:self.editor.textContainerOrigin.y),from:self.editor);return false
      }
      return result
    }
    let viewport=surface.convert(scroll.contentView.bounds,from:scroll.contentView).insetBy(dx:6,dy:4)
    let start=caretRect(selection.location),end=caretRect(NSMaxRange(selection))
    let anchor:NSRect,y:CGFloat
    if let start,start.insetBy(dx:-1,dy:0).intersects(viewport),start.maxY+30 <= viewport.maxY {
      anchor=start;y=start.maxY+4
    } else if let end,end.insetBy(dx:-1,dy:0).intersects(viewport),end.minY-30 >= viewport.minY {
      anchor=end;y=end.minY-30
    } else {hideCommentHint();return}
    let sourceRange=projection?.sourceRange(selection) ?? selection
    let remove=SQLComments.isCommented(source,selection:sourceRange)
    let label=(remove ? "Yorumu Kaldır":"Yorum Yap")+"  "+GridShortcuts.binding(.comment).label
    commentHint.title="";commentHint.toolTip=label+" · Seçimin kapsadığı SQL satırlarına uygulanır."
    commentHint.setAccessibilityLabel(label);commentHint.refreshStyle()
    commentHint.frame=NSRect(x:max(viewport.minX,min(anchor.minX,viewport.maxX-28)),y:y,width:28,height:26)
    commentHint.isHidden=false
  }
  func setText() {
    // A host refresh is not a request to unfold or replace an unchanged document.
    if initializedText && document.sql == (projection?.source ?? editor.string) { return }
    let selection=document.selectedRange
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
    let length=(editor.string as NSString).length
    let start=min(max(0,selection.location),length)
    editor.setSelectedRange(NSRange(location:start,length:min(max(0,selection.length),length-start)))
    ruler.needsDisplay = true
    updateOccurrences()
    scheduleIntelligence()
  }
  func textDidChange(_ notification: Notification) {
    guard !editor.isBatchEditing else {return}
    objectHover.hide()
    textRevision = UUID();executionRequest=UUID();previewExecutionRange(nil)
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
    completion.close()
    scheduleParameters()
    scheduleIntelligence(allowPopup:!suppressNextPopup)
    suppressNextPopup = false
    scheduleOccurrences()
  }
  private func scheduleOccurrences() {
    occurrenceTask?.cancel()
    let range = editor.selectedRange(), selectedSource = editor.string
    occurrenceTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(90)) } catch { return }
      guard let self, !changingPresentation, editor.string == selectedSource, editor.selectedRange() == range else { return }
      updateOccurrences()
    }
  }
  func textViewDidChangeSelection(_ notification: Notification) {
    objectHover.hide()
    guard !editor.isBatchEditing,!paintingOccurrences, !changingPresentation else {return}
    let range = editor.selectedRange()
    updateCommentHint()
    scheduleOccurrences()
    scheduleParameters()
    document.selectedRange = projection?.sourceRange(range) ?? range
    let prefix = (document.sql as NSString).substring(
      to: min(document.selectedRange.location, (document.sql as NSString).length))
    position?(
      prefix.filter { $0 == "\n" }.count + 1,
      (prefix.split(separator: "\n", omittingEmptySubsequences: false).last?.utf16.count ?? 0) + 1)
    if !changingPresentation && editor.string == completion.analysisSource && range.location != completion.analysisCaret { completion.close(); scheduleIntelligence(allowPopup:false) }
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
    occurrenceHighlights.blockGuides.clear()
    occurrenceHighlights.insertRanges=[];insertPresentation.clear()
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
    occurrenceHighlights.blockRanges = occurrenceHighlights.blockGuides.update(source: document.sql, selection: sourceRange, projection: projection)
    occurrenceHighlights.insertRanges=insertPresentation.update(source:document.sql,selection:sourceRange,projection:projection,editor:editor,allowPreview:!completionShown && !parameterShown)
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
    if manual {completion.cancel()}
    parameterTask?.cancel()
    let generation=UUID();parameterGeneration=generation
    guard projection == nil,editor.selectedRange().length == 0,!editor.hasMarkedText(),editor.window == nil || editor.window?.firstResponder === editor else {parameterPopover.close();return}
    let source=editor.string,caret=editor.selectedRange().location,db=document.database,server=document.server,serverGeneration=document.server.generation
    let catalog=document.catalogDatabase == db ? document.intelligenceCatalog:nil
    let delay = !manual && !parameterShown
    parameterTask=Task { [weak self] in
      do {
        if delay {try await Task.sleep(for:.milliseconds(180))}
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
    guard !completionShown else {parameterPopover.close();return}
    insertPresentation.hidePreview()
    let height=parameterStatus == nil && !parameterValues.isEmpty ? CGFloat(min(6,parameterValues.count))*28+62:104
    let content=SQLParameterHelp(name:call.symbol.schema+"."+call.symbol.name,parameters:parameterValues,active:call.activeIndex(in:parameterValues),status:parameterStatus)
    StudioPopover.show(parameterPopover,content:content,from:editor,rect:anchor,size:NSSize(width:480,height:height),updatingExisting:true,behavior:.semitransient)
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
    let offset=projection?.sourceOffset(editor.selectedRange().location) ?? editor.selectedRange().location
    guard let parts=DefinitionReference.parts(in:document.sql,at:offset) else {return}
    if !document.server.online {document.openDefinitionNamed?(parts);return}
    if let catalog=document.intelligenceCatalog,document.catalogDatabase == document.database,let symbol=catalog.resolve(parts) {document.openDefinition?(symbol)}
  }
  func insertSQLAtCaret(_ text:String) throws {
    guard document.offlinePreview == nil,!document.definitionLoading,document.definitionError == nil,!editor.hasMarkedText() else {throw SQLFailure("SQL’e dönün ve metin girişini tamamlayın.")}
    if projection != nil {expandAll()}
    editor.finishUndoInput()
    editor.insertText(text,replacementRange:editor.selectedRange())
    editor.finishUndoInput()
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
    completion.cancel();occurrenceTask?.cancel();clearOccurrences();highlightedSource=nil; completion.close(); diagnostics = []
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
    if !editor.isBatchEditing {clearOccurrences()}
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
    let values = completion.analysisSource == textView.string ? completion.currentAnalysis?.suggestions.map(\.text) ?? [] : []
    index?.pointee = values.isEmpty ? -1 : 0
    return values
  }
  private(set) var catalogAnalysisPending=false
  @objc private func catalogChanged() {
    dismissParameterHelp();completion.cancel()
    catalogAnalysisPending=true
    refreshCatalogAnalysisIfNeeded()
  }
  func refreshCatalogAnalysisIfNeeded() {
    guard catalogAnalysisPending,editor.window != nil,!editor.isHiddenOrHasHiddenAncestor else {return}
    catalogAnalysisPending=false
    scheduleParameters();scheduleIntelligence(allowPopup:false)
  }
  func scheduleIntelligence(manual:Bool=false,allowPopup:Bool=true) {
    completion.scheduleIntelligence(manual:manual,allowPopup:allowPopup)
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
      let variables=TSQL.variableAnalysis(completeSource)
      unusedVariableRanges = variables.unused
      undeclaredVariableRanges = variables.undeclared
    }
    func visibleLocations(_ ranges:[NSRange])->Set<Int> {Set(ranges.compactMap { range -> Int? in
      if let projection {
        guard !projection.regions.contains(where:{ NSIntersectionRange($0.hidden,range).length > 0 }) else { return nil }
        return projection.displayOffset(range.location)
      }
      return range.location
    })}
    let unused=visibleLocations(unusedVariableRanges),undeclared=visibleLocations(undeclaredVariableRanges)
    var changes: [(NSRange,NSColor)] = []
    func collect(_ range: NSRange, color: NSColor) {
      guard range.length > 0 else { return }
      storage.enumerateAttribute(.foregroundColor,in:range) { value, run, _ in
        if (value as? NSColor) != color { changes.append((run,color)) }
      }
    }
    if tokens.isEmpty { collect(NSRange(location:0,length:storage.length),color:StudioTheme.editorText) }
    else { for token in tokens { collect(token.range,color:SQLSourceHighlighting.foreground(token,unused:unused.contains(token.range.location),undeclared:undeclared.contains(token.range.location))) } }
    let selection = editor.selectedRanges
    storage.beginEditing()
    for (range,color) in changes { storage.addAttribute(.foregroundColor,value:color,range:range) }
    let full = NSRange(location:0,length:storage.length)
    for key in [NSAttributedString.Key.underlineStyle,.underlineColor,.toolTip] {
      var ranges: [NSRange] = []
      storage.enumerateAttribute(key,in:full) { value, range, _ in if value != nil { ranges.append(range) } }
      for range in ranges { storage.removeAttribute(key,range:range) }
    }
    for token in tokens where undeclared.contains(token.range.location) {
      storage.addAttribute(.toolTip,value:"Bu değişken bu SQL batch’inde tanımlanmamış: "+token.text,range:token.range)
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
