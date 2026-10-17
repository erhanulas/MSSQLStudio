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

  @Test func sharedSystemThemeChoiceFitsAndDraftSelectionDoesNotApplyPreferences() throws {
    _=NSApplication.shared
    let oldTheme=UserDefaults.standard.string(forKey:"ssmsTheme"),oldAppearance=NSApp.appearance
    defer {
      StudioTheme.apply(oldTheme ?? "light");NSApp.appearance=oldAppearance
      if oldTheme==nil {UserDefaults.standard.removeObject(forKey:"ssmsTheme")}
    }
    StudioTheme.apply("system")
    var draft="system"
    let choices=StudioChoiceTabs(choices:[("system","Sistem","circle.lefthalf.filled"),("light","Studio Açık","sun.max"),("dark","Studio Koyu","moon")],selection:Binding(get:{draft},set:{draft=$0}))
    let tabs=try #require(choices.body as? StudioTabBar)
    #expect(tabs.items.map(\.title)==["Sistem","Studio Açık","Studio Koyu"])
    #expect(tabs.selection==0)
    let host=NSHostingView(rootView:choices)
    host.frame=NSRect(x:0,y:0,width:500,height:38)
    let window=NSWindow(contentRect:host.frame,styleMask:.borderless,backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=host;window.setFrameOrigin(NSPoint(x:-20000,y:0));window.orderFront(nil)
    defer {window.close()}
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width<=500 && host.fittingSize.height<=38)
    tabs.$selection.wrappedValue=2
    #expect(draft=="dark" && tabs.selection==2)
    #expect(UserDefaults.standard.string(forKey:"ssmsTheme")=="system" && NSApp.appearance==nil)
  }
}
