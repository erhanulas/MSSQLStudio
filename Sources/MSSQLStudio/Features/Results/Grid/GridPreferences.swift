import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class ResultSplitView: NSSplitView {
  var hideDivider = false
  override var dividerThickness: CGFloat { hideDivider ? 0 : super.dividerThickness }
  override func drawDivider(in rect: NSRect) { if !hideDivider { StudioTheme.border.setFill(); rect.fill() } }
}
@MainActor enum GridPaging {
  static let choices = [10,100,250,500,1000,0]
  static var defaultSize: Int {
    guard UserDefaults.standard.object(forKey: "gridDefaultPageSize") != nil else { return 500 }
    let value = UserDefaults.standard.integer(forKey: "gridDefaultPageSize")
    return (0...1_000_000).contains(value) ? value : 500
  }
}
// Cell-based drawing avoids constructing NSTextField/Auto Layout trees for every visible row × column.
