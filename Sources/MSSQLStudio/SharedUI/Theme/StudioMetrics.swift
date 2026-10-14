import AppKit

/// Shared desktop density. Content panes grow; controls and headings do not.
enum StudioMetrics {
  static let micro: CGFloat = 4
  static let small: CGFloat = 8
  static let gap: CGFloat = 12
  static let inset: CGFloat = 16
  static let controlHeight: CGFloat = 26
  static let choiceRowHeight: CGFloat = 24
  static let toolbarHeight: CGFloat = 32
  static let controlRadius: CGFloat = 6
  static let cardRadius: CGFloat = 8
  static let bodyFont: CGFloat = 12
  static let detailFont: CGFloat = 11
  static let headingFont: CGFloat = 16
  static let icon: CGFloat = 16
}

enum ExplorerDensity: String, CaseIterable {
  case compact, comfortable
  static let key = "explorerRowDensity"
  static let changed = Notification.Name("explorerDensityChanged")
  var title: String { self == .compact ? "Kompakt" : "Rahat" }
  var rowHeight: CGFloat { self == .compact ? 24 : 28 }
  static func current(in defaults: UserDefaults = .standard) -> Self {
    Self(rawValue: defaults.string(forKey: key) ?? "") ?? .compact
  }
}
