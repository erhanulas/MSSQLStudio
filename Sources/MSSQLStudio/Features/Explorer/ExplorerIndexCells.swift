import AppKit
import SQLServerKit

extension WorkbenchController {
  func indexCell(for node:TreeNode)->NSView {
    let cell=ExplorerIndexCell();cell.outline=outline
    if case .database = node.kind {
      let server=node.server,database=node.database
      explorerIndexStatuses.request(server:server,database:database) { [weak self,weak server] in
        guard let self,let server,let current=explorerTree.databaseNode(server:server,database:database) else {return}
        reloadExplorer(item:current)
      }
      let snapshot=explorerIndexStatuses.snapshot(server:server,database:database)
      let activity=node.server.definitionIndex.activities[node.database]
      for content in [false,true] {
        let badge=DatabaseIndexButton();badge.node=node;badge.target=self;badge.action=#selector(showDatabaseIndex(_:))
        let enabled = !content || node.server.allowsDefinitionIndex(node.database)
        let ready = content ? snapshot?.definitionsReady == true : snapshot?.objectsReady == true
        let failed = content ? activity?.phase == .failed || snapshot?.definitionsWarning == true : node.server.indexErrors[node.database] != nil
        let building = content ? activity?.phase == .building || activity?.phase == .waiting : node.server.indexingDatabases.contains(node.database)
        let title = content ? "Nesne içerikleri" : "Nesne indeksi"
        badge.image=NSImage(systemSymbolName:content ? "doc.text.magnifyingglass":"square.stack.3d.up",accessibilityDescription:nil)
        badge.contentTintColor = !enabled ? StudioTheme.muted : failed ? .systemOrange : building ? StudioTheme.accent : ready ? .systemGreen : StudioTheme.muted
        badge.bezelStyle = .inline;badge.isBordered=false;badge.imagePosition = .imageOnly
        badge.toolTip=node.database + " · " + title + " · " + (enabled ? failed ? "Hata" : building ? "Hazırlanıyor" : ready ? "Hazır" : "Durumu göster" : "Kapalı")
        if let error=snapshot?.readError {badge.toolTip=(badge.toolTip ?? "")+"\n"+error}
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

/// The tree scrolls long object names, while its native index cells stay at the viewport edge.
@MainActor final class ExplorerIndexCell:NSTableCellView {
  weak var outline:NSOutlineView?
  override init(frame frameRect:NSRect) {
    super.init(frame:frameRect)
    clipsToBounds=true
  }
  required init?(coder:NSCoder) {
    super.init(coder:coder)
    clipsToBounds=true
  }
  override var frame:NSRect {
    get {super.frame}
    set {
      var value=newValue
      // AppKit can propose the row width during reattachment. The opaque pinned
      // surface must stay inside its own column rather than cover object names.
      if let outline,let column=outline.tableColumns.first(where: {$0.identifier.rawValue == "indexes"}) {
        value.size.width=column.width
      }
      if let outline,let parent=superview {
        let viewport=outline.visibleRect.intersection(outline.bounds)
        if !viewport.isEmpty {
          let visible=parent.convert(viewport,from:outline)
          value.origin.x=max(visible.minX,visible.maxX-value.width)
        }
      }
      super.frame=value
    }
  }
  override func setFrameSize(_ newSize:NSSize) {
    var size=newSize
    if let outline,let column=outline.tableColumns.first(where: {$0.identifier.rawValue == "indexes"}) {
      size.width=column.width
    }
    super.setFrameSize(size)
  }
  func pinToViewport() {let current=frame;frame=current;needsDisplay=true}
  override func draw(_ dirtyRect:NSRect) {
    // Empty index cells must remain transparent so connection/folder colors
    // and the native row selection continue across the complete row.
    guard !subviews.isEmpty else {super.draw(dirtyRect);return}
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect:dirtyRect.intersection(bounds)).addClip()
    StudioTheme.explorerCanvas.setFill()
    bounds.fill()
    if let row=superview as? NSTableRowView {
      let region=row.convert(bounds,from:self)
      let origin=convert(NSPoint.zero,from:row)
      let unit=convert(NSPoint(x:1,y:1),from:row)
      let transform=NSAffineTransform()
      transform.translateX(by:origin.x,yBy:origin.y)
      transform.scaleX(by:unit.x-origin.x,yBy:unit.y-origin.y)
      transform.concat()
      row.drawBackground(in:region)
      if row.isSelected {row.drawSelection(in:region)}
    }
    NSGraphicsContext.restoreGraphicsState()
    super.draw(dirtyRect)
  }
}

@MainActor final class ExplorerScrollView:NSScrollView {
  private var sizing=false
  private var pinning=false
  var requiredObjectWidth:CGFloat=40
  override func tile() {
    super.tile()
    guard !sizing,let table=documentView as? NSOutlineView,table.tableColumns.count==2,contentView.bounds.width>0 else {return}
    sizing=true;defer {sizing=false}
    let width=contentView.bounds.width
    table.tableColumns[0].width=max(requiredObjectWidth,width-56-table.intercellSpacing.width*2)
    table.setFrameSize(NSSize(width:max(width,table.tableColumns[0].width+56+table.intercellSpacing.width*2),height:table.frame.height))
    table.tile()
    pinIndexCells(table)
  }
  override func reflectScrolledClipView(_ clipView:NSClipView) {
    super.reflectScrolledClipView(clipView)
    if let table=documentView as? NSOutlineView {pinIndexCells(table)}
  }
  private func pinIndexCells(_ table:NSOutlineView) {
    guard !pinning,table.tableColumns.count>1 else {return}
    pinning=true;defer {pinning=false}
    table.enumerateAvailableRowViews {_,row in
      (table.view(atColumn:1,row:row,makeIfNecessary:true) as? ExplorerIndexCell)?.pinToViewport()
    }
  }
}
