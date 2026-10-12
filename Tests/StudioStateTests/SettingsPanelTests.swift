import AppKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct SettingsPanelTests {
  private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
  private func window(_ section: SettingsSection) -> (NSWindow, NSHostingController<SettingsPanel>) {
    let state = StudioState(); state.historyEnabled = false; state.recoveryEnabled = false
    let host = NSHostingController(rootView: SettingsPanel(state: state, initialTab: section)); host.sizingOptions = []
    let window = NSWindow(contentViewController: host); window.isReleasedWhenClosed = false
    window.setFrame(window.frameRect(forContentRect: NSRect(x: -2000, y: -2000, width: 780, height: 600)), display: true)
    host.view.frame = NSRect(x: 0, y: 0, width: 780, height: 600)
    return (window, host)
  }
  private func settle(_ host: NSHostingController<SettingsPanel>) async throws {
    try await Task.sleep(for: .milliseconds(90))
    host.view.layoutSubtreeIfNeeded(); host.view.displayIfNeeded()
  }
  @Test func allSixPagesUseNativeNavigationAndFitMinimumInBothThemes() async throws {
    _ = NSApplication.shared
    let oldTheme = UserDefaults.standard.string(forKey: "ssmsTheme")
    defer { StudioTheme.apply(oldTheme ?? "light") }
    for theme in ["light", "dark"] {
      StudioTheme.apply(theme)
      for section in SettingsSection.allCases {
        let (window, host) = window(section)
        window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
        defer { window.close() }
        try await settle(host)
        #expect(host.view.bounds.size == NSSize(width: 780, height: 600))
        let views = descendants(host.view)
        let tabs = try #require(views.compactMap { $0 as? NSTabView }.first)
        #expect(tabs.numberOfTabViewItems == 6)
        #expect(tabs.tabViewItems.map(\.label) == SettingsSection.allCases.map(\.title))
        #expect(tabs.selectedTabViewItem?.label == section.title)
        let tabRect = host.view.convert(tabs.bounds, from: tabs)
        #expect(tabRect.minX >= 0 && tabRect.maxX <= 780 && tabRect.minY >= 55 && tabRect.maxY <= 530)
        for control in views.compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
          let rect = host.view.convert(control.bounds, from: control)
          #expect(rect.minX >= -1 && rect.maxX <= 781, "\(theme) \(section) horizontal control overflow: \(rect)")
        }
        if section == .shortcuts {
          let capture = views.compactMap { $0 as? NSButton }.filter { $0.title.contains("Değiştir") }
          #expect(capture.count == GridShortcuts.Action.allCases.count)
          #expect(capture.allSatisfy { !($0.toolTip ?? "").isEmpty && !($0.accessibilityLabel() ?? "").isEmpty })
        }
        let rep = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
        host.view.cacheDisplay(in: host.view.bounds, to: rep)
        let corner = try #require(rep.colorAt(x: 5, y: 5)?.usingColorSpace(.deviceRGB))
        let brightness = (corner.redComponent + corner.greenComponent + corner.blueComponent) / 3
        #expect(theme == "dark" ? brightness < 0.4 : brightness > 0.7)
        var colors = Set<Int>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: 16) {
          for x in stride(from: 0, to: rep.pixelsWide, by: 16) {
            if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
              colors.insert((Int(c.redComponent * 255) << 16) | (Int(c.greenComponent * 255) << 8) | Int(c.blueComponent * 255))
            }
          }
        }
        #expect(colors.count > 20, "A populated, correctly themed Settings surface must be drawn")
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/mssql-settings-\(section.rawValue)-\(theme).png"))
      }
    }
  }
  @Test func unsavedRepositorySurvivesNativeTabNavigationAndThemeRefresh() async throws {
    _ = NSApplication.shared
    let oldTheme = UserDefaults.standard.string(forKey: "ssmsTheme")
    let oldRepository = UserDefaults.standard.object(forKey: "githubUpdateRepository")
    defer {
      StudioTheme.apply(oldTheme ?? "light")
      if let oldRepository { UserDefaults.standard.set(oldRepository, forKey: "githubUpdateRepository") }
      else { UserDefaults.standard.removeObject(forKey: "githubUpdateRepository") }
    }
    UserDefaults.standard.set("erhanulas/MSSQLStudio", forKey: "githubUpdateRepository")
    StudioTheme.apply("light")
    let (window, host) = window(.updates); defer { window.close() }
    try await settle(host)
    func repositoryField() throws -> NSTextField {
      try #require(descendants(host.view).compactMap { $0 as? NSTextField }.first { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor })
    }
    let field = try repositoryField()
    #expect(field.stringValue == "erhanulas/MSSQLStudio")
    field.stringValue = "team/unsaved-repository"
    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    let tabs = try #require(descendants(host.view).compactMap { $0 as? NSTabView }.first)
    for section in [0, 1, 2, 3, 5] {
      tabs.selectTabViewItem(at: section)
      try await settle(host)
    }
    StudioTheme.apply("dark")
    tabs.selectTabViewItem(at: 4)
    try await settle(host)
    #expect(try repositoryField().stringValue == "team/unsaved-repository")
    #expect(UserDefaults.standard.string(forKey: "githubUpdateRepository") == "erhanulas/MSSQLStudio")
  }
}
