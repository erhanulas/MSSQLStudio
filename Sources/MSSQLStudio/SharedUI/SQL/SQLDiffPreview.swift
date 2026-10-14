import AppKit
import SQLServerKit
import SwiftUI

/// A zero-based changeIndex identifies a contiguous group of changed aligned rows.
/// -1 leaves the viewport alone; a new source initially reveals its first change.
struct SQLInlineDiffPreview: NSViewRepresentable {
  let comparison: SQLTextDiff.Comparison
  let original: String
  let edited: String
  let changeIndex: Int
  var editedOnLeft = false
  func makeNSView(context: Context) -> SQLInlineDiffView { SQLInlineDiffView(frame: .zero) }
  func updateNSView(_ view: SQLInlineDiffView, context: Context) {
    view.display(comparison: comparison, original: original, edited: edited, changeIndex: changeIndex, editedOnLeft: editedOnLeft)
  }
}

@MainActor private enum SQLInlineDiffRowStyle {
  case unchanged, removed, added, placeholder
  var background: NSColor {
    switch self {
    case .unchanged: StudioTheme.editorCanvas
    case .removed: StudioTheme.color(0xFCE5E5, 0x502D36)
    case .added: StudioTheme.color(0xE3F3EA, 0x254B3A)
    case .placeholder: StudioTheme.panel
    }
  }
}

@MainActor final class SQLInlineDiffTextView: NSTextView {
  fileprivate var rowStyles: [SQLInlineDiffRowStyle] = []
  fileprivate var rowRanges: [NSRange] = []
  fileprivate var copyRanges: [NSRange] = []
  fileprivate var copySourceRanges: [NSRange?] = []
  fileprivate var sourceSQL: NSString = ""
  fileprivate var sourceNumbers: [Int?] = []
  func backgroundFrame(forRow row: Int) -> NSRect {
    NSRect(x:0,y:textContainerOrigin.y+CGFloat(row)*SQLInlineDiffView.lineHeight,width:bounds.width,height:SQLInlineDiffView.lineHeight)
  }
  func lineGeometry(forRow row: Int) -> (rect: NSRect, baseline: CGFloat)? {
    guard rowRanges.indices.contains(row),let content=textContentStorage,let layout=textLayoutManager,
      let location=content.location(content.documentRange.location,offsetBy:rowRanges[row].location),
      let range=NSTextRange(location:location,end:location) else {return nil}
    layout.ensureLayout(for:range)
    guard let fragment=layout.textLayoutFragment(for:location) else {return nil}
    let offset=content.offset(from:content.documentRange.location,to:fragment.rangeInElement.location)
    let local=rowRanges[row].location-offset
    guard let line=fragment.textLineFragments.first(where:{NSLocationInRange(local,$0.characterRange) || $0.characterRange.location==local}) else {return nil}
    let rect=line.typographicBounds.offsetBy(dx:fragment.layoutFragmentFrame.minX+textContainerOrigin.x,dy:fragment.layoutFragmentFrame.minY+textContainerOrigin.y)
    return (rect,rect.minY+line.glyphOrigin.y)
  }
  override func draw(_ dirtyRect: NSRect) {
    NSGraphicsContext.saveGraphicsState();defer {NSGraphicsContext.restoreGraphicsState()};bounds.clip()
    StudioTheme.editorCanvas.setFill(); dirtyRect.fill()
    let first=max(0, Int((dirtyRect.minY-textContainerInset.height)/SQLInlineDiffView.lineHeight))
    let last=min(rowStyles.count-1, Int((dirtyRect.maxY-textContainerInset.height)/SQLInlineDiffView.lineHeight))
    if first <= last {
      for row in first...last where rowStyles[row] != .unchanged {
        rowStyles[row].background.setFill()
        backgroundFrame(forRow:row).fill()
      }
    }
    super.draw(dirtyRect)
  }
  /// Alignment-only rows and the painted ruler never become SQL clipboard text.
  func selectedSQL(in range: NSRange) -> String {
    var pieces: [String] = []
    for (row, lineRange) in copyRanges.enumerated() where sourceNumbers[row] != nil {
      let intersection=NSIntersectionRange(range, lineRange)
      guard intersection.length>0,let sourceRange=copySourceRanges[row] else {continue}
      let contentLength=rowRanges[row].length-1,relative=intersection.location-lineRange.location
      let length=min(intersection.length,max(0,contentLength-relative))
      if length>0 {pieces.append(sourceSQL.substring(with:NSRange(location:sourceRange.location+relative,length:length)))}
      if NSMaxRange(intersection)>lineRange.location+contentLength,sourceRange.length>contentLength {
        pieces.append(sourceSQL.substring(with:NSRange(location:sourceRange.location+contentLength,length:sourceRange.length-contentLength)))
      }
    }
    return pieces.joined()
  }
  override func copy(_ sender: Any?) {
    let text=selectedRanges.map { selectedSQL(in: $0.rangeValue) }.joined(separator: "\n")
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
  }
}

@MainActor final class SQLInlineDiffRuler: NSView {
  override var isFlipped:Bool {true}
  weak var scrollView:NSScrollView?
  var ruleThickness:CGFloat=36
  init(scrollView:NSScrollView) {self.scrollView=scrollView;super.init(frame:.zero)}
  required init?(coder:NSCoder) {fatalError()}
  weak var textView: SQLInlineDiffTextView?
  var numbers: [Int?] = []
  fileprivate var styles: [SQLInlineDiffRowStyle] = []
  func labelOrigin(forRow row: Int) -> NSPoint? {
    guard numbers.indices.contains(row),let number=numbers[row],let geometry=textView?.lineGeometry(forRow:row) else {return nil}
    let font=NSFont.monospacedDigitSystemFont(ofSize:11,weight:.regular)
    let width=(String(number) as NSString).size(withAttributes:[.font:font]).width
    return NSPoint(x:ruleThickness-width-8,y:geometry.baseline-(scrollView?.contentView.bounds.minY ?? 0)-font.ascender)
  }
  override func draw(_ rect: NSRect) {
    NSGraphicsContext.saveGraphicsState();defer {NSGraphicsContext.restoreGraphicsState()};bounds.clip()
    StudioTheme.editorCanvas.setFill(); bounds.fill()
    guard let clip=scrollView?.contentView else { return }
    let top=clip.bounds.minY
    let first=max(0, Int((top-8)/SQLInlineDiffView.lineHeight))
    let last=min(numbers.count-1, Int((top+clip.bounds.height)/SQLInlineDiffView.lineHeight)+1)
    if first <= last {
      let font=NSFont.monospacedDigitSystemFont(ofSize:11,weight:.regular)
      let attributes: [NSAttributedString.Key: Any] = [.font:font,.foregroundColor:StudioTheme.lineNumber]
      for row in first...last {
        let y=8+CGFloat(row)*SQLInlineDiffView.lineHeight-top
        if styles.indices.contains(row), styles[row] != .unchanged {
          styles[row].background.setFill(); NSRect(x: 0, y: y, width: ruleThickness, height: SQLInlineDiffView.lineHeight).fill()
        }
        guard let number=numbers[row] else { continue }
        guard let origin=labelOrigin(forRow:row) else {continue}
        (String(number) as NSString).draw(at:origin,withAttributes:attributes)
      }
    }
    StudioTheme.border.setFill(); NSRect(x: bounds.maxX-1, y: bounds.minY, width: 1, height: bounds.height).fill()
  }
}

/// Native, selectable, aligned SQL panes. The parent owns captions and navigation.
@MainActor final class SQLInlineDiffView: NSView {
  static let lineHeight: CGFloat = 20
  static let maximumRows = 10_000
  static let maximumCharacters = 1_000_000
  let left=NSScrollView(), right=NSScrollView()
  private(set) lazy var leftRuler=SQLInlineDiffRuler(scrollView:left)
  private(set) lazy var rightRuler=SQLInlineDiffRuler(scrollView:right)
  let leftText=SQLInlineDiffTextView(usingTextLayoutManager: true)
  let rightText=SQLInlineDiffTextView(usingTextLayoutManager: true)
  // Pane identities stay attached to original/edited SQL when their physical
  // positions swap, preserving diff direction, copy mapping and scroll state.
  private(set) var editedOnLeft = false
  private(set) var changeRows: [Int] = []
  private(set) var renderedRows = 0
  private(set) var truncated = false
  private(set) var renderCount = 0
  private var cachedComparison: SQLTextDiff.Comparison?
  private var cachedOriginal: String?
  private var cachedEdited: String?
  private var lastChangeIndex = -1
  private var pendingChangeRow: Int?
  private var preserveOrientationViewport = false
  private var sourceWidth: CGFloat = 0, targetWidth: CGFloat = 0
  private var syncing = false
  override var isFlipped: Bool { true }
  override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer=true;clipsToBounds=true
    for (scroll, text, label) in [(left, leftText, "Hedef SQL farkları"), (right, rightText, "Kaynak SQL farkları")] {
      scroll.wantsLayer=true;text.wantsLayer=true
      text.identifier = .init("sqlSourcePreview"); text.isEditable=false; text.isSelectable=true
      text.drawsBackground=false; text.font=StudioTheme.codeFont; text.textColor=StudioTheme.editorText
      text.isVerticallyResizable=true; text.isHorizontallyResizable=true; text.autoresizingMask=[]
      text.textContainerInset=NSSize(width: 10, height: 8)
      text.textContainer?.widthTracksTextView=false
      text.textContainer?.lineBreakMode = .byClipping
      // Consolas has nonzero leading. TextKit 2 otherwise adds it on top of
      // the fixed paragraph height, causing code and painted rows to drift.
      text.textLayoutManager?.usesFontLeading=false
      text.setAccessibilityLabel(label)
      scroll.documentView=text; scroll.borderType = .noBorder
      scroll.hasVerticalScroller=true; scroll.hasHorizontalScroller=true; scroll.autohidesScrollers=true
      scroll.contentView.postsBoundsChangedNotifications=true
      let ruler=scroll === left ? leftRuler:rightRuler
      ruler.textView=text;ruler.clipsToBounds=true;scroll.clipsToBounds=true
      ruler.ruleThickness=36;ruler.wantsLayer=true
      addSubview(ruler);addSubview(scroll)
      NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    setAccessibilityChildren([left,right])
    NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: StudioTheme.changed, object: nil)
    setContentHuggingPriority(.init(1), for: .horizontal); setContentHuggingPriority(.init(1), for: .vertical)
  }
  required init?(coder: NSCoder) { fatalError() }

  static func changeRows(in comparison: SQLTextDiff.Comparison) -> [Int] {
    var rows: [Int] = [], wasChanged=false
    for (index, line) in comparison.lines.prefix(maximumRows).enumerated() {
      if line.changed && !wasChanged { rows.append(index) }
      wasChanged=line.changed
    }
    return rows
  }
  func display(comparison: SQLTextDiff.Comparison, original: String, edited: String, changeIndex: Int, editedOnLeft: Bool = false) {
    if self.editedOnLeft != editedOnLeft {
      self.editedOnLeft=editedOnLeft
      setAccessibilityChildren(editedOnLeft ? [right,left]:[left,right])
      preserveOrientationViewport=true
      needsLayout=true
    }
    if cachedOriginal.map({!$0.utf8.elementsEqual(original.utf8)}) ?? true || cachedEdited.map({!$0.utf8.elementsEqual(edited.utf8)}) ?? true || cachedComparison != comparison {
      cachedComparison=comparison; cachedOriginal=original; cachedEdited=edited
      render(preservingViewport: false)
      lastChangeIndex=changeIndex
      let requested=changeIndex >= 0 && changeRows.indices.contains(changeIndex) ? changeIndex : 0
      if changeRows.indices.contains(requested) { pendingChangeRow=changeRows[requested] }
      needsLayout=true; revealPendingChange()
    } else if lastChangeIndex != changeIndex {
      lastChangeIndex=changeIndex
      if changeIndex >= 0, changeRows.indices.contains(changeIndex) {
        pendingChangeRow=changeRows[changeIndex]; revealPendingChange()
      }
    }
  }
  override func layout() {
    super.layout()
    let preserveViewport=preserveOrientationViewport,previouslySyncing=syncing
    preserveOrientationViewport=false
    let origins=[left.contentView.bounds.origin,right.contentView.bounds.origin]
    if preserveViewport {syncing=true}
    let half=max(0, (bounds.width-1)/2)
    let leading=NSRect(x: 0, y: 0, width: half, height: bounds.height)
    let trailing=NSRect(x: half+1, y: 0, width: max(0,bounds.width-half-1), height: bounds.height)
    for (scroll,ruler,pane) in [(left,leftRuler,editedOnLeft ? trailing:leading),(right,rightRuler,editedOnLeft ? leading:trailing)] {
      let width=min(pane.width,ruler.ruleThickness)
      ruler.frame=NSRect(x:pane.minX,y:pane.minY,width:width,height:pane.height)
      scroll.frame=NSRect(x:pane.minX+width,y:pane.minY,width:max(0,pane.width-width),height:pane.height)
    }
    resizeDocuments()
    if preserveViewport {
      // Retiling can backing-align clip bounds or reveal an offscreen selection.
      // Keep each SQL pane's viewport before applying explicit diff navigation.
      for (scroll,origin) in zip([left,right],origins) {
        scroll.contentView.scroll(to:origin);scroll.reflectScrolledClipView(scroll.contentView)
        (scroll === left ? leftRuler:rightRuler).needsDisplay=true
      }
      syncing=previouslySyncing
    }
    revealPendingChange()
  }
  override func draw(_ dirtyRect: NSRect) {
    StudioTheme.border.setFill(); NSRect(x: max(0,(bounds.width-1)/2), y: 0, width: 1, height: bounds.height).fill()
  }
  @objc private func scrolled(_ notification: Notification) {
    guard !syncing, let clip=notification.object as? NSClipView else { return }
    let previouslySyncing=syncing; syncing=true; defer { syncing=previouslySyncing }
    let other=clip === left.contentView ? right : left
    other.contentView.scroll(to: NSPoint(x: other.contentView.bounds.minX, y: clip.bounds.minY))
    other.reflectScrolledClipView(other.contentView)
    leftRuler.needsDisplay=true;rightRuler.needsDisplay=true
  }
  private func revealPendingChange() {
    guard let row=pendingChangeRow, left.contentView.bounds.height > 0, right.contentView.bounds.height > 0 else { return }
    pendingChangeRow=nil; syncing=true; defer { syncing=false }
    let desired=max(0, CGFloat(row)*Self.lineHeight+8-40)
    for scroll in [left, right] {
      let y=min(desired, max(0,(scroll.documentView?.bounds.height ?? 0)-scroll.contentView.bounds.height+scroll.contentView.contentInsets.bottom))
      scroll.contentView.scroll(to: NSPoint(x: -scroll.contentView.contentInsets.left, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
      (scroll === left ? leftRuler:rightRuler).needsDisplay=true
    }
  }
  private func resizeDocuments() {
    let previouslySyncing=syncing; syncing=true; defer { syncing=previouslySyncing }
    let contentHeight=CGFloat(renderedRows)*Self.lineHeight+16
    for (scroll, text, width) in [(left,leftText,sourceWidth),(right,rightText,targetWidth)] {
      let viewport=effectiveViewport(scroll)
      let size=NSSize(width: max(viewport.width,width), height: max(viewport.height,contentHeight))
      text.textContainer?.containerSize=NSSize(width: max(1,size.width-20), height: CGFloat.greatestFiniteMagnitude)
      text.setFrameSize(size); scroll.tile()
    }
    // Legacy scrollbars can consume height on only the wider side. Equal scroll
    // ranges keep the final code rows aligned even in the system's Always mode.
    let minimumViewport=min(effectiveViewport(left).height,effectiveViewport(right).height)
    let scrollableHeight=max(0,contentHeight-minimumViewport)
    for (scroll,text) in [(left,leftText),(right,rightText)] {
      text.setFrameSize(NSSize(width:text.frame.width,height:scrollableHeight+effectiveViewport(scroll).height))
    }
  }
  private func effectiveViewport(_ scroll: NSScrollView) -> NSSize {
    let insets=scroll.contentView.contentInsets, size=scroll.contentView.bounds.size
    return NSSize(width:max(0,size.width-insets.left-insets.right),height:max(0,size.height-insets.top-insets.bottom))
  }
  @objc private func themeChanged() { render(preservingViewport: true) }
  private func render(preservingViewport: Bool) {
    guard let comparison=cachedComparison, let original=cachedOriginal, let edited=cachedEdited else { return }
    let selections=[leftText.selectedRanges,rightText.selectedRanges], origins=[left.contentView.bounds.origin,right.contentView.bounds.origin]
    syncing=true
    var sizeA=0,sizeB=0, rows: [SQLTextDiff.Line] = []
    for line in comparison.lines.prefix(Self.maximumRows) {
      sizeA += (line.old?.utf16.count ?? 0)+1; sizeB += (line.new?.utf16.count ?? 0)+1
      guard sizeA <= Self.maximumCharacters, sizeB <= Self.maximumCharacters else { break }
      rows.append(line)
    }
    renderedRows=rows.count; truncated=rows.count < comparison.lines.count
    changeRows=Self.changeRows(in: comparison).filter { $0 < rows.count }
    sourceWidth=render(rows, source: original, old: true, text: leftText, scroll: left)
    targetWidth=render(rows, source: edited, old: false, text: rightText, scroll: right)
    resizeDocuments()
    for (index, scroll) in [left,right].enumerated() {
      let text=index == 0 ? leftText : rightText
      if preservingViewport { text.selectedRanges=selections[index]; scroll.contentView.scroll(to: origins[index]) }
      else { text.setSelectedRange(NSRange(location:0,length:0)); scroll.contentView.scroll(to:NSPoint(x:-scroll.contentView.contentInsets.left,y:0)) }
      scroll.reflectScrolledClipView(scroll.contentView); (scroll === left ? leftRuler:rightRuler).needsDisplay=true
    }
    syncing=false; renderCount += 1; needsDisplay=true
  }
  private func render(_ rows: [SQLTextDiff.Line], source: String, old: Bool, text: SQLInlineDiffTextView, scroll: NSScrollView) -> CGFloat {
    let attributed=NSMutableAttributedString(string: ""), colored=SQLSourceHighlighting.attributed(source)
    var offsets: [Int] = [], offset=0
    for line in source.components(separatedBy: "\n") { offsets.append(offset); offset += line.utf16.count+1 }
    var ranges: [NSRange] = [], copyRanges: [NSRange] = [], copySourceRanges:[NSRange?]=[], numbers: [Int?] = [], styles: [SQLInlineDiffRowStyle] = [], maximumWidth: CGFloat = 0
    let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=Self.lineHeight; paragraph.maximumLineHeight=Self.lineHeight
    paragraph.lineBreakMode = .byClipping; paragraph.tabStops=[]
    paragraph.defaultTabInterval=(" " as NSString).size(withAttributes:[.font:StudioTheme.codeFont]).width*4
    for row in rows {
      let number=old ? row.oldNumber : row.newNumber, value=old ? row.old : row.new
      let sourceRange=old ? row.oldSourceRange:row.newSourceRange,ending=old ? row.oldLineEnding:row.newLineEnding
      let meaningfulChanges=old ? row.oldChanges:row.newChanges,sideChanged=old ? row.oldChanged:row.newChanged
      let start=attributed.length
      if let value, let number, sourceRange != nil || offsets.indices.contains(number-1) {
        attributed.append(colored.attributedSubstring(from:sourceRange ?? NSRange(location:offsets[number-1],length:value.utf16.count)))
        maximumWidth=max(maximumWidth,(value as NSString).size(withAttributes:[.font:StudioTheme.codeFont,.paragraphStyle:paragraph]).width)
      }
      attributed.append(NSAttributedString(string: "\n", attributes:[.font:StudioTheme.codeFont,.foregroundColor:StudioTheme.editorText]))
      let style: SQLInlineDiffRowStyle = sideChanged ? (old ? .removed:.added) : row.changed && value == nil ? .placeholder:.unchanged
      ranges.append(NSRange(location: start, length: attributed.length-start)); numbers.append(number); styles.append(style)
      // The final aligned display row has a layout newline, even if the source does not.
      let hasEnding=ending.map {!$0.isEmpty} ?? (number.map {$0<offsets.count} ?? false)
      let copyLength=(value?.utf16.count ?? 0)+(hasEnding ? 1:0)
      copyRanges.append(NSRange(location:start,length:copyLength))
      if let number,let value {
        let range=sourceRange ?? NSRange(location:offsets[number-1],length:value.utf16.count)
        copySourceRanges.append(NSRange(location:range.location,length:range.length+(ending?.utf16.count ?? (hasEnding ? 1:0))))
      } else {copySourceRanges.append(nil)}
      if sideChanged {
        attributed.addAttribute(.backgroundColor, value: style.background, range: ranges.last!)
        if let value {
          if let meaningfulChanges {
            for raw in meaningfulChanges where raw.length>0 {
              let changed=(value as NSString).rangeOfComposedCharacterSequences(for:raw)
              attributed.addAttribute(.backgroundColor,value:old ? StudioTheme.color(0xF2BABA,0x784150):StudioTheme.color(0xACE0C4,0x3B7154),range:NSRange(location:start+changed.location,length:changed.length))
            }
          } else {
          let a=Array(value.utf16), b=Array(((old ? row.new : row.old) ?? "").utf16)
          var prefix=0,suffix=0
          while prefix < min(a.count,b.count), a[prefix] == b[prefix] { prefix += 1 }
          while suffix < min(a.count,b.count)-prefix, a[a.count-1-suffix] == b[b.count-1-suffix] { suffix += 1 }
          let raw=NSRange(location:prefix,length:a.count-prefix-suffix)
          if raw.length > 0 {
            let changed=(value as NSString).rangeOfComposedCharacterSequences(for:raw)
            attributed.addAttribute(.backgroundColor, value: old ? StudioTheme.color(0xF2BABA,0x784150) : StudioTheme.color(0xACE0C4,0x3B7154), range:NSRange(location:start+changed.location,length:changed.length))
          }
          }
        }
      }
    }
    attributed.addAttribute(.paragraphStyle, value: paragraph, range:NSRange(location:0,length:attributed.length))
    text.defaultParagraphStyle=paragraph; text.rowRanges=ranges; text.copyRanges=copyRanges;text.copySourceRanges=copySourceRanges;text.sourceSQL=source as NSString; text.sourceNumbers=numbers; text.rowStyles=styles
    text.textContentStorage?.textStorage?.setAttributedString(attributed); text.needsDisplay=true
    scroll.backgroundColor=StudioTheme.editorCanvas
    do {
      let ruler=scroll === left ? leftRuler:rightRuler
      ruler.numbers=numbers; ruler.styles=styles
      let digits=String(numbers.compactMap { $0 }.max() ?? 1).count
      ruler.ruleThickness=max(36, CGFloat(digits)*7+16)
    }
    return maximumWidth+30
  }
}
