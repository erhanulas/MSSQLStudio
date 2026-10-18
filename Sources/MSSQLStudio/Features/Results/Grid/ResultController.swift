import AppKit
import SQLServerKit
import SwiftUI

@MainActor
final class ResultController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSControlTextEditingDelegate {
  let table = CopyTable()
  let rowGutter = ResultRowGutter()
  let selectionSummary=ResultSelectionPresentation()
  let queryCopy=ResultQueryCopyPresentation()
  // Both native tables read the same result/projection/staged edits; only presentation differs.
  let frozenTable = CopyTable()
  let frozenScroll = NSScrollView()
  private(set) var pinnedColumns: [Int] = []
  private var frozenWidth: NSLayoutConstraint?
  private var rowGutterWidth:NSLayoutConstraint?
  private var synchronizingSelection=false
  private var synchronizingScroll=false
  private var synchronizingColumns=false
  private var synchronizingSort=false
  var visibleColumnOrdinals: [Int] {
    pinnedColumns + table.tableColumns.compactMap {column in
      guard !column.isHidden, let ordinal=Int(column.identifier.rawValue), !pinnedColumns.contains(ordinal) else {return nil}
      return ordinal
    }
  }
  func isColumnHidden(_ ordinal:Int) -> Bool {
    !pinnedColumns.contains(ordinal) && (table.tableColumns.first {$0.identifier.rawValue == String(ordinal)}?.isHidden ?? true)
  }
  private func presentationColumn(_ ordinal:Int) -> (CopyTable,Int)? {
    let target=pinnedColumns.contains(ordinal) ? frozenTable:table
    guard let position=target.tableColumns.firstIndex(where:{$0.identifier.rawValue == String(ordinal)}) else {return nil}
    return (target,position)
  }
  func setColumnPinned(_ ordinal:Int,pinned:Bool) {
    _ = view
    guard result.fields.indices.contains(ordinal), pinnedColumns.contains(ordinal) != pinned,
      let column=table.tableColumns.first(where:{$0.identifier.rawValue == String(ordinal)}) else {return}
    // Finish the native field editor before changing its column's presentation.
    if let window=view.window, !window.makeFirstResponder(nil) {return}
    popover?.close()
    if pinned {pinnedColumns.append(ordinal)} else {pinnedColumns.removeAll {$0 == ordinal}}
    column.isHidden=pinned
    rebuildFrozenColumns()
    view.layoutSubtreeIfNeeded()
    if !pinned {table.scrollColumnToVisible(table.column(withIdentifier:column.identifier))}
    editsChanged?();scheduleSelectionSummary()
  }
  private func rebuildFrozenColumns() {
    synchronizingColumns=true
    synchronizingSort=true
    defer {synchronizingColumns=false; synchronizingSort=false}
    for column in frozenTable.tableColumns {frozenTable.removeTableColumn(column)}
    let row=NSTableColumn(identifier:.init("row")); row.isHidden=true; frozenTable.addTableColumn(row)
    for ordinal in pinnedColumns {
      guard let source=table.tableColumns.first(where:{$0.identifier.rawValue == String(ordinal)}) else {continue}
      let column=NSTableColumn(identifier:source.identifier)
      column.title=source.title; column.minWidth=max(96,source.minWidth); column.maxWidth=source.maxWidth; column.width=max(column.minWidth,source.width,GridColumnSizing.headerWidth(source.title, detail: (source.headerCell as? FilterHeaderCell)?.typeDetail ?? "")+16)
      column.isEditable=source.isEditable; column.sortDescriptorPrototype=source.sortDescriptorPrototype
      if let cell=source.dataCell as? NSCell {column.dataCell=cell.copy()}
      column.headerCell=FilterHeaderCell(textCell:source.title)
      frozenTable.addTableColumn(column)
    }
    frozenTable.sortDescriptors=table.sortDescriptors
    refreshColumnHeaders()
    frozenScroll.isHidden=pinnedColumns.isEmpty
    frozenTable.reloadData()
    synchronizeSelection(from:table)
    updateFrozenWidth()
    synchronizeVerticalScroll(from:table.enclosingScrollView?.contentView)
  }
  private func refreshColumnHeaders() {
    for column in table.tableColumns+frozenTable.tableColumns {
      guard let ordinal=Int(column.identifier.rawValue), result.fields.indices.contains(ordinal), let header=column.headerCell as? FilterHeaderCell else {continue}
      let field=result.fields[ordinal], reason=readOnlyReason(column:ordinal)
      header.typeSymbol=reason != nil ? "lock.fill":field.type == -7 ? "checkmark.square":field.numeric ? "number":([91,92,93,-9_101,-9_102].contains(Int(field.type)) ? "calendar":"textformat")
      header.typeDetail=field.dataType; header.pinned=pinnedColumns.contains(ordinal)
      header.primaryKey = editDefinition.map { definition in definition.columns.indices.contains(ordinal) && definition.primaryKey.contains(definition.columns[ordinal].name) } ?? false
      header.active=rules[ordinal] != nil
      header.navigationTarget=highlightedColumnOrdinal == ordinal
      header.ascending=table.sortDescriptors.first?.key == String(ordinal) ? table.sortDescriptors.first?.ascending:nil
      column.headerToolTip="\(field.name) · \(field.dataType)"+(header.primaryKey ? " · Primary key":"")+(header.pinned ? " · Sabitlenmiş kolon":"")+(rules[ordinal].map {" · Yerel filtre: "+$0.summary} ?? "")+(reason.map {" · "+$0} ?? "")
    }
    table.headerView?.needsDisplay=true; frozenTable.headerView?.needsDisplay=true
  }
  override func viewDidLayout() {super.viewDidLayout();updateFrozenWidth()}
  private func updateFrozenWidth() {
    let total=frozenTable.tableColumns.filter {!$0.isHidden}.reduce(CGFloat(0)) {$0+$1.width+frozenTable.intercellSpacing.width}
    // An oversized pinned group has its own horizontal scrollbar, keeping the other columns reachable.
    let width=pinnedColumns.isEmpty ? 0:min(total,max(0,view.bounds.width-(rowGutterWidth?.constant ?? 36)-160))
    if frozenWidth?.constant != width {frozenWidth?.constant=width}
  }
  @objc private func gridBoundsChanged(_ notification:Notification) {
    synchronizeVerticalScroll(from:notification.object as? NSClipView)
  }
  private func synchronizeVerticalScroll(from source:NSClipView?) {
    guard !synchronizingScroll, !pinnedColumns.isEmpty, let source, let main=table.enclosingScrollView?.contentView else {return}
    let target=source === main ? frozenScroll.contentView:main
    guard target.bounds.minY != source.bounds.minY else {return}
    synchronizingScroll=true
    target.scroll(to:NSPoint(x:target.bounds.minX,y:source.bounds.minY))
    target.enclosingScrollView?.reflectScrolledClipView(target)
    synchronizingScroll=false
  }
  private func synchronizeSelection(from source:NSTableView) {
    guard !synchronizingSelection, !pinnedColumns.isEmpty else {return}
    synchronizingSelection=true
    let target=source === table ? frozenTable:table
    target.selectRowIndexes(source.selectedRowIndexes,byExtendingSelection:false)
    table.needsDisplay=true; frozenTable.needsDisplay=true; rowGutter.needsDisplay=true
    synchronizingSelection=false
  }
  private func moveSelectedCell(_ step:Int) {
    let order=visibleColumnOrdinals
    guard !order.isEmpty, table.selectedRow >= 0 else {return}
    let current=table.selectedColumns(in:table.selectedRow).first.flatMap {table.tableColumns.indices.contains($0) ? Int(table.tableColumns[$0].identifier.rawValue):nil}
    let index=current.flatMap {order.firstIndex(of:$0)} ?? (step>0 ? -1:order.count)
    let ordinal=order[max(0,min(order.count-1,index+step))]
    guard let canonical=table.tableColumns.firstIndex(where:{$0.identifier.rawValue == String(ordinal)}), let (target,position)=presentationColumn(ordinal) else {return}
    table.selectCell(row:table.selectedRow,column:canonical)
    target.scrollColumnToVisible(position); view.window?.makeFirstResponder(target)
  }
  private func selectDraggedCell(_ event:NSEvent) -> Bool {
    for target in [frozenTable,table] where !target.isHiddenOrHasHiddenAncestor {
      guard let clip=target.enclosingScrollView?.contentView else {continue}
      let point=target.convert(event.locationInWindow,from:nil)
      guard clip.documentVisibleRect.contains(point), let column=target.canonicalPosition(target.column(at:point)), target.row(at:point)>=0 else {continue}
      table.selectCell(row:target.row(at:point),column:column,extending:true)
      return true
    }
    return false
  }
  func tableViewColumnDidResize(_ notification:Notification) {
    guard !synchronizingColumns, let source=notification.object as? NSTableView else {return}
    synchronizingColumns=true
    for ordinal in pinnedColumns {
      guard let main=table.tableColumns.first(where:{$0.identifier.rawValue == String(ordinal)}), let fixed=frozenTable.tableColumns.first(where:{$0.identifier == main.identifier}) else {continue}
      if source === frozenTable {main.width=fixed.width} else {fixed.width=main.width}
    }
    synchronizingColumns=false; updateFrozenWidth()
  }
  func tableViewColumnDidMove(_ notification:Notification) {
    guard !synchronizingColumns, let source=notification.object as? NSTableView else {return}
    if source === frozenTable {
      pinnedColumns=frozenTable.tableColumns.compactMap {Int($0.identifier.rawValue)}
    } else if let from=notification.userInfo?["NSOldColumn"] as? Int, let to=notification.userInfo?["NSNewColumn"] as? Int {
      table.remapSelectionAfterColumnMove(from:from,to:to)
    }
    frozenTable.needsDisplay=true
    scheduleSelectionSummary()
  }
  private var generation = -1
  var requestEditing: ((Int, Int) -> Bool)?
  var editDefinition: TableDefinition? {
    didSet {
      editFormatters = Dictionary(uniqueKeysWithValues: (editDefinition?.columns.enumerated().map { ($0.offset, ResultCellFormatter(column: $0.element)) } ?? []))
      if isViewLoaded {refreshColumnHeaders();updateRange()}
    }
  }
  private var editFormatters: [Int: ResultCellFormatter] = [:]
  var hasDraftChanges: Bool {
    for target in [table,frozenTable] {
      let row=target.editedRow, position=target.editedColumn
      guard row >= 0, row < pageCount, target.tableColumns.indices.contains(position),
        let ordinal=Int(target.tableColumns[position].identifier.rawValue), let editor=target.currentEditor() as? NSTextView else {continue}
      let current=values(at:sourceIndex(row))
      if current.indices.contains(ordinal) && editor.string != (current[ordinal] ?? "NULL") {return true}
    }
    return false
  }
  func readOnlyReason(column: Int) -> String? {
    guard let definition = editDefinition, definition.columns.indices.contains(column) else { return nil }
    let c = definition.columns[column]
    if c.identity { return "IDENTITY alanını SQL Server üretir; değeri elle değiştirilemez." }
    if !c.computed.isEmpty { return "Hesaplanan kolonun değeri SQL Server tarafından hesaplanır." }
    if c.generated { return "Rowversion / timestamp değerini SQL Server üretir." }
    if !c.editableValue { return "Bu kolonun türü (\(c.type)) için güvenli hücre düzenleme henüz desteklenmiyor." }
    return nil
  }
  var editMetadataSignature: String?
  var editMetadataCached = false
  var editObjectID: Int?
  private(set) var pendingEdits: [Int: DataEditRow] = [:]
  private(set) var editValidationMessage: String?
  private var newRowOrder: [Int] = []
  private var nextNewRow = -1
  private func values(at index: Int) -> [String?] { pendingEdits[index]?.values ?? (index >= 0 ? Array(result.values[index]) : []) }
  func appendRow(cloning: Bool = false) {
    guard editingAllowed?() == true, let definition = editDefinition, pendingEdits.count < 400 else { return }
    var row = DataEditRow(original: nil, values: Array(repeating: nil, count: definition.columns.count))
    if cloning {
      guard table.selectedRow >= 0, table.selectedRow < pageCount else { return }
      let source = values(at: sourceIndex(table.selectedRow))
      for i in definition.columns.indices where !definition.columns[i].generated && definition.columns[i].editableValue && !definition.primaryKey.contains(definition.columns[i].name) {
        row.values[i] = source[i]; row.touched.insert(i)
      }
    }
    let index = nextNewRow; nextNewRow -= 1
    pendingEdits[index] = row; newRowOrder.append(index)
    table.reloadData(); updateRange(); let visible = basePageCount + newRowOrder.count - 1
    table.selectRowIndexes(IndexSet(integer: visible), byExtendingSelection: false); table.scrollRowToVisible(visible); editsChanged?()
  }
  func toggleSelectedDeletion() {
    guard editingAllowed?() == true, editDefinition != nil else { return }
    let selected = table.selectedRowIndexes.filter { $0 < pageCount }.map(sourceIndex)
    for index in selected {
      if index < 0 { pendingEdits.removeValue(forKey: index); newRowOrder.removeAll { $0 == index }; continue }
      if pendingEdits[index] == nil {
        guard pendingEdits.count < 400 else { break }
        let original = values(at: index); pendingEdits[index] = DataEditRow(original: original, values: original)
      }
      pendingEdits[index]?.deleted.toggle()
      if pendingEdits[index]?.deleted == false && pendingEdits[index]?.original == pendingEdits[index]?.values { pendingEdits.removeValue(forKey: index) }
    }
    table.deselectAll(nil); table.reloadData(); updateRange(); editsChanged?()
  }
  func revertSelectedRows() {
    guard editingAllowed?() == true else { return }
    let indices = table.selectedRowIndexes.filter { $0 < pageCount }.map(sourceIndex)
    for index in indices { pendingEdits.removeValue(forKey: index); newRowOrder.removeAll { $0 == index } }
    table.deselectAll(nil); table.reloadData(); updateRange(); editsChanged?()
  }
  var hasSelectedRows: Bool { table.selectedRowIndexes.contains { $0 >= 0 && $0 < pageCount } }
  var canAppendRow: Bool { editDefinition != nil && editingAllowed?() == true && pendingEdits.count < 400 }
  var canCloneRow: Bool { canAppendRow && hasSelectedRows }
  var canDeleteRows: Bool { editDefinition != nil && editingAllowed?() == true && hasSelectedRows }
  var canRevertRows: Bool {
    editDefinition != nil && editingAllowed?() == true &&
      (hasDraftChanges || table.selectedRowIndexes.contains { $0 < pageCount && pendingEdits[sourceIndex($0)] != nil })
  }
  var selectionIsDeleted: Bool {
    hasSelectedRows && table.selectedRowIndexes.filter { $0 < pageCount }.allSatisfy { pendingEdits[sourceIndex($0)]?.deleted == true }
  }
  var canSetSelectedNull: Bool {
    guard let position = table.selectedColumns(in:table.selectedRow).first, table.tableColumns.indices.contains(position),
      let ordinal = Int(table.tableColumns[position].identifier.rawValue),
      canEdit(row: table.selectedRow, column: ordinal), let definition = editDefinition
    else { return false }
    return definition.columns[ordinal].nullable
  }
  private func queryCopyColumns() throws -> [Int] {
    let rows=table.selectedRowIndexes
    guard !rows.isEmpty,!table.cellColumns.isEmpty,table.cellColumns.allSatisfy({table.tableColumns.indices.contains($0)}),rows.allSatisfy({$0<basePageCount}) else {
      throw SQLFailure("Bir satırda yan yana veya bir kolonda alt alta hücre seçin.")
    }
    guard !hasDraftChanges else {throw SQLFailure("Önce hücre düzenlemesini tamamlayın veya iptal edin.")}
    let selected=Set(table.cellColumns.compactMap {position in Int(table.tableColumns[position].identifier.rawValue)})
    let ordinals=visibleColumnOrdinals.filter {selected.contains($0)}
    guard !ordinals.isEmpty,ordinals.count<=64,rows.count<=1000 else {throw SQLFailure("En fazla 64 kolon veya 1.000 satır seçin.")}
    guard rows.count==1 || ordinals.count==1 else {throw SQLFailure("Çok satırlı seçimde tek bir kolon seçin.")}
    return ordinals
  }
  private func queryCopyCells() throws -> [(column:Int,value:String?)] {
    let ordinals=try queryCopyColumns()
    return try table.selectedRowIndexes.flatMap {row in
      let rowValues=values(at:sourceIndex(row))
      return try ordinals.map {ordinal in
        guard rowValues.indices.contains(ordinal) else {throw SQLFailure("Seçili hücre kaynağı değişti.")}
        return (ordinal,rowValues[ordinal])
      }
    }
  }
  private func queryCopyMenuItem()->NSMenuItem {
    let item=NSMenuItem(title:"Bu değerlerle sorgu kopyala",action:#selector(copyQueryWithValues),keyEquivalent:"")
    item.target=self;item.image=NSImage(systemSymbolName:"doc.on.doc",accessibilityDescription:nil)
    item.identifier = .init("gridCopyQuery")
    do {
      let columns=try queryCopyColumns()
      if let template=queryCopy.template,!template.supports(columns:columns) {throw SQLFailure("Seçili hesaplanan kolon doğrudan WHERE koşuluna çevrilemiyor.")}
      item.isEnabled=queryCopy.template != nil
      item.toolTip=item.isEnabled ? "Kaynak SELECT’in WHERE koşulunu seçili değerlerle değiştirip panoya kopyalar; sorguyu çalıştırmaz.":queryCopy.reason
    } catch {item.isEnabled=false;item.toolTip=error.localizedDescription}
    return item
  }
  @objc private func copyQueryWithValues() {
    do {
      guard let template=queryCopy.template else {throw SQLFailure(queryCopy.reason)}
      let sql=try template.sql(cells:queryCopyCells())
      NSPasteboard.general.clearContents()
      guard NSPasteboard.general.setString(sql,forType:.string) else {throw SQLFailure("SQL panoya yazılamadı.")}
      if let host=view.window?.contentView {StudioConfetti.show(in:host)}
    } catch {
      let alert=StudioAlert(role:"copyQueryWithValues")
      alert.messageText="Sorgu kopyalanamadı";alert.informativeText=error.localizedDescription
      alert.runModal()
    }
  }
  func editingMenu() -> [NSMenuItem] {
    guard editDefinition != nil else { return [] }
    return [("Yeni Satır", "plus", #selector(addResultRow), canAppendRow), ("Satırı Çoğalt", "plus.square.on.square", #selector(cloneResultRow), canCloneRow), (selectionIsDeleted ? "Silmeyi Geri Al" : "Satırı Sil", selectionIsDeleted ? "trash.slash" : "trash", #selector(deleteResultRow), canDeleteRows), ("Seçili Düzenlemeleri Geri Al", "arrow.uturn.backward", #selector(revertResultRows), canRevertRows)].map { title, icon, action, enabled in
      let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self
      item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
      item.isEnabled = enabled
      return item
    }
  }
  @objc private func addResultRow() { table.window?.makeFirstResponder(nil); appendRow() }
  @objc private func cloneResultRow() { table.window?.makeFirstResponder(nil); appendRow(cloning: true) }
  @objc private func deleteResultRow() { table.window?.makeFirstResponder(nil); toggleSelectedDeletion() }
  @objc private func revertResultRows() { table.window?.makeFirstResponder(nil); revertSelectedRows() }
  var editsChanged: (() -> Void)?
  var rowCountChanged:(()->Void)?
  var editingAllowed: (() -> Bool)?
  func discardEdits() { _ = table.abortEditing(); _ = frozenTable.abortEditing(); pendingEdits = [:]; newRowOrder = []; nextNewRow = -1; editValidationMessage = nil; editDefinition = nil; editObjectID = nil; editMetadataSignature = nil; editMetadataCached = false; table.reloadData(); updateInfo(); editsChanged?() }
  func pendingSQL() throws -> String {
    guard let editDefinition else { throw SQLFailure("Önce düzenlemeyi açın.") }
    return try DataEditScripts.changes(table: editDefinition, rows: (pendingEdits.keys.filter { $0 >= 0 }.sorted() + newRowOrder).compactMap { pendingEdits[$0] }, expectedObjectID: editObjectID, rowMatching: .primaryKeyOrOriginalValues)
  }
  private func validateEditValue(_ value: String?, column: Int) -> Bool {
    guard let definition = editDefinition, definition.columns.indices.contains(column) else { return false }
    do {
      try ResultValueValidation.validate(value, column: definition.columns[column])
      editValidationMessage = nil; info.textColor = StudioTheme.muted; updateRange()
      updateInfo()
      return true
    } catch {
      editValidationMessage = error.localizedDescription
      info.stringValue = error.localizedDescription; info.textColor = StudioTheme.danger; info.toolTip = error.localizedDescription
      info.isHidden = false
      return false
    }
  }
  func setEditValue(_ value: String?, row: Int, column: Int) {
    guard canEdit(row: row, column: column), validateEditValue(value, column: column) else { return }
    let index = sourceIndex(row)
    if pendingEdits[index] == nil {
      guard pendingEdits.count < 400 else { NSSound.beep(); return }
      let original = Array(result.values[index]); pendingEdits[index] = DataEditRow(original: original, values: original)
    }
    pendingEdits[index]?.values[column] = value
    pendingEdits[index]?.touched.insert(column)
    if pendingEdits[index]?.original != nil && pendingEdits[index]?.values == pendingEdits[index]?.original { pendingEdits.removeValue(forKey: index) }
    editsChanged?(); table.reloadData()
  }
  private func canEdit(row: Int, column: Int) -> Bool {
    guard editingAllowed?() == true, let definition = editDefinition, row >= 0, row < pageCount, definition.columns.indices.contains(column) else { return false }
    let c = definition.columns[column]
    let staged = pendingEdits[sourceIndex(row)]
    return staged?.deleted != true && c.editableValue && !c.generated
  }
  func setSelectedNull() {
    guard canSetSelectedNull, let column = table.selectedColumns(in:table.selectedRow).first, let ordinal = Int(table.tableColumns[column].identifier.rawValue) else { return }
    setEditValue(nil, row: table.selectedRow, column: ordinal)
  }
  private(set) var result = Rows()
  private var loadedResult = Rows()
  private(set) var readLimit=Int.max
  var loadedRowCount:Int {loadedResult.values.count}
  var isReadLimited:Bool {result.values.count < loadedRowCount}
  private(set) var visibleIndices: [Int]?
  private(set) var rules: [Int: ColumnRule] = [:]
  private let projectionController = ResultProjectionController()
  private var busy = false
  var isProcessing: Bool { busy }
  private let info = NSTextField(labelWithString: "")
  private let clearFiltersButton=StudioToolbarButton(symbol:"line.3.horizontal.decrease",label:"Filtreleri temizle",tone:.warning)
  private var navigation: [NSButton] = []
  private let chips = NSStackView()
  let toolbar = NSStackView()
  var toolbarHosted = false
  private(set) var pageStart = 0
  private(set) var pageSize = GridPaging.defaultSize
  private var needsAutoFit = true
  private var chipsHeight: NSLayoutConstraint?
  private var popover: NSPopover?
  private(set) var highlightedColumnOrdinal:Int?
  var clearSearch: (() -> Void)?
  var partial = false { didSet { updateInfo() } }
  var filter = "" { didSet { if filter != oldValue { reload() } } }
  var visibleCount: Int { visibleIndices?.count ?? result.values.count }
  private func configureGrid(_ target:CopyTable,scroll:NSScrollView,identifier:String) {
    target.dataSource=self; target.delegate=self; target.style = .plain
    target.usesAlternatingRowBackgroundColors=true
    target.backgroundColor=StudioTheme.resultCanvas
    target.rowHeight=24; target.usesAutomaticRowHeights=false
    target.intercellSpacing=NSSize(width:1,height:1)
    target.gridStyleMask=[.solidVerticalGridLineMask,.solidHorizontalGridLineMask]
    target.gridColor=StudioTheme.resultBorder
    target.columnAutoresizingStyle = .noColumnAutoresizing
    target.allowsMultipleSelection=true; target.allowsColumnReordering=true
    target.setAccessibilityIdentifier(identifier)
    target.toolTip="Düzenlemek için çift tıklayın veya Enter’a basın. Değişiklikler yalnız SQL önizlemesinden onayla gönderilir."
    target.focusRingType = .none; scroll.focusRingType = .none
    scroll.borderType = .noBorder
    scroll.drawsBackground=false
    scroll.backgroundColor = StudioTheme.resultCanvas
    scroll.horizontalScrollElasticity = .none; scroll.verticalScrollElasticity = .none
    target.rowActions = { [weak self] in guard let self else {return []};return [queryCopyMenuItem()]+editingMenu() }
    target.columnShortcutItems={ [weak self] in
      guard let self else {return []}
      let ordinal=table.cellColumns.count == 1 ? table.cellColumns.first.flatMap {table.tableColumns.indices.contains($0) ? Int(table.tableColumns[$0].identifier.rawValue):nil}:nil
      let menu=columnMenu(ordinal:ordinal)
      let items=menu.items.filter {!$0.isSeparatorItem && $0.submenu == nil}
      for item in items {menu.removeItem(item)}
      return items
    }
    target.editCell = { [weak self, weak target] row,position in
      guard let self, let canonical=target?.canonicalPosition(position) else {return}
      inspectCell(row:row,position:canonical)
    }
    target.draftChanged = { [weak self, weak target] in
      if let self, let target, let editor = target.currentEditor() as? NSTextView {
        _ = target.validateDraft?(target.editedRow, target.editedColumn, editor.string)
      } else if let self {
        editValidationMessage = nil; updateInfo()
      }
      self?.editsChanged?()
    }
    target.validateDraft = { [weak self, weak target] row, position, value in
      guard let self, let target, row >= 0, row < pageCount, target.tableColumns.indices.contains(position),
        let ordinal = Int(target.tableColumns[position].identifier.rawValue) else { return true }
      if value == self.tableView(target, objectValueFor: target.tableColumns[position], row: row) as? String { return true }
      return validateEditValue(value, column: ordinal)
    }
    target.copyRows = { [weak self] in self?.copySelectionData() }
    target.copyHeaders = { [weak self] in self?.copySelectionData(includeHeaders:true) }
    target.navigateCell = { [weak self] in self?.moveSelectedCell($0) }
    target.dragSelection = { [weak self] in self?.selectDraggedCell($0) ?? false }
    let header=FilterHeader(); header.frame.size.height=40
    header.openFilter = { [weak self,weak target] position in
      guard let target, target.tableColumns.indices.contains(position), let ordinal=Int(target.tableColumns[position].identifier.rawValue) else {return}
      self?.openColumnOrdinal(ordinal)
    }
    header.openMenu = { [weak self,weak target,weak header] position,event in
      guard let self, let target, let header else {return}
      let ordinal=target.tableColumns.indices.contains(position) ? Int(target.tableColumns[position].identifier.rawValue):nil
      NSMenu.popUpContextMenu(columnMenu(ordinal:ordinal),with:event,for:header)
    }
    target.headerView=header
    scroll.contentView.postsBoundsChangedNotifications=true
    NotificationCenter.default.addObserver(self,selector:#selector(gridBoundsChanged(_:)),name:NSView.boundsDidChangeNotification,object:scroll.contentView)
  }
  override func loadView() {
    view = NSView()
    let scroll = NSScrollView()
    scroll.automaticallyAdjustsContentInsets=false; scroll.contentInsets = NSEdgeInsets(top:0,left:0,bottom:0,right:0)
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.usesPredominantAxisScrolling = true
    rowGutter.label = { [weak self] row in
      guard let self, row >= 0, row < pageCount else { return ("",StudioTheme.muted) }
      let index=sourceIndex(row)
      return (rowNumber(row),pendingEdits[index]?.deleted == true ? StudioTheme.danger:index < 0 ? StudioTheme.success:pendingEdits[index] != nil ? StudioTheme.warning:StudioTheme.muted)
    }
    configureGrid(table,scroll:scroll,identifier:"resultsGrid")
    // Install the final 40 pt header before AppKit computes its initial clip origin.
    // Otherwise the default 28 pt offset leaves the first row under the taller header.
    scroll.documentView = table
    rowGutter.connect(table)
    frozenScroll.hasHorizontalScroller=true; frozenScroll.hasVerticalScroller=false
    frozenScroll.autohidesScrollers=true; frozenScroll.scrollerStyle = .overlay
    frozenScroll.automaticallyAdjustsContentInsets=false
    frozenScroll.contentInsets=NSEdgeInsets(top:0,left:0,bottom:0,right:0)
    frozenScroll.usesPredominantAxisScrolling=true; frozenScroll.isHidden=true
    frozenScroll.setAccessibilityLabel("Sabitlenmiş sonuç kolonları")
    frozenTable.selectionOwner=table
    configureGrid(frozenTable,scroll:frozenScroll,identifier:"resultsFrozenGrid")
    frozenScroll.documentView=frozenTable
    frozenTable.searchColumns = { [weak self] in self?.table.searchColumns?() }
    table.cellSelectionChanged = { [weak self] in
      self?.frozenTable.needsDisplay=true; self?.editsChanged?(); self?.scheduleSelectionSummary()
    }
    table.selectionColumnOrder = { [weak self] in
      guard let self else {return []}
      return visibleColumnOrdinals.compactMap {ordinal in table.tableColumns.firstIndex {$0.identifier.rawValue == String(ordinal)}}
    }
    table.dataReloaded = { [weak self] in
      guard let self else {return}
      scheduleSelectionSummary()
      guard !pinnedColumns.isEmpty else {return}
      frozenTable.reloadData(); synchronizeSelection(from:table)
      synchronizeVerticalScroll(from:table.enclosingScrollView?.contentView)
    }
    let clear=clearFiltersButton
    clear.target = self; clear.action = #selector(clearFilters)
    clear.controlSize = .small; clear.flat = true
    info.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    info.textColor = StudioTheme.muted
    info.lineBreakMode = .byTruncatingMiddle
    info.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    navigation = ["backward.end", "chevron.left", "chevron.right", "forward.end"].enumerated().map { index, symbol in
      let button = StudioToolbarButton(symbol: symbol, label: ["İlk sayfa", "Önceki sayfa", "Sonraki sayfa", "Son sayfa"][index], tone: .neutral, width: 24)
      button.flat = true
      button.tag = index; button.target = self; button.action = #selector(navigate(_:))
      return button
    }
    let bar=toolbar
    for control in [navigation[0],navigation[1],navigation[2],navigation[3],info,clear] {bar.addArrangedSubview(control)}
    clear.setAccessibilityIdentifier("gridClearFilters")
    clear.isEnabled=false
    clear.title = ""
    clear.image = NSImage(systemSymbolName:"line.3.horizontal.decrease",accessibilityDescription:"Filtreleri temizle")
    clear.toolTip = "Tüm kolon filtrelerini ve sonuç aramasını temizle"
    bar.setAccessibilityIdentifier("gridNavigation")
    StudioTheme.resultSurface(bar)
    bar.spacing = 3
    bar.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    let chipScroll = NSScrollView()
    chipScroll.hasHorizontalScroller = true
    chipScroll.autohidesScrollers = true
    chipScroll.documentView = chips
    chips.orientation = .horizontal
    chips.spacing = 5
    chips.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    chips.setContentHuggingPriority(.required, for: .horizontal)
    for child in (toolbarHosted ? [chipScroll, rowGutter, frozenScroll, scroll] : [bar, chipScroll, rowGutter, frozenScroll, scroll]) {
      view.addSubview(child)
      child.translatesAutoresizingMaskIntoConstraints = false
    }
    chips.translatesAutoresizingMaskIntoConstraints = false
    frozenWidth=frozenScroll.widthAnchor.constraint(equalToConstant:0)
    rowGutterWidth=rowGutter.widthAnchor.constraint(equalToConstant:36)
    chipsHeight = chipScroll.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      chipsHeight!,
      chipScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      chipScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      chipScroll.topAnchor.constraint(equalTo: toolbarHosted ? view.topAnchor : bar.bottomAnchor),
      chips.leadingAnchor.constraint(equalTo: chipScroll.contentView.leadingAnchor),
      chips.topAnchor.constraint(equalTo: chipScroll.contentView.topAnchor),
      chips.heightAnchor.constraint(equalToConstant: 25),
      rowGutter.leadingAnchor.constraint(equalTo:view.leadingAnchor),
      rowGutter.topAnchor.constraint(equalTo:scroll.topAnchor),
      rowGutter.bottomAnchor.constraint(equalTo:scroll.bottomAnchor),
      rowGutterWidth!,
      frozenScroll.leadingAnchor.constraint(equalTo:rowGutter.trailingAnchor),
      frozenScroll.topAnchor.constraint(equalTo:scroll.topAnchor),
      frozenScroll.bottomAnchor.constraint(equalTo:scroll.bottomAnchor),
      frozenWidth!,
      scroll.leadingAnchor.constraint(equalTo: frozenScroll.trailingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: chipScroll.bottomAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    if !toolbarHosted {
      NSLayoutConstraint.activate([
        bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        bar.topAnchor.constraint(equalTo: view.topAnchor), bar.heightAnchor.constraint(equalToConstant: 28)
      ])
    }
  }
  var pageExportIndices: [Int]? {
    if pageSize == 0 { return visibleIndices }
    return (pageStart..<pageStart + basePageCount).map { visibleIndices?[$0] ?? $0 }
  }
  private var basePageCount: Int { pageSize == 0 ? visibleCount : min(pageSize, max(0, visibleCount - pageStart)) }
  var pageCount: Int { basePageCount + newRowOrder.count }
  func setPageSize(_ size: Int) {
    guard (0...1_000_000).contains(size) else { return }
    pageSize = size; pageStart = 0
    table.deselectAll(nil); table.reloadData(); updateRange()
  }
  @discardableResult func applyReadLimit(_ value:Int)->Bool {
    guard value > 0 else {return false}
    guard readLimit != value else {return true}
    // Even unchanged native drafts must retain their original row mapping until
    // editing is explicitly closed. Never hide staged UPDATE/DELETE rows.
    guard editDefinition == nil else {return false}
    readLimit=value
    let rows=loadedResult.values.prefixSnapshot(value)
    guard result.values.count != rows.count else {return true}
    popover?.close()
    result.values=rows
    visibleIndices=nil;pageStart=0
    table.deselectAll(nil)
    updateRange();table.reloadData()
    if let clip=table.enclosingScrollView?.contentView {
      clip.scroll(to:NSPoint(x:clip.bounds.minX,y:0));clip.enclosingScrollView?.reflectScrolledClipView(clip)
    }
    reload(debounce:false)
    return true
  }
  @objc private func navigate(_ sender: NSButton) {
    guard visibleCount > 0, pageSize > 0 else { return }
    let last = ((visibleCount - 1) / pageSize) * pageSize
    pageStart = [0, max(0,pageStart - pageSize), min(last,pageStart + pageSize),last][sender.tag]
    table.deselectAll(nil); table.reloadData()
    if let clip = table.enclosingScrollView?.contentView { clip.scroll(to: NSPoint(x: clip.bounds.minX, y: 0)) }
    updateRange()
  }
  @objc private func updateRange() {
    rowGutterWidth?.constant=ResultRowGutter.width(maxRow:result.values.count,editing:editDefinition != nil,newRows:!newRowOrder.isEmpty)
    updateFrozenWidth()
    pageStart = pageSize == 0 || visibleCount == 0 ? 0 : min(((visibleCount - 1) / pageSize) * pageSize, pageStart)
    let label = (visibleCount == 0 ? "0 / 0" : "\(pageStart + 1)–\(pageStart + basePageCount) / \(visibleCount.formatted())\(partial ? "+" : "")") + (newRowOrder.isEmpty ? "" : " + \(newRowOrder.count) yeni")
    toolbar.setAccessibilityValue(label)
    toolbar.setAccessibilityHelp("Geçerli sayfa / sınır içindeki satırlar. \(visibleCount.formatted()) filtrelenen · \(result.values.count.formatted()) sınır içinde · \(loadedRowCount.formatted()) önbellekte.")
    for button in navigation { button.isHidden = pageSize == 0; button.isEnabled = pageSize > 0 && visibleCount > 0 && (button.tag < 2 ? pageStart > 0 : pageStart + basePageCount < visibleCount) }
    rowCountChanged?()
  }
  func update(_ rows: Rows, generation: Int = 0) {
    _ = view
    queryCopy.prepare(source:rows.source,fields:rows.fields)
    let changedFields = result.fields != rows.fields
    guard changedFields || self.generation != generation || loadedResult.values.count != rows.values.count else {result.source=rows.source;loadedResult.source=rows.source;return}
    let changedGeneration=self.generation != generation,previousCount=result.values.count
    self.generation = generation
    highlightColumn(nil)
    if editDefinition != nil { discardEdits() }
    if changedFields {
      synchronizingSort=true
      defer {synchronizingSort=false}
      pinnedColumns=[]
      for column in frozenTable.tableColumns {frozenTable.removeTableColumn(column)}
      frozenScroll.isHidden=true; frozenWidth?.constant=0
      for c in table.tableColumns { table.removeTableColumn(c) }
      let n = NSTableColumn(identifier: .init("row"))
      let numberHeader = FilterHeaderCell(textCell: "#")
      numberHeader.typeSymbol = ""
      numberHeader.showsFilter = false
      n.headerCell = numberHeader
      let numberCell = GridDataCell(textCell:""); numberCell.alignment = .right; n.dataCell = numberCell
      n.title = "#"
      n.width = 36
      n.isHidden = true // Drawn in the fixed gutter; preserve the synthetic selection column.
      table.addTableColumn(n)
      for (i, f) in rows.fields.enumerated() {
        let c = NSTableColumn(identifier: .init(String(i)))
        let header = FilterHeaderCell(textCell: f.name)
        header.typeSymbol = f.type == -7 ? "checkmark.square" : f.numeric ? "number" : ([91, 92, 93, -9_101, -9_102].contains(Int(f.type)) ? "calendar" : "textformat")
        header.typeDetail = f.dataType
        c.headerCell = header
        let dataCell = GridDataCell(textCell:""); dataCell.isBit = f.type == -7; dataCell.alignment = f.numeric ? .right : .left; c.dataCell = dataCell
        c.isEditable = true
        c.title = f.name
        c.headerToolTip = "\(f.name) · \(f.dataType)"
        c.maxWidth = max(10_000, GridColumnSizing.headerWidth(f.name, detail: f.dataType))
        c.width = max(150, GridColumnSizing.headerWidth(f.name, detail: f.dataType))
        c.minWidth = 70
        c.sortDescriptorPrototype = NSSortDescriptor(key: String(i), ascending: true)
        table.addTableColumn(c)
      }
      needsAutoFit = true
      rules = [:]
      visibleIndices = nil
    }
    loadedResult=rows
    result=rows;result.values=rows.values.prefixSnapshot(readLimit)
    if changedFields || changedGeneration || result.values.count < previousCount {visibleIndices=nil}
    refreshColumnHeaders()
    if needsAutoFit && !rows.values.isEmpty { autoFitColumns(); needsAutoFit = false }
    reload()
  }
  func setRule(_ rule: ColumnRule, column: Int) throws {
    guard result.fields.indices.contains(column) else { return }
    try ResultFiltering.validate(rule, field: result.fields[column])
    rules[column] = rule.active ? rule : nil
    reload()
  }
  private func reload(debounce:Bool=true) {
    guard isViewLoaded else { return }
    projectionController.cancel()
    selectionSummary.cancel()
    rebuildChips()
    let rows = result
    let rules = rules
    let search = filter
    let descriptor = table.sortDescriptors.first
    let sort = descriptor?.key.flatMap(Int.init)
    let ascending = descriptor?.ascending ?? true
    if rules.isEmpty && search.isEmpty && sort == nil {
      busy = false
      visibleIndices = nil
      updateRange()
      table.reloadData()
      updateInfo()
      return
    }
    busy = true
    updateInfo()
    let request=ResultProjectionController.Request(rows:rows,search:search,rules:rules,sortColumn:sort,ascending:ascending)
    projectionController.project(request,debounce:debounce) { [weak self] result in
      guard let self else {return}
      busy=false
      switch result {
      case .success(let projected):
        visibleIndices=projected
        table.deselectAll(nil)
        updateRange()
        table.reloadData()
        updateInfo()
      case .failure(let error):
        info.stringValue="Filtre hatası"
        info.toolTip=error.localizedDescription
        info.isHidden=false
        scheduleSelectionSummary()
      }
    }
  }

  private func updateInfo() {
    guard isViewLoaded else { return }
    if let editValidationMessage {
      info.stringValue = editValidationMessage; info.toolTip = editValidationMessage
      info.textColor = StudioTheme.danger; info.isHidden = false
      return
    }
    info.textColor = StudioTheme.muted
    info.stringValue = busy ? "İşleniyor…" : (!partial && isReadLimited ? "Sınırlandı" : "")
    info.isHidden = info.stringValue.isEmpty
    info.toolTip = "\(loadedRowCount.formatted()) önbellekte · ilk \(result.values.count.formatted()) satır sınırında \(visibleCount.formatted()) eşleşme · Filtre/sıralama yalnızca sınır içindeki satırlara uygulanır."
    updateRange()
  }
  private func rebuildChips() {
    clearFiltersButton.isEnabled = !rules.isEmpty || !filter.isEmpty
    for c in chips.arrangedSubviews {
      chips.removeArrangedSubview(c)
      c.removeFromSuperview()
    }
    for (index, rule) in rules.sorted(by: { $0.key < $1.key }) {
      let b = NSButton(
        title: "\(result.fields[index].name): \(rule.summary) ×", target: self,
        action: #selector(removeRule(_:)))
      b.tag = index
      b.controlSize = .small
      b.toolTip = b.title
      chips.addArrangedSubview(b)
    }
    chipsHeight?.constant = rules.isEmpty ? 0 : 28
    refreshColumnHeaders()
  }
  @objc private func removeRule(_ sender: NSButton) {
    rules[sender.tag] = nil
    reload()
  }
  @objc private func clearFilters() {
    rules = [:]
    filter = ""
    clearSearch?()
    reload()
  }
  func revealColumn(_ ordinal:Int) {
    guard let (target,position)=presentationColumn(ordinal) else {return}
    target.tableColumns[position].isHidden=false
    view.layoutSubtreeIfNeeded(); target.scrollColumnToVisible(position)
    highlightColumn(ordinal); view.window?.makeFirstResponder(target)
  }
  private func highlightColumn(_ ordinal:Int?) {
    highlightedColumnOrdinal=ordinal
    refreshColumnHeaders()
    let help=ordinal.flatMap {result.fields.indices.contains($0) ? "Gidilen kolon: "+result.fields[$0].name:nil}
    table.headerView?.setAccessibilityHelp(help); frozenTable.headerView?.setAccessibilityHelp(help)
  }
  func columnMenu(ordinal:Int?) -> NSMenu {
    let menu=StudioMenu()
    func add(_ title:String,_ action:Selector,_ index:Int,_ symbol:String,to parent:NSMenu) -> NSMenuItem {
      let item=NSMenuItem(title:title,action:action,keyEquivalent:"")
      item.target=self; item.tag=index; item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:title)
      parent.addItem(item); return item
    }
    if let ordinal, result.fields.indices.contains(ordinal) {
      _ = add("Kolon Filtresi…",#selector(filterColumnMenu(_:)),ordinal,"line.3.horizontal.decrease.circle",to:menu)
      _ = add("İçeriğe Sığdır",#selector(fitColumn(_:)),ordinal,"arrow.left.and.right",to:menu)
      let pinned=pinnedColumns.contains(ordinal)
      _ = add(pinned ? "Sabitlemeyi Kaldır":"Kolonu Sabitle",#selector(togglePinnedColumn(_:)),ordinal,pinned ? "pin.slash":"pin",to:menu)
      _ = add("Kolonu Gizle",#selector(toggleColumn(_:)),ordinal,"eye.slash",to:menu)
      menu.addItem(.separator())
    }
    if !pinnedColumns.isEmpty {
      _ = add("Tüm Sabitlemeleri Kaldır",#selector(unpinAllColumns),-1,"pin.slash",to:menu)
      menu.addItem(.separator())
    }
    let parent=NSMenuItem(title:"Kolonları Göster / Gizle",action:nil,keyEquivalent:"")
    let list=StudioMenu(); parent.submenu=list
    parent.image=NSImage(systemSymbolName:"tablecells",accessibilityDescription:parent.title); menu.addItem(parent)
    for (index,field) in result.fields.enumerated() {
      let item=add("\(index+1). \(field.name)",#selector(toggleColumn(_:)),index,"eye",to:list)
      item.state=isColumnHidden(index) ? .off:.on
    }
    return menu
  }
  @objc private func togglePinnedColumn(_ sender:NSMenuItem) {setColumnPinned(sender.tag,pinned:!pinnedColumns.contains(sender.tag))}
  @objc private func unpinAllColumns() {
    for ordinal in pinnedColumns {setColumnPinned(ordinal,pinned:false)}
  }
  @objc private func toggleColumn(_ sender:NSMenuItem) {
    let hidden=isColumnHidden(sender.tag)
    if pinnedColumns.contains(sender.tag) {setColumnPinned(sender.tag,pinned:false); guard !pinnedColumns.contains(sender.tag) else {return}}
    table.tableColumns.first {$0.identifier.rawValue == String(sender.tag)}?.isHidden = !hidden
    table.cellSelectionChanged?()
  }
  @objc private func filterColumnMenu(_ sender:NSMenuItem) {openColumnOrdinal(sender.tag)}
  private func autoFitColumns() {
    let count = result.fields.count
    guard count > 0 else { return }
    let sampleCount = min(32, result.values.count, max(1,4096 / count))
    let attributes: [NSAttributedString.Key:Any] = [.font: StudioTheme.uiFont]
    var widths = result.fields.map { max(80,GridColumnSizing.headerWidth($0.name, detail: $0.dataType)) }
    for row in 0..<sampleCount {
      let values = result.values[row]
      for c in result.fields.indices where values.indices.contains(c) {
        let text = String((values[c] ?? "NULL").prefix(160)).replacingOccurrences(of: "\n", with: " ↵ ")
        widths[c] = max(widths[c],min(420,CGFloat(text.size(withAttributes: attributes).width + 18)))
      }
    }
    for column in table.tableColumns {
      if let ordinal = Int(column.identifier.rawValue) { column.width = result.fields[ordinal].type == -7 ? max(75,widths[ordinal]) : widths[ordinal] }
    }
  }
  @objc private func fitColumn(_ sender: NSMenuItem) {
    guard
      let column = table.tableColumns.first(where: { $0.identifier.rawValue == String(sender.tag) })
    else { return }
    let attributes: [NSAttributedString.Key: Any] = [.font: StudioTheme.uiFont]
    let headerWidth = GridColumnSizing.headerWidth(column.title, detail: result.fields[sender.tag].dataType)+(pinnedColumns.contains(sender.tag) ? 16:0)
    var width = headerWidth
    for i in 0..<min(200, pageCount) {
      let row = values(at: sourceIndex(i))
      let value = row.indices.contains(sender.tag) ? row[sender.tag] ?? "NULL" : "NULL"
      width = max(width, String(value.prefix(1000)).size(withAttributes: attributes).width + 16)
    }
    column.width = max(headerWidth,min(600, max(80, width)))
    tableViewColumnDidResize(Notification(name:NSTableView.columnDidResizeNotification,object:table))
  }
  private func openColumnOrdinal(_ ordinal:Int) {
    guard result.fields.indices.contains(ordinal), let (target,position)=presentationColumn(ordinal) else {return}
    popover?.close()
    let popup=NSPopover()
    let panel=ColumnFilterPanel(rows:result,column:ordinal,initial:rules[ordinal] ?? ColumnRule()) { [weak self,weak popup] rule in
      try self?.setRule(rule,column:ordinal);popup?.close()
    }.studioPanel()
    popover=popup
    let header=target.headerView
    let anchor=target.tableColumns[position].isHidden ? target:header ?? target
    let rect=anchor === target ? target.visibleRect:header?.headerRect(ofColumn:position)
    StudioPopover.show(popup,content:panel,from:anchor,rect:rect,size:NSSize(width:400,height:540))
  }
  func tableViewSelectionDidChange(_ notification:Notification) {
    guard !synchronizingSelection, let source=notification.object as? NSTableView else {return}
    synchronizeSelection(from:source); editsChanged?(); scheduleSelectionSummary()
  }
  private func scheduleSelectionSummary() {
    guard !busy else {selectionSummary.cancel();return}
    let selected=Set(table.cellColumns.compactMap {position in
      table.tableColumns.indices.contains(position) ? Int(table.tableColumns[position].identifier.rawValue):nil
    })
    let columns=visibleColumnOrdinals.filter {table.cellColumns.isEmpty || selected.contains($0)}
    func ordinals(_ positions:IndexSet)->[Int] {
      let chosen=Set(positions.compactMap {table.tableColumns.indices.contains($0) ? Int(table.tableColumns[$0].identifier.rawValue):nil})
      return columns.filter {chosen.contains($0)}
    }
    selectionSummary.update(.init(rows:result,selection:table.selectedRowIndexes,columns:columns,
      projection:visibleIndices,pageStart:pageStart,basePageCount:basePageCount,newRows:newRowOrder,
      overrides:pendingEdits.mapValues(\.values),sumEnabled:columns.count==1,
      defaultColumns:table.selectionDefaultColumns.map(ordinals),
      columnOverrides:table.selectionColumnOverrides.mapValues {IndexSet(ordinals($0))}))
  }
  override func viewDidDisappear() {super.viewDidDisappear();selectionSummary.cancel()}
  override func viewDidAppear() {super.viewDidAppear();scheduleSelectionSummary()}
  func numberOfRows(in tableView: NSTableView) -> Int { pageCount }
  func tableView(
    _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
  ) {
    guard !synchronizingSort else {return}
    synchronizingSort=true
    let other=tableView === table ? frozenTable:table
    other.sortDescriptors=tableView.sortDescriptors
    synchronizingSort=false; reload()
  }
  func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
    columnIndex != 0 && newColumnIndex != 0
  }
  private func sourceIndex(_ row: Int) -> Int { row >= basePageCount ? newRowOrder[row - basePageCount] : (visibleIndices?[pageStart + row] ?? (pageStart + row)) }
  func tableView(_ tableView: NSTableView, shouldEdit column: NSTableColumn?, row: Int) -> Bool {
    guard let ordinal = column.flatMap({ Int($0.identifier.rawValue) }) else { return false }
    if toggleBitValue(row:row,column:ordinal) {return false}
    return canEdit(row: row, column: ordinal)
  }
  /// Boolean edits use the same validated draft path as text; no database write occurs here.
  @discardableResult private func toggleBitValue(row:Int,column:Int)->Bool {
    guard result.fields.indices.contains(column),result.fields[column].type == -7,
      canEdit(row:row,column:column) else {return false}
    let current=values(at:sourceIndex(row))[column]
    setEditValue(current == "1" ? "0":"1",row:row,column:column)
    return true
  }
  func control(_ control: NSControl, didFailToFormatString string: String, errorDescription error: String?) -> Bool { false }
  func tableView(_ tableView: NSTableView, setObjectValue value: Any?, for column: NSTableColumn?, row: Int) {
    guard let ordinal = column.flatMap({ Int($0.identifier.rawValue) }) else { return }
    // Merely entering/leaving NULL or DEFAULT must not turn its display text into data.
    if let text = value as? String,
      text == self.tableView(tableView, objectValueFor: column, row: row) as? String { return }
    setEditValue(value as? String ?? "", row: row, column: ordinal)
  }
  private func rowNumber(_ row:Int) -> String {
    let index=sourceIndex(row)
    return (pendingEdits[index]?.deleted == true ? "− " : index < 0 ? "+ " : pendingEdits[index] == nil ? "" : "✎ ") + (index < 0 ? "Yeni" : String(index+1))
  }
  func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
    guard let column, row >= 0, row < pageCount else { return nil }
    let index = sourceIndex(row)
    guard let ordinal = Int(column.identifier.rawValue) else { return rowNumber(row) }
    let values = values(at: index)
    if index < 0, pendingEdits[index]?.touched.contains(ordinal) != true { return "" }
    guard values.indices.contains(ordinal), let value = values[ordinal] else { return "NULL" }
    if editDefinition != nil { return value }
    return String(value.prefix(1000)).replacingOccurrences(of: "\n", with: " ↵ ")
  }
  func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for column: NSTableColumn?, row: Int) {
    guard row >= 0, row < pageCount, let cell = cell as? GridDataCell else { return }
    cell.searchTerm=filter.trimmingCharacters(in:.whitespacesAndNewlines)
    let ordinal = column.flatMap { Int($0.identifier.rawValue) }
    let index = sourceIndex(row)
    let values = values(at: index)
    let missing = ordinal.map { !values.indices.contains($0) || values[$0] == nil } ?? false
    let changed = ordinal.map { pendingEdits[index]?.values[$0] != pendingEdits[index]?.original?[$0] } ?? (pendingEdits[index] != nil)
    cell.placeholderString = index < 0 && ordinal.map({ pendingEdits[index]?.touched.contains($0) != true }) == true ? "DEFAULT" : nil
    cell.isEditable = !cell.isBit && (ordinal.map { canEdit(row: row, column: $0) } ?? false)
    cell.isSelectable = cell.isEditable
    cell.formatter = ordinal.flatMap { editFormatters[$0] }
    cell.textColor = pendingEdits[index]?.deleted == true ? .systemRed : index < 0 ? .systemGreen : changed ? .systemOrange : missing ? .secondaryLabelColor : StudioTheme.text
    cell.font = missing ? nullFont : StudioTheme.uiFont
  }
  private let nullFont = NSFontManager.shared.convert(StudioTheme.uiFont,toHaveTrait:.italicFontMask)
  func copySelectionData(includeHeaders: Bool = false) {
    let chosen = table.selectedRowIndexes
    guard !chosen.isEmpty else { return }
    let ordinals=visibleColumnOrdinals.filter {ordinal in
      table.cellColumns.isEmpty || table.tableColumns.firstIndex(where:{$0.identifier.rawValue == String(ordinal)}).map {table.cellColumns.contains($0)} == true
    }
    let positions=Dictionary(uniqueKeysWithValues:ordinals.map {($0,table.column(withIdentifier:.init(String($0))))})
    guard chosen.count <= 10_000 else {
      let a = StudioAlert(role:"copyRowLimit")
      a.messageText = "Kopyalama sınırı: 10.000 satır"
      a.informativeText = "Daha büyük sonuçlar için Dışa Aktar kullanın veya daha az satır seçin."
      a.runModal()
      return
    }
    var bytes = includeHeaders ? ordinals.reduce(0) { $0 + result.fields[$1].name.utf8.count * 2 + 4 } : 0
    for row in chosen where row < pageCount {
      let values = values(at: sourceIndex(row))
      bytes += ordinals.reduce(0) {total,ordinal in
        let position=positions[ordinal] ?? -1
        return total + (table.isCellSelected(row:row,column:position) ? (values[ordinal]?.utf8.count ?? 4)*2+4:1)
      }
      if bytes > 16_777_216 {
        let alert = StudioAlert(role:"copyByteLimit")
        alert.messageText = "Kopyalama boyutu 16 MB sınırını aşıyor."
        alert.informativeText = "Dışa Aktar kullanın veya daha az satır seçin."
        alert.runModal()
        return
      }
    }
    let body = chosen.filter { $0 < pageCount }.map { row in
      ordinals.map { ordinal in
        let position=positions[ordinal] ?? -1
        guard table.isCellSelected(row:row,column:position) else {return ""}
        let value = (values(at: sourceIndex(row)))[ordinal]
        let v = value ?? "NULL"
        return v.contains("\t") || v.contains("\n") || v.contains("\"")
          ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
      }.joined(separator: "\t")
    }.joined(separator: "\n")
    let header = ordinals.map { ordinal in
      let name = result.fields[ordinal].name
      return name.contains("\t") || name.contains("\n") || name.contains("\"") ? "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : name
    }.joined(separator: "\t")
    let text = includeHeaders ? header + "\n" + body : body
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
  func cellIdentity(row: Int, position: Int) -> String? {
    guard row >= 0, row < pageCount, table.tableColumns.indices.contains(position) else { return nil }
    return "\(sourceIndex(row)):\(table.tableColumns[position].identifier.rawValue)"
  }
  private func inspectCell(row r: Int, position c: Int) {
    guard r >= 0, r < pageCount, table.tableColumns.indices.contains(c),
      let i = Int(table.tableColumns[c].identifier.rawValue)
    else { return }
    if editDefinition == nil, requestEditing?(r, c) == true { return }
    if toggleBitValue(row:r,column:i) {return}
    if canEdit(row:r,column:i), let (target,position)=presentationColumn(i) {target.editColumn(position,row:r,with:nil,select:true);return}
    let values = values(at: sourceIndex(r))
    guard values.indices.contains(i) else { return }
    let alert = StudioAlert(role:"readOnlyCell")
    alert.messageText = result.fields[i].name
    alert.informativeText = readOnlyReason(column: i) ?? "Bu hücre salt okunur."
    let text = StudioTextView()
    text.string = values[i] ?? "NULL"
    text.isEditable = false
    text.font = StudioTheme.codeFont
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 360))
    scroll.documentView = text
    scroll.hasVerticalScroller = true
    text.frame = scroll.bounds
    text.autoresizingMask = [.width]
    text.isVerticallyResizable = true
    alert.accessoryView = scroll
    alert.addButton(withTitle: "Kapat")
    alert.runModal()
  }
}
