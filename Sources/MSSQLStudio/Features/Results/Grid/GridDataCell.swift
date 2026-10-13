import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class GridDataCell: NSTextFieldCell {
  var isBit = false
  override init(textCell string: String) {
    super.init(textCell:string)
    font = StudioTheme.uiFont; lineBreakMode = .byTruncatingTail
    isEditable = false; isSelectable = false; isBordered = false; focusRingType = .none
  }
  required init(coder: NSCoder) { fatalError() }
  // Field editing copies the cell; preserve its bit presentation and read-only state.
  override func copy(with zone: NSZone? = nil) -> Any {
    let cell = GridDataCell(textCell: stringValue)
    cell.isBit = isBit; cell.font = font; cell.alignment = alignment
    cell.textColor = textColor; cell.lineBreakMode = lineBreakMode
    cell.isEditable = isEditable; cell.isSelectable = isSelectable
    cell.isBordered = isBordered; cell.isEnabled = isEnabled; cell.placeholderString = placeholderString
    return cell
  }
  override func draw(withFrame frame: NSRect, in view: NSView) {
    isHighlighted = false
    backgroundStyle = .normal
    super.draw(withFrame:frame,in:view)
  }
  override func drawInterior(withFrame frame: NSRect, in view: NSView) {
    if isBit && ["0","1"].contains(stringValue) {
      let box = NSRect(x:frame.midX-6,y:frame.midY-6,width:12,height:12)
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
    } else { super.drawInterior(withFrame:frame.insetBy(dx:6,dy:2),in:view) }
  }
}
