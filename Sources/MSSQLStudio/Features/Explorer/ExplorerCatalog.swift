import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  @objc func refreshManagedObject(_ notification:Notification) {
    guard let node=notification.object as? TreeNode else {return}
    if case .folder = node.kind {refresh(node)} else {refresh(node.parent ?? node)}
  }
  func refresh(_ node: TreeNode,indexForce:Bool=false) {
    if case .favorites = node.kind {Task {await state.favorites.load()};return}
    if case .favorite = node.kind {return}
    if case .object = node.kind, !node.expandable,let parent=node.parent {refresh(parent);return}
    if case .folder(.databases) = node.kind,
      let root = roots.first(where: { $0.server === node.server })
    {
      refresh(root,indexForce:indexForce)
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
          node.server.prepareCatalogIndexes(force:indexForce)
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
    } else {
      func refreshBranches(_ branch:TreeNode) {
        if case .folder = branch.kind, branch.expandable, branch.loaded {
          branch.loaded=false; branch.error=nil; load(branch)
        } else if branch.expandable {
          for child in branch.children {refreshBranches(child)}
        }
      }
      switch node.kind {
      case .database,.group:
        for branch in node.children {refreshBranches(branch)}
      default:
        node.loaded = false
        node.error = nil
        load(node)
      }
    }
  }
  func refreshExplorerScope(_ node:TreeNode) {
    refresh(node,indexForce:true)
    guard node.server.online else {return}
    if case .database=node.kind {refreshIndexInBackground(server:node.server,database:node.database,force:true)}
  }
  @objc func refreshExplorer() {
    if let node = selected ?? roots.first { refreshExplorerScope(node) }
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
  @objc func reconnectServer() {
    guard let server = contextNode?.server else { return }
    Task { await state.reconnectExplorer(server) }
  }
  func explorerConnectionMenu(server:ConnectedServer?) -> NSMenu {
    let menu=StudioMenu();menu.autoenablesItems=false
    let add=NSMenuItem(title:"Yeni Bağlantı…",action:#selector(showConnect),keyEquivalent:"")
    add.target=self;add.image=NSImage(systemSymbolName:"plus",accessibilityDescription:nil);menu.addItem(add)
    let folder=NSMenuItem(title:"Yeni Klasör…",action:#selector(createExplorerGroup(_:)),keyEquivalent:"")
    folder.target=self;folder.image=NSImage(systemSymbolName:"folder.badge.plus",accessibilityDescription:nil);menu.addItem(folder)
    if let server {
      menu.addItem(.separator())
      let action=NSMenuItem(title:server.online ? "Aktif Bağlantıyı Kapat":"Yeniden Bağlan",action:server.online ? #selector(closeExplorerConnection(_:)):#selector(reconnectExplorerConnection(_:)),keyEquivalent:"")
      action.target=self;action.representedObject=server;action.isEnabled = !server.reconnecting
      action.image=NSImage(systemSymbolName:server.online ? "power":"arrow.triangle.2.circlepath",accessibilityDescription:nil)
      action.toolTip=server.profile.name+" · Açık sorgu oturumları korunur."
      menu.addItem(action)
    }
    menu.addItem(.separator())
    for (title,action) in [("Explorer’ı Dışa Aktar…",#selector(exportExplorer)),("Explorer’ı İçe Aktar…",#selector(importExplorer))] {
      let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;item.isEnabled = !explorerTransferBusy;menu.addItem(item)
    }
    return menu
  }
  @objc func showExplorerConnections(_ sender:NSButton) {
    explorerConnectionMenu(server:selectedServer).popUp(positioning:nil,at:NSPoint(x:0,y:sender.bounds.maxY),in:sender)
  }
  @objc func closeExplorerConnection(_ sender:NSMenuItem) {
    guard let server=sender.representedObject as? ConnectedServer,server.online,!server.reconnecting else {return}
    Task {await state.disconnectExplorer(server)}
  }
  @objc private func reconnectExplorerConnection(_ sender:NSMenuItem) {
    guard let server=sender.representedObject as? ConnectedServer else {return}
    Task {await state.reconnectExplorer(server)}
  }
  @objc func disconnectServer() {
    guard let server = contextNode?.server else { return }
    guard !server.reconnecting, let window = view.window else { return }
    let alert = StudioAlert()
    alert.messageText = "Bağlantı Explorer’dan kaldırılsın mı?"
    alert.informativeText = "\(server.profile.name) bağlantısı Explorer’dan ve yerel nesne/kolon/tanım indeksleri diskten kaldırılacak. Kayıtlı bağlantı bilgileri ve açık sorgu sekmeleri korunur."
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
  @objc func schemaApplied(_ notification:Notification) {
    guard let server=notification.object as? ConnectedServer,let db=notification.userInfo?["database"] as? String,
      let key=notification.userInfo?["key"] as? SchemaObjectKey,let type=notification.userInfo?["type"] as? String else {return}
    Task {[weak self] in await self?.refreshComparedObject(server:server,database:db,key:key,type:type)}
  }
  func refreshComparedObject(server:ConnectedServer,database:String,key:SchemaObjectKey,type:String,indexService:CatalogIndexService = .shared,catalogService:SQLCatalogService = .shared) async {
    guard server.online,server.allowsCatalogIndex(database) else {return}
    let generation=server.generation,revision=server.catalogIndexRevision
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
      guard generation==server.generation,server.online,server.catalogIndexRevision==revision,server.allowsCatalogIndex(database) else {return}
      guard !result.partial,!result.stoppedEarly,result.results.count==1,!result.results.contains(where:\.truncated) else {throw SQLFailure("Nesne yenilemesi kısmi geldi.")}
      let values=Array(result.results.first?.values ?? [])
      guard values.count<=30_000,values.allSatisfy({$0.count>=6 && $0[0].flatMap(Int.init).map {$0>0}==true && $0[0]==values.first?[0] && $0[1]==values.first?[1] && $0[2]==values.first?[2] && $0[1].map({!$0.isEmpty && $0.utf16.count<=128}) == true && $0[2].map({$0.utf16.count<=128}) == true && $0[3] != nil}) else {throw SQLFailure("Nesne yenileme yanıtı doğrulanamadı.")}
      let item=Catalog.rows(result).first
      let key=item.map {SchemaObjectKey(schema:$0.schema,name:$0.name,databaseTrigger:key.databaseTrigger)} ?? key
      let parentID=values.first?[5].flatMap(Int.init) ?? 0
      if folder != .triggers {
        let rows=item.map {[$0]} ?? []
        try await indexService.replaceTarget(profile:server.profile,database:database,name:key.schema+"."+key.name,folder:folder,items:rows)
        guard generation==server.generation,server.online,server.catalogIndexRevision==revision,server.allowsCatalogIndex(database) else {return}
        let symbol=item.map {CatalogSymbol(schema:$0.schema,name:$0.name,columns:values.compactMap {$0[4]},kind:$0.detail)}
        let catalog=try await catalogService.replaceTarget(profile:server.profile,database:database,schema:key.schema,name:key.name,symbol:symbol)
        guard generation==server.generation,server.online,server.catalogIndexRevision==revision,server.allowsCatalogIndex(database) else {return}
        if let catalog {for document in state.documents where document.server === server && document.database==database {document.applyTargetedCatalog(catalog,database:database,generation:generation)}}
      }
      var queue=roots.filter {$0.server === server},visited=0
      while let node=queue.popLast() {
        visited+=1;if visited%200==0 {await Task.yield()}
        guard generation==server.generation,server.online,server.catalogIndexRevision==revision,server.allowsCatalogIndex(database) else {return}
        queue.append(contentsOf:node.children)
        guard node.database==database else {continue}
        if case .folder(let category)=node.kind,category==folder,node.loaded,
          folder != .triggers || values.isEmpty || (node.ownerObject?.item?.id ?? 0)==parentID {
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
      guard generation==server.generation,server.catalogIndexRevision==revision,server.allowsCatalogIndex(database) else {return}
      searchStatus.stringValue="Nesnenin yerel kataloğu yenilenemedi."
      searchStatus.toolTip=error.localizedDescription
    }
  }
  @objc func refreshChangedObjects(_ notification: Notification) {
    guard let doc=notification.object as? QueryDocument else {return}
    let changes=notification.userInfo?["changes"] as? [ModuleEditing.Change] ?? ModuleEditing.changes(doc.lastExecutedSQL ?? "")
    let database=notification.userInfo?["database"] as? String ?? doc.database
    let generation=notification.userInfo?["generation"] as? UUID ?? doc.server.generation
    Task {[weak self,weak doc] in
      guard let self,let doc,doc.server.generation==generation else {return}
      await refreshDDLChanges(changes,server:doc.server,database:database)
    }
  }
  func refreshDDLChanges(_ changes:[ModuleEditing.Change],server:ConnectedServer,database:String,indexService:CatalogIndexService = .shared,catalogService:SQLCatalogService = .shared) async {
    let generation=server.generation,revision=server.catalogIndexRevision
    for change in changes {
      let db=change.database ?? database
      guard server.generation==generation,server.catalogIndexRevision==revision,server.online else {return}
      guard server.allowsCatalogIndex(db) else {continue}
      var schema=change.schema,fallback:String?
      if schema == nil {
        do {
          var limits=Limits();limits.rows=2;limits.timeout=10
          let sql="-- StudioDDLDefaultSchema\nSELECT SCHEMA_NAME(),OBJECT_SCHEMA_NAME(OBJECT_ID("+SQL.literal(SQL.identifier(change.name))+"));"
          let output=try await server.catalog(sql,database:db,limits:limits)
          guard !output.partial,!output.stoppedEarly,output.results.count==1,let row=output.results.first?.values.first,row.count==2,let defaultSchema=row[0],!defaultSchema.isEmpty else {throw SQLFailure("Varsayılan şema doğrulanamadı.")}
          schema=row[1] ?? defaultSchema
          // A dropped unqualified name may have resolved through dbo rather
          // than the login's default schema. Re-read both candidate identities.
          if row[1]==nil,defaultSchema != "dbo" {fallback="dbo"}
        } catch {searchStatus.stringValue="DDL tamamlandı; varsayılan şema okunamadı.";searchStatus.toolTip=error.localizedDescription;continue}
      }
      guard server.generation==generation,server.catalogIndexRevision==revision,let schema else {return}
      await refreshComparedObject(server:server,database:db,key:.init(schema:schema,name:change.name,databaseTrigger:change.databaseTrigger),type:change.type,indexService:indexService,catalogService:catalogService)
      if let fallback,server.generation==generation,server.catalogIndexRevision==revision {await refreshComparedObject(server:server,database:db,key:.init(schema:fallback,name:change.name,databaseTrigger:change.databaseTrigger),type:change.type,indexService:indexService,catalogService:catalogService)}
    }
  }
  @objc func explorerConnectionChanged(_ notification:Notification) {
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
  @objc func catalogIndexUpdated(_ notification: Notification) {
    // Editor snapshots do not change Explorer metadata or index status.
    if notification.name.rawValue == "sqlCatalogChanged" { return }
    if notification.userInfo?["definitionsOnly"] as? Bool == true {
      if notification.userInfo?["definitionProgress"] as? Bool != true {lastIndexStatusCheck = .distantPast;updateIndexStatus()}
      for row in 0..<outline.numberOfRows {
        if let node=outline.item(atRow:row) as? TreeNode,case .database=node.kind,node.server === notification.object as? ConnectedServer,node.database==notification.userInfo?["database"] as? String {reloadExplorer(item:node)}
      }
      return
    }
    lastIndexStatusCheck = .distantPast; updateIndexStatus()
    for row in 0..<outline.numberOfRows {
      if let node=outline.item(atRow:row) as? TreeNode,case .database=node.kind {reloadExplorer(item:node)}
    }
    if let server = notification.object as? ConnectedServer, let db = notification.userInfo?["database"] as? String, notification.userInfo?["error"] == nil,notification.userInfo?["excluded"] as? Bool != true,server.allowsCatalogIndex(db) {
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
  func refreshIndexInBackground(server: ConnectedServer, database: String, force: Bool = false) {
    guard server.online,server.allowsCatalogIndex(database), !server.indexingDatabases.contains(database) else {return}
    let revision=server.catalogIndexRevision
    server.definitionIndex.refresh(force:force,database:database)
    server.indexingDatabases.insert(database)
    NotificationCenter.default.post(name:.init("catalogIndexUpdated"),object:server,userInfo:["database":database])
    lastIndexStatusCheck = .distantPast; updateIndexStatus()
    Task {
      defer {
        if server.catalogIndexRevision==revision,server.allowsCatalogIndex(database) {
          server.indexingDatabases.remove(database)
          NotificationCenter.default.post(name:.init("catalogIndexUpdated"),object:server,userInfo:["database":database])
          lastIndexStatusCheck = .distantPast; updateIndexStatus()
        }
      }
      do {
        let key = CatalogDiskIndex.scope(profile: server.profile, database: database)
        let before = try await CatalogDiskIndex.shared.status(scope: key)
        let after = try await CatalogIndexService.shared.refresh(profile: server.profile, password: server.password, database: database, force: force)
        guard server.catalogIndexRevision==revision,server.allowsCatalogIndex(database) else {return}
        _ = try await SQLCatalogService.shared.refresh(profile:server.profile,password:server.password,database:database,force:force)
        guard server.catalogIndexRevision==revision,server.allowsCatalogIndex(database) else {return}
        if force && (searchScope ?? selected ?? roots.first)?.server === server {
          searchStatus.stringValue = "\(database) · Disk indeksi hazır · \(after.count) nesne"
        }
        server.indexErrors.removeValue(forKey:database)
        if !force && before?.synchronizedAt == after.synchronizedAt { return }
        NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: server, userInfo: ["database": database])
      } catch {
        guard !(error is CancellationError),server.catalogIndexRevision==revision,server.allowsCatalogIndex(database) else {return}
        server.indexErrors[database]=error.localizedDescription
        if force { searchStatus.stringValue = "Disk indeksi eşitlenemedi"; searchStatus.toolTip = error.localizedDescription }
        NotificationCenter.default.post(name: .init("catalogIndexUpdated"), object: server, userInfo: ["database": database, "error": error.localizedDescription])
      }
    }
  }
  func updateIndexStatus() {
    guard let scope = (showingSearch ? searchScope : selected) ?? searchScope ?? roots.first else { indexStatus.toolTip = "İndeks durumu için bağlantı seçin"; return }
    let databases = searchDatabases(scope), key = scope.server.id.uuidString + databases.joined(separator:"|")
    guard key != lastIndexStatusScope || Date().timeIntervalSince(lastIndexStatusCheck) > 2 else { return }
    lastIndexStatusScope = key; lastIndexStatusCheck = Date(); indexStatusTask?.cancel()
    let server = scope.server
    indexStatusTask = Task { [weak self] in
      var lines: [String] = [], ready = 0
      var definitions:[String:DefinitionIndexPresentation]=[:]
      for db in databases {
        guard !Task.isCancelled else { return }
        do {
          let definition=try await server.definitionIndex.presentation(database:db)
          definitions[db]=definition
          lines.append("\(db): nesne içerikleri · "+definition.detail)
          let objects = try await server.catalogIndexStatus(database:db)
          let columnDate = try await server.completionIndexDate(database:db)
          if let objects {
            ready += 1
            let stamp = objects.synchronizedAt.formatted(date:.numeric,time:.shortened)
            let columnStamp = columnDate?.formatted(date:.numeric,time:.shortened) ?? "yok"
            lines.append("\(db): nesne indeksi \(objects.count) nesne · \(stamp)\nKolon indeksi: \(columnStamp) · \(columnDate.map { Date().timeIntervalSince($0) < 300 } == true ? "güncel" : "yenileme gerekli")")
          } else { lines.append("\(db): indeks henüz hazır değil / hazırlanıyor") }
        } catch { lines.append("\(db): indeks okunamadı · \(error.localizedDescription)") }
      }
      guard !Task.isCancelled, let self else { return }
      for db in databases {
        if let error = server.indexErrors[db] { lines.append("\(db): eşitleme başarısız · \(error)") }
        else if server.indexingDatabases.contains(db) { lines.append("\(db): indeks hazırlanıyor…") }
      }
      if let doc = state.active, doc.server === server, let error = doc.catalogError { lines.append("Editör doğrulaması kapalı: \(error)") }
      let failed = databases.contains(where:{server.indexErrors[$0] != nil || definitions[$0]?.warning == true})
      let building = !server.indexingDatabases.isDisjoint(with:databases) || definitions.values.contains(where: \.building)
      indexStatus.image=NSImage(systemSymbolName:failed ? "exclamationmark.triangle" : building ? "arrow.triangle.2.circlepath" : ready == databases.count && ready > 0 ? "externaldrive.badge.checkmark":"externaldrive",accessibilityDescription:nil)
      indexStatus.contentTintColor=failed ? .systemOrange : building ? StudioTheme.accent : ready > 0 ? .systemGreen:.secondaryLabelColor
      for db in databases {
        indexDetailsByDatabase[server.id.uuidString+"|"+db] = lines.filter {$0.hasPrefix(db+":")}.joined(separator:"\n")
      }
      indexStatus.toolTip = lines.joined(separator:"\n\n")
      indexStatus.setAccessibilityLabel(indexStatus.toolTip ?? "Yerel indeks")
      let databaseSet=Set(databases)
      for row in 0..<outline.numberOfRows {
        if let node=outline.item(atRow:row) as? TreeNode,case .database=node.kind,node.server === server,databaseSet.contains(node.database) {reloadExplorer(item:node)}
      }
    }
  }
}
