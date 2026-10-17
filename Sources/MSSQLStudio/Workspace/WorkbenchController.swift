import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WorkbenchController: NSViewController, NSToolbarDelegate, NSOutlineViewDataSource,
  NSOutlineViewDelegate, NSMenuDelegate, NSUserInterfaceValidations
{
  lazy var tabSwitcher=QueryTabSwitcher(owner:self)
  let state: StudioState
  var focusedWindowProvider:()->NSWindow? = {NSApp.keyWindow}
  var explorerTransferBusy=false
  var updateInProgress=false
  var updateProgress:UpdateProgressController?
  let triggerStateAction=TriggerStateAction()
  let split = NSSplitViewController()
  let explorer = NSViewController()
  let center = NSViewController()
  let outline = StudioCommandOutlineView()
  let explorerSearch = StudioSearchField(frame:.zero)
  let searchOperator = StudioSelectionControl()
  let searchScopePicker = StudioSearchablePopUpButton()
  let searchType = StudioSelectionControl()
  let searchFilters = NSStackView()
  var searchScopes: [TreeNode] = []
  var searchDatabaseByServer: [UUID:String] = [:]
  var explorerRevealTask:Task<Void,Never>?
  var explorerRevealID=UUID()
  let indexStatus = StudioToolbarButton(symbol: "externaldrive", label: "Yerel indeks durumu ve işlemleri", tone: .neutral, width: 26)
  let explorerIndexStatuses=ExplorerIndexStatusController()
  var indexPopover:NSPopover?
  var indexStatusTask: Task<Void,Never>?
  var lastIndexStatusCheck = Date.distantPast
  var lastIndexStatusScope = ""
  let searchStatus = NSTextField(labelWithString: "Seçili veritabanı / nesne türünde ara")
  var searchScope: TreeNode?
  let explorerTabs = StudioTabControl(items:[.init(id:0,title:"Bağlantılar",icon:"square.stack.3d.up"),.init(id:1,title:"Arama",icon:"magnifyingglass")])
  var showingSearch = false
  var savedExpanded: [TreeNode] = []
  var savedTreeSelection: TreeNode?
  var savedTreeOrigin = NSPoint.zero
  var searchResults: [TreeNode]?
  let explorerSearchController = ExplorerSearchController()
  let explorerToggle = StudioToolbarButton(symbol: "sidebar.left", label: "Object Explorer’ı Göster / Gizle", tone: .neutral)
  let tabs = QueryTabStrip()
  let content = NSView()
  let database = StudioSearchablePopUpButton()
  let executionDate = NSTextField(labelWithString:"Son çalıştırma: —")
  let statusStrip = NSStackView()
  let resultSelectionStatus=NSTextField(labelWithString:"")
  let status = NSTextField(labelWithString: "Bağlantı bekleniyor")
  let context = NSTextField(labelWithString: "")
  private let queryToolbarHost=NSView()
  private weak var hostedQuery:QueryController?
  let explorerTree = ExplorerTreeModel()
  var roots:[TreeNode] {get {explorerTree.roots} set {explorerTree.roots=newValue}}
  var organization:ExplorerOrganization {explorerTree.organization}
  var displayRoots:[TreeNode] {explorerTree.displayRoots}
  var restoringTree=false
  weak var collapsingNode:TreeNode?
  var expansionState:[String:Bool] {get {explorerTree.expansionState} set {explorerTree.expansionState=newValue}}
  private var agentPolling: Task<Void,Never>?
  var agentAutoRefresh = true
  private var tabSignature: [String]?
  private var controllers: [UUID: QueryController] = [:]
  var auxiliaryWindows: [NSWindowController] = []
  lazy var profilerLauncher=MonitoringToolLauncher(owner:self,tool:.profiler)
  lazy var activityLauncher=MonitoringToolLauncher(owner:self,tool:.activity)
  var profilerWindows:[UUID:ProfilerWindowController]=[:]
  var contextNode: TreeNode?
  var sheet: NSWindow?
  private var connectionSheetBusy=false
  var detached: [UUID: DetachedQueryWindow] = [:]
  var sidebar: NSSplitViewItem!
  init(state: StudioState) {
    self.state = state
    explorerTree.expansionState=state.explorerTreeDefaults.dictionary(forKey:"explorerExpansionState") as? [String:Bool] ?? [:]
    super.init(nibName: nil, bundle: nil)
    NotificationCenter.default.addObserver(self,selector:#selector(updateExplorerDensity),name:ExplorerDensity.changed,object:nil)
    NotificationCenter.default.addObserver(self,selector:#selector(explorerConnectionChanged(_:)),name:ConnectedServer.explorerConnectionChanged,object:nil)
    NotificationCenter.default.addObserver(self,selector:#selector(agentChanged(_:)),name:.init("studioAgentChanged"),object:nil)
    NotificationCenter.default.addObserver(self, selector: #selector(refreshShortcuts), name: GridShortcuts.changed, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(themeChanged), name: StudioTheme.changed, object: nil)
    for name in [NSWindow.didEnterFullScreenNotification,NSWindow.didExitFullScreenNotification] {
      NotificationCenter.default.addObserver(self,selector:#selector(windowPresentationChanged(_:)),name:name,object:nil)
    }
    NotificationCenter.default.addObserver(self, selector: #selector(refreshChangedObjects(_:)), name: .init("studioDDLCompleted"), object: nil)
    NotificationCenter.default.addObserver(self,selector:#selector(refreshManagedObject(_:)),name:.init("studioManagedObjectCompleted"),object:nil)
    NotificationCenter.default.addObserver(self, selector: #selector(catalogIndexUpdated(_:)), name: .init("catalogIndexUpdated"), object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(catalogIndexUpdated(_:)), name: .init("sqlCatalogChanged"), object: nil)
    NotificationCenter.default.addObserver(self,selector:#selector(schemaApplied(_:)),name:.init("studioSchemaComparedApplied"),object:nil)
    NotificationCenter.default.addObserver(self,selector:#selector(favoritesChanged),name:FavoriteQueriesModel.changed,object:state.favorites)
    NotificationCenter.default.addObserver(self,selector:#selector(favoriteWindowClosed(_:)),name:NSWindow.willCloseNotification,object:nil)
    NotificationCenter.default.addObserver(self,selector:#selector(toolWindowVisibilityChanged(_:)),name:StudioAssociatedWindow.visibilityChanged,object:nil)
    for name in [NSWindow.willCloseNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification] {NotificationCenter.default.addObserver(self,selector:#selector(toolWindowVisibilityChanged(_:)),name:name,object:nil)}
    state.changed = { [weak self] in self?.reloadWorkspace() }
  }
  deinit {agentPolling?.cancel();explorerRevealTask?.cancel()}
  @objc private func windowPresentationChanged(_ notification:Notification) {
    guard isViewLoaded,let window=notification.object as? NSWindow,window === view.window else {return}
    StudioTheme.decorate(tabs)
    (tabs.enclosingScrollView as? QueryTabScrollView)?.revealActiveTab()
    tabs.needsDisplay=true
  }
  @objc func themeChanged() {
    tabSignature=nil
    guard isViewLoaded else { return }
    StudioTheme.decorate(view)
    for item in view.window?.toolbar?.items ?? [] {
      (item.view as? StudioToolbarButton)?.refreshStyle()
    }
    reloadWorkspace()
  }
  required init?(coder: NSCoder) { fatalError() }
  override func loadView() {
    view = NSView()
    StudioTheme.surface(view, chrome: true)
    split.splitView.isVertical = true
    split.splitView.autosaveName="MSSQLStudio.ExplorerWidths"
    buildExplorer()
    buildCenter()
    sidebar = NSSplitViewItem(sidebarWithViewController: explorer)
    sidebar.canCollapse = false
    sidebar.canCollapseFromWindowResize = false
    sidebar.minimumThickness = 140
    sidebar.maximumThickness = 760
    sidebar.preferredThicknessFraction = 0.22
    split.addSplitViewItem(sidebar)
    split.addSplitViewItem(NSSplitViewItem(viewController: center))
    addChild(split)
    view.addSubview(split.view)
    split.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      split.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      split.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
      split.view.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
      split.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
    ])
    sidebar.isCollapsed=UserDefaults.standard.bool(forKey:"explorerCollapsed")
    reloadWorkspace()
    tabSwitcher.install()
    Task { [weak self] in await self?.state.favorites.load() }
  }
  private func buildCenter() {
    center.view = NSView()
    StudioTheme.surface(center.view, card: true)
    tabs.reorder = { [weak self] id,index in self?.moveQueryTab(id,to: index) }
    tabs.orientation = .horizontal
    tabs.alignment = .centerY
    tabs.spacing = 3
    tabs.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
    let tabScroll = QueryTabScrollView()
    tabScroll.documentView = tabs
    tabScroll.hasHorizontalScroller = false
    tabScroll.scrollerStyle = .overlay
    tabScroll.horizontalScroller?.controlSize = .small
    tabScroll.autohidesScrollers = true
    tabScroll.drawsBackground = true
    tabs.frame=NSRect(x:0,y:0,width:12,height:36)
    tabs.translatesAutoresizingMaskIntoConstraints = true
    tabs.autoresizingMask=[]
    tabs.detachesHiddenViews=false
    database.target = self
    database.action = #selector(changeDatabase)
    database.setAccessibilityIdentifier("databaseSelector")
    context.font = .systemFont(ofSize: 11)
    context.textColor = .secondaryLabelColor
    context.lineBreakMode = .byTruncatingMiddle
    context.setContentCompressionResistancePriority(.init(200),for:.horizontal)
    explorerToggle.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Object Explorer’ı Göster / Gizle")
    explorerToggle.target = self; explorerToggle.action = #selector(toggleExplorer)
    explorerToggle.bezelStyle = .inline; explorerToggle.isBordered = false
    explorerToggle.toolTip = "Object Explorer’ı Göster / Gizle"
    queryToolbarHost.setAccessibilityIdentifier("queryToolbarHost")
    queryToolbarHost.isHidden=true
    let row = NSStackView(views: [explorerToggle, database, queryToolbarHost, context])
    row.setAccessibilityIdentifier("queryContextToolbar")
    StudioTheme.surface(row)
    row.orientation = .horizontal
    row.spacing = 8
    row.edgeInsets = NSEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)
    database.leadingSymbol="square.on.square"
    database.controlSize = .small
    database.widthAnchor.constraint(equalToConstant: 170).isActive = true
    status.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
    status.textColor = .secondaryLabelColor
    status.lineBreakMode = .byTruncatingTail
    status.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    let statusRow = statusStrip
    executionDate.font = .monospacedSystemFont(ofSize:10,weight:.regular)
    executionDate.textColor=StudioTheme.muted
    executionDate.lineBreakMode = .byTruncatingTail
    executionDate.setAccessibilityIdentifier("queryLastExecutionDate")
    let divider=NSBox();divider.boxType = .separator
    resultSelectionStatus.font = .monospacedDigitSystemFont(ofSize:10,weight:.medium)
    resultSelectionStatus.isSelectable=true;resultSelectionStatus.lineBreakMode = .byTruncatingMiddle
    resultSelectionStatus.setAccessibilityIdentifier("resultSelectionSummaryValues")
    resultSelectionStatus.setContentCompressionResistancePriority(.init(751),for:.horizontal)
    resultSelectionStatus.widthAnchor.constraint(lessThanOrEqualToConstant:340).isActive=true
    executionDate.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    statusRow.setViews([status,NSView(),resultSelectionStatus,divider,executionDate],in:.center)
    divider.widthAnchor.constraint(equalToConstant:1).isActive=true
    divider.heightAnchor.constraint(equalToConstant:14).isActive=true
    statusRow.spacing=10
    StudioTheme.statusSurface(statusRow)
    statusRow.edgeInsets = NSEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)
    let stack = NSStackView(views: [tabScroll, row, separator(), content, separator(), statusRow])
    stack.orientation = .vertical
    stack.distribution = .fill
    stack.spacing = 0
    center.view.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: center.view.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: center.view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: center.view.topAnchor),
      stack.bottomAnchor.constraint(equalTo: center.view.bottomAnchor),
      tabScroll.heightAnchor.constraint(equalToConstant: 36),
      tabScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
      row.widthAnchor.constraint(equalTo: stack.widthAnchor),
      content.widthAnchor.constraint(equalTo: stack.widthAnchor),
      statusRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
      row.heightAnchor.constraint(equalToConstant: 34),
      queryToolbarHost.heightAnchor.constraint(equalToConstant:28),
      statusRow.heightAnchor.constraint(equalToConstant: 26),
    ])
    content.setContentHuggingPriority(.init(1), for: .vertical)
    content.setContentCompressionResistancePriority(.init(1), for: .vertical)
  }
  func embed(_ child: NSView, in parent: NSView) {
    parent.addSubview(child)
    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
      child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
      child.topAnchor.constraint(equalTo: parent.topAnchor),
      child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])
  }
  func separator() -> NSView {
    let box = NSBox()
    box.boxType = .separator
    return box
  }
  func symbolButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
    let button = StudioToolbarButton(symbol: symbol, label: tip, tone: .neutral, width: 26)
    button.target = self; button.action = action
    return button
  }
  var selected: TreeNode? { outline.item(atRow: outline.selectedRow) as? TreeNode }
  var selectedServer: ConnectedServer? {
    (selected?.connectionGroupID == nil ? selected?.server:nil) ?? state.active?.server ?? state.servers.first(where: \.online) ?? state.servers.first
  }
  static func queryDatabase(for node: TreeNode) -> String {
    switch node.kind {
    case .server, .group, .folder(.databases), .folder(.logins), .folder(.linkedServers), .folder(.jobs), .folder(.schedules): return node.server.profile.database
    default: return node.database.isEmpty ? node.server.profile.database : node.database
    }
  }
  var selectedDatabase: String {
    if let node = selected,node.connectionGroupID == nil { return Self.queryDatabase(for: node) }
    return state.active?.database ?? selectedServer?.profile.database ?? "master"
  }
  func moveQueryTab(_ id: UUID, to insertionIndex: Int) {
    guard let old = state.documents.firstIndex(where: { $0.id == id }) else { return }
    let document = state.documents.remove(at: old)
    let adjusted = insertionIndex > old ? insertionIndex - 1 : insertionIndex
    let pinnedCount=state.documents.filter(\.pinned).count
    let range=document.pinned ? 0...pinnedCount:pinnedCount...state.documents.count
    state.documents.insert(document,at: min(range.upperBound,max(range.lowerBound,adjusted)))
    state.scheduleSnapshot(); renderTabs()
  }
  @objc func refreshShortcuts() {
    func update(_ menu: NSMenu) {
      for item in menu.items {
        StudioCommandCatalog.decorate(item)
        if item.action == #selector(SQLTextView.toggleSQLComment(_:)) || item.action == #selector(SQLTextView.uncommentSQL(_:)) {
          let binding=GridShortcuts.binding(item.action == #selector(SQLTextView.toggleSQLComment(_:)) ? .comment:.uncomment)
          item.keyEquivalent=binding.key;item.keyEquivalentModifierMask=binding.flags
        }
        if item.action == #selector(SQLTextView.formatSQLText(_:)) || item.action == #selector(formatSQL) {
          let binding = GridShortcuts.binding(.format)
          item.keyEquivalent = binding.key; item.keyEquivalentModifierMask = binding.flags
        }
        if item.action == #selector(showHistory) || item.action == #selector(reopenLastClosedTab) {
          let binding=GridShortcuts.binding(item.action == #selector(showHistory) ? .history:.reopenTab)
          item.keyEquivalent=binding.key;item.keyEquivalentModifierMask=binding.flags
        }
        if item.action == #selector(newQuery) {
          let binding = GridShortcuts.binding(.newQuery)
          item.keyEquivalent = binding.key; item.keyEquivalentModifierMask = binding.flags
        }
        if item.action == #selector(showFavorites) {
          let binding = GridShortcuts.binding(.favorites)
          item.keyEquivalent = binding.key; item.keyEquivalentModifierMask = binding.flags
        }
        if let child = item.submenu { update(child) }
      }
    }
    if let menu = NSApp.mainMenu { update(menu) }
    if isViewLoaded {
      for item in view.window?.toolbar?.items ?? [] {
        let help=StudioCommandCatalog.help(item.label,selector:item.action)
        if let button=item.view as? StudioToolbarButton {button.toolTip=help;item.toolTip=nil}
        else {item.toolTip=help}
      }
      renderTabs()
    }
  }
  private func reloadWorkspace() {
    guard isViewLoaded else { return }
    let selection=outline.selectedRowIndexes.compactMap {outline.item(atRow:$0) as? TreeNode}
    if explorerTree.synchronizeServers(state.servers) {
      contextNode=nil; savedTreeSelection=nil; savedExpanded=[]
      explorerSearchController.cancel();searchResults=nil
      indexStatusTask?.cancel();indexPopover?.performClose(nil)
      lastIndexStatusScope=""; indexStatus.toolTip="İndeks durumu için bağlantı seçin"
    }
    explorerIndexStatuses.retain(servers:Set(state.servers.map(\.id)))
    for root in roots {synchronizeFavorites(in:root)}
    rebuildOrganizationRoots()
    rebuildSearchScopes()
    reloadExplorer()
    restoreExplorerExpansion()
    let restored=IndexSet(selection.compactMap {node -> Int? in let row=outline.row(forItem:node);return row>=0 ? row:nil})
    if !restored.isEmpty {outline.selectRowIndexes(restored,byExtendingSelection:false)}
    renderTabs()
    renderActive()
    updateControls()
  }
  private func renderTabs() {
    if agentPolling == nil {
      agentPolling=Task { [weak self] in
        while !Task.isCancelled {
          do {try await Task.sleep(for:.seconds(15))} catch {return}
          guard self != nil else {return}
          await self?.checkExplorerConnections()
          await self?.refreshExpandedAgentJobs()
        }
      }
    }
    let signature=state.documents.map {doc in
      "\(doc.id)|\(doc.title)|\(doc.needsCloseConfirmation)|\(doc.pinned)|\(doc.busy)|\(state.active === doc)|\(doc.server.profile)|\(organization.color(for:doc.server.id) ?? "")"
    }
    guard signature != tabSignature else {return}
    tabSignature=signature
    tabs.resetDragPreview()
    tabs.documentIDs = state.documents.map(\.id)
    for view in tabs.arrangedSubviews {
      tabs.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    for doc in state.documents {
      let button = DocumentButton(
        title: (doc.needsCloseConfirmation ? "● " : "") + doc.title, target: self, action: #selector(selectTab(_:)))
      button.document = doc
      button.draggable = true
      button.showMenu = { [weak self, weak button] event in
        guard let button else { return }
        self?.showTabMenu(doc, event: event, view: button)
      }
      button.bezelStyle = .inline
      button.isBordered = false
      button.state = state.active === doc ? .on : .off
      button.font = .systemFont(ofSize: 12)
      let close = QueryTabCloseButton(
        image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Sekmeyi kapat")!,
        target: self, action: #selector(closeSpecificTab(_:)))
      close.document = doc
      close.bezelStyle = .inline
      close.isBordered = false
      close.controlSize = .small
      close.toolTip="Sekmeyi kapat · \(doc.title)"
      close.setAccessibilityIdentifier("closeQueryTab_"+doc.id.uuidString)
      close.widthAnchor.constraint(equalToConstant:24).isActive=true
      close.heightAnchor.constraint(equalToConstant:24).isActive=true
      let group = QueryTabSurface(views: [button, close])
      group.primaryButton = button
      button.selectionSurface=group
      group.identifier = NSUserInterfaceItemIdentifier("connectionAccent")
      group.sourceColor=sourceColor(for:doc.server)
      button.font = .systemFont(ofSize: 12, weight: state.active === doc ? .medium : .regular)
      group.configure(active:state.active === doc)
      close.refreshStyle()
      let icon = NSImageView(image: NSImage(systemSymbolName: doc.pinned ? "pin.fill" : "externaldrive", accessibilityDescription: doc.pinned ? "Sabitlenmiş sekme" : nil)!)
      icon.contentTintColor = sourceColor(for:doc.server) ?? StudioTheme.accent
      icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
      icon.heightAnchor.constraint(equalToConstant: 14).isActive = true
      if doc.busy {
        let progress=NSProgressIndicator();progress.style = .spinning;progress.isIndeterminate=true;progress.controlSize = .small
        progress.setAccessibilityLabel("Sekmede işlem sürüyor")
        progress.widthAnchor.constraint(equalToConstant:14).isActive=true
        progress.heightAnchor.constraint(equalToConstant:14).isActive=true
        progress.startAnimation(nil);group.insertArrangedSubview(progress,at:0)
      } else {group.insertArrangedSubview(icon, at: 0)}
      button.toolTip =
        "\(doc.server.profile.appearance?.badge ?? "") · \(doc.server.profile.name) · \(doc.database)"
      group.spacing = 6
      group.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 4)
      // Stable title sizing must not inherit a stretched frame from the previous selection.
      let titleWidth=ceil((button.title as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.medium)]).width)+12
      button.widthAnchor.constraint(equalToConstant:max(100,titleWidth)).isActive=true
      group.widthAnchor.constraint(equalToConstant:max(100,titleWidth)+62).isActive=true
      tabs.addView(group,in:.leading)
    }
    let plus = symbolButton("plus", tip: "Yeni Sorgu (\(GridShortcuts.binding(.newQuery).label))", action: #selector(newQuery))
    tabs.addView(plus,in:.leading)
    if tabSwitcher.panel != nil {tabSwitcher.refreshHighlight()}
    else {(tabs.enclosingScrollView as? QueryTabScrollView)?.revealActiveTab()}
  }
  private func renderActive() {
    var initialFocus: QueryController?
    let wanted: NSView
    if let doc = state.active, detached[doc.id] == nil {
      let controller: QueryController
      if let existing = controllers[doc.id] {
        controller = existing
      } else {
        doc.openDefinition = { [weak self, weak doc] symbol in
          guard let self, let doc else { return }; self.openEditorDefinition(symbol,document:doc)
        }
        doc.openDefinitionNamed = { [weak self,weak doc] parts in
          guard let self,let doc else {return};openDefinitionReference(parts,document:doc)
        }
        doc.openOfflineReference = { [weak self,weak doc] parts,server,db in
          guard let self,let doc else {return};openOfflineDefinition(named:parts,server:server,database:db,in:doc)
        }
        doc.revealInExplorer = { [weak self,weak doc] parts,server,database in
          guard let self,let doc else {return};revealExplorerObject(parts,document:doc,targetServer:server,targetDatabase:database)
        }
        controller = QueryController(document: doc)
        initialFocus = controller
        controller.favorites=state.favorites
        controller.favoriteRequested = { [weak self] doc in self?.presentFavoriteEditor(for:doc) }
        controller.changed = { [weak self] in
          self?.updateControls()
          self?.renderTabs()
          self?.state.scheduleSnapshot()
        }
        controller.selectionStatusChanged = { [weak self,weak controller] in
          guard let self,let controller else {return}
          let id=controller.document.id
          if let owner=detached[id] {owner.updateStatus()}
          else if state.active?.id==id {updateSelectionStatus()}
        }
        controllers[doc.id] = controller
        addChild(controller)
      }
      wanted = controller.view
      if hostedQuery !== controller {
        hostedQuery?.hostEditorToolbar(in:nil)
        controller.hostEditorToolbar(in:queryToolbarHost);hostedQuery=controller
        queryToolbarHost.isHidden=false
        initialFocus=controller
      }
    } else {
      hostedQuery?.hostEditorToolbar(in:nil);hostedQuery=nil;queryToolbarHost.isHidden=true
      if content.subviews.first?.identifier?.rawValue == "welcome" { return }
      let host = NSHostingView(
        rootView: WelcomeView(connect: { [weak self] in self?.showConnect() }))
      host.identifier = .init("welcome")
      wanted = host
    }
    if content.subviews.first === wanted { return }
    for subview in content.subviews { subview.removeFromSuperview() }
    embed(wanted, in: content)
    if let initialFocus, let id=state.active?.id {
      DispatchQueue.main.async { [weak self, weak initialFocus] in
        guard let self,state.active?.id == id,detached[id] == nil,
          content.subviews.first === initialFocus?.view,view.window?.attachedSheet == nil,
          focusedWindowProvider() == nil || focusedWindowProvider() === view.window else {return}
        initialFocus?.focusEditor()
      }
    }
  }
  private func updateSelectionStatus() {
    let value=state.active.flatMap {detached[$0.id]==nil ? controllers[$0.id]?.selectionStatus:nil}
    resultSelectionStatus.stringValue=value?.text ?? ""
    resultSelectionStatus.toolTip=value?.help
    resultSelectionStatus.isHidden=value==nil
  }
  func updateControls() {
    guard isViewLoaded else { return }
    updateIndexStatus()
    updateSelectionStatus()
    let doc = state.active
    executionDate.stringValue="Son çalıştırma: " + (doc?.lastExecutionDate?.formatted(date:.numeric,time:.standard) ?? "—")
    for controller in controllers.values { controller.updateConnectionAppearance() }
    for owner in detached.values { owner.updateConnectionAppearance() }
    if let doc {
      let names = doc.server.databases.map(\.name)
      database.updateChoices(names.contains(doc.database) ? names:[doc.database]+names,selected:doc.database,contextID:doc.id,enabled:!doc.busy && doc.offlinePreview == nil)
      context.stringValue = "\(doc.server.profile.name) · \(doc.server.profile.host),\(doc.server.profile.port)  •  \(doc.server.profile.login)"
      context.toolTip=context.stringValue+" · "+(doc.server.profile.appearance?.badge ?? "")
      context.textColor = .secondaryLabelColor
      let phase: String
      switch doc.state {
      case .disconnected: phase = doc.disconnectedStatus
      case .connecting: phase = "Connecting…"
      case .ready: phase = doc.offlinePreview != nil ? "Çevrimdışı tanım · Salt okunur" : doc.definitionLoading ? "Nesne tanımı yükleniyor…" : "Ready"
      case .running: phase = "Executing…"
      case .cancelling: phase = "Cancelling…"
      }
      let operation=state.connectionActivities[doc.server.id] ?? (doc.server.reconnecting ? "Explorer yeniden bağlanıyor…" : doc.server.updatingProfile ? "Bağlantı ayarları kaydediliyor…" : connectionSheetBusy ? "Bağlantı yönetimi işlemi sürüyor…" : nil)
      let displayPhase=operation ?? state.connectionErrors[doc.server.id].map {"Explorer bağlantısı başarısız: " + $0} ?? (doc.offlinePreview != nil ? "Çevrimdışı tanım · Salt okunur" : doc.definitionLoading ? "Nesne tanımı yükleniyor…" : phase)
      let loaded = doc.results.filter { !$0.isPlan }.reduce(0) { $0 + $1.values.count }
      let shown = doc.results.filter { !$0.isPlan }.reduce(0) { $0 + min($1.values.count, max(1, doc.limits.rows)) }
      let rows = shown < loaded ? "\(shown.formatted()) gösterilen · \(loaded.formatted()) yüklenen" : "\(doc.rowCount.formatted()) rows"
      status.toolTip=doc.connectionError ?? state.connectionErrors[doc.server.id] ?? doc.server.startupError
      status.setAccessibilityIdentifier("queryStatus")
      status.stringValue =
        "\(displayPhase)   |   \(doc.database)   |   \(rows)   |   \(String(format:"%.3f",doc.elapsed)) s\(doc.partial ? "   |   PARTIAL" : "")\(doc.transactionCount > 0 ? "   |   TRAN: \(doc.transactionCount)" : "")"
    } else {
      database.updateChoices([],selected:nil,contextID:nil,enabled:false)
      context.stringValue = ""
      status.stringValue = (connectionSheetBusy ? "Bağlantı yönetimi işlemi sürüyor…" : nil) ?? state.connectionActivities.values.sorted().first ?? state.connectionErrors.values.sorted().first ?? selectedServer?.startupError ?? (
        state.servers.isEmpty ? "Connect to SQL Server" : "Yeni bir sorgu açın veya nesne seçin")
    }
    for item in view.window?.toolbar?.items ?? [] {
      switch item.itemIdentifier.rawValue {
      case "run", "plan": item.isEnabled = doc?.canExecute == true
      case "cancel": item.isEnabled = doc?.state == .running || doc?.state == .connecting
      case "save", "format": item.isEnabled = doc != nil
      case "query", "profiler": item.isEnabled = selectedServer != nil
      default: break
      }
      (item.view as? NSControl)?.isEnabled = item.isEnabled
    }
    view.window?.title =
      doc.map { "\($0.title) — \($0.server.profile.name) / \($0.database)" } ?? "MSSQL Studio"
  }
  @discardableResult func activateObjectEditor(server:ConnectedServer,database:String,objectID:Int) -> Bool {
    let key=ObjectEditorKey(serverID:server.id,database:database,objectID:objectID)
    guard let doc=state.documents.first(where:{$0.objectEditorKey == key && $0.database == database}) else {return false}
    if let source=state.active,source !== doc,detached[doc.id] == nil,
      let index=state.documents.firstIndex(where:{$0 === source}) {moveQueryTab(doc.id,to:index+1)}
    state.active=doc;state.changed?()
    if let owner=detached[doc.id] {owner.showWindow(nil);owner.query.focusEditor()}
    else {controllers[doc.id]?.focusEditor()}
    return true
  }
  @discardableResult func openObjectEditor(server:ConnectedServer,database:String,objectID:Int,sql:String,title:String,original:String?=nil) -> QueryDocument {
    if activateObjectEditor(server:server,database:database,objectID:objectID),let doc=state.active {return doc}
    let doc=state.newQuery(server:server,database:database,text:sql,title:title)
    doc.objectEditorKey=ObjectEditorKey(serverID:server.id,database:database,objectID:objectID)
    if let original {doc.moduleOriginal=original;doc.moduleInitialSQL=sql;doc.moduleObjectID=objectID}
    doc.changed?()
    return doc
  }
  private func showTabMenu(_ document: QueryDocument, event: NSEvent, view: NSView) {
    NSMenu.popUpContextMenu(tabMenu(for: document), with: event, for: view)
  }
  func tabMenu(for document: QueryDocument) -> NSMenu {
    let menu = StudioMenu()
    for (index, title) in [document.pinned ? "Unpin Tab" : "Pin Tab", "Close Tab", "Close Right Tabs", "Close Left Tabs", "Close Other Tabs", "Close All Tabs"].enumerated() {
      if index==1 || index==5 {menu.addItem(.separator())}
      let item = menu.addItem(withTitle: title, action: #selector(tabMenuAction(_:)), keyEquivalent: "")
      item.target = self; item.tag = index; item.representedObject = document
    }
    menu.addItem(.separator())
    for (title,action,shortcut) in [("Kapatılan Sekmeyi Aç",#selector(reopenLastClosedTab),GridShortcuts.Action.reopenTab),("History…",#selector(showHistory),.history)] {
      let binding=GridShortcuts.binding(shortcut)
      let item=NSMenuItem(title:title,action:action,keyEquivalent:binding.key);item.target=self;item.keyEquivalentModifierMask=binding.flags
      if shortcut == .reopenTab {item.representedObject=document;item.isEnabled=state.lastClosedTab(for:document) != nil}
      menu.addItem(item)
    }
    for item in menu.items {StudioCommandCatalog.decorate(item)}
    return menu
  }
  @objc private func tabMenuAction(_ item: NSMenuItem) {
    guard let doc = item.representedObject as? QueryDocument,
      let index = state.documents.firstIndex(where: { $0 === doc }) else { return }
    if item.tag == 5 {Task { @MainActor [weak self] in self?.requestCloseAllTabs() };return}
    if item.tag == 0 {
      guard let index=state.documents.firstIndex(where:{$0 === doc}) else {return}
      state.documents.remove(at:index)
      doc.pinned.toggle()
      state.documents=state.documents.filter(\.pinned)+state.documents.filter {!$0.pinned}
      let destination=doc.pinned ? 0:state.documents.filter(\.pinned).count
      state.documents.insert(doc,at:destination)
      state.scheduleSnapshot();renderTabs();return
    }
    let targets = state.documents.enumerated().filter { i, candidate in
      switch item.tag {
      case 1: return candidate === doc
      case 2: return i > index && !candidate.pinned
      case 3: return i < index && !candidate.pinned
      case 4: return candidate !== doc && !candidate.pinned
      default: return true
      }
    }.map(\.element)
    for target in targets {
      guard state.close(target) else { break }
      controllers.removeValue(forKey: target.id)?.removeFromParent()
      if let owner = detached.removeValue(forKey: target.id) { owner.redock = nil; owner.close() }
    }
  }
  func requestCloseAllTabs() {
    guard state.canBeginBulkClose() else {return}
    guard state.needsBulkCloseConfirmation else {closeAllWithoutSaving();return}
    if let existing=auxiliaryWindows.compactMap(\.window).first(where:{$0.identifier?.rawValue=="studio.bulkClose" && $0.isVisible}) {existing.makeKeyAndOrderFront(nil);return}
    let owner=StudioCloseWindowController(title:"Tüm sorgu sekmelerini kapat",count:state.documents.count) {[weak self] choice in
      guard let self else {return true}
      if choice == .cancel {return true}
      guard state.approveBulkClose(choice) else {return false}
      closeAllWithoutSaving();return true
    }
    auxiliaryWindows.append(owner)
    owner.closed={ [weak self,weak owner] in Task { @MainActor [weak self,weak owner] in self?.auxiliaryWindows.removeAll {$0 === owner} } }
    (owner.window as? StudioAssociatedWindow)?.associate(with:view.window)
    owner.showWindow(nil);owner.window?.makeKeyAndOrderFront(nil)
  }
  @objc func closeAllWithoutSaving() {
    guard state.documents.allSatisfy({!$0.busy && $0.transactionCount == 0 && $0.closeOperationBlocked?() != true}) else {
      state.showError("Tüm sekmeleri kapatmadan önce çalışan sorguları ve açık transaction’ları tamamlayın.");return
    }
    for target in state.documents {
      guard state.close(target,discardChanges:true) else {return}
      controllers.removeValue(forKey:target.id)?.removeFromParent()
      if let owner=detached.removeValue(forKey:target.id) {owner.redock=nil;owner.close()}
    }
  }
  @objc private func selectTab(_ sender: DocumentButton) {
    guard let doc = sender.document else { return }
    activateQueryTab(doc)
  }
  func activateQueryTab(_ doc:QueryDocument) {
    guard state.documents.contains(where:{$0 === doc}) else {return}
    state.active = doc
    if let window = detached[doc.id] { window.showWindow(nil) }
    renderTabs()
    renderActive()
    updateControls()
  }
  @objc private func closeSpecificTab(_ sender: DocumentButton) {
    if let doc = sender.document, state.close(doc) {
      controllers.removeValue(forKey: doc.id)?.removeFromParent()
      if let owner = detached.removeValue(forKey: doc.id) {
        owner.redock = nil
        owner.close()
      }
    }
  }
  @objc func closeFocusedWindow() {
    if let panel=(NSApp.modalWindow ?? focusedWindowProvider()) as? NSSavePanel {panel.cancel(nil);return}
    guard NSApp.modalWindow == nil,let key=focusedWindowProvider() else {return}
    if let sheet=key.attachedSheet {sheet.performClose(nil);return}
    if key !== view.window {key.performClose(nil);return}
    closeTab()
  }
  @objc func closeTab() {
    if let doc = state.active, state.close(doc) {
      controllers.removeValue(forKey: doc.id)?.removeFromParent()
      if let owner = detached.removeValue(forKey: doc.id) {
        owner.redock = nil
        owner.close()
      }
    }
  }
  @objc private func changeDatabase() {
    if let name = database.titleOfSelectedItem { state.active?.useDatabase(name) }
  }
  @objc func newQuery() {
    guard let server = selectedServer else {
      showConnect()
      return
    }
    openNewQuery(server:server,database:selectedDatabase)
  }
  func queryController(for document:QueryDocument)->QueryController? {detached[document.id]?.query ?? controllers[document.id]}
  func openNewQuery(server:ConnectedServer,database:String) {
    state.newQuery(server:server,database:database)
  }

  var commandDocument:QueryDocument? {
    if let key=focusedWindowProvider() {
      if let detached=detached.values.first(where:{$0.window === key}) {return detached.query.document}
      if key !== view.window {return nil}
    }
    return state.active
  }
  @objc func execute() {guard let doc=commandDocument,doc.canExecute else {return};(controllers[doc.id] ?? detached[doc.id]?.query)?.focusEditor();doc.execute()}
  @objc func cancel() { commandDocument?.cancel() }
  @objc func estimatedPlan() {guard let doc=commandDocument,doc.canExecute else {return};(controllers[doc.id] ?? detached[doc.id]?.query)?.focusEditor();doc.execute(estimated:true)}
  @objc func toggleActualPlan() {
    if let doc = commandDocument {
      doc.actualPlan.toggle()
      controllers[doc.id]?.update()
      updateControls()
    }
  }
  @objc func formatSQL() {
    if let doc = commandDocument {
      (controllers[doc.id] ?? detached[doc.id]?.query)?.format()
      renderTabs()
      state.scheduleSnapshot()
    }
  }
  @objc func beginTransaction() { commandDocument?.execute(override: "BEGIN TRANSACTION;") }
  @objc func commitTransaction() { commandDocument?.execute(override: "COMMIT;") }
  @objc func rollbackTransaction() { commandDocument?.execute(override: "ROLLBACK;") }
  @objc func saveSQL() { if let doc = commandDocument { state.save(doc) } }
  @objc func saveAsSQL() { if let doc = commandDocument { state.save(doc, asNew: true) } }
  @objc func openSQL() {
    guard let server = selectedServer else {
      showConnect()
      return
    }
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "sql") ?? .plainText]
    guard panel.runModal() == .OK else { return }
    for url in panel.urls {
      do {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8_000_000 else {
          throw SQLFailure("SQL dosyası 8 MB'dan büyük.")
        }
        if let existing = state.documents.first(where: { $0.file == url }) {
          state.active = existing
          reloadWorkspace()
          continue
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let doc = state.newQuery(
          server: server, database: selectedDatabase, text: text, title: url.lastPathComponent)
        doc.file = url
        doc.savedText = text
        renderTabs()
      } catch { state.showError(error.localizedDescription) }
    }
  }
  @objc func toggleResults() {
    guard let doc = commandDocument else { return }
    (controllers[doc.id] ?? detached[doc.id]?.query)?.toggleResults()
  }
  @objc func showConnect() { presentConnection() }
  @objc func editConnection() {
    if let server = contextNode?.server { presentConnection(editing: server) }
  }
  private func presentConnection(editing server: ConnectedServer? = nil) {
    guard sheet == nil, view.window != nil else { sheet?.makeKeyAndOrderFront(nil);return }
    connectionSheetBusy=false
    let form = ConnectionManager(
      servers: state.servers, initial: server,
      connect: { [weak self] profile, password, save in
        guard let self else { throw SQLFailure("Çalışma alanı kapandı.") }
        let activeBefore=state.active
        let server = try await state.connect(profile, password: password, save: save)
        finishSheet()
        state.completeExplorerConnection(server,previousActive:activeBefore)
        reloadWorkspace()
      }, save: { [weak self] editingServer,profile,password,remember in
        guard let self else {throw SQLFailure("Çalışma alanı kapandı.")}
        try await state.saveConnectionProfile(editingServer,profile:profile,password:password,remember:remember)
        finishSheet();reloadWorkspace()
      }, loadingChanged:{[weak self] busy in
        guard let self else {return};connectionSheetBusy=busy
        sheet?.standardWindowButton(.closeButton)?.isEnabled = !busy
        updateControls()
      }, cancel: { [weak self] in self?.finishSheet() })
    let controller = NSHostingController(
      rootView: form.font(.custom(StudioTheme.uiFont.fontName, size: 12)))
    let sheet = ConnectionPanelWindow(contentViewController: controller)
    sheet.animationBehavior = .none
    sheet.cancelAction={ [weak self] in guard let self,!connectionSheetBusy else {return};finishSheet() }
    sheet.framePersistenceRole="connections"
    sheet.title = "Bağlantılar"
    sheet.styleMask = [.titled,.closable,.resizable]
    controller.sizingOptions=[]
    sheet.setContentSize(NSSize(width:1080,height:700));sheet.minSize=sheet.frameRect(forContentRect:NSRect(x:0,y:0,width:1020,height:640)).size
    sheet.isReleasedWhenClosed=false;sheet.center()
    self.sheet = sheet
    sheet.setFrame(sheet.constrainFrameRect(sheet.frame,to:sheet.screen),display:false)
    sheet.associate(with:view.window)
    controller.view.layoutSubtreeIfNeeded()
    sheet.makeKeyAndOrderFront(nil)
    controller.view.layoutSubtreeIfNeeded()
  }
  private func finishSheet() {
    if let sheet {
      if sheet.sheetParent != nil {sheet.sheetParent?.endSheet(sheet)}
      sheet.orderOut(nil);sheet.close()
    }
    sheet = nil;connectionSheetBusy=false
  }
  @objc func detachQuery() {
    guard let doc = state.active, detached[doc.id] == nil else { return }
    renderActive()
    guard let controller = controllers[doc.id] else { return }
    controller.hostEditorToolbar(in:nil)
    if hostedQuery === controller {hostedQuery=nil;queryToolbarHost.isHidden=true}
    controller.view.removeFromSuperview()
    controller.removeFromParent()
    let owner = DetachedQueryWindow(query: controller)
    owner.redock = { [weak self, weak controller] in
      guard let self, let controller else { return }
      controller.view.removeFromSuperview()
      controller.removeFromParent()
      addChild(controller)
      detached.removeValue(forKey: doc.id)
      state.active = doc
      renderActive()
      updateControls()
    }
    detached[doc.id] = owner
    state.active = state.documents.first { $0 !== doc && detached[$0.id] == nil }
    renderTabs()
    renderActive()
    updateControls()
    owner.showWindow(nil)
  }
  @objc func redockQueries() { for owner in Array(detached.values) { owner.close() } }
  @objc func settings() { showSettingsWindow() }
  @objc func showHistory() { showHistoryWindow() }
  @objc func aiAssistant() { showAIWindow() }
  @objc func extensionsPanel() { showExtensionsWindow() }
  @objc private func indexDesigner() { showIndexWindow(node: contextNode) }
  @objc func jobDesigner() { showJobWindow(node: contextNode) }
  @discardableResult func present<V: View>(_ root: V, title: String, width: CGFloat = 700, height: CGFloat = 560, minWidth:CGFloat=620, minHeight:CGFloat=480,identity:String?=nil) -> NSWindow {
    if let identity,let existing=auxiliaryWindows.compactMap(\.window).first(where:{$0.identifier?.rawValue == identity && $0.isVisible}) {
      existing.makeKeyAndOrderFront(nil);return existing
    }
    let controller = NSHostingController(
      rootView: root.font(.custom(StudioTheme.uiFont.fontName, size: 12)))
    controller.sizingOptions = []
    let window = StudioPanelWindow(contentViewController: controller)
    window.animationBehavior = .none
    window.framePersistenceRole=String(reflecting:V.self)
    if let identity {window.identifier = .init(identity)}
    window.title = title
    window.styleMask = [.titled, .closable, .resizable]
    window.setContentSize(NSSize(width: width, height: height))
    // Minimums describe usable content; the title bar must not consume form space.
    window.contentMinSize = NSSize(width: min(width, minWidth), height: min(height, minHeight))
    window.center()
    // Resolve AppKit's screen-height constraint before the hosting view's first
    // layout instead of letting orderFront change its proposal afterward.
    window.setFrame(window.constrainFrameRect(window.frame,to:window.screen),display:false)
    let owner = NSWindowController(window: window)
    auxiliaryWindows.append(owner)
    window.didClose={ [weak self,weak window] in
      Task { @MainActor [weak self,weak window] in
        guard let window else {return};self?.auxiliaryWindows.removeAll {$0.window === window};window.contentViewController=nil;self?.refreshToolWindowIndicators()
      }
    }
    window.associate(with:view.window)
    window.contentView?.layoutSubtreeIfNeeded()
    owner.showWindow(nil);window.makeKeyAndOrderFront(nil)
    window.contentView?.layoutSubtreeIfNeeded()
    return window
  }
  func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(closeFocusedWindow) {return NSApp.modalWindow is NSSavePanel || NSApp.modalWindow == nil && focusedWindowProvider() != nil}
    if commandDocument == nil,[#selector(execute),#selector(cancel),#selector(estimatedPlan),#selector(toggleActualPlan),#selector(formatSQL),#selector(beginTransaction),#selector(commitTransaction),#selector(rollbackTransaction),#selector(saveSQL),#selector(saveAsSQL),#selector(closeTab),#selector(detachQuery),#selector(closeAllTabs),#selector(closeOtherTabs),#selector(closeLeftTabs),#selector(closeRightTabs),#selector(pinActiveTab),#selector(toggleResults),#selector(reconnectQuery)].contains(item.action) {return false}
    if item.action == #selector(installUpdate) {return !updateInProgress}
    if let menuItem=item as? NSMenuItem,let node=menuItem.representedObject as? TreeNode,
       item.action == #selector(agentMenuAction(_:)) {
      let running=node.item?.detail.contains("Running") == true
      switch menuItem.identifier?.rawValue {
      case "start":return !running
      case "stop":return running
      default:return true
      }
    }
    if item.action == #selector(execute) || item.action == #selector(estimatedPlan) {return commandDocument?.canExecute == true}
    if [
      #selector(beginTransaction),
      #selector(commitTransaction), #selector(rollbackTransaction),
    ].contains(item.action) {
      return state.active?.state == .ready
    }
    if item.action == #selector(addFavorite) {return favoriteContextDocument?.sql.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty == false}
    if item.action == #selector(reopenLastClosedTab) {return state.lastClosedTab(for:(item as? NSMenuItem)?.representedObject as? QueryDocument ?? state.active) != nil}
    if item.action == #selector(cancel) { return state.active?.state == .running || state.active?.state == .connecting }
    if [
      #selector(saveSQL), #selector(saveAsSQL), #selector(formatSQL), #selector(closeTab),
      #selector(toggleResults),
    ]
    .contains(item.action) {
      return state.active != nil
    }
    return true
  }
  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar) + [.space, .flexibleSpace]
  }
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .init("query"), .init("save"), .init("explorerBoundary"), .flexibleSpace, .init("activity"), .init("profiler"), .init("favorites"), .init("history"),
      .init("ai"),
    ]
  }
  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar: Bool
  ) -> NSToolbarItem? {
    if id == .init("explorerBoundary") {return NSTrackingSeparatorToolbarItem(identifier:id,splitView:split.splitView,dividerIndex:0)}
    let definitions: [String: (String, String, Selector)] = [
      "connect": ("Bağlan", "network", #selector(showConnect)),
      "query": ("Yeni Sorgu", "doc.badge.plus", #selector(newQuery)),
      "save": ("Kaydet", "square.and.arrow.down", #selector(saveSQL)),
      "run": ("Çalıştır", "play.fill", #selector(execute)),
      "cancel": ("İptal", "stop.fill", #selector(cancel)),
      "plan": ("Tahmini Plan", "point.3.connected.trianglepath.dotted", #selector(estimatedPlan)),
      "format": ("Formatla", "text.alignleft", #selector(formatSQL)),
      "favorites": ("Favori Sorgular", "star", #selector(showFavorites)),
      "activity": ("Activity", "waveform.path.ecg", #selector(activity)),
      "profiler": ("SQL Profiler", "list.bullet.rectangle.portrait", #selector(profiler)),
      "history": ("Geçmiş", "clock.arrow.circlepath", #selector(showHistory)),
      "ai": ("AI", "sparkles", #selector(aiAssistant)),
    ]
    guard let definition = definitions[id.rawValue] else { return nil }
    let item = NSToolbarItem(itemIdentifier: id)
    item.label = definition.0
    let help = StudioCommandCatalog.help(definition.0,selector:definition.2)
    item.image = NSImage(systemSymbolName: definition.1, accessibilityDescription: definition.0)
    item.target = self
    item.action = definition.2
    let button = StudioToolbarButton(symbol: definition.1, label: definition.0,
      tone: id.rawValue == "run" ? .success : id.rawValue == "cancel" ? .warning : ["connect", "query", "save", "format", "ai"].contains(id.rawValue) ? .accent : .neutral,
      title: id.rawValue == "run" ? "Çalıştır" : "", width: id.rawValue == "run" ? 88 : 30,
      prominent: id.rawValue == "run")
    button.target = self; button.action = definition.2
    button.toolTip=help
    item.toolTip=nil
    item.view = button
    configureToolWindowIndicator(button,id:id.rawValue,label:definition.0)
    return item
  }
}
struct WelcomeView: View {
  var connect: () -> Void
  var body: some View {
    VStack(spacing: 18) {
      Image(systemName: "server.rack").font(.system(size: 42, weight: .light)).foregroundStyle(Color(nsColor: StudioTheme.accent)).padding(20).background(Color(nsColor: StudioTheme.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
      Text("MSSQL Studio").font(.system(size: 30, weight: .semibold))
      Text("SQL Server Management Workspace").font(.title3).foregroundStyle(.secondary)
      Text(
        "Object Explorer’dan veritabanlarını ve nesneleri gezinin.\nSorguları bağımsız sekmelerde çalıştırın, sonuçları ve planları inceleyin."
      ).multilineTextAlignment(.center).foregroundStyle(.secondary)
      Button("SQL Server’a Bağlan", action: connect).buttonStyle(StudioPrimaryButton())
      HStack(spacing: 28) {
        Label("Bağımsız sorgu sekmeleri", systemImage: "macwindow")
        Label("Şifreli bağlantı", systemImage: "lock.shield")
        Label("SQL Server", systemImage: "server.rack")
      }.font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, maxHeight: .infinity).studioPanel()
  }
}
