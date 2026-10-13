import AppKit
import SQLServerKit
import SwiftUI
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct SystemThemeTests {
  @Test func explicitModesAndSystemAppearanceResolveIndependently() throws {
    let light = try #require(NSAppearance(named: .aqua))
    let dark = try #require(NSAppearance(named: .darkAqua))
    #expect(StudioTheme.usesDark("system", appearance: light) == false)
    #expect(StudioTheme.usesDark("system", appearance: dark))
    #expect(StudioTheme.usesDark("light", appearance: dark) == false)
    #expect(StudioTheme.usesDark("dark", appearance: light))
    #expect(StudioTheme.normalizedMode("unknown") == "light")
    #expect(StudioTheme.normalizedMode("system") == "system")
  }

  @Test func systemModeInheritsAppearanceAndRecolorsLiveEditorWithoutChangingItsHistory() async throws {
    _ = NSApplication.shared
    let oldTheme = UserDefaults.standard.string(forKey: "ssmsTheme"), oldAppearance = NSApp.appearance
    defer {
      StudioTheme.apply(oldTheme ?? "light"); NSApp.appearance = oldAppearance
      if oldTheme == nil { UserDefaults.standard.removeObject(forKey: "ssmsTheme") }
    }
    let server = ConnectedServer(profile: ServerProfile(), password: ""); server.online = false
    let document = QueryDocument(server: server, database: "master", title: "System theme")
    let source = "DECLARE @unused int; SELECT N'İstanbul 😀', GETDATE(); -- comment"
    document.sql = source
    let controller = EditorController(document: document)
    let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = controller.surface
    defer { window.close() }
    window.makeFirstResponder(controller.editor)
    let undo = try #require(controller.editor.undoManager)
    undo.beginUndoGrouping()
    controller.editor.insertText("\nSELECT 2;", replacementRange: NSRange(location: (source as NSString).length, length: 0))
    undo.endUndoGrouping()
    let edited = controller.editor.string, selection = NSRange(location: 30, length: 4)
    controller.editor.setSelectedRange(selection)
    StudioTheme.apply("system")
    #expect(StudioTheme.mode == "system" && NSApp.appearance == nil)
    let storage = try #require(controller.editor.textContentStorage?.textStorage)
    for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
      // Simulate effectiveAppearance KVO using the test process's app override;
      // the user's macOS preference is never changed.
      NSApp.appearance = try #require(NSAppearance(named: name))
      let deadline = ContinuousClock.now.advanced(by: .seconds(2))
      while storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor != StudioTheme.syntax(.keyword), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(StudioTheme.dark == (name == .darkAqua))
      #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == StudioTheme.syntax(.keyword))
      let unused = (edited as NSString).range(of: "@unused").location
      let literal = (edited as NSString).range(of: "N'İstanbul 😀'").location
      #expect(storage.attribute(.foregroundColor, at: unused, effectiveRange: nil) as? NSColor == StudioTheme.unusedVariable)
      #expect(storage.attribute(.foregroundColor, at: literal, effectiveRange: nil) as? NSColor == StudioTheme.syntax(.string))
      #expect(window.backgroundColor == StudioTheme.chrome)
      #expect(controller.editor.string == edited && document.sql == edited)
      #expect(controller.editor.selectedRange() == selection && controller.editor.textLayoutManager != nil)
      #expect(undo.canUndo && UserDefaults.standard.string(forKey: "ssmsTheme") == "system")
    }
    undo.undo()
    #expect(controller.editor.string == source && document.sql == source)
    StudioTheme.apply("system")
    #expect(NSApp.appearance == nil)
  }

  @Test func explicitThemeDoesNotChangePaletteWhenEffectiveAppearanceChanges() async throws {
    _ = NSApplication.shared
    let oldTheme = UserDefaults.standard.string(forKey: "ssmsTheme"), oldAppearance = NSApp.appearance
    defer {
      StudioTheme.apply(oldTheme ?? "light"); NSApp.appearance = oldAppearance
      if oldTheme == nil { UserDefaults.standard.removeObject(forKey: "ssmsTheme") }
    }
    StudioTheme.apply("light")
    let color = StudioTheme.syntax(.keyword)
    NSApp.appearance = try #require(NSAppearance(named: .darkAqua))
    for _ in 0..<10 { await Task.yield() }
    #expect(StudioTheme.mode == "light" && !StudioTheme.dark)
    #expect(StudioTheme.syntax(.keyword) == color)
    StudioTheme.apply("dark")
    #expect(NSApp.appearance?.name == .darkAqua && StudioTheme.dark)
  }

  @Test func systemThemeChoiceFitsSettingsAndDraftSelectionDoesNotApplyPreferences() async throws {
    _ = NSApplication.shared
    let oldTheme = UserDefaults.standard.string(forKey: "ssmsTheme"), oldAppearance = NSApp.appearance
    defer {
      StudioTheme.apply(oldTheme ?? "light"); NSApp.appearance = oldAppearance
      if oldTheme == nil { UserDefaults.standard.removeObject(forKey: "ssmsTheme") }
    }
    StudioTheme.apply("system")
    let state = StudioState(); state.historyEnabled = false; state.recoveryEnabled = false
    let host = NSHostingController(rootView: SettingsPanel(state: state)); host.sizingOptions = []
    let window = NSWindow(contentViewController: host); window.isReleasedWhenClosed = false
    defer { window.close() }
    window.setFrame(window.frameRect(forContentRect: NSRect(x: -3000, y: 0, width: 780, height: 600)), display: true)
    host.view.frame = NSRect(x: 0, y: 0, width: 780, height: 600)
    try await Task.sleep(for: .milliseconds(90)); host.view.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let picker = try #require(descendants(host.view).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 })
    #expect((0..<3).map { picker.label(forSegment: $0) } == ["Sistem", "Studio Açık", "Studio Koyu"])
    #expect(picker.selectedSegment == 0)
    let rect = host.view.convert(picker.bounds, from: picker)
    #expect(rect.minX >= 0 && rect.maxX <= 780)
    picker.selectedSegment = 2; picker.sendAction(picker.action, to: picker.target)
    try await Task.sleep(for: .milliseconds(90)); host.view.layoutSubtreeIfNeeded()
    #expect(UserDefaults.standard.string(forKey: "ssmsTheme") == "system" && NSApp.appearance == nil)
  }
}
