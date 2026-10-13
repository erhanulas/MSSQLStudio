import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor class StudioRowView: NSTableRowView {
  override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
  override func drawSelection(in dirtyRect: NSRect) {
    guard selectionHighlightStyle != .none else { return }
    StudioTheme.selection.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 5, yRadius: 5).fill()
    StudioTheme.accent.withAlphaComponent(0.45).setFill()
    NSBezierPath(roundedRect: NSRect(x: 3, y: 4, width: 2, height: max(0, bounds.height - 8)), xRadius: 1, yRadius: 1).fill()
  }
}

/// One label column for form controls; long labels wrap instead of shifting fields.
