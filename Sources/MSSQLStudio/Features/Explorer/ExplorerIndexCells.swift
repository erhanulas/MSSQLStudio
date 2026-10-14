import AppKit
import SQLServerKit

extension WorkbenchController {
  func indexCell(for node:TreeNode)->NSView {
    let cell=NSTableCellView()
    if case .database = node.kind {
      let activity=node.server.definitionIndex.activities[node.database]
      for content in [false,true] {
        let badge=DatabaseIndexButton();badge.node=node;badge.target=self;badge.action=#selector(showDatabaseIndex(_:))
        let enabled = !content || node.server.allowsDefinitionIndex(node.database)
        let details=indexDetailsByDatabase[node.server.id.uuidString+"|"+node.database] ?? ""
        let ready = content ? details.contains("nesne içerikleri · Hazır") : details.contains("nesne indeksi")
        let failed = content ? activity?.phase == .failed || details.contains("nesne içerikleri · Kısmi indeks") : node.server.indexErrors[node.database] != nil
        let building = content ? activity?.phase == .building || activity?.phase == .waiting : node.server.indexingDatabases.contains(node.database)
        let title = content ? "Nesne içerikleri" : "Nesne indeksi"
        badge.image=NSImage(systemSymbolName:content ? "doc.text.magnifyingglass":"square.stack.3d.up",accessibilityDescription:nil)
        badge.contentTintColor = !enabled ? StudioTheme.muted : failed ? .systemOrange : building ? StudioTheme.accent : ready ? .systemGreen : StudioTheme.muted
        badge.bezelStyle = .inline;badge.isBordered=false;badge.imagePosition = .imageOnly
        badge.toolTip=node.database + " · " + title + " · " + (enabled ? failed ? "Hata" : building ? "Hazırlanıyor" : "Durumu göster" : "Kapalı")
        if content,let activity {badge.toolTip=(badge.toolTip ?? "")+" · \(activity.processed) / \(activity.total.map(String.init) ?? "…")"}
        badge.setAccessibilityLabel(badge.toolTip)
        badge.setAccessibilityIdentifier((content ? "databaseDefinitionIndex_":"databaseIndex_")+node.database)
        cell.addSubview(badge);badge.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([badge.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:content ? -2:-28),badge.centerYAnchor.constraint(equalTo:cell.centerYAnchor),badge.widthAnchor.constraint(equalToConstant:24),badge.heightAnchor.constraint(equalToConstant:24)])
      }
    }
    return cell
  }
}

@MainActor final class ExplorerScrollView:NSScrollView {
  private var sizing=false
  override func tile() {
    super.tile()
    guard !sizing,let table=documentView as? NSOutlineView,table.tableColumns.count==2,contentView.bounds.width>0 else {return}
    sizing=true;defer {sizing=false}
    let width=contentView.bounds.width
    table.tableColumns[0].width=max(40,width-56-table.intercellSpacing.width*2)
    table.setFrameSize(NSSize(width:width,height:table.frame.height))
    table.tile()
  }
}
