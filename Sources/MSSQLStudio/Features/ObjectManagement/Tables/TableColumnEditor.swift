import AppKit
import SQLServerKit
import SwiftUI

/// One native key-view chain keeps row navigation independent of system button-navigation preferences.
struct TableColumnEditor:NSViewRepresentable {
  @Binding var column:SQLServerKit.TableColumn
  @Binding var primary:Bool
  let choices:[TableDataType]
  let selected:Bool
  let existing:Bool
  let generated:Bool
  let select:()->Void
  @Environment(\.isEnabled) private var enabled
  func makeNSView(context:Context)->TableColumnEditorView {TableColumnEditorView()}
  func updateNSView(_ view:TableColumnEditorView,context:Context) {
    view.changed={value,key in column=value;primary=key;select()}
    view.selected=select
    view.update(column:column,primary:primary,choices:choices,selected:selected,existing:existing,generated:generated,enabled:enabled)
  }
}

@MainActor final class TableColumnEditorView:NSView,NSTextFieldDelegate,StudioTabNavigation {
  private final class RowToggle:NSButton {
    override var canBecomeKeyView:Bool {isEnabled && !isHiddenOrHasHiddenAncestor}
  }
  let name=NSTextField(),type=StudioSearchablePopUpButton(),size=NSTextField(),scale=NSTextField(),defaultSQL=NSTextField()
  private let selectButton=NSButton(),nullable=RowToggle(checkboxWithTitle:"",target:nil,action:nil),primary=RowToggle(checkboxWithTitle:"",target:nil,action:nil),identity=RowToggle(checkboxWithTitle:"",target:nil,action:nil)
  private let typeGroup=NSView(),computed=NSTextField(labelWithString:"")
  private var column=SQLServerKit.TableColumn(id:0,name:"")
  private var choices:[TableDataType]=[]
  private var isPrimary=false
  var changed:((SQLServerKit.TableColumn,Bool)->Void)?
  var selected:(()->Void)?
  override init(frame:NSRect) {
    super.init(frame:frame)
    let stack=NSStackView(views:[selectButton,name,typeGroup,nullable,primary,identity,defaultSQL])
    stack.orientation = .horizontal;stack.spacing=8;stack.alignment = .centerY
    stack.translatesAutoresizingMaskIntoConstraints=false;addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:leadingAnchor),stack.trailingAnchor.constraint(equalTo:trailingAnchor),stack.centerYAnchor.constraint(equalTo:centerYAnchor)])
    for (view,width) in [(selectButton,28.0),(name,150),(typeGroup,224),(nullable,45),(primary,40),(identity,70),(defaultSQL,240)] {
      view.translatesAutoresizingMaskIntoConstraints=false;view.widthAnchor.constraint(equalToConstant:width).isActive=true
    }
    typeGroup.heightAnchor.constraint(equalToConstant:StudioMetrics.controlHeight).isActive=true
    for (view,x,width) in [(type,0.0,136.0),(size,140,44),(scale,188,32)] {
      typeGroup.addSubview(view);view.translatesAutoresizingMaskIntoConstraints=false
      NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:typeGroup.leadingAnchor,constant:x),view.widthAnchor.constraint(equalToConstant:width),view.centerYAnchor.constraint(equalTo:typeGroup.centerYAnchor)])
    }
    for field in [name,size,scale,defaultSQL] {field.delegate=self;field.font=StudioTheme.uiFont}
    name.placeholderString="Kolon";defaultSQL.placeholderString="DEFAULT SQL"
    selectButton.isBordered=false;selectButton.target=self;selectButton.action=#selector(selectName)
    type.participatesInTabOrder=true;type.target=self;type.action=#selector(changeType)
    for button in [nullable,primary,identity] {button.target=self;button.action=#selector(changeFlags)}
    nullable.setAccessibilityLabel("NULL");primary.setAccessibilityLabel("PK");identity.setAccessibilityLabel("Identity")
    type.setAccessibilityLabel("Veri tipi");name.setAccessibilityLabel("Kolon adı")
    size.setAccessibilityLabel("Uzunluk veya precision");scale.setAccessibilityLabel("Scale")
    defaultSQL.setAccessibilityLabel("Default SQL")
    name.nextKeyView=type;type.nextKeyView=size;size.nextKeyView=scale
    scale.nextKeyView=nullable;nullable.nextKeyView=primary;primary.nextKeyView=identity;identity.nextKeyView=defaultSQL
    computed.font=StudioTheme.uiFont;computed.lineBreakMode = .byTruncatingTail
    defaultSQL.addSubview(computed);computed.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([computed.leadingAnchor.constraint(equalTo:defaultSQL.leadingAnchor),computed.trailingAnchor.constraint(equalTo:defaultSQL.trailingAnchor),computed.centerYAnchor.constraint(equalTo:defaultSQL.centerYAnchor)])
  }
  required init?(coder:NSCoder) {fatalError()}
  func update(column:SQLServerKit.TableColumn,primary:Bool,choices:[TableDataType],selected:Bool,existing:Bool,generated:Bool,enabled:Bool) {
    self.column=column;self.choices=choices;isPrimary=primary
    func text(_ field:NSTextField,_ value:String) {if field.stringValue != value {field.stringValue=value}}
    text(name,column.name);text(defaultSQL,column.defaultSQL)
    let base=TableDataType.baseName(column.type),choice=choices.first {$0.name.caseInsensitiveCompare(base) == .orderedSame}
    let values=choices.map(\.name)
    type.updateChoices(values.contains(base) ? values:[base]+values,selected:choice?.name ?? base,contextID:nil,enabled:enabled && !generated && column.computed.isEmpty)
    let parameters=Self.parameters(column.type)
    size.isHidden=choice?.parameters == TableDataType.Parameters.none || choice==nil;scale.isHidden=choice?.parameters != .precision
    text(size,parameters.first ?? "");text(scale,parameters.count>1 ? parameters[1]:"")
    size.placeholderString=choice?.parameters == .precision ? "p":"Boyut";scale.placeholderString="s"
    size.isEnabled=type.isEnabled;scale.isEnabled=type.isEnabled;name.isEnabled=enabled
    nullable.state=column.nullable ? .on:.off;self.primary.state=primary ? .on:.off;identity.state=column.identity ? .on:.off
    nullable.isEnabled=enabled && !column.identity && column.computed.isEmpty && !primary
    self.primary.isEnabled=enabled;identity.isEnabled=enabled && !existing;selectButton.isEnabled=enabled
    defaultSQL.isEnabled=enabled && column.computed.isEmpty
    defaultSQL.isBordered=false;defaultSQL.isBezeled=column.computed.isEmpty
    defaultSQL.bezelStyle = .roundedBezel;defaultSQL.drawsBackground=column.computed.isEmpty
    computed.isHidden=column.computed.isEmpty;computed.stringValue="AS "+column.computed
    selectButton.image=NSImage(systemSymbolName:primary ? "key.fill":selected ? "arrowtriangle.right.fill":"circle",accessibilityDescription:nil)
    selectButton.contentTintColor=primary ? StudioTheme.warning:selected ? StudioTheme.accent:StudioTheme.muted
    selectButton.setAccessibilityLabel(column.name+" kolonunu seç")
    selectButton.setAccessibilityIdentifier("selectDesignerColumn_\(column.id)")
  }
  private var tabFields:[NSControl] {
    [name,type,size,scale,nullable,primary,identity,defaultSQL].filter {$0.isEnabled && !$0.isHiddenOrHasHiddenAncestor}
  }
  func advanceTabFocus(from view:NSView,backward:Bool)->Bool {
    let fields=tabFields
    guard let index=fields.firstIndex(where:{$0 === view}),let window else {return false}
    let next=index+(backward ? -1:1)
    if fields.indices.contains(next) {fields[next].scrollToVisible(fields[next].bounds);return window.makeFirstResponder(fields[next])}
    // Lazy rows only register mounted native views; no retained control registry survives row removal.
    guard let document=enclosingScrollView?.documentView else {return false}
    func rows(_ view:NSView)->[TableColumnEditorView] {
      if let row=view as? TableColumnEditorView {return [row]}
      return view.subviews.flatMap(rows)
    }
    let visibleRows=rows(document).sorted {a,b in
      let ay=document.convert(a.bounds,from:a).midY,by=document.convert(b.bounds,from:b).midY
      return document.isFlipped ? ay<by:ay>by
    }
    guard let rowIndex=visibleRows.firstIndex(where:{$0 === self}) else {return false}
    let adjacent=rowIndex+(backward ? -1:1)
    guard visibleRows.indices.contains(adjacent),let target=backward ? visibleRows[adjacent].tabFields.last:visibleRows[adjacent].tabFields.first else {return false}
    target.scrollToVisible(target.bounds)
    return window.makeFirstResponder(target)
  }
  private static func parameters(_ type:String)->[String] {
    guard let open=type.firstIndex(of:"("),type.hasSuffix(")") else {return []}
    return type[type.index(after:open)..<type.index(before:type.endIndex)].split(separator:",",omittingEmptySubsequences:false).map(String.init)
  }
  @objc private func selectName() {selected?();window?.makeFirstResponder(name)}
  @objc private func changeType() {
    guard let choice=choices.first(where:{$0.name==type.titleOfSelectedItem}) else {return}
    if choice.name.caseInsensitiveCompare(TableDataType.baseName(column.type)) != .orderedSame {column.type=choice.defaultSQL}
    changed?(column,isPrimary)
  }
  @objc private func changeFlags() {
    isPrimary=primary.state == .on;column.identity=identity.state == .on
    column.nullable=nullable.state == .on && !isPrimary && !column.identity
    changed?(column,isPrimary)
  }
  func controlTextDidBeginEditing(_ notification:Notification) {selected?()}
  func controlTextDidChange(_ notification:Notification) {
    guard let field=notification.object as? NSTextField else {return}
    if field===name {column.name=name.stringValue}
    else if field===defaultSQL {column.defaultSQL=defaultSQL.stringValue}
    else {
      let precision=choices.first {$0.name.caseInsensitiveCompare(TableDataType.baseName(column.type)) == .orderedSame}?.parameters == .precision
      column.type=TableDataType.baseName(column.type)+"("+size.stringValue+(precision ? ","+scale.stringValue:"")+")"
    }
    changed?(column,isPrimary)
  }
}
