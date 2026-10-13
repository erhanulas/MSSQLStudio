import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WorkbenchController: NSViewController, NSToolbarDelegate, NSOutlineViewDataSource,
  NSOutlineViewDelegate, NSMenuDelegate, NSUserInterfaceValidations
{
  let state: StudioState
  var updateInProgress=false
  var updateProgress:UpdateProgressController?
  let split = NSSplitViewController()
  let explorer = NSViewController()
  let center = NSViewController()
  let outline = NSOutlineView()
  let explorerSearch = NSSearchField()
  let searchOperator = NSPopUpButton()
  let searchScopePicker = NSPopUpButton()
  let searchType = NSPopUpButton()
  var searchScopes: [TreeNode] = []
  var searchDatabaseByServer: [UUID:String] = [:]
  let indexStatus = StudioToolbarButton(symbol: "externaldrive", label: "Yerel indeks durumu ve işlemleri", tone: .neutral, width: 26)
  var indexDetailsByDatabase:[String:String]=[:]
  var indexPopover:NSPopover?
  var indexStatusTask: Task<Void,Never>?
  var lastIndexStatusCheck = Date.distantPast
  var lastIndexStatusScope = ""
  let searchStatus = NSTextField(labelWithString: "Seçili veritabanı / nesne türünde ara")
  var searchScope: TreeNode?
  let explorerTabs = NSSegmentedControl(labels:["Nesneler", "Arama"],trackingMode:.selectOne,target:nil,action:nil)
  var showingSearch = false
  var savedExpanded: [TreeNode] = []
  var savedTreeSelection: TreeNode?
  var savedTreeOrigin = NSPoint.zero
  var searchResults: [TreeNode]?
  let explorerSearchController = ExplorerSearchController()
  let explorerToggle = StudioToolbarButton(symbol: "sidebar.left", label: "Object Explorer’ı Göster / Gizle", tone: .neutral)
  let tabs = QueryTabStrip()
  let content = NSView()
  let database = NSPopUpButton()
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
  var contextNode: TreeNode?
  var sheet: NSWindow?
  private var connectionSheetBusy=false
  var detached: [UUID: DetachedQueryWindow] = [:]
  var sidebar: NSSplitViewItem!
  init(state: StudioState) {
    self.state = state
    explorerTree.expansionState=state.explorerTreeDefaults.dictionary(forKey:"explorerExpansionState") as? [String:Bool] ?? [:]
    explorerToggle.tracksActiveState=true
    super.init(nibName: nil, bundle: nil)
    NotificationCenter.default.addObserver(self,selector:#selector(explorerConnectionChanged(_:)),name:ConnectedServer.explorerConnectionChanged,object:nil)
    NotificationCenter.default.addObserver(self,selector:#selector(agentChanged(_:)),name:.init("studioAgentChanged"),object:nil)
    NotificationCenter.default.addObserver(self, selector: #selector(refreshShortcuts), name: GridShortcuts.changed, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(themeChanged), name: StudioTheme.changed, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(refreshChangedObjects(_:)), name: .init("studioDDLCompleted"), object: nil)
    NotificationCenter.default.addObserver(self,selector:#selector(refreshManagedObject(_:)),name:.init("studioManagedObjectCompleted"),object:nil)
    NotificationCenter.default.addObserver(self, selector: #selector(catalogIndexUpdated(_:)), name: .init("catalogIndexUpdated"), object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(catalogIndexUpdated(_:)), name: .init("sqlCatalogChanged"), object: nil)
    NotificationCenter.default.addObserver(self,selector:#selector(schemaApplied(_:)),name:.init("studioSchemaComparedApplied"),object:nil)
    NotificationCenter.default.addObserver(self,selector:#selector(favoritesChanged),name:FavoriteQueriesModel.changed,object:state.favorites)
    NotificationCenter.default.addObserver(self,selector:#selector(favoriteWindowClosed(_:)),name:NSWindow.willCloseNotification,object:nil)
    state.changed = { [weak self] in self?.reloadWorkspace() }
  }
  deinit {agentPolling?.cancel()}
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
    Task { [weak self] in await self?.state.favorites.load() }
  }
  private func buildCenter() {
    center.view = NSView()
    StudioTheme.surface(center.view, card: true)
    tabs.reorder = { [weak self] id,index in self?.moveQueryTab(id,to: index) }
    tabs.orientation = .horizontal
    tabs.alignment = .centerY
    tabs.spacing = 4
    tabs.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
    let tabScroll = NSScrollView()
    tabScroll.documentView = tabs
    tabScroll.hasHorizontalScroller = true
    tabScroll.autohidesScrollers = true
    tabScroll.drawsBackground = false
    tabs.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      tabs.leadingAnchor.constraint(equalTo: tabScroll.contentView.leadingAnchor),
      tabs.topAnchor.constraint(equalTo: tabScroll.contentView.topAnchor),
      tabs.heightAnchor.constraint(equalToConstant: 36),
    ])
    database.target = self
    database.action = #selector(changeDatabase)
    database.setAccessibilityIdentifier("databaseSelector")
    context.font = .systemFont(ofSize: 11)
    context.textColor = .secondaryLabelColor
    context.lineBreakMode = .byTruncatingMiddle
    context.setContentCompressionResistancePriority(.init(200),for:.horizontal)
    let databaseLabel = NSTextField(labelWithString: "Veritabanı:")
    databaseLabel.font = .systemFont(ofSize: 11)
    explorerToggle.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Object Explorer’ı Göster / Gizle")
    explorerToggle.target = self; explorerToggle.action = #selector(toggleExplorer)
    explorerToggle.bezelStyle = .inline; explorerToggle.isBordered = false
    explorerToggle.toolTip = "Object Explorer’ı Göster / Gizle"
    queryToolbarHost.setAccessibilityIdentifier("queryToolbarHost")
    queryToolbarHost.isHidden=true
    let row = NSStackView(views: [explorerToggle, databaseLabel, database, context, queryToolbarHost])
    row.setAccessibilityIdentifier("queryContextToolbar")
    StudioTheme.surface(row)
    row.orientation = .horizontal
    row.spacing = 8
    row.edgeInsets = NSEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)
    database.controlSize = .small
    database.widthAnchor.constraint(equalToConstant: 170).isActive = true
    status.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
    status.textColor = .secondaryLabelColor
    let statusRow = NSStackView(views: [status, NSView()])
    StudioTheme.surface(statusRow)
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
      tabScroll.heightAnchor.constraint(equalToConstant: 40),
      tabScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
      row.widthAnchor.constraint(equalTo: stack.widthAnchor),
      content.widthAnchor.constraint(equalTo: stack.widthAnchor),
      statusRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
      row.heightAnchor.constraint(equalToConstant: 30),
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
    state.documents.insert(document,at: min(state.documents.count,max(0,adjusted)))
    state.scheduleSnapshot(); renderTabs()
  }
  @objc func refreshShortcuts() {
    func update(_ menu: NSMenu) {
      for item in menu.items {
        if item.action == #selector(SQLTextView.toggleSQLComment(_:)) || item.action == #selector(SQLTextView.uncommentSQL(_:)) {
          let binding=GridShortcuts.binding(item.action == #selector(SQLTextView.toggleSQLComment(_:)) ? .comment:.uncomment)
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
      for item in view.window?.toolbar?.items ?? [] where item.itemIdentifier.rawValue == "favorites" {
        item.toolTip="Favori Sorgular ("+GridShortcuts.binding(.favorites).label+")"
        (item.view as? NSButton)?.toolTip=item.toolTip
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
      group.identifier = NSUserInterfaceItemIdentifier("connectionAccent")
      group.sourceColor=sourceColor(for:doc.server)
      group.configure(active: state.active === doc)
      button.contentTintColor = state.active === doc ? StudioTheme.accent : StudioTheme.muted
      button.font = .systemFont(ofSize: 12, weight: state.active === doc ? .medium : .regular)
      button.attributedTitle = NSAttributedString(
        string: button.title,
        attributes: [
          .font: button.font!,
          .foregroundColor: state.active === doc ? StudioTheme.text : StudioTheme.muted,
        ])
      close.contentTintColor = StudioTheme.muted
      let icon = NSImageView(image: NSImage(systemSymbolName: doc.pinned ? "pin.fill" : "doc.text", accessibilityDescription: doc.pinned ? "Sabitlenmiş sekme" : nil)!)
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
      group.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 8)
      tabs.addArrangedSubview(group)
    }
    let plus = symbolButton("plus", tip: "Yeni Sorgu (\(GridShortcuts.binding(.newQuery).label))", action: #selector(newQuery))
    tabs.addArrangedSubview(plus)
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
        controller = QueryController(document: doc)
        initialFocus = controller
        controller.favorites=state.favorites
        controller.favoriteRequested = { [weak self] doc in self?.presentFavoriteEditor(for:doc) }
        controller.changed = { [weak self] in
          self?.updateControls()
          self?.renderTabs()
          self?.state.scheduleSnapshot()
        }
        controllers[doc.id] = controller
        addChild(controller)
      }
      wanted = controller.view
      if hostedQuery !== controller {
        hostedQuery?.hostEditorToolbar(in:nil)
        controller.hostEditorToolbar(in:queryToolbarHost);hostedQuery=controller
        queryToolbarHost.isHidden=false
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
          content.subviews.first === initialFocus?.view,view.window?.attachedSheet == nil else {return}
        initialFocus?.focusEditor()
      }
    }
  }
  func updateControls() {
    guard isViewLoaded else { return }
    updateIndexStatus()
    let doc = state.active
    for controller in controllers.values { controller.updateConnectionAppearance() }
    for owner in detached.values { owner.updateConnectionAppearance() }
    database.removeAllItems()
    if let doc {
      let names = doc.server.databases.map(\.name)
      database.addItems(withTitles: names.contains(doc.database) ? names : [doc.database] + names)
      database.selectItem(withTitle: doc.database)
      database.isEnabled = doc.state == .ready
      context.stringValue = "\(doc.server.profile.name) · \(doc.server.profile.host),\(doc.server.profile.port)  •  \(doc.server.profile.login)"
      context.toolTip=context.stringValue+" · "+(doc.server.profile.appearance?.badge ?? "")
      context.textColor = .secondaryLabelColor
      let phase: String
      switch doc.state {
      case .disconnected: phase = "Disconnected"
      case .connecting: phase = "Connecting…"
      case .ready: phase = "Ready"
      case .running: phase = "Executing…"
      case .cancelling: phase = "Cancelling…"
      }
      let loaded = doc.results.filter { !$0.isPlan }.reduce(0) { $0 + $1.values.count }
      let shown = doc.results.filter { !$0.isPlan }.reduce(0) { $0 + min($1.values.count, max(1, doc.limits.rows)) }
      let rows = shown < loaded ? "\(shown.formatted()) gösterilen · \(loaded.formatted()) yüklenen" : "\(doc.rowCount.formatted()) rows"
      status.setAccessibilityIdentifier("queryStatus")
      status.stringValue =
        "\(phase)   |   \(doc.database)   |   \(rows)   |   \(String(format:"%.3f",doc.elapsed)) s\(doc.partial ? "   |   PARTIAL" : "")\(doc.transactionCount > 0 ? "   |   TRAN: \(doc.transactionCount)" : "")"
    } else {
      database.isEnabled = false
      context.stringValue = ""
      status.stringValue =
        state.servers.isEmpty ? "Connect to SQL Server" : "Yeni bir sorgu açın veya nesne seçin"
    }
    for item in view.window?.toolbar?.items ?? [] {
      switch item.itemIdentifier.rawValue {
      case "run", "plan": item.isEnabled = doc?.state == .ready && doc?.definitionLoading == false
      case "cancel": item.isEnabled = doc?.state == .running
      case "save", "format": item.isEnabled = doc != nil
      case "query": item.isEnabled = selectedServer?.reconnecting == false
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
    return menu
  }
  @objc private func tabMenuAction(_ item: NSMenuItem) {
    guard let doc = item.representedObject as? QueryDocument,
      let index = state.documents.firstIndex(where: { $0 === doc }) else { return }
    if item.tag == 5 {Task { @MainActor [weak self] in self?.requestCloseAllTabs() };return}
    if item.tag == 0 { doc.pinned.toggle(); state.scheduleSnapshot(); renderTabs(); return }
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
  func openNewQuery(server:ConnectedServer,database:String) {
    guard !server.reconnecting,!server.updatingProfile else {return}
    if server.online || Bundle.main.bundleIdentifier == "local.mssqlstudio.uitest" {
      state.newQuery(server:server,database:database); return
    }
    Task { [weak self] in
      guard let self else {return}
      guard await state.prepareExplorerForNewQuery(server) else {
        if let error=server.startupError {status.stringValue="Yeniden bağlantı başarısız: "+error;status.toolTip=error}
        return
      }
      state.newQuery(server:server,database:database)
    }
  }
  @objc func execute() { state.active?.execute() }
  @objc func cancel() { state.active?.cancel() }
  @objc func estimatedPlan() { state.active?.execute(estimated: true) }
  @objc func toggleActualPlan() {
    if let doc = state.active {
      doc.actualPlan.toggle()
      controllers[doc.id]?.update()
      updateControls()
    }
  }
  @objc func formatSQL() {
    if let doc = state.active {
      (controllers[doc.id] ?? detached[doc.id]?.query)?.format()
      renderTabs()
      state.scheduleSnapshot()
    }
  }
  @objc func beginTransaction() { state.active?.execute(override: "BEGIN TRANSACTION;") }
  @objc func commitTransaction() { state.active?.execute(override: "COMMIT;") }
  @objc func rollbackTransaction() { state.active?.execute(override: "ROLLBACK;") }
  @objc func saveSQL() { if let doc = state.active { state.save(doc) } }
  @objc func saveAsSQL() { if let doc = state.active { state.save(doc, asNew: true) } }
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
    guard let doc = state.active else { return }
    (controllers[doc.id] ?? detached[doc.id]?.query)?.toggleResults()
  }
  @objc func showConnect() { presentConnection() }
  @objc func editConnection() {
    if let server = contextNode?.server { presentConnection(editing: server) }
  }
  private func presentConnection(editing server: ConnectedServer? = nil) {
    guard sheet == nil, let window = view.window else { return }
    connectionSheetBusy=false
    let form = ConnectionForm(
      initial: server,
      connect: { [weak self] profile, password, save in
        guard let self else { throw SQLFailure("Çalışma alanı kapandı.") }
        let server = try await state.connect(profile, password: password, save: save)
        finishSheet()
        state.recover(for: server)
        if !state.documents.contains(where: { $0.server === server }) {
          state.newQuery(
            server: server, database: profile.database,
            text:
              "-- MSSQL Studio\nSELECT DB_NAME() AS [Database], @@SPID AS [Session], SYSDATETIME() AS [Server time];"
          )
        }
        reloadWorkspace()
      }, saveProfile:server.map {editingServer in { [weak self] profile,password,remember in
        guard let self else {throw SQLFailure("Çalışma alanı kapandı.")}
        try await state.saveConnectionProfile(editingServer,profile:profile,password:password,remember:remember)
        finishSheet();reloadWorkspace()
      }}, loadingChanged:{[weak self] busy in self?.connectionSheetBusy=busy}, cancel: { [weak self] in self?.finishSheet() })
    let controller = NSHostingController(
      rootView: form.font(.custom(StudioTheme.uiFont.fontName, size: 12)))
    let sheet = StudioPanelWindow(contentViewController: controller)
    sheet.animationBehavior = .none
    sheet.cancelAction={ [weak self] in guard let self,!connectionSheetBusy else {return};finishSheet() }
    sheet.title = server == nil ? "Yeni bağlantı" : "Bağlantı ayarları"
    sheet.styleMask = [.titled]
    self.sheet = sheet
    window.beginSheet(sheet)
  }
  private func finishSheet() {
    if let sheet {
      view.window?.endSheet(sheet)
      sheet.orderOut(nil)
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
    if let identity {window.identifier = .init(identity)}
    window.title = title
    window.styleMask = [.titled, .closable, .resizable]
    window.setContentSize(NSSize(width: width, height: height))
    window.minSize = NSSize(width: min(width, minWidth), height: min(height, minHeight))
    window.center()
    let owner = NSWindowController(window: window)
    auxiliaryWindows.append(owner)
    owner.showWindow(nil)
    return window
  }
  func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
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
    if [
      #selector(execute), #selector(estimatedPlan), #selector(beginTransaction),
      #selector(commitTransaction), #selector(rollbackTransaction),
    ].contains(item.action) {
      return state.active?.state == .ready
    }
    if item.action == #selector(addFavorite) {return favoriteContextDocument?.sql.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty == false}
    if item.action == #selector(cancel) { return state.active?.state == .running }
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
      .init("connect"), .init("query"), .init("save"), .space, .init("run"), .init("cancel"),
      .init("plan"), .space, .init("format"), .flexibleSpace, .init("activity"), .init("favorites"), .init("history"),
      .init("ai"),
    ]
  }
  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar: Bool
  ) -> NSToolbarItem? {
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
      "history": ("Geçmiş", "clock.arrow.circlepath", #selector(showHistory)),
      "ai": ("AI", "sparkles", #selector(aiAssistant)),
    ]
    guard let definition = definitions[id.rawValue] else { return nil }
    let item = NSToolbarItem(itemIdentifier: id)
    item.label = definition.0
    item.toolTip = id.rawValue == "favorites" ? definition.0+" ("+GridShortcuts.binding(.favorites).label+")":definition.0
    item.image = NSImage(systemSymbolName: definition.1, accessibilityDescription: definition.0)
    item.target = self
    item.action = definition.2
    let button = StudioToolbarButton(symbol: definition.1, label: definition.0,
      tone: id.rawValue == "run" ? .success : id.rawValue == "cancel" ? .warning : ["connect", "query", "save", "format", "ai"].contains(id.rawValue) ? .accent : .neutral,
      title: id.rawValue == "run" ? "Çalıştır" : "", width: id.rawValue == "run" ? 88 : 30,
      prominent: id.rawValue == "run")
    button.target = self; button.action = definition.2
    button.toolTip = id.rawValue == "run" ? "Çalıştır (⌘↩ / F5)" : item.toolTip
    item.view = button
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
