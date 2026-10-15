import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor enum StudioTheme {
  static let changed = Notification.Name("MSSQLStudio.themeChanged")
  private static var appearanceObservation: NSKeyValueObservation?
  private static var paintedDark: Bool?
  static var mode: String { normalizedMode(UserDefaults.standard.string(forKey: "ssmsTheme") ?? "light") }
  static func normalizedMode(_ value: String) -> String {
    ["system", "light", "dark"].contains(value) ? value : "light"
  }
  static func usesDark(_ value: String, appearance: NSAppearance) -> Bool {
    switch normalizedMode(value) {
    case "dark": return true
    case "system": return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    default: return false
    }
  }
  static var dark: Bool { usesDark(mode, appearance: NSApplication.shared.effectiveAppearance) }
  static func color(_ light: UInt32, _ darkValue: UInt32) -> NSColor {
    let hex = dark ? darkValue : light
    return NSColor(
      srgbRed: CGFloat((hex >> 16) & 255) / 255,
      green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
  }
  static var canvas: NSColor { color(0xFFFFFF, 0x191D25) }
  static var chrome: NSColor { color(0xEBEFF5, 0x141820) }
  static var controlSurface: NSColor { color(0xFFFFFF, 0x2B3341) }
  static var controlBorder: NSColor { color(0xCAD3E0, 0x48576D) }
  static var success: NSColor { color(0x21814E, 0x7BC69C) }
  static var warning: NSColor { color(0xA86412, 0xF0B866) }
  static var danger: NSColor { color(0xC23B48, 0xEE8792) }
  static var explorerCanvas:NSColor {color(0xFFFFFF,0x1E1F22)}
  static var panel: NSColor { color(0xF4F6FA, 0x222833) }
  static var text: NSColor { color(0x263247, 0xE1E7F0) }
  static var border: NSColor { color(0xE1E6EF, 0x333C4A) }
  static var editorSelection:NSColor {dark ? NSColor(srgbRed:0.23,green:0.34,blue:0.50,alpha:1):NSColor(srgbRed:0.72,green:0.81,blue:0.97,alpha:1)}
  static var selection: NSColor { color(0xE8EFFF, 0x2C4062) }
  static var lineNumber: NSColor { color(0x008080, 0x4EC9B0) }
  static var editorCanvas: NSColor { color(0xFFFFFF,0x1E1E1E) }
  static var blockGuide: NSColor { color(0xD8DEE8, 0x414750) }
  static var activeBlockGuide: NSColor { accent.withAlphaComponent(0.75) }
  static var unusedVariable: NSColor { color(0x929292,0x808080) }
  static var undeclaredVariable:NSColor {color(0xFF0000,0xFF8080)}
  static var editorText: NSColor { color(0x000000,0xD4D4D4) }
  static var codeFont: NSFont {
    NSFont(name: "Consolas", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
  }
  static var uiFont: NSFont { .systemFont(ofSize: 12) }
  static var accent: NSColor { color(0x3869D6, 0x8EAEFF) }
  static var muted: NSColor { color(0x5E6D82, 0x9DAAC0) }
  static var stripe: NSColor { color(0xFAFBFD, 0x1C212B) }
  static var resultCanvas: NSColor { color(0xFFFFFF, 0x1E1F22) }
  static var resultHeader: NSColor { color(0xFFFFFF, 0x252830) }
  static var resultStripe: NSColor { color(0xFBFCFE, 0x22252B) }
  static var resultGutter: NSColor { color(0xFAFBFD, 0x22252B) }
  static var resultBorder: NSColor { color(0xE9EDF3, 0x343942) }
  static var resultFilteredHeader: NSColor { color(0xF0F6FF, 0x283952) }
  static func surface(_ view: NSView, card: Bool = false, chrome: Bool = false, sidebar: Bool = false) {
    view.identifier = .init(sidebar ? "studio.sidebar" : card ? "studio.card" : chrome ? "studio.frame" : "studio.chrome")
    view.wantsLayer = true
    paintSurface(view)
  }
  static var statusCanvas:NSColor {color(0xEEF3FC,0x242D40)}
  static func statusSurface(_ view:NSView) {view.identifier = .init("studio.status");view.wantsLayer=true;paintSurface(view)}
  static func resultSurface(_ view: NSView) {
    view.identifier = .init("studio.results")
    view.wantsLayer = true
    paintSurface(view)
  }
  private static func paintSurface(_ view: NSView) {
    view.layer?.backgroundColor = (view.identifier?.rawValue == "studio.status" ? statusCanvas : view.identifier?.rawValue == "studio.results" ? resultCanvas : view.identifier?.rawValue == "studio.sidebar" ? explorerCanvas : view.identifier?.rawValue == "studio.card" ? canvas : view.identifier?.rawValue == "studio.frame" ? chrome : panel).cgColor
    if ["studio.card", "studio.sidebar"].contains(view.identifier?.rawValue ?? "") {
      view.layer?.cornerRadius = 10
      view.layer?.borderWidth = 1
      view.layer?.borderColor = border.cgColor
      view.layer?.masksToBounds = true
    }
  }
  static func syntax(_ style: TSQL.SyntaxStyle) -> NSColor {
    switch style {
    case .keyword: return color(0x0000FF, 0x6CA0FF)
    case .string: return color(0xFF0000, 0xFF8080)
    case .comment: return color(0x008000, 0x6A9955)
    case .function: return color(0xFF00FF, 0xE88BFF)
    case .systemObject: return color(0x008000, 0x72C77B)
    case .procedure: return color(0x800000, 0xD88585)
    case .operatorSymbol: return color(0x808080, 0xB4B4B4)
    case .plain: return editorText
    }
  }
  static func start() {
    if NSFont(name: "Consolas", size: 13) == nil {
      let path = "/Applications/Microsoft Word.app/Contents/Resources/DFonts/Consola.ttf"
      if FileManager.default.fileExists(atPath: path) {
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, nil)
      }
    }
    apply(UserDefaults.standard.string(forKey: "ssmsTheme") ?? "light")
  }
  static func apply(_ value: String) {
    let mode = normalizedMode(value)
    UserDefaults.standard.set(mode, forKey: "ssmsTheme")
    let application = NSApplication.shared
    if appearanceObservation == nil {
      appearanceObservation = application.observe(\.effectiveAppearance) { _, _ in
        Task { @MainActor in refreshSystemAppearance() }
      }
    }
    // nil inherits macOS appearance; explicit light/dark remains a user override.
    application.appearance = mode == "system" ? nil : NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
    repaint()
  }
  private static func refreshSystemAppearance() {
    guard mode == "system", paintedDark != dark else { return }
    repaint()
  }
  private static func repaint() {
    paintedDark = dark
    for window in NSApp.windows {
      window.backgroundColor = chrome
      if let view = window.contentView { decorate(view) }
    }
    NotificationCenter.default.post(name: changed, object: nil)
  }
  static func decorate(_ view: NSView) {
    if let tab=view as? QueryTabSurface {tab.configure(active:tab.isActiveTab)}
    if let button = view as? StudioToolbarButton { button.refreshStyle() }
    if let button = view as? QueryTabCloseButton {button.refreshStyle()}
    if let button = view as? StudioResultTabButton { button.refreshStyle() }
    if let label = view as? NSTextField, label.identifier?.rawValue == "studio.mutedLabel" { label.textColor = muted }
    // AppKit owns private text/layout views inside controls and the shared field editor.
    // Preserve their native typography and appearance when updating the SQL workspace.
    if view is NSTextField || view is NSPopUpButton || view is NSSegmentedControl { return }
    if let table = view as? NSTableView {
      table.backgroundColor = table is NSOutlineView ? explorerCanvas : table is CopyTable ? resultCanvas : canvas
      // Gridless SwiftUI lists own their separators; setting gridColor can inspect unbuilt cells.
      if !table.gridStyleMask.isEmpty {table.gridColor = table is CopyTable ? resultBorder : border}
      table.headerView?.needsDisplay = true
      table.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
    } else if let scroll = view as? NSScrollView {
      scroll.backgroundColor = scroll.documentView is NSOutlineView ? explorerCanvas : scroll.documentView is CopyTable || scroll.identifier?.rawValue == "studio.results" ? resultCanvas : scroll.identifier?.rawValue == "studio.chrome" ? panel : canvas
    } else if let textView = view as? NSTextView, !textView.isFieldEditor, !(textView is SQLTextView), !["sqlSourcePreview","agentCommandEditor"].contains(textView.identifier?.rawValue ?? "") {
      textView.backgroundColor = canvas
      textView.textColor = text
      textView.font = codeFont
    }
    if view.identifier?.rawValue.hasPrefix("studio.") == true { paintSurface(view) }
    for child in view.subviews { decorate(child) }
  }
}

/// Fenced SQL is selectable, themed text. Markdown never executes code or loads images.
