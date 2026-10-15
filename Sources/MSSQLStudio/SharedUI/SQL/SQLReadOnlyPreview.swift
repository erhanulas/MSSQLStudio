import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor private final class DefinitionPreviewTextView: StudioTextView {
  var navigateDefinition: (([String]) -> Void)?
  var revealInExplorer: (([String]) -> Void)?
  override func mouseDown(with event:NSEvent) {
    if DefinitionReference.isNavigationClick(event),let navigateDefinition {
      if let offset=DefinitionReference.clickedOffset(in:self,at:convert(event.locationInWindow,from:nil)),
        let parts=DefinitionReference.parts(in:string,at:offset) {
        window?.makeFirstResponder(self);setSelectedRange(NSRange(location:offset,length:0))
        navigateDefinition(parts)
      }
      return
    }
    super.mouseDown(with:event)
  }
  @objc private func revealExplorerObject(_ item:NSMenuItem) {if let parts=item.representedObject as? [String] {revealInExplorer?(parts)}}
  override func validateUserInterfaceItem(_ item:any NSValidatedUserInterfaceItem)->Bool {
    if item.action == #selector(revealExplorerObject(_:)) {return revealInExplorer != nil && (item as? NSMenuItem)?.representedObject is [String]}
    return super.validateUserInterfaceItem(item)
  }
  override func menu(for event:NSEvent)->NSMenu? {
    let menu=super.menu(for:event) ?? StudioMenu()
    if revealInExplorer != nil {
      let item=NSMenuItem(title:"Explorer’da Git",action:#selector(revealExplorerObject(_:)),keyEquivalent:"")
      item.target=self;item.representedObject=DefinitionReference.parts(in:string,at:characterIndexForInsertion(at:convert(event.locationInWindow,from:nil)),maxParts:3)
      item.isEnabled=item.representedObject != nil;menu.addItem(.separator());menu.addItem(item)
    }
    return menu
  }
  @objc private func goToDefinition(_ sender:Any?) {
    if let parts=DefinitionReference.parts(in:string,at:selectedRange().location) {navigateDefinition?(parts)}
  }
  override func keyDown(with event: NSEvent) {
    if GridShortcuts.matches(.revealExplorer,event),let parts=DefinitionReference.parts(in:string,at:selectedRange().location,maxParts:3) {revealInExplorer?(parts);return}
    if GridShortcuts.matches(.definition,event), let navigateDefinition {
      if let parts=DefinitionReference.parts(in:string,at:selectedRange().location) {navigateDefinition(parts)}
      return
    }
    super.keyDown(with:event)
  }
}
/// A fixed sibling gutter, shared with the editor, stays outside the scrolling text viewport.
@MainActor final class SQLPreviewView: NSView {
  let scroll=NSScrollView()
  let ruler:LineNumbers
  private let preview=DefinitionPreviewTextView(usingTextLayoutManager:true)
  var textView:NSTextView {preview}
  var navigateDefinition: (([String])->Void)? {didSet {preview.navigateDefinition=navigateDefinition}}
  var revealInExplorer: (([String])->Void)? {didSet {preview.revealInExplorer=revealInExplorer}}
  private var lastSQL:String?
  private var lastDark:Bool?
  private var lineStarts=[0]
  private var measuredWidth:CGFloat=1
  override var isFlipped:Bool {true}
  override init(frame:NSRect) {
    ruler=LineNumbers(scrollView:scroll)
    super.init(frame:frame)
    wantsLayer=true;clipsToBounds=true
    preview.wantsLayer=true;scroll.wantsLayer=true;ruler.wantsLayer=true
    preview.identifier = .init("sqlSourcePreview")
    preview.isEditable=false;preview.isSelectable=true
    preview.isHorizontallyResizable=false;preview.isVerticallyResizable=false
    preview.textLayoutManager?.usesFontLeading=false
    preview.textContainer?.widthTracksTextView=false
    preview.textContainer?.lineBreakMode = .byClipping
    preview.textContainerInset=NSSize(width:14,height:10)
    preview.setAccessibilityLabel("SQL önizleme editörü")
    scroll.documentView=preview;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true
    scroll.autohidesScrollers=true;scroll.borderType = .noBorder;scroll.clipsToBounds=true
    ruler.editor=preview;ruler.ruleThickness=48;ruler.numberPadding=10;ruler.clipsToBounds=true
    ruler.sourceText={ [weak self] in self?.lastSQL ?? "" }
    ruler.lineNumber={ [weak self] offset in
      guard let self else {return 1}
      var low=0,high=lineStarts.count
      while low<high {let mid=(low+high)/2;if lineStarts[mid]<=offset {low=mid+1} else {high=mid}}
      return max(1,low)
    }
    ruler.selectLine={ [weak preview] range in preview?.window?.makeFirstResponder(preview);preview?.setSelectedRange(range) }
    addSubview(ruler);addSubview(scroll)
    ruler.translatesAutoresizingMaskIntoConstraints=false;scroll.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([ruler.leadingAnchor.constraint(equalTo:leadingAnchor),ruler.topAnchor.constraint(equalTo:topAnchor),ruler.bottomAnchor.constraint(equalTo:bottomAnchor),ruler.widthAnchor.constraint(equalToConstant:48),scroll.leadingAnchor.constraint(equalTo:ruler.trailingAnchor),scroll.trailingAnchor.constraint(equalTo:trailingAnchor),scroll.topAnchor.constraint(equalTo:topAnchor),scroll.bottomAnchor.constraint(equalTo:bottomAnchor)])
    scroll.contentView.postsBoundsChangedNotifications=true
    NotificationCenter.default.addObserver(self,selector:#selector(scrolled),name:NSView.boundsDidChangeNotification,object:scroll.contentView)
    NotificationCenter.default.addObserver(self,selector:#selector(themeChanged),name:StudioTheme.changed,object:nil)
  }
  required init?(coder:NSCoder) {fatalError()}
  @objc private func scrolled() {ruler.needsDisplay=true}
  @objc private func themeChanged() {if let lastSQL {display(lastSQL)}}
  override func layout() {super.layout();updateGeometry();ruler.needsDisplay=true}
  private func updateGeometry() {
    scroll.tile()
    let width=max(measuredWidth,scroll.contentView.bounds.width),height=max(scroll.contentView.bounds.height,CGFloat(lineStarts.count)*20+32)
    if preview.frame.size != NSSize(width:width,height:height) {
      preview.textContainer?.containerSize=NSSize(width:max(1,width-28),height:CGFloat.greatestFiniteMagnitude)
      preview.setFrameSize(NSSize(width:width,height:height))
      preview.needsLayout=true;preview.layoutSubtreeIfNeeded()
    }
  }
  func display(_ sql:String) {
    guard lastSQL != sql || lastDark != StudioTheme.dark else {return}
    let same=lastSQL==sql,selection=preview.selectedRanges,origin=scroll.contentView.bounds.origin
    lastSQL=sql;lastDark=StudioTheme.dark
    preview.backgroundColor=StudioTheme.editorCanvas;scroll.backgroundColor=StudioTheme.editorCanvas
    let attributed=NSMutableAttributedString(attributedString:SQLSourceHighlighting.attributed(sql))
    let paragraph=NSMutableParagraphStyle();paragraph.minimumLineHeight=20;paragraph.maximumLineHeight=20
    attributed.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:attributed.length))
    preview.textContentStorage?.textStorage?.setAttributedString(attributed)
    lineStarts=[0]
    let units=Array(sql.utf16)
    for (index,unit) in units.enumerated() {
      if unit==13 {lineStarts.append(index+1+(index+1<units.count && units[index+1]==10 ? 1:0))}
      else if unit==10 {if index==0 || units[index-1] != 13 {lineStarts.append(index+1)}}
      else if [UInt16(0x85),0x2028,0x2029].contains(unit) {lineStarts.append(index+1)}
    }
    measuredWidth=max(40,(sql.components(separatedBy:.newlines).map {($0 as NSString).size(withAttributes:[.font:StudioTheme.codeFont]).width}.max() ?? 0)+40)
    updateGeometry()
    if same {preview.selectedRanges=selection;scroll.contentView.scroll(to:origin)}
    else {preview.setSelectedRange(NSRange(location:0,length:0));scroll.contentView.scroll(to:.zero)}
    scroll.reflectScrolledClipView(scroll.contentView);ruler.needsDisplay=true
  }
}
struct SQLReadOnlyPreview:NSViewRepresentable {
  let sql:String
  var navigateDefinition:(([String])->Void)?=nil
  var revealInExplorer:(([String])->Void)?=nil
  func makeNSView(context:Context)->SQLPreviewView {SQLPreviewView(frame:.zero)}
  func updateNSView(_ view:SQLPreviewView,context:Context) {view.navigateDefinition=navigateDefinition;view.revealInExplorer=revealInExplorer;view.display(sql)}
}
