import AppKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct AboutPanelTests {
  @Test func aboutWindowReusesVisiblePanelWithoutOpeningQueries() {
    _ = NSApplication.shared
    let state = StudioState(); state.recoveryEnabled = false
    let controller = WorkbenchController(state: state)
    controller.about()
    let first = NSApp.windows.first { $0.identifier?.rawValue == "studio.about" && $0.isVisible }
    #expect(first != nil)
    defer { first?.close() }
    controller.about()
    let windows = NSApp.windows.filter { $0.identifier?.rawValue == "studio.about" && $0.isVisible }
    #expect(windows.count == 1)
    #expect(windows.first === first)
    #expect(state.documents.isEmpty)
  }
  @Test func settingsWindowReusesPanelAndProvidesRoomForTabs() {
    _ = NSApplication.shared
    let state = StudioState(); state.recoveryEnabled = false
    let controller = WorkbenchController(state: state)
    controller.showSettingsWindow()
    let first = NSApp.windows.first { $0.identifier?.rawValue == "studio.settings" && $0.isVisible }
    #expect(first != nil)
    defer { first?.close() }
    #expect((first?.contentView?.bounds.width ?? 0) >= 780)
    #expect((first?.contentView?.bounds.height ?? 0) >= 600)
    controller.showSettingsWindow()
    let windows = NSApp.windows.filter { $0.identifier?.rawValue == "studio.settings" && $0.isVisible }
    #expect(windows.count == 1)
    #expect(windows.first === first)
    #expect(state.documents.isEmpty)
  }
}
