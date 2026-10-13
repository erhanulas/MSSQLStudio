import AppKit
import SwiftUI
import SQLServerKit

@MainActor final class SQLEditorScrollView: NSScrollView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    let local = convert(point, from: superview)
    // An empty NSTextView may not expose a text hit region before its first edit.
    // The entire document viewport remains an editing surface; keep rulers/scrollers native.
    if contentView.frame.contains(local), !(hit is NSScroller), let text = documentView as? SQLTextView {
      return text
    }
    return hit
  }
}
@MainActor final class SQLClipView: NSClipView {
  var allowsHorizontalMovement = false
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var rect = super.constrainBoundsRect(proposedBounds)
    if !allowsHorizontalMovement { rect.origin.x = 0 }
    return rect
  }
}
/// A mouse-transparent decoration above the native text layers. Selection matches
/// must not edit text attributes or invalidate TextKit's cached paragraph fragments.
@MainActor final class OccurrenceHighlights: NSView {
  weak var editor: NSTextView?
  var findRanges:[NSRange]=[] {didSet {if oldValue != findRanges {needsDisplay=true}}}
  var blockRanges:[NSRange]=[] {didSet {if oldValue != blockRanges {needsDisplay=true}}}
  var ranges:[NSRange]=[] {didSet {if oldValue != ranges {needsDisplay=true}}}
  override var isFlipped: Bool {true}
  override func hitTest(_ point:NSPoint) -> NSView? {nil}
  func highlightRects(in dirtyRect:NSRect) -> [NSRect] {
    guard let editor,let content=editor.textContentStorage,let layout=editor.textLayoutManager else {return []}
    var rects:[NSRect]=[]
    let viewport=layout.textViewportLayoutController.viewportRange
    for range in ranges+blockRanges+findRanges where range != editor.selectedRange() {
      guard NSMaxRange(range) <= (content.textStorage?.length ?? 0),
        let start=content.location(content.documentRange.location,offsetBy:range.location),
        let end=content.location(start,offsetBy:range.length),
        let textRange=NSTextRange(location:start,end:end),
        viewport == nil || viewport!.intersects(textRange) else {continue}
      layout.enumerateTextSegments(in:textRange,type:.standard,options:[]) { _,rect,_,_ in
        let frame=self.convert(rect.offsetBy(dx:editor.textContainerOrigin.x,dy:editor.textContainerOrigin.y),from:editor)
        if frame.intersects(dirtyRect) {rects.append(frame)}
        return true
      }
    }
    return rects
  }
  override func draw(_ dirtyRect:NSRect) {
    NSColor.systemYellow.withAlphaComponent(0.25).setFill()
    for rect in highlightRects(in:dirtyRect) {NSBezierPath(roundedRect:rect,xRadius:2,yRadius:2).fill()}
  }
}
@MainActor final class GutterAction: NSAccessibilityElement {
  var perform: (() -> Void)?
  override func accessibilityPerformPress() -> Bool { perform?(); return true }
}
@MainActor final class LineNumbers: NSView, NSViewToolTipOwner {
  weak var scrollView: NSScrollView?
  var ruleThickness: CGFloat = 44
  static func width(lineCount:Int,font:NSFont) -> CGFloat {
    max(44,ceil((String(max(1,lineCount)) as NSString).size(withAttributes:[.font:font]).width)+28)
  }
  var sourceOffset: ((Int) -> Int)?
  var sourceText: (() -> String)?
  var lineNumber: ((Int) -> Int)?
  var foldRegions: (() -> [SQLFolding.Region])?
  var collapsed: ((SQLFolding.Region) -> Bool)?
  var toggle: ((SQLFolding.Region) -> Void)?
  var selectLine: ((NSRange) -> Void)?
  private var hits: [(CGFloat, NSRange, SQLFolding.Region?)] = []
  init(scrollView: NSScrollView) {
    self.scrollView = scrollView; super.init(frame:.zero)
    setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Satır numaraları ve bloklar")
  }
  private func updateAccessibility() {
    guard let window else { return }
    let original = (sourceText?() ?? "") as NSString
    var children: [GutterAction] = []
    for (top, range, region) in hits {
      let number = lineNumber?(range.location) ?? 1
      let line = GutterAction(); line.setAccessibilityRole(.button); line.setAccessibilityEnabled(true); line.setAccessibilityParent(self)
      line.setAccessibilityLabel("\(number). satırı seç")
      line.setAccessibilityFrame(window.convertToScreen(convert(NSRect(x:0,y:top,width:ruleThickness-20,height:18),to:nil)))
      line.perform = { [weak self] in self?.selectLine?(range) }; children.append(line)
      if let region, NSMaxRange(region.hidden) <= original.length {
        let fold = GutterAction(); fold.setAccessibilityRole(.button); fold.setAccessibilityEnabled(true); fold.setAccessibilityParent(self)
        fold.setAccessibilityLabel("Satır \(number): Bloğu \(collapsed?(region) == true ? "aç" : "daralt")")
        fold.setAccessibilityFrame(window.convertToScreen(convert(NSRect(x:ruleThickness-20,y:top,width:20,height:18),to:nil)))
        fold.perform = { [weak self] in self?.toggle?(region) }; children.append(fold)
      }
    }
    setAccessibilityChildren(children)
  }
  required init?(coder: NSCoder) { fatalError() }
  func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
    guard let region = hits.first(where: { point.y >= $0.0 && point.y < $0.0+18 })?.2 else { return "Satırın tamamını seç" }
    let source = (sourceText?() ?? "") as NSString
    let range = NSRange(location:region.header.location,length:min(4000,NSMaxRange(region.hidden)-region.header.location))
    return "\(collapsed?(region) == true ? "+ Bloğu aç" : "− Bloğu daralt") (⌥⌘[)\n" + source.substring(with:range)
  }
  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow,from:nil)
    guard let hit = hits.first(where: { point.y >= $0.0 && point.y < $0.0+18 }) else { return }
    if point.x >= ruleThickness-20, let region = hit.2 { toggle?(region) }
    else { selectLine?(hit.1) }
  }
  weak var editor: NSTextView?
  override var isFlipped: Bool { true }
  override func draw(_ rect: NSRect) {
    hits.removeAll(); removeAllToolTips()
    defer { updateAccessibility() }
    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }; bounds.clip()
    StudioTheme.panel.setFill()
    NSIntersectionRect(rect, bounds).fill()
    guard let editor, let clip = scrollView?.contentView else { return }
    guard let layout = editor.textLayoutManager, let content = editor.textContentStorage else {
      return
    }
    let font = StudioTheme.codeFont
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: StudioTheme.lineNumber,
    ]
    let offset = clip.bounds.minY
    let source = editor.string as NSString
    var number: Int?
    var lastBaseline: CGFloat?
    var lastHeight: CGFloat = 18
    var reachedEnd = false
    var drewEmptyLine = false
    let start = layout.textViewportLayoutController.viewportRange?.location
    layout.enumerateTextLayoutFragments(
      from: start, options: [.ensuresLayout, .ensuresExtraLineFragment]
    ) { fragment in
      let frame = fragment.layoutFragmentFrame
      if frame.minY > offset + clip.bounds.height { return false }
      if number == nil {
        let location = content.offset(
          from: content.documentRange.location, to: fragment.rangeInElement.location)
        number =
          source.substring(to: max(0, min(source.length, location))).filter { $0 == "\n" }.count + 1
      }
      reachedEnd =
        fragment.rangeInElement.endLocation.compare(content.documentRange.endLocation)
        == .orderedSame
      for line in fragment.textLineFragments {
        let visibleOffset = content.offset(from:content.documentRange.location,to:fragment.rangeInElement.location) + line.characterRange.location
        let original = (sourceText?() ?? editor.string) as NSString
        let originalOffset = max(0,min(original.length,sourceOffset?(visibleOffset) ?? visibleOffset))
        let originalLine = original.lineRange(for:NSRange(location:originalOffset,length:0))
        let lineNumber = lineNumber?(originalOffset) ?? 1
        let value = String(lineNumber) as NSString
        let size = value.size(withAttributes: attrs)
        let baseline =
          frame.minY + line.typographicBounds.minY + line.glyphOrigin.y
          + editor.textContainerInset.height - offset
        lastBaseline = baseline
        lastHeight = max(18, line.typographicBounds.height)
        drewEmptyLine = line.characterRange.length == 0
        value.draw(
          at: NSPoint(x: ruleThickness - size.width - 25, y: baseline - font.ascender),
          withAttributes: attrs)
        let region = foldRegions?().first(where: { $0.header.location == originalLine.location })
        let top = baseline-font.ascender
        hits.append((top,originalLine,region))
        if let region {
          addToolTip(NSRect(x:ruleThickness-20,y:top,width:20,height:18),owner:self,userData:nil)
          let isCollapsed=collapsed?(region) == true
          let box=NSRect(x:ruleThickness-18,y:top+2,width:13,height:13)
          (isCollapsed ? StudioTheme.accent : StudioTheme.editorCanvas).setFill()
          let path=NSBezierPath(roundedRect:box,xRadius:2,yRadius:2);path.fill()
          (isCollapsed ? StudioTheme.accent : NSColor.secondaryLabelColor).setStroke();path.lineWidth=1;path.stroke()
          (isCollapsed ? StudioTheme.editorCanvas : NSColor.secondaryLabelColor).setStroke()
          let lines=NSBezierPath();lines.move(to:NSPoint(x:box.minX+3,y:box.midY));lines.line(to:NSPoint(x:box.maxX-3,y:box.midY))
          if isCollapsed {lines.move(to:NSPoint(x:box.midX,y:box.minY+3));lines.line(to:NSPoint(x:box.midX,y:box.maxY-3))}
          lines.lineWidth=isCollapsed ? 1.5 : 1;lines.stroke()
        }
        number! += 1
      }
      return true
    }
    // TextKit may omit the trailing empty paragraph from viewport enumeration.
    if (source.length == 0 || (reachedEnd && editor.string.hasSuffix("\n"))) && !drewEmptyLine {
      let value = String(lineNumber?(((sourceText?() ?? editor.string) as NSString).length) ?? 1) as NSString
      let size = value.size(withAttributes: attrs)
      let baseline =
        lastBaseline.map { $0 + lastHeight }
        ?? (editor.textContainerInset.height + font.ascender - offset)
      let original = (sourceText?() ?? editor.string) as NSString
      hits.append((baseline-font.ascender,original.lineRange(for:NSRange(location:original.length,length:0)),nil))
      value.draw(
        at: NSPoint(x: ruleThickness - size.width - 25, y: baseline - font.ascender),
        withAttributes: attrs)
    }
  }
}
