import AppKit
import SQLServerKit
import SwiftUI

@MainActor private final class PlanNode: NSObject {
  let operation: PlanOperation
  var children: [PlanNode] = []
  init(_ operation: PlanOperation) { self.operation = operation }
}
@MainActor
final class PlanController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
  private let plan: ExecutionPlan
  private var roots: [PlanNode] = []
  private let tree = NSOutlineView()
  init(plan: ExecutionPlan) {
    self.plan = plan
    super.init(nibName: nil, bundle: nil)
    var stack: [PlanNode] = []
    for operation in plan.operations {
      let node = PlanNode(operation)
      while stack.count > operation.depth { stack.removeLast() }
      if let parent = stack.last { parent.children.append(node) } else { roots.append(node) }
      stack.append(node)
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func loadView() {
    view = NSView()
    tree.dataSource = self
    tree.delegate = self
    tree.style = .plain
    tree.rowHeight = 24
    tree.backgroundColor = StudioTheme.canvas
    tree.gridStyleMask = [.solidHorizontalGridLineMask]
    tree.gridColor = StudioTheme.resultBorder
    tree.usesAlternatingRowBackgroundColors = false
    for (id, title, width) in [
      ("operation", "Operator", 330.0), ("estimated", "Estimated Rows", 140.0),
      ("actual", "Actual Rows", 120.0), ("cost", "Subtree Cost", 130.0),
    ] {
      let column = NSTableColumn(identifier: .init(id))
      let header = FilterHeaderCell(textCell: title)
      header.showsFilter = false
      header.typeSymbol = id == "operation" ? "point.3.connected.trianglepath.dotted" : "number"
      column.headerCell = header
      column.title = title
      column.width = width
      tree.addTableColumn(column)
    }
    tree.outlineTableColumn = tree.tableColumns[0]
    let scroll = NSScrollView()
    scroll.documentView = tree
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay; scroll.borderType = .noBorder
    let label = NSTextField(
      labelWithString: plan.operations.isEmpty
        ? "SQL Server Execution Plan — Bu sorgu için operatör yok" : "SQL Server Execution Plan")
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    let button = StudioToolbarButton(symbol:"square.and.arrow.down",label:"Planı .sqlplan dosyasına kaydet",title:"Planı Kaydet",width:110)
    button.flat=true;button.target=self;button.action=#selector(save)
    let header = NSStackView(views: [label, NSView(), button])
    StudioTheme.surface(header)
    header.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
    let stack = NSStackView(views: [header, scroll])
    stack.orientation = .vertical
    stack.distribution = .fill
    stack.spacing = 0
    view.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: view.topAnchor),
      stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      header.widthAnchor.constraint(equalTo: stack.widthAnchor),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
    tree.reloadData()
    tree.expandItem(nil, expandChildren: true)
  }
  func outlineView(_ view: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    (item as? PlanNode)?.children.count ?? roots.count
  }
  func outlineView(_ view: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    ((item as? PlanNode)?.children ?? roots)[index]
  }
  func outlineView(_ view: NSOutlineView, isItemExpandable item: Any) -> Bool {
    !((item as? PlanNode)?.children.isEmpty ?? true)
  }
  func outlineView(_ view: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
    guard let node = item as? PlanNode else { return nil }
    let value: String
    switch column?.identifier.rawValue {
    case "estimated": value = node.operation.estimatedRows
    case "actual": value = node.operation.actualRows?.formatted() ?? "—"
    case "cost": value = node.operation.cost
    default: value = (node.operation.warnings.isEmpty ? "" : "⚠ ") + node.operation.physical
    }
    let text = NSTextField(labelWithString: value)
    text.font = StudioTheme.uiFont
    text.textColor = StudioTheme.text
    text.lineBreakMode = .byTruncatingTail
    if column?.identifier.rawValue != "operation" {text.alignment = .right}
    text.toolTip = ([node.operation.logical] + node.operation.warnings).joined(separator: "\n")
    return text
  }
  func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { StudioRowView() }
  @objc private func save() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Query.sqlplan"
    if panel.runModal() == .OK, let url = panel.url {
      do { try plan.xml.write(to: url, atomically: true, encoding: .utf8) } catch {
        NSAlert(error: error).runModal()
      }
    }
  }
}
