import AppKit
import CoreText
import SQLServerKit
import SwiftUI

struct StudioFormField<Content: View>: View {
  let title: String
  let labelWidth: CGFloat
  @ViewBuilder let content: () -> Content
  init(_ title: String, labelWidth: CGFloat = 150, @ViewBuilder content: @escaping () -> Content) {
    self.title = title; self.labelWidth = labelWidth; self.content = content
  }
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title).foregroundStyle(.secondary).frame(width: labelWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      content().frame(maxWidth: .infinity, alignment: .leading)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
/// Compact native actions share semantic colors, hit areas and theme handling.
// Shared, non-interactive hover names avoid the system tooltip's long initial delay.
