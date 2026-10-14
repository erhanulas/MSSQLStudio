import AppKit
import SwiftUI

/// Retains NSPopUpButton selection/target-action API; searching never changes selection.
@MainActor final class StudioSearchablePopUpButton:NSPopUpButton {
  private let popup=NSPopover()
  private var choicesRevision=UUID()
  var contextID:UUID? {didSet {if contextID != oldValue {invalidateChoices()}}}
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
    choices=controller;popup.behavior = .transient;popup.animates=false
    popup.contentViewController=controller;popup.contentSize=NSSize(width:max(260,min(420,bounds.width)),height:300)
    popup.show(relativeTo:bounds,of:self,preferredEdge:.maxY)
    popup.contentViewController?.view.window?.makeFirstResponder(controller.search)
  }
  override func viewWillMove(toWindow newWindow:NSWindow?) {popup.close();super.viewWillMove(toWindow:newWindow)}
}

@MainActor final class StudioSearchableChoices:NSViewController,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate {
  let search=NSSearchField()
  let table=NSTableView()
  let values:[String]
  private(set) var filtered:[String]
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
    search.placeholderString="Ara…";search.delegate=self;search.setAccessibilityLabel("Seçeneklerde ara")
    search.translatesAutoresizingMaskIntoConstraints=false
    table.addTableColumn(NSTableColumn(identifier:.init("choice")));table.headerView=nil;table.rowHeight=28
    table.frame=NSRect(x:0,y:0,width:280,height:0);table.autoresizingMask=[.width];table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.dataSource=self;table.delegate=self;table.target=self;table.action=#selector(commit)
    table.backgroundColor=StudioTheme.panel;table.setAccessibilityLabel("Arama sonuçları")
    let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.borderType = .noBorder;scroll.translatesAutoresizingMaskIntoConstraints=false
    view.addSubview(search);view.addSubview(scroll)
    NSLayoutConstraint.activate([search.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:10),search.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-10),search.topAnchor.constraint(equalTo:view.topAnchor,constant:10),scroll.topAnchor.constraint(equalTo:search.bottomAnchor,constant:8),scroll.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:6),scroll.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-6),scroll.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-6)])
  }
  func filter(_ query:String) {
    filtered=values.filter {query.isEmpty || $0.localizedStandardContains(query)}
    table.reloadData();table.deselectAll(nil)
    if !filtered.isEmpty {table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)}
  }
  func controlTextDidChange(_ obj:Notification) {filter(search.stringValue)}
  func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector)->Bool {
    if selector == #selector(NSResponder.cancelOperation(_:)) {dismiss?();return true}
    if selector == #selector(NSResponder.insertNewline(_:)) {commit();return true}
    if selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.moveUp(_:)) {
      guard !filtered.isEmpty else {return true}
      let row=max(0,min(filtered.count-1,table.selectedRow+(selector == #selector(NSResponder.moveDown(_:)) ? 1:-1)))
      table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);table.scrollRowToVisible(row);return true
    }
    return false
  }
  @objc func commit() {guard filtered.indices.contains(table.selectedRow) else {return};let value=filtered[table.selectedRow];dismiss?();accept(value)}
  func numberOfRows(in tableView:NSTableView)->Int {filtered.count}
  func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
    let cell=NSTextField(labelWithString:filtered[row]);cell.font = .systemFont(ofSize:12);cell.lineBreakMode = .byTruncatingMiddle;return cell
  }
}

struct StudioSearchablePicker:NSViewRepresentable {
  let title:String
  let values:[String]
  var emptyTitle="Veritabanı seçin"
  @Binding var selection:String
  final class Coordinator:NSObject {
    var parent:StudioSearchablePicker
    init(_ parent:StudioSearchablePicker) {self.parent=parent}
    @objc func changed(_ sender:NSPopUpButton) {if let value=sender.titleOfSelectedItem {parent.selection=sender.selectedItem?.representedObject as? String ?? value}}
  }
  @Environment(\.isEnabled) private var enabled
  func makeCoordinator()->Coordinator {Coordinator(self)}
  func makeNSView(context:Context)->StudioSearchablePopUpButton {
    let button=StudioSearchablePopUpButton();button.target=context.coordinator;button.action=#selector(Coordinator.changed(_:));return button
  }
  func updateNSView(_ button:StudioSearchablePopUpButton,context:Context) {
    context.coordinator.parent=self
    let items=values.contains(selection) ? values:[selection]+values
    let labels=items.map {$0.isEmpty ? emptyTitle:$0}
    if button.itemTitles != labels {button.invalidateChoices();button.removeAllItems();button.addItems(withTitles:labels)}
    if let index=items.firstIndex(of:selection),button.indexOfSelectedItem != index {button.invalidateChoices()}
    for (index,value) in items.enumerated() {button.item(at:index)?.representedObject=value}
    if let index=items.firstIndex(of:selection) {button.selectItem(at:index)}
    button.isEnabled=enabled;button.setAccessibilityLabel(title)
  }
}
