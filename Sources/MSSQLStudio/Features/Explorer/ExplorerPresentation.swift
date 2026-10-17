import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  func buildExplorer() {
    let background = NSView()
    StudioTheme.surface(background, sidebar: true)
    explorer.view = background
    let label = NSTextField(labelWithString: "Explorer")
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    let refresh = symbolButton("arrow.clockwise", tip: "Seçili dalı ve kapsamındaki yerel indeksleri yenile", action: #selector(refreshExplorer))
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
    label.lineBreakMode = .byClipping
    label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    explorerSearch.controlSize = .small
    explorerSearch.font = .systemFont(ofSize: 12)
    explorerSearch.placeholderString = "Nesnelerde filtrele"
    explorerSearch.target = self
    explorerSearch.action = #selector(filterExplorer)
    outline.style = .plain
    outline.headerView = nil
    outline.rowHeight = ExplorerDensity.current(in:state.explorerTreeDefaults).rowHeight
    outline.intercellSpacing = NSSize(width: 1, height: 0)
    outline.indentationPerLevel = 14
    outline.selectionHighlightStyle = .regular
    outline.usesAlternatingRowBackgroundColors = false
    let column = NSTableColumn(identifier: .init("object"))
    column.width = 274;column.minWidth=40;column.resizingMask = .autoresizingMask
    outline.autoresizesOutlineColumn=false
    outline.columnAutoresizingStyle = .noColumnAutoresizing
    outline.autoresizingMask = [.width]
    outline.addTableColumn(column)
    let indexes=NSTableColumn(identifier:.init("indexes"));indexes.width=56;indexes.minWidth=56;indexes.maxWidth=56;indexes.resizingMask=[]
    outline.addTableColumn(indexes)
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
    indexStatus.setContentCompressionResistancePriority(.required,for:.horizontal)
    let menu = StudioMenu()
    menu.delegate = self
    outline.menu = menu
    outline.shortcutMenu={ [weak self] in
      guard let self else {return nil}
      let menu=StudioMenu();populateExplorerMenu(menu,for:outline.item(atRow:outline.selectedRow) as? TreeNode);return menu
    }
    let scroll = ExplorerScrollView()
    scroll.documentView = outline
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.drawsBackground = false
    scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
    searchOperator.addItems(withTitles: ["İçerir", "Eşittir", "İle başlar", "İle biter", "İçermez"])
    searchOperator.target = self; searchOperator.action = #selector(filterExplorer)
    searchType.addItems(withTitles:["Tüm nesneler","Tables","Views","Procedures","Functions","Synonyms"])
    searchType.target = self; searchType.action = #selector(filterExplorer)
    searchType.setAccessibilityLabel("Aranacak nesne türü")
    let searchOptions = NSStackView(views:[searchOperator,searchType]); searchOptions.spacing = 4
    searchOptions.distribution = .fillEqually
    // Metadata names and explanatory text must not dictate the pane's minimum width.
    for control in [searchScopePicker,searchOperator,searchType] {
      if !(control is StudioSelectionControl) {control.controlSize = .small; control.font = .systemFont(ofSize: 11)}
      control.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
      (control.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
    }
    for control in [searchStatus,explorerSearch,explorerTabs] {
      control.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    }
    searchOperator.setAccessibilityLabel("Nesne arama operatörü")
    searchStatus.font = .systemFont(ofSize: 10); searchStatus.textColor = .secondaryLabelColor
    searchStatus.lineBreakMode = .byTruncatingMiddle
    searchScopePicker.target = self; searchScopePicker.action = #selector(changeSearchScope)
    searchScopePicker.setAccessibilityLabel("Nesne arama kapsamı")
    searchScopePicker.toolTip = "Arama bu bağlantı ve veritabanında kalır; metni temizlemek kapsamı değiştirmez."
    explorerTabs.controlSize = .small
    explorerTabs.selectedSegment = 0
    explorerTabs.target = self; explorerTabs.action = #selector(changeExplorerTab)
    explorerTabs.setAccessibilityLabel("Explorer sekmeleri")
    for button in [connect,indexStatus,refresh,collapse] { (button as? StudioToolbarButton)?.flat=true }
    searchFilters.orientation = .vertical;searchFilters.alignment = .leading;searchFilters.spacing=4
    searchFilters.addArrangedSubview(searchScopePicker);searchFilters.addArrangedSubview(searchOptions)
    searchFilters.isHidden = !showingSearch
    let stack = NSStackView(views: [header, explorerTabs, explorerSearch, searchFilters, searchStatus, scroll])
    stack.orientation = .vertical
    stack.distribution = .fill
    stack.alignment = .leading
    stack.spacing = 4
    background.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -4),
      header.widthAnchor.constraint(equalTo: stack.widthAnchor),
      explorerTabs.widthAnchor.constraint(equalTo: stack.widthAnchor),
      explorerSearch.widthAnchor.constraint(equalTo: stack.widthAnchor),
      searchFilters.widthAnchor.constraint(equalTo: stack.widthAnchor),
      searchScopePicker.widthAnchor.constraint(equalTo: searchFilters.widthAnchor),
      searchScopePicker.heightAnchor.constraint(equalToConstant:StudioMetrics.controlHeight),
      explorerSearch.heightAnchor.constraint(equalToConstant:StudioMetrics.controlHeight),
      searchOptions.widthAnchor.constraint(equalTo: searchFilters.widthAnchor),
      searchOptions.heightAnchor.constraint(equalToConstant:StudioMetrics.controlHeight),
      searchStatus.widthAnchor.constraint(equalTo: stack.widthAnchor),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }
}
extension WorkbenchController {
  @objc func updateExplorerDensity() {
    guard isViewLoaded else {return}
    let origin=outline.enclosingScrollView?.contentView.bounds.origin
    outline.rowHeight=ExplorerDensity.current(in:state.explorerTreeDefaults).rowHeight
    outline.tile();outline.needsDisplay=true
    if let origin,let scroll=outline.enclosingScrollView {scroll.contentView.scroll(to:origin);scroll.reflectScrolledClipView(scroll.contentView)}
  }
  func visible(_ nodes: [TreeNode]) -> [TreeNode] { nodes }
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
      !organization.groups.isEmpty || explorerDropIndex(sourceID:id,item:item,childIndex:childIndex) != nil else {return []}
    if !organization.groups.isEmpty {
      guard explorerGroupDrop(sourceID:id,item:item,childIndex:childIndex,apply:false) else {return []}
      return .move
    }
    let index=explorerDropIndex(sourceID:id,item:item,childIndex:childIndex)!
    outlineView.setDropItem(nil,dropChildIndex:index)
    return .move
  }
  func outlineView(_ outlineView:NSOutlineView,acceptDrop info:any NSDraggingInfo,item:Any?,childIndex:Int) -> Bool {
    guard info.draggingSource as? NSOutlineView === outlineView,info.draggingPasteboard.pasteboardItems?.count == 1,
      let raw=info.draggingPasteboard.string(forType:Self.explorerDragType),let id=UUID(uuidString:raw),
      !organization.groups.isEmpty || explorerDropIndex(sourceID:id,item:item,childIndex:childIndex) != nil else {return false}
    if !organization.groups.isEmpty {return explorerGroupDrop(sourceID:id,item:item,childIndex:childIndex,apply:true)}
    return state.moveExplorer(id,to:explorerDropIndex(sourceID:id,item:item,childIndex:childIndex)!)
  }
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    visible((item as? TreeNode)?.children ?? (showingSearch ? searchResults ?? [] : displayRoots)).count
  }
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    visible((item as? TreeNode)?.children ?? (showingSearch ? searchResults ?? [] : displayRoots))[index]
  }
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    (item as? TreeNode)?.expandable ?? false
  }
  func reloadExplorer(item:TreeNode?=nil,children:Bool=false) {
    if item == nil {(outline.enclosingScrollView as? ExplorerScrollView)?.requiredObjectWidth=40}
    let previous=restoringTree;restoringTree=true
    if let item {outline.reloadItem(item,reloadChildren:children)} else {outline.reloadData()}
    restoringTree=previous
    if item == nil || children {restoreExplorerExpansion()}
    outline.enclosingScrollView?.needsLayout=true
  }
  func restoreExplorerExpansion() {
    guard !showingSearch,!restoringTree else {return}
    restoringTree=true;defer {restoringTree=false}
    func restore(_ node:TreeNode,isRoot:Bool=false) {
      guard node.expandable,outline.row(forItem:node)>=0 else {return}
      let expanded=expansionState[node.persistenceKey] ?? (isRoot || roots.contains(where:{$0 === node}) || node.connectionGroupID != nil)
      if expanded {
        outline.expandItem(node)
        for child in node.children {restore(child)}
      } else {outline.collapseItem(node)}
    }
    for root in displayRoots {restore(root,isRoot:true)}
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
  @objc func compareDatabasesAtNode() {
    let selection=outline.selectedRowIndexes.compactMap {outline.item(atRow:$0) as? TreeNode}
    let nodes=contextNode.map {node in selection.contains(where:{$0 === node}) ? selection:[node]} ?? selection
    let seeds=schemaEndpoints(for:nodes)
    let endpoints=state.servers.filter(\.online).flatMap {server in server.databases.map {SchemaEndpoint(server:server,database:$0.name)}}
    let model=SchemaComparisonModel(endpoints:endpoints,sourceID:seeds.first?.id)
    let owner=SchemaComparisonWindow(model:model) {[weak self] endpoint,sql in self?.state.newQuery(server:endpoint.server,database:endpoint.database,text:sql,title:"DDL Karşılaştırma · SQL Önizlemesi")}
    auxiliaryWindows.append(owner);owner.showWindow(nil)
  }
  func outlineViewSelectionDidChange(_ notification: Notification) {
    if !showingSearch, !restoringTree, let node=selected,node.connectionGroupID == nil {
      let followsSelection:Bool
      switch node.kind {
      case .server, .database: followsSelection=true
      default: followsSelection=node.server !== searchScope?.server
      }
      if followsSelection {
        rebuildSearchScopes(selecting:node)
        filterExplorer()
      }
    }
    updateControls()
  }
  func outlineView(_ outlineView:NSOutlineView,didAdd rowView:NSTableRowView,forRow row:Int) {
    (outlineView.view(atColumn:1,row:row,makeIfNecessary:true) as? ExplorerIndexCell)?.pinToViewport()
  }
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any)
    -> NSView?
  {
    guard let node = item as? TreeNode else { return nil }
    if tableColumn?.identifier.rawValue == "indexes" {return indexCell(for:node)}
    let cell = ExplorerMetadataCell();cell.node=node
    // Connection health is represented by its connection icon and tooltip.
    // Keep errors on actual metadata nodes visible without warning adornments on servers.
    let presentsError:Bool
    if case .server=node.kind {presentsError=false} else {presentsError=node.error != nil}
    let label = NSTextField(
      labelWithString: node.displayTitle + (node.loading ? " …" : "")
        + (presentsError ? " ⚠" : ""))
    label.font = .systemFont(ofSize: 12)
    label.lineBreakMode = .byClipping
    if let scroll=outlineView.enclosingScrollView as? ExplorerScrollView {
      let textWidth=ceil((label.stringValue as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.semibold)]).width)
      let width=textWidth+CGFloat(max(0,outlineView.level(forItem:node)))*outlineView.indentationPerLevel+48
      if width>scroll.requiredObjectWidth {scroll.requiredObjectWidth=width;scroll.needsLayout=true}
    }
    if node.objectFolder == .jobs || node.objectFolder == .triggers {
      label.setAccessibilityLabel(node.displayTitle + " · " + (node.item?.detail ?? ""))
    }
    let image = NSImageView(
      image: NSImage(systemSymbolName: node.icon, accessibilityDescription: nil)!)
    image.contentTintColor = presentsError ? .systemOrange : node.tint
    if case .server = node.kind {
      image.image = NSImage(systemSymbolName: node.server.reconnecting || node.server.updatingProfile ? "arrow.triangle.2.circlepath" : node.server.online ? "externaldrive.connected.to.line.below" : "externaldrive.badge.xmark", accessibilityDescription: node.displayTitle)
      image.contentTintColor = node.server.reconnecting || node.server.updatingProfile ? .systemOrange : node.server.online ? .systemGreen : .secondaryLabelColor
    }
    label.textColor = presentsError ? .systemOrange : .labelColor
    if case .server = node.kind { label.font = .systemFont(ofSize: 12, weight: .semibold) }
    if case .database=node.kind {label.font = .systemFont(ofSize:12,weight:.medium)}
    if let id=node.connectionGroupID {
      label.font = .systemFont(ofSize:12,weight:.semibold)
      image.contentTintColor=groupColor(id) ?? StudioTheme.accent
    }
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
      label.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-3),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    if node.objectFolder == .columns || node.objectFolder == .parameters || node.objectFolder == .functions {cell.toolTip=nil}
    cell.textField = label
    cell.imageView = image
    cell.toolTip = node.error ?? (!node.server.online ? "Explorer bağlantısı kapalı. Son yüklenen nesneler gösteriliyor. Bağlantı işlemleri menüsünden yeniden bağlanabilirsiniz; açık sorgu oturumları korunur." : nil) ?? node.item?.detail ?? "\(node.server.profile.name) · \(node.server.profile.host),\(node.server.profile.port) · \(node.database)"
    cell.toolTip=node.displayTitle+"\n"+(cell.toolTip ?? "")
    if case .server = node.kind {
      cell.toolTip=(cell.toolTip ?? "")+" · "+(node.server.profile.appearance?.badge ?? "")+"\nSürükleyerek Explorer bağlantılarının sırasını değiştirin."
      image.setAccessibilityLabel(node.server.updatingProfile ? "Kaydediliyor" : node.server.reconnecting ? "Bağlanıyor" : node.server.online ? "Bağlı" : "Bağlantı kapalı")
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
    if let id=node.connectionGroupID {cell.toolTip=organization.path(id)+" · Yerel bağlantı klasörü · Bağlantıları buraya sürükleyebilirsiniz";label.setAccessibilityLabel(node.title)}
    if [.columns,.parameters,.functions].contains(node.objectFolder) {cell.toolTip=nil}
    return cell
  }
  func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
    guard let node = item as? TreeNode else { return StudioRowView() }
    let color:NSColor?
    if let id=node.connectionGroupID {color=groupColor(id) ?? StudioTheme.accent}
    else if let appearance=node.server.profile.appearance,appearance.isMarked {color=appearance.color}
    else {color=organization.color(for:node.server.id).map {ServerAppearance(colorHex:$0).color}}
    guard let color else {return StudioRowView()}
    let row = ConnectionTreeRow()
    row.color = color
    if node.connectionGroupID != nil {row.isServer=true}
    if case .server = node.kind { row.isServer = true }
    return row
  }
}
