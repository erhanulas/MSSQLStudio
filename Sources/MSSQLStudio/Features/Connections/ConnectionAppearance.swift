import AppKit
import CoreText
import SQLServerKit
import SwiftUI

extension ServerAppearance {
  @MainActor var color: NSColor {
    let value = UInt32(effectiveColorHex, radix: 16) ?? 0x7C3AED
    return NSColor(
      srgbRed: CGFloat((value >> 16) & 255) / 255,
      green: CGFloat((value >> 8) & 255) / 255,
      blue: CGFloat(value & 255) / 255, alpha: 1)
  }
}

@MainActor final class ConnectionTreeRow: StudioRowView {
  var color = NSColor.systemIndigo
  var isServer = false
  override func drawBackground(in dirtyRect: NSRect) {
    super.drawBackground(in: dirtyRect)
    if isServer {
      color.withAlphaComponent(0.1).setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
    stripe(in: dirtyRect)
  }
  override func drawSelection(in dirtyRect: NSRect) {
    super.drawSelection(in: dirtyRect)
    stripe(in: dirtyRect)
  }
  private func stripe(in dirtyRect: NSRect) {
    color.setFill()
    NSBezierPath(
      rect: NSRect(x: bounds.minX, y: bounds.minY, width: 3, height: bounds.height).intersection(
        dirtyRect)
    ).fill()
  }
}

struct ConnectionAppearanceFields: View {
  @Binding var appearance: ServerAppearance
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Picker(
          "Ortam",
          selection: Binding(
            get: { appearance.environment },
            set: { value in
              appearance.environment = value
              if value != .custom {appearance.customLabel=""}
              appearance.colorHex = nil
            })
        ) {
          ForEach(ServerEnvironment.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Button("İşareti Kaldır") { appearance = ServerAppearance() }
          .disabled(!appearance.isMarked)
      }
      HStack {
        ColorPicker(
          "Renk",
          selection: Binding(
            get: { Color(nsColor: appearance.color) },
            set: { color in
              guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
              let hex = String(
                format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
              if hex != appearance.effectiveColorHex { appearance.colorHex = hex }
            }), supportsOpacity: false
        ).fixedSize()
        TextField(
          "RRGGBB",
          text: Binding(
            get: { appearance.colorHex ?? appearance.effectiveColorHex },
            set: { value in
              if value != (appearance.colorHex ?? appearance.effectiveColorHex) {
                appearance.colorHex = value
              }
            })
        )
        .frame(width: 80).studioHelp("Altı haneli RGB renk kodu; örneğin D92D20.")
        StudioActionButton("Varsayılan", icon:"arrow.counterclockwise", tint:.accentColor) { appearance.colorHex = nil }
      }
      if appearance.environment == .custom {
        TextField("Özel ortam etiketi", text: $appearance.customLabel)
      }
      HStack(spacing: 8) {
        Image(
          systemName: appearance.environment == .live || appearance.environment == .attention
            ? "exclamationmark.triangle.fill" : "circle.fill"
        )
        .foregroundStyle(Color(nsColor: appearance.color))
        Text(appearance.isMarked ? appearance.badge : "Ortam işareti yok").fontWeight(.semibold)
        Text("Bağlantı ve sorgu alanında görünür").foregroundStyle(.secondary)
      }.font(.caption).padding(7).frame(maxWidth: .infinity, alignment: .leading)
        .background(
          Color(nsColor: appearance.color).opacity(appearance.isMarked ? 0.12 : 0.04),
          in: RoundedRectangle(cornerRadius: 5))
    }
  }
}
// Shared native design tokens. Explicit surfaces preserve semantic typography and colors.
