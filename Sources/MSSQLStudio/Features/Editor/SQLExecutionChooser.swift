import AppKit
import SQLServerKit

@MainActor private final class SQLExecutionMenuAction:NSObject {
  let action:()->Void
  init(_ action:@escaping ()->Void) {self.action=action}
  @objc func invoke(_ sender:Any?) {action()}
}

extension EditorController {
  func requestStatementExecution() {
    guard document.canExecute,!editor.hasMarkedText(),editor.selectedRanges.count == 1 else {return}
    // An explicit selection has priority, including folded source selections.
    if document.selectedRange.length > 0 {document.execute();return}
    let source=document.sql,caret=document.selectedRange.location
    guard !source.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return}
    let database=document.database,generation=document.server.generation,request=UUID()
    executionRequest=request
    Task { [weak self] in
      let scopes=await Task.detached(priority:.userInitiated) {SQLExecutionScopes(source)}.value
      guard let self,executionRequest == request,document.sql == source,document.database == database,
        document.server.generation == generation,document.canExecute,!editor.hasMarkedText(),document.selectedRange.location == caret else {return}
      guard scopes.statements.count != 1 else {document.execute(override:source);return}
      closeExecutionAssistance()
      let text=source as NSString,menu=StudioMenu(),all=NSRange(location:0,length:text.length)
      if scopes.statements.isEmpty {
        let note=NSMenuItem(title:"İfadeler güvenle ayrıştırılamadı; seçim yapabilir veya tüm SQL’i çalıştırabilirsiniz.",action:nil,keyEquivalent:"")
        note.isEnabled=false;menu.addItem(note)
      }
      var actions:[SQLExecutionMenuAction]=[],ranges:[NSRange]=[]
      @MainActor func add(_ range:NSRange,title:String) -> NSMenuItem {
        let sql=text.substring(with:range)
        let target=SQLExecutionMenuAction { [weak self] in
          guard let self,executionRequest == request,document.sql == source,document.database == database,
            document.server.generation == generation,document.canExecute,!editor.hasMarkedText() else {return}
          document.execute(override:sql)
        }
        actions.append(target);ranges.append(range)
        let item=NSMenuItem(title:title,action:#selector(SQLExecutionMenuAction.invoke(_:)),keyEquivalent:"")
        item.target=target;item.toolTip=String(sql.prefix(2000));menu.addItem(item);return item
      }
      let nearest=scopes.statements.last(where:{$0.range.location <= caret}) ?? scopes.statements.first
      var preferred:NSMenuItem?
      for (index,statement) in scopes.statements.enumerated() {
        let start=text.substring(to:statement.range.location).filter {$0 == "\n"}.count+1
        let snippet=text.substring(with:statement.range).split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        let item=add(statement.range,title:"\(index+1). Satır \(start) · "+String(snippet.prefix(120)))
        if statement == nearest {preferred=item;item.state = .on}
      }
      menu.addItem(.separator())
      if let nearest,nearest.batch != all,nearest.batch != nearest.range {add(nearest.batch,title:"İmleçteki batch’i çalıştır (GO tekrarı dahil)")}
      add(all,title:"Tüm SQL’i çalıştır")
      if let fixture=executionChoiceFixture {if let index=fixture(ranges),actions.indices.contains(index) {actions[index].action()};return}
      guard editor.window != nil else {return}
      let rect=editor.firstRect(forCharacterRange:editor.selectedRange(),actualRange:nil)
      let screen=rect.origin,window=editor.window?.convertPoint(fromScreen:screen) ?? .zero
      let point=editor.convert(window,from:nil)
      withExtendedLifetime(actions) {menu.popUp(positioning:preferred,at:point,in:editor)}
    }
  }
}
