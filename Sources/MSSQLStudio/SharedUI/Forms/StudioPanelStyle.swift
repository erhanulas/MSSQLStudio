import AppKit
import CoreText
import SQLServerKit
import SwiftUI

struct StudioActionButton: View {
  let title: String
  let icon: String
  let tint: Color?
  let action: () -> Void
  @Environment(\.isEnabled) private var enabled
  @Environment(\.studioPrimaryAction) private var primary
  init(_ title: String, icon: String, tint: Color? = nil, action: @escaping () -> Void) {
    self.title = title; self.icon = icon; self.tint = tint; self.action = action
  }
  var body: some View {
    Button(action: action) {
      Label {
        Text(title)
      } icon: {
        if let tint, !primary { Image(systemName: icon).foregroundStyle(enabled ? tint : Color.secondary) }
        else { Image(systemName: icon) }
      }
    }.accessibilityLabel(title).studioHelp(title)
  }
}
private struct StudioPrimaryActionKey: EnvironmentKey {
  static let defaultValue = false
}
private extension EnvironmentValues {
  var studioPrimaryAction: Bool {
    get { self[StudioPrimaryActionKey.self] }
    set { self[StudioPrimaryActionKey.self] = newValue }
  }
}
struct StudioPrimaryButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    StudioButtonSurface(configuration: configuration, primary: true)
  }
}
struct StudioSecondaryButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    StudioButtonSurface(configuration: configuration, primary: false)
  }
}
private struct StudioButtonSurface: View {
  let configuration: ButtonStyleConfiguration
  let primary: Bool
  @Environment(\.isEnabled) private var enabled
  @Environment(\.controlSize) private var size
  @Environment(\.colorScheme) private var colorScheme
  @State private var hovered = false
  private var compact: Bool { size == .small || size == .mini }
  private var ink: Color {
    enabled ? (primary ? Color(nsColor: StudioTheme.dark ? StudioTheme.canvas : .white) : Color(nsColor: StudioTheme.text)) : Color.secondary
  }
  var body: some View {
    let _ = colorScheme // Recompute semantic tokens when an open form changes theme.
    return configuration.label
      .font(.system(size: compact ? 11 : 12, weight: .medium))
      .symbolRenderingMode(.hierarchical)
      .padding(.horizontal, primary ? 14 : compact ? 8 : 10)
      .padding(.vertical, compact ? 4 : 6)
      .foregroundStyle(ink)
      .frame(minHeight: compact ? 24 : 30)
      .background {
        RoundedRectangle(cornerRadius: StudioMetrics.controlRadius).fill(
          LinearGradient(colors: primary && enabled
            ? [Color(nsColor: StudioTheme.accent), Color(nsColor: StudioTheme.accent).opacity(0.88)]
            : [Color(nsColor: StudioTheme.controlSurface), Color(nsColor: StudioTheme.controlSurface)],
            startPoint: .top, endPoint: .bottom))
          .overlay(RoundedRectangle(cornerRadius: StudioMetrics.controlRadius).fill(Color(nsColor: StudioTheme.accent).opacity(enabled && (hovered || configuration.isPressed) ? configuration.isPressed ? 0.14 : 0.06 : 0)))
      }
      .overlay(RoundedRectangle(cornerRadius: StudioMetrics.controlRadius).strokeBorder(
        primary && enabled ? Color.white.opacity(0.16) : Color(nsColor: hovered && enabled ? StudioTheme.accent : StudioTheme.controlBorder).opacity(enabled ? 0.8 : 0.4)).allowsHitTesting(false))

      .opacity(enabled ? 1 : 0.5)
      .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.controlRadius))
      .environment(\.studioPrimaryAction, primary)
      .onHover { hovered = $0 }
      .animation(.easeOut(duration: 0.10), value: hovered)
  }
}
struct StudioGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: StudioMetrics.gap) {
      configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(nsColor: StudioTheme.text))
      configuration.content.frame(maxWidth: .infinity, alignment: .leading)
    }.studioCard()
  }
}
struct StudioNavigationItem: View {
  let title: String
  let icon: String
  let selected: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 20)
          .foregroundStyle(Color(nsColor: selected ? StudioTheme.accent : StudioTheme.muted))
        Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
        Spacer(minLength: 0)
      }.padding(.horizontal, 8).padding(.vertical, 6)
        .foregroundStyle(Color(nsColor: StudioTheme.text))
        .background(selected ? Color(nsColor: StudioTheme.selection) : .clear, in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius))
        .overlay(alignment: .leading) {
          if selected { Capsule().fill(Color(nsColor: StudioTheme.accent)).frame(width: 3, height: 16) }
        }.contentShape(Rectangle())
    }.buttonStyle(.plain).studioHelp(title).accessibilityLabel(title)
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
struct StudioEmptyState: View {
  let title: String
  let icon: String
  let detail: String
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: icon).font(.system(size: 22, weight: .regular)).foregroundStyle(.tint)
      Text(title).font(.system(size: 13, weight: .medium))
      Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: StudioTheme.border)))
  }
}
struct StudioPanelHeading: View {
  let title: String
  let icon: String
  let subtitle: String
  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: icon).font(.system(size: 17, weight: .medium))
        .foregroundStyle(Color(nsColor: StudioTheme.accent))
        .frame(width: 32, height: 32)
        .background(Color(nsColor: StudioTheme.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: StudioMetrics.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: StudioMetrics.cardRadius).strokeBorder(Color(nsColor: StudioTheme.accent).opacity(0.12)))
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: StudioMetrics.headingFont, weight: .semibold))
        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }.fixedSize(horizontal: false, vertical: true)
  }
}
struct StudioPanelStyle: ViewModifier {
  @State private var revision = 0
  func body(content: Content) -> some View {
    content
      .textFieldStyle(.roundedBorder)
      .buttonStyle(StudioSecondaryButton())
      .groupBoxStyle(StudioGroupBoxStyle())
      .font(.system(size: 12))
      .tint(Color(nsColor: StudioTheme.accent))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color(nsColor: StudioTheme.panel))
      .onReceive(NotificationCenter.default.publisher(for: StudioTheme.changed)) { _ in revision += 1 }
      .environment(\.colorScheme, revision >= 0 && StudioTheme.dark ? .dark : .light)
      .overlay(alignment: .top) { Rectangle().fill(Color(nsColor: StudioTheme.border)).frame(height: 1).allowsHitTesting(false) }
  }
}
private struct StudioCardStyle: ViewModifier {
  let padding: CGFloat
  @Environment(\.colorScheme) private var colorScheme
  func body(content: Content) -> some View {
    let _ = colorScheme
    return content.padding(padding).background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: StudioMetrics.cardRadius))
      .overlay(RoundedRectangle(cornerRadius: StudioMetrics.cardRadius).strokeBorder(Color(nsColor: StudioTheme.border)))
  }
}
extension View {
  func studioPanel() -> some View { modifier(StudioPanelStyle()) }
  func studioCard(padding: CGFloat = StudioMetrics.gap) -> some View {
    modifier(StudioCardStyle(padding:padding))
  }
  func studioEditor() -> some View {
    padding(8).background(Color(nsColor: StudioTheme.editorCanvas), in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: StudioTheme.border)))
  }
}
