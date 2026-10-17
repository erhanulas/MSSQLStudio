import AppKit
import SQLServerKit

extension WorkbenchController {
  func revealExplorerObject(_ parts:[String],document:QueryDocument,targetServer:ConnectedServer?=nil,targetDatabase:String?=nil) {
    guard !parts.isEmpty,parts.count<=3 else {state.showError("Bu nesne başvurusu Explorer kapsamında değil.");return}
    let server=targetServer ?? document.server,database=parts.count==3 ? parts[0]:(targetDatabase ?? document.database),generation=server.generation
    let sourceServer=document.server
    let name=parts.last!,schema=parts.count>1 ? parts[parts.count-2]:nil
    guard server.allowsCatalogIndex(database) else {state.showError("Veritabanı Explorer’da görünür değil.");return}
    explorerRevealTask?.cancel();let request=UUID();explorerRevealID=request
    let sourceDB=document.database,sourceSQL=document.sql,selection=document.selectedRange
    explorerRevealTask=Task { [weak self,weak document] in
      guard let self,let document else {return}
      defer {if explorerRevealID==request {explorerRevealTask=nil}}
      @MainActor func current()->Bool {!Task.isCancelled && explorerRevealID==request && document.database==sourceDB && document.sql==sourceSQL && document.selectedRange==selection && state.documents.contains(where:{$0 === document}) && document.server === sourceServer && server.generation==generation}
      do {
        let previousRoot=explorerTree.roots.first {$0.server === server}
        _=explorerTree.synchronizeServers(state.servers)
        if previousRoot !== explorerTree.roots.first(where:{$0.server === server}) {reloadExplorer()}
        guard let db=explorerTree.databaseNode(server:server,database:database) else {throw SQLFailure("Veritabanı Explorer’da görünür değil; bağlantı ayarlarından ekleyin.")}
        var folders:[TreeNode]=[]
        for node in db.children {
          if case .group=node.kind {folders.append(contentsOf:node.children)} else {folders.append(node)}
        }
        let matches=folders.flatMap {$0.children}.filter {node in
          guard let item=node.item else {return false}
          return item.name.caseInsensitiveCompare(name) == .orderedSame && (schema == nil || item.schema.caseInsensitiveCompare(schema!) == .orderedSame)
        }
        let loaded=matches.first {$0.item?.schema.caseInsensitiveCompare(schema ?? "dbo") == .orderedSame} ?? (matches.count==1 ? matches.first:nil)
        var symbol:CatalogSymbol?
        var resolvedFolder:Folder?
        if let loaded,let item=loaded.item,case .object(let folder)=loaded.kind {
          symbol=CatalogSymbol(schema:item.schema,name:item.name,columns:[],kind:item.detail);resolvedFolder=folder
        }
        if symbol == nil,!server.online {
          var items:[CatalogItem]=[]
          for folder in [Folder.tables,.views,.procedures,.functions,.synonyms,.triggers] {
            items += try await server.definitionIndex.items(database:database,folder:folder).filter {
              $0.name.caseInsensitiveCompare(name) == .orderedSame && (schema == nil || $0.schema.caseInsensitiveCompare(schema!) == .orderedSame)
            }
          }
          if let item=items.first(where:{$0.schema=="dbo"}) ?? (items.count==1 ? items.first:nil) {symbol=CatalogSymbol(schema:item.schema,name:item.name,columns:[],kind:item.detail)}
        }
        if symbol == nil,server.online {
          var limits=Limits();limits.rows=3;limits.timeout=10
          let result=try await server.catalog("SELECT TOP(3) object_id,name,SCHEMA_NAME(schema_id),type_desc FROM sys.objects WHERE name=\(SQL.literal(name)) AND type IN ('U','V','P','PC','FN','IF','TF','FS','FT','SN','TR','TA')"+(schema.map {" AND SCHEMA_NAME(schema_id)=\(SQL.literal($0))"} ?? "")+" ORDER BY CASE WHEN SCHEMA_NAME(schema_id)=N'dbo' THEN 0 ELSE 1 END,object_id;",database:database,limits:limits)
          let rows=Catalog.rows(result)
          if let item=rows.first(where:{$0.schema=="dbo"}) ?? (rows.count==1 ? rows.first:nil) {symbol=CatalogSymbol(schema:item.schema,name:item.name,columns:[],kind:item.detail)}
        }
        guard current() else {return}
        guard let symbol else {throw SQLFailure("Nesne bulunamadı veya adı belirsiz. Şema adıyla yeniden deneyin; çevrimdışıyken yerel kolon indeksi gerekir.")}
        let folder:Folder=resolvedFolder ?? (symbol.kind=="USER_TABLE" ? .tables:symbol.kind=="VIEW" ? .views:symbol.kind.contains("PROCEDURE") ? .procedures:symbol.kind=="SYNONYM" ? .synonyms:symbol.kind.contains("TRIGGER") ? .triggers:.functions)
        var pending=db.children,branch:TreeNode?
        while let candidate=pending.popLast() {
          if case .folder(let value)=candidate.kind,value==folder {branch=candidate;break}
          if case .group=candidate.kind {pending.append(contentsOf:candidate.children)}
        }
        guard let branch else {throw SQLFailure("Nesne klasörü Explorer’da bulunamadı.")}
        explorerSearch.stringValue="";filterExplorer()
        showExplorerSearch(false)
        if sidebar.isCollapsed {toggleExplorer()}
        var ancestors:[TreeNode]=[];var parent:TreeNode?=branch
        while let node=parent {ancestors.append(node);parent=node.parent}
        for node in ancestors.reversed() {expansionState[node.persistenceKey]=true;outline.expandItem(node)}
        let hasObject=branch.children.contains {$0.item?.name.caseInsensitiveCompare(symbol.name) == .orderedSame && $0.item?.schema.caseInsensitiveCompare(symbol.schema) == .orderedSame}
        if branch.error != nil || branch.loaded && !hasObject && server.online {
          branch.loaded=false;branch.children=[];branch.error=nil
        }
        if !branch.loaded {load(branch)}
        for _ in 0..<1500 where branch.loading {try await Task.sleep(for:.milliseconds(10));guard current() else {return}}
        guard current() else {return}
        guard !branch.loading else {throw SQLFailure("Nesne listesi hâlâ yükleniyor; daha sonra tekrar deneyin.")}
        guard let node=branch.children.first(where:{$0.item?.name.caseInsensitiveCompare(symbol.name) == .orderedSame && $0.item?.schema.caseInsensitiveCompare(symbol.schema) == .orderedSame}) else {throw SQLFailure(branch.error ?? "Nesne Explorer’da bulunamadı; Yenile ile tekrar deneyin.")}
        // Loading may finish after a search-tab change; reveal in the real tree.
        showExplorerSearch(false)
        // A list reload can restore an old collapsed state. Expand the current
        // branch again after loading before asking AppKit for its visible row.
        for ancestor in ancestors.reversed() {expansionState[ancestor.persistenceKey]=true;outline.expandItem(ancestor)}
        outline.layoutSubtreeIfNeeded()
        let row=outline.row(forItem:node)
        guard row>=0 else {throw SQLFailure("Nesne satırı görüntülenemedi.")}
        outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
        rebuildSearchScopes(selecting:db)
        changeSearchScope()
        explorer.view.layoutSubtreeIfNeeded()
        if let scroll=outline.enclosingScrollView {
          let clip=scroll.contentView,rect=outline.rect(ofRow:row)
          var proposed=clip.bounds
          proposed.origin.y=rect.midY-proposed.height/2
          clip.scroll(to:clip.constrainBoundsRect(proposed).origin)
          scroll.reflectScrolledClipView(clip)
        }
        view.window?.makeKeyAndOrderFront(nil);view.window?.makeFirstResponder(outline)
      } catch {if current() {state.showError(error.localizedDescription)}}
    }
  }
}
