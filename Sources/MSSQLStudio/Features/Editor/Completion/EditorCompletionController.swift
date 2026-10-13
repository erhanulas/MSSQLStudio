import AppKit
import SwiftUI
import SQLServerKit

private final class SQLSuggestionKeyMonitor: @unchecked Sendable {
  let token:Any
  init(_ token:Any) {self.token=token}
  deinit {NSEvent.removeMonitor(token)}
}
/// Owns completion analysis, cancellation/generation and popup/key-monitor lifetime.
/// The editor owns text/selection/undo, folds and syntax presentation.
@MainActor final class EditorCompletionController: NSObject, NSPopoverDelegate {
  private let document:QueryDocument
  private let editor:SQLTextView
  private var intelligenceTask:Task<Void,Never>?
  private var intelligenceGeneration=UUID()
  private let suggestionList=SQLSuggestionList()
  private let suggestionPopover=NSPopover()
  private var suggestionKeyMonitor:SQLSuggestionKeyMonitor?
  private(set) var currentAnalysis:SQLIntelligence.Analysis?
  private(set) var analysisSource=""
  private(set) var analysisCaret = -1
  var isProjected:()->Bool = {false}
  var parametersShown:()->Bool = {false}
  var anchor:(()->NSRect?)?
  var publish:((SQLIntelligence.Analysis,[SQLFolding.Region],String,Bool)->Void)?
  var willShow:(()->Void)?
  var willAccept:(()->Void)?
  var contentSize:NSSize {suggestionPopover.contentSize}
  var isShown:Bool {suggestionPopover.isShown}
  init(document:QueryDocument,editor:SQLTextView) {
    self.document=document;self.editor=editor
    super.init()
    suggestionPopover.contentViewController=suggestionList
    suggestionPopover.delegate=self
    suggestionPopover.animates=false;suggestionPopover.behavior = .semitransient
    suggestionList.accept = { [weak self] in self?.acceptSuggestion($0) }
  }
  deinit {intelligenceTask?.cancel()}
  func close() {suggestionPopover.close()}
  func cancel() {intelligenceGeneration=UUID();intelligenceTask?.cancel();close()}
  func scheduleIntelligence(manual: Bool = false, allowPopup: Bool = true) {
    intelligenceTask?.cancel()
    let generation = UUID(); intelligenceGeneration = generation
    guard !isProjected() else { return }
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
        currentAnalysis = analysis; analysisSource = source; analysisCaret = caret
        publish?(analysis,regions,source,validate)
        let prefixLength = caret-analysis.replacement.location
        let dot = analysis.replacement.location > 0 && (source as NSString).substring(with:NSRange(location:analysis.replacement.location-1,length:1)) == "."
        if !parametersShown(),(manual || automatic && allowPopup && (analysis.objectCompletion || analysis.procedureCompletion || analysis.variableCompletion || prefixLength >= 2 || dot)), !analysis.suggestions.isEmpty, let window = editor.window, window.firstResponder === editor {
          guard let anchor = anchor?(), let host = window.contentView else { return }
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
          willShow?()
          suggestionPopover.show(relativeTo:hostAnchor,of:host,preferredEdge:edge)
          window.makeFirstResponder(editor)
          installSuggestionKeys()
        } else { suggestionPopover.close() }
      } catch { /* Superseded edits never publish stale diagnostics or suggestions. */ }
    }
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
  func handleSuggestionKey(_ event: NSEvent) -> Bool {
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
    guard let analysis = currentAnalysis, analysisSource == editor.string, analysis.suggestions.indices.contains(index), !isProjected() else { suggestionPopover.close(); return }
    suggestionPopover.close(); willAccept?()
    editor.window?.makeFirstResponder(editor)
    editor.finishUndoInput()
    let suggestion=analysis.suggestions[index],source=editor.string
    editor.insertText(suggestion.text,replacementRange:analysis.replacement)
    if editor.string != source,let offset=suggestion.caretOffset,offset>=0,offset<=suggestion.text.utf16.count {
      editor.setSelectedRange(NSRange(location:analysis.replacement.location+offset,length:0))
    }
    editor.finishUndoInput()
  }
}
