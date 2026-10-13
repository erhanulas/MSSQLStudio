import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor private final class SQLPreviewRuler: NSRulerView {
  var lines = 1
  override func drawHashMarksAndLabels(in rect: NSRect) {
    StudioTheme.editorCanvas.setFill(); bounds.fill()
    guard let clip=scrollView?.contentView else { return }
    let top=clip.bounds.minY
    let first=max(0,Int((top-10)/20)), last=min(lines-1,Int((top+clip.bounds.height)/20)+1)
    guard first <= last else { return }
    for line in first...last {
      let label=String(line+1) as NSString
      let attributes:[NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.regular),.foregroundColor:StudioTheme.lineNumber]
      let width=label.size(withAttributes:attributes).width
      label.draw(at:NSPoint(x:ruleThickness-width-10,y:10+CGFloat(line)*20-top+3),withAttributes:attributes)
    }
    StudioTheme.border.setFill(); NSRect(x:bounds.maxX-1,y:bounds.minY,width:1,height:bounds.height).fill()
  }
}
@MainActor final class SQLPreviewScrollView: NSScrollView {
  private let preview = NSTextView(usingTextLayoutManager:true)
  private var lastSQL: String?
  private var lastDark: Bool?
  override init(frame frameRect: NSRect) {
    super.init(frame:frameRect)
    clipsToBounds=true
    preview.identifier=NSUserInterfaceItemIdentifier("sqlSourcePreview")
    preview.isEditable=false; preview.isSelectable=true
    preview.isHorizontallyResizable=true; preview.isVerticallyResizable=true
    preview.textContainer?.widthTracksTextView=false
    preview.textContainerInset=NSSize(width:14,height:10)
    preview.setAccessibilityLabel("SQL önizleme editörü")
    documentView=preview; hasVerticalScroller=true; hasHorizontalScroller=true
    borderType = .noBorder
    let ruler=SQLPreviewRuler(scrollView:self,orientation:.verticalRuler); ruler.ruleThickness=48;ruler.clipsToBounds=true
    verticalRulerView=ruler; hasVerticalRuler=true; rulersVisible=true
    NotificationCenter.default.addObserver(self,selector:#selector(themeChanged),name:StudioTheme.changed,object:nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func themeChanged() { if let lastSQL { display(lastSQL) } }
  func display(_ sql: String) {
    guard lastSQL != sql || lastDark != StudioTheme.dark else { return }
    let sameSource=lastSQL == sql, selection=preview.selectedRanges, origin=contentView.bounds.origin
    lastSQL=sql; lastDark=StudioTheme.dark
    preview.backgroundColor=StudioTheme.editorCanvas; backgroundColor=StudioTheme.editorCanvas
    let attributed=NSMutableAttributedString(attributedString:SQLSourceHighlighting.attributed(sql))
    let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=20; paragraph.maximumLineHeight=20
    attributed.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:attributed.length))
    preview.textContentStorage?.textStorage?.setAttributedString(attributed)
    let lines=sql.components(separatedBy:"\n")
    let width=min(100000,max(600,(lines.map { ($0 as NSString).size(withAttributes:[.font:StudioTheme.codeFont]).width }.max() ?? 0)+40))
    preview.textContainer?.containerSize=NSSize(width:width,height:10000000)
    preview.setFrameSize(NSSize(width:width,height:max(200,CGFloat(lines.count)*20+32)))
    (verticalRulerView as? SQLPreviewRuler)?.lines=lines.count
    verticalRulerView?.needsDisplay=true
    if sameSource { preview.selectedRanges=selection; contentView.scroll(to:origin); reflectScrolledClipView(contentView) }
  }
}
struct SQLReadOnlyPreview: NSViewRepresentable {
  let sql: String
  func makeNSView(context: Context) -> SQLPreviewScrollView { SQLPreviewScrollView(frame:.zero) }
  func updateNSView(_ scroll: SQLPreviewScrollView, context: Context) { scroll.display(sql) }
}
