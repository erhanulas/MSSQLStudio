import AppKit

@MainActor enum StudioWindowPickerStyle {
  static let rowHeight:CGFloat=84
  static let rowGap:CGFloat=8
  static let chromeHeight:CGFloat=160
  static func tint(_ entry:StudioWindowSwitcherView.Entry)->NSColor {
    switch entry.symbol {
    case "waveform.path.ecg":return StudioTheme.success
    case "list.bullet.rectangle","star":return StudioTheme.warning
    default:return StudioTheme.accent
    }
  }
}

/// Native reusable cards; all decoration is vector drawing and never captures window contents.
@MainActor final class StudioWindowSwitcherView:NSView,NSTableViewDataSource,NSTableViewDelegate {
  struct Entry {
    let title,context,type,symbol,status:String
  }
  let entries:[Entry]
  let table=NSTableView()
  private let selectedTitle=NSTextField(labelWithString:"")
  private let count=StudioWindowPickerPill()
  private let select:(Int)->Void
  private let accept:(Int)->Void
  private var updating=false
  init(entries:[Entry],selected:Int,select:@escaping(Int)->Void,accept:@escaping(Int)->Void) {
    self.entries=entries;self.select=select;self.accept=accept
    super.init(frame:.zero)
    wantsLayer=true;layer?.cornerRadius=StudioMetrics.cardRadius;layer?.masksToBounds=true
    layer?.backgroundColor=StudioTheme.panel.cgColor;layer?.borderWidth=1;layer?.borderColor=StudioTheme.border.cgColor
    setAccessibilityIdentifier("studioWindowSwitcher")
    let emblem=StudioWindowPickerEmblem()
    emblem.configure(symbol:"rectangle.stack.fill",tint:StudioTheme.accent)
    let heading=NSTextField(labelWithString:"Pencereler")
    heading.font = .systemFont(ofSize:StudioMetrics.headingFont,weight:.semibold);heading.textColor=StudioTheme.text
    let subtitle=NSTextField(labelWithString:"Açık çalışma alanları ve araçlar")
    subtitle.font = .systemFont(ofSize:StudioMetrics.detailFont);subtitle.textColor=StudioTheme.muted
    let headings=NSStackView(views:[heading,subtitle]);headings.orientation = .vertical;headings.alignment = .leading;headings.spacing=4
    count.configure(text:"\(entries.count) pencere",tint:StudioTheme.accent)
    let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
    scroll.drawsBackground=false;table.backgroundColor=StudioTheme.panel
    table.headerView=nil;table.rowHeight=StudioWindowPickerStyle.rowHeight
    table.intercellSpacing=NSSize(width:0,height:StudioWindowPickerStyle.rowGap)
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    let column=NSTableColumn(identifier:.init("window"));column.width=560;table.addTableColumn(column)
    table.allowsMultipleSelection=false;table.allowsEmptySelection=false
    table.selectionHighlightStyle = .regular;table.dataSource=self;table.delegate=self
    table.target=self;table.action=#selector(clickedRow)
    table.setAccessibilityIdentifier("studioWindowSwitcherList")
    selectedTitle.font = .systemFont(ofSize:StudioMetrics.detailFont,weight:.medium);selectedTitle.textColor=StudioTheme.muted
    selectedTitle.lineBreakMode = .byTruncatingTail
    let hints=NSStackView(views:[hint(keys:"⌃",text:"bırak ve geç"),hint(keys:"Tab",text:"ilerle"),hint(keys:"↑ ↓",text:"seç"),hint(keys:"esc",text:"vazgeç")])
    hints.orientation = .horizontal;hints.spacing=16
    for view in [emblem,headings,count,scroll,selectedTitle,hints] {view.translatesAutoresizingMaskIntoConstraints=false;addSubview(view)}
    NSLayoutConstraint.activate([
      emblem.leadingAnchor.constraint(equalTo:leadingAnchor,constant:20),emblem.topAnchor.constraint(equalTo:topAnchor,constant:16),emblem.widthAnchor.constraint(equalToConstant:40),emblem.heightAnchor.constraint(equalToConstant:40),
      headings.leadingAnchor.constraint(equalTo:emblem.trailingAnchor,constant:12),headings.centerYAnchor.constraint(equalTo:emblem.centerYAnchor),headings.trailingAnchor.constraint(lessThanOrEqualTo:count.leadingAnchor,constant:-12),
      count.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-20),count.centerYAnchor.constraint(equalTo:emblem.centerYAnchor),
      scroll.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),scroll.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),
      scroll.topAnchor.constraint(equalTo:emblem.bottomAnchor,constant:16),scroll.bottomAnchor.constraint(equalTo:selectedTitle.topAnchor,constant:-12),
      selectedTitle.leadingAnchor.constraint(equalTo:leadingAnchor,constant:20),selectedTitle.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-20),
      selectedTitle.bottomAnchor.constraint(equalTo:hints.topAnchor,constant:-8),
      hints.leadingAnchor.constraint(equalTo:leadingAnchor,constant:20),hints.trailingAnchor.constraint(lessThanOrEqualTo:trailingAnchor,constant:-16),hints.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-16)
    ])
    updating=true;table.reloadData();updateSelection(selected,reveal:true)
  }
  required init?(coder:NSCoder) {fatalError()}
  private func hint(keys:String,text:String)->NSView {
    let key=StudioWindowPickerPill();key.configure(text:keys,tint:StudioTheme.muted)
    let label=NSTextField(labelWithString:text);label.font = .systemFont(ofSize:10);label.textColor=StudioTheme.muted
    let stack=NSStackView(views:[key,label]);stack.orientation = .horizontal;stack.spacing=4;return stack
  }
  func numberOfRows(in tableView:NSTableView)->Int {entries.count}
  func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView? {StudioWindowSwitcherRow()}
  func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView? {
    guard entries.indices.contains(row) else {return nil}
    let id=NSUserInterfaceItemIdentifier("windowCell")
    let cell=(tableView.makeView(withIdentifier:id,owner:self) as? StudioWindowSwitcherCell) ?? StudioWindowSwitcherCell()
    cell.identifier=id;cell.show(entries[row]);cell.chosen=tableView.selectedRowIndexes.contains(row);return cell
  }
  func tableViewSelectionDidChange(_ notification:Notification) {
    if !updating,table.selectedRow>=0 {select(table.selectedRow)}
  }
  func updateSelection(_ index:Int,reveal:Bool) {
    guard entries.indices.contains(index) else {return}
    updating=true;defer {updating=false}
    let entry=entries[index]
    selectedTitle.stringValue="Geçiş yapılacak: "+entry.title;selectedTitle.toolTip=entry.title+" · "+entry.context
    table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)
    table.enumerateAvailableRowViews {_,row in
      (self.table.view(atColumn:0,row:row,makeIfNecessary:false) as? StudioWindowSwitcherCell)?.chosen=row==index
    }
    if reveal {table.scrollRowToVisible(index)}
  }
  @objc private func clickedRow() {if table.clickedRow>=0 {accept(table.clickedRow)}}
}

@MainActor private final class StudioWindowSwitcherCell:NSTableCellView {
  private let icon=StudioWindowPickerEmblem()
  private let kind=NSTextField(labelWithString:"")
  private let title=NSTextField(wrappingLabelWithString:"")
  private let context=NSTextField(labelWithString:"")
  private let status=StudioWindowPickerPill()
  private let open=NSTextField(labelWithString:"↩  Aç")
  var chosen=false {didSet {open.alphaValue=chosen ? 1:0;open.setAccessibilityElement(chosen)}}
  override init(frame:NSRect) {
    super.init(frame:frame)
    title.font = .systemFont(ofSize:13,weight:.semibold);title.textColor=StudioTheme.text;title.maximumNumberOfLines=2
    context.font = .systemFont(ofSize:StudioMetrics.detailFont);context.textColor=StudioTheme.muted;context.lineBreakMode = .byTruncatingTail
    kind.font = .systemFont(ofSize:10,weight:.semibold)
    open.font = .systemFont(ofSize:11,weight:.semibold);open.textColor=StudioTheme.accent;open.alignment = .right
    let labels=NSStackView(views:[kind,title,context]);labels.orientation = .vertical;labels.alignment = .leading;labels.spacing=4
    let trailing=NSStackView(views:[status,open]);trailing.orientation = .vertical;trailing.alignment = .trailing;trailing.spacing=8
    for view in [icon,labels,trailing] {view.translatesAutoresizingMaskIntoConstraints=false;addSubview(view)}
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),icon.centerYAnchor.constraint(equalTo:centerYAnchor),icon.widthAnchor.constraint(equalToConstant:44),icon.heightAnchor.constraint(equalToConstant:44),
      labels.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:12),labels.trailingAnchor.constraint(equalTo:trailing.leadingAnchor,constant:-12),labels.centerYAnchor.constraint(equalTo:centerYAnchor),
      trailing.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),trailing.centerYAnchor.constraint(equalTo:centerYAnchor),trailing.widthAnchor.constraint(equalToConstant:84),
      title.widthAnchor.constraint(equalTo:labels.widthAnchor),context.widthAnchor.constraint(equalTo:labels.widthAnchor)
    ])
    textField=title
  }
  required init?(coder:NSCoder) {fatalError()}
  func show(_ entry:StudioWindowSwitcherView.Entry) {
    let tint=StudioWindowPickerStyle.tint(entry)
    title.stringValue=entry.title;context.stringValue=entry.context;kind.stringValue=entry.type;kind.textColor=tint
    status.configure(text:entry.status,tint:entry.status=="Şu an açık" ? StudioTheme.success:StudioTheme.muted)
    icon.configure(symbol:entry.symbol,tint:tint)
    toolTip=entry.title+"\n"+entry.context+" · "+entry.status
    setAccessibilityLabel(entry.title+", "+entry.context+", "+entry.status)
  }
}

@MainActor private final class StudioWindowPickerPill:NSView {
  private var text=""
  private var tint:NSColor = .labelColor
  func configure(text:String,tint:NSColor) {self.text=text;self.tint=tint;invalidateIntrinsicContentSize();needsDisplay=true;setAccessibilityElement(true);setAccessibilityRole(.staticText);setAccessibilityLabel(text)}
  override var intrinsicContentSize:NSSize {NSSize(width:ceil(text.size(withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.medium)]).width)+16,height:20)}
  override func hitTest(_ point:NSPoint)->NSView? {nil}
  override func draw(_ dirtyRect:NSRect) {
    let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:6,yRadius:6)
    tint.withAlphaComponent(0.09).setFill();shape.fill();tint.withAlphaComponent(0.18).setStroke();shape.stroke()
    let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:10,weight:.medium),.foregroundColor:tint]
    let size=text.size(withAttributes:attributes)
    text.draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attributes)
  }
}

@MainActor private final class StudioWindowPickerEmblem:NSView {
  private var image:NSImage?
  private var tint:NSColor = .labelColor
  func configure(symbol:String,tint:NSColor) {
    self.tint=tint
    image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[tint]))
    needsDisplay=true
  }
  override func hitTest(_ point:NSPoint)->NSView? {nil}
  override func draw(_ dirtyRect:NSRect) {
    let rect=bounds.insetBy(dx:0.5,dy:0.5),path=NSBezierPath(roundedRect:rect,xRadius:StudioMetrics.cardRadius,yRadius:StudioMetrics.cardRadius)
    let start=tint.blended(withFraction:0.86,of:StudioTheme.panel) ?? StudioTheme.selection
    let end=tint.blended(withFraction:0.96,of:StudioTheme.canvas) ?? StudioTheme.canvas
    NSGradient(starting:start,ending:end)?.draw(in:path,angle:90)
    tint.withAlphaComponent(0.2).setStroke();path.stroke()
    if let image {StudioSymbolDrawing.draw(image,in:bounds.insetBy(dx:10,dy:10))}
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
    let path=NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:1),xRadius:StudioMetrics.cardRadius,yRadius:StudioMetrics.cardRadius)
    (hovered ? StudioTheme.selection:StudioTheme.canvas).setFill();path.fill()
    StudioTheme.border.withAlphaComponent(0.7).setStroke();path.stroke()
  }
  override func drawSelection(in dirtyRect:NSRect) {
    let path=NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:1),xRadius:StudioMetrics.cardRadius,yRadius:StudioMetrics.cardRadius)
    NSGradient(starting:StudioTheme.selection,ending:StudioTheme.canvas)?.draw(in:path,angle:0)
    StudioTheme.accent.withAlphaComponent(0.8).setStroke();path.lineWidth=1;path.stroke()
  }
  override var isEmphasized:Bool {get {true} set {}}
}
