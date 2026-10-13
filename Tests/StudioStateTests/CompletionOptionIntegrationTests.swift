import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct CompletionOptionIntegrationTests {
  @Test func oldPreferencesDefaultToExistingSQLAndOptionsPersistIndependently() throws {
    let suite = "StudioCompletionOptions-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(SQLEditorPreferences.includeSchema(in: defaults))
    #expect(SQLEditorPreferences.quoteIdentifiers(in: defaults))
    defaults.set(false, forKey: SQLEditorPreferences.completionSchemaKey)
    #expect(!SQLEditorPreferences.includeSchema(in: defaults))
    #expect(SQLEditorPreferences.quoteIdentifiers(in: defaults))
    defaults.set(false, forKey: SQLEditorPreferences.completionBracketsKey)
    #expect(!SQLEditorPreferences.quoteIdentifiers(in: defaults))
    defaults.set(true, forKey: SQLEditorPreferences.completionSchemaKey)
    #expect(SQLEditorPreferences.includeSchema(in: defaults))
    #expect(!SQLEditorPreferences.quoteIdentifiers(in: defaults))
  }

  @Test func activeEditorUsesFormattingPreferencesAndTabKeepsSingleUndoStep() async throws {
    _ = NSApplication.shared
    let keys = [SQLEditorPreferences.completionSchemaKey, SQLEditorPreferences.completionBracketsKey,
      "sqlAutomaticAliases", "sqlAutomaticNoLock"]
    let old = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer {
      for (index, key) in keys.enumerated() {
        if let value = old[index] { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
      }
    }
    UserDefaults.standard.set(false, forKey: "sqlAutomaticAliases")
    UserDefaults.standard.set(false, forKey: "sqlAutomaticNoLock")
    let server = ConnectedServer(profile: ServerProfile(), password: ""); server.online = false
    let document = QueryDocument(server: server, database: "master", title: "Completion options")
    document.intelligenceCatalog = SQLIntelligence.Catalog(snapshot: .init(symbols: [
      CatalogSymbol(schema: "dbo", name: "Products", columns: ["STOK_KODU"])
    ]))
    document.catalogDatabase = "master"; document.catalogVerified = true
    let controller = EditorController(document: document)
    let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 900, height: 680),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = controller.surface
    defer { controller.editor.dismissSuggestions?(); window.close() }
    window.makeKeyAndOrderFront(nil); window.makeFirstResponder(controller.editor)

    for (schema, brackets, expected) in [
      (true, true, "[dbo].[Products]"), (false, true, "[Products]"),
      (true, false, "dbo.Products"), (false, false, "Products")
    ] {
      UserDefaults.standard.set(schema, forKey: SQLEditorPreferences.completionSchemaKey)
      UserDefaults.standard.set(brackets, forKey: SQLEditorPreferences.completionBracketsKey)
      let sql = "SELECT * FROM Prod"
      controller.editor.string = sql
      controller.editor.setSelectedRange(NSRange(location: (sql as NSString).length, length: 0))
      controller.editor.undoManager?.removeAllActions()
      NotificationCenter.default.post(name: .init("sqlEditorPreferencesChanged"), object: nil)
      controller.scheduleIntelligence(manual: true)
      for _ in 0..<200 where !controller.completionShown { try await Task.sleep(for: .milliseconds(10)) }
      #expect(controller.completionShown)
      #expect(window.firstResponder === controller.editor)
      let tab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\t",
        charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
      controller.editor.keyDown(with: tab)
      #expect(controller.editor.string == "SELECT * FROM " + expected)
      #expect(!controller.completionShown)
      controller.editor.undoManager?.undo()
      #expect(controller.editor.string == sql)
      #expect(controller.editor.undoManager?.canUndo == false)
      controller.editor.undoManager?.redo()
      #expect(controller.editor.string == "SELECT * FROM " + expected)
    }
  }

  @Test func interiorColumnMatchIsAcceptedWithActualAliasAndOptionalBrackets() async throws {
    _ = NSApplication.shared
    let old = UserDefaults.standard.object(forKey: SQLEditorPreferences.completionBracketsKey)
    defer {
      if let old { UserDefaults.standard.set(old, forKey: SQLEditorPreferences.completionBracketsKey) }
      else { UserDefaults.standard.removeObject(forKey: SQLEditorPreferences.completionBracketsKey) }
    }
    UserDefaults.standard.set(false, forKey: SQLEditorPreferences.completionBracketsKey)
    let server = ConnectedServer(profile: ServerProfile(), password: ""); server.online = false
    let document = QueryDocument(server: server, database: "master", title: "Interior column")
    document.sql = "SELECT * FROM Products p WHERE KODU"
    document.intelligenceCatalog = SQLIntelligence.Catalog(snapshot: .init(symbols: [
      CatalogSymbol(schema: "dbo", name: "Products", columns: ["STOK_KODU"])
    ]))
    document.catalogDatabase = "master"; document.catalogVerified = true
    let controller = EditorController(document: document)
    let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 900, height: 680),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = controller.surface
    defer { controller.editor.dismissSuggestions?(); window.close() }
    window.makeKeyAndOrderFront(nil); window.makeFirstResponder(controller.editor)
    controller.editor.setSelectedRange(NSRange(location: (document.sql as NSString).length, length: 0))
    controller.scheduleIntelligence(manual: true)
    for _ in 0..<200 where !controller.completionShown { try await Task.sleep(for: .milliseconds(10)) }
    #expect(controller.completionShown)
    let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
      charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    controller.editor.keyDown(with: enter)
    #expect(controller.editor.string == "SELECT * FROM Products p WHERE p.STOK_KODU")
    #expect(window.firstResponder === controller.editor)
    controller.editor.undoManager?.undo()
    #expect(controller.editor.string == "SELECT * FROM Products p WHERE KODU")
  }
}
