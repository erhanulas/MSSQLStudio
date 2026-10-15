import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  func serverTree(_ server:ConnectedServer) -> TreeNode {explorerTree.serverTree(server)}
  func load(_ node: TreeNode) {
    guard !node.loading, !node.loaded, node.server.online || node.server.catalogFixture != nil || node.server.allowsDefinitionIndex(node.database) else { return }
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
      let generation=node.server.generation
      do {
        let sql =
          node.item.map { Catalog.children(folder, object: $0.id) } ?? Catalog.objects(folder)
        let rows:[CatalogItem]
        if node.server.online || node.server.catalogFixture != nil {
          rows=Catalog.rows(try await node.server.catalog(sql,database:node.database))
        } else {
          guard [.tables,.views,.procedures,.functions,.triggers,.synonyms].contains(folder) else {throw SQLFailure("Bu ayrıntı çevrimdışı indeks kapsamında değil.")}
          rows=try await node.server.definitionIndex.items(database:node.database,folder:folder,parentID:node.item?.id)
        }
        guard generation==node.server.generation,!Task.isCancelled else {throw CancellationError()}
        node.children = rows.map { item in
          TreeNode(
            item.schema.isEmpty
              ? item.name + (folder == .triggers || item.detail.isEmpty ? "" : " (\(item.detail))")
              : "\(item.schema).\(item.name)", kind: .object(folder),
            server: node.server, database: node.database, item: item)
        }
        node.loaded = true
        node.error = nil
      } catch is CancellationError {
        node.loading=false;node.loaded=false
        reloadExplorer(item:node)
        return
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
}
