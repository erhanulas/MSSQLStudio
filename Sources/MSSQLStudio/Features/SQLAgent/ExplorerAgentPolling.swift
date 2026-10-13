import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  @objc func toggleAgentAutoRefresh() {agentAutoRefresh.toggle()}
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

