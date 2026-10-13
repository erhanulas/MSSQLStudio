import AppKit
import SQLServerKit
import SwiftUI

struct OfflineObjectDefinitionView: View {
  let value: IndexedObjectDefinition
  let database: String
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Çevrimdışı tanım · Salt okunur", systemImage: "externaldrive").font(.headline)
      Text(
        database + " · " + value.item.qualified + " · Son okuma: "
          + value.fetchedAt.formatted(date: .numeric, time: .shortened)
      ).font(.caption).foregroundStyle(.secondary)
      Text("Sunucudaki güncel tanım farklı olabilir. Bu önizleme SQL çalıştırmaz.").font(.caption)
        .foregroundStyle(.secondary)
      SQLReadOnlyPreview(sql: value.sql)
    }.padding(16).frame(minWidth: 640, minHeight: 440).studioPanel()
  }
}
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
    Task { [weak self] in
      guard let self else { return }
      do {
        let value = try await node.server.definitionIndex.cached(
          database: node.database, id: item.id)
        present(
          OfflineObjectDefinitionView(value: value, database: node.database),
          title: "Çevrimdışı · " + item.name, width: 960, height: 680)
      } catch { state.showError(error.localizedDescription) }
    }
  }
}
