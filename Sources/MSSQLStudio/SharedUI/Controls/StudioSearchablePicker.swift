import AppKit
import SwiftUI

/// Retains NSPopUpButton selection/target-action API; searching never changes selection.
@MainActor final class StudioSearchablePopUpButton:NSPopUpButton {
  private var helpText:String?
  override var toolTip:String? {
    get {helpText}
    set {helpText=newValue;super.toolTip=nil;StudioHoverHelp.shared.configureText(newValue,for:self)}
  }

  private let popup=NSPopover()
  private var hoverArea:NSTrackingArea?
  private var hovered=false
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea {removeTrackingArea(hoverArea)}
    let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self)
    addTrackingArea(area);hoverArea=area
  }
  override func mouseEntered(with event:NSEvent) {hovered=true;needsDisplay=true;StudioHoverHelp.shared.schedule(for:self)}
  override func mouseExited(with event:NSEvent) {hovered=false;needsDisplay=true;StudioHoverHelp.shared.hide(for:self)}
  var leadingSymbol:String? {didSet {needsDisplay=true}}
  override init(frame:NSRect = .zero,pullsDown:Bool = false) {super.init(frame:frame,pullsDown:pullsDown);font = .systemFont(ofSize:StudioMetrics.bodyFont);isBordered=false;setContentHuggingPriority(.required,for:.vertical);setContentCompressionResistancePriority(.required,for:.vertical)}
  required init?(coder:NSCoder) {super.init(coder:coder)}
  override var intrinsicContentSize:NSSize {
    let text=(titleOfSelectedItem ?? "") as NSString
    let width=text.size(withAttributes:[.font:NSFont.systemFont(ofSize:StudioMetrics.bodyFont)]).width
    return NSSize(width:min(280,max(120,width+(leadingSymbol == nil ? 36:56))),height:StudioMetrics.controlHeight)
  }
  static func choicesSize(_ values:[String],searching:Bool=false)->NSSize {
    let font=NSFont.systemFont(ofSize:StudioMetrics.bodyFont)
    let width=values.reduce(CGFloat(0)) {max($0,($1 as NSString).size(withAttributes:[.font:font]).width)}
    return NSSize(width:min(360,max(160,width+36)),height:min(360,max(44,CGFloat(values.count)*StudioMetrics.choiceRowHeight+12)+(searching ? 28:0)))
  }
  override func draw(_ dirtyRect:NSRect) {
    if isEnabled && hovered {
      StudioTheme.accent.withAlphaComponent(0.06).setFill()
      NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:StudioMetrics.controlRadius,yRadius:StudioMetrics.controlRadius).fill()
    }
    let color=isEnabled ? StudioTheme.text:StudioTheme.muted.withAlphaComponent(0.5)
    let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingMiddle
    let left:CGFloat=leadingSymbol == nil ? 8:28
    if let leadingSymbol,let image=NSImage(systemSymbolName:leadingSymbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[StudioTheme.accent])) {
      image.draw(in:NSRect(x:7,y:(bounds.height-16)/2,width:16,height:16))
    }
    NSAttributedString(string:titleOfSelectedItem ?? "",attributes:[.font:NSFont.systemFont(ofSize:StudioMetrics.bodyFont),.foregroundColor:color,.paragraphStyle:paragraph])
      .draw(in:NSRect(x:left,y:(bounds.height-17)/2,width:max(0,bounds.width-left-24),height:17))
    NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:9,weight:.medium))?
      .withSymbolConfiguration(.init(paletteColors:[StudioTheme.muted]))?.draw(in:NSRect(x:bounds.width-18,y:(bounds.height-10)/2,width:10,height:10))
    if window?.firstResponder === self {StudioTheme.accent.withAlphaComponent(0.6).setStroke();let path=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:5,yRadius:5);path.stroke()}
  }

  private var choicesRevision=UUID()
  var contextID:UUID? {didSet {if contextID != oldValue {invalidateChoices()}}}
  /// Refresh metadata without discarding an in-progress search in the same scope.
  func updateChoices(_ titles:[String],selected:String?,contextID:UUID?,enabled:Bool) {
    self.contextID=contextID
    if itemTitles != titles {invalidateChoices();removeAllItems();addItems(withTitles:titles)}
    if titleOfSelectedItem != selected {invalidateChoices();selectItem(withTitle:selected ?? "")}
    if isEnabled && !enabled {invalidateChoices()}
    isEnabled=enabled;invalidateIntrinsicContentSize();needsDisplay=true
  }
  func invalidateChoices() {choicesRevision=UUID();popup.close()}
  private(set) var choices:StudioSearchableChoices?
  override func mouseDown(with event:NSEvent) {showChoices()}
  override func performClick(_ sender:Any?) {showChoices()}
  override func accessibilityPerformPress()->Bool {guard isEnabled,window?.isVisible == true else {return false};showChoices();return true}
  override func accessibilityPerformShowMenu()->Bool {accessibilityPerformPress()}
  override func keyDown(with event:NSEvent) {
    if event.modifierFlags.intersection([.command,.control,.option]).isEmpty,[36,49,125,126].contains(event.keyCode) {showChoices()} else {super.keyDown(with:event)}
  }
  func showChoices() {
    guard isEnabled,window != nil,!popup.isShown else {return}
    StudioHoverHelp.shared.hide()
    let values=itemTitles,revision=choicesRevision
    let controller=StudioSearchableChoices(values:values,selected:titleOfSelectedItem) { [weak self] value in
      guard let self,revision==choicesRevision,isEnabled,itemTitles.contains(value) else {return}
      selectItem(withTitle:value)
      if let action {_ = sendAction(action,to:target)}
    }
    controller.dismiss={ [weak self] in self?.popup.close() }
    controller.searchActivated={ [weak self] in guard let self,popup.isShown else {return};popup.contentSize=Self.choicesSize(values,searching:true) }
    choices=controller;popup.behavior = .transient;popup.animates=false
    popup.contentViewController=controller;popup.contentSize=Self.choicesSize(values)
    (window as? StudioPanelWindow)?.activePopover=popup
    popup.show(relativeTo:bounds,of:self,preferredEdge:.maxY)
    controller.view.layoutSubtreeIfNeeded()
    controller.table.scrollRowToVisible(controller.table.selectedRow)
    popup.contentViewController?.view.window?.makeKey()
    popup.contentViewController?.view.window?.makeFirstResponder(controller.table)
  }
  override func viewWillMove(toWindow newWindow:NSWindow?) {popup.close();super.viewWillMove(toWindow:newWindow)}
}

@MainActor private final class StudioChoiceRow:NSTableRowView {
  override func drawSelection(in dirtyRect:NSRect) {
    guard isSelected else {return}
    StudioTheme.selection.setFill()
    NSBezierPath(roundedRect:bounds.insetBy(dx:4,dy:1),xRadius:6,yRadius:6).fill()
  }
  override var isEmphasized:Bool {get {false} set {}}
}
@MainActor final class StudioChoiceTable:NSTableView {
  var handleKey:((NSEvent)->Bool)?
  override func keyDown(with event:NSEvent) {if handleKey?(event) != true {super.keyDown(with:event)}}
}
@MainActor final class StudioSearchableChoices:NSViewController,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate {
  let search=NSSearchField()
  let table=StudioChoiceTable()
  let values:[String]
  private(set) var filtered:[String]
  private var searchHeight:NSLayoutConstraint?
  private let emptyLabel=NSTextField(labelWithString:"Eşleşen seçenek yok")
  var searchActivated:(()->Void)?
  let accept:(String)->Void
  var dismiss:(()->Void)?
  init(values:[String],selected:String?,accept:@escaping (String)->Void) {
    self.values=values;filtered=values;self.accept=accept
    super.init(nibName:nil,bundle:nil)
    loadViewIfNeeded()
    if let selected,let index=values.firstIndex(of:selected) {table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false);table.scrollRowToVisible(index)}
    else if !values.isEmpty {table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)}
  }
  required init?(coder:NSCoder) {fatalError()}
  override func loadView() {
    view=NSView(frame:NSRect(x:0,y:0,width:280,height:300));StudioTheme.surface(view,card:true)
    view.layer?.backgroundColor=StudioTheme.canvas.cgColor
    search.placeholderString="Ara…";search.delegate=self;search.setAccessibilityLabel("Seçeneklerde ara")
    search.translatesAutoresizingMaskIntoConstraints=false;search.isHidden=true
    table.style = .plain
    table.addTableColumn(NSTableColumn(identifier:.init("choice")));table.headerView=nil;table.rowHeight=StudioMetrics.choiceRowHeight
    table.intercellSpacing=NSSize(width:0,height:0);table.selectionHighlightStyle = .regular
    table.frame=NSRect(x:0,y:0,width:280,height:0);table.autoresizingMask=[.width];table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.dataSource=self;table.delegate=self;table.target=self;table.action=#selector(clickedChoice)
    table.backgroundColor=StudioTheme.canvas;table.setAccessibilityLabel("Seçenekler")
    table.handleKey={ [weak self] event in self?.handle(event) ?? false }
    let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.borderType = .noBorder;scroll.translatesAutoresizingMaskIntoConstraints=false
    scroll.drawsBackground=false;scroll.automaticallyAdjustsContentInsets=false;scroll.contentInsets = .init(top:0,left:0,bottom:0,right:0);scroll.scrollerInsets = .init(top:0,left:0,bottom:0,right:0)
    view.addSubview(search);view.addSubview(scroll)
    emptyLabel.textColor=StudioTheme.muted;emptyLabel.font = .systemFont(ofSize:12);emptyLabel.isHidden = !values.isEmpty
    emptyLabel.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(emptyLabel)
    NSLayoutConstraint.activate([emptyLabel.centerXAnchor.constraint(equalTo:scroll.centerXAnchor),emptyLabel.centerYAnchor.constraint(equalTo:scroll.centerYAnchor)])
    searchHeight=search.heightAnchor.constraint(equalToConstant:0)
    NSLayoutConstraint.activate([search.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:10),search.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-10),search.topAnchor.constraint(equalTo:view.topAnchor,constant:6),searchHeight!,scroll.topAnchor.constraint(equalTo:search.bottomAnchor,constant:0),scroll.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:5),scroll.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-5),scroll.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-6)])
  }
  func beginSearch(_ seed:String) {
    let first=search.isHidden
    search.isHidden=false;searchHeight?.constant=28
    if first {searchActivated?()}
    view.layoutSubtreeIfNeeded();search.stringValue=seed;filter(seed)
    view.window?.makeFirstResponder(search)
    search.currentEditor()?.selectedRange=NSRange(location:(seed as NSString).length,length:0)
  }
  func handle(_ event:NSEvent)->Bool {
    guard event.modifierFlags.intersection([.command,.control,.option]).isEmpty else {return false}
    switch event.keyCode {
    case 53:dismiss?();return true
    case 36,76:commit();return true
    case 125:move(1);return true
    case 126:move(-1);return true
    default:
      guard let text=event.characters,!text.isEmpty,text.unicodeScalars.allSatisfy({!CharacterSet.controlCharacters.contains($0)}) else {return false}
      beginSearch(text);return true
    }
  }
  func filter(_ query:String) {
    filtered=values.filter {query.isEmpty || $0.localizedStandardContains(query)}
    emptyLabel.isHidden = !filtered.isEmpty
    table.reloadData();table.deselectAll(nil)
    if !filtered.isEmpty {table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);table.scrollRowToVisible(0)}
  }
  func controlTextDidChange(_ obj:Notification) {filter(search.stringValue)}
  func move(_ delta:Int) {
    guard !filtered.isEmpty else {return}
    let row=max(0,min(filtered.count-1,table.selectedRow+delta))
    table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);table.scrollRowToVisible(row)
  }
  func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector)->Bool {
    if selector == #selector(NSResponder.cancelOperation(_:)) {dismiss?();return true}
    if selector == #selector(NSResponder.insertNewline(_:)) {commit();return true}
    if selector == #selector(NSResponder.moveDown(_:)) {move(1);return true}
    if selector == #selector(NSResponder.moveUp(_:)) {move(-1);return true}
    return false
  }
  @objc private func clickedChoice() {guard table.clickedRow>=0 else {return};commit()}
  @objc func commit() {guard filtered.indices.contains(table.selectedRow) else {return};let value=filtered[table.selectedRow];dismiss?();accept(value)}
  func numberOfRows(in tableView:NSTableView)->Int {filtered.count}
  func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView? {StudioChoiceRow()}
  func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
    let cell=NSTextField(labelWithString:filtered[row]);cell.font = .systemFont(ofSize:StudioMetrics.bodyFont);cell.textColor=StudioTheme.text;cell.lineBreakMode = .byTruncatingMiddle
    let host=NSView();host.addSubview(cell);cell.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([cell.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:10),cell.trailingAnchor.constraint(equalTo:host.trailingAnchor,constant:-10),cell.centerYAnchor.constraint(equalTo:host.centerYAnchor)])
    return host
  }
}

struct StudioSearchablePicker:NSViewRepresentable {
  let title:String
  let values:[String]
  var emptyTitle="Veritabanı seçin"
  @Binding var selection:String
  @MainActor final class Coordinator:NSObject {
    var parent:StudioSearchablePicker
    init(_ parent:StudioSearchablePicker) {self.parent=parent}
    @objc func changed(_ sender:NSPopUpButton) {if let value=sender.titleOfSelectedItem {parent.selection=sender.selectedItem?.representedObject as? String ?? value}}
  }
  @Environment(\.isEnabled) private var enabled
  func makeCoordinator()->Coordinator {Coordinator(self)}
  func makeNSView(context:Context)->StudioSearchablePopUpButton {
    let button=StudioSearchablePopUpButton();button.target=context.coordinator;button.action=#selector(Coordinator.changed(_:));return button
  }
  // An unconstrained NSViewRepresentable otherwise accepts the entire available
  // height, turning whitespace into an invisible popup button (notably History).
  func sizeThatFits(_ proposal:ProposedViewSize,nsView:StudioSearchablePopUpButton,context:Context)->CGSize? {
    CGSize(width:min(280,max(100,proposal.width ?? nsView.intrinsicContentSize.width)),height:StudioMetrics.controlHeight)
  }
  func updateNSView(_ button:StudioSearchablePopUpButton,context:Context) {
    context.coordinator.parent=self
    let items=values.contains(selection) ? values:[selection]+values
    let labels=items.map {$0.isEmpty ? emptyTitle:$0}
    button.updateChoices(labels,selected:selection.isEmpty ? emptyTitle:selection,contextID:nil,enabled:enabled)
    for (index,value) in items.enumerated() {button.item(at:index)?.representedObject=value}
    button.setAccessibilityLabel(title)
  }
}
