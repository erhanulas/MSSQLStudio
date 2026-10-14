import AppKit
import SQLServerKit
import SwiftUI

extension TreeNode {
  var supportsIndexedDefinition: Bool {
    guard linked == nil, case .object(let folder) = kind else { return false }
    return [Folder.tables, .views, .procedures, .functions, .triggers, .synonyms].contains(folder)
  }
}
extension WorkbenchController {
  @objc func showOfflineDefinitionAtContext() {
    guard let node = contextNode else { return }
    showOfflineObjectDefinition(node)
  }
  func showOfflineObjectDefinition(_ node: TreeNode) {
    guard let item = node.item else { return }
    let target=favoriteContextDocument
    let request=UUID();target?.offlinePreviewRequest=request
    Task { [weak self] in
      guard let self else { return }
      do {
        let value = try await node.server.definitionIndex.cached(
          database: node.database, id: item.id)
        guard target == nil || target?.offlinePreviewRequest == request else {return}
        let document=target ?? state.newQuery(server:node.server,database:node.database)
        guard state.documents.contains(where:{$0 === document}) else {return}
        document.offlinePreview=OfflineDefinitionPreview(server:node.server,database:node.database,value:value)
        document.changed?()

      } catch is CancellationError {}
      catch {if target == nil || target?.offlinePreviewRequest == request {state.showError(error.localizedDescription)}}
    }
  }
}
