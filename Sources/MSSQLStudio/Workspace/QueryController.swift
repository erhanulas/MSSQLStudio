import AppKit
import SQLServerKit
import SwiftUI
@MainActor final class QueryController: NSViewController, NSTabViewDelegate, NSSplitViewDelegate {
  let document: QueryDocument
  var changed: (() -> Void)?
  var selectionStatusChanged:(()->Void)?
  var selectionStatus:(text:String,help:String?)? {
    guard !resultsHidden,document.offlinePreview==nil,let grid=selectedGrid else {return nil}
    return (grid.selectionSummary.label.stringValue,grid.selectionSummary.label.toolTip)
  }
  var favoriteRequested: ((QueryDocument) -> Void)?
  var favorites:FavoriteQueriesModel? {didSet {syncFavoriteButton()}}
  private var removingFavorite=false
  private let favoriteButton = StudioToolbarButton(symbol:"star",label:"Sorguyu favorilere ekle",tone:.warning)
  private let panes = ResultSplitView()
  private let resultStrip = NSStackView()
  private let stripScroll = NSScrollView()
  private var selectedPageSize = 0
  private weak var resultsToggle:NSButton?
  private let columnSearchButton = StudioToolbarButton(symbol: "text.magnifyingglass", label: "Kolon başlığında ara", tone: .neutral)
  private let autoRefreshButton = StudioToolbarButton(symbol:"clock.arrow.circlepath",label:"Otomatik yenileme",tone:.neutral)
  private var optionsPopover: NSPopover?
  private var selectedRefreshSeconds = 0
  private var defaultRefreshApplied = false
  private var definitionPresentation:DefinitionLoadingPresentation?
  private var offlinePreviewHost: NSHostingView<InlineOfflineDefinitionView>?
  private let editor: EditorController
  private let resultTabs = NSTabView()
  private let navigationHost = NSStackView()
  private let copyHeadersButton = StudioToolbarButton(symbol: "doc.on.doc", label: "Başlıklarla kopyala", tone: .neutral)
  private let refreshButton = StudioToolbarButton(symbol: "arrow.clockwise", label: "Sonuçları yenile", tone: .success)
  private let dataActionsBar = NSStackView()
  private let addRowButton = StudioToolbarButton(symbol: "plus", label: "Yeni satır", tone: .success)
  private let cloneRowButton = StudioToolbarButton(symbol: "plus.square.on.square", label: "Satırı çoğalt", tone: .neutral)
  private let deleteRowButton = StudioToolbarButton(symbol: "trash", label: "Satırı sil", tone: .danger)
  private let undoRowButton = StudioToolbarButton(symbol: "arrow.uturn.backward", label: "Seçili düzenlemeleri geri al", tone: .warning)
  private let editDataButton = StudioToolbarButton(symbol: "square.and.pencil", label: "Satır düzenlemeyi aç")
  private let previewDataButton = StudioToolbarButton(symbol: "eye", label: "SQL önizle ve gönder", title: "", width: 30, prominent: true)
  private let nullDataButton = StudioToolbarButton(symbol: "nosign", label: "Seçili hücreyi NULL yap", tone: .warning)
  private var preparingData = false
  private let editPreparation = ResultEditingCoordinator()
  private let editingIndex: CatalogDiskIndex
  private var submittingData = false
  private var dataReview: NSWindowController?
  private var refreshTask: Task<Void, Never>?
  deinit { refreshTask?.cancel(); exportJob?.cancel() }
  private let resultPane = NSView()
  private(set) var resultsHidden = false
  private var savedEditorFraction: CGFloat = 0.60
  private let messages = ResultMessagesView()
  private var revealedErrorGeneration:Int?
  private let connectionBadge = NSTextField(labelWithString: "")
  private lazy var queryActions=QueryEditorActions(document:document,focus:{[weak self] in self?.focusEditor()},format:{[weak self] in self?.format()})
  private var editorHeader: NSStackView?
  private let editorHeaderSlot=NSView()
  private var editorHeaderHeight:NSLayoutConstraint?
  private var editorHeaderConstraints:[NSLayoutConstraint]=[]
  private weak var editorToolbarHost:NSView?
  private let compareModuleButton = StudioFullAreaButton()
  private let submitModuleButton = StudioFullAreaButton()
  private var checkingModuleSubmission = false
  private let position = NSTextField(labelWithString: "Ln 1, Col 1")
  private let summary = NSTextField(labelWithString: "")
  private let actual = NSButton(checkboxWithTitle: "Gerçek plan", target: nil, action: nil)
  private let filter = StudioSearchField(frame:.zero)
  private let rowLimit = StudioSearchablePopUpButton()
  private let export = StudioToolbarPopUpButton(frame: .zero, pullsDown: true)
  private let cancelExport = StudioToolbarButton(symbol: "stop.circle", label: "Dışa aktarmayı iptal et", tone: .warning)
  private var exportJob: Task<Void, Never>?
  private var tables: [Int: ResultController] = [:]
  private var plans: [Int: String] = [:]
  private var displayed = Set<Int>()
  private var displayedGeneration: Int?
  private var initialSplitApplied = false
  private var pendingResultUpdate:Task<Void,Never>?
  private var moduleReview: ModuleReviewController?
  private var refreshSelection: Any?
  init(document: QueryDocument, editingIndex: CatalogDiskIndex = .shared) {
    self.document = document
    self.editingIndex = editingIndex
    editor = EditorController(document: document)
    super.init(nibName: nil, bundle: nil)
    document.closeOperationBlocked = { [weak self] in self?.submittingData == true }
    document.hasResultEdits = { [weak self] in self?.hasDataEdits == true }
    document.confirmDiscardResultEdits = { [weak self] in
      guard let self else { return true }
      _ = view // Preserve lazy result setup without resigning the SQL responder.
      guard !submittingData else { return false }
      guard hasDataEdits else { return true }
      if let field=view.window?.firstResponder as? NSTextView,field.isFieldEditor {view.window?.makeFirstResponder(nil)}
      let alert = StudioAlert(role:"discardResultEdits"); alert.messageText = "Gönderilmemiş sonuç düzenlemeleri var"
      alert.informativeText = "Devam ederseniz bu yerel değişiklikler silinir. Veritabanına göndermek için Önizle'yi kullanın."
      alert.addButton(withTitle: "Düzenlemeleri Sil ve Devam Et"); alert.addButton(withTitle: "Geri Dön")
      guard alert.runModal() == .alertFirstButtonReturn else { return false }
      for grid in tables.values { grid.discardEdits() }; return true
    }
    NotificationCenter.default.addObserver(self,selector:#selector(favoriteListChanged(_:)),name:FavoriteQueriesModel.changed,object:nil)
    document.changed = { [weak self] in
      self?.documentDidChange()
    }
    editor.edited = { [weak self] in self?.syncFavoriteButton();self?.changed?() }
    editor.position = { [weak self] line, column in
      self?.position.stringValue = "Ln \(line), Col \(column)"
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func loadView() {
    let root = ResultWorkspaceView()
    root.searchColumns = { [weak self] in self?.showColumnSearch() }
    view = root
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
    position.textColor = StudioTheme.muted
    position.identifier = .init("studio.mutedLabel")
    connectionBadge.font = .systemFont(ofSize: 10, weight: .medium)
    connectionBadge.lineBreakMode = .byTruncatingMiddle
    connectionBadge.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    connectionBadge.setAccessibilityIdentifier("queryConnectionBadge")
    let toggle = StudioFullAreaButton(
      image: NSImage(
        systemSymbolName: "rectangle.bottomthird.inset.filled",
        accessibilityDescription: "Sonuçları Göster / Gizle")!, target: self,
      action: #selector(toggleResults))
    toggle.bezelStyle = .inline
    toggle.isBordered = false
    resultsToggle=toggle
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
    favoriteButton.flat=true
    favoriteButton.tracksActiveState=true;editDataButton.tracksActiveState=true;autoRefreshButton.tracksActiveState=true
    favoriteButton.target=self;favoriteButton.action=#selector(addQueryFavorite)
    favoriteButton.setAccessibilityIdentifier("queryFavorite")
    let header = NSStackView(views: [queryActions, favoriteButton, compareModuleButton, submitModuleButton, actual, NSView(), connectionBadge, position, toggle])
    header.spacing = 6
    header.wantsLayer = true
    editorHeader = header
    header.edgeInsets = NSEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)
    editorPane.addSubview(editorHeaderSlot)
    editorHeaderSlot.translatesAutoresizingMaskIntoConstraints=false
    editorPane.addSubview(editor.surface)
    header.translatesAutoresizingMaskIntoConstraints = false
    editor.surface.translatesAutoresizingMaskIntoConstraints = false
    editorHeaderHeight=editorHeaderSlot.heightAnchor.constraint(equalToConstant:28)
    NSLayoutConstraint.activate([
      editorHeaderSlot.leadingAnchor.constraint(equalTo:editorPane.leadingAnchor),
      editorHeaderSlot.trailingAnchor.constraint(equalTo:editorPane.trailingAnchor),
      editorHeaderSlot.topAnchor.constraint(equalTo:editorPane.topAnchor),
      editorHeaderHeight!,
      editor.surface.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor),
      editor.surface.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor),
      editor.surface.topAnchor.constraint(equalTo: editorHeaderSlot.bottomAnchor),
      editor.surface.bottomAnchor.constraint(equalTo: editorPane.bottomAnchor),
    ])
    definitionPresentation=DefinitionLoadingPresentation(in:editorPane,relativeTo:editor.surface)
    placeEditorToolbar(in:editorHeaderSlot)
    resultTabs.delegate = self
    resultTabs.tabViewType = .noTabsNoBorder
    resultTabs.setAccessibilityIdentifier("resultSelector")
    refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Sonuçları yenile")
    refreshButton.target = self
    refreshButton.action = #selector(refreshResults)
    refreshButton.toolTip = "Son çalıştırılan SELECT sorgusunu yenile"
    refreshButton.setAccessibilityIdentifier("refreshResults")
    autoRefreshButton.target=self;autoRefreshButton.action=#selector(showAutoRefreshOptions)
    autoRefreshButton.setAccessibilityIdentifier("gridAutoRefresh")
    messages.navigate = { [weak self] range in
      guard let self,document.sql==document.errorSourceSQL else {return}
      editor.expandAll();editor.selectSourceLine(range)
      editor.editor.scrollRangeToVisible(range)
    }
    messages.isEditable = false
    messages.isSelectable = true
    messages.font = StudioTheme.codeFont
    messages.textContainerInset = NSSize(width: 12, height: 10)
    let messageScroll = NSScrollView()
    messageScroll.documentView = messages
    messageScroll.hasVerticalScroller = true
    messageScroll.autohidesScrollers=true;messageScroll.scrollerStyle = .overlay;messageScroll.borderType = .noBorder
    messages.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
    messages.autoresizingMask = [.width]
    messages.isVerticallyResizable = true
    let messageItem = NSTabViewItem(identifier: "messages")
    messageItem.label = "Messages"
    messageItem.view = messageScroll
    resultTabs.addTabViewItem(messageItem)
    filter.placeholderString = "Sonuç ara"
    filter.sendsSearchStringImmediately = true
    filter.target = self
    filter.action = #selector(filterChanged)
    export.addItems(withTitles: [
      "Dışa Aktar", "Görünen sonuç · CSV…", "Görünen sonuç · JSON…",
    ])
    export.item(at: 0)?.title = ""
    export.item(at: 0)?.image = NSImage(systemSymbolName: "arrow.down.document", accessibilityDescription: "Sonuçları dışa aktar")
    export.toolTip = "Görünen sonuçları mevcut filtre ve sıralamayla CSV / JSON olarak dışa aktar"
    export.widthAnchor.constraint(equalToConstant: 38).isActive = true
    configurePageMenu()
    rowLimit.leadingSymbol="tablecells"
    rowLimit.target=self;rowLimit.action=#selector(selectReadChoice)
    rowLimit.controlSize = .small
    rowLimit.isBordered = false
    rowLimit.font = .systemFont(ofSize: StudioMetrics.detailFont,weight: .medium)
    rowLimit.heightAnchor.constraint(equalToConstant: StudioMetrics.controlHeight).isActive = true
    rowLimit.setAccessibilityLabel("Satır sınırı")
    rowLimit.setAccessibilityIdentifier("gridRowOptions")
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
    let editingDivider = NSBox()
    editingDivider.boxType = .separator
    editingDivider.widthAnchor.constraint(equalToConstant: 1).isActive = true
    editingDivider.heightAnchor.constraint(equalToConstant: 18).isActive = true
    let browsingDivider = NSBox()
    browsingDivider.boxType = .separator
    browsingDivider.widthAnchor.constraint(equalToConstant: 1).isActive = true
    browsingDivider.heightAnchor.constraint(equalToConstant: 16).isActive = true
    let resultHeader = NSStackView(views: [
      rowLimit, navigationHost, refreshButton, autoRefreshButton, browsingDivider, columnSearchButton,
      copyHeadersButton, editingDivider, editDataButton, dataActionsBar,
      previewDataButton, NSView(), filter, cancelExport, export,
    ])
    for (button, action, id) in [
      (editDataButton, #selector(beginDataEditing), "gridEdit"),
      (addRowButton, #selector(addDataRow), "gridAddRow"),
      (cloneRowButton, #selector(cloneDataRow), "gridCloneRow"),
      (deleteRowButton, #selector(deleteDataRows), "gridDeleteRows"),
      (undoRowButton, #selector(undoDataRows), "gridUndoRows"),
      (nullDataButton, #selector(nullDataEditing), "gridSetNull"),
      (previewDataButton, #selector(previewDataEditing), "gridPreviewChanges")
    ] {
      button.target = self; button.action = action; button.setAccessibilityIdentifier(id)
    }
    dataActionsBar.setViews([addRowButton, cloneRowButton, deleteRowButton, undoRowButton, nullDataButton], in: .leading)
    dataActionsBar.spacing = 3
    for button in [refreshButton,autoRefreshButton,columnSearchButton,copyHeadersButton,editDataButton,addRowButton,cloneRowButton,deleteRowButton,undoRowButton,nullDataButton,cancelExport] {button.flat=true;button.layer?.cornerRadius=StudioMetrics.controlRadius}
    dataActionsBar.setAccessibilityIdentifier("gridDataActions")
    addRowButton.toolTip = "Yeni satır ekle · Değer girilmeyen alanlar DEFAULT kullanır"
    cloneRowButton.toolTip = "Seçili satırı çoğalt · Anahtar ve üretilen alanlar kopyalanmaz"
    undoRowButton.toolTip = "Seçili satırlardaki yerel değişiklikleri geri al"
    nullDataButton.toolTip = "Seçili düzenlenebilir hücreyi NULL yap"
    columnSearchButton.target=self;columnSearchButton.action=#selector(showColumnSearch)
    resultHeader.setAccessibilityIdentifier("gridToolbar")
    navigationHost.spacing = 0
    copyHeadersButton.target = self; copyHeadersButton.action = #selector(copyHeadersSelection)
    copyHeadersButton.setAccessibilityIdentifier("gridCopyHeaders")
    updateShortcutHints()
    NotificationCenter.default.addObserver(self, selector: #selector(updateShortcutHints), name: GridShortcuts.changed, object: nil)
    filter.toolTip = "Yalnızca yüklenen sonuçlarda ara; sunucuya sorgu göndermez"
    StudioTheme.resultSurface(resultHeader)
    resultHeader.edgeInsets = NSEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)
    resultHeader.spacing = 3
    filter.controlSize = .small
    export.controlSize = .small
    summary.lineBreakMode = .byTruncatingTail
    summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    filter.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
    filter.widthAnchor.constraint(lessThanOrEqualToConstant: 140).isActive = true
    filter.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    NSLayoutConstraint.activate([rowLimit.widthAnchor.constraint(greaterThanOrEqualToConstant:120),rowLimit.widthAnchor.constraint(lessThanOrEqualToConstant:180)])
    rowLimit.setContentCompressionResistancePriority(.required, for: .horizontal)
    export.bezelStyle = .rounded; export.isBordered = false; export.contentTintColor = StudioTheme.muted
    export.setAccessibilityLabel("Sonuçları dışa aktar")
    resultStrip.spacing = 2
    resultStrip.edgeInsets = NSEdgeInsets(top: 3,left: 6,bottom: 3,right: 6)
    StudioTheme.resultSurface(resultStrip)
    resultStrip.setAccessibilityIdentifier("resultTabStrip")
    StudioTheme.resultSurface(stripScroll)
    stripScroll.documentView = resultStrip
    stripScroll.hasHorizontalScroller = true; stripScroll.autohidesScrollers = true; stripScroll.scrollerStyle = .overlay
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
      stripScroll.heightAnchor.constraint(equalToConstant: 32),
      resultStrip.leadingAnchor.constraint(equalTo: stripScroll.contentView.leadingAnchor),
      resultStrip.topAnchor.constraint(equalTo: stripScroll.contentView.topAnchor),
      resultStrip.heightAnchor.constraint(equalToConstant: 32),
      resultHeader.topAnchor.constraint(equalTo: stripScroll.bottomAnchor),
      resultHeader.heightAnchor.constraint(equalToConstant: 34),
      resultTabs.leadingAnchor.constraint(equalTo: resultPane.leadingAnchor),
      resultTabs.trailingAnchor.constraint(equalTo: resultPane.trailingAnchor),
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
    selectionStatusChanged?()
  }
  @objc private func updateShortcutHints() {
    resultsToggle?.toolTip=StudioCommandCatalog.help("Sonuçları Göster / Gizle",action:.results)
    copyHeadersButton.toolTip=StudioCommandCatalog.help("Seçili hücreleri veya satırları kolon başlıklarıyla kopyala",action:.headers)
    columnSearchButton.toolTip=StudioCommandCatalog.help("Kolon başlığında ara",action:.columns)
  }
  @objc private func copyHeadersSelection() {
    guard let index = (resultTabs.selectedTabViewItem?.identifier as? NSNumber)?.intValue else { return }
    tables[index]?.copySelectionData(includeHeaders: true)
  }
  func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) { syncNavigation(); syncResultStrip() }
  private func syncResultStrip() {
    if resultStrip.arrangedSubviews.count != resultTabs.numberOfTabViewItems {
      for child in resultStrip.arrangedSubviews { resultStrip.removeArrangedSubview(child); child.removeFromSuperview() }
      for index in resultTabs.tabViewItems.indices {
        let button = StudioResultTabButton(title: "",target: self,action: #selector(selectResultTab(_:)))
        button.tag = index; button.bezelStyle = .inline; button.isBordered = false; button.font = StudioTheme.uiFont
        resultStrip.addArrangedSubview(button)
      }
    }
    for (index,item) in resultTabs.tabViewItems.enumerated() {
      guard let button = resultStrip.arrangedSubviews[index] as? NSButton else { continue }
      if button.title != item.label { button.title = item.label }
      button.setAccessibilityLabel(item.label)
      if let tab = button as? StudioResultTabButton {
        let ordinal = (item.identifier as? NSNumber)?.intValue
        tab.source = ordinal.flatMap { document.results.indices.contains($0) ? document.results[$0].source : nil }
      }
      button.contentTintColor = item === resultTabs.selectedTabViewItem ? StudioTheme.accent : StudioTheme.muted
      button.state = item === resultTabs.selectedTabViewItem ? .on : .off
      button.setAccessibilityValue(button.state == .on ? "Seçili" : "")
      (button as? StudioResultTabButton)?.refreshStyle()
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
    export.isHidden = exportJob != nil
    export.isEnabled = toolbar != nil && exportJob == nil
    copyHeadersButton.isEnabled = toolbar != nil
    filter.isEnabled = toolbar != nil
    syncDataActions()
    selectionStatusChanged?()
  }
  private var selectedGrid: ResultController? {
    guard let index = (resultTabs.selectedTabViewItem?.identifier as? NSNumber)?.intValue else { return nil }
    return tables[index]
  }
  private var hasDataEdits: Bool { tables.values.contains { !$0.pendingEdits.isEmpty || $0.hasDraftChanges } }
  private var canChangeReadLimit:Bool {!tables.values.contains {$0.editDefinition != nil} && exportJob == nil}
  private func syncDataActions() {
    warmDataEditing()
    let grid = selectedGrid
    let editing = grid?.editDefinition != nil
    let safe = document.canRefresh && !preparingData && !submittingData
    dataActionsBar.isHidden = !editing
    previewDataButton.isHidden = !editing
    editDataButton.state = editing ? .on : .off
    editDataButton.tone = editing ? .warning : .accent
    editDataButton.image = NSImage(systemSymbolName: preparingData ? "hourglass" : editing ? "pencil.slash" : "square.and.pencil", accessibilityDescription: "Veri düzenleme")?.withSymbolConfiguration(.init(pointSize: 12,weight: .medium))
    editDataButton.setAccessibilityLabel(preparingData ? "Düzenleme hazırlanıyor" : editing ? "Vazgeç ve düzenleme modunu kapat" : "Satır düzenlemeyi aç")
    editDataButton.toolTip = editing ? "Düzenleme açık · Kapatmak için tıklayın" : "Hücreleri düzenlemek için kaynağı doğrula ve düzenleme modunu aç"
    editDataButton.isEnabled = editing ? !preparingData && !submittingData : safe && grid != nil && document.canEditLoadedRows
    columnSearchButton.isEnabled = grid != nil
    rowLimit.isEnabled = !document.busy && !submittingData
    syncReadOptionsHelp()
    autoRefreshButton.isEnabled = !document.busy && !submittingData && !tables.values.contains {$0.editDefinition != nil}
    let pending = !(grid?.pendingEdits.isEmpty ?? true) || grid?.hasDraftChanges == true
    let canChange = !preparingData && !submittingData
    previewDataButton.flat = true
    previewDataButton.prominent = pending
    previewDataButton.isEnabled = canChange && grid?.editingAllowed?() == true && pending && grid?.editValidationMessage == nil
    previewDataButton.toolTip = pending ? "SQL önizle ve gönder · Değişiklikler yalnız önizlemedeki onayınızla veritabanına gönderilir" : "SQL önizle ve gönder · Bir hücreyi değiştirdiğinizde etkinleşir"
    previewDataButton.setAccessibilityLabel("Bekleyen değişikliklerin SQL önizlemesi")
    addRowButton.isEnabled = canChange && grid?.canAppendRow == true
    cloneRowButton.isEnabled = canChange && grid?.canCloneRow == true
    deleteRowButton.isEnabled = canChange && grid?.canDeleteRows == true
    undoRowButton.isEnabled = canChange && grid?.canRevertRows == true
    nullDataButton.isEnabled = canChange && grid?.canSetSelectedNull == true
    let restoring = grid?.selectionIsDeleted == true
    deleteRowButton.image = NSImage(systemSymbolName: restoring ? "trash.slash" : "trash", accessibilityDescription: restoring ? "Silmeyi geri al" : "Satırı sil")
    deleteRowButton.tone = restoring ? .warning : .danger
    deleteRowButton.setAccessibilityLabel(restoring ? "Silmeyi geri al" : "Satırı sil")
    deleteRowButton.toolTip = restoring ? "Seçili satırların silme işaretini kaldır" : "Seçili satırları silinmek üzere işaretle · SQL önizlemesinden onayla uygulanır"
  }
  private func dataError(_ error: Error) {
    let alert = StudioAlert(role:"resultEditingError"); alert.messageText = "Veri düzenleme"; alert.informativeText = error.localizedDescription
    if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
  }
  @objc private func beginDataEditing() {
    if selectedGrid?.editDefinition != nil { revertDataEditing() }
    else { prepareDataEditing() }
  }
  private func editingContext(_ grid: ResultController) -> ResultEditingCoordinator.Context? {
    guard document.canEditLoadedRows, let sql = document.lastExecutedSQL else { return nil }
    return .init(serverID: document.server.id, serverGeneration: document.server.generation, resultGeneration: document.resultGeneration, database: document.database, sql: sql, fields: grid.result.fields, profileScope: CatalogDiskIndex.scope(profile: document.server.profile, database: document.database))
  }
  private func warmDataEditing() {
    guard let grid = selectedGrid, let context = editingContext(grid) else { editPreparation.invalidate(); return }
    guard !preparingData, !submittingData, grid.editDefinition == nil else { return }
    // Synthetic query fixtures must never start an actual metadata connection.
    guard document.executionFixture == nil || document.server.catalogFixture != nil || document.server.asyncCatalogFixture != nil else { return }
    let document=document, server = document.server, profile = server.profile, index = editingIndex
    editPreparation.warm(context) {
      try await ResultEditingPreparation.load(sql: context.sql, fields: context.fields, profile: profile, database: context.database, index: index) { query in
        try await document.resultEditingMetadata(query, database: context.database)
      }
    }
  }
  private func prepareDataEditing(cell: (Int, Int)? = nil) {
    guard !preparingData, !submittingData else { return }
    guard let grid = selectedGrid, document.canEditLoadedRows, let sql = document.lastExecutedSQL, let context = editingContext(grid) else { return }
    let generation = document.resultGeneration, db = document.database, server = document.server
    let serverGeneration = server.generation
    let index = editingIndex
    let cellIdentity = cell.flatMap { grid.cellIdentity(row: $0.0, position: $0.1) }
    preparingData = true; syncDataActions()
    // Unattended refresh would discard the staged copy.
    setAutoRefresh(0)
    Task { [weak self, weak grid] in
      guard let self, let grid else { return }
      defer { preparingData = false; syncDataActions() }
      do {
        let profile = server.profile
        let prepared = try await editPreparation.prepared(context) {
          try await ResultEditingPreparation.load(sql:sql,fields:context.fields,profile:profile,database:db,index:index) { query in
            try await self.document.resultEditingMetadata(query,database:db)
          }
        }
        let table = prepared.snapshot.table, id = prepared.snapshot.objectID
        guard document.server === server, server.generation == serverGeneration, document.resultGeneration == generation, document.database == db, document.canRefresh else { throw SQLFailure("Sonuç değişti; güncel sonuçta yeniden deneyin.") }
        grid.editMetadataSignature = prepared.snapshot.metadataSignature
        grid.editMetadataCached = prepared.cached
        grid.editObjectID = id
        grid.editDefinition = table
        grid.editingAllowed = { [weak self] in self?.document.server === server && server.generation == serverGeneration && self?.document.resultGeneration == generation && self?.document.canRefresh == true && self?.submittingData == false }
        grid.editsChanged = { [weak self] in self?.syncDataActions() }
        grid.table.reloadData()
        if let cell, cellIdentity != nil, grid.cellIdentity(row: cell.0, position: cell.1) == cellIdentity, selectedGrid === grid {
          grid.table.editCell?(cell.0, cell.1)
        }
      } catch is CancellationError {} catch { dataError(error) }
    }
  }
  @objc private func addDataRow() { guard commitDataCell() else { return }; selectedGrid?.appendRow() }
  @objc private func cloneDataRow() { guard commitDataCell() else { return }; selectedGrid?.appendRow(cloning: true) }
  @objc private func deleteDataRows() { guard commitDataCell() else { return }; selectedGrid?.toggleSelectedDeletion() }
  @objc private func undoDataRows() { guard commitDataCell() else { return }; selectedGrid?.revertSelectedRows() }
  private func commitDataCell() -> Bool { view.window?.makeFirstResponder(nil) ?? true }
  @objc private func nullDataEditing() { guard commitDataCell() else { return }; selectedGrid?.setSelectedNull() }
  @objc private func revertDataEditing() {
    guard let grid = selectedGrid, !submittingData else { return }
    view.window?.makeFirstResponder(nil)
    if grid.pendingEdits.isEmpty { grid.discardEdits(); return }
    let alert = StudioAlert(role:"discardResultEditsConfirmation"); alert.messageText = "Bekleyen düzenlemelerden vazgeçilsin mi?"; alert.addButton(withTitle: "Vazgeç"); alert.addButton(withTitle: "Düzenlemeye Devam Et")
    if let window = view.window { alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { grid.discardEdits() } } }
  }
  @objc private func previewDataEditing() {
    guard commitDataCell() else { return }
    guard let grid = selectedGrid, document.canRefresh, !submittingData, let sourceSQL=document.lastExecutedSQL else { return }
    do {
      let sql = try grid.pendingSQL(), generation = document.resultGeneration, db = document.database
      let server = document.server, serverGeneration = document.server.generation
      let panel = DataChangesPreview(sql: sql, target: document.server.profile.name + " / " + db, submit: { [weak self, weak grid] in
        guard let self, let grid else { throw SQLFailure("Sorgu kapatıldı.") }
        guard !submittingData, document.server === server, server.generation == serverGeneration, document.canRefresh, document.database == db, document.resultGeneration == generation, try grid.pendingSQL() == sql else { throw SQLFailure("Önizlemeden sonra sonuç veya düzenlemeler değişti. Yeniden önizleyin.") }
        submittingData = true; syncDataActions()
        defer { submittingData = false; syncDataActions() }
        guard let definition = grid.editDefinition, let objectID = grid.editObjectID else { throw SQLFailure("Kaynak kimliği kayboldu.") }
        do {
          let freshSource = try ResultEditSource.decode(await document.resultEditingMetadata(ResultEditSource.metadata(sourceSQL),database:db),fields:grid.result.fields,database:db)
          guard ResultEditingSnapshot.matchesSource(freshSource,table:definition) else { throw SQLFailure("Sorgunun kaynak tablosu değişmiş; sonucu yeniden yükleyin.") }
          let current = try ObjectMetadata.decode(try await document.resultEditingMetadata(ObjectMetadata.table(objectID), database: db), schema: definition.schema, name: definition.name)
          guard ResultEditingSnapshot.signature(table:current) == grid.editMetadataSignature else { throw SQLFailure("Tablo yapısı değişmiş; güncel sonucu yeniden yükleyin.") }
        } catch {
          // Reloading after a schema/source mismatch must not reuse the same stale entry.
          try? await editingIndex.invalidateEditingMetadata(scope:CatalogDiskIndex.scope(profile:server.profile,database:db))
          throw error
        }
        guard document.server === server, server.generation == serverGeneration, document.canRefresh, document.database == db, document.resultGeneration == generation, try grid.pendingSQL() == sql else { throw SQLFailure("Önizleme artık güncel değil.") }
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
      let window = StudioPanelWindow(contentViewController: NSHostingController(rootView: panel)); window.framePersistenceRole="dataChangesPreview"; window.title = "Veri Değişiklikleri — SQL Önizlemesi"; window.setContentSize(NSSize(width: 1000, height: 720)); window.styleMask = [.titled, .closable, .resizable]; window.minSize = NSSize(width: 760, height: 520)
      let controller = DataReviewWindowController(window: window); controller.canClose = { [weak self] in self?.submittingData != true }; window.delegate = controller; dataReview = controller; controller.showWindow(nil)
    } catch { dataError(error) }
  }
  @objc private func refreshResults() {repeatResults(automatic:false)}
  private func repeatResults(automatic:Bool) {
    guard document.canRefresh, let sql = document.lastExecutedSQL else { return }
    refreshSelection = resultTabs.selectedTabViewItem?.identifier;document.execute(override: sql, repeatRead: true, automaticRefresh:automatic)
  }
  func setAutoRefresh(_ seconds:Int) {
    guard !document.busy,!submittingData,!tables.values.contains(where:{$0.editDefinition != nil}),(0...3600).contains(seconds) else {return}
    document.initialRefreshSeconds=seconds
    defaultRefreshApplied=document.canRefresh
    applyRefreshSeconds(seconds)
  }
  @objc private func showAutoRefreshOptions() {
    autoRefreshButton.menu?.popUp(positioning:nil,at:NSPoint(x:0,y:autoRefreshButton.bounds.maxY+3),in:autoRefreshButton)
  }
  @objc private func changeAutoRefresh(_ item:NSMenuItem) {setAutoRefresh(item.tag)}
  private func applyRefreshSeconds(_ seconds: Int) {
    refreshTask?.cancel(); refreshTask=nil
    selectedRefreshSeconds=0
    defer {syncReadOptions()}
    guard (0...3600).contains(seconds) else { return }
    guard seconds > 0, document.canRefresh, !tables.values.contains(where: { $0.editDefinition != nil }) else { return }
    selectedRefreshSeconds=seconds

    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        guard let self else { return }
        if document.busy { continue }
        guard document.canRefresh else { applyRefreshSeconds(0); return }
        repeatResults(automatic:true)
      }
    }
  }
  private func syncResultSelector() {
    if !defaultRefreshApplied && document.canRefresh {
      defaultRefreshApplied=true; applyRefreshSeconds(document.initialRefreshSeconds ?? ResultReadPreferences.refreshSeconds)
    }
    refreshButton.isEnabled = document.canRefresh
    refreshButton.toolTip = document.refreshDisabledReason.map { "Sonuçları yenile · " + $0 }
      ?? "Son başarılı sorguyu aynı veritabanında yeniden çalıştır"
    refreshButton.setAccessibilityHelp(refreshButton.toolTip)
    autoRefreshButton.isEnabled = !document.busy && !submittingData && !tables.values.contains(where: { $0.editDefinition != nil })
    if !document.busy && !document.canRefresh { applyRefreshSeconds(0) }
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
  func focusEditor() {
    guard document.offlinePreview == nil,!document.definitionLoading else {return}
    editor.resizeToViewport()
    view.window?.makeFirstResponder(editor.editor)
    editor.refreshCatalogAnalysisIfNeeded()
    editor.editor.scrollRangeToVisible(editor.editor.selectedRange())
    editor.editor.updateInsertionPointStateAndRestartTimer(true)
  }
  func setText() { editor.setText() }
  func format() { guard document.offlinePreview == nil else {return};editor.formatSQL(options: SQLEditorPreferences.formatting()) }
  @objc private func refreshTheme() {
    StudioTheme.decorate(view)
    for controller in tables.values {
      let selected = controller.table.selectedRowIndexes
      controller.table.reloadData()
      controller.table.selectRowIndexes(selected, byExtendingSelection: false)
    }
    updateConnectionAppearance()
  }
  private func placeEditorToolbar(in host:NSView) {
    guard let header=editorHeader else {return}
    NSLayoutConstraint.deactivate(editorHeaderConstraints)
    header.removeFromSuperview();host.addSubview(header)
    editorHeaderConstraints=[
      header.leadingAnchor.constraint(equalTo:host.leadingAnchor),
      header.trailingAnchor.constraint(equalTo:host.trailingAnchor),
      header.centerYAnchor.constraint(equalTo:host.centerYAnchor),
      header.heightAnchor.constraint(equalToConstant:28)
    ]
    NSLayoutConstraint.activate(editorHeaderConstraints)
  }
  func hostEditorToolbar(in host:NSView?) {
    _=view
    guard editorToolbarHost !== host else {return}
    editorToolbarHost=host
    connectionBadge.isHidden=host != nil
    editorHeaderHeight?.constant=host == nil ? 28:0
    placeEditorToolbar(in:host ?? editorHeaderSlot)
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
    // Execution boundaries must not be hidden by the streaming debounce.
    guard document.state == .running, displayedGeneration == document.resultGeneration else {
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
  private func removeDisplayedResult(_ index: Int) {
    let item = resultTabs.tabViewItems.first { ($0.identifier as? NSNumber)?.intValue == index }
    tables.removeValue(forKey: index)?.removeFromParent()
    plans.removeValue(forKey: index)
    displayed.remove(index)
    if let item {
      children.first { $0.view === item.view }?.removeFromParent()
      resultTabs.removeTabViewItem(item)
    }
  }
  private func clearDisplayedResults() {
    for index in displayed.sorted() { removeDisplayedResult(index) }
    stripScroll.contentView.scroll(to: .zero)
    stripScroll.reflectScrolledClipView(stripScroll.contentView)
  }
  func insertSQLAtCaret(_ text:String) throws {
    _ = view
    try editor.insertSQLAtCaret(text)
    view.window?.makeKeyAndOrderFront(nil);focusEditor()
  }
  func update() {
    compareModuleButton.isHidden = document.moduleOriginal == nil
    compareModuleButton.isEnabled = !document.busy
    submitModuleButton.isHidden = document.moduleOriginal == nil
    submitModuleButton.isEnabled = document.canSubmitModule && !checkingModuleSubmission
    guard isViewLoaded else { return }
    let pending=document.definitionLoading || document.definitionError != nil
    definitionPresentation?.update(document)
    if let preview=document.offlinePreview {
      let root=InlineOfflineDefinitionView(preview:preview,back:{[weak self] in
        guard let self else {return};document.offlinePreview=nil;document.changed?();focusEditor()
      },navigate:{[weak self] parts in
        guard let self else {return};document.openOfflineReference?(parts,preview.server,preview.database)
      },revealInExplorer:{[weak self] parts in self?.document.revealInExplorer?(parts,preview.server,preview.database)})
      if let host=offlinePreviewHost {host.rootView=root}
      else if let pane=editor.surface.superview {
        let host=NSHostingView(rootView:root);offlinePreviewHost=host;pane.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo:editor.surface.leadingAnchor),host.trailingAnchor.constraint(equalTo:editor.surface.trailingAnchor),host.topAnchor.constraint(equalTo:editor.surface.topAnchor),host.bottomAnchor.constraint(equalTo:editor.surface.bottomAnchor)])
      }
    } else {offlinePreviewHost?.removeFromSuperview();offlinePreviewHost=nil}
    editor.surface.isHidden=pending || document.offlinePreview != nil
    editor.editor.isEditable = !pending && document.offlinePreview == nil
    editor.setText()
    if displayedGeneration != document.resultGeneration {
      displayedGeneration = document.resultGeneration
      if !document.repeating {
        clearDisplayedResults()
        refreshSelection = nil
      }
    }
    updateConnectionAppearance()
    syncDataActions()
    queryActions.refresh()
    actual.state = document.actualPlan ? .on : .off
    actual.isEnabled = !document.busy
    syncFavoriteButton()
    if document.results.isEmpty && !displayed.isEmpty && !(document.repeating && document.busy) {
      clearDisplayedResults()
    }
    let fixtureSQL=document.sql.trimmingCharacters(in:.whitespacesAndNewlines)
    let limitApplies=document.lastExecutedSQL != nil ? document.lastExecutedReadLimit != nil : fixtureSQL.isEmpty || TSQL.usesResultRowLimit(fixtureSQL)
    let displayRowLimit=limitApplies ? document.limits.rows:Int.max
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
          controller.requestEditing = { [weak self, weak controller] row, column in
            guard let self, selectedGrid === controller, document.canEditLoadedRows else { return false }
            prepareDataEditing(cell: (row, column))
            return true
          }
          controller.editsChanged = { [weak self] in self?.syncDataActions() }
          controller.selectionSummary.changed = { [weak self,weak controller] in
            guard let self,let controller,selectedGrid === controller else {return}
            selectionStatusChanged?()
          }
          controller.table.searchColumns = { [weak self] in self?.showColumnSearch() }
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
        controller.applyReadLimit(displayRowLimit)
        controller.update(result, generation: document.resultGeneration)
        controller.partial = result.truncated
        controller.filter = filter.stringValue
        resultTabs.tabViewItems.first(where: { ($0.identifier as? NSNumber)?.intValue == index })?
          .label = "Results \(index + 1) (\(controller.result.values.count.formatted()))\(result.truncated ? " · KISMİ" : controller.isReadLimited ? " · SINIRLI" : "")"
      }
    }
    if !document.busy {
      let current = Set(document.results.indices.filter { !document.results[$0].fields.isEmpty })
      for index in displayed.subtracting(current).sorted() { removeDisplayedResult(index) }
      if document.repeating, let identifier = refreshSelection,
        resultTabs.tabViewItems.contains(where: { $0.identifier as? NSObject == identifier as? NSObject }) {
        resultTabs.selectTabViewItem(withIdentifier: identifier)
      }
      refreshSelection = nil
    }
    syncNavigation()
    syncResultStrip()
    syncResultSelector()
    messages.show(document.messages,locations:document.sql==document.errorSourceSQL ? document.errorLocations:[])
    if document.executionFailed,revealedErrorGeneration != document.resultGeneration {
      revealedErrorGeneration=document.resultGeneration
      if resultsHidden {toggleResults()}
      resultTabs.selectTabViewItem(withIdentifier:"messages")
      syncResultSelector()
    }
    summary.stringValue =
      document.state == .running
      ? "Sonuçlar okunuyor · \(document.rowCount.formatted()) satır"
      : "\(document.rowCount.formatted()) satır\(document.partial ? " · KISMİ" : "")"
    if document.state == .ready && displayed.isEmpty {
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
    guard document.hasClosedTransaction else {
      let alert=StudioAlert(role:"moduleTransactionWarning");alert.messageText="Önce COMMIT veya ROLLBACK çalıştırın.";alert.runModal();return
    }
    guard document.canSubmitModule else {return}
    modulePreview()
  }
  private func submitModule(sql:String,database db:String,original:String) {
    guard let object=document.moduleObjectID,document.objectEditorKey?.database == db,document.sql == sql,document.database == db,document.canSubmitModule,!checkingModuleSubmission else {return}
    if document.state == .disconnected {
      document.connect { [weak self] in self?.submitModule(sql:sql,database:db,original:original) }
      return
    }
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
            // The shared targeted DDL observer updates completion metadata.
          }
        }
        document.applyingModule=true;document.execute(override:sql)
      } catch {
        let alert=StudioAlert(role:"moduleSubmissionError");alert.messageText="Değişiklik uygulanamadı";alert.informativeText=error.localizedDescription;alert.runModal()
      }
    }
  }
  @objc private func actualChanged() { document.actualPlan = actual.state == .on }
  @objc private func showLoadingOptions() {
    optionsPopover?.close()
    let popup=NSPopover()
    let panel=ResultLoadingPanel(rows:document.limits.rows == Int.max ? 0:document.limits.rows,refresh:effectiveRefreshSeconds,refreshAllowed:!tables.values.contains {$0.editDefinition != nil},readLimitAllowed:canChangeReadLimit) { [weak self,weak popup] rows,refresh,save in
      guard let self,!document.busy,!submittingData else {return}
      applyLoadingPreferences(rows:rows,refresh:refresh,save:save);popup?.close()
    }
    optionsPopover=popup;StudioPopover.show(popup,content:panel,from:rowLimit,size:NSSize(width:440,height:400))
  }
  @objc private func showColumnSearch() {
    guard let grid=selectedGrid else {return}
    optionsPopover?.close()
    let columns=grid.result.fields.enumerated().map {ordinal,field in
      ResultColumnChoice(id:ordinal,name:field.name,type:field.dataType,hidden:grid.isColumnHidden(ordinal))
    }
    let popup=NSPopover()
    let panel=ResultColumnSearch(columns:columns,select:{ [weak grid,weak popup] ordinal in
      popup?.close();grid?.revealColumn(ordinal)
    },dismiss:{[weak popup] in popup?.close()})
    optionsPopover=popup;StudioPopover.show(popup,content:panel,from:columnSearchButton,size:NSSize(width:420,height:420))
  }
  @objc private func filterChanged() {
    for table in tables.values { table.filter = filter.stringValue }
  }
  private func configurePageMenu() {syncPageMenu()}
  private var effectiveRefreshSeconds:Int {defaultRefreshApplied ? selectedRefreshSeconds : document.initialRefreshSeconds ?? ResultReadPreferences.refreshSeconds}
  func applyLoadingPreferences(rows:Int,refresh:Int,save:Bool) {
    guard !document.busy,!submittingData,(0...5_000_000).contains(rows),(0...3600).contains(refresh) else {return}
    let newLimits=ResultReadPreferences.limits(rows:rows)
    let limitChanged=newLimits.rows != document.limits.rows
    guard !limitChanged || canChangeReadLimit else {return}
    let seconds=tables.values.contains {$0.editDefinition != nil} ? 0:refresh
    document.limits=newLimits
    document.initialRefreshSeconds=seconds
    defaultRefreshApplied=document.canRefresh
    applyPageSize(0);applyRefreshSeconds(seconds)
    if save {ResultReadPreferences.save(rows:rows,refresh:seconds)}
    syncPageMenu()
    update();changed?()
    if limitChanged,document.lastExecutedReadLimit != nil {refreshResults()}
  }
  private func syncReadOptions() {
    let seconds=effectiveRefreshSeconds
    autoRefreshButton.tone=seconds>0 ? .success:.neutral
    autoRefreshButton.state=seconds>0 ? .on:.off
    autoRefreshButton.image=NSImage(systemSymbolName:seconds>0 ? "clock.badge.checkmark":"clock.arrow.circlepath",accessibilityDescription:"Otomatik yenileme")
    autoRefreshButton.toolTip="Otomatik yenileme · \(seconds == 0 ? "Kapalı":"\(seconds) sn")\(seconds>0 && !document.canRefresh ? " · Başarılı SELECT sonrası başlar":"")"
    autoRefreshButton.setAccessibilityValue(seconds == 0 ? "Kapalı":"\(seconds) sn")
    let menu=StudioMenu()
    for value in [0,5,10,30,60,300] {
      let item=NSMenuItem(title:value == 0 ? "Kapalı":"Her \(value) saniyede",action:#selector(changeAutoRefresh(_:)),keyEquivalent:"")
      item.target=self;item.tag=value;item.state=value == seconds ? .on:.off
      menu.addItem(item)
    }
    if seconds>0 && ![5,10,30,60,300].contains(seconds) {
      let item=NSMenuItem(title:"Her \(seconds) saniyede (özel)",action:#selector(changeAutoRefresh(_:)),keyEquivalent:"")
      item.target=self;item.tag=seconds;item.state = .on;menu.addItem(item)
    }
    menu.addItem(.separator())
    let custom=NSMenuItem(title:"Özel süre…",action:#selector(showRefreshOptions),keyEquivalent:"");custom.target=self;menu.addItem(custom)
    autoRefreshButton.menu=menu
  }
  private func syncPageMenu() {
    syncReadOptions()
    let menu=StudioMenu();menu.autoenablesItems=false
    let selected=document.limits.rows == Int.max ? 0:document.limits.rows
    let defaultValue=ResultReadPreferences.readLimit == Int.max ? 0:ResultReadPreferences.readLimit
    let presets=[10,100,250,500,1000]
    let extra=[selected,defaultValue].filter {$0>0 && !presets.contains($0)}
    for value in presets+Array(Set(extra)).sorted()+[0] {
      let name=value==0 ? "Tümü":value.formatted()
      let item=NSMenuItem(title:name+(value==defaultValue ? "  Varsayılan":""),action:#selector(changeReadLimit(_:)),keyEquivalent:"")
      item.identifier = .init("gridReadChoices");item.target=self;item.tag=value
      item.state=value==selected ? .on:.off;item.isEnabled=canChangeReadLimit;menu.addItem(item)
    }
    let custom=NSMenuItem(title:"Özel…",action:#selector(showLoadingOptions),keyEquivalent:"");custom.target=self;custom.isEnabled=canChangeReadLimit;menu.addItem(custom)
    let save=NSMenuItem(title:"Varsayılan Yap",action:#selector(saveLoadingDefaults),keyEquivalent:"");save.target=self;save.tag = -2;menu.addItem(save)
    rowLimit.invalidateChoices();rowLimit.menu=menu
    if let item=menu.items.first(where:{$0.identifier?.rawValue=="gridReadChoices" && $0.tag==selected}) {rowLimit.select(item)}
    syncReadOptionsHelp()
  }
  @objc private func selectReadChoice() {
    guard let item=rowLimit.selectedItem,let action=item.action else {return}
    syncPageMenu()
    NSApp.sendAction(action,to:item.target,from:item)
  }
  private func syncReadOptionsHelp() {
    let grid=selectedGrid,count=grid?.result.values.count ?? 0
    rowLimit.displayTitle="\(count.formatted())\(grid?.partial == true || grid?.isReadLimited == true ? "+":"") satır"
    let enabled = !document.busy && !submittingData && canChangeReadLimit
    if rowLimit.isEnabled && !enabled {rowLimit.invalidateChoices()}
    rowLimit.isEnabled=enabled
    rowLimit.setAccessibilityValue(rowLimit.displayTitle)

    rowLimit.toolTip="Satır sınırı: \(document.limits.rows == Int.max ? "Tümü":document.limits.rows.formatted()) / sonuç · Yalnız doğrulanmış SELECT sorgularında uygulanır. INSERT/UPDATE/DELETE/EXEC yürütmesini veya çıktısını sınırlamaz. Değiştirildiğinde güvenle yenilenebilen son SELECT yeni sınırla tekrar çalışır."
    if let previous=document.lastExecutedReadLimit,previous != document.limits.rows,!document.results.isEmpty {
      rowLimit.toolTip! += "\nSon okuma sınırı: \(previous == Int.max ? "Tümü":previous.formatted()). Yenileme uygun değilse mevcut önbelleğe uygulanır; ek satır okumak için Çalıştır’ı kullanın."
    }
    if !canChangeReadLimit {rowLimit.toolTip! += "\nSatır sınırını değiştirmek için düzenleme modunu ve devam eden dışa aktarmayı tamamlayın."}
    for item in rowLimit.menu?.items ?? [] where item.identifier?.rawValue == "gridReadChoices" {item.isEnabled=canChangeReadLimit}
    for item in rowLimit.menu?.items.first(where:{$0.identifier?.rawValue == "gridReadChoices"})?.submenu?.items ?? [] {item.isEnabled=canChangeReadLimit}
    rowLimit.setAccessibilityHelp(rowLimit.toolTip)
  }
  @objc private func changeReadLimit(_ item:NSMenuItem) {
    guard !document.busy,!submittingData,canChangeReadLimit,(0...5_000_000).contains(item.tag) else {return}
    applyLoadingPreferences(rows:item.tag,refresh:effectiveRefreshSeconds,save:false)
  }
  @objc private func saveLoadingDefaults() {
    guard !document.busy,!submittingData else {return}
    ResultReadPreferences.save(rows:document.limits.rows,refresh:effectiveRefreshSeconds)
    syncPageMenu()
  }
  func applyPageSize(_ value: Int, makeDefault: Bool = false) {
    guard (0...1_000_000).contains(value) else { return }
    selectedPageSize = value
    if makeDefault { UserDefaults.standard.set(value, forKey: "gridDefaultPageSize") }
    for table in tables.values { table.setPageSize(value) }
    syncPageMenu()
  }
  @objc private func changeRowLimit(_ item:NSMenuItem) {
    guard !document.busy,!submittingData else {return}
    applyPageSize(item.tag)
  }
  private var matchedFavorite:FavoriteQuery? {favorites?.matching(sql:document.sql,serverID:document.server.id,database:document.database,preferredID:document.favoriteID)}
  @objc private func favoriteListChanged(_ notification:Notification) {
    guard notification.object as? FavoriteQueriesModel === favorites else {return}
    syncFavoriteButton()
  }
  private func syncFavoriteButton() {
    let favorite=matchedFavorite
    favoriteButton.isEnabled = !removingFavorite && (favoriteRequested != nil || favorite != nil) && !document.sql.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
    favoriteButton.state=favorite == nil ? .off:.on
    favoriteButton.image=NSImage(systemSymbolName:favorite == nil ? "star":"star.fill",accessibilityDescription:nil)
    favoriteButton.toolTip=favorite.map {"Favorilerden çıkar · \($0.name)"} ?? "Sorguyu favorilere ekle"
    favoriteButton.setAccessibilityLabel(favorite == nil ? "Sorguyu favorilere ekle":"Favorilerden çıkar")
  }
  @objc private func addQueryFavorite() {
    guard !removingFavorite else {return}
    guard let favorite=matchedFavorite,let favorites else {favoriteRequested?(document);return}
    removingFavorite=true;syncFavoriteButton()
    Task { [weak self] in
      do {
        try await favorites.delete(favorite.id)
        if self?.document.favoriteID == favorite.id {self?.document.favoriteID=nil}
      } catch {
        if let window=self?.view.window {let alert=StudioAlert(role:"favoriteRemovalError");alert.messageText="Favori kaldırılamadı";alert.informativeText=error.localizedDescription;_ = await alert.beginSheetModal(for:window)}
      }
      self?.removingFavorite=false;self?.syncFavoriteButton()
    }
  }
  @objc private func showRefreshOptions() {
    optionsPopover?.close()
    let popup=NSPopover()
    let panel=ResultRefreshPanel(seconds:effectiveRefreshSeconds) { [weak self,weak popup] seconds in
      self?.setAutoRefresh(seconds);popup?.close()
    }
    optionsPopover=popup;StudioPopover.show(popup,content:panel,from:autoRefreshButton,size:NSSize(width:420,height:280))
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
      let a = StudioAlert(role:"resultExportBusy")
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
    export.isHidden = true
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
      } catch is CancellationError {} catch { StudioAlert(role:"resultExportError",error:error).runModal() }
      self?.cancelExport.isHidden = true
      self?.exportJob = nil
      self?.syncNavigation()
    }
    syncDataActions()
  }

}
