import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class GridDataCell: NSTextFieldCell {
  var isBit = false
  var searchTerm="" {didSet {if oldValue != searchTerm {highlightCache.removeAll();highlightOrder.removeAll()}}}
  private var highlightCache:[String:NSAttributedString]=[:]
  private var highlightOrder:[String]=[]
  private var highlightFont:NSFont?
  private var highlightColor:NSColor?
  private var highlightAlignment:NSTextAlignment?
  private var highlightLineBreak:NSLineBreakMode?
  override init(textCell string: String) {
    super.init(textCell:string)
    font = StudioTheme.uiFont; lineBreakMode = .byTruncatingTail
    isEditable = false; isSelectable = false; isBordered = false; focusRingType = .none
  }
  required init(coder: NSCoder) { fatalError() }
  override func fieldEditor(for controlView: NSView) -> NSTextView? {
    (controlView as? CopyTable)?.editingFieldEditor(formatter: formatter as? ResultCellFormatter)
  }
  // Field editing copies the cell; preserve its bit presentation and read-only state.
  override func copy(with zone: NSZone? = nil) -> Any {
    let cell = GridDataCell(textCell: stringValue)
    cell.isBit = isBit;cell.searchTerm=searchTerm; cell.font = font; cell.alignment = alignment
    cell.textColor = textColor; cell.lineBreakMode = lineBreakMode
    cell.isEditable = isEditable; cell.isSelectable = isSelectable
    cell.isBordered = isBordered; cell.isEnabled = isEnabled; cell.placeholderString = placeholderString
    cell.formatter = formatter
    return cell
  }
  func highlightedValue()->NSAttributedString {
      // Reuse bounded presentation values across redraws. Never cache source rows or edit drafts.
      if font != highlightFont || textColor != highlightColor || alignment != highlightAlignment || lineBreakMode != highlightLineBreak {
        highlightCache.removeAll();highlightOrder.removeAll()
        highlightFont=font;highlightColor=textColor;highlightAlignment=alignment;highlightLineBreak=lineBreakMode
      }
      let displayed=String(stringValue.prefix(1000))
      if let cached=highlightCache[displayed] {return cached}
      let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode=lineBreakMode;paragraph.alignment=alignment
      let value=NSMutableAttributedString(string:displayed,attributes:[.font:font ?? StudioTheme.uiFont,.foregroundColor:textColor ?? StudioTheme.text,.paragraphStyle:paragraph])
      let source=displayed as NSString
      var search=NSRange(location:0,length:source.length),count=0
      while search.length>0,count<100 {
        let range=source.range(of:searchTerm,options:[.caseInsensitive,.diacriticInsensitive],range:search)
        guard range.location != NSNotFound,range.length>0 else {break}
        value.addAttribute(.backgroundColor,value:NSColor.systemYellow.withAlphaComponent(0.4),range:range)
        let end=NSMaxRange(range);search=NSRange(location:end,length:source.length-end);count+=1
      }
      let result=NSAttributedString(attributedString:value)
      if highlightOrder.count>=64 {highlightCache.removeValue(forKey:highlightOrder.removeFirst())}
      highlightOrder.append(displayed);highlightCache[displayed]=result
      return result
  }
  override func draw(withFrame frame: NSRect, in view: NSView) {
    isHighlighted = false
    backgroundStyle = .normal
    super.draw(withFrame:frame,in:view)
  }
  override func drawInterior(withFrame frame: NSRect, in view: NSView) {
    if isBit && ["0","1"].contains(stringValue) {
      let box = NSRect(x:frame.midX-6,y:frame.midY-6,width:12,height:12)
      if !searchTerm.isEmpty,stringValue.range(of:searchTerm,options:[.caseInsensitive,.diacriticInsensitive]) != nil {
        NSColor.systemYellow.withAlphaComponent(0.4).setFill();box.insetBy(dx:-3,dy:-3).fill()
      }
      if stringValue == "0" {
        let outline = NSBezierPath(roundedRect:box.insetBy(dx:0.5,dy:0.5),xRadius:2,yRadius:2)
        NSColor.secondaryLabelColor.setStroke(); outline.lineWidth = 1; outline.stroke()
      } else {
        StudioTheme.success.setFill()
        NSBezierPath(roundedRect:box,xRadius:2.5,yRadius:2.5).fill()
        // Paint the value without enabling a control in the read-only results grid.
        let check=NSBezierPath()
        check.move(to:NSPoint(x:box.minX+2.5,y:box.midY))
        check.line(to:NSPoint(x:box.minX+5,y:box.minY+(view.isFlipped ? 8.5:3.5)))
        check.line(to:NSPoint(x:box.maxX-2.5,y:box.minY+(view.isFlipped ? 3.5:8.5)))
        check.lineWidth=1.5;check.lineCapStyle = .round;check.lineJoinStyle = .round
        (StudioTheme.dark ? NSColor(calibratedWhite:0.12,alpha:1):NSColor.white).setStroke();check.stroke()
      }
    } else if !searchTerm.isEmpty {
      highlightedValue().draw(in:frame.insetBy(dx:6,dy:2))
    } else { super.drawInterior(withFrame:frame.insetBy(dx:6,dy:2),in:view) }
  }
}
