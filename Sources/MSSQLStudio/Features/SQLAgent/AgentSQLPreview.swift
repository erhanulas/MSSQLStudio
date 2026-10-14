import AppKit
import SQLServerKit
import SwiftUI

struct AgentSQLPreview:NSViewRepresentable {
  let sql:String
  func makeNSView(context:Context) -> NSScrollView {
    let scroll=NSScrollView();scroll.hasVerticalScroller=true
    let text=StudioTextView(usingTextLayoutManager:true);text.isEditable=false;text.isSelectable=true;text.font=StudioTheme.codeFont
    text.identifier = .init("sqlSourcePreview");text.isVerticallyResizable=true;text.autoresizingMask=[.width];text.textContainerInset=NSSize(width:10,height:10)
    scroll.documentView=text;return scroll
  }
  func updateNSView(_ scroll:NSScrollView,context:Context) {
    guard let text=scroll.documentView as? NSTextView else {return}
    if text.string != sql {text.textContentStorage?.textStorage?.setAttributedString(SQLSourceHighlighting.attributed(sql))}
    text.backgroundColor=StudioTheme.canvas
  }
}
