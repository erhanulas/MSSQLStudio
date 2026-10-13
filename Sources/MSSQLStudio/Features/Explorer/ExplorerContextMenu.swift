import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  @objc func openObject() {
    let row=outline.clickedRow>=0 ? outline.clickedRow:outline.selectedRow
    guard let node = outline.item(atRow:row) as? TreeNode else { return }
    if case .favorite = node.kind {openExplorerFavorite(node);return}
    if case .favorites = node.kind {
      if outline.isItemExpanded(node) {outline.collapseItem(node)} else {outline.expandItem(node)}
      return
    }
    if case .folder(.files)=node.kind {showDatabaseFiles(node.server);return}
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
    case .folder(.jobHistory):showAgentHistory(node)
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
    populateExplorerMenu(menu,for:outline.item(atRow:outline.clickedRow) as? TreeNode)
  }
  func populateExplorerMenu(_ menu:NSMenu,for node:TreeNode?) {
    menu.removeAllItems()
    menu.autoenablesItems=false
    contextNode=node
    let busy=node.map {$0.server.reconnecting || $0.server.updatingProfile} ?? false
    func command(_ title: String, _ selector: Selector) {
      let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
      item.target = self
      item.isEnabled = !busy
      let symbol = title.contains("Favori") ? "star" : title.contains("Yenile") ? "arrow.clockwise" : title.contains("Sorgu") ? "plus.square" : title.contains("İndeks") ? "externaldrive" : title.contains("Özellikler") ? "slider.horizontal.3" : title.contains("Kopyala") ? "doc.on.doc" : "gearshape"
      item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)
      menu.addItem(item)
    }
    func scriptMenu(_ title:String,modes:[String]) {
      let scripts=StudioMenu(title:title)
      for mode in modes {
        let destinations=StudioMenu(title:mode+" To")
        for destination in ["New Query Editor Window","Clipboard","File…"] {
          // ALTER in the editor already has the direct Modify command.
          if mode == "ALTER", destination == "New Query Editor Window" {continue}
          let item=NSMenuItem(title:destination,action:#selector(scriptManagedMenu(_:)),keyEquivalent:"");item.target=self;item.representedObject=[mode,destination];destinations.addItem(item)
        }
        let item=NSMenuItem(title:mode+" To",action:nil,keyEquivalent:"");item.submenu=destinations;scripts.addItem(item)
      }
      let item=NSMenuItem(title:title,action:nil,keyEquivalent:"");item.submenu=scripts;item.isEnabled = !busy;menu.addItem(item)
    }
    guard let node = contextNode else {
      command("Yeni Klasör…",#selector(createExplorerGroup(_:)))
      command("Yeni Bağlantı…",#selector(showConnect));return
    }
    if let id=node.connectionGroupID {
      command("Alt Klasör…",#selector(createExplorerGroup(_:)));menu.items.last?.representedObject=id.uuidString
      command("Klasörü Yeniden Adlandır…",#selector(renameExplorerGroup))
      addMoveMenu(to:menu,group:id,server:nil)
      addGroupColorMenu(to:menu,id:id)
      command("Klasörü Kaldır…",#selector(removeExplorerGroup));return
    }
    if case .server=node.kind {
      command("Bağlantıyı Yeniden Adlandır…",#selector(renameExplorerConnection))
      addMoveMenu(to:menu,group:nil,server:node.server.id)
      command("Kayıtlı Bağlantıyı Sil…",#selector(deleteExplorerConnection))
      menu.items.last?.toolTip="Kayıtlı profili ve bu profile ait parolayı siler; açık sorgu sekmeleri korunur."
      menu.addItem(.separator())
    }
    if case .favorite = node.kind {
      let favorites=favoriteMenu(for:node)
      for item in favorites.items {favorites.removeItem(item);menu.addItem(item)}
      return
    }
    if case .favorites = node.kind {command("Favori Sorguları Yönet…",#selector(showFavoritesAtNode));return}
    if case .detail = node.kind, node.linked == nil {
      if node.parent?.error != nil {command("Yüklemeyi Tekrar Dene",#selector(refreshContextParent))}
      command("Adı Kopyala",#selector(copyNodeName));menu.items.last?.isEnabled=true
      return
    }
    if case .server = node.kind {command("Favori Sorgular…",#selector(showFavoritesAtNode))}
    if case .database = node.kind {command("Favori Sorgular…",#selector(showFavoritesAtNode))}

    if !node.server.online || node.server.reconnecting {
      command(node.server.reconnecting ? "Bağlanıyor…" : "Yeniden Bağlan", #selector(reconnectServer))
      command("Bağlantı ayarları…", #selector(editConnection))
      if case .server = node.kind {
        command("Explorer’dan Kaldır…", #selector(disconnectServer))
        menu.items.last?.toolTip="Explorer’dan kaldırır; kayıtlı profil, parola ve açık sorgu sekmeleri korunur."
      }
      command("Yeni Sorgu", #selector(newQueryAtNode))
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
      command("Explorer’dan Kaldır…", #selector(disconnectServer))
      menu.items.last?.toolTip="Explorer’dan kaldırır; kayıtlı profil, parola ve açık sorgu sekmeleri korunur."
    }
    if case .database=node.kind {
      command("DDL Karşılaştır…",#selector(compareDatabasesAtNode))
      menu.items.last?.image=NSImage(systemSymbolName:"arrow.left.arrow.right.square",accessibilityDescription:"DDL Karşılaştır")
      menu.items.last?.toolTip="Command-tıklama ile iki veritabanı seçin; kaynak/hedef yönü karşılaştırma penceresinde değiştirilebilir."
    }
    command("Yeni Sorgu", #selector(newQueryAtNode))
    if node.expandable || node.objectFolder != nil {
      command("Nesneleri Yenile", #selector(refreshContextNode))
      menu.items.last?.toolTip="Bu dalın nesne listesini sunucudan yeniden okur; açık SQL sekmelerini çalıştırmaz ve yerel disk indeksini yeniden oluşturmaz."
    }
    menu.addItem(.separator())
    if case .object(let folder) = node.kind {
      if [.tables, .views].contains(folder) {
        if folder == .tables { command("Design…", #selector(designTableObject)); command("Edit Top 200 Rows…", #selector(editObjectData)) }
        else { command("Design…", #selector(designViewObject)); command("Modify · ALTER…", #selector(modifyManagedModule)) }
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
      if [.columns,.parameters].contains(folder), let owner=node.ownerObject {
        command(owner.objectFolder == .tables ? "Modify / Properties…" : "Modify · ALTER…",#selector(manageChildStructure))
      }
      if [.logins,.users,.roles].contains(folder) {command("Properties…",#selector(objectProperties))}
    }
    if case .folder(.tables) = node.kind { command("New Table…",#selector(newManagedTable)) }
    if case .folder(.views) = node.kind { command("New View…",#selector(newManagedView)) }
    if case .folder(.procedures)=node.kind {command("New Stored Procedure…",#selector(newManagedProcedure))}
    if case .folder(.functions)=node.kind {command("New Scalar Function…",#selector(newManagedScalarFunction));command("New Inline Table-valued Function…",#selector(newManagedTableFunction))}
    if case .folder(.triggers)=node.kind {command("New Trigger…",#selector(newManagedTrigger))}
    if case .folder(.synonyms)=node.kind {command("New Synonym…",#selector(newManagedSynonym))}
    if case .folder(let f)=node.kind, [.indexes,.keys,.constraints].contains(f), node.ownerObject != nil {command("New…",#selector(manageChildStructure))}
    if case .folder(let folder) = node.kind, [.activity,.sessions,.locks,.files].contains(folder) {
      command(folder == .activity ? "Grafikli Activity Monitor…" : folder == .files ? "Veritabanı Dosyaları…" : "Verileri Aç", #selector(openMonitoring))
      if folder == .activity {command("Sorguda Tablo Olarak İzle",#selector(openActivityTable))}
    }
    if case .database = node.kind {
      let create=StudioMenu(title:"Yeni Nesne")
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
    menu.items.last?.isEnabled=true
  }
  func agentMenu(for node:TreeNode) -> NSMenu {
    let menu=StudioMenu()
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
  @objc func agentMenuAction(_ item:NSMenuItem) {
    guard let node=item.representedObject as? TreeNode,let command=item.identifier?.rawValue else {return}
    switch command {
    case "history":showAgentHistory(node)
    case "properties":showAgentProperties(node)
    case "schedule":showAgentSchedule(node)
    case "activity":showAgentActivity(node)
    default:if let action=SQLAgent.Action(rawValue:command) {showAgentAction(node,action:action)}
    }
  }
  @objc func agentChanged(_ notification:Notification) {
    guard let server=notification.object as? ConnectedServer else {return}
    for root in roots where root.server === server {
      for group in root.children where group.title == "SQL Server Agent" {
        for branch in group.children where branch.loaded {refresh(branch)}
      }
    }
  }
}
