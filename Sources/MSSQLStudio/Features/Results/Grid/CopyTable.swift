import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class CopyTable: NSTableView {
  weak var rowGutter: ResultRowGutter?
  var dataReloaded: (() -> Void)?
  weak var selectionOwner: CopyTable?
  var selectionColumnOrder: (() -> [Int])?
  var navigateCell: ((Int) -> Void)?
  var dragSelection: ((NSEvent) -> Bool)?
  private var owner: CopyTable { selectionOwner ?? self }
  func canonicalPosition(_ position:Int) -> Int? {
    guard tableColumns.indices.contains(position) else { return nil }
    guard let selectionOwner else {return position}
    let canonical=selectionOwner.column(withIdentifier:tableColumns[position].identifier)
    return canonical >= 0 ? canonical:nil
  }
  override func reloadData() { super.reloadData(); rowGutter?.needsDisplay=true; dataReloaded?() }
  private func cellRange(_ from:Int,_ to:Int) -> IndexSet {
    guard from != 0, to != 0 else { return IndexSet() }
    let order=selectionColumnOrder?() ?? Array(1..<max(1,numberOfColumns))
    guard let start=order.firstIndex(of:from), let end=order.firstIndex(of:to) else { return IndexSet(integer:to) }
    return IndexSet(order[min(start,end)...max(start,end)])
  }
  func selectCell(row:Int,column:Int,extending:Bool=false) {
    guard row >= 0, row < numberOfRows else { return }
    if extending, let anchor {
      selectRowIndexes(IndexSet(integersIn:min(row,anchor.row)...max(row,anchor.row)),byExtendingSelection:false)
      cellColumns=cellRange(anchor.column,column)
    } else {
      anchor=(row,column); selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
      cellColumns=column == 0 ? IndexSet():IndexSet(integer:column)
    }
    needsDisplay=true
  }
  func remapSelectionAfterColumnMove(from:Int,to:Int) {
    func moved(_ position:Int) -> Int {
      if position == from {return to}
      if from < to && position > from && position <= to {return position-1}
      if from > to && position >= to && position < from {return position+1}
      return position
    }
    cellColumns=IndexSet(cellColumns.map(moved))
    if let anchor {self.anchor=(anchor.row,moved(anchor.column))}
  }
  @objc func selectAllCells(_ sender:Any?=nil) {
    if let window,!window.makeFirstResponder(self) {return}
    owner.cellColumns=IndexSet()
    owner.selectAll(sender)
    owner.cellSelectionChanged?()
  }
  func selectGutterRow(_ row:Int, extending:Bool=false, dragging:Bool=false) {
    guard row >= 0, row < numberOfRows else { return }
    window?.makeFirstResponder(self)
    if (extending || dragging), let anchor {
      selectRowIndexes(IndexSet(integersIn:min(row,anchor.row)...max(row,anchor.row)),byExtendingSelection:false)
    } else {
      anchor=(row,0); selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
    }
    cellColumns=IndexSet(); needsDisplay=true
  }
  func gutterContextMenu(with event:NSEvent,row:Int) {
    guard row >= 0, row < numberOfRows else { return }
    if !selectedRowIndexes.contains(row) || !cellColumns.isEmpty { selectGutterRow(row) }
    showSelectionMenu(with:event)
  }
  var editCell: ((Int, Int) -> Void)?
  var draftChanged: (() -> Void)?
  var validateDraft: ((Int, Int, String) -> Bool)?
  private var resultFieldEditor: ResultFieldEditor?
  func editingFieldEditor(formatter: ResultCellFormatter?) -> NSTextView {
    if resultFieldEditor == nil {
      let editor = ResultFieldEditor(usingTextLayoutManager: true)
      editor.isFieldEditor = true; editor.isRichText = false; editor.allowsUndo = true
      editor.table = self
      resultFieldEditor = editor
    }
    resultFieldEditor!.valueFormatter = formatter
    return resultFieldEditor!
  }
  override func abortEditing() -> Bool {
    resultFieldEditor?.allowsInvalidExit = true
    defer { resultFieldEditor?.allowsInvalidExit = false }
    return super.abortEditing()
  }
  override func textShouldEndEditing(_ textObject: NSText) -> Bool {
    guard validateDraft?(editedRow, editedColumn, textObject.string) != false else { return false }
    return super.textShouldEndEditing(textObject)
  }
  override func textDidChange(_ notification: Notification) {
    super.textDidChange(notification)
    draftChanged?()
  }
  override func textDidEndEditing(_ notification: Notification) {
    super.textDidEndEditing(notification)
    draftChanged?()
  }
  override func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      _ = abortEditing()
      window?.makeFirstResponder(self)
      draftChanged?()
      return true
    }
    return super.textView(textView, doCommandBy: commandSelector)
  }
  var rowActions: (() -> [NSMenuItem])?
  var columnShortcutItems:(()->[NSMenuItem])?
  var copyRows: (() -> Void)?
  var copyHeaders: (() -> Void)?
  var searchColumns: (() -> Void)?
  var cellSelectionChanged: (() -> Void)?
  private(set) var cellColumns = IndexSet() {
    didSet { if cellColumns != oldValue { needsDisplay = true; cellSelectionChanged?() } }
  }
  override func drawBackground(inClipRect clip: NSRect) {
    StudioTheme.resultCanvas.setFill(); clip.fill()
    let visible = rows(in: clip)
    guard visible.location != NSNotFound, visible.length > 0 else { return }
    StudioTheme.resultStripe.setFill()
    for row in visible.location..<NSMaxRange(visible) where !row.isMultiple(of: 2) {
      NSIntersectionRect(rect(ofRow: row), clip).fill()
    }
  }
  override func highlightSelection(inClipRect clip: NSRect) {
    StudioTheme.selection.setFill()
    let visible=rows(in:clip)
    guard visible.location != NSNotFound, visible.length>0 else {return}
    for row in selectedRowIndexes.intersection(IndexSet(integersIn:visible.location..<NSMaxRange(visible))) {
      let rowRect=rect(ofRow:row)
      if owner.cellColumns.isEmpty {NSIntersectionRect(rowRect,clip).fill()}
      else {
        for column in columnIndexes(in:clip) where canonicalPosition(column).map({owner.cellColumns.contains($0)}) == true {
          NSIntersectionRect(NSIntersectionRect(rect(ofColumn:column),rowRect),clip).fill()
        }
      }
    }
  }
  private var anchor: (row: Int, column: Int)?
  override func mouseDown(with event:NSEvent) {
    let point=convert(event.locationInWindow,from:nil), row=row(at:convert(event.locationInWindow,from:nil))
    guard row >= 0, let column=canonicalPosition(column(at:point)) else {super.mouseDown(with:event);return}
    window?.makeFirstResponder(self)
    owner.selectCell(row:row,column:column,extending:event.modifierFlags.contains(.shift))
    if event.clickCount == 2 {editCell?(row,self.column(at:point))}
  }
  override func mouseDragged(with event:NSEvent) {
    if dragSelection?(event) == true {return}
    guard owner.anchor != nil else {return}
    _ = autoscroll(with:event)
    let point=convert(event.locationInWindow,from:nil)
    guard let column=canonicalPosition(column(at:point)) else {return}
    owner.selectCell(row:row(at:point),column:column,extending:true)
  }
  override func rightMouseDown(with event:NSEvent) {
    let point=convert(event.locationInWindow,from:nil), row=row(at:convert(event.locationInWindow,from:nil))
    guard row >= 0, let column=canonicalPosition(column(at:point)) else {return}
    if !owner.selectedRowIndexes.contains(row) || (!owner.cellColumns.isEmpty && !owner.cellColumns.contains(column)) {owner.selectCell(row:row,column:column)}
    showSelectionMenu(with:event)
  }
  private func showSelectionMenu(with event:NSEvent) {
    NSMenu.popUpContextMenu(makeSelectionMenu(),with:event,for:self)
  }
  private func makeShortcutMenu()->NSMenu {
    let menu=makeSelectionMenu()
    for item in columnShortcutItems?() ?? [] {menu.addItem(item)}
    return menu
  }
  func makeSelectionMenu()->NSMenu {
    let menu = StudioMenu(); menu.autoenablesItems = false
    let item = menu.addItem(withTitle: "Kopyala", action: #selector(copySelection), keyEquivalent: "c")
    item.target = self
    let headers = menu.addItem(withTitle: "Başlıklarla Kopyala", action: #selector(copyWithHeaders), keyEquivalent: GridShortcuts.binding(.headers).key)
    headers.keyEquivalentModifierMask = GridShortcuts.headersModifiers
    headers.target = self
    if let items = rowActions?(), !items.isEmpty { menu.addItem(.separator()); for item in items { menu.addItem(item) } }
    return menu
  }
  @objc func copyWithHeaders() { copyHeaders?() }
  @objc func copySelection() { copyRows?() }
  @objc func copy(_ sender: Any?) { copyRows?() }
  override func performKeyEquivalent(with event:NSEvent)->Bool {
    if window?.firstResponder === self,StudioCommandCatalog.dispatch(event,to:self,menu:{makeShortcutMenu()}) {return true}
    if window?.firstResponder === self,GridShortcuts.matches(.gridCopyQuery,event) {return true}
    return super.performKeyEquivalent(with:event)
  }
  override func keyDown(with event: NSEvent) {
    if StudioCommandCatalog.dispatch(event,to:self,menu:{makeShortcutMenu()}) {return}
    if GridShortcuts.matches(.gridCopyQuery,event) {return}
    if GridShortcuts.matches(.columns,event) { searchColumns?(); return }
    if event.keyCode == 36 || event.keyCode == 76 {
      if let c=owner.cellColumns.first, let position=tableColumns.indices.first(where:{canonicalPosition($0) == c}), selectedRow >= 0 {editCell?(selectedRow,position);return}
    }
    if GridShortcuts.matchesHeaders(event) { copyHeaders?(); return }
    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" { copyRows?(); return }
    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "a" {
      selectAllCells(nil); return
    }
    if let step=[123:-1,124:1][Int(event.keyCode)], let navigateCell {navigateCell(step);return}
    super.keyDown(with: event)
  }
}
/// A single painted gutter outside the horizontal clip view. The hidden synthetic
/// table column keeps existing cell/ordinal mappings; no data cells or spool are duplicated.
