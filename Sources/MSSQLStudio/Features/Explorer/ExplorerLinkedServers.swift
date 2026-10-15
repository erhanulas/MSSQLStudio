import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

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
      } catch is CancellationError {node.loaded=false
      } catch {
        guard generation == node.server.generation, node.server.metadata === metadata else {return}
        node.error=error.localizedDescription; node.loaded=true
        node.children=[linkedNode("Metadata alınamadı — Yenile ile tekrar deneyin",kind:.detail,branch:.detail,parent:node,loaded:true)]
      }
    }
  }
  func linkedMenu(for node: TreeNode) -> NSMenu {
    let menu=StudioMenu()
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
