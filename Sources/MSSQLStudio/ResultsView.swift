import AppKit
import SQLServerKit
import SwiftUI

@MainActor enum GridShortcuts {
  enum Action: String, CaseIterable { case headers, newQuery }
  struct Binding: Codable, Equatable {
    var key: String
    var modifiers: UInt
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    var label: String {
      (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
        + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + key.uppercased()
    }
  }
  static let changed = Notification.Name("MSSQLStudio.gridShortcutsChanged")
  static func binding(_ action: Action) -> Binding {
    if let data = UserDefaults.standard.data(forKey: "shortcut.\(action.rawValue)"), let binding = try? JSONDecoder().decode(Binding.self, from: data) { return binding }
    if action == .newQuery { return Binding(key: "n", modifiers: NSEvent.ModifierFlags.command.rawValue) }
    return Binding(key: "c", modifiers: headersModifiers.rawValue)
  }
  static var headersModifiers: NSEvent.ModifierFlags {
    if let data = UserDefaults.standard.data(forKey: "shortcut.headers"), let binding = try? JSONDecoder().decode(Binding.self, from: data) { return binding.flags }
    return UserDefaults.standard.string(forKey: "gridCopyHeadersShortcut") == "option" ? [.command,.option] : [.command,.shift]
  }
  static var headersLabel: String { binding(.headers).label }
  static func matchesHeaders(_ event: NSEvent) -> Bool {
    let binding = binding(.headers)
    return event.charactersIgnoringModifiers?.lowercased() == binding.key && event.modifierFlags.intersection([.command,.shift,.option,.control]) == binding.flags
  }
  static func save(_ event: NSEvent, action: Action) -> String? {
    let flags = event.modifierFlags.intersection([.command,.shift,.option,.control])
    guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1,
      key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }), flags.contains(.command) || flags.contains(.control)
    else { return "Bir harf/rakam ile ⌘ veya ⌃ kullanın. Escape iptal eder." }
    // Existing application and standard editing commands remain reserved.
    let reserved: [(String,NSEvent.ModifierFlags)] = [("q",.command),("w",.command),("s",.command),("s",[.command,.shift]),("o",.command),("c",.command),("v",.command),("x",.command),("a",.command),("z",.command),("z",[.command,.shift]),("f",.command),("f",.control),("f",[.command,.shift]),("r",.command),("m",.command),("l",.command),("b",[.command,.option])]
    guard !reserved.contains(where: { $0.0 == key && $0.1 == flags }) else { return "Bu tuş uygulamanın başka bir işlemi için ayrılmış." }
    let value = Binding(key: key, modifiers: flags.rawValue)
    guard !Action.allCases.filter({ $0 != action }).contains(where: { binding($0) == value }) else { return "Bu kısayol diğer işlemde kullanılıyor." }
    if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "shortcut.\(action.rawValue)") }
    NotificationCenter.default.post(name: changed, object: nil)
    return nil
  }
  static func reset(_ action: Action) {
    UserDefaults.standard.removeObject(forKey: "shortcut.\(action.rawValue)")
    if action == .headers { UserDefaults.standard.removeObject(forKey: "gridCopyHeadersShortcut") }
    NotificationCenter.default.post(name: changed, object: nil)
  }
}
@MainActor final class ResultSplitView: NSSplitView {
  var hideDivider = false
  override var dividerThickness: CGFloat { hideDivider ? 0 : super.dividerThickness }
  override func drawDivider(in rect: NSRect) { if !hideDivider { super.drawDivider(in: rect) } }
}
@MainActor enum GridPaging {
  static let choices = [10,100,250,500,1000,0]
  static var defaultSize: Int {
    guard UserDefaults.standard.object(forKey: "gridDefaultPageSize") != nil else { return 500 }
    let value = UserDefaults.standard.integer(forKey: "gridDefaultPageSize")
    return (0...1_000_000).contains(value) ? value : 500
  }
}
// Cell-based drawing avoids constructing NSTextField/Auto Layout trees for every visible row × column.
@MainActor final class GridDataCell: NSTextFieldCell {
  var isBit = false
  private let checkbox = NSButtonCell()
  override init(textCell string: String) {
    super.init(textCell:string)
    font = StudioTheme.uiFont; lineBreakMode = .byTruncatingTail
    isEditable = false; isSelectable = false; isBordered = false
    checkbox.setButtonType(.switch); checkbox.title = ""; checkbox.isEnabled = false; checkbox.controlSize = .small
  }
  required init(coder: NSCoder) { fatalError() }
  // NSCell's inherited ObjC copy would shallow-copy Swift-owned checkbox storage.
  // Field editing copies the cell; each copy must own a separate NSButtonCell.
  override func copy(with zone: NSZone? = nil) -> Any {
    let cell = GridDataCell(textCell: stringValue)
    cell.isBit = isBit; cell.font = font; cell.alignment = alignment
    cell.textColor = textColor; cell.lineBreakMode = lineBreakMode
    cell.isEditable = isEditable; cell.isSelectable = isSelectable
    cell.isBordered = isBordered; cell.isEnabled = isEnabled
    return cell
  }
  override func draw(withFrame frame: NSRect, in view: NSView) {
    isHighlighted = false
    backgroundStyle = .normal
    super.draw(withFrame:frame,in:view)
  }
  override func drawInterior(withFrame frame: NSRect, in view: NSView) {
    if isBit && ["0","1"].contains(stringValue) {
      checkbox.state = stringValue == "1" ? .on : .off
      checkbox.draw(withFrame:NSRect(x:frame.midX-8,y:frame.midY-8,width:16,height:16),in:view)
    } else { super.drawInterior(withFrame:frame.insetBy(dx:6,dy:2),in:view) }
  }
}
@MainActor final class CopyTable: NSTableView {
  var copyRows: (() -> Void)?
  var copyHeaders: (() -> Void)?
  private(set) var cellColumns = IndexSet() {
    didSet { if cellColumns != oldValue { needsDisplay = true } }
  }
  override func highlightSelection(inClipRect clip: NSRect) {
    StudioTheme.selection.setFill()
    let visible = rows(in:clip)
    guard visible.location != NSNotFound, visible.length > 0 else { return }
    for row in selectedRowIndexes.intersection(IndexSet(integersIn:visible.location..<NSMaxRange(visible))) {
      let rowRect = rect(ofRow:row)
      if cellColumns.isEmpty { NSIntersectionRect(rowRect,clip).fill() }
      else { for column in cellColumns where column < numberOfColumns { NSIntersectionRect(NSIntersectionRect(rect(ofColumn:column),rowRect),clip).fill() } }
    }
  }
  private var anchor: (row: Int, column: Int)?
  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let r = row(at: point), c = column(at: point)
    guard r >= 0, c >= 0 else { super.mouseDown(with: event); return }
    window?.makeFirstResponder(self)
    if event.modifierFlags.contains(.shift), let anchor {
      selectRowIndexes(IndexSet(integersIn: min(r, anchor.row)...max(r, anchor.row)), byExtendingSelection: false)
      cellColumns = c == 0 || anchor.column == 0 ? IndexSet() : IndexSet(integersIn: min(c, anchor.column)...max(c, anchor.column))
    } else {
      anchor = (r, c)
      selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
      cellColumns = c == 0 ? IndexSet() : IndexSet(integer: c)
    }
    needsDisplay = true
    if event.clickCount == 2 { super.mouseDown(with: event) }
  }
  override func mouseDragged(with event: NSEvent) {
    guard let anchor else { return }
    _ = autoscroll(with: event)
    let p = convert(event.locationInWindow, from: nil)
    let r = row(at: p), c = column(at: p)
    guard r >= 0, c >= 0 else { return }
    selectRowIndexes(IndexSet(integersIn: min(r, anchor.row)...max(r, anchor.row)), byExtendingSelection: false)
    cellColumns = anchor.column == 0 || c == 0 ? IndexSet() : IndexSet(integersIn: min(c, anchor.column)...max(c, anchor.column))
  }
  override func rightMouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    let r = row(at: p), c = column(at: p)
    guard r >= 0, c >= 0 else { return }
    if !selectedRowIndexes.contains(r) || (!cellColumns.isEmpty && !cellColumns.contains(c)) {
      selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
      cellColumns = c == 0 ? IndexSet() : IndexSet(integer: c)
      anchor = (r, c)
    }
    let menu = NSMenu()
    let item = menu.addItem(withTitle: "Kopyala", action: #selector(copySelection), keyEquivalent: "c")
    item.target = self
    let headers = menu.addItem(withTitle: "Başlıklarla Kopyala", action: #selector(copyWithHeaders), keyEquivalent: GridShortcuts.binding(.headers).key)
    headers.keyEquivalentModifierMask = GridShortcuts.headersModifiers
    headers.target = self
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }
  @objc func copyWithHeaders() { copyHeaders?() }
  @objc func copySelection() { copyRows?() }
  @objc func copy(_ sender: Any?) { copyRows?() }
  override func keyDown(with event: NSEvent) {
    if GridShortcuts.matchesHeaders(event) { copyHeaders?(); return }
    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" { copyRows?(); return }
    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "a" {
      cellColumns = IndexSet(); selectAll(nil); return
    }
    if let anchor, let code = [123: -1, 124: 1][Int(event.keyCode)] {
      let c = max(1, min(numberOfColumns - 1, anchor.column + code))
      self.anchor = (max(0, selectedRow), c); cellColumns = IndexSet(integer: c)
      scrollColumnToVisible(c); needsDisplay = true; return
    }
    super.keyDown(with: event)
  }
}
@MainActor private final class FilterHeaderCell: NSTableHeaderCell {
  var active = false
  var typeSymbol = "textformat"
  var showsFilter = true
  var ascending: Bool?
  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    StudioTheme.panel.setFill()
    NSBezierPath(rect: cellFrame).fill()
    StudioTheme.border.setFill()
    NSBezierPath(rect: NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY, width: 1, height: cellFrame.height)).fill()
    NSBezierPath(rect: NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1)).fill()
    drawInterior(withFrame: cellFrame, in: controlView)
  }
  override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
    guard !stringValue.isEmpty else { return }
    let label = NSMutableParagraphStyle()
    label.lineBreakMode = .byTruncatingTail
    let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    stringValue.draw(
      in: NSRect(
        x: cellFrame.minX + 24, y: cellFrame.midY - font.pointSize / 2 - 2,
        width: max(0, cellFrame.width - 62), height: font.pointSize + 5),
      withAttributes: [.font: font, .foregroundColor: StudioTheme.text, .paragraphStyle: label])
    if let type = NSImage(systemSymbolName: typeSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [StudioTheme.accent])) {
      StudioTheme.accent.set()
      type.draw(in: NSRect(x: cellFrame.minX + 6, y: cellFrame.midY - 6, width: 12, height: 12))
    }
    if let ascending, let sort = NSImage(systemSymbolName: ascending ? "chevron.up" : "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [StudioTheme.accent])) {
      sort.draw(in: NSRect(x: cellFrame.maxX - 34, y: cellFrame.midY - 4, width: 8, height: 8))
    }
    if showsFilter, let filter = NSImage(systemSymbolName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [active ? StudioTheme.accent : StudioTheme.muted])) {
      filter.draw(in: NSRect(x: cellFrame.maxX - 19, y: cellFrame.midY - 6, width: 12, height: 12))
    }

  }
  override func drawSortIndicator(
    withFrame cellFrame: NSRect, in controlView: NSView, ascending: Bool, priority: Int
  ) {
    super.drawSortIndicator(
      withFrame: cellFrame.offsetBy(dx: -19, dy: 0), in: controlView, ascending: ascending,
      priority: priority)
  }
}
@MainActor private final class FilterHeader: NSTableHeaderView {
  var openFilter: ((Int) -> Void)?
  var openMenu: ((Int, NSEvent) -> Void)?
  override func rightMouseDown(with event: NSEvent) {
    openMenu?(column(at: convert(event.locationInWindow, from: nil)), event)
  }
  override func mouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    let c = column(at: p)
    if c >= 0 && p.x >= headerRect(ofColumn: c).maxX - 24 {
      openFilter?(c)
    } else {
      super.mouseDown(with: event)
    }
  }
}
@MainActor
final class ResultController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  let table = CopyTable()
  private var generation = -1
  var editDefinition: TableDefinition?
  var editObjectID: Int?
  private(set) var pendingEdits: [Int: DataEditRow] = [:]
  var editsChanged: (() -> Void)?
  var editingAllowed: (() -> Bool)?
  func discardEdits() { pendingEdits = [:]; editDefinition = nil; editObjectID = nil; table.reloadData(); editsChanged?() }
  func pendingSQL() throws -> String {
    guard let editDefinition else { throw SQLFailure("Önce düzenlemeyi açın.") }
    return try DataEditScripts.changes(table: editDefinition, rows: pendingEdits.keys.sorted().compactMap { pendingEdits[$0] }, expectedObjectID: editObjectID)
  }
  func setEditValue(_ value: String?, row: Int, column: Int) {
    guard canEdit(row: row, column: column) else { return }
    let index = sourceIndex(row)
    if pendingEdits[index] == nil {
      guard pendingEdits.count < 400 else { NSSound.beep(); return }
      let original = Array(result.values[index]); pendingEdits[index] = DataEditRow(original: original, values: original)
    }
    pendingEdits[index]?.values[column] = value
    if pendingEdits[index]?.values == pendingEdits[index]?.original { pendingEdits.removeValue(forKey: index) }
    editsChanged?(); table.reloadData()
  }
  private func canEdit(row: Int, column: Int) -> Bool {
    guard editingAllowed?() == true, let definition = editDefinition, row >= 0, row < pageCount, definition.columns.indices.contains(column) else { return false }
    let c = definition.columns[column]
    return !c.generated && !definition.primaryKey.contains(c.name)
  }
  func setSelectedNull() {
    guard let column = table.cellColumns.first, table.tableColumns.indices.contains(column), let ordinal = Int(table.tableColumns[column].identifier.rawValue) else { return }
    setEditValue(nil, row: table.selectedRow, column: ordinal)
  }
  private(set) var result = Rows()
  private(set) var visibleIndices: [Int]?
  private(set) var rules: [Int: ColumnRule] = [:]
  private var job: Task<Void, Never>?
  private var revision = 0
  private var busy = false
  var isProcessing: Bool { busy }
  private let info = NSTextField(labelWithString: "")
  private let rangeLabel = NSTextField(labelWithString: "0 / 0")
  private var navigation: [NSButton] = []
  private let chips = NSStackView()
  let toolbar = NSStackView()
  var toolbarHosted = false
  private(set) var pageStart = 0
  private(set) var pageSize = GridPaging.defaultSize
  private var needsAutoFit = true
  private var chipsHeight: NSLayoutConstraint?
  private var popover: NSPopover?
  var clearSearch: (() -> Void)?
  var partial = false { didSet { updateInfo() } }
  var filter = "" { didSet { if filter != oldValue { reload() } } }
  deinit { job?.cancel() }
  var visibleCount: Int { visibleIndices?.count ?? result.values.count }
  override func loadView() {
    view = NSView()
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = false
    scroll.scrollerStyle = .legacy
    scroll.usesPredominantAxisScrolling = true
    table.dataSource = self
    table.delegate = self
    table.usesAlternatingRowBackgroundColors = true
    scroll.horizontalScrollElasticity = .none
    scroll.verticalScrollElasticity = .none
    table.toolTip = "Tam değeri görmek için çift tıklayın"
    table.backgroundColor = StudioTheme.canvas
    table.gridColor = StudioTheme.border
    table.rowHeight = 24
    table.usesAutomaticRowHeights = false
    table.intercellSpacing = NSSize(width: 1, height: 1)
    table.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
    table.columnAutoresizingStyle = .noColumnAutoresizing
    table.allowsMultipleSelection = true
    table.allowsColumnReordering = true
    table.setAccessibilityIdentifier("resultsGrid")
    table.target = self
    table.doubleAction = #selector(inspectCell)
    table.copyRows = { [weak self] in self?.copySelectionData() }
    table.copyHeaders = { [weak self] in self?.copySelectionData(includeHeaders: true) }
    let head = FilterHeader()
    head.openFilter = { [weak self] c in self?.openColumn(c) }
    head.openMenu = { [weak self] column, event in self?.showColumnMenu(column, event: event) }
    head.frame.size.height = 28
    table.headerView = head
    let clear = NSButton(title: "Filtreleri Temizle", target: self, action: #selector(clearFilters))
    clear.controlSize = .small
    info.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    info.textColor = StudioTheme.muted
    info.lineBreakMode = .byTruncatingMiddle
    info.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    navigation = ["backward.end", "chevron.left", "chevron.right", "forward.end"].enumerated().map { index, symbol in
      let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: ["İlk sayfa", "Önceki sayfa", "Sonraki sayfa", "Son sayfa"][index])!, target: self, action: #selector(navigate(_:)))
      button.tag = index; button.bezelStyle = .inline; button.isBordered = false
      button.toolTip = ["İlk sayfa", "Önceki sayfa", "Sonraki sayfa", "Son sayfa"][index]
      return button
    }
    rangeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    rangeLabel.toolTip = "Yüklenen ve filtrelenmiş satırlarda gezinir; sunucudan sayfa istemez."
    // No bounds-change observer: scrolling never formats the counter or relayouts the toolbar.
    let bar = toolbar
    for control in [navigation[0], navigation[1], rangeLabel, navigation[2], navigation[3], info, clear] { bar.addArrangedSubview(control) }
    rangeLabel.setAccessibilityIdentifier("gridRange")
    rangeLabel.toolTip = "Son gezinme aralığı / yüklenen satırlar. Kaydırırken sayaç yeniden hesaplanmaz."
    clear.title = ""
    clear.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "Filtreleri temizle")
    clear.toolTip = "Tüm kolon filtrelerini ve sonuç aramasını temizle"
    bar.setAccessibilityIdentifier("gridNavigation")
    StudioTheme.surface(bar)
    clear.bezelStyle = .inline
    clear.isBordered = false
    clear.contentTintColor = StudioTheme.muted
    bar.spacing = 6
    bar.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    let chipScroll = NSScrollView()
    chipScroll.hasHorizontalScroller = true
    chipScroll.autohidesScrollers = true
    chipScroll.documentView = chips
    chips.orientation = .horizontal
    chips.spacing = 5
    chips.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    chips.setContentHuggingPriority(.required, for: .horizontal)
    for child in (toolbarHosted ? [chipScroll, scroll] : [bar, chipScroll, scroll]) {
      view.addSubview(child)
      child.translatesAutoresizingMaskIntoConstraints = false
    }
    chips.translatesAutoresizingMaskIntoConstraints = false
    chipsHeight = chipScroll.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      chipsHeight!,
      chipScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      chipScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      chipScroll.topAnchor.constraint(equalTo: toolbarHosted ? view.topAnchor : bar.bottomAnchor),
      chips.leadingAnchor.constraint(equalTo: chipScroll.contentView.leadingAnchor),
      chips.topAnchor.constraint(equalTo: chipScroll.contentView.topAnchor),
      chips.heightAnchor.constraint(equalToConstant: 25),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
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
    return (pageStart..<pageStart + pageCount).map { visibleIndices?[$0] ?? $0 }
  }
  var pageCount: Int { pageSize == 0 ? visibleCount : min(pageSize, max(0, visibleCount - pageStart)) }
  func setPageSize(_ size: Int) {
    guard (0...1_000_000).contains(size) else { return }
    pageSize = size; pageStart = 0
    table.deselectAll(nil); table.reloadData(); updateRange()
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
    pageStart = pageSize == 0 || visibleCount == 0 ? 0 : min(((visibleCount - 1) / pageSize) * pageSize, pageStart)
    let label = visibleCount == 0 ? "0 / 0" : "\(pageStart + 1)–\(pageStart + pageCount) / \(visibleCount.formatted())\(partial ? "+" : "")"
    if rangeLabel.stringValue != label { rangeLabel.stringValue = label }
    rangeLabel.toolTip = "Geçerli sayfa / yüklenen satırlar. \(visibleCount.formatted()) gösterilen / \(result.values.count.formatted()) yüklenen satır. All yalnızca yüklenen sonuçları kapsar."
    for button in navigation { button.isEnabled = pageSize > 0 && visibleCount > 0 && (button.tag < 2 ? pageStart > 0 : pageStart + pageCount < visibleCount) }
  }
  func update(_ rows: Rows, generation: Int = 0) {
    _ = view
    let changedFields = result.fields != rows.fields
    guard changedFields || self.generation != generation || result.values.count != rows.values.count else { return }
    self.generation = generation
    if editDefinition != nil { discardEdits() }
    if changedFields {
      for c in table.tableColumns { table.removeTableColumn(c) }
      let n = NSTableColumn(identifier: .init("row"))
      let numberHeader = FilterHeaderCell(textCell: "#")
      numberHeader.typeSymbol = ""
      numberHeader.showsFilter = false
      n.headerCell = numberHeader
      let numberCell = GridDataCell(textCell:""); numberCell.alignment = .right; n.dataCell = numberCell
      n.title = "#"
      n.width = 60
      table.addTableColumn(n)
      for (i, f) in rows.fields.enumerated() {
        let c = NSTableColumn(identifier: .init(String(i)))
        let header = FilterHeaderCell(textCell: f.name)
        header.typeSymbol = f.type == -7 ? "checkmark.square" : f.numeric ? "number" : ([91, 92, 93, -9_101, -9_102].contains(Int(f.type)) ? "calendar" : "textformat")
        c.headerCell = header
        let dataCell = GridDataCell(textCell:""); dataCell.isBit = f.type == -7; dataCell.alignment = f.numeric ? .right : .left; c.dataCell = dataCell
        c.isEditable = true
        c.title = f.name
        c.headerToolTip = "\(f.name) · \(f.dataType)"
        c.width = max(150, min(360, CGFloat(f.name.count * 9 + 45)))
        c.minWidth = 70
        c.sortDescriptorPrototype = NSSortDescriptor(key: String(i), ascending: true)
        table.addTableColumn(c)
      }
      needsAutoFit = true
      rules = [:]
      visibleIndices = nil
    }
    result = rows
    if needsAutoFit && !rows.values.isEmpty { autoFitColumns(); needsAutoFit = false }
    reload()
  }
  func setRule(_ rule: ColumnRule, column: Int) throws {
    guard result.fields.indices.contains(column) else { return }
    try ResultFiltering.validate(rule, field: result.fields[column])
    rules[column] = rule.active ? rule : nil
    reload()
  }
  private func reload() {
    guard isViewLoaded else { return }
    revision += 1
    let version = revision
    job?.cancel()
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
    job = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(220))
        let worker = Task.detached(priority: .userInitiated) {
          try ResultFiltering.projection(
            rows, search: search, rules: rules, sortColumn: sort, ascending: ascending)
        }
        let projected = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        guard let self, self.revision == version, !Task.isCancelled else { return }
        visibleIndices = projected
        busy = false
        table.deselectAll(nil)
        updateRange()
        table.reloadData()
        updateInfo()
      } catch is CancellationError {} catch {
        guard let self, revision == version else { return }
        busy = false
        info.stringValue = "Filtre hatası"
        info.toolTip = error.localizedDescription
        info.isHidden = false
      }
    }
  }
  private func updateInfo() {
    guard isViewLoaded else { return }
    info.stringValue = busy ? "İşleniyor…" : (partial ? "Kısmi sonuç" : "")
    info.isHidden = info.stringValue.isEmpty
    info.toolTip = "\(result.values.count.formatted()) yüklenen satırdan \(visibleCount.formatted()) gösteriliyor · Filtreler yalnızca yüklenmiş satırlara uygulanır."
    updateRange()
  }
  private func rebuildChips() {
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
    for c in table.tableColumns {
      if let i = Int(c.identifier.rawValue), result.fields.indices.contains(i) {
        c.title = result.fields[i].name
        (c.headerCell as? FilterHeaderCell)?.active = rules[i] != nil
        (c.headerCell as? FilterHeaderCell)?.ascending = table.sortDescriptors.first?.key == String(i) ? table.sortDescriptors.first?.ascending : nil
      }
    }
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
  private func showColumnMenu(_ position: Int, event: NSEvent) {
    let menu = NSMenu()
    func add(_ title: String, _ action: Selector, _ index: Int, to parent: NSMenu) -> NSMenuItem {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      item.tag = index
      parent.addItem(item)
      return item
    }
    if table.tableColumns.indices.contains(position),
      let index = Int(table.tableColumns[position].identifier.rawValue)
    {
      _ = add("Kolon Filtresi…", #selector(filterColumnMenu(_:)), index, to: menu)
      _ = add("İçeriğe Sığdır", #selector(fitColumn(_:)), index, to: menu)
      _ = add("Kolonu Gizle", #selector(toggleColumn(_:)), index, to: menu)
      menu.addItem(.separator())
    }
    let list = NSMenu()
    let parent = NSMenuItem(title: "Kolonları Göster / Gizle", action: nil, keyEquivalent: "")
    parent.submenu = list
    menu.addItem(parent)
    for (index, field) in result.fields.enumerated() {
      let item = add("\(index+1). \(field.name)", #selector(toggleColumn(_:)), index, to: list)
      item.state =
        table.tableColumns.first(where: { $0.identifier.rawValue == String(index) })?.isHidden
          == false ? .on : .off
    }
    if let header = table.headerView { NSMenu.popUpContextMenu(menu, with: event, for: header) }
  }
  @objc private func toggleColumn(_ sender: NSMenuItem) {
    if let column = table.tableColumns.first(where: { $0.identifier.rawValue == String(sender.tag) }
    ) {
      column.isHidden.toggle()
    }
  }
  @objc private func filterColumnMenu(_ sender: NSMenuItem) {
    if let i = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == String(sender.tag) }
    ) {
      openColumn(i)
    }
  }
  private func autoFitColumns() {
    let count = result.fields.count
    guard count > 0 else { return }
    let sampleCount = min(32, result.values.count, max(1,4096 / count))
    let attributes: [NSAttributedString.Key:Any] = [.font: StudioTheme.uiFont]
    var widths = result.fields.map { min(420,max(70,CGFloat($0.name.size(withAttributes: attributes).width + 58))) }
    for row in 0..<sampleCount {
      let values = result.values[row]
      for c in result.fields.indices where values.indices.contains(c) {
        let text = String((values[c] ?? "NULL").prefix(160)).replacingOccurrences(of: "\n", with: " ↵ ")
        widths[c] = min(420,max(widths[c],CGFloat(text.size(withAttributes: attributes).width + 18)))
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
    var width = CGFloat(column.title.size(withAttributes: attributes).width + 45)
    for i in 0..<min(200, pageCount) {
      let row = result.values[sourceIndex(i)]
      let value = row.indices.contains(sender.tag) ? row[sender.tag] ?? "NULL" : "NULL"
      width = max(width, String(value.prefix(1000)).size(withAttributes: attributes).width + 16)
    }
    column.width = min(600, max(80, width))
  }
  private func openColumn(_ position: Int) {
    guard table.tableColumns.indices.contains(position),
      let i = Int(table.tableColumns[position].identifier.rawValue),
      result.fields.indices.contains(i)
    else { return }
    popover?.close()
    let popup = NSPopover()
    popup.behavior = .transient
    popup.contentSize = NSSize(width: 400, height: 540)
    popup.contentViewController = NSHostingController(
      rootView: ColumnFilterPanel(rows: result, column: i, initial: rules[i] ?? ColumnRule()) {
        [weak self, weak popup] rule in
        try self?.setRule(rule, column: i)
        popup?.close()
      }.studioPanel())
    popover = popup
    if table.tableColumns[position].isHidden {
      popup.show(relativeTo: table.bounds, of: table, preferredEdge: .maxY)
    } else {
      popup.show(
        relativeTo: table.headerView?.headerRect(ofColumn: position) ?? table.bounds,
        of: table.headerView ?? table, preferredEdge: .maxY)
    }
  }
  func numberOfRows(in tableView: NSTableView) -> Int { pageCount }
  func tableView(
    _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
  ) { reload() }
  func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
    columnIndex != 0 && newColumnIndex != 0
  }
  private func sourceIndex(_ row: Int) -> Int { visibleIndices?[pageStart + row] ?? (pageStart + row) }
  func tableView(_ tableView: NSTableView, shouldEdit column: NSTableColumn?, row: Int) -> Bool {
    guard let ordinal = column.flatMap({ Int($0.identifier.rawValue) }) else { return false }
    return canEdit(row: row, column: ordinal)
  }
  func tableView(_ tableView: NSTableView, setObjectValue value: Any?, for column: NSTableColumn?, row: Int) {
    guard let ordinal = column.flatMap({ Int($0.identifier.rawValue) }) else { return }
    setEditValue(value as? String ?? "", row: row, column: ordinal)
  }
  func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
    guard let column, row >= 0, row < pageCount else { return nil }
    let index = sourceIndex(row)
    guard let ordinal = Int(column.identifier.rawValue) else { return (pendingEdits[index] == nil ? "" : "✎ ") + String(index+1) }
    let values = pendingEdits[index]?.values ?? Array(result.values[index])
    guard values.indices.contains(ordinal), let value = values[ordinal] else { return "NULL" }
    if editDefinition != nil { return value }
    return String(value.prefix(1000)).replacingOccurrences(of: "\n", with: " ↵ ")
  }
  func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for column: NSTableColumn?, row: Int) {
    guard row >= 0, row < pageCount, let cell = cell as? GridDataCell else { return }
    let ordinal = column.flatMap { Int($0.identifier.rawValue) }
    let index = sourceIndex(row)
    let values = pendingEdits[index]?.values ?? Array(result.values[index])
    let missing = ordinal.map { !values.indices.contains($0) || values[$0] == nil } ?? false
    let changed = ordinal.map { pendingEdits[index]?.values[$0] != pendingEdits[index]?.original?[$0] } ?? (pendingEdits[index] != nil)
    cell.isEditable = ordinal.map { canEdit(row: row, column: $0) } ?? false
    cell.isSelectable = cell.isEditable
    cell.textColor = changed ? .systemOrange : missing ? .secondaryLabelColor : StudioTheme.text
    cell.font = missing ? nullFont : StudioTheme.uiFont
  }
  private let nullFont = NSFontManager.shared.convert(StudioTheme.uiFont,toHaveTrait:.italicFontMask)
  func copySelectionData(includeHeaders: Bool = false) {
    let chosen = table.selectedRowIndexes
    guard !chosen.isEmpty else { return }
    let ordinals = table.tableColumns.enumerated().compactMap { index, column -> Int? in
      guard !column.isHidden, table.cellColumns.isEmpty || table.cellColumns.contains(index) else { return nil }
      return Int(column.identifier.rawValue)
    }
    guard chosen.count <= 10_000 else {
      let a = NSAlert()
      a.messageText = "Kopyalama sınırı: 10.000 satır"
      a.informativeText = "Daha büyük sonuçlar için Dışa Aktar kullanın veya daha az satır seçin."
      a.runModal()
      return
    }
    var bytes = includeHeaders ? ordinals.reduce(0) { $0 + result.fields[$1].name.utf8.count * 2 + 4 } : 0
    for row in chosen where row < pageCount {
      let values = pendingEdits[sourceIndex(row)]?.values ?? Array(result.values[sourceIndex(row)])
      bytes += ordinals.reduce(0) { $0 + (values[$1]?.utf8.count ?? 4) * 2 + 4 }
      if bytes > 16_777_216 {
        let alert = NSAlert()
        alert.messageText = "Kopyalama boyutu 16 MB sınırını aşıyor."
        alert.informativeText = "Dışa Aktar kullanın veya daha az satır seçin."
        alert.runModal()
        return
      }
    }
    let body = chosen.filter { $0 < pageCount }.map { row in
      ordinals.map { ordinal in
        let value = (pendingEdits[sourceIndex(row)]?.values ?? Array(result.values[sourceIndex(row)]))[ordinal]
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
  @objc private func inspectCell() {
    let r = table.clickedRow
    let c = table.clickedColumn
    guard r >= 0, r < pageCount, table.tableColumns.indices.contains(c),
      let i = Int(table.tableColumns[c].identifier.rawValue)
    else { return }
    if canEdit(row: r, column: i) { table.editColumn(c, row: r, with: nil, select: true); return }
    let values = pendingEdits[sourceIndex(r)]?.values ?? Array(result.values[sourceIndex(r)])
    guard values.indices.contains(i) else { return }
    let alert = NSAlert()
    alert.messageText = result.fields[i].name
    let text = NSTextView()
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
private struct ColumnFilterPanel: View {
  let rows: Rows
  let column: Int
  let apply: (ColumnRule) throws -> Void
  @State private var rule: ColumnRule
  @State private var search = ""
  @State private var values: [CellChoice] = []
  @State private var truncated = false
  @State private var loading = false
  @State private var error = ""
  init(rows: Rows, column: Int, initial: ColumnRule, apply: @escaping (ColumnRule) throws -> Void) {
    self.rows = rows
    self.column = column
    self.apply = apply
    _rule = State(initialValue: initial)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(rows.fields[column].name).font(.headline).lineLimit(2)
      Picker("Koşul", selection: $rule.operation) {
        ForEach(ColumnOperation.allCases, id: \.self) { op in
          if !rows.fields[column].numeric && !ResultFiltering.isDate(rows.fields[column])
            || ![.contains, .starts, .empty, .notEmpty].contains(op)
          {
            Text(op.rawValue).tag(op)
          }
        }
      }
      if rule.operation.needsValue {
        TextField(
          ResultFiltering.isDate(rows.fields[column]) ? "YYYY-MM-DD veya ISO 8601" : "Değer",
          text: $rule.first)
      }
      if rule.operation == .between { TextField("Bitiş (dahil)", text: $rule.second) }
      Divider()
      Toggle(
        "Değer seçimini kullan",
        isOn: Binding(get: { rule.choices != nil }, set: { rule.choices = $0 ? [] : nil }))
      TextField("Kolon değerlerinde ara", text: $search).textFieldStyle(.roundedBorder)
      HStack {
        Button("Görünenleri seç") { rule.choices = (rule.choices ?? []).union(values) }
        Button("Kaldır") { if rule.choices != nil { rule.choices?.subtract(values) } }
        Spacer()
        if loading { ProgressView().controlSize(.small) }
      }.controlSize(.small)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 5) {
          ForEach(values, id: \.self) { value in
            Toggle(
              String(value.title.prefix(256)),
              isOn: Binding(
                get: { rule.choices?.contains(value) ?? false },
                set: { on in
                  if on { rule.choices?.insert(value) } else { rule.choices?.remove(value) }
                })
            )
            .toggleStyle(.checkbox).disabled(rule.choices == nil).lineLimit(1).help(
              String(value.title.prefix(4000)))
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(maxHeight: .infinity)
      Text(
        truncated
          ? "En fazla 500 farklı değer gösterilir; diğerlerini arayın. Seçimler korunur."
          : "\(values.count) farklı değer · NULL ve boş metin ayrıdır."
      ).font(.caption).foregroundStyle(.secondary)
      if let choices = rule.choices {
        Text("\(choices.count) değer seçili; koşulla birlikte uygulanır.").font(.caption)
      }
      if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3) }
      HStack {
        Button("Filtreyi Kaldır") { commit(ColumnRule()) }
        Spacer()
        Button("Uygula") { commit(rule) }.buttonStyle(.borderedProminent)
      }
    }.padding(16).frame(width: 400, height: 540)
      .task(id: search) {
        loading = true
        error = ""
        do {
          try await Task.sleep(for: .milliseconds(200))
          let input = search
          let worker = Task.detached(priority: .userInitiated) {
            try ResultFiltering.choices(rows, column: column, search: input)
          }
          let output = try await withTaskCancellationHandler {
            try await worker.value
          } onCancel: {
            worker.cancel()
          }
          try Task.checkCancellation()
          values = output.values
          truncated = output.truncated
          loading = false
        } catch is CancellationError {} catch {
          self.error = error.localizedDescription
          loading = false
        }
      }
  }
  private func commit(_ value: ColumnRule) {
    do { try apply(value) } catch { self.error = error.localizedDescription }
  }
}
@MainActor final class QueryController: NSViewController, NSTabViewDelegate, NSSplitViewDelegate {
  let document: QueryDocument
  var changed: (() -> Void)?
  private let panes = ResultSplitView()
  private let resultStrip = NSStackView()
  private let stripScroll = NSScrollView()
  private var selectedPageSize = GridPaging.defaultSize
  private let editor: EditorController
  private let resultTabs = NSTabView()
  private let navigationHost = NSStackView()
  private let copyHeadersButton = NSButton()
  private let refreshButton = NSButton()
  private let editDataButton = NSButton(title: "Düzenle", target: nil, action: nil)
  private let previewDataButton = NSButton(title: "Önizle", target: nil, action: nil)
  private let revertDataButton = NSButton(title: "Vazgeç", target: nil, action: nil)
  private let nullDataButton = NSButton(title: "NULL", target: nil, action: nil)
  private var preparingData = false
  private var submittingData = false
  private var dataReview: NSWindowController?
  private let refreshInterval = NSPopUpButton()
  private var refreshTask: Task<Void, Never>?
  deinit { refreshTask?.cancel(); exportJob?.cancel() }
  private let resultPane = NSView()
  private(set) var resultsHidden = false
  private var savedEditorFraction: CGFloat = 0.60
  private let messages = NSTextView()
  private let connectionBadge = NSTextField(labelWithString: "")
  private var editorHeader: NSStackView?
  private let compareModuleButton = NSButton()
  private let submitModuleButton = NSButton()
  private var checkingModuleSubmission = false
  private let position = NSTextField(labelWithString: "Ln 1, Col 1")
  private let summary = NSTextField(labelWithString: "")
  private let actual = NSButton(checkboxWithTitle: "Gerçek plan", target: nil, action: nil)
  private let filter = NSSearchField()
  private let rowLimit = NSPopUpButton()
  private let export = NSPopUpButton(frame: .zero, pullsDown: true)
  private let cancelExport = NSButton(title: "Aktarımı İptal Et", target: nil, action: nil)
  private var exportJob: Task<Void, Never>?
  private var tables: [Int: ResultController] = [:]
  private var plans: [Int: String] = [:]
  private var displayed = Set<Int>()
  private var initialSplitApplied = false
  private var pendingResultUpdate:Task<Void,Never>?
  private var moduleReview: ModuleReviewController?
  private var refreshSelection: Any?
  init(document: QueryDocument) {
    self.document = document
    editor = EditorController(document: document)
    super.init(nibName: nil, bundle: nil)
    document.confirmDiscardResultEdits = { [weak self] in
      guard let self else { return true }
      view.window?.makeFirstResponder(nil)
      guard !submittingData else { return false }
      guard hasDataEdits else { return true }
      let alert = NSAlert(); alert.messageText = "Gönderilmemiş sonuç düzenlemeleri var"
      alert.informativeText = "Devam ederseniz bu yerel değişiklikler silinir. Veritabanına göndermek için Önizle'yi kullanın."
      alert.addButton(withTitle: "Düzenlemeleri Sil ve Devam Et"); alert.addButton(withTitle: "Geri Dön")
      guard alert.runModal() == .alertFirstButtonReturn else { return false }
      for grid in tables.values { grid.discardEdits() }; return true
    }
    document.changed = { [weak self] in
      self?.documentDidChange()
    }
    editor.edited = { [weak self] in self?.changed?() }
    editor.position = { [weak self] line, column in
      self?.position.stringValue = "Ln \(line), Col \(column)"
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func loadView() {
    view = NSView()
    panes.isVertical = false
    panes.dividerStyle = .thin
    panes.delegate = self
    let editorPane = NSView()
    for pane in [view, panes, editorPane, resultPane] {
      pane.wantsLayer = true
      pane.clipsToBounds = true
      pane.layer?.masksToBounds = true
    }
    actual.target = self
    actual.action = #selector(actualChanged)
    actual.font = .systemFont(ofSize: 11)
    position.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
    position.textColor = .tertiaryLabelColor
    connectionBadge.font = .systemFont(ofSize: 11, weight: .semibold)
    connectionBadge.lineBreakMode = .byTruncatingMiddle
    connectionBadge.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    connectionBadge.setAccessibilityIdentifier("queryConnectionBadge")
    let toggle = NSButton(
      image: NSImage(
        systemSymbolName: "rectangle.bottomthird.inset.filled",
        accessibilityDescription: "Sonuçları Göster / Gizle")!, target: self,
      action: #selector(toggleResults))
    toggle.bezelStyle = .inline
    toggle.isBordered = false
    toggle.toolTip = "Sonuçları Göster / Gizle (⌘R)"
    toggle.setAccessibilityIdentifier("toggleResults")
    actual.controlSize = .small
    compareModuleButton.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Farkları Gör")
    compareModuleButton.imagePosition = .imageOnly
    compareModuleButton.target = self
    compareModuleButton.action = #selector(compareModule)
    compareModuleButton.bezelStyle = .inline
    compareModuleButton.isBordered = false
    compareModuleButton.toolTip = "Farkları Gör"
    compareModuleButton.setAccessibilityLabel("Farkları Gör")
    compareModuleButton.setAccessibilityIdentifier("compareModule")
    compareModuleButton.isHidden = document.moduleOriginal == nil
    submitModuleButton.image = NSImage(systemSymbolName:"tray.and.arrow.up",accessibilityDescription:"Veritabanına Gönder")
    submitModuleButton.imagePosition = .imageOnly
    submitModuleButton.target=self;submitModuleButton.action=#selector(applyModule)
    submitModuleButton.bezelStyle = .inline;submitModuleButton.isBordered=false
    submitModuleButton.toolTip="Değişiklikleri incele ve veritabanına gönder…"
    submitModuleButton.setAccessibilityLabel("Veritabanına Gönder")
    submitModuleButton.setAccessibilityIdentifier("submitModule")
    submitModuleButton.isHidden=document.moduleOriginal == nil
    submitModuleButton.isEnabled=document.canSubmitModule
    let header = NSStackView(views: [connectionBadge, NSView(), compareModuleButton, submitModuleButton, actual, position, toggle])
    header.spacing = 10
    header.wantsLayer = true
    editorHeader = header
    header.edgeInsets = NSEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)
    editorPane.addSubview(header)
    editorPane.addSubview(editor.surface)
    header.translatesAutoresizingMaskIntoConstraints = false
    editor.surface.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor),
      header.topAnchor.constraint(equalTo: editorPane.topAnchor),
      header.heightAnchor.constraint(equalToConstant: 28),
      editor.surface.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor),
      editor.surface.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor),
      editor.surface.topAnchor.constraint(equalTo: header.bottomAnchor),
      editor.surface.bottomAnchor.constraint(equalTo: editorPane.bottomAnchor),
    ])
    resultTabs.delegate = self
    resultTabs.tabViewType = .noTabsNoBorder
    resultTabs.tabViewType = .noTabsNoBorder
    resultTabs.setAccessibilityIdentifier("resultSelector")
    refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Sonuçları yenile")
    refreshButton.bezelStyle = .inline
    refreshButton.isBordered = false
    refreshButton.target = self
    refreshButton.action = #selector(refreshResults)
    refreshButton.toolTip = "Son çalıştırılan SELECT sorgusunu yenile"
    refreshButton.setAccessibilityIdentifier("refreshResults")
    refreshInterval.addItems(withTitles: ["Kapalı", "5 sn", "10 sn", "30 sn", "60 sn", "5 dk"])
    for item in refreshInterval.itemArray { item.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil) }
    refreshInterval.controlSize = .small
    refreshInterval.widthAnchor.constraint(equalToConstant: 90).isActive = true
    refreshInterval.target = self
    refreshInterval.action = #selector(setRefreshInterval)
    refreshInterval.setAccessibilityLabel("Otomatik yenileme süresi")
    messages.isEditable = false
    messages.isSelectable = true
    messages.font = StudioTheme.codeFont
    messages.textContainerInset = NSSize(width: 12, height: 10)
    let messageScroll = NSScrollView()
    messageScroll.documentView = messages
    messageScroll.hasVerticalScroller = true
    messages.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
    messages.autoresizingMask = [.width]
    messages.isVerticallyResizable = true
    let messageItem = NSTabViewItem(identifier: "messages")
    messageItem.label = "Messages"
    messageItem.view = messageScroll
    resultTabs.addTabViewItem(messageItem)
    filter.placeholderString = "Yüklenen sonuçlarda filtrele"
    filter.sendsSearchStringImmediately = true
    filter.target = self
    filter.action = #selector(filterChanged)
    export.addItems(withTitles: [
      "Dışa Aktar", "Geçerli sayfa · CSV…", "Geçerli sayfa · JSON…", "Tüm yüklenen · CSV…",
      "Tüm yüklenen · JSON…",
    ])
    export.item(at: 0)?.title = ""
    export.item(at: 0)?.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Sonuçları dışa aktar")
    export.toolTip = "Görünen veya tüm yüklenen sonuçları CSV / JSON olarak dışa aktar"
    export.widthAnchor.constraint(equalToConstant: 38).isActive = true
    configurePageMenu()
    rowLimit.controlSize = .small
    rowLimit.target = self
    rowLimit.action = #selector(changeRowLimit)
    rowLimit.toolTip = "Page Size · Sayfada gösterilecek satırlar. All yalnızca yüklenen sonuçları kapsar."
    rowLimit.setAccessibilityLabel("Page Size")
    cancelExport.title = ""
    cancelExport.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: "Dışa aktarmayı iptal et")
    cancelExport.toolTip = "Devam eden dışa aktarmayı iptal et"
    cancelExport.target = self
    cancelExport.action = #selector(stopExport)
    cancelExport.controlSize = .small
    cancelExport.isHidden = true
    export.target = self
    export.action = #selector(exportResult(_:))
    summary.font = .systemFont(ofSize: 11)
    summary.textColor = .secondaryLabelColor
    let resultHeader = NSStackView(views: [
      navigationHost, refreshButton, refreshInterval, rowLimit, copyHeadersButton, export, cancelExport, editDataButton, previewDataButton, revertDataButton, nullDataButton, NSView(), filter,
    ])
    for (button, icon, action) in [(editDataButton, "pencil", #selector(beginDataEditing)), (previewDataButton, "doc.text.magnifyingglass", #selector(previewDataEditing)), (revertDataButton, "arrow.uturn.backward", #selector(revertDataEditing)), (nullDataButton, "nosign", #selector(nullDataEditing))] {
      button.target = self; button.action = action; button.controlSize = .small
      button.image = NSImage(systemSymbolName: icon, accessibilityDescription: button.title)
      button.imagePosition = .imageLeading; button.bezelStyle = .rounded
      button.contentTintColor = button === revertDataButton || button === nullDataButton ? .systemOrange : .controlAccentColor
    }
    editDataButton.toolTip = "Kaynağı doğrula, hücreleri çift tıklayarak yerelde düzenle. Göndermeden önce SQL önizlemesi zorunludur."
    previewDataButton.toolTip = "Bekleyen UPDATE komutlarını incele ve onaylayarak gönder"
    resultHeader.setAccessibilityIdentifier("gridToolbar")
    navigationHost.spacing = 0
    copyHeadersButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Başlıklarla kopyala")
    copyHeadersButton.bezelStyle = .inline; copyHeadersButton.isBordered = false
    copyHeadersButton.target = self; copyHeadersButton.action = #selector(copyHeadersSelection)
    updateShortcutHints()
    NotificationCenter.default.addObserver(self, selector: #selector(updateShortcutHints), name: GridShortcuts.changed, object: nil)
    filter.toolTip = "Yalnızca yüklenen sonuçlarda ara; sunucuya sorgu göndermez"
    refreshInterval.toolTip = "Son başarılı SELECT için otomatik yenileme süresi"
    StudioTheme.surface(resultHeader)
    resultHeader.edgeInsets = NSEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)
    resultHeader.spacing = 6
    filter.controlSize = .small
    export.controlSize = .small
    summary.lineBreakMode = .byTruncatingTail
    summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    filter.widthAnchor.constraint(equalToConstant: 140).isActive = true
    resultStrip.spacing = 2
    resultStrip.edgeInsets = NSEdgeInsets(top: 2,left: 6,bottom: 2,right: 6)
    resultStrip.setAccessibilityIdentifier("resultTabStrip")
    stripScroll.documentView = resultStrip
    stripScroll.hasHorizontalScroller = true; stripScroll.autohidesScrollers = true
    resultStrip.translatesAutoresizingMaskIntoConstraints = false
    resultPane.addSubview(stripScroll)
    stripScroll.translatesAutoresizingMaskIntoConstraints = false
    resultPane.addSubview(resultHeader)
    resultPane.addSubview(resultTabs)
    resultHeader.translatesAutoresizingMaskIntoConstraints = false
    resultTabs.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      resultHeader.leadingAnchor.constraint(equalTo: resultPane.leadingAnchor),
      resultHeader.trailingAnchor.constraint(equalTo: resultPane.trailingAnchor),
      stripScroll.leadingAnchor.constraint(equalTo: resultPane.leadingAnchor),
      stripScroll.trailingAnchor.constraint(equalTo: resultPane.trailingAnchor),
      stripScroll.topAnchor.constraint(equalTo: resultPane.topAnchor),
      stripScroll.heightAnchor.constraint(equalToConstant: 28),
      resultStrip.leadingAnchor.constraint(equalTo: stripScroll.contentView.leadingAnchor),
      resultStrip.topAnchor.constraint(equalTo: stripScroll.contentView.topAnchor),
      resultStrip.heightAnchor.constraint(equalToConstant: 28),
      resultHeader.topAnchor.constraint(equalTo: stripScroll.bottomAnchor),
      resultHeader.heightAnchor.constraint(equalToConstant: 34),
      resultTabs.leadingAnchor.constraint(equalTo: resultPane.leadingAnchor, constant: 2),
      resultTabs.trailingAnchor.constraint(equalTo: resultPane.trailingAnchor, constant: -2),
      resultTabs.topAnchor.constraint(equalTo: resultHeader.bottomAnchor),
      resultTabs.bottomAnchor.constraint(equalTo: resultPane.bottomAnchor),
    ])
    panes.addArrangedSubview(editorPane)
    panes.addArrangedSubview(resultPane)
    embed(panes, in: view)
    StudioTheme.decorate(view)
    NotificationCenter.default.addObserver(self, selector: #selector(refreshTheme), name: StudioTheme.changed, object: nil)
    update()
  }
  override func viewDidLayout() {
    super.viewDidLayout()
    if !initialSplitApplied && !resultsHidden && panes.bounds.height > 360 {
      initialSplitApplied = true
      panes.setPosition(panes.bounds.height * 0.60, ofDividerAt: 0)
    }
    editor.resizeToViewport()

  }
  @objc func toggleResults() {
    guard isViewLoaded else { return }
    if !resultsHidden && panes.bounds.height > 0 {
      savedEditorFraction = panes.subviews[0].frame.height / panes.bounds.height
    }
    resultsHidden.toggle()
    panes.hideDivider = resultsHidden
    if resultsHidden { resultPane.removeFromSuperview() }
    else { panes.addArrangedSubview(resultPane) }
    panes.adjustSubviews()
    panes.needsDisplay = true
    view.needsDisplay = true
    editor.scroll.needsDisplay = true
    if !resultsHidden {
      panes.setPosition(panes.bounds.height * savedEditorFraction, ofDividerAt: 0)
    }
    editor.resizeToViewport()
  }
  @objc private func updateShortcutHints() { copyHeadersButton.toolTip = "Seçili hücreleri veya satırları kolon başlıklarıyla kopyala (\(GridShortcuts.headersLabel))" }
  @objc private func copyHeadersSelection() {
    guard let index = (resultTabs.selectedTabViewItem?.identifier as? NSNumber)?.intValue else { return }
    tables[index]?.copySelectionData(includeHeaders: true)
  }
  func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) { syncNavigation(); syncResultStrip() }
  private func syncResultStrip() {
    if resultStrip.arrangedSubviews.count != resultTabs.numberOfTabViewItems {
      for child in resultStrip.arrangedSubviews { resultStrip.removeArrangedSubview(child); child.removeFromSuperview() }
      for index in resultTabs.tabViewItems.indices {
        let button = NSButton(title: "",target: self,action: #selector(selectResultTab(_:)))
        button.tag = index; button.bezelStyle = .inline; button.isBordered = false; button.font = StudioTheme.uiFont
        resultStrip.addArrangedSubview(button)
      }
    }
    for (index,item) in resultTabs.tabViewItems.enumerated() {
      guard let button = resultStrip.arrangedSubviews[index] as? NSButton else { continue }
      if button.title != item.label { button.title = item.label }
      button.contentTintColor = item === resultTabs.selectedTabViewItem ? StudioTheme.accent : StudioTheme.muted
      button.state = item === resultTabs.selectedTabViewItem ? .on : .off
      button.setAccessibilityValue(button.state == .on ? "Seçili" : "")
    }
  }
  @objc private func selectResultTab(_ button: NSButton) { resultTabs.selectTabViewItem(at: button.tag) }
  private func syncNavigation() {
    let index = (resultTabs.selectedTabViewItem?.identifier as? NSNumber)?.intValue
    let toolbar = index.flatMap { tables[$0]?.toolbar }
    if navigationHost.arrangedSubviews.first !== toolbar {
      for child in navigationHost.arrangedSubviews { navigationHost.removeArrangedSubview(child); child.removeFromSuperview() }
      if let toolbar { navigationHost.addArrangedSubview(toolbar) }
    }
    export.isEnabled = toolbar != nil && exportJob == nil
    copyHeadersButton.isEnabled = toolbar != nil
    filter.isEnabled = toolbar != nil
    syncDataActions()
  }
  private var selectedGrid: ResultController? {
    guard let index = (resultTabs.selectedTabViewItem?.identifier as? NSNumber)?.intValue else { return nil }
    return tables[index]
  }
  private var hasDataEdits: Bool { tables.values.contains { !$0.pendingEdits.isEmpty } }
  private func syncDataActions() {
    let grid = selectedGrid
    let safe = document.canRefresh && !preparingData && !submittingData
    editDataButton.title = grid?.editDefinition == nil ? "Düzenle" : "Düzenleme Açık"
    editDataButton.isEnabled = safe && grid != nil && grid?.editDefinition == nil && document.results.count == 1 && !document.partial
    previewDataButton.isEnabled = safe && !(grid?.pendingEdits.isEmpty ?? true)
    previewDataButton.title = "Önizle (\(grid?.pendingEdits.count ?? 0))"
    revertDataButton.isEnabled = grid?.editDefinition != nil && !submittingData
    nullDataButton.isEnabled = safe && grid?.editDefinition != nil
  }
  private func dataError(_ error: Error) {
    let alert = NSAlert(); alert.messageText = "Veri düzenleme"; alert.informativeText = error.localizedDescription
    if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
  }
  @objc private func beginDataEditing() {
    guard let grid = selectedGrid, document.canRefresh, !document.partial, document.results.count == 1, let sql = document.lastExecutedSQL else { return }
    let generation = document.resultGeneration, db = document.database, server = document.server
    let serverGeneration = server.generation
    preparingData = true; syncDataActions()
    // Unattended refresh would discard the staged copy.
    refreshTask?.cancel(); refreshTask = nil; refreshInterval.selectItem(at: 0)
    Task { [weak self, weak grid] in
      guard let self, let grid else { return }
      defer { preparingData = false; syncDataActions() }
      do {
        let source = try ResultEditSource.decode(try await server.catalog(ResultEditSource.metadata(sql), database: db), fields: grid.result.fields, database: db)
        let identity = try await server.catalog("SELECT object_id FROM sys.tables WHERE schema_id=SCHEMA_ID(\(SQL.literal(source.schema))) AND name=\(SQL.literal(source.table));", database: db)
        guard !identity.partial, let id = identity.results.first?.values.first?.first.flatMap({ $0 }).flatMap(Int.init) else { throw SQLFailure("Kaynak bir yerel kullanıcı tablosu değil.") }
        let table = try source.projected(ObjectMetadata.decode(try await server.catalog(ObjectMetadata.table(id), database: db), schema: source.schema, name: source.table))
        guard document.server === server, server.generation == serverGeneration, document.resultGeneration == generation, document.database == db, document.canRefresh else { throw SQLFailure("Sonuç değişti; güncel sonuçta yeniden deneyin.") }
        grid.editObjectID = id
        grid.editDefinition = table
        grid.editingAllowed = { [weak self] in self?.document.server === server && server.generation == serverGeneration && self?.document.resultGeneration == generation && self?.document.canRefresh == true && self?.submittingData == false }
        grid.editsChanged = { [weak self] in self?.syncDataActions() }
        grid.table.reloadData()
      } catch { dataError(error) }
    }
  }
  @objc private func nullDataEditing() { selectedGrid?.setSelectedNull() }
  @objc private func revertDataEditing() {
    guard let grid = selectedGrid, !submittingData else { return }
    view.window?.makeFirstResponder(nil)
    if grid.pendingEdits.isEmpty { grid.discardEdits(); return }
    let alert = NSAlert(); alert.messageText = "Bekleyen düzenlemelerden vazgeçilsin mi?"; alert.addButton(withTitle: "Vazgeç"); alert.addButton(withTitle: "Düzenlemeye Devam Et")
    if let window = view.window { alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { grid.discardEdits() } } }
  }
  @objc private func previewDataEditing() {
    view.window?.makeFirstResponder(nil)
    guard let grid = selectedGrid, document.canRefresh, !submittingData else { return }
    do {
      let sql = try grid.pendingSQL(), generation = document.resultGeneration, db = document.database
      let server = document.server, serverGeneration = document.server.generation
      let panel = DataChangesPreview(sql: sql, target: document.server.profile.name + " / " + db, submit: { [weak self, weak grid] in
        guard let self, let grid else { throw SQLFailure("Sorgu kapatıldı.") }
        guard !submittingData, document.server === server, server.generation == serverGeneration, server.online, document.canRefresh, document.database == db, document.resultGeneration == generation, try grid.pendingSQL() == sql else { throw SQLFailure("Önizlemeden sonra sonuç veya düzenlemeler değişti. Yeniden önizleyin.") }
        submittingData = true; syncDataActions()
        defer { submittingData = false; syncDataActions() }
        guard let definition = grid.editDefinition, let objectID = grid.editObjectID else { throw SQLFailure("Kaynak kimliği kayboldu.") }
        let current = try ObjectMetadata.decode(try await server.catalog(ObjectMetadata.table(objectID), database: db), schema: definition.schema, name: definition.name)
        guard current.primaryKey == definition.primaryKey, Set(current.columns.map(\.id)) == Set(definition.columns.map(\.id)), current.columns.allSatisfy({ c in definition.columns.contains(c) }) else { throw SQLFailure("Tablo yapısı değişmiş; güncel sonucu yeniden yükleyin.") }
        guard document.server === server, server.generation == serverGeneration, server.online, document.canRefresh, document.database == db, document.resultGeneration == generation, try grid.pendingSQL() == sql else { throw SQLFailure("Önizleme artık güncel değil.") }
        // Dedicated connection: commits cannot affect the console's transaction/session.
        let connection = ODBCConnection(); var profile = server.profile; profile.database = db
        do {
          try await connection.connect(profile, password: server.password)
          let output = try await connection.execute(sql)
          await connection.disconnect()
          guard !output.partial else { throw SQLFailure("Sunucu yanıtı kısmi; sonucu yenileyip kontrol edin, aynı değişiklikleri tekrar göndermeyin.") }
          grid.discardEdits()
          submittingData = false
          if document.resultGeneration == generation && document.database == db && document.canRefresh { refreshResults() }
        } catch { await connection.disconnect(); throw error }
      })
      let window = NSWindow(contentViewController: NSHostingController(rootView: panel)); window.title = "UPDATE Önizlemesi"; window.setContentSize(NSSize(width: 1000, height: 720)); window.styleMask = [.titled, .closable, .resizable]; window.minSize = NSSize(width: 760, height: 520)
      let controller = DataReviewWindowController(window: window); controller.canClose = { [weak self] in self?.submittingData != true }; window.delegate = controller; dataReview = controller; controller.showWindow(nil)
    } catch { dataError(error) }
  }
  @objc private func refreshResults() {
    guard document.canRefresh, let sql = document.lastExecutedSQL else { return }
    refreshSelection = resultTabs.selectedTabViewItem?.identifier
    document.execute(override: sql, repeatRead: true)
  }
  @objc private func setRefreshInterval() {
    refreshTask?.cancel()
    let seconds = [0, 5, 10, 30, 60, 300][refreshInterval.indexOfSelectedItem]
    guard seconds > 0, document.canRefresh, !tables.values.contains(where: { $0.editDefinition != nil }) else { refreshInterval.selectItem(at: 0); return }
    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        guard let self else { return }
        if document.busy { continue }
        guard document.canRefresh else { refreshInterval.selectItem(at: 0); return }
        refreshResults()
      }
    }
  }
  private func syncResultSelector() {
    refreshButton.isEnabled = document.canRefresh
    refreshInterval.isEnabled = (document.canRefresh || document.busy) && !tables.values.contains(where: { $0.editDefinition != nil })
    if !document.busy && !document.canRefresh { refreshTask?.cancel(); refreshInterval.selectItem(at: 0) }
  }
  func splitView(
    _ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int
  ) -> CGFloat { max(170, proposed) }
  func splitView(
    _ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int
  ) -> CGFloat {
    resultsHidden ? splitView.bounds.height : min(splitView.bounds.height - 120, proposed)
  }
  func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
    subview === resultPane
  }
  private func embed(_ child: NSView, in parent: NSView) {
    parent.addSubview(child)
    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
      child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
      child.topAnchor.constraint(equalTo: parent.topAnchor),
      child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])
  }
  func focusEditor() { view.window?.makeFirstResponder(editor.editor) }
  func setText() { editor.setText() }
  func format() { editor.replaceText(SQLServerKit.TSQL.format(document.sql)) }
  @objc private func refreshTheme() {
    StudioTheme.decorate(view)
    for controller in tables.values {
      let selected = controller.table.selectedRowIndexes
      controller.table.reloadData()
      controller.table.selectRowIndexes(selected, byExtendingSelection: false)
    }
    updateConnectionAppearance()
  }
  func updateConnectionAppearance() {
    guard isViewLoaded else { return }
    let profile = document.server.profile
    let appearance = profile.appearance
    let badge = appearance?.badge ?? ""
    connectionBadge.stringValue =
      (badge.isEmpty ? "" : "[\(badge)] ")
      + "\(profile.name)"
    connectionBadge.toolTip = "\(connectionBadge.stringValue) · \(profile.host),\(profile.port) · \(document.database)"
    editorHeader?.identifier = NSUserInterfaceItemIdentifier("connectionAccent")
    editorHeader?.layer?.backgroundColor =
      appearance?.isMarked == true
      ? appearance!.color.withAlphaComponent(0.12).cgColor : StudioTheme.panel.cgColor
  }
  private func documentDidChange() {
    guard document.state == .running else {
      pendingResultUpdate?.cancel();pendingResultUpdate=nil
      update();changed?();return
    }
    guard pendingResultUpdate == nil else {return}
    pendingResultUpdate=Task { [weak self] in
      do {try await Task.sleep(for:.milliseconds(50))} catch {return}
      guard let self else {return}
      pendingResultUpdate=nil;update();changed?()
    }
  }
  func update() {
    compareModuleButton.isHidden = document.moduleOriginal == nil
    compareModuleButton.isEnabled = !document.busy
    submitModuleButton.isHidden = document.moduleOriginal == nil
    submitModuleButton.isEnabled = document.canSubmitModule && !checkingModuleSubmission
    guard isViewLoaded else { return }
    updateConnectionAppearance()
    syncDataActions()
    actual.state = document.actualPlan ? .on : .off
    actual.isEnabled = !document.busy
    rowLimit.isEnabled = !document.busy
    if document.results.isEmpty && !displayed.isEmpty && !(document.repeating && document.busy) {
      for item in resultTabs.tabViewItems where item.identifier is NSNumber {
        resultTabs.removeTabViewItem(item)
      }
      for child in children { child.removeFromParent() }
      tables = [:]
      displayed = []
      plans = [:]
    }
    for (index, result) in document.results.enumerated() where !result.fields.isEmpty {
      if let xml = result.values.first?.first.flatMap({ $0 }), xml.contains("<ShowPlanXML"),
        plans[index] == nil, let plan = try? ExecutionPlan.parse(xml)
      {
        let wasSelected =
          (resultTabs.selectedTabViewItem?.identifier as? NSNumber)?.intValue == index
        if let existing = resultTabs.tabViewItems.first(where: {
          ($0.identifier as? NSNumber)?.intValue == index
        }) {
          resultTabs.removeTabViewItem(existing)
          tables.removeValue(forKey: index)?.removeFromParent()
        }
        let controller = PlanController(plan: plan)
        let item = NSTabViewItem(identifier: NSNumber(value: index))
        item.label = "Execution Plan \(index + 1)"
        item.view = controller.view
        addChild(controller)
        resultTabs.insertTabViewItem(item, at: max(0, resultTabs.numberOfTabViewItems - 1))
        plans[index] = xml
        displayed.insert(index)
        if wasSelected || displayed.count == 1 { resultTabs.selectTabViewItem(item) }
      } else if plans[index] == nil {
        let controller: ResultController
        if let existing = tables[index] {
          controller = existing
        } else {
          controller = ResultController()
          controller.toolbarHosted = true
          controller.setPageSize(selectedPageSize)
          controller.clearSearch = { [weak self] in
            self?.filter.stringValue = ""
            self?.filterChanged()
          }
          tables[index] = controller
          addChild(controller)
          let item = NSTabViewItem(identifier: NSNumber(value: index))
          item.label = "Results \(index + 1)"
          item.view = controller.view
          resultTabs.insertTabViewItem(item, at: max(0, resultTabs.numberOfTabViewItems - 1))
          displayed.insert(index)
          if displayed.count == 1 { resultTabs.selectTabViewItem(item) }
        }
        controller.update(result, generation: document.resultGeneration)
        controller.partial = document.partial
        controller.filter = filter.stringValue
        resultTabs.tabViewItems.first(where: { ($0.identifier as? NSNumber)?.intValue == index })?
          .label = "Results \(index + 1) (\(result.values.count.formatted()))"
      }
    }
    if !document.busy, document.repeating {
      let removed = tables.keys.filter { !document.results.indices.contains($0) }
      for index in removed {
        if let item = resultTabs.tabViewItems.first(where: { ($0.identifier as? NSNumber)?.intValue == index }) { resultTabs.removeTabViewItem(item) }
        tables.removeValue(forKey: index)?.removeFromParent()
        displayed.remove(index)
      }
      if let identifier = refreshSelection { resultTabs.selectTabViewItem(withIdentifier: identifier) }
      refreshSelection = nil
    }
    syncNavigation()
    syncResultStrip()
    syncResultSelector()
    if messages.string != document.messages {messages.string = document.messages}
    summary.stringValue =
      document.state == .running
      ? "Sonuçlar okunuyor · \(document.rowCount.formatted()) satır"
      : "\(document.rowCount.formatted()) satır\(document.partial ? " · KISMİ" : "")"
    if document.state == .ready && document.results.isEmpty {
      resultTabs.selectTabViewItem(withIdentifier: "messages")
      syncResultSelector()
    }
  }
  private func modulePreview() {
    guard !checkingModuleSubmission,moduleReview == nil,let original=document.moduleOriginal,let parent=view.window else {return}
    let sql=document.sql,db=document.database,baseline=document.moduleInitialSQL ?? ModuleEditing.alter(original)
    moduleReview=ModuleReviewController(parent:parent,title:"\(document.server.profile.name)  /  \(db)  /  \(document.title)",original:baseline,edited:sql,canApply:document.canSubmitModule,approved:{ [weak self] in
      self?.submitModule(sql:sql,database:db,original:original)
    },finished:{ [weak self] in self?.moduleReview=nil })
  }
  @objc private func compareModule() {modulePreview()}
  @objc private func applyModule() {
    guard document.transactionCount == 0 else {
      let alert=NSAlert();alert.messageText="Önce COMMIT veya ROLLBACK çalıştırın.";alert.runModal();return
    }
    guard document.canSubmitModule else {return}
    modulePreview()
  }
  private func submitModule(sql:String,database db:String,original:String) {
    guard let object=document.moduleObjectID,document.objectEditorKey?.database == db,document.sql == sql,document.database == db,document.canSubmitModule,!checkingModuleSubmission else {return}
    checkingModuleSubmission=true;update()
    Task { [weak self] in
      guard let self else {return}
      defer {checkingModuleSubmission=false;update()}
      do {
        let output=try await document.server.catalog(Catalog.definition(object),database:db)
        guard !output.partial,let current=output.results.first?.values.first?.first,let current,current == original else {
          throw SQLFailure("Nesne sunucuda değişmiş veya kaldırılmış. Değişiklik gönderilmedi; sunucudaki güncel tanımı ayrı sekmede karşılaştırın.")
        }
        guard document.sql == sql,document.database == db,document.canSubmitModule,document.moduleOriginal == original else {return}
        let targetDocument=document
        document.moduleApplied={ [weak targetDocument] in
          guard let doc=targetDocument,doc.database == db else {return}
          // SQL Server retains the executed ALTER definition. Advance exactly the submitted
          // snapshot; edits made during execution must remain pending.
          doc.acceptAppliedModule(sql:sql,original:sql)
          Task { [weak doc] in
            guard let doc else {return}
            if let result=try? await doc.server.catalog(Catalog.definition(object),database:db),!result.partial,
              let current=result.results.first?.values.first?.first,let current,doc.moduleInitialSQL == sql,doc.database == db {doc.moduleOriginal=current;doc.changed?()}
            await doc.loadSymbols(force:true)
          }
        }
        document.applyingModule=true;document.execute(override:sql)
      } catch {
        let alert=NSAlert();alert.messageText="Değişiklik uygulanamadı";alert.informativeText=error.localizedDescription;alert.runModal()
      }
    }
  }
  @objc private func actualChanged() { document.actualPlan = actual.state == .on }
  @objc private func filterChanged() {
    for table in tables.values { table.filter = filter.stringValue }
  }
  private func configurePageMenu() {
    rowLimit.removeAllItems()
    for size in GridPaging.choices {
      rowLimit.addItem(withTitle: size == 0 ? "All" : String(size.formatted()))
      rowLimit.lastItem?.tag = size
    }
    rowLimit.addItem(withTitle: "Custom…"); rowLimit.lastItem?.tag = -1
    rowLimit.menu?.addItem(.separator())
    rowLimit.addItem(withTitle: "Set as Default"); rowLimit.lastItem?.tag = -2
    let cap = NSMenuItem(title: "Sorgu okuma sınırı", action: nil, keyEquivalent: "")
    cap.tag = -3
    let submenu = NSMenu()
    for size in [50_000,1_000_000,5_000_000] {
      let item = submenu.addItem(withTitle: size.formatted(), action: #selector(changeReadLimit(_:)), keyEquivalent: "")
      item.tag = size; item.target = self
      item.state = size == document.limits.rows ? .on : .off
    }
    cap.submenu = submenu; rowLimit.menu?.addItem(.separator()); rowLimit.menu?.addItem(cap)
    syncPageMenu()
  }
  private func syncPageMenu() {
    for item in rowLimit.itemArray where !item.isSeparatorItem && item.submenu == nil && item.tag >= 0 && GridPaging.choices.contains(item.tag) {
      item.title = (item.tag == 0 ? "All" : item.tag.formatted()) + (item.tag == GridPaging.defaultSize ? " · Default" : "")
    }
    if let item = rowLimit.itemArray.first(where: { $0.tag == selectedPageSize && $0.tag >= 0 }) { rowLimit.select(item) }
    else { rowLimit.itemArray.first(where: { $0.tag == -1 })?.title = "Custom: \(selectedPageSize.formatted())…"; rowLimit.selectItem(withTag: -1) }
  }
  @objc private func changeReadLimit(_ item: NSMenuItem) {
    guard !document.busy else { return }
    document.limits.rows = item.tag
    document.limits.totalBytes = item.tag == 50_000 ? 67_108_864 : 2_147_483_648
    document.limits.timeout = item.tag == 50_000 ? 60 : 600
    configurePageMenu()
  }
  func applyPageSize(_ value: Int, makeDefault: Bool = false) {
    guard (0...1_000_000).contains(value) else { return }
    selectedPageSize = value
    if makeDefault { UserDefaults.standard.set(value, forKey: "gridDefaultPageSize") }
    for table in tables.values { table.setPageSize(value) }
    syncPageMenu()
  }
  @objc private func changeRowLimit() {
    let value = rowLimit.selectedItem?.tag ?? 500
    if value == -2 { applyPageSize(selectedPageSize, makeDefault: true); return }
    if value == -1 {
      let alert = NSAlert(); alert.messageText = "Custom Page Size"
      alert.informativeText = "Sayfa başına 1–1.000.000 satır girin."
      let field = NSTextField(string: String(max(1,selectedPageSize))); field.frame = NSRect(x:0,y:0,width:220,height:26)
      alert.accessoryView = field; alert.addButton(withTitle: "Uygula"); alert.addButton(withTitle: "Vazgeç")
      if alert.runModal() == .alertFirstButtonReturn, let size = Int(field.stringValue), (1...1_000_000).contains(size) { applyPageSize(size) }
      else { syncPageMenu() }
    } else if value >= 0 { applyPageSize(value) }
  }
  @objc private func stopExport() { exportJob?.cancel() }
  @objc private func exportResult(_ sender: NSPopUpButton) {
    let choice = sender.indexOfSelectedItem
    sender.selectItem(at: 0)
    guard choice > 0, exportJob == nil,
      let index = (resultTabs.selectedTabViewItem?.identifier as? NSNumber)?.intValue,
      document.results.indices.contains(index), let controller = tables[index]
    else { return }
    guard !controller.isProcessing else {
      let a = NSAlert()
      a.messageText = "Önce filtreleme veya sıralamanın tamamlanmasını bekleyin."
      a.runModal()
      return
    }
    let rows = controller.result
    let indices = choice <= 2 ? controller.pageExportIndices : nil
    let json = choice == 2 || choice == 4
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Results.\(json ? "json" : "csv")"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    cancelExport.isHidden = false
    export.isEnabled = false
    exportJob = Task { [weak self] in
      let worker = Task.detached(priority: .utility) {
        try ResultFileExport.write(rows, indices: indices, json: json, to: url)
      }
      do {
        try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
      } catch is CancellationError {} catch { NSAlert(error: error).runModal() }
      self?.cancelExport.isHidden = true
      self?.exportJob = nil
      self?.syncNavigation()
    }
  }

}
@MainActor private final class PlanNode: NSObject {
  let operation: PlanOperation
  var children: [PlanNode] = []
  init(_ operation: PlanOperation) { self.operation = operation }
}
@MainActor
final class PlanController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
  private let plan: ExecutionPlan
  private var roots: [PlanNode] = []
  private let tree = NSOutlineView()
  init(plan: ExecutionPlan) {
    self.plan = plan
    super.init(nibName: nil, bundle: nil)
    var stack: [PlanNode] = []
    for operation in plan.operations {
      let node = PlanNode(operation)
      while stack.count > operation.depth { stack.removeLast() }
      if let parent = stack.last { parent.children.append(node) } else { roots.append(node) }
      stack.append(node)
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func loadView() {
    view = NSView()
    tree.dataSource = self
    tree.delegate = self
    tree.rowHeight = 28
    tree.backgroundColor = StudioTheme.canvas
    tree.gridColor = StudioTheme.border
    tree.gridStyleMask = [.solidHorizontalGridLineMask]
    tree.usesAlternatingRowBackgroundColors = false
    for (id, title, width) in [
      ("operation", "Operator", 330.0), ("estimated", "Estimated Rows", 140.0),
      ("actual", "Actual Rows", 120.0), ("cost", "Subtree Cost", 130.0),
    ] {
      let column = NSTableColumn(identifier: .init(id))
      let header = FilterHeaderCell(textCell: title)
      header.showsFilter = false
      header.typeSymbol = id == "operation" ? "point.3.connected.trianglepath.dotted" : "number"
      column.headerCell = header
      column.title = title
      column.width = width
      tree.addTableColumn(column)
    }
    tree.outlineTableColumn = tree.tableColumns[0]
    let scroll = NSScrollView()
    scroll.documentView = tree
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    let label = NSTextField(
      labelWithString: plan.operations.isEmpty
        ? "SQL Server Execution Plan — Bu sorgu için operatör yok" : "SQL Server Execution Plan")
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    let button = NSButton(title: "Save .sqlplan…", target: self, action: #selector(save))
    let header = NSStackView(views: [label, NSView(), button])
    StudioTheme.surface(header)
    header.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
    let stack = NSStackView(views: [header, scroll])
    stack.orientation = .vertical
    stack.distribution = .fill
    stack.spacing = 0
    view.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: view.topAnchor),
      stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      header.widthAnchor.constraint(equalTo: stack.widthAnchor),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
    tree.reloadData()
    tree.expandItem(nil, expandChildren: true)
  }
  func outlineView(_ view: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    (item as? PlanNode)?.children.count ?? roots.count
  }
  func outlineView(_ view: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    ((item as? PlanNode)?.children ?? roots)[index]
  }
  func outlineView(_ view: NSOutlineView, isItemExpandable item: Any) -> Bool {
    !((item as? PlanNode)?.children.isEmpty ?? true)
  }
  func outlineView(_ view: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
    guard let node = item as? PlanNode else { return nil }
    let value: String
    switch column?.identifier.rawValue {
    case "estimated": value = node.operation.estimatedRows
    case "actual": value = node.operation.actualRows?.formatted() ?? "—"
    case "cost": value = node.operation.cost
    default: value = (node.operation.warnings.isEmpty ? "" : "⚠ ") + node.operation.physical
    }
    let text = NSTextField(labelWithString: value)
    text.font = StudioTheme.uiFont
    text.toolTip = ([node.operation.logical] + node.operation.warnings).joined(separator: "\n")
    return text
  }
  func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { StudioRowView() }
  @objc private func save() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Query.sqlplan"
    if panel.runModal() == .OK, let url = panel.url {
      do { try plan.xml.write(to: url, atomically: true, encoding: .utf8) } catch {
        NSAlert(error: error).runModal()
      }
    }
  }
}


struct DataChangesPreview: View {
  let sql: String
  let target: String
  let submit: () async throws -> Void
  @State private var sending = false
  @State private var completed = false
  @State private var message = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      StudioPanelHeading(title: "Değişiklikleri İncele", icon: "doc.text.magnifyingglass", subtitle: target)
      Text("Aşağıdaki SQL onayınızla tek transaction içinde gönderilir. Satır başka biri tarafından değiştirilmişse tüm işlem geri alınır.").foregroundStyle(.secondary)
      SQLReadOnlyPreview(sql: sql)
      if !message.isEmpty { Text(message).foregroundStyle(completed ? Color.green : Color.red).textSelection(.enabled) }
      HStack {
        if sending { ProgressView().controlSize(.small) }
        Spacer()
        StudioActionButton(completed ? "Gönderildi" : "Onayla ve Veritabanına Gönder", icon: completed ? "checkmark.circle" : "paperplane", tint: .green) {
          sending = true
          Task {
            defer { sending = false }
            do { try await submit(); completed = true; message = "Değişiklikler gönderildi. Sonuç yeniden yükleniyor." }
            catch { message = error.localizedDescription + " Bağlantı hatasında işlem tamamlanmış olabilir; yeniden göndermeden önce sonucu kontrol edin." }
          }
        }.buttonStyle(StudioPrimaryButton()).disabled(sending || completed || !message.isEmpty)
      }
    }.padding(24).studioPanel()
  }
}

@MainActor private final class DataReviewWindowController: NSWindowController, NSWindowDelegate {
  var canClose: (() -> Bool)?
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard canClose?() != false else { NSSound.beep(); return false }
    return true
  }
}
