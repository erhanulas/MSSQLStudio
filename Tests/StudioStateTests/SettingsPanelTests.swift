import SQLServerKit
import AppKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct SettingsPanelTests {
  private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
  private func window(_ section: SettingsSection) -> (NSWindow, NSHostingController<SettingsPanel>) {
    let state = StudioState(); state.historyEnabled = false; state.recoveryEnabled = false
    let host = NSHostingController(rootView: SettingsPanel(state: state, initialTab: section, definitionStorage:DefinitionIndexStorageModel(disk:CatalogDiskIndex(url:URL(fileURLWithPath:"/tmp/SettingsStorage-"+UUID().uuidString+"/index.sqlite"))))); host.sizingOptions = []
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
        let nativeButtons:[NSButton]=views.compactMap {$0 as? NSButton}
        let categoryButtons:[NSButton]=nativeButtons.filter {button in (button.accessibilityIdentifier() ?? "").hasPrefix("settingsSection_")}
        let categories:[NSButton]=categoryButtons.sorted {left,right in left.tag<right.tag}
        #expect(categories.count==6 && categories.map(\.title)==SettingsSection.allCases.map(\.title))
        #expect(categories.first(where:{$0.state == .on})?.title==section.title)
        let navigation=try #require(categories.first?.superview)
        let navRect=host.view.convert(navigation.bounds,from:navigation)
        #expect(navRect.minX>=0 && navRect.maxX<=190 && navRect.minY>=55 && navRect.maxY<=530)
        for control in views.compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
          let rect = host.view.convert(control.bounds, from: control)
          #expect(rect.minX >= -1 && rect.maxX <= 781, "\(theme) \(section) horizontal control overflow: \(rect)")
        }
        let apply=try #require(nativeButtons.first {$0.accessibilityIdentifier()=="settingsApply"})
        let applyRect=host.view.convert(apply.bounds,from:apply)
        #expect(applyRect.minX>=20 && applyRect.maxX<=host.view.bounds.maxX-20 && applyRect.minY>=20 && applyRect.maxY<=host.view.bounds.maxY-20)
        if section == .shortcuts {
          let capture = views.compactMap { $0 as? NSButton }.filter { $0.title.contains("Değiştir") }
          #expect(capture.count == ShortcutCatalog.actions(category:.workspace).count)
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
      try #require(descendants(host.view).compactMap { $0 as? NSTextField }.first { $0.isEditable && $0.placeholderString=="kullanıcı/depo veya GitHub depo adresi" })
    }
    let field = try repositoryField()
    #expect(field.stringValue == "erhanulas/MSSQLStudio")
    field.stringValue = "team/unsaved-repository"
    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    let search=try #require(descendants(host.view).compactMap {$0 as? NSTextField}.first {$0.isEditable && $0.placeholderString=="Tüm ayarlarda ara…"})
    for query in ["parola","tamamlama","", "bulunmayan ayar xyz", ""] {
      search.stringValue=query;search.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:search))
      try await settle(host)
      #expect(try repositoryField().stringValue=="team/unsaved-repository")
    }
    func choose(_ section:SettingsSection) throws {
      let button=try #require(descendants(host.view).compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier()=="settingsSection_"+section.rawValue})
      #expect(NSApp.sendAction(try #require(button.action),to:button.target,from:button))
    }
    for section in [SettingsSection.appearance,.editor,.shortcuts,.workspace,.security] {
      try choose(section);try await settle(host)
    }
    StudioTheme.apply("dark")
    try choose(.updates);try await settle(host)
    #expect(try repositoryField().stringValue == "team/unsaved-repository")
    #expect(UserDefaults.standard.string(forKey: "githubUpdateRepository") == "erhanulas/MSSQLStudio")
  }
  @Test func cardHeaderCollapsesAndRestoresItsFieldsWithoutLosingDraft() async throws {
    _=NSApplication.shared
    let (window,host)=window(.updates);defer {window.close()}
    try await settle(host)
    func header() throws -> StudioDisclosureButton {
      try #require(descendants(host.view).compactMap {$0 as? StudioDisclosureButton}.first {$0.title=="GitHub yayınları"})
    }
    func field()->NSTextField? {
      descendants(host.view).compactMap {$0 as? NSTextField}.first {$0.isEditable && $0.placeholderString=="kullanıcı/depo veya GitHub depo adresi"}
    }
    let repository=try #require(field());repository.stringValue="fixture/unsaved"
    repository.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:repository))
    let open=try header();#expect(open.expanded && open.bounds.width>400)
    #expect(NSApp.sendAction(try #require(open.action),to:open.target,from:open))
    try await settle(host)
    let closed=try header();#expect(!closed.expanded && field()==nil)
    #expect(NSApp.sendAction(try #require(closed.action),to:closed.target,from:closed))
    try await settle(host)
    #expect(try header().expanded && field()?.stringValue=="fixture/unsaved")
  }
  @Test func globalSearchFindsEverySectionAndTurkishAliasesWithoutChangingPreferences() {
    let old=UserDefaults.standard.object(forKey:"ssmsTheme")
    #expect(SettingsSearch.results("KOSELI PARANTEZ").contains {$0.id=="brackets"})
    #expect(SettingsSearch.results("anahtar zinciri").contains {$0.section == .security})
    #expect(SettingsSearch.results("Saklama SÜRESİ").map(\.id)==["retention"])
    #expect(SettingsSearch.results("yorum").contains {$0.id=="shortcut.comment"})
    #expect(SettingsSearch.results("guncelleme").contains {$0.section == .updates})
    #expect(SettingsSearch.results("   ").isEmpty && SettingsSearch.results("xyz missing setting").isEmpty)
    #expect(Set(SettingsSearch.entries.map(\.section))==Set(SettingsSection.allCases))
    #expect(Set(SettingsSearch.entries.map(\.id)).count==SettingsSearch.entries.count)
    #expect(UserDefaults.standard.object(forKey:"ssmsTheme") as? String == old as? String)
  }
}
