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
}
