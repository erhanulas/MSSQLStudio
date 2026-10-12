import AppKit
import SQLServerKit
import SwiftUI

@MainActor private final class DatabaseIndexButton:NSButton { weak var node:TreeNode? }
import UniformTypeIdentifiers

@MainActor final class TreeNode: NSObject {
  enum Kind {
    case server, group, database, favorites, favorite
    case folder(Folder)
    case object(Folder)
    case detail
  }
  enum LinkedBranch {
    case catalogs(String), catalog(String, String?), group
    case relation(LinkedCatalog.Relation), columns(LinkedCatalog.Relation), detail
  }
  var linked: LinkedBranch?
  var title: String
  var favorite: FavoriteQuery?
  var favoriteScope: FavoriteQuery.Scope?
  let generation: UUID
  let kind: Kind
  let server: ConnectedServer
  let database: String
  var item: CatalogItem?
  weak var parent: TreeNode?
  var children: [TreeNode] = [] { didSet { for child in children { child.parent=self } } }
  var loaded = false
  var loading = false
  var error: String?
  init(
    _ title: String, kind: Kind, server: ConnectedServer, database: String = "master",
    item: CatalogItem? = nil
  ) {
    self.title = title
    self.generation = server.generation
    self.kind = kind
    self.server = server
    self.database = database
    self.item = item
  }
  var displayTitle: String {
    if case .server = kind {
      let badge = server.profile.appearance?.badge ?? ""
      return (badge.isEmpty ? "" : "[\(badge)] ") + server.profile.name + (server.reconnecting ? " · Bağlanıyor…" : server.online ? " · Bağlı" : " · Bağlantı kapalı")
    }
    if case .object(.triggers)=kind { return title }
    if case .object(.jobs)=kind { return item?.name ?? title }
    return title
  }
  var persistenceKey:String {
    var parts:[String]=[];var cursor:TreeNode?=self
    while let node=cursor {
      let kind:String
      switch node.kind {
      case .server:kind="server"
      case .group:kind="group"
      case .database:kind="database"
      case .favorites:kind="favorites:"+(node.favoriteScope?.rawValue ?? "root")
      case .favorite:kind="favorite"
      case .folder(let folder):kind="folder:"+folder.rawValue
      case .object(let folder):kind="object:"+folder.rawValue
      case .detail:kind="detail"
      }
      parts.insert(contentsOf:[kind,node.database,node.favorite?.id.uuidString ?? node.item.map {String($0.id)+":"+$0.schema+":"+$0.name} ?? (kind == "server" ? node.server.id.uuidString:node.title)],at:0)
      cursor=node.parent
    }
    return String(decoding:try! JSONEncoder().encode(parts),as:UTF8.self)
  }
  var triggerDisabled:Bool { item?.detail.contains("Disabled") == true }
  var ownerObject:TreeNode? {
    var node=parent
    while let current=node { if case .object(let f)=current.kind, [.tables,.views,.procedures,.functions].contains(f) {return current}; node=current.parent }
    return nil
  }
  var objectFolder:Folder? { if case .object(let f)=kind { return f }; return nil }
  var expandable: Bool {
    if case .detail = linked {return false}
    if linked != nil {return true}
    if case .object(.linkedServers) = kind {return true}
    switch kind {
    case .server, .group, .database, .favorites: return true
    case .folder(let folder):
      return [
        .databases, .tables, .views, .procedures, .functions, .synonyms, .columns, .indexes, .keys,
        .triggers, .constraints, .parameters, .logins, .users, .roles, .linkedServers, .jobs,
        .schedules,
      ].contains(folder)
    case .object(let folder): return [.tables, .views, .procedures, .functions].contains(folder)
    case .detail, .favorite: return false
    }
  }
  private var category: Folder? {
    switch kind {
    case .folder(let folder), .object(let folder): return folder
    default: return nil
    }
  }
  var tint: NSColor {
    switch kind {
    case .server:
      return server.profile.appearance?.isMarked == true
        ? server.profile.appearance!.color : StudioTheme.accent
    case .favorites, .favorite: return StudioTheme.warning
    case .database: return StudioTheme.color(0x278A91, 0x69C3C7)
    case .group:
      if title == "Security" { return StudioTheme.color(0xB77A36, 0xDDB17F) }
      if title == "SQL Server Agent" { return StudioTheme.color(0x8B69B6, 0xBA9AD7) }
      if title == "Management" { return StudioTheme.color(0x43866C, 0x87C0AA) }
      return StudioTheme.accent
    default: break
    }
    switch category {
    case .databases: return StudioTheme.color(0x278A91, 0x69C3C7)
    case .tables, .columns: return StudioTheme.accent
    case .views: return StudioTheme.color(0x278A91, 0x69C3C7)
    case .procedures, .functions, .parameters, .synonyms: return StudioTheme.color(0x8B69B6, 0xBA9AD7)
    case .logins, .users, .roles, .keys, .constraints: return StudioTheme.color(0xB77A36, 0xDDB17F)
    case .activity, .sessions, .locks, .files: return StudioTheme.color(0x43866C, 0x87C0AA)
    case .jobs where item?.detail.contains("Disabled") == true:return .secondaryLabelColor
    case .jobs, .jobHistory, .schedules: return StudioTheme.color(0xA46B9D, 0xD7A3CF)
    case .triggers: return triggerDisabled ? .secondaryLabelColor : StudioTheme.color(0x43866C, 0x87C0AA)
    case .indexes: return StudioTheme.color(0xB77A36, 0xDDB17F)
    default: return .secondaryLabelColor
    }
  }
  var icon: String {
    switch kind {
    case .favorites: return favoriteScope == .global ? "globe" : favoriteScope == .database ? "cylinder.split.1x2" : "star.circle"
    case .favorite: return "star.fill"
    case .server: return "server.rack"
    case .database: return "cylinder.split.1x2"
    case .group:
      if title == "Security" { return "lock.shield" }
      if title == "SQL Server Agent" { return "clock.badge.checkmark" }
      if title == "Management" { return "waveform.path.ecg" }
      return "folder"
    case .detail: return "rectangle.split.1x2"
    default: break
    }
    switch category {
    case .databases: return "externaldrive"
    case .tables: return "tablecells"
    case .views: return "eye"
    case .procedures: return "terminal"
    case .functions: return "function"
    case .parameters: return "at"
    case .triggers: return triggerDisabled ? "bolt.slash.fill" : "bolt.fill"
    case .constraints: return "checkmark.shield"
    case .linkedServers: return "network"
    case .synonyms: return "link"
    case .columns: return "rectangle.split.1x2"
    case .logins, .users: return "person.crop.circle"
    case .roles: return "lock.shield"
    case .keys: return "key"
    case .indexes: return "list.number"
    case .activity, .sessions: return "waveform.path.ecg"
    case .locks: return "lock"
    case .jobs: return item?.detail.contains("Running") == true ? "play.circle.fill":item?.detail.contains("Disabled") == true ? "pause.circle":"clock.badge.checkmark"
    case .schedules, .jobHistory: return "clock"
    default: return "folder"
    }
  }
}
@MainActor final class DocumentButton: NSButton, NSDraggingSource {
  var document: QueryDocument?
  var showMenu: ((NSEvent) -> Void)?
  var draggable = false
  override func rightMouseDown(with event: NSEvent) { showMenu?(event) }
  override func mouseDown(with event: NSEvent) {
    guard draggable, let document, let window else { super.mouseDown(with: event); return }
    let origin = event.locationInWindow
    highlight(true)
    while let next = window.nextEvent(matching: [.leftMouseDragged,.leftMouseUp]) {
      if next.type == .leftMouseUp { highlight(false); if let action { _ = sendAction(action,to: target) }; return }
      if hypot(next.locationInWindow.x-origin.x,next.locationInWindow.y-origin.y) > 4 {
        highlight(false)
        let item = NSPasteboardItem(); item.setString(document.id.uuidString,forType: QueryTabStrip.type)
        let drag = NSDraggingItem(pasteboardWriter: item)
        let image = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) { cacheDisplay(in: bounds,to: rep); image.addRepresentation(rep) }
        drag.setDraggingFrame(bounds,contents: image)
        beginDraggingSession(with: [drag],event: next,source: self)
        return
      }
    }
    highlight(false)
  }
  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
}
@MainActor final class QueryTabSurface: NSStackView {
  weak var primaryButton: DocumentButton?
  // Padding and the document icon belong to the same draggable/selectable tab.
  override func mouseDown(with event: NSEvent) { primaryButton?.mouseDown(with: event) }
  override func rightMouseDown(with event: NSEvent) { primaryButton?.rightMouseDown(with: event) }
}
@MainActor final class QueryTabStrip: NSStackView {
  static let type = NSPasteboard.PasteboardType("local.mssqlstudio.queryTab")
  var documentIDs: [UUID] = []
  var reorder: ((UUID,Int) -> Void)?
  private let indicator = NSView()
  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([Self.type])
    indicator.wantsLayer = true; indicator.isHidden = true
    addSubview(indicator)
  }
  required init?(coder: NSCoder) { fatalError() }
  private func location(_ sender: NSDraggingInfo) -> Int {
    let point = convert(sender.draggingLocation,from: nil)
    for (index,view) in arrangedSubviews.prefix(documentIDs.count).enumerated() where point.x < view.frame.midX { return index }
    return documentIDs.count
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard let raw = sender.draggingPasteboard.string(forType: Self.type), let id = UUID(uuidString: raw), documentIDs.contains(id), sender.draggingSource is DocumentButton else { return [] }
    let index = location(sender)
    let x = index < documentIDs.count ? arrangedSubviews[index].frame.minX : arrangedSubviews.prefix(documentIDs.count).last?.frame.maxX ?? 0
    indicator.frame = NSRect(x:x,y:2,width:2,height:max(0,bounds.height-4))
    indicator.layer?.backgroundColor = StudioTheme.accent.cgColor; indicator.isHidden = false
    return .move
  }
  override func draggingExited(_ sender: NSDraggingInfo?) { indicator.isHidden = true }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    indicator.isHidden = true
    guard sender.draggingSource is DocumentButton, let raw = sender.draggingPasteboard.string(forType: Self.type), let id = UUID(uuidString: raw), documentIDs.contains(id) else { return false }
    reorder?(id,location(sender)); return true
  }
  override func draggingEnded(_ sender: NSDraggingInfo) { indicator.isHidden = true }
}

@MainActor
final class WorkbenchController: NSViewController, NSToolbarDelegate, NSOutlineViewDataSource,
  NSOutlineViewDelegate, NSMenuDelegate, NSUserInterfaceValidations
{
  let state: StudioState
  var updateInProgress=false
  var updateProgress:UpdateProgressController?
  private let split = NSSplitViewController()
  private let explorer = NSViewController()
  private let center = NSViewController()
  private let outline = NSOutlineView()
  private let explorerSearch = NSSearchField()
  private let searchOperator = NSPopUpButton()
  private let searchScopePicker = NSPopUpButton()
  private let searchType = NSPopUpButton()
  private var searchScopes: [TreeNode] = []
  private var searchDatabaseByServer: [UUID:String] = [:]
  private let indexStatus = StudioToolbarButton(symbol: "externaldrive", label: "Yerel indeks durumu ve işlemleri", tone: .neutral, width: 26)
  private var indexDetailsByDatabase:[String:String]=[:]
  private var indexPopover:NSPopover?
  private var indexStatusTask: Task<Void,Never>?
  private var lastIndexStatusCheck = Date.distantPast
  private var lastIndexStatusScope = ""
  private let searchStatus = NSTextField(labelWithString: "Seçili veritabanı / nesne türünde ara")
  private var searchScope: TreeNode?
  private let explorerTabs = NSSegmentedControl(labels:["Nesneler", "Arama"],trackingMode:.selectOne,target:nil,action:nil)
  private var showingSearch = false
  private var savedExpanded: [TreeNode] = []
  private var savedTreeSelection: TreeNode?
  private var savedTreeOrigin = NSPoint.zero
  private var searchResults: [TreeNode]? 
  private var searchTask: Task<Void, Never>?
  private var searchToken = UUID()
  private var searchRunning = false
  private let explorerToggle = StudioToolbarButton(symbol: "sidebar.left", label: "Object Explorer’ı Göster / Gizle", tone: .neutral)
  private let tabs = QueryTabStrip()
  private let content = NSView()
  private let database = NSPopUpButton()
  private let status = NSTextField(labelWithString: "Bağlantı bekleniyor")
  private let context = NSTextField(labelWithString: "")
  private let queryToolbarHost=NSView()
  private weak var hostedQuery:QueryController?
  private var roots: [TreeNode] = []
  private var restoringTree=false
  private weak var collapsingNode:TreeNode?
  private var expansionState:[String:Bool] = [:]
  private var agentPolling: Task<Void,Never>?
  private var agentAutoRefresh = true
  private var tabSignature: [String]?
  private var controllers: [UUID: QueryController] = [:]
  private var auxiliaryWindows: [NSWindowController] = []
  private var contextNode: TreeNode?
  private var sheet: NSWindow?
  private var detached: [UUID: DetachedQueryWindow] = [:]
  private var sidebar: NSSplitViewItem!
  init(state: StudioState) {
    self.state = state
    expansionState=state.explorerTreeDefaults.dictionary(forKey:"explorerExpansionState") as? [String:Bool] ?? [:]
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
    state.changed = { [weak self] in self?.reloadWorkspace() }
  }
  deinit {agentPolling?.cancel()}
  @objc private func themeChanged() {
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
  private func buildExplorer() {
    let background = NSView()
    StudioTheme.surface(background, sidebar: true)
    explorer.view = background
    let label = NSTextField(labelWithString: "EXPLORER")
    label.font = .systemFont(ofSize: 10, weight: .semibold)
    let refresh = symbolButton("arrow.clockwise", tip: "Seçili dalın nesnelerini sunucudan yenile", action: #selector(refreshExplorer))
    let connect = symbolButton("network", tip: "Bağlantı işlemleri", action: #selector(showExplorerConnections(_:)))
    connect.setAccessibilityIdentifier("explorerConnectionActions")
    let collapse = symbolButton("sidebar.left", tip: "Object Explorer’ı gizle", action: #selector(toggleExplorer))
    indexStatus.target=self; indexStatus.action=#selector(showIndexStatus(_:))
    indexStatus.image=NSImage(systemSymbolName:"externaldrive",accessibilityDescription:nil)
    indexStatus.imagePosition = .imageOnly; indexStatus.bezelStyle = .inline
    indexStatus.setAccessibilityIdentifier("ddlIndexStatus")
    indexStatus.setAccessibilityLabel("Yerel indeks durumu ve işlemleri")
    let header = NSStackView(views: [label, NSView(), connect, indexStatus, refresh, collapse])
    header.orientation = .horizontal
    header.spacing = 2
    header.heightAnchor.constraint(equalToConstant: 32).isActive = true
    label.textColor = StudioTheme.muted
    label.identifier = .init("studio.mutedLabel")
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    explorerSearch.controlSize = .small
    explorerSearch.font = .systemFont(ofSize: 12)
    explorerSearch.placeholderString = "Nesnelerde filtrele"
    explorerSearch.target = self
    explorerSearch.action = #selector(filterExplorer)
    outline.headerView = nil
    outline.rowHeight = 27
    outline.intercellSpacing = NSSize(width: 1, height: 1)
    outline.indentationPerLevel = 14
    outline.selectionHighlightStyle = .regular
    outline.usesAlternatingRowBackgroundColors = false
    let column = NSTableColumn(identifier: .init("object"))
    column.width = 330
    outline.addTableColumn(column)
    outline.outlineTableColumn = column
    outline.allowsMultipleSelection = true
    outline.dataSource = self
    outline.delegate = self
    outline.target = self
    outline.doubleAction = #selector(openObject)
    outline.setAccessibilityIdentifier("objectExplorer")
    outline.registerForDraggedTypes([Self.explorerDragType])
    outline.setDraggingSourceOperationMask(.move,forLocal:true)
    outline.setDraggingSourceOperationMask([],forLocal:false)
    outline.setAccessibilityHelp("Bağlantı başlıklarını sürükleyerek sıralayın. Command-tıklama ile iki veritabanı seçip sağ tıktan DDL Karşılaştır’ı açın.")
    let menu = NSMenu()
    menu.delegate = self
    outline.menu = menu
    let scroll = NSScrollView()
    scroll.documentView = outline
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.drawsBackground = false
    searchOperator.addItems(withTitles: ["İçerir", "Eşittir", "İle başlar", "İle biter", "İçermez"])
    searchOperator.target = self; searchOperator.action = #selector(filterExplorer)
    searchType.addItems(withTitles:["Tüm nesneler","Tables","Views","Procedures","Functions","Synonyms"])
    searchType.target = self; searchType.action = #selector(filterExplorer)
    searchType.setAccessibilityLabel("Aranacak nesne türü")
    let searchOptions = NSStackView(views:[searchOperator,searchType]); searchOptions.spacing = 4
    searchOptions.distribution = .fillEqually
    // Metadata names and explanatory text must not dictate the pane's minimum width.
    for control in [searchScopePicker,searchOperator,searchType] {
      control.controlSize = .small; control.font = .systemFont(ofSize: 11)
      control.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
      (control.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
    }
    for control in [indexStatus,searchStatus,explorerSearch,explorerTabs] {
      control.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    }
    searchOperator.setAccessibilityLabel("Nesne arama operatörü")
    searchStatus.font = .systemFont(ofSize: 10); searchStatus.textColor = .secondaryLabelColor
    searchStatus.lineBreakMode = .byTruncatingMiddle
    searchScopePicker.target = self; searchScopePicker.action = #selector(changeSearchScope)
    searchScopePicker.setAccessibilityLabel("Nesne arama kapsamı")
    searchScopePicker.toolTip = "Arama bu bağlantı ve veritabanında kalır; metni temizlemek kapsamı değiştirmez."
    explorerTabs.segmentStyle = .texturedRounded
    explorerTabs.controlSize = .small
    explorerTabs.selectedSegment = 0
    explorerTabs.target = self; explorerTabs.action = #selector(changeExplorerTab)
    explorerTabs.setAccessibilityLabel("Explorer sekmeleri")
    let stack = NSStackView(views: [header, explorerTabs, searchScopePicker, explorerSearch, searchOptions, searchStatus, scroll])
    stack.orientation = .vertical
    stack.distribution = .fill
    stack.alignment = .leading
    stack.spacing = 7
    background.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
      stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -4),
      header.widthAnchor.constraint(equalTo: stack.widthAnchor),
      explorerTabs.widthAnchor.constraint(equalTo: stack.widthAnchor),
      explorerSearch.widthAnchor.constraint(equalTo: stack.widthAnchor),
      searchScopePicker.widthAnchor.constraint(equalTo: stack.widthAnchor),
      searchOptions.widthAnchor.constraint(equalTo: stack.widthAnchor),
      searchStatus.widthAnchor.constraint(equalTo: stack.widthAnchor),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
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
  private func separator() -> NSView {
    let box = NSBox()
    box.boxType = .separator
    return box
  }
  private func symbolButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
    let button = StudioToolbarButton(symbol: symbol, label: tip, tone: .neutral, width: 26)
    button.target = self; button.action = action
    return button
  }
  private var selected: TreeNode? { outline.item(atRow: outline.selectedRow) as? TreeNode }
  var selectedServer: ConnectedServer? {
    selected?.server ?? state.active?.server ?? state.servers.first(where: \.online) ?? state.servers.first
  }
  static func queryDatabase(for node: TreeNode) -> String {
    switch node.kind {
    case .server, .group, .folder(.databases), .folder(.logins), .folder(.linkedServers), .folder(.jobs), .folder(.schedules): return node.server.profile.database
    default: return node.database.isEmpty ? node.server.profile.database : node.database
    }
  }
  var selectedDatabase: String {
    if let node = selected { return Self.queryDatabase(for: node) }
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
        if item.action == #selector(newQuery) {
          let binding = GridShortcuts.binding(.newQuery)
          item.keyEquivalent = binding.key; item.keyEquivalentModifierMask = binding.flags
        }
        if let child = item.submenu { update(child) }
      }
    }
    if let menu = NSApp.mainMenu { update(menu) }
    if isViewLoaded { renderTabs() }
  }
  private func reloadWorkspace() {
    guard isViewLoaded else { return }
    let selection=outline.selectedRowIndexes.compactMap {outline.item(atRow:$0) as? TreeNode}
    let removed = roots.filter {root in !state.servers.contains(where:{$0 === root.server})}
    if !removed.isEmpty {
      roots.removeAll {root in removed.contains(where:{$0 === root})}
      contextNode=nil; savedTreeSelection=nil; savedExpanded=[]
      searchTask?.cancel(); searchToken=UUID();searchRunning=false;searchResults=nil
      indexStatusTask?.cancel();indexPopover?.performClose(nil)
      lastIndexStatusScope=""; indexStatus.toolTip="İndeks durumu için bağlantı seçin"
    }
    for server in state.servers {
      if let index = roots.firstIndex(where: { $0.server === server }) {
        roots[index].error = server.startupError
        let existing =
          roots[index].children.first?.children.flatMap { node -> [String] in
            if case .database = node.kind { return [node.database] }
            return node.children.map(\.database)
          } ?? []
        if roots[index].generation != server.generation
          || Set(existing) != Set(server.databases.map(\.name))
        {
          roots[index] = serverTree(server)
        }
      } else {
        roots.append(serverTree(server))
      }
    }
    roots=state.servers.compactMap {server in roots.first {$0.server === server}}
    for root in roots {synchronizeFavorites(in:root)}
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
      "\(doc.id)|\(doc.title)|\(doc.needsCloseConfirmation)|\(doc.pinned)|\(doc.busy)|\(state.active === doc)|\(doc.server.profile)"
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
      let close = DocumentButton(
        image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Sekmeyi kapat")!,
        target: self, action: #selector(closeSpecificTab(_:)))
      close.document = doc
      close.bezelStyle = .inline
      close.isBordered = false
      close.controlSize = .mini
      let group = QueryTabSurface(views: [button, close])
      group.primaryButton = button
      group.identifier = NSUserInterfaceItemIdentifier("connectionAccent")
      group.wantsLayer = true
      group.layer?.backgroundColor =
        (state.active === doc ? StudioTheme.canvas : StudioTheme.panel).cgColor
      button.contentTintColor = state.active === doc ? StudioTheme.accent : StudioTheme.muted
      button.font = .systemFont(ofSize: 12, weight: state.active === doc ? .medium : .regular)
      button.attributedTitle = NSAttributedString(
        string: button.title,
        attributes: [
          .font: button.font!,
          .foregroundColor: state.active === doc ? StudioTheme.text : StudioTheme.muted,
        ])
      group.layer?.cornerRadius = 6
      group.layer?.borderWidth = state.active === doc ? 1 : 0
      group.layer?.borderColor = StudioTheme.accent.withAlphaComponent(0.28).cgColor
      close.contentTintColor = StudioTheme.muted
      let icon = NSImageView(image: NSImage(systemSymbolName: doc.pinned ? "pin.fill" : "doc.text", accessibilityDescription: doc.pinned ? "Sabitlenmiş sekme" : nil)!)
      icon.contentTintColor = doc.server.profile.appearance?.isMarked == true
        ? doc.server.profile.appearance!.color : StudioTheme.accent
      icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
      icon.heightAnchor.constraint(equalToConstant: 14).isActive = true
      if doc.busy {
        let progress=NSProgressIndicator();progress.style = .spinning;progress.isIndeterminate=true;progress.controlSize = .small
        progress.setAccessibilityLabel("Sekmede işlem sürüyor")
        progress.widthAnchor.constraint(equalToConstant:14).isActive=true
        progress.heightAnchor.constraint(equalToConstant:14).isActive=true
        progress.startAnimation(nil);group.insertArrangedSubview(progress,at:0)
      } else {group.insertArrangedSubview(icon, at: 0)}
      if let appearance = doc.server.profile.appearance, appearance.isMarked {
        group.wantsLayer = true
        group.layer?.borderColor = appearance.color.cgColor
        group.layer?.borderWidth = 1
      }
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
  private func updateControls() {
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
      let badge = doc.server.profile.appearance?.badge ?? ""
      context.stringValue =
        (badge.isEmpty ? "" : "[\(badge)] ")
        + "\(doc.server.profile.name) · \(doc.server.profile.host),\(doc.server.profile.port)  •  \(doc.server.profile.login)"
      context.toolTip=context.stringValue
      context.textColor = .secondaryLabelColor
      let phase: String
      switch doc.state {
      case .disconnected: phase = "Disconnected"
      case .connecting: phase = "Connecting…"
      case .ready: phase = "Ready"
      case .running: phase = "Executing…"
      case .cancelling: phase = "Cancelling…"
      }
      status.stringValue =
        "\(phase)   |   \(doc.database)   |   \(doc.rowCount.formatted()) rows   |   \(String(format:"%.3f",doc.elapsed)) s\(doc.partial ? "   |   PARTIAL" : "")\(doc.transactionCount > 0 ? "   |   TRAN: \(doc.transactionCount)" : "")"
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
    let menu = NSMenu()
    for (index, title) in [document.pinned ? "Unpin Tab" : "Pin Tab", "Close Tab", "Close Right Tabs", "Close Left Tabs", "Close Other Tabs", "Close All Tabs"].enumerated() {
      let item = menu.addItem(withTitle: title, action: #selector(tabMenuAction(_:)), keyEquivalent: "")
      item.target = self; item.tag = index; item.representedObject = document
    }
    return menu
  }
  @objc private func tabMenuAction(_ item: NSMenuItem) {
    guard let doc = item.representedObject as? QueryDocument,
      let index = state.documents.firstIndex(where: { $0 === doc }) else { return }
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
  private func openNewQuery(server:ConnectedServer,database:String) {
    guard !server.reconnecting else {return}
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
  @objc private func editConnection() {
    if let server = contextNode?.server { presentConnection(editing: server) }
  }
  private func presentConnection(editing server: ConnectedServer? = nil) {
    guard sheet == nil, let window = view.window else { return }
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
      }, cancel: { [weak self] in self?.finishSheet() })
    let controller = NSHostingController(
      rootView: form.font(.custom(StudioTheme.uiFont.fontName, size: 12)))
    let sheet = NSWindow(contentViewController: controller)
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
    sheet = nil
  }
  @objc private func refreshManagedObject(_ notification:Notification) {
    guard let node=notification.object as? TreeNode else {return}
    if case .folder = node.kind {refresh(node)} else {refresh(node.parent ?? node)}
  }
  func refresh(_ node: TreeNode) {
    if case .favorites = node.kind {Task {await state.favorites.load()};return}
    if case .favorite = node.kind {return}
    if case .object = node.kind, !node.expandable,let parent=node.parent {refresh(parent);return}
    if case .folder(.databases) = node.kind,
      let root = roots.first(where: { $0.server === node.server })
    {
      refresh(root)
      return
    }
    guard !node.server.reconnecting else { return }
    guard node.server.online else { return }
    if node.linked != nil || node.objectFolder == .linkedServers {
      if case .group = node.linked, let parent=node.parent {refresh(parent);return}
      if case .detail = node.linked, let parent=node.parent {refresh(parent);return}
      node.loaded=false; node.error=nil; loadLinked(node);return
    }
    if case .server = node.kind {
      Task { [weak self] in
        guard let self else { return }
        let token = node.server.generation
        let connection = node.server.metadata
        do {
          let rows = Catalog.rows(try await connection.execute(Catalog.databases))
          guard token == node.server.generation, node.server.online,
            node.server.metadata === connection else { return }
          node.server.startupError = nil
          node.error = nil
          node.server.databases = node.server.profile.visibleItems(from: rows)
          node.server.prepareCatalogIndexes()
          rebuildSearchScopes()
          node.children = serverTree(node.server).children
          synchronizeFavorites(in:node)
          node.loaded = true
          reloadExplorer(item:node,children:true)
          updateControls()
        } catch {
          guard token == node.server.generation, node.server.online,
            node.server.metadata === connection else { return }
          node.server.recordExplorerFailure(error)
          node.error = error.localizedDescription
          reloadExplorer(item:node)
          updateControls()
        }
      }
    } else if case .database = node.kind {
      func refreshBranches(_ branch:TreeNode) {
        if case .folder = branch.kind, branch.loaded {
          branch.loaded=false; branch.error=nil; load(branch)
        } else if case .group = branch.kind {
          for child in branch.children {refreshBranches(child)}
        }
      }
      for branch in node.children {refreshBranches(branch)}
    } else {
      node.loaded = false
      node.error = nil
      load(node)
    }
  }
  @objc private func refreshExplorer() {
    if let node = selected ?? roots.first { refresh(node) }
  }
  @objc func reconnectQuery() {
    guard let doc = state.active, !doc.busy else { return }
    Task { [weak self] in
      guard let self else { return }
      do {
        doc.server = try await state.connect(
          doc.server.profile, password: doc.server.password, save: false)
        doc.connect()
      } catch { state.showError(error.localizedDescription) }
    }
  }
  @objc private func reconnectServer() {
    guard let server = contextNode?.server else { return }
    Task { await state.reconnectExplorer(server) }
  }
  func explorerConnectionMenu(server:ConnectedServer?) -> NSMenu {
    let menu=NSMenu();menu.autoenablesItems=false
    let add=NSMenuItem(title:"Yeni Bağlantı…",action:#selector(showConnect),keyEquivalent:"")
    add.target=self;add.image=NSImage(systemSymbolName:"plus",accessibilityDescription:nil);menu.addItem(add)
    if let server {
      menu.addItem(.separator())
      let action=NSMenuItem(title:server.online ? "Aktif Bağlantıyı Kapat":"Yeniden Bağlan",action:server.online ? #selector(closeExplorerConnection(_:)):#selector(reconnectExplorerConnection(_:)),keyEquivalent:"")
      action.target=self;action.representedObject=server;action.isEnabled = !server.reconnecting
      action.image=NSImage(systemSymbolName:server.online ? "power":"arrow.triangle.2.circlepath",accessibilityDescription:nil)
      action.toolTip=server.profile.name+" · Açık sorgu oturumları korunur."
      menu.addItem(action)
    }
    return menu
  }
  @objc private func showExplorerConnections(_ sender:NSButton) {
    explorerConnectionMenu(server:selectedServer).popUp(positioning:nil,at:NSPoint(x:0,y:sender.bounds.maxY),in:sender)
  }
  @objc private func closeExplorerConnection(_ sender:NSMenuItem) {
    guard let server=sender.representedObject as? ConnectedServer,server.online,!server.reconnecting else {return}
    Task {await state.disconnectExplorer(server)}
  }
  @objc private func reconnectExplorerConnection(_ sender:NSMenuItem) {
    guard let server=sender.representedObject as? ConnectedServer else {return}
    Task {await state.reconnectExplorer(server)}
  }
  @objc private func disconnectServer() {
    guard let server = contextNode?.server else { return }
    guard !server.reconnecting, let window = view.window else { return }
    let alert = NSAlert()
    alert.messageText = "Bağlantı Explorer’dan kaldırılsın mı?"
    alert.informativeText = "\(server.profile.name) bağlantısı Explorer’dan kaldırılacak. Kayıtlı bağlantı bilgileri ve açık sorgu sekmeleri korunur."
    alert.addButton(withTitle:"Kaldır"); alert.addButton(withTitle:"Vazgeç")
    alert.beginSheetModal(for:window) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      Task { @MainActor in await self?.state.removeExplorer(server) }
    }
  }
  @objc func toggleExplorer() {
    sidebar.isCollapsed.toggle()
    UserDefaults.standard.set(sidebar.isCollapsed,forKey:"explorerCollapsed")
    explorerToggle.state = sidebar.isCollapsed ? .on : .off
  }
  @objc private func schemaApplied(_ notification:Notification) {
    guard let server=notification.object as? ConnectedServer,let db=notification.userInfo?["database"] as? String,
      let key=notification.userInfo?["key"] as? SchemaObjectKey,let type=notification.userInfo?["type"] as? String else {return}
    Task {[weak self] in await self?.refreshComparedObject(server:server,database:db,key:key,type:type)}
  }
  func refreshComparedObject(server:ConnectedServer,database:String,key:SchemaObjectKey,type:String,indexService:CatalogIndexService = .shared,catalogService:SQLCatalogService = .shared) async {
    guard server.online else {return}
    let generation=server.generation
    let folder:Folder
    switch type {case "U":folder = .tables;case "V":folder = .views;case "P","PC":folder = .procedures;case "FN","IF","TF","FS","FT":folder = .functions;case "SN":folder = .synonyms;case "TR","TRD":folder = .triggers;default:return}
    let sql:String
    if folder == .triggers {
      let parentClass=key.databaseTrigger ? 0:1
      let schema=key.databaseTrigger ? "CAST(N'' AS sysname)":"OBJECT_SCHEMA_NAME(t.object_id)"
      sql="-- StudioSchemaTargetRefresh\nSELECT t.object_id,t.name,\(schema),t.type_desc+CASE WHEN t.is_disabled=1 THEN N' Disabled' ELSE N'' END,CAST(NULL AS sysname),t.parent_id FROM sys.triggers t WHERE t.is_ms_shipped=0 AND t.parent_class=\(parentClass) AND t.name=\(SQL.literal(key.name))"+(key.databaseTrigger ? ";":" AND OBJECT_SCHEMA_NAME(t.object_id)=\(SQL.literal(key.schema));")
    } else {
      sql="-- StudioSchemaTargetRefresh\nSELECT TOP (30001) o.object_id,o.name,s.name,o.type_desc,c.name,0 FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id LEFT JOIN sys.columns c ON c.object_id=o.object_id WHERE o.is_ms_shipped=0 AND s.name=\(SQL.literal(key.schema)) AND o.name=\(SQL.literal(key.name)) ORDER BY c.column_id;"
    }
    do {
      let result=try await server.catalog(sql,database:database,limits:SchemaComparison.limits)
      guard generation==server.generation,server.online else {return}
      guard !result.partial,!result.stoppedEarly,result.results.count==1,!result.results.contains(where:\.truncated) else {throw SQLFailure("Nesne yenilemesi kısmi geldi.")}
      let values=Array(result.results.first?.values ?? [])
      guard values.count<=30_000,values.allSatisfy({$0.count>=6 && $0[0].flatMap(Int.init).map {$0>0}==true && $0[0]==values.first?[0] && $0[1]==key.name && $0[2]==key.schema && $0[3] != nil}) else {throw SQLFailure("Nesne yenileme yanıtı doğrulanamadı.")}
      let item=Catalog.rows(result).first
      let parentID=values.first?[5].flatMap(Int.init) ?? 0
      if folder != .triggers {
        let rows=item.map {[$0]} ?? []
        try await indexService.replaceTarget(profile:server.profile,database:database,name:key.schema+"."+key.name,folder:folder,items:rows)
        guard generation==server.generation,server.online else {return}
        let symbol=item.map {CatalogSymbol(schema:$0.schema,name:$0.name,columns:values.compactMap {$0[4]},kind:$0.detail)}
        let catalog=try await catalogService.replaceTarget(profile:server.profile,database:database,schema:key.schema,name:key.name,symbol:symbol)
        guard generation==server.generation,server.online else {return}
        if let catalog {for document in state.documents where document.server === server && document.database==database {document.applyTargetedCatalog(catalog,database:database,generation:generation)}}
      }
      var queue=roots.filter {$0.server === server},visited=0
      while let node=queue.popLast() {
        visited+=1;if visited%200==0 {await Task.yield()}
        guard generation==server.generation,server.online else {return}
        queue.append(contentsOf:node.children)
        guard node.database==database else {continue}
        if case .folder(let category)=node.kind,category==folder,node.loaded,
          folder != .triggers || (node.ownerObject?.item?.id ?? 0)==parentID {
          let matches:(TreeNode)->Bool={child in child.item?.name==key.name && (key.databaseTrigger || child.item?.schema==key.schema)}
          if let existing=node.children.first(where:matches),let item {existing.item=item;existing.title=folder == .triggers ? item.name:item.schema+"."+item.name}
          else if let item {node.children.append(TreeNode(folder == .triggers ? item.name:item.schema+"."+item.name,kind:.object(folder),server:server,database:database,item:item));node.children.sort {$0.title.localizedStandardCompare($1.title) == .orderedAscending}}
          else {node.children.removeAll(where:matches)}
          reloadExplorer(item:node,children:true)
        }
        if case .object(let category)=node.kind,category==folder,node.item?.name==key.name,
          key.databaseTrigger || node.item?.schema==key.schema {
          if let item {node.item=item}
          if node.expandable {let expanded=outline.isItemExpanded(node);node.loaded=false;node.children=[];if expanded {load(node)} else {reloadExplorer(item:node,children:true)}}
          else {reloadExplorer(item:node)}
        }
      }
      if searchScope?.server === server,searchScope.map({searchDatabases($0).contains(database)})==true,!explorerSearch.stringValue.isEmpty {filterExplorer()}
    } catch {
      guard generation==server.generation else {return}
      searchStatus.stringValue="Nesne uygulandı; yerel katalog yenilenemedi."
      searchStatus.toolTip=error.localizedDescription
    }
  }
  @objc private func refreshChangedObjects(_ notification: Notification) {
    guard let doc = notification.object as? QueryDocument else { return }
    let targets = ModuleEditing.changedObjects(doc.lastExecutedSQL ?? "")
    let db = doc.database, server = doc.server
    Task { [weak self] in
      guard let self else { return }
      for target in targets {
        guard let result = try? await server.catalog(Catalog.searchObjects(target.name, operation: 1, folder: target.folder), database: db) else { continue }
        let rows = Catalog.rows(result)
        do {
          try await CatalogIndexService.shared.replaceTarget(profile: server.profile, database: db, name: target.name, folder: target.folder, items: rows)
        } catch { searchStatus.stringValue = "Disk indeksi güncellenemedi; indeksi yenileyin." }
        var queue = roots.filter { $0.server === server }, visited = 0
        while let node = queue.popLast() {
          visited += 1
          if visited % 200 == 0 { await Task.yield() }
          queue.append(contentsOf: node.children)
          guard node.database == db else { continue }
          if case .folder(let folder) = node.kind, folder == target.folder, node.item == nil, node.loaded {
            func matches(_ item: CatalogItem) -> Bool {
              target.name.caseInsensitiveCompare(item.name) == .orderedSame || target.name.caseInsensitiveCompare(item.schema + "." + item.name) == .orderedSame
            }
            let previousCount = node.children.count
            node.children.removeAll { child in
              child.item.map { matches($0) && !rows.contains(where: { $0.id == child.item?.id }) } ?? false
            }
            for item in rows where !node.children.contains(where: { $0.item?.id == item.id }) {
              node.children.append(TreeNode("\(item.schema).\(item.name)", kind: .object(folder), server: server, database: db, item: item))
            }
            if node.children.count != previousCount {
              node.children.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
              reloadExplorer(item:node,children:true)
            }
          }
          if let item = node.item, case .object(let folder) = node.kind, folder == target.folder,
            rows.contains(where: { $0.id == item.id }) {
            node.loaded = false; node.children = []; load(node)
          }
        }
      }
      if searchScope?.server === server && searchScope.map({ searchDatabases($0).contains(db) }) == true && !explorerSearch.stringValue.isEmpty { filterExplorer() }
    }
  }
  @objc private func explorerConnectionChanged(_ notification:Notification) {
    guard isViewLoaded, let server=notification.object as? ConnectedServer else {return}
    for root in roots where root.server === server {reloadExplorer(item:root)}
    updateControls(); updateIndexStatus()
  }
  func checkExplorerConnections() async {
    guard isViewLoaded, let window=view.window, window.isVisible, !window.isMiniaturized,
      window.occlusionState.contains(.visible) else {return}
    for server in state.servers where server.online && !server.reconnecting {
      await server.checkExplorerHealth()
    }
  }
  @objc private func catalogIndexUpdated(_ notification: Notification) {
    lastIndexStatusCheck = .distantPast; updateIndexStatus()
    for row in 0..<outline.numberOfRows {
      if let node=outline.item(atRow:row) as? TreeNode,case .database=node.kind {reloadExplorer(item:node)}
    }
    if let server = notification.object as? ConnectedServer, let db = notification.userInfo?["database"] as? String, notification.userInfo?["error"] == nil {
      for doc in state.documents where doc.server === server && doc.database == db { Task { await doc.loadSymbols() } }
    }
    guard let server = notification.object as? ConnectedServer,
      let db = notification.userInfo?["database"] as? String,
      searchScope?.server === server, searchScope.map({ searchDatabases($0).contains(db) }) == true,
      !explorerSearch.stringValue.isEmpty else { return }
    if let error = notification.userInfo?["error"] as? String {
      searchStatus.stringValue = "Disk önbelleği · Eşitleme başarısız"
      searchStatus.toolTip = error + " Son tamamlanan indeks kullanılıyor."
    } else { filterExplorer() }
  }
  private func refreshIndexInBackground(server: ConnectedServer, database: String, force: Bool = false) {
    guard server.online, !server.indexingDatabases.contains(database) else {return}
    server.indexingDatabases.insert(database)
    NotificationCenter.default.post(name:.init("catalogIndexUpdated"),object:server,userInfo:["database":database])
    lastIndexStatusCheck = .distantPast; updateIndexStatus()
    Task {
      defer {
        server.indexingDatabases.remove(database)
        NotificationCenter.default.post(name:.init("catalogIndexUpdated"),object:server,userInfo:["database":database])
        lastIndexStatusCheck = .distantPast; updateIndexStatus()
      }
      do {
        let key = CatalogDiskIndex.scope(profile: server.profile, database: database)
        let before = try await CatalogDiskIndex.shared.status(scope: key)
        let after = try await CatalogIndexService.shared.refresh(profile: server.profile, password: server.password, database: database, force: force)
        _ = try await SQLCatalogService.shared.refresh(profile:server.profile,password:server.password,database:database,force:force)
        if force && (searchScope ?? selected ?? roots.first)?.server === server {
          searchStatus.stringValue = "\(database) · Disk indeksi hazır · \(after.count) nesne"
        }
        server.indexErrors.removeValue(forKey:database)
        if !force && before?.synchronizedAt == after.synchronizedAt { return }
        NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: server, userInfo: ["database": database])
      } catch {
        server.indexErrors[database]=error.localizedDescription
        if force { searchStatus.stringValue = "Disk indeksi eşitlenemedi"; searchStatus.toolTip = error.localizedDescription }
        NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: server, userInfo: ["database": database, "error": error.localizedDescription])
      }
    }
  }
  private func updateIndexStatus() {
    guard let scope = (showingSearch ? searchScope : selected) ?? searchScope ?? roots.first else { indexStatus.toolTip = "İndeks durumu için bağlantı seçin"; return }
    let databases = searchDatabases(scope), key = scope.server.id.uuidString + databases.joined(separator:"|")
    guard key != lastIndexStatusScope || Date().timeIntervalSince(lastIndexStatusCheck) > 2 else { return }
    lastIndexStatusScope = key; lastIndexStatusCheck = Date(); indexStatusTask?.cancel()
    let profile = scope.server.profile, server = scope.server
    indexStatusTask = Task { [weak self] in
      var lines: [String] = [], ready = 0
      for db in databases {
        guard !Task.isCancelled else { return }
        do {
          let objects = try await CatalogDiskIndex.shared.status(scope:CatalogDiskIndex.scope(profile:profile,database:db))
          let columns = try await SQLCatalogService.shared.cached(profile:profile,database:db)
          if let objects {
            ready += 1
            let stamp = objects.synchronizedAt.formatted(date:.numeric,time:.shortened)
            let columnStamp = columns?.snapshot.synchronizedAt.formatted(date:.numeric,time:.shortened) ?? "yok"
            lines.append("\(db): nesne indeksi \(objects.count) nesne · \(stamp)\nKolon indeksi: \(columnStamp) · \(columns?.fresh == true ? "güncel" : "yenileme gerekli")")
          } else { lines.append("\(db): indeks henüz hazır değil / hazırlanıyor") }
        } catch { lines.append("\(db): indeks okunamadı · \(error.localizedDescription)") }
      }
      guard !Task.isCancelled, let self else { return }
      for db in databases {
        if let error = server.indexErrors[db] { lines.append("\(db): eşitleme başarısız · \(error)") }
        else if server.indexingDatabases.contains(db) { lines.append("\(db): indeks hazırlanıyor…") }
      }
      if let doc = state.active, doc.server === server, let error = doc.catalogError { lines.append("Editör doğrulaması kapalı: \(error)") }
      let failed = databases.contains(where:{server.indexErrors[$0] != nil})
      let building = !server.indexingDatabases.isDisjoint(with:databases)
      indexStatus.image=NSImage(systemSymbolName:failed ? "exclamationmark.triangle" : building ? "arrow.triangle.2.circlepath" : ready == databases.count && ready > 0 ? "externaldrive.badge.checkmark":"externaldrive",accessibilityDescription:nil)
      indexStatus.contentTintColor=failed ? .systemOrange : building ? StudioTheme.accent : ready > 0 ? .systemGreen:.secondaryLabelColor
      for db in databases {
        indexDetailsByDatabase[server.id.uuidString+"|"+db] = lines.filter {$0.hasPrefix(db+":")}.joined(separator:"\n")
      }
      indexStatus.toolTip = lines.joined(separator:"\n\n")
      indexStatus.setAccessibilityLabel(indexStatus.toolTip ?? "Yerel indeks")
    }
  }
  func openEditorDefinition(_ symbol: CatalogSymbol, document: QueryDocument) {
    let server=document.server,db=document.database,generation=document.server.generation
    if let existing=state.documents.first(where: {$0.server === server && $0.database == db && $0.definitionSymbol?.schema == symbol.schema && $0.definitionSymbol?.name == symbol.name}) {
      state.active=existing;state.changed?()
      detached[existing.id]?.showWindow(nil)
      if existing.definitionError == nil {return}
      state.active=document
      _=state.close(existing)
    }
    let target=state.newQuery(server:server,database:db,title:(symbol.kind == "USER_TABLE" ? "CREATE · ":"ALTER · ")+symbol.name,startConnection:false)
    target.definitionSymbol=symbol;target.definitionLoading=true;target.changed?()
    target.definitionTask=Task { [weak self,weak target] in
      guard let self,let target else {return}
      @MainActor func current()->Bool {!Task.isCancelled && state.documents.contains(where: {$0 === target}) && target.database == db && target.server === server}
      defer {target.definitionTask=nil}
      do {
        let result=try await server.catalog("SELECT object_id FROM sys.objects WHERE schema_id=SCHEMA_ID(\(SQL.literal(symbol.schema))) AND name=\(SQL.literal(symbol.name));",database:db)
        guard current() else {return}
        guard server.generation == generation else {throw SQLFailure("Bağlantı değişti; nesne tanımını yeniden açın.")}
        guard let rawID=result.results.first?.values.first?.first,let rawID,let id=Int(rawID) else {throw SQLFailure("Nesne bulunamadı; DDL indeksini yenileyin.")}
        let key=ObjectEditorKey(serverID:server.id,database:db,objectID:id)
        if let existing=state.documents.first(where: {$0 !== target && $0.objectEditorKey == key}) {
          target.definitionLoading=false;_=state.close(target)
          _=activateObjectEditor(server:server,database:db,objectID:id)
          existing.definitionSymbol=symbol;return
        }
        target.objectEditorKey=key
        let sql:String,original:String?
        if symbol.kind == "USER_TABLE" {
          let table=try ObjectMetadata.decode(await server.catalog(ObjectMetadata.table(id),database:db),schema:symbol.schema,name:symbol.name)
          sql=try table.createScript();original=nil
        } else {
          let result=try await server.catalog(Catalog.definition(id),database:db)
          guard let text=result.results.first?.values.first?.first,let text else {throw SQLFailure("Tanım alınamadı; VIEW DEFINITION iznini veya şifreli modülü kontrol edin.")}
          sql=ModuleEditing.alter(text);original=text
        }
        guard current() else {return}
        guard server.generation == generation else {throw SQLFailure("Bağlantı değişti; nesne tanımını yeniden açın.")}
        target.sql=sql;target.savedText=sql
        if let original {target.moduleOriginal=original;target.moduleInitialSQL=sql;target.moduleObjectID=id}
        target.definitionLoading=false;target.changed?();target.connect()
      } catch {
        guard current() else {return}
        target.definitionLoading=false;target.definitionError=error.localizedDescription;target.changed?()
      }
    }
  }
  @objc private func showDatabaseIndex(_ sender:DatabaseIndexButton) {showIndexDetails(sender.node,relativeTo:sender)}
  @objc private func showIndexStatus(_ sender:NSButton) {
    let scope=(showingSearch ? searchScope:selected) ?? searchScope ?? roots.first
    showIndexDetails(scope,relativeTo:sender)
  }
  @objc private func showContextIndex() {showIndexDetails(contextNode,relativeTo:indexStatus)}
  @objc private func rebuildContextIndex() {
    guard let node=contextNode,node.server.online else {return}
    refreshIndexInBackground(server:node.server,database:node.database,force:true)
  }
  private func showIndexDetails(_ scope:TreeNode?,relativeTo button:NSButton) {
    guard let scope else {return}
    let popover=NSPopover();popover.animates = false;popover.behavior = .transient
    let panel=ExplorerIndexPanel(server:scope.server,databases:searchDatabases(scope)) { [weak self] in
      if case .server = scope.kind {scope.server.prepareCatalogIndexes(force:true)}
      else {self?.refreshIndexInBackground(server:scope.server,database:scope.database,force:true)}
    }
    indexPopover?.close();indexPopover=popover
    StudioPopover.show(popover,content:panel,from:button,size:NSSize(width:420,height:500))
  }
  @objc private func rebuildCatalogIndex() {
    guard let scope = searchScope ?? selected ?? roots.first else { return }
    searchStatus.stringValue = "Disk indeksleri eşitleniyor…"
    if case .server = scope.kind { scope.server.prepareCatalogIndexes(force: true) }
    else { refreshIndexInBackground(server: scope.server, database: scope.database, force: true) }
  }
  private func searchDatabases(_ scope: TreeNode) -> [String] {
    if case .server = scope.kind { return scope.server.databases.map(\.name) }
    return [scope.database]
  }
  private func rebuildSearchScopes() {
    if let scope=searchScope {searchDatabaseByServer[scope.server.id]=scope.database}
    let candidate = (showingSearch ? searchScope?.server : selected?.server) ?? searchScope?.server ?? selectedServer
    let server = roots.first {$0.server === candidate}?.server ?? roots.first?.server
    searchScopes = server.map { server in
      [TreeNode("Tüm seçili veritabanları",kind:.server,server:server,database:"*")] + server.databases.map { item in
        TreeNode(item.name,kind:.database,server:server,database:item.name,item:item)
      }
    } ?? []
    searchScopePicker.removeAllItems()
    for scope in searchScopes { searchScopePicker.addItem(withTitle: "\(scope.server.profile.name) / \(scope.database == "*" ? "Tüm seçili veritabanları" : scope.database)") }
    let previous = UserDefaults.standard.string(forKey: "explorerSearchScope")
    let index = searchScopes.firstIndex { scope in
      if let database=searchDatabaseByServer[scope.server.id] {return scope.database == database}
      return "\(scope.server.id.uuidString)|\(scope.database)" == previous
    } ?? 0
    if searchScopes.indices.contains(index) { searchScopePicker.selectItem(at:index); searchScope = searchScopes[index] }
    else { searchScope = nil }
    searchScopePicker.isEnabled = !searchScopes.isEmpty
  }
  @objc private func changeSearchScope() {
    guard searchScopes.indices.contains(searchScopePicker.indexOfSelectedItem) else { return }
    searchScope = searchScopes[searchScopePicker.indexOfSelectedItem]
    updateIndexStatus()
    if let scope = searchScope { UserDefaults.standard.set("\(scope.server.id.uuidString)|\(scope.database)",forKey:"explorerSearchScope") }
    filterExplorer()
  }
  private func showExplorerSearch(_ show: Bool) {
    guard show != showingSearch else { return }
    if show {
      savedExpanded = (0..<outline.numberOfRows).compactMap { outline.item(atRow:$0) as? TreeNode }.filter { outline.isItemExpanded($0) }
      savedTreeSelection = outline.item(atRow:outline.selectedRow) as? TreeNode
      savedTreeOrigin = outline.enclosingScrollView?.contentView.bounds.origin ?? .zero
    }
    showingSearch = show
    explorerTabs.selectedSegment = show ? 1 : 0
    reloadExplorer()
    if !show {
      restoringTree=true
      for node in savedExpanded { outline.expandItem(node) }
      restoringTree=false
      restoreExplorerExpansion()
      if let node = savedTreeSelection {
        let row = outline.row(forItem:node)
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false) }
      }
      if let scroll = outline.enclosingScrollView {
        scroll.contentView.scroll(to:savedTreeOrigin)
        scroll.reflectScrolledClipView(scroll.contentView)
      }
    }
  }
  @objc private func changeExplorerTab() { showExplorerSearch(explorerTabs.selectedSegment == 1) }
  @objc private func filterExplorer() {
    searchToken = UUID()
    searchTask?.cancel()
    let text = explorerSearch.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      searchResults = nil
      searchStatus.stringValue = searchScope.map { "Arama kapsamı: " + ($0.database == "*" ? $0.server.profile.name + " / Tüm seçili veritabanları" : $0.database) } ?? "Önce bir bağlantı / veritabanı seçin"
      searchStatus.toolTip = nil
      showExplorerSearch(false)
      return
    }
    showExplorerSearch(true)
    if searchScope == nil { searchScope = selected ?? roots.first }
    guard let scope = searchScope else { return }
    let token = searchToken
    searchStatus.stringValue = "\(scope.displayTitle) · Aranıyor…"
    searchTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(350))
      guard let self, !Task.isCancelled, token == searchToken else { return }
      // At most one server search is in flight. New input invalidates its result.
      if searchRunning { return }
      searchRunning = true
      defer {
        searchRunning = false
        if token != searchToken && !explorerSearch.stringValue.isEmpty { filterExplorer() }
      }
      let databases = searchDatabases(scope)
      let types: [Folder?] = [nil,.tables,.views,.procedures,.functions,.synonyms]
      let folder = types[max(0,min(searchType.indexOfSelectedItem,types.count-1))]
      do {
        var matches: [TreeNode] = []
        var pending = 0
        for db in databases {
          try Task.checkCancellation()
          let key = CatalogDiskIndex.scope(profile: scope.server.profile, database: db)
          guard let status = try await CatalogDiskIndex.shared.status(scope: key) else {
            pending += 1; continue
          }
          if Date().timeIntervalSince(status.synchronizedAt) > 300 {
            refreshIndexInBackground(server: scope.server, database: db)
          }
          let rows = try await CatalogDiskIndex.shared.search(scope: key, text: text, operation: searchOperator.indexOfSelectedItem, folder: folder, limit: 501 - matches.count)
          for item in rows {
            let type: Folder = item.detail == "USER_TABLE" ? .tables : item.detail == "VIEW" ? .views : item.detail.contains("PROCEDURE") ? .procedures : item.detail == "SYNONYM" ? .synonyms : .functions
            let title = (databases.count > 1 ? db + " · " : "") + item.schema + "." + item.name
            matches.append(TreeNode(title,kind:.object(type),server:scope.server,database:db,item:item))
          }
          if matches.count > 500 { break }
        }
        guard token == searchToken, !Task.isCancelled else { return }
        searchResults = Array(matches.prefix(500))
        searchStatus.stringValue = "\(databases.count) veritabanı · \(searchResults!.count) sonuç" + (matches.count > 500 ? " · İlk 500" : "") + (pending > 0 ? " · \(pending) indeks hazırlanıyor" : "")
        searchStatus.toolTip = "Seçili veritabanlarının yerel disk indeksinde arama yapılır. Sonuçlar veritabanı sırasındadır; en fazla 500 sonuç gösterilir."
        if showingSearch { reloadExplorer() }
      } catch {
        guard token == searchToken else { return }
        searchResults = []; searchStatus.stringValue = "Arama başarısız: \(error.localizedDescription)"
        if showingSearch { reloadExplorer() }
      }
    }
  }
  private func visible(_ nodes: [TreeNode]) -> [TreeNode] { nodes }
  static let explorerDragType=NSPasteboard.PasteboardType("local.mssqlstudio.explorer-connection")
  func outlineView(_ outlineView:NSOutlineView,pasteboardWriterForItem item:Any) -> (any NSPasteboardWriting)? {
    guard !showingSearch,let node=item as? TreeNode,case .server=node.kind,roots.contains(where:{$0 === node}) else {return nil}
    let writer=NSPasteboardItem();writer.setString(node.server.id.uuidString,forType:Self.explorerDragType)
    return writer
  }
  func explorerDropIndex(sourceID:UUID,item:Any?,childIndex:Int) -> Int? {
    guard !showingSearch,let old=roots.firstIndex(where:{$0.server.id == sourceID}) else {return nil}
    let index:Int
    if let item {
      guard childIndex == NSOutlineViewDropOnItemIndex,let node=item as? TreeNode,case .server=node.kind,
        let target=roots.firstIndex(where:{$0 === node}) else {return nil}
      index=target
    } else {index=childIndex}
    guard (0...roots.count).contains(index),index != old,index != old+1 else {return nil}
    return index
  }
  func outlineView(_ outlineView:NSOutlineView,validateDrop info:any NSDraggingInfo,proposedItem item:Any?,proposedChildIndex childIndex:Int) -> NSDragOperation {
    guard info.draggingSource as? NSOutlineView === outlineView,info.draggingPasteboard.pasteboardItems?.count == 1,
      let raw=info.draggingPasteboard.string(forType:Self.explorerDragType),let id=UUID(uuidString:raw),
      let index=explorerDropIndex(sourceID:id,item:item,childIndex:childIndex) else {return []}
    outlineView.setDropItem(nil,dropChildIndex:index)
    return .move
  }
  func outlineView(_ outlineView:NSOutlineView,acceptDrop info:any NSDraggingInfo,item:Any?,childIndex:Int) -> Bool {
    guard info.draggingSource as? NSOutlineView === outlineView,info.draggingPasteboard.pasteboardItems?.count == 1,
      let raw=info.draggingPasteboard.string(forType:Self.explorerDragType),let id=UUID(uuidString:raw),
      let index=explorerDropIndex(sourceID:id,item:item,childIndex:childIndex) else {return false}
    return state.moveExplorer(id,to:index)
  }
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    visible((item as? TreeNode)?.children ?? (showingSearch ? searchResults ?? [] : roots)).count
  }
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    visible((item as? TreeNode)?.children ?? (showingSearch ? searchResults ?? [] : roots))[index]
  }
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    (item as? TreeNode)?.expandable ?? false
  }
  private func reloadExplorer(item:TreeNode?=nil,children:Bool=false) {
    let previous=restoringTree;restoringTree=true
    if let item {outline.reloadItem(item,reloadChildren:children)} else {outline.reloadData()}
    restoringTree=previous
    restoreExplorerExpansion()
  }
  func restoreExplorerExpansion() {
    guard !showingSearch,!restoringTree else {return}
    restoringTree=true;defer {restoringTree=false}
    func restore(_ node:TreeNode,isRoot:Bool=false) {
      guard node.expandable,outline.row(forItem:node)>=0 else {return}
      let expanded=expansionState[node.persistenceKey] ?? isRoot
      if expanded {
        outline.expandItem(node)
        for child in node.children {restore(child)}
      } else {outline.collapseItem(node)}
    }
    for root in roots {restore(root,isRoot:true)}
  }
  private func recordExpansion(_ notification:Notification,expanded:Bool) {
    guard !restoringTree,!showingSearch,let node=notification.userInfo?["NSObject"] as? TreeNode else {return}
    expansionState[node.persistenceKey]=expanded
    state.explorerTreeDefaults.set(expansionState,forKey:"explorerExpansionState")
  }
  func outlineViewItemDidExpand(_ notification:Notification) {recordExpansion(notification,expanded:true);restoreExplorerExpansion()}
  func outlineViewItemWillCollapse(_ notification:Notification) {
    guard !restoringTree,!showingSearch,collapsingNode == nil,let node=notification.userInfo?["NSObject"] as? TreeNode else {return}
    collapsingNode=node
  }
  func outlineViewItemDidCollapse(_ notification:Notification) {
    // AppKit emits descendant collapse notifications when an ancestor closes.
    // Their remembered expansion remains intact for reopening that ancestor.
    if let root=collapsingNode {
      guard notification.userInfo?["NSObject"] as? TreeNode === root else {return}
      collapsingNode=nil
    }
    recordExpansion(notification,expanded:false)
  }
  func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
    if let node = item as? TreeNode, !node.loaded { load(node) }
    return true
  }
  func outlineView(_ outlineView:NSOutlineView,selectionIndexesForProposedSelection proposed:IndexSet)->IndexSet {
    guard proposed.count>1 else {return proposed}
    if proposed.allSatisfy({index in guard let node=outlineView.item(atRow:index) as? TreeNode else {return false};if case .database=node.kind {return true};return false}) {return IndexSet(proposed.suffix(2))}
    return IndexSet(integer:proposed.last ?? 0)
  }
  func schemaEndpoints(for nodes:[TreeNode])->[SchemaEndpoint] {
    nodes.compactMap {node in guard node.server.online,case .database=node.kind else {return nil};return SchemaEndpoint(server:node.server,database:node.database)}
  }
  @objc private func compareDatabasesAtNode() {
    let selection=outline.selectedRowIndexes.compactMap {outline.item(atRow:$0) as? TreeNode}
    let nodes=contextNode.map {node in selection.contains(where:{$0 === node}) ? selection:[node]} ?? selection
    let seeds=schemaEndpoints(for:nodes)
    let endpoints=state.servers.filter(\.online).flatMap {server in server.databases.map {SchemaEndpoint(server:server,database:$0.name)}}
    let model=SchemaComparisonModel(endpoints:endpoints,sourceID:seeds.first?.id)
    let owner=SchemaComparisonWindow(model:model) {[weak self] endpoint,sql in self?.state.newQuery(server:endpoint.server,database:endpoint.database,text:sql,title:"DDL Karşılaştırma · SQL Önizlemesi")}
    auxiliaryWindows.append(owner);owner.showWindow(nil)
  }
  func outlineViewSelectionDidChange(_ notification: Notification) {
    if !showingSearch, let node=selected, node.server !== searchScope?.server {
      rebuildSearchScopes()
      filterExplorer()
    }
    updateControls()
    // Database scope stays explicit within the selected Explorer connection.
  }
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any)
    -> NSView?
  {
    guard let node = item as? TreeNode else { return nil }
    let cell = NSTableCellView()
    let label = NSTextField(
      labelWithString: node.displayTitle + (node.loading ? " …" : "")
        + (node.error != nil ? " ⚠" : ""))
    label.font = .systemFont(ofSize: 12)
    label.lineBreakMode = .byTruncatingTail
    if node.objectFolder == .jobs || node.objectFolder == .triggers {
      label.setAccessibilityLabel(node.displayTitle + " · " + (node.item?.detail ?? ""))
    }
    let image = NSImageView(
      image: NSImage(systemSymbolName: node.icon, accessibilityDescription: nil)!)
    image.contentTintColor = node.error == nil ? node.tint : .systemOrange
    if case .server = node.kind {
      image.image = NSImage(systemSymbolName: node.server.reconnecting ? "arrow.triangle.2.circlepath" : node.server.online ? "externaldrive.connected.to.line.below" : "externaldrive.badge.xmark", accessibilityDescription: node.displayTitle)
      image.contentTintColor = node.server.reconnecting ? .systemOrange : node.server.online ? .systemGreen : .secondaryLabelColor
    }
    label.textColor = node.error == nil ? .labelColor : .systemOrange
    if case .server = node.kind { label.font = .systemFont(ofSize: 12, weight: .semibold) }
    cell.addSubview(label)
    cell.addSubview(image)
    label.translatesAutoresizingMaskIntoConstraints = false
    image.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
      image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      image.widthAnchor.constraint(equalToConstant: 16),
      image.heightAnchor.constraint(equalToConstant: 16),
      label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
      {if case .database = node.kind {return label.trailingAnchor.constraint(lessThanOrEqualTo:cell.trailingAnchor,constant:-32)};return label.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-3)}(),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    if case .database = node.kind {
      let badge=DatabaseIndexButton();badge.node=node;badge.target=self;badge.action=#selector(showDatabaseIndex(_:))
      let ready=indexDetailsByDatabase[node.server.id.uuidString+"|"+node.database]?.contains("nesne indeksi") == true
      badge.image=NSImage(systemSymbolName:node.server.indexErrors[node.database] != nil ? "exclamationmark.triangle" : node.server.indexingDatabases.contains(node.database) ? "arrow.triangle.2.circlepath":ready ? "externaldrive.badge.checkmark":"externaldrive",accessibilityDescription:nil)
      badge.contentTintColor=node.server.indexErrors[node.database] != nil ? .systemOrange:ready ? .systemGreen:StudioTheme.accent
      badge.bezelStyle = .inline;badge.imagePosition = .imageOnly
      badge.toolTip="\(node.database) · Yerel indeks durumu ve yenileme";badge.setAccessibilityLabel(badge.toolTip)
      badge.setAccessibilityIdentifier("databaseIndex_"+node.database)
      cell.addSubview(badge);badge.translatesAutoresizingMaskIntoConstraints=false
      NSLayoutConstraint.activate([badge.leadingAnchor.constraint(equalTo:label.trailingAnchor,constant:6),badge.centerYAnchor.constraint(equalTo:cell.centerYAnchor),badge.widthAnchor.constraint(equalToConstant:24),badge.heightAnchor.constraint(equalToConstant:24)])
    }
    cell.textField = label
    cell.imageView = image
    cell.toolTip = node.error ?? (!node.server.online ? "Explorer bağlantısı kapalı. Son yüklenen nesneler gösteriliyor. Bağlantı işlemleri menüsünden yeniden bağlanabilirsiniz; açık sorgu oturumları korunur." : nil) ?? node.item?.detail ?? "\(node.server.profile.name) · \(node.server.profile.host),\(node.server.profile.port) · \(node.database)"
    if case .server = node.kind {
      cell.toolTip=(cell.toolTip ?? "")+"\nSürükleyerek Explorer bağlantılarının sırasını değiştirin."
      label.setAccessibilityHelp(cell.toolTip)
    }
    if case .relation(let relation)=node.linked {
      cell.toolTip=relation.qualified + " · " + relation.type + (relation.remarks.isEmpty ? "" : "\n"+relation.remarks)
    }
    if let favorite=node.favorite {
      cell.toolTip="\(favorite.name) · \(favorite.scope == .global ? "Genel":favorite.scope == .connection ? "Bağlantı":"Veritabanı") · \(node.server.profile.name) / \(node.database) · Çift tıklayarak sorguda aç (çalıştırılmaz)"
      label.setAccessibilityLabel(cell.toolTip)
    }
    if case .favorites = node.kind {cell.toolTip="Yerel favori sorgular · Bağlantı kapalıyken de açılabilir"}
    return cell
  }
  func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
    guard let node = item as? TreeNode else { return StudioRowView() }
    guard let appearance = node.server.profile.appearance, appearance.isMarked else { return StudioRowView() }
    let row = ConnectionTreeRow()
    row.color = appearance.color
    if case .server = node.kind { row.isServer = true }
    return row
  }
  @objc private func favoritesChanged() {
    guard isViewLoaded else {return}
    let selection=selected
    for root in roots {
      let folder=synchronizeFavorites(in:root)
      if !showingSearch {reloadExplorer(item:folder,children:true)}
    }
    if !showingSearch,let selection {
      let row=outline.row(forItem:selection)
      if row>=0 {outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
      else {outline.deselectAll(nil)}
    }
  }
  @discardableResult private func synchronizeFavorites(in root:TreeNode) -> TreeNode {
    let folder=root.children.first {if case .favorites=$0.kind {return true};return false}
      ?? TreeNode("Favori Sorgular",kind:.favorites,server:root.server,database:root.server.profile.database)
    folder.loaded=true
    if !root.children.contains(where:{$0 === folder}) {root.children.append(folder)}
    let items=state.favorites.items.filter {$0.scope == .global || $0.serverID == root.server.id}
    let databases=Set(items.filter {$0.scope == .database}.compactMap(\.database)).sorted {$0.localizedStandardCompare($1) == .orderedAscending}
    let groups:[(FavoriteQuery.Scope,String,String)] = [(.global,"Genel",root.server.profile.database),(.connection,"Bu Bağlantı",root.server.profile.database)] + databases.map {(.database,$0,$0)}
    folder.children=groups.compactMap {scope,title,database in
      let values=items.filter {$0.scope == scope && (scope != .database || $0.database == database)}
      guard !values.isEmpty else {return nil}
      let group=folder.children.first {$0.favoriteScope == scope && $0.database == database}
        ?? TreeNode(title,kind:.favorites,server:root.server,database:database)
      group.favoriteScope=scope;group.loaded=true
      group.children=values.map {value in
        let node=group.children.first {$0.favorite?.id == value.id}
          ?? TreeNode(value.name,kind:.favorite,server:root.server,database:database)
        node.title=value.name;node.favorite=value;node.loaded=true
        return node
      }
      return group
    }
    return folder
  }
  func openExplorerFavorite(_ node:TreeNode) {
    guard let favorite=node.favorite else {return}
    do {try state.openFavorite(favorite,contextServerID:node.server.id,contextDatabase:node.database)}
    catch {state.showError(error.localizedDescription)}
  }
  @objc private func openFavoriteAtNode() {if let node=contextNode {openExplorerFavorite(node)}}
  func favoriteMenu(for node:TreeNode) -> NSMenu {
    let menu=NSMenu()
    guard let favorite=node.favorite else {return menu}
    for (title,symbol,selector) in [("Sorguda Aç","arrow.up.right.square",#selector(openFavoriteMenu(_:))),("Düzenle…","pencil",#selector(editFavoriteMenu(_:))),("Sil…","trash",#selector(deleteFavoriteMenu(_:)))] {
      let item=NSMenuItem(title:title,action:selector,keyEquivalent:"")
      item.target=self;item.representedObject=node;item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:title)
      item.toolTip=favorite.name;menu.addItem(item)
    }
    return menu
  }
  @objc private func openFavoriteMenu(_ item:NSMenuItem) {if let node=item.representedObject as? TreeNode {openExplorerFavorite(node)}}
  @objc private func editFavoriteMenu(_ item:NSMenuItem) {
    guard let node=item.representedObject as? TreeNode,let favorite=state.favorites.items.first(where:{$0.id == node.favorite?.id}) else {return}
    presentFavoriteEditor(favorite:favorite,serverID:node.server.id,database:node.database)
  }
  @objc private func deleteFavoriteMenu(_ item:NSMenuItem) {
    guard let node=item.representedObject as? TreeNode,let favorite=state.favorites.items.first(where:{$0.id == node.favorite?.id}),let window=view.window else {return}
    let alert=NSAlert();alert.messageText="Favori sorgu silinsin mi?";alert.informativeText=favorite.name
    alert.addButton(withTitle:"Favoriyi Sil");alert.addButton(withTitle:"Vazgeç")
    alert.beginSheetModal(for:window) { [weak self] response in
      guard response == .alertFirstButtonReturn else {return}
      Task {await self?.state.favorites.remove(favorite.id);if let self,!self.state.favorites.error.isEmpty {self.state.showError(self.state.favorites.error)}}
    }
  }
  private func serverTree(_ server: ConnectedServer) -> TreeNode {
    func folder(_ value: Folder, database: String = "master", item: CatalogItem? = nil) -> TreeNode
    {
      TreeNode(value.rawValue, kind: .folder(value), server: server, database: database, item: item)
    }
    let root = TreeNode(
      server.profile.name + " (" + server.profile.host + ")", kind: .server, server: server)
    root.loaded = true
    root.error = server.startupError
    let databases = folder(.databases)
    databases.loaded = true
    let system = TreeNode("System Databases", kind: .group, server: server)
    system.loaded = true
    for db in server.databases {
      let node = databaseTree(db, server: server)
      if db.id <= 4 { system.children.append(node) } else { databases.children.append(node) }
    }
    if !system.children.isEmpty { databases.children.insert(system, at: 0) }
    let security = TreeNode("Security", kind: .group, server: server)
    security.loaded = true
    security.children = [folder(.logins), folder(.roles)]
    let objects = TreeNode("Server Objects", kind: .group, server: server)
    objects.loaded = true
    objects.children = [folder(.linkedServers)]
    let management = TreeNode("Management", kind: .group, server: server)
    management.loaded = true
    management.children = [.activity, .sessions, .locks, .files].map { folder($0) }
    let agent = TreeNode("SQL Server Agent", kind: .group, server: server)
    agent.loaded = true
    agent.children = [.jobs, .jobHistory, .schedules].map { folder($0) }
    root.children = [databases, security, objects, management, agent]
    return root
  }
  private func databaseTree(_ db: CatalogItem, server: ConnectedServer) -> TreeNode {
    let node = TreeNode(db.name, kind: .database, server: server, database: db.name, item: db)
    node.loaded = true
    func folder(_ f: Folder) -> TreeNode {
      TreeNode(f.rawValue, kind: .folder(f), server: server, database: db.name)
    }
    let programming = TreeNode("Programmability", kind: .group, server: server, database: db.name)
    programming.loaded = true
    programming.children = [.procedures, .functions, .synonyms, .triggers].map(folder)
    let security = TreeNode("Security", kind: .group, server: server, database: db.name)
    security.loaded = true
    security.children = [folder(.users)]
    node.children = [folder(.tables), folder(.views), programming, security]
    if server.catalogFixture != nil {
      node.children[0].loaded=true; node.children[1].loaded=true
      node.children[0].children=[TreeNode("dbo.Customers",kind:.object(.tables),server:server,database:db.name,item:CatalogItem(id:1001,name:"Customers",schema:"dbo",detail:"USER_TABLE"))]
      node.children[1].children=[TreeNode("dbo.ActiveCustomers",kind:.object(.views),server:server,database:db.name,item:CatalogItem(id:1002,name:"ActiveCustomers",schema:"dbo",detail:"VIEW"))]
      for branch in programming.children {branch.loaded=true}
      programming.children[0].children=[TreeNode("dbo.SalesByCity",kind:.object(.procedures),server:server,database:db.name,item:CatalogItem(id:1003,name:"SalesByCity",schema:"dbo",detail:"SQL_STORED_PROCEDURE"))]
      programming.children[1].children=[TreeNode("dbo.CityLabel",kind:.object(.functions),server:server,database:db.name,item:CatalogItem(id:1004,name:"CityLabel",schema:"dbo",detail:"SQL_SCALAR_FUNCTION")),TreeNode("dbo.CityRows",kind:.object(.functions),server:server,database:db.name,item:CatalogItem(id:1008,name:"CityRows",schema:"dbo",detail:"SQL_INLINE_TABLE_VALUED_FUNCTION"))]
      programming.children[2].children=[TreeNode("dbo.CustomerAlias",kind:.object(.synonyms),server:server,database:db.name,item:CatalogItem(id:1009,name:"CustomerAlias",schema:"dbo",detail:"SYNONYM"))]
      programming.children[3].children=[TreeNode("DDLGuard",kind:.object(.triggers),server:server,database:db.name,item:CatalogItem(id:1007,name:"DDLGuard",detail:"SQL_TRIGGER, Disabled"))]
    }
    return node
  }
  private func load(_ node: TreeNode) {
    guard !node.loading, !node.loaded, node.server.online || node.server.catalogFixture != nil else { return }
    if node.linked != nil || node.objectFolder == .linkedServers {loadLinked(node);return}
    if case .object(let kind) = node.kind {
      node.loaded = true
      node.children =
        (kind == .tables
        ? [Folder.columns, .keys, .indexes, .constraints, .triggers]
        : kind == .views
          ? [Folder.columns, .triggers]
          : kind == .procedures ? [Folder.parameters] : [Folder.parameters, .columns]).map {
          TreeNode(
            $0.rawValue, kind: .folder($0), server: node.server, database: node.database,
            item: node.item)
        }
      reloadExplorer(item:node,children:true)
      return
    }
    guard case .folder(let folder) = node.kind else {
      node.loaded = true
      return
    }
    node.loading = true
    reloadExplorer(item:node)
    Task { [weak self, weak node] in
      guard let self, let node else { return }
      do {
        let sql =
          node.item.map { Catalog.children(folder, object: $0.id) } ?? Catalog.objects(folder)
        let rows = Catalog.rows(try await node.server.catalog(sql, database: node.database))
        node.children = rows.map { item in
          TreeNode(
            item.schema.isEmpty
              ? item.name + (folder == .triggers || item.detail.isEmpty ? "" : " (\(item.detail))")
              : "\(item.schema).\(item.name)", kind: .object(folder),
            server: node.server, database: node.database, item: item)
        }
        node.loaded = true
        node.error = nil
      } catch {
        node.error = error.localizedDescription
        node.loaded = true
        node.children = [
          TreeNode(
            "Yükleme hatası — Yenile ile tekrar deneyin", kind: .detail, server: node.server,
            database: node.database)
        ]
      }
      node.loading = false
      reloadExplorer(item:node,children:true)
    }
  }
  @objc private func openObject() {
    guard let node = outline.item(atRow: outline.clickedRow) as? TreeNode else { return }
    if case .favorite = node.kind {openExplorerFavorite(node);return}
    if case .favorites = node.kind {
      if outline.isItemExpanded(node) {outline.collapseItem(node)} else {outline.expandItem(node)}
      return
    }
    guard node.server.online else {
      Task { await state.reconnectExplorer(node.server) }
      return
    }
    if let error = node.error {
      state.showError(error)
      return
    }
    contextNode = node
    if node.linked != nil || node.objectFolder == .linkedServers {
      if case .relation = node.linked {openLinkedRelation(node,run:true)}
      else if node.expandable {
        if outline.isItemExpanded(node) {outline.collapseItem(node)} else {outline.expandItem(node)}
      }
      return
    }
    switch node.kind {
    case .object(let folder) where [.tables, .views].contains(folder): selectRows()
    case .object(let folder) where [.procedures,.functions,.triggers].contains(folder): modifyManagedModule()
    case .folder(.activity):showPerformanceMonitor(node.server)
    case .object(.jobs):showAgentProperties(node)
    case .object(.schedules):showAgentSchedule(node)
    case .object: objectProperties()
    case .folder(let folder) where !node.expandable:
      state.newQuery(
        server: node.server, database: node.database, text: Catalog.monitoring(folder),
        title: folder.rawValue, run: true)
    default:
      if node.expandable {
        if outline.isItemExpanded(node) {
          outline.collapseItem(node)
        } else {
          outline.expandItem(node)
        }
      }
    }
  }
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    contextNode =
      outline.item(atRow: outline.clickedRow) as? TreeNode
    func command(_ title: String, _ selector: Selector) {
      let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
      item.target = self
      let symbol = title.contains("Favori") ? "star" : title.contains("Yenile") ? "arrow.clockwise" : title.contains("Sorgu") ? "plus.square" : title.contains("İndeks") ? "externaldrive" : title.contains("Özellikler") ? "slider.horizontal.3" : title.contains("Kopyala") ? "doc.on.doc" : "gearshape"
      item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)
      menu.addItem(item)
    }
    func scriptMenu(_ title:String,modes:[String]) {
      let scripts=NSMenu(title:title)
      for mode in modes {
        let destinations=NSMenu(title:mode+" To")
        for destination in ["New Query Editor Window","Clipboard","File…"] {
          let item=NSMenuItem(title:destination,action:#selector(scriptManagedMenu(_:)),keyEquivalent:"");item.target=self;item.representedObject=[mode,destination];destinations.addItem(item)
        }
        let item=NSMenuItem(title:mode+" To",action:nil,keyEquivalent:"");item.submenu=destinations;scripts.addItem(item)
      }
      let item=NSMenuItem(title:title,action:nil,keyEquivalent:"");item.submenu=scripts;menu.addItem(item)
    }
    guard let node = contextNode else { return }
    if case .favorite = node.kind {
      let favorites=favoriteMenu(for:node)
      for item in favorites.items {favorites.removeItem(item);menu.addItem(item)}
      return
    }
    if case .favorites = node.kind {command("Favori Sorguları Yönet…",#selector(showFavoritesAtNode));return}
    if case .server = node.kind {command("Favori Sorgular…",#selector(showFavoritesAtNode))}
    if case .database = node.kind {command("Favori Sorgular…",#selector(showFavoritesAtNode))}

    if !node.server.online {
      command(node.server.reconnecting ? "Bağlanıyor…" : "Yeniden Bağlan", #selector(reconnectServer))
      menu.items.last?.isEnabled = !node.server.reconnecting
      command("Bağlantı ayarları…", #selector(editConnection))
      if case .server = node.kind {command("Bağlantıyı kaldır…", #selector(disconnectServer))}
      command("Yeni Sorgu", #selector(newQueryAtNode))
      menu.items.last?.isEnabled = !node.server.reconnecting
      return
    }
    if node.linked != nil || node.objectFolder == .linkedServers {
      let linkedCommands=linkedMenu(for:node)
      for item in linkedCommands.items {linkedCommands.removeItem(item);menu.addItem(item)}
      return
    }
    if case .server = node.kind {
      command("Bağlantı ayarları…",#selector(editConnection))
      command("Aktif Bağlantıyı Kapat",#selector(closeExplorerConnection(_:)))
      menu.items.last?.representedObject=node.server
      menu.items.last?.image=NSImage(systemSymbolName:"power",accessibilityDescription:nil)
      menu.items.last?.isEnabled = !node.server.reconnecting
      command("Bağlantıyı kaldır…", #selector(disconnectServer))
    }
    if case .database=node.kind {
      command("DDL Karşılaştır…",#selector(compareDatabasesAtNode))
      menu.items.last?.image=NSImage(systemSymbolName:"arrow.left.arrow.right.square",accessibilityDescription:"DDL Karşılaştır")
      menu.items.last?.toolTip="Command-tıklama ile iki veritabanı seçin; kaynak/hedef yönü karşılaştırma penceresinde değiştirilebilir."
    }
    command("Yeni Sorgu", #selector(newQueryAtNode))
    command("Nesneleri Yenile", #selector(refreshContextNode))
    menu.items.last?.toolTip="Bu dalın nesne listesini sunucudan yeniden okur; açık SQL sekmelerini çalıştırmaz ve yerel disk indeksini yeniden oluşturmaz."
    menu.addItem(.separator())
    if case .object(let folder) = node.kind {
      if [.tables, .views].contains(folder) {
        if folder == .tables { command("Design…", #selector(designTableObject)); command("Edit Top 200 Rows…", #selector(editObjectData)) }
        else { command("Design…", #selector(designViewObject)); command("Modify · ALTER…", #selector(scriptDefinition)) }
        command("Select Top 1000 Rows", #selector(selectRows))
        scriptMenu(folder == .tables ? "Script Table As" : "Script View As",modes:folder == .tables ? ["CREATE","DROP","DROP And CREATE","SELECT","INSERT","UPDATE","DELETE"] : ["CREATE","ALTER","CREATE OR ALTER","DROP","DROP And CREATE","SELECT","INSERT","UPDATE","DELETE"])
        if folder == .tables {
          command("Indexes / Keys…",#selector(manageObjectIndexes))
          command("Relationships…",#selector(manageObjectRelationships))
          command("Check Constraints…",#selector(manageObjectChecks))
        }
        command("View Dependencies",#selector(objectDependencies))
        menu.addItem(.separator())
        command("Rename…",#selector(renameManagedObject))
        command("Delete…",#selector(deleteManagedObject))
        command("Properties…",#selector(managedObjectProperties))
      }
      if [.procedures,.functions,.triggers].contains(folder) {
        command("Modify · ALTER…",#selector(modifyManagedModule))
        if folder != .triggers {command(folder == .procedures ? "Execute Stored Procedure…" : "Invoke Function…",#selector(invokeManagedRoutine))}
        if folder == .triggers {command(node.triggerDisabled ? "Enable…" : "Disable…",node.triggerDisabled ? #selector(enableManagedTrigger) : #selector(disableManagedTrigger))}
        scriptMenu(folder == .procedures ? "Script Stored Procedure As" : folder == .functions ? "Script Function As" : "Script Trigger As",modes:["CREATE","ALTER","CREATE OR ALTER","DROP","DROP And CREATE"])
        command("View Dependencies",#selector(objectDependencies))
        if folder != .triggers || node.item?.schema.isEmpty == false {command("Rename…",#selector(renameManagedObject))}
        command("Delete…",#selector(deleteManagedObject));command("Properties…",#selector(managedObjectProperties))
      }
      if folder == .synonyms {
        command("Modify / Re-create…",#selector(editManagedSynonym))
        scriptMenu("Script Synonym As",modes:["CREATE","DROP","DROP And CREATE"])
        command("View Dependencies",#selector(objectDependencies));command("Delete…",#selector(deleteManagedObject));command("Properties…",#selector(managedObjectProperties))
      }
      if [.indexes,.keys,.constraints].contains(folder), node.ownerObject != nil {
        command("Modify / Properties…",#selector(manageChildStructure))
        scriptMenu(folder == .indexes ? "Script Index As" : "Script Constraint As",modes:["CREATE","DROP","DROP And CREATE"])
        if folder == .indexes { command("Rebuild…",#selector(rebuildManagedIndex));command("Reorganize…",#selector(reorganizeManagedIndex));command("Disable…",#selector(disableManagedIndex)) }
        else if node.item?.detail.contains("CHECK_CONSTRAINT") == true || node.item?.detail.contains("FOREIGN_KEY") == true {command("Enable / Check…",#selector(checkManagedConstraint));command("Disable / NOCHECK…",#selector(disableManagedConstraint))}
      }
      if [.columns,.parameters].contains(folder), node.ownerObject != nil {command("Modify / Properties…",#selector(manageChildStructure))}
    }
    if case .folder(.tables) = node.kind { command("New Table…",#selector(newManagedTable)) }
    if case .folder(.views) = node.kind { command("New View…",#selector(newManagedView)) }
    if case .folder(.procedures)=node.kind {command("New Stored Procedure…",#selector(newManagedProcedure))}
    if case .folder(.functions)=node.kind {command("New Scalar Function…",#selector(newManagedScalarFunction));command("New Inline Table-valued Function…",#selector(newManagedTableFunction))}
    if case .folder(.triggers)=node.kind {command("New Trigger…",#selector(newManagedTrigger))}
    if case .folder(.synonyms)=node.kind {command("New Synonym…",#selector(newManagedSynonym))}
    if case .folder(let f)=node.kind, [.indexes,.keys,.constraints].contains(f), node.ownerObject != nil {command("New…",#selector(manageChildStructure))}
    if case .folder(let folder) = node.kind, !node.expandable {
      command(folder == .activity ? "Grafikli Activity Monitor…":"Verileri Aç", #selector(openMonitoring))
      if folder == .activity {command("Sorguda Tablo Olarak İzle",#selector(openActivityTable))}
      if folder == .jobs { command("New SQL Agent Job…", #selector(jobDesigner)) }
    }
    if case .database = node.kind {
      let create=NSMenu(title:"Yeni Nesne")
      for (title,selector,icon) in [("Tablo…",#selector(newManagedTable),"tablecells"),("View…",#selector(newManagedView),"eye"),("Stored Procedure…",#selector(newManagedProcedure),"function"),("Scalar Function…",#selector(newManagedScalarFunction),"function")] {
        let item=NSMenuItem(title:title,action:selector,keyEquivalent:"");item.target=self;item.image=NSImage(systemSymbolName:icon,accessibilityDescription:nil);create.addItem(item)
      }
      let item=NSMenuItem(title:"Yeni Nesne",action:nil,keyEquivalent:"");item.submenu=create;menu.addItem(item)
      command("Yerel İndeks Durumu…",#selector(showContextIndex))
      command("Yerel İndeksi Yenile",#selector(rebuildContextIndex))
      menu.addItem(.separator())
      command("Veritabanı bilgileri…", #selector(databaseProperties))
    }
    if case .folder(.jobs) = node.kind { command("New SQL Agent Job…", #selector(jobDesigner)) }
    let agentCommands=agentMenu(for:node)
    for item in agentCommands.items {agentCommands.removeItem(item);menu.addItem(item)}
    command("Adı Kopyala", #selector(copyNodeName))
  }
  func agentMenu(for node:TreeNode) -> NSMenu {
    let menu=NSMenu()
    if node.title == "SQL Server Agent" || {if case .folder(.jobs)=node.kind {return true};return false}() {
      let item=NSMenuItem(title:"Otomatik Yenile · 15 sn",action:#selector(toggleAgentAutoRefresh),keyEquivalent:"")
      item.target=self;item.state=agentAutoRefresh ? .on:.off;menu.addItem(item)
    }
    func add(_ title:String,_ command:String,_ icon:String,enabled:Bool=true) {
      let item=NSMenuItem(title:title,action:#selector(agentMenuAction(_:)),keyEquivalent:"")
      item.target=self;item.representedObject=node;item.identifier = .init(command);item.isEnabled=enabled
      item.image=NSImage(systemSymbolName:icon,accessibilityDescription:title);menu.addItem(item)
    }
    menu.autoenablesItems=false
    if node.objectFolder == .jobs {
      let disabled=node.item?.detail.contains("Disabled") == true,running=node.item?.detail.contains("Running") == true
      add("View History…","history","clock.arrow.circlepath")
      add("Start Job…","start","play.fill",enabled:!running)
      add("Stop Job…","stop","stop.fill",enabled:running)
      add(disabled ? "Enable…":"Disable…",disabled ? "enable":"disable",disabled ? "checkmark.circle":"pause.circle")
      menu.addItem(.separator());add("Delete Job…","delete","trash");add("Properties…","properties","gearshape")
    } else if node.objectFolder == .schedules {add("Properties / Enable / Disable…","schedule","calendar")}
    else if node.title == "SQL Server Agent" || {if case .folder(let f)=node.kind {return [.jobs,.jobHistory].contains(f)};return false}() {
      add("View History…","history","clock.arrow.circlepath");add("Job Activity Monitor…","activity","waveform.path.ecg")
    }
    return menu
  }
  @objc private func agentMenuAction(_ item:NSMenuItem) {
    guard let node=item.representedObject as? TreeNode,let command=item.identifier?.rawValue else {return}
    switch command {
    case "history":showAgentHistory(node)
    case "properties":showAgentProperties(node)
    case "schedule":showAgentSchedule(node)
    case "activity":showAgentActivity(node)
    default:if let action=SQLAgent.Action(rawValue:command) {showAgentAction(node,action:action)}
    }
  }
  @objc private func agentChanged(_ notification:Notification) {
    guard let server=notification.object as? ConnectedServer else {return}
    for root in roots where root.server === server {
      for group in root.children where group.title == "SQL Server Agent" {
        for branch in group.children where branch.loaded {refresh(branch)}
      }
    }
  }
  @objc private func designTableObject() { showManagedTable(contextNode) }
  @objc private func designViewObject() { showManagedView(contextNode) }
  @objc private func newManagedTable() { showManagedTable(contextNode,create:true) }
  @objc private func newManagedView() { showManagedView(contextNode,create:true) }
  @objc private func editObjectData() { showManagedData(contextNode) }
  @objc private func deleteManagedObject() { showManagedDelete(contextNode) }
  @objc private func renameManagedObject() { showManagedRename(contextNode) }
  @objc private func managedObjectProperties() { showManagedProperties(contextNode) }
  @objc private func manageObjectIndexes() { showManagedTable(contextNode,initialKind:"INDEX") }
  @objc private func manageObjectRelationships() { showManagedTable(contextNode,initialKind:"FK") }
  @objc private func manageObjectChecks() { showManagedTable(contextNode,initialKind:"CHECK") }
  @objc private func modifyManagedModule() { if let node=contextNode {scriptManagedObject(node,mode:"MODIFY",destination:"New Query Editor Window")} }
  @objc private func invokeManagedRoutine() {showRoutineInvocation(contextNode)}
  @objc private func enableManagedTrigger() {stageTriggerState(contextNode,enabled:true)}
  @objc private func disableManagedTrigger() {stageTriggerState(contextNode,enabled:false)}
  @objc private func newManagedProcedure() {stageNewModule(contextNode,kind:"PROCEDURE")}
  @objc private func newManagedScalarFunction() {stageNewModule(contextNode,kind:"SCALAR FUNCTION")}
  @objc private func newManagedTableFunction() {stageNewModule(contextNode,kind:"TABLE FUNCTION")}
  @objc private func newManagedTrigger() {stageNewModule(contextNode,kind:"TRIGGER")}
  @objc private func newManagedSynonym() {showSynonymDesigner(contextNode,create:true)}
  @objc private func editManagedSynonym() {showSynonymDesigner(contextNode)}
  @objc private func manageChildStructure() {showChildStructure(contextNode)}
  @objc private func rebuildManagedIndex() {stageStructureAction(contextNode,action:"REBUILD")}
  @objc private func reorganizeManagedIndex() {stageStructureAction(contextNode,action:"REORGANIZE")}
  @objc private func disableManagedIndex() {stageStructureAction(contextNode,action:"DISABLE")}
  @objc private func checkManagedConstraint() {stageStructureAction(contextNode,action:"CHECK")}
  @objc private func disableManagedConstraint() {stageStructureAction(contextNode,action:"NOCHECK")}
  @objc private func scriptManagedMenu(_ sender:NSMenuItem) {
    guard let node=contextNode, let request=sender.representedObject as? [String], request.count == 2 else { return }
    scriptManagedObject(node,mode:request[0],destination:request[1])
  }
  @objc private func objectDependencies() {
    guard let node = contextNode, let item = node.item else { return }
    state.newQuery(server: node.server, database: node.database,
      text: "SELECT OBJECT_SCHEMA_NAME(referencing_id) AS [Schema], OBJECT_NAME(referencing_id) AS [Object], referenced_schema_name, referenced_entity_name FROM sys.sql_expression_dependencies WHERE referencing_id=\(item.id) OR referenced_id=\(item.id);",
      title: "Dependencies · " + item.name, run: true)
  }
  @objc private func objectProperties() {
    guard let node = contextNode, let item = node.item, case .object(let folder) = node.kind else {
      return
    }
    let sql: String
    switch folder {
    case .jobs:
      sql =
        "SELECT name,enabled,description,date_created,date_modified FROM msdb.dbo.sysjobs WHERE name=\(SQL.literal(item.name)); SELECT s.step_id,s.step_name,s.subsystem,s.database_name,s.command FROM msdb.dbo.sysjobsteps s JOIN msdb.dbo.sysjobs j ON j.job_id=s.job_id WHERE j.name=\(SQL.literal(item.name)) ORDER BY s.step_id;"
    case .logins, .roles:
      sql =
        "SELECT name,type_desc,is_disabled,default_database_name,create_date,modify_date FROM sys.server_principals WHERE principal_id=\(item.id);"
    case .users:
      sql =
        "SELECT name,type_desc,default_schema_name,authentication_type_desc,create_date,modify_date FROM sys.database_principals WHERE principal_id=\(item.id);"
    case .linkedServers:
      sql =
        "SELECT name,product,provider,data_source,is_data_access_enabled,is_rpc_out_enabled FROM sys.servers WHERE server_id=\(item.id);"
    case .schedules: sql = "SELECT * FROM msdb.dbo.sysschedules WHERE schedule_id=\(item.id);"
    default: return
    }
    state.newQuery(
      server: node.server, database: node.database, text: sql, title: item.name, run: true)
  }
  private func jobScript(_ action: String) {
    guard let node = contextNode, let item = node.item else { return }
    stage(
      "USE [msdb];\nEXEC dbo.\(action) @job_name=\(SQL.literal(item.name));",
      title: action + " · " + item.name)
  }
  @objc private func startJob() { jobScript("sp_start_job") }
  @objc private func stopJob() { jobScript("sp_stop_job") }
  @objc private func enableJob() {
    if let item = contextNode?.item {
      stage(
        "USE [msdb];\nEXEC dbo.sp_update_job @job_name=\(SQL.literal(item.name)), @enabled=1;",
        title: "Enable Job")
    }
  }
  @objc private func disableJob() {
    if let item = contextNode?.item {
      stage(
        "USE [msdb];\nEXEC dbo.sp_update_job @job_name=\(SQL.literal(item.name)), @enabled=0;",
        title: "Disable Job")
    }
  }
  @objc private func newQueryAtNode() {
    if let node = contextNode {
      let name = Self.queryDatabase(for: node)
      openNewQuery(server: node.server, database: name)
    }
  }
  @objc private func refreshContextNode() { if let node = contextNode { refresh(node) } }
  @objc private func selectRows() {
    if let node = contextNode, let item = node.item {
      state.newQuery(
        server: node.server, database: node.database,
        text: "SELECT TOP (1000) *\nFROM \(item.qualified);", title: item.name, run: true)
    }
  }
  private func stage(_ sql: String, title: String) {
    if let node = contextNode {
      state.newQuery(server: node.server, database: node.database, text: sql, title: title)
    } else if let server = selectedServer {
      state.newQuery(server: server, database: selectedDatabase, text: sql, title: title)
    }
  }
  @objc private func scriptSelect() {
    if let item = contextNode?.item {
      stage("SELECT TOP (1000) *\nFROM \(item.qualified);", title: "SELECT \(item.name)")
    }
  }
  @objc private func scriptInsert() { scriptColumns(operation: "INSERT") }
  @objc private func scriptUpdate() { scriptColumns(operation: "UPDATE") }
  @objc private func scriptDelete() {
    if let item = contextNode?.item {
      stage(
        "-- Önce WHERE koşulunu belirleyin.\nDELETE FROM \(item.qualified)\nWHERE 1 = 0;",
        title: "DELETE \(item.name)")
    }
  }
  private func scriptColumns(operation: String) {
    guard let node = contextNode, let item = node.item else { return }
    Task { [weak self] in
      guard let self else { return }
      do {
        let columns = Catalog.rows(
          try await node.server.catalog(
            Catalog.children(.columns, object: item.id), database: node.database)
        ).filter {
          !$0.detail.contains("identity") && !$0.detail.contains("computed")
            && !$0.detail.hasPrefix("timestamp") && !$0.detail.hasPrefix("rowversion")
        }
        let sql =
          operation == "INSERT"
          ? "INSERT INTO \(item.qualified) (\(columns.map { SQL.identifier($0.name) }.joined(separator:", ")))\nVALUES (\(columns.map { _ in "NULL" }.joined(separator:", ")));"
          : "-- Değerleri ve WHERE koşulunu belirleyin.\nUPDATE \(item.qualified)\nSET \(columns.map { SQL.identifier($0.name)+" = NULL" }.joined(separator:",\n    "))\nWHERE 1 = 0;"
        state.newQuery(
          server: node.server, database: node.database, text: sql,
          title: "\(operation) \(item.name)")
      } catch { state.showError(error.localizedDescription) }
    }
  }
  @objc private func scriptDefinition() {
    if let node=contextNode {scriptManagedObject(node,mode:"MODIFY",destination:"New Query Editor Window")}
  }
  @objc private func copyNodeName() {
    if let node = contextNode {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(node.item?.qualified ?? node.title, forType: .string)
    }
  }
  @objc private func openMonitoring() {
    if let node = contextNode, case .folder(let folder) = node.kind {
      if folder == .activity {showPerformanceMonitor(node.server);return}
      state.newQuery(
        server: node.server, database: node.database, text: Catalog.monitoring(folder),
        title: folder.rawValue, run: true)
    }
  }
  @objc func activity() {if let server=selectedServer {showPerformanceMonitor(server)}}
  func showPerformanceMonitor(_ server:ConnectedServer) {
    present(ActivityMonitorPanel(server:server,openTable:{[weak self] in self?.createActivityTable(server)}),
      title:"Activity Monitor · \(server.profile.name)",width:1080,height:780,minWidth:920,minHeight:700,identity:"activity|\(server.id)")
  }
  @objc private func openActivityTable() {if let server=contextNode?.server ?? selectedServer {createActivityTable(server)}}
  private func createActivityTable(_ server:ConnectedServer) {
    state.newQuery(server:server,database:"master",text:Catalog.monitoring(.activity),title:"Activity Monitor · İstekler",run:true,refreshSeconds:10)
    view.window?.makeKeyAndOrderFront(nil)
  }
  @objc func showFavorites() {presentFavorites(server:selectedServer,database:selectedDatabase)}
  @objc private func showFavoritesAtNode() {if let node=contextNode {presentFavorites(server:node.server,database:Self.queryDatabase(for:node))}}
  private func presentFavorites(server:ConnectedServer?,database:String) {
    present(FavoriteQueriesPanel(state:state,model:state.favorites,contextServerID:server?.id,contextDatabase:database,didOpen:{[weak self] in self?.view.window?.makeKeyAndOrderFront(nil)}),
      title:"Favori Sorgular",width:1100,height:760,minWidth:900,minHeight:660,identity:"favorites|\(server?.id.uuidString ?? "global")|\(database)")
  }
  @objc func addFavorite() {if let doc=state.active {presentFavoriteEditor(for:doc)}}
  private func presentFavoriteEditor(for doc:QueryDocument) {
    guard !doc.sql.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return}
    presentFavoriteEditor(favorite:nil,serverID:doc.server.id,database:doc.database,sql:doc.sql,name:doc.title)
  }
  private func presentFavoriteEditor(favorite:FavoriteQuery?,serverID:UUID?,database:String,sql:String="",name:String="") {
    let identity="favorite-editor|\(favorite?.id ?? UUID())"
    present(FavoriteQueryEditor(model:state.favorites,servers:state.servers,contextServerID:serverID,database:database,favorite:favorite,sql:sql,name:name,close:{[weak self] in
      self?.auxiliaryWindows.first(where:{$0.window?.identifier?.rawValue == identity})?.close()
    }),title:favorite == nil ? "Favorilere Ekle":"Favoriyi Düzenle",width:720,height:660,minWidth:720,minHeight:660,identity:identity)
  }
  @objc private func tableProperties() {
    if let item = contextNode?.item {
      stage(
        "SELECT c.name,t.name AS type,c.max_length,c.precision,c.scale,c.is_nullable,c.is_identity FROM sys.columns c JOIN sys.types t ON t.user_type_id=c.user_type_id WHERE c.object_id=\(item.id);\nSELECT name,type_desc,is_unique,is_primary_key,is_disabled FROM sys.indexes WHERE object_id=\(item.id);",
        title: "Properties \(item.name)")
      state.active?.changed?()
    }
  }
  @objc private func databaseProperties() {
    guard let node = contextNode else { return }
    present(ExplorerDatabasePanel(server:node.server,database:node.database),title:"Veritabanı bilgileri · \(node.database)",width:760,height:620,identity:"database-info|\(node.server.id)|\(node.database)")
  }
  @objc private func createTable() {
    stage(
      "CREATE TABLE [dbo].[NewTable]\n(\n    [Id] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_NewTable] PRIMARY KEY,\n    [Name] nvarchar(200) NOT NULL,\n    [CreatedAt] datetime2(7) NOT NULL CONSTRAINT [DF_NewTable_CreatedAt] DEFAULT SYSUTCDATETIME()\n);",
      title: "Create Table")
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
  @objc private func jobDesigner() { showJobWindow(node: contextNode) }
  @discardableResult func present<V: View>(_ root: V, title: String, width: CGFloat = 700, height: CGFloat = 560, minWidth:CGFloat=620, minHeight:CGFloat=480,identity:String?=nil) -> NSWindow {
    if let identity,let existing=auxiliaryWindows.compactMap(\.window).first(where:{$0.identifier?.rawValue == identity && $0.isVisible}) {
      existing.makeKeyAndOrderFront(nil);return existing
    }
    let controller = NSHostingController(
      rootView: root.font(.custom(StudioTheme.uiFont.fontName, size: 12)))
    controller.sizingOptions = []
    let window = NSWindow(contentViewController: controller)
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
    if item.action == #selector(addFavorite) {return state.active?.sql.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty == false}
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
    item.toolTip = definition.0
    item.image = NSImage(systemSymbolName: definition.1, accessibilityDescription: definition.0)
    item.target = self
    item.action = definition.2
    let button = StudioToolbarButton(symbol: definition.1, label: definition.0,
      tone: id.rawValue == "run" ? .success : id.rawValue == "cancel" ? .warning : ["connect", "query", "save", "format", "ai"].contains(id.rawValue) ? .accent : .neutral,
      title: id.rawValue == "run" ? "Çalıştır" : "", width: id.rawValue == "run" ? 88 : 30,
      prominent: id.rawValue == "run")
    button.target = self; button.action = definition.2
    button.toolTip = id.rawValue == "run" ? "Çalıştır (⌘↩ / F5)" : definition.0
    item.view = button
    return item
  }
}
private struct WelcomeView: View {
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

private struct DatabaseChoices: View {
  let items: [CatalogItem]
  @Binding var chosen: Set<String>
  @Binding var defaultDatabase: String
  @State private var search = ""
  @State private var scope = DatabaseListScope.all
  @State private var selectedOnly = false
  @FocusState private var searchFocused: Bool
  private var filtered: [CatalogItem] {
    DatabaseSelection.filtered(
      items, search: search, scope: scope, selectedOnly: selectedOnly, chosen: chosen)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("\(chosen.count) seçili / \(items.count) veritabanı").fontWeight(.semibold)
        Spacer()
        Menu("Toplu seçim") {
          Button("Tüm veritabanlarını seç (\(items.count))") { chosen = Set(items.map(\.name)) }
          Button("Bütün seçimi temizle") { chosen = [] }
        }.fixedSize()
      }
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Veritabanı ara — ör. satış 2026", text: $search)
          .textFieldStyle(.roundedBorder).focused($searchFocused)
          .accessibilityIdentifier("databaseSearch")
          .onSubmit {
            if filtered.count == 1, let item = filtered.first { chosen.insert(item.name) }
          }
          .onExitCommand { search = "" }
        if !search.isEmpty {
          Button {
            search = ""
            searchFocused = true
          } label: {
            Image(systemName: "xmark.circle.fill").frame(width: 24, height: 24).contentShape(Rectangle())
          }
          .buttonStyle(.plain).help("Aramayı temizle").accessibilityLabel("Aramayı temizle")
        }
      }
      HStack {
        Picker("Veritabanı türü", selection: $scope) {
          Text("Tümü").tag(DatabaseListScope.all)
          Text("Kullanıcı").tag(DatabaseListScope.user)
          Text("Sistem").tag(DatabaseListScope.system)
        }.labelsHidden().pickerStyle(.segmented)
        Toggle("Yalnızca seçilenler", isOn: $selectedOnly).toggleStyle(.checkbox).fixedSize()
      }
      HStack(spacing: 10) {
        Text("\(filtered.count) eşleşme").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Görünenleri Seç") {
          chosen = DatabaseSelection.changingVisible(filtered, chosen: chosen, select: true)
        }.disabled(filtered.isEmpty)
        Button("Görünenleri Kaldır") {
          chosen = DatabaseSelection.changingVisible(filtered, chosen: chosen, select: false)
        }.disabled(!filtered.contains { chosen.contains($0.name) })
      }.controlSize(.small)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(filtered, id: \.name) { item in
            HStack(spacing: 8) {
              Toggle(
                isOn: Binding(
                  get: { chosen.contains(item.name) },
                  set: { value in
                    if value { chosen.insert(item.name) } else { chosen.remove(item.name) }
                  })
              ) {
                Text(item.name).lineLimit(1).truncationMode(.middle).help(item.name)
              }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
              if (1...4).contains(item.id) {
                Text("Sistem").font(.caption).foregroundStyle(.secondary)
              }
              Button {
                chosen.insert(item.name)
                defaultDatabase = item.name
              } label: {
                Image(systemName: defaultDatabase == item.name ? "star.fill" : "star")
                  .foregroundStyle(defaultDatabase == item.name ? Color.orange : Color.secondary)
              }.buttonStyle(.borderless)
                .help("Yeni sorgular için varsayılan yap: \(item.name)")
                .accessibilityLabel("Varsayılan yap: \(item.name)")
            }.padding(.horizontal, 10).padding(.vertical, 7)
            Divider().padding(.leading, 30)
          }
        }.padding(.vertical, 4)
      }.background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15)))
        .overlay {
          if filtered.isEmpty {
            VStack(spacing: 6) {
              Image(systemName: "line.3.horizontal.decrease.circle").font(.title2)
              Text(selectedOnly && chosen.isEmpty ? "Henüz seçim yok" : "Eşleşen veritabanı yok")
              Text("Aramayı veya filtreleri değiştirin.").font(.caption)
              Button("Filtreleri Sıfırla") {
                search = ""
                scope = .all
                selectedOnly = false
              }
            }.foregroundStyle(.secondary)
          }
        }.frame(minHeight: 220, maxHeight: .infinity)
        .accessibilityIdentifier("databaseChoicesList")
      HStack(spacing: 6) {
        Image(systemName: "star.fill").foregroundStyle(.orange)
        Text(
          defaultDatabase.isEmpty
            ? "Varsayılan için bir satırdaki yıldıza basın." : "Yeni sorgular: \(defaultDatabase)"
        )
        .lineLimit(1).truncationMode(.middle).help(defaultDatabase)
        Spacer(minLength: 0)
      }.font(.caption)
      Text("Seçim yalnızca Object Explorer görünümünü belirler; sunucu izinlerini değiştirmez.")
        .font(.caption).foregroundStyle(.secondary)
    }.onChange(of: chosen) { _, names in
      defaultDatabase = DatabaseSelection.defaultName(defaultDatabase, items: items, chosen: names)
    }.task { searchFocused = true }
  }
}

private struct ConnectionForm: View {
  var connect: (ServerProfile, String, Bool) async throws -> Void
  var cancel: () -> Void
  @State private var profile = ServerProfile(visibleDatabases: [])
  @State private var password = ""
  @State private var remember = false
  @State private var loading = false
  @State private var tested = false
  @State private var listed = false
  @State private var phase = ""
  @State private var status = ""
  @State private var error = ""
  @State private var items: [CatalogItem] = []
  @State private var chosen: Set<String> = []
  @State private var defaultDatabase = ""
  private let editing: Bool
  init(
    initial: ConnectedServer? = nil,
    connect: @escaping (ServerProfile, String, Bool) async throws -> Void,
    cancel: @escaping () -> Void
  ) {
    self.connect = connect
    self.cancel = cancel
    editing = initial != nil
    _profile = State(initialValue: initial?.profile ?? ServerProfile(visibleDatabases: []))
    _password = State(initialValue: initial?.password ?? "")
    _remember = State(initialValue: initial?.remembered ?? true)
  }
  private var appearance: Binding<ServerAppearance> {
    Binding(get: { profile.appearance ?? ServerAppearance() }, set: { profile.appearance = $0 })
  }
  @State private var didAutoTest = false
  @State private var connectionPage = "Genel"
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: editing ? "Bağlantı ayarları" : "Yeni bağlantı", icon: "server.rack", subtitle: editing ? "Bağlantı ve görünür veritabanlarını düzenle" : "Sunucuya bağlan, veritabanlarını seç")
      Divider()
      HStack(alignment: .top, spacing: 18) {
        VStack(alignment: .leading, spacing: 12) {
          Text("Sunucu bilgileri").font(.headline)
          Picker("Bağlantı seçenekleri",selection:$connectionPage) {Text("Genel").tag("Genel");Text("Gelişmiş").tag("Gelişmiş")}.pickerStyle(.segmented)
          ScrollView {
          VStack(alignment:.leading,spacing:14) {
          if connectionPage == "Genel" {
          Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
              Text("Görünen ad").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
              TextField("Bağlantı adı", text: $profile.name)
            }
            GridRow {
              Text("Sunucu / port").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
              HStack(spacing: 6) {
                TextField("Sunucu", text: $profile.host)
                TextField("Port", value: $profile.port, format: .number.grouping(.never)).frame(
                  width: 58)
              }
            }
            GridRow {
              Text("Kimlik").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
              Picker("Kimlik doğrulama", selection: $profile.kerberos) {
                Text("SQL Server Authentication").tag(false)
                Text("Windows / Kerberos").tag(true)
              }.labelsHidden()
            }
            if !profile.kerberos {
              GridRow {
                Text("Kullanıcı").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
                TextField("Login", text: $profile.login)
              }
              GridRow {
                Text("Parola").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
                SecureField("Password", text: $password)
              }
            }
            GridRow {
              Text("Test veritabanı").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
              TextField("master", text: $profile.database)
                .help(
                  "Bağlantı testi ve listeleme için kullanılır. Yeni sorguların veritabanını sağdaki yıldızla seçin."
                )
            }
          }.textFieldStyle(.roundedBorder)
          if profile.kerberos {
            Text("Geçerli Kerberos bileti ve sunucu SPN ayarı gerekir.").font(.caption)
              .foregroundStyle(.secondary)
          }
          Toggle("Bağlantıyı Keychain’de sakla", isOn: $remember).toggleStyle(.checkbox)
          } else {
          Text("Güvenlik").font(.headline)
          Label("Bağlantı şifrelemesi zorunlu",systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
          Toggle("Trust server certificate", isOn: $profile.trustCertificate).toggleStyle(.checkbox)
            .help("Şifreleme açık kalır; sunucu sertifikası doğrulanmaz.")
          if profile.trustCertificate {
            Text("Şifreleme açık; sertifika doğrulanmayacak.").font(.caption).foregroundStyle(
              .orange)
          }
          Divider()
          Text("Ortam ve renk").font(.headline)
          ConnectionAppearanceFields(appearance: appearance)
          }
          }.padding(2)
          }
                }.studioCard(padding: 16).frame(width: 420).disabled(loading)
        Divider()
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Object Explorer veritabanları").font(.headline)
            Spacer()
            if listed {
              StudioActionButton("Listeyi Yenile",icon:"arrow.clockwise",tint:.accentColor,action:list).disabled(loading)
            }
          }
          if listed {
            DatabaseChoices(items: items, chosen: $chosen, defaultDatabase: $defaultDatabase)
              .disabled(loading)
          } else {
            VStack(spacing: 12) {
              Image(systemName: "externaldrive.badge.magnifyingglass").font(.system(size: 32))
                .foregroundStyle(.secondary)
              Text("Görmek istediğin veritabanlarını seç").font(.headline)
              Text(
                "Bağlantı bilgilerini girip Veritabanlarını Yükle’ye basın. Ardından görünür veritabanlarını ve varsayılanı seçin."
              )
              .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)

            }.frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }.studioCard(padding: 16).frame(maxWidth: .infinity, maxHeight: .infinity)
      }.frame(maxHeight: .infinity)
      Divider()
      HStack {
        if loading {
          ProgressView().controlSize(.small)
          Text(phase).font(.caption)
        } else {
          if !error.isEmpty {Label(error,systemImage:"exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red).lineLimit(3).textSelection(.enabled)}
          else if !status.isEmpty {Label(status,systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.green)}
          else {Text("Bilgileri girip veritabanlarını yükleyin.").font(.caption).foregroundStyle(.secondary)}
        }
        Spacer()
        StudioActionButton("Vazgeç",icon:"xmark",action:cancel).disabled(loading)
        if tested && listed {
          StudioActionButton(editing ? "Uygula" : "Bağlan",icon:editing ? "checkmark":"bolt.horizontal",action:submit)
            .buttonStyle(StudioPrimaryButton()).disabled(loading || chosen.isEmpty)
        } else {
          StudioActionButton("Veritabanlarını Yükle",icon:"arrow.right",action:test)
            .buttonStyle(StudioPrimaryButton()).disabled(loading)
        }
      }
    }.padding(22).studioPanel().frame(width: 980, height: 700)
      .task {
        if editing && !didAutoTest {
          didAutoTest = true
          test()
        }
      }
      .onChange(of: profile) { old, new in
        var previous = old
        previous.name = new.name
        previous.appearance = new.appearance
        if previous != new { invalidate() }
      }
      .onChange(of: password) { _, _ in invalidate() }
  }
  private func invalidate() {
    tested = false
    listed = false
    items = []
    chosen = []
    defaultDatabase = ""
    status = ""
    error = ""
  }
  private func test() {
    loading = true
    phase = "Test ediliyor…"
    tested = false
    status = ""
    error = ""
    let input = profile
    let secret = password
    Task { @MainActor in
      defer { loading = false }
      do {
        let database = try await ServerDiscovery.test(input, password: secret)
        tested = true
        status = "Bağlantı başarılı · \(database)"
        try await discover()
      } catch { self.error = error.localizedDescription }
    }
  }
  private func list() {
    guard tested, !loading else { return }
    loading = true
    error = ""
    Task { @MainActor in
      defer { loading = false }
      do { try await discover() } catch { self.error = error.localizedDescription }
    }
  }
  private func discover() async throws {
    phase = "Veritabanları yükleniyor…"
    let previous = listed ? chosen : Set(profile.visibleDatabases ?? [])
    let legacy = !listed && profile.visibleDatabases == nil
    let previousDefault = defaultDatabase.isEmpty ? profile.database : defaultDatabase
    let available = try await ServerDiscovery.databases(profile, password: password)
    items = available
    chosen = Set(items.map(\.name)).intersection(legacy ? Set(items.map(\.name)) : previous)
    defaultDatabase = DatabaseSelection.defaultName(previousDefault, items: items, chosen: chosen)
    listed = true
  }
  private func submit() {
    loading = true
    phase = "Bağlanıyor…"
    error = ""
    Task { @MainActor in
      defer { loading = false }
      do {
        var final = profile
        final.appearance = try profile.appearance?.validated()
        try final.selectDatabases(chosen, available: items)
        if chosen.contains(defaultDatabase) { final.database = defaultDatabase }
        try await connect(final, password, remember)
      } catch { self.error = error.localizedDescription }
    }
  }
}

extension WorkbenchController {
  private func linkedNode(_ title: String, kind: TreeNode.Kind = .group, branch: TreeNode.LinkedBranch, parent: TreeNode, item: CatalogItem? = nil, loaded: Bool = false) -> TreeNode {
    let child=TreeNode(title,kind:kind,server:parent.server,database:"master",item:item)
    child.linked=branch; child.loaded=loaded
    return child
  }
  func loadLinked(_ node: TreeNode) {
    guard !node.loading, !node.loaded, node.server.online || node.server.catalogFixture != nil else {return}
    if node.linked == nil, node.objectFolder == .linkedServers, let item=node.item {
      node.children=[linkedNode("Catalogs",branch:.catalogs(item.name),parent:node)]
      node.loaded=true; reloadExplorer(item:node,children:true); return
    }
    guard let branch=node.linked else {return}
    if case .relation(let relation)=branch {
      node.children=[linkedNode("Columns",kind:.folder(.columns),branch:.columns(relation),parent:node)]
      node.loaded=true; reloadExplorer(item:node,children:true); return
    }
    let sql:String
    switch branch {
    case .catalogs(let link): sql=LinkedCatalog.catalogsSQL(server:link)
    case .catalog(let link,let catalog): sql=LinkedCatalog.relationsSQL(server:link,catalog:catalog)
    case .columns(let relation): sql=LinkedCatalog.columnsSQL(relation)
    default: return
    }
    node.loading=true; node.error=nil; reloadExplorer(item:node)
    let generation=node.server.generation
    let metadata=node.server.metadata
    Task { [weak self, weak node] in
      guard let self,let node else {return}
      defer {node.loading=false; reloadExplorer(item:node,children:true)}
      do {
        var limits=Limits(); limits.rows=5000; limits.totalBytes=8_000_000; limits.timeout=30
        let result=try await node.server.catalog(sql,database:"master",limits:limits)
        guard generation == node.server.generation, node.server.metadata === metadata,
          node.server.online || node.server.catalogFixture != nil else {return}
        switch branch {
        case .catalogs(let link):
          let catalogs=try LinkedCatalog.catalogs(result)
          node.children=catalogs.map {linkedNode($0,branch:.catalog(link,$0),parent:node)}
          if catalogs.isEmpty {
            node.children=[linkedNode("Varsayılan katalog (sağlayıcı katalog adı döndürmedi)",branch:.catalog(link,nil),parent:node)]
          }
        case .catalog(let link,let catalog):
          let relations=try LinkedCatalog.relations(result,server:link,catalog:catalog)
          let groups=["Tables","Views","System Tables","System Views","Synonyms & Aliases","Temporary Tables","Other Objects"]
          node.children=groups.compactMap { title in
            let items=relations.filter {$0.group == title}
            guard !items.isEmpty else {return nil}
            let group=linkedNode(title,branch:.group,parent:node,loaded:true)
            group.children=items.map { relation in
              let kind:Folder=relation.type.uppercased().contains("VIEW") ? .views : .tables
              let display=(catalog == nil ? relation.catalog.map {$0+" · "} ?? "" : "")+(relation.schema.map {$0+"."} ?? "")+relation.name
              return linkedNode(display,kind:.object(kind),branch:.relation(relation),parent:group,item:CatalogItem(name:relation.name,schema:relation.schema ?? "",detail:relation.type + (relation.remarks.isEmpty ? "" : " · "+relation.remarks)))
            }
            return group
          }
        case .columns(let relation):
          node.children=try LinkedCatalog.columns(result,relation:relation).map {
            linkedNode($0.name + ($0.detail.isEmpty ? "" : " ("+$0.detail+")"),kind:.detail,branch:.detail,parent:node,item:$0,loaded:true)
          }
        default: break
        }
        if node.children.isEmpty {
          node.children=[linkedNode("Görünür metadata yok; sağlayıcı desteği ve yetkileri kontrol edin.",kind:.detail,branch:.detail,parent:node,loaded:true)]
        }
        if result.partial {
          node.children.append(linkedNode("Kısmi liste: satır, süre veya boyut sınırına ulaşıldı.",kind:.detail,branch:.detail,parent:node,loaded:true))
        }
        node.loaded=true
      } catch {
        guard generation == node.server.generation, node.server.metadata === metadata else {return}
        node.error=error.localizedDescription; node.loaded=true
        node.children=[linkedNode("Metadata alınamadı — Yenile ile tekrar deneyin",kind:.detail,branch:.detail,parent:node,loaded:true)]
      }
    }
  }
  func linkedMenu(for node: TreeNode) -> NSMenu {
    let menu=NSMenu()
    func add(_ title:String,_ action:Selector) {
      let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;item.representedObject=node;menu.addItem(item)
    }
    add("Yenile",#selector(linkedRefresh(_:)))
    if case .relation = node.linked {
      add("Select Top 1000 Rows",#selector(linkedSelect(_:)))
      add("SELECT SQL'ini Aç",#selector(linkedScript(_:)))
      add("Tam Adı Kopyala",#selector(linkedCopy(_:)))
    }
    if node.objectFolder == .linkedServers, node.linked == nil {
      add("Test Connection",#selector(linkedTest(_:)))
      add("Properties…",#selector(linkedProperties(_:)))
    }
    return menu
  }
  @objc private func linkedRefresh(_ sender:NSMenuItem) {if let node=sender.representedObject as? TreeNode {refresh(node)}}
  @objc private func linkedSelect(_ sender:NSMenuItem) {if let node=sender.representedObject as? TreeNode {openLinkedRelation(node,run:true)}}
  @objc private func linkedScript(_ sender:NSMenuItem) {if let node=sender.representedObject as? TreeNode {openLinkedRelation(node,run:false)}}
  func openLinkedRelation(_ node:TreeNode,run:Bool) {
    guard case .relation(let relation)=node.linked else {return}
    state.newQuery(server:node.server,database:"master",text:relation.selectSQL,title:relation.name,run:run)
  }
  @objc private func linkedCopy(_ sender:NSMenuItem) {
    guard let node=sender.representedObject as? TreeNode,case .relation(let relation)=node.linked else {return}
    NSPasteboard.general.clearContents();NSPasteboard.general.setString(relation.qualified,forType:.string)
  }
  @objc private func linkedTest(_ sender:NSMenuItem) {
    guard let node=sender.representedObject as? TreeNode,let item=node.item else {return}
    state.newQuery(server:node.server,database:"master",text:LinkedCatalog.testSQL(server:item.name),title:"Test Connection · "+item.name,run:true)
  }
  @objc private func linkedProperties(_ sender:NSMenuItem) {
    guard let node=sender.representedObject as? TreeNode else {return}
    contextNode=node;objectProperties()
  }
}


extension WorkbenchController {
  @objc private func toggleAgentAutoRefresh() {agentAutoRefresh.toggle()}
  func refreshExpandedAgentJobs() async {
    guard agentAutoRefresh, isViewLoaded, let window=view.window, window.isVisible, !window.isMiniaturized else {return}
    for root in roots where root.server.online && !root.server.reconnecting && outline.isItemExpanded(root) {
      for agent in root.children where agent.title == "SQL Server Agent" && outline.isItemExpanded(agent) {
        for jobs in agent.children where jobs.objectFolder == nil {
          guard case .folder(.jobs)=jobs.kind, jobs.loaded, !jobs.loading else {continue}
          jobs.loading=true
          let token=root.server.generation
          let metadata=root.server.metadata
          defer {jobs.loading=false;reloadExplorer(item:jobs)}
          do {
            var limits=Limits();limits.rows=5000;limits.timeout=10
            let result=try await root.server.catalog(Catalog.objects(.jobs),database:"msdb",limits:limits)
            guard root.server.online,root.server.generation == token,root.server.metadata === metadata else {continue}
            let items=Catalog.rows(result)
            var existing=Dictionary(jobs.children.compactMap {child in child.item.map {($0.name,child)}},uniquingKeysWith: {a,_ in a})
            jobs.children=items.map {item in
              if let old=existing.removeValue(forKey:item.name) {old.item=item;return old}
              return TreeNode(item.name,kind:.object(.jobs),server:root.server,database:"msdb",item:item)
            }
            jobs.loaded=true
            jobs.error=result.partial ? "Kısmi job listesi; metadata sınırına ulaşıldı.":nil
            let selected=outline.item(atRow:outline.selectedRow) as? TreeNode
            let origin=outline.enclosingScrollView?.contentView.bounds.origin
            reloadExplorer(item:jobs,children:true)
            if let selected,outline.row(forItem:selected)>=0 {outline.selectRowIndexes(IndexSet(integer:outline.row(forItem:selected)),byExtendingSelection:false)}
            if let origin,let scroll=outline.enclosingScrollView {scroll.contentView.scroll(to:origin);scroll.reflectScrolledClipView(scroll.contentView)}
          } catch {
            guard root.server.generation == token else {continue}
            jobs.error=error.localizedDescription;reloadExplorer(item:jobs)
          }
        }
      }
    }
  }
}

@MainActor private struct ExplorerIndexPanel: View {
  let server:ConnectedServer
  let databases:[String]
  let refresh:()->Void
  @State private var revision=UUID()
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Label("Yerel indeks",systemImage:"externaldrive").font(.title3.bold())
      Text(server.profile.name).foregroundStyle(.secondary)
      ScrollView {
        VStack(spacing:12) {
          ForEach(databases,id:\.self) {db in ExplorerIndexCard(server:server,database:db).id(revision.uuidString+db)}
        }
      }.frame(maxHeight:420)
      Text("Bu Mac’teki arama ve SQL önerisi önbelleği.").font(.caption).foregroundStyle(.secondary)
      StudioActionButton("Yerel İndeksi Yenile",icon:"arrow.clockwise",tint:.accentColor,action:refresh).disabled(!server.online)
    }.padding(18).frame(maxWidth:.infinity,maxHeight:.infinity).studioPanel()
      .onReceive(NotificationCenter.default.publisher(for:.init("catalogIndexUpdated"))) {note in
        if let updated=note.object as? ConnectedServer,updated === server {revision=UUID()}
      }
  }
}

@MainActor private struct ExplorerIndexCard:View {
  let server:ConnectedServer
  let database:String
  @State private var count:Int?
  @State private var objectDate:Date?
  @State private var columnDate:Date?
  @State private var fresh=false
  @State private var loading=true
  @State private var error:String?
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack {
        Label(database,systemImage:"cylinder.split.1x2").font(.headline)
        Spacer()
        if loading {ProgressView().controlSize(.small)}
        else {Label(error != nil ? "Hata" : server.indexingDatabases.contains(database) ? "Hazırlanıyor" : count == nil ? "Hazır değil" : "Hazır",systemImage:error != nil ? "exclamationmark.triangle" : count == nil ? "clock" : "checkmark.circle.fill").foregroundStyle(error != nil ? .orange : count == nil ? .secondary : .green).font(.caption)}
      }
      HStack(alignment:.top,spacing:12) {
        metric("Nesneler",value:count.map(String.init) ?? "—",icon:"square.stack.3d.up",date:objectDate)
        metric("SQL kolonları",value:columnDate == nil ? "Hazır değil" : fresh ? "Güncel" : "Yenileme gerekli",icon:"tablecells",date:columnDate)
      }
      if let error {Label(error,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
      if !server.online {Label("Bağlantı kapalı · önbellek bilgisi",systemImage:"network.slash").font(.caption).foregroundStyle(.secondary)}
    }.padding(14).frame(maxWidth:.infinity,alignment:.leading).explorerInfoCard()
      .task {
        do {
          let objects=try await CatalogDiskIndex.shared.status(scope:CatalogDiskIndex.scope(profile:server.profile,database:database))
          let columns=try await SQLCatalogService.shared.cached(profile:server.profile,database:database)
          count=objects?.count;objectDate=objects?.synchronizedAt;columnDate=columns?.snapshot.synchronizedAt;fresh=columns?.fresh == true
          error=server.indexErrors[database]
        } catch {self.error=error.localizedDescription}
        loading=false
      }
  }
  private func metric(_ title:String,value:String,icon:String,date:Date?) -> some View {
    VStack(alignment:.leading,spacing:7) {
      Label(title,systemImage:icon).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.headline)
      Text(date?.formatted(date:.abbreviated,time:.shortened) ?? "Henüz eşitlenmedi").font(.caption2).foregroundStyle(.secondary)
    }.padding(10).frame(maxWidth:.infinity,alignment:.leading).explorerInfoCard()
  }
}

@MainActor private struct ExplorerDatabasePanel:View {
  let server:ConnectedServer
  let database:String
  @State private var sections:[(title:String,fields:[(String,String)])]=[]
  @State private var loading=false
  @State private var error:String?
  @State private var revision=UUID()
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      HStack {
        Label(database,systemImage:"cylinder.split.1x2").font(.title2.bold())
        Spacer()
        StudioActionButton("Yenile",icon:"arrow.clockwise",tint:.accentColor) {revision=UUID()}.disabled(loading || !server.online)
      }
      Text(server.profile.name+" · Salt okunur veritabanı bilgileri").foregroundStyle(.secondary)
      Divider()
      if loading {ProgressView("Veritabanı bilgileri yükleniyor…")}
      if let error {Label(error,systemImage:"exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)}
      ScrollView {
        VStack(alignment:.leading,spacing:14) {
          ForEach(sections.indices,id:\.self) {index in
            VStack(alignment:.leading,spacing:12) {
              Label(sections[index].title,systemImage:sections[index].title == "Genel" ? "info.circle" : "doc").font(.headline)
              ForEach(sections[index].fields.indices,id:\.self) {row in
                let field=sections[index].fields[row]
                StudioFormField(field.0) {Text(field.1).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
              }
            }.padding(16).frame(maxWidth:.infinity,alignment:.leading).explorerInfoCard()
          }
        }
      }
      Spacer(minLength:0)
    }.padding(20).studioPanel().task(id:revision) {await load()}
  }
  private func load() async {
    guard server.online else {error="Sunucu bağlantısı kapalı. Bilgileri yüklemek için yeniden bağlanın.";return}
    loading=true;error=nil
    defer {loading=false}
    do {
      let result=try await server.catalog("SELECT name,state_desc,recovery_model_desc,compatibility_level,collation_name,is_read_only FROM sys.databases WHERE name=\(SQL.literal(database)); SELECT name,type_desc,CAST(size*8.0/1024 AS decimal(18,2)) AS size_mb,physical_name FROM sys.database_files;",database:database)
      guard !Task.isCancelled else {return}
      let general=["Ad","Durum","Kurtarma modeli","Uyumluluk düzeyi","Karşılaştırma düzeni","Salt okunur"]
      let files=["Ad","Tür","Boyut (MB)","Dosya yolu"]
      sections=[]
      for (index,set) in result.results.enumerated() {
        for row in set.values {
          let labels=index == 0 ? general : files
          sections.append((index == 0 ? "Genel" : "Dosya \(sections.count)",row.enumerated().map {offset,value in (offset < labels.count ? labels[offset] : "Değer",value ?? "—")}))
        }
      }
      if sections.isEmpty {error="Veritabanı bilgisi dönmedi; erişim izinlerini kontrol edin."}
    } catch {self.error=error.localizedDescription}
  }
}

private extension View {
  func explorerInfoCard() -> some View {
    background(Color(nsColor:StudioTheme.canvas),in:RoundedRectangle(cornerRadius:8))
      .overlay(RoundedRectangle(cornerRadius:8).stroke(Color(nsColor:StudioTheme.border),lineWidth:1))
  }
}
