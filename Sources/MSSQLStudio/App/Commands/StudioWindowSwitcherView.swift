import AppKit

/// Native list layout keeps window names readable independently of hosted button sizing.
@MainActor final class StudioWindowSwitcherView:NSView,NSTableViewDataSource,NSTableViewDelegate {
  struct Entry {
    let title,context,type,symbol,status:String
  }
  let entries:[Entry]
  let table=NSTableView()
  private let selectedTitle=NSTextField(wrappingLabelWithString:"")
  private let selectedContext=NSTextField(labelWithString:"")
  private let select:(Int)->Void
  private let accept:(Int)->Void
  private var updating=false
  init(entries:[Entry],selected:Int,select:@escaping(Int)->Void,accept:@escaping(Int)->Void) {
    self.entries=entries;self.select=select;self.accept=accept
    super.init(frame:.zero)
    wantsLayer=true;layer?.cornerRadius=StudioMetrics.cardRadius;layer?.masksToBounds=true
    layer?.backgroundColor=StudioTheme.panel.cgColor;layer?.borderWidth=1;layer?.borderColor=StudioTheme.border.cgColor
    setAccessibilityIdentifier("studioWindowSwitcher")
    let heading=NSTextField(labelWithString:"Pencereler")
    heading.font = .systemFont(ofSize:16,weight:.semibold);heading.textColor=StudioTheme.text
    let count=NSTextField(labelWithString:"\(entries.count) açık pencere")
    count.font=StudioTheme.uiFont;count.textColor=StudioTheme.muted
    selectedTitle.font = .systemFont(ofSize:13,weight:.medium);selectedTitle.textColor=StudioTheme.text
    selectedTitle.maximumNumberOfLines=2
    selectedContext.font = .systemFont(ofSize:11);selectedContext.textColor=StudioTheme.muted
    selectedContext.lineBreakMode = .byTruncatingTail
    let header=NSStackView(views:[heading,selectedTitle,selectedContext]);header.orientation = .vertical;header.alignment = .leading;header.spacing=4
    let footer=NSTextField(labelWithString:"⌃ bırak / ↩ Aç     Tab / ⇧ Tab · İlerle     ↑ ↓ · Seç     esc · Vazgeç")
    footer.font = .systemFont(ofSize:11);footer.textColor=StudioTheme.muted
    let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
    scroll.drawsBackground=false;table.backgroundColor=StudioTheme.panel
    table.headerView=nil;table.rowHeight=72;table.intercellSpacing=NSSize(width:0,height:4)
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    let column=NSTableColumn(identifier:.init("window"));column.width=560;table.addTableColumn(column)
    table.allowsMultipleSelection=false;table.allowsEmptySelection=false
    table.selectionHighlightStyle = .regular;table.dataSource=self;table.delegate=self
    table.target=self;table.action=#selector(clickedRow)
    table.setAccessibilityIdentifier("studioWindowSwitcherList")
    for view in [header,count,scroll,footer] {view.translatesAutoresizingMaskIntoConstraints=false;addSubview(view)}
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo:leadingAnchor,constant:20),header.topAnchor.constraint(equalTo:topAnchor,constant:16),
      header.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-20),header.heightAnchor.constraint(equalToConstant:76),
      selectedTitle.widthAnchor.constraint(equalTo:header.widthAnchor),selectedContext.widthAnchor.constraint(equalTo:header.widthAnchor),
      count.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-20),count.topAnchor.constraint(equalTo:topAnchor,constant:19),
      scroll.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),scroll.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),
      scroll.topAnchor.constraint(equalTo:header.bottomAnchor,constant:12),scroll.bottomAnchor.constraint(equalTo:footer.topAnchor,constant:-12),
      footer.leadingAnchor.constraint(equalTo:leadingAnchor,constant:20),footer.trailingAnchor.constraint(lessThanOrEqualTo:trailingAnchor,constant:-16),footer.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-16)
    ])
    updating=true;table.reloadData();updateSelection(selected,reveal:true)
  }
  required init?(coder:NSCoder) {fatalError()}
  func numberOfRows(in tableView:NSTableView)->Int {entries.count}
  func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView? {StudioWindowSwitcherRow()}
  func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView? {
    guard entries.indices.contains(row) else {return nil}
    let id=NSUserInterfaceItemIdentifier("windowCell")
    let cell=(tableView.makeView(withIdentifier:id,owner:self) as? StudioWindowSwitcherCell) ?? StudioWindowSwitcherCell()
    cell.identifier=id;cell.show(entries[row]);return cell
  }
  func tableViewSelectionDidChange(_ notification:Notification) {
    if !updating,table.selectedRow>=0 {select(table.selectedRow)}
  }
  func updateSelection(_ index:Int,reveal:Bool) {
    guard entries.indices.contains(index) else {return}
    updating=true;defer {updating=false}
    let entry=entries[index]
    selectedTitle.stringValue=entry.title;selectedTitle.toolTip=entry.title
    selectedContext.stringValue=entry.context+" · "+entry.status;selectedContext.toolTip=selectedContext.stringValue
    table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)
    if reveal {table.scrollRowToVisible(index)}
  }
  @objc private func clickedRow() {if table.clickedRow>=0 {accept(table.clickedRow)}}
}

@MainActor private final class StudioWindowSwitcherCell:NSTableCellView {
  private let icon=NSImageView()
  private let title=NSTextField(wrappingLabelWithString:"")
  private let context=NSTextField(labelWithString:"")
  private let status=NSTextField(labelWithString:"")
  override init(frame:NSRect) {
    super.init(frame:frame)
    title.font = .systemFont(ofSize:13,weight:.semibold);title.textColor=StudioTheme.text;title.maximumNumberOfLines=2
    context.font = .systemFont(ofSize:11);context.textColor=StudioTheme.muted;context.lineBreakMode = .byTruncatingTail
    status.font = .systemFont(ofSize:10,weight:.medium);status.textColor=StudioTheme.muted
    let labels=NSStackView(views:[title,context]);labels.orientation = .vertical;labels.alignment = .leading;labels.spacing=4
    for view in [icon,labels,status] {view.translatesAutoresizingMaskIntoConstraints=false;addSubview(view)}
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),icon.centerYAnchor.constraint(equalTo:centerYAnchor),icon.widthAnchor.constraint(equalToConstant:32),icon.heightAnchor.constraint(equalToConstant:32),
      labels.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:12),labels.trailingAnchor.constraint(equalTo:status.leadingAnchor,constant:-12),labels.centerYAnchor.constraint(equalTo:centerYAnchor),
      status.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),status.centerYAnchor.constraint(equalTo:centerYAnchor),status.widthAnchor.constraint(equalToConstant:78),
      title.widthAnchor.constraint(equalTo:labels.widthAnchor),context.widthAnchor.constraint(equalTo:labels.widthAnchor)
    ])
    textField=title;imageView=icon
  }
  required init?(coder:NSCoder) {fatalError()}
  func show(_ entry:StudioWindowSwitcherView.Entry) {
    title.stringValue=entry.title;context.stringValue=entry.context;status.stringValue=entry.status
    let configuration=NSImage.SymbolConfiguration(pointSize:24,weight:.regular)
      .applying(.init(paletteColors:[StudioTheme.accent]))
    let image=NSImage(systemSymbolName:entry.symbol,accessibilityDescription:entry.type)?
      .withSymbolConfiguration(configuration)
    image?.isTemplate=false;icon.image=image
    toolTip=entry.title+"\n"+entry.context+" · "+entry.status
    setAccessibilityLabel(entry.title+", "+entry.context+", "+entry.status)
  }
}

@MainActor private final class StudioWindowSwitcherRow:NSTableRowView {
  private var hovered=false
  override func updateTrackingAreas() {
    for area in trackingAreas {removeTrackingArea(area)}
    super.updateTrackingAreas()
    addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self))
  }
  override func mouseEntered(with event:NSEvent) {hovered=true;needsDisplay=true}
  override func mouseExited(with event:NSEvent) {hovered=false;needsDisplay=true}
  override func drawBackground(in dirtyRect:NSRect) {
    if hovered,!isSelected {StudioTheme.selection.withAlphaComponent(0.45).setFill();NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:1),xRadius:8,yRadius:8).fill()}
  }
  override func drawSelection(in dirtyRect:NSRect) {
    let path=NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:1),xRadius:8,yRadius:8)
    StudioTheme.selection.setFill();path.fill();StudioTheme.accent.setStroke();path.lineWidth=1;path.stroke()
  }
  override var isEmphasized:Bool {get {true} set {}}
}
