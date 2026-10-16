import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorFormatShortcutTests {
  private func event(_ key: String, _ flags: NSEvent.ModifierFlags, window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: key == "f" ? 3 : 37))
  }
  @Test func assignmentFeedbackNamesTheOwnerAndProvidesANavigableSettingsTarget() throws {
    _=NSApplication.shared
    let keys=GridShortcuts.Action.allCases.map {"shortcut."+$0.rawValue},old=GridShortcuts.Action.allCases.map {UserDefaults.standard.object(forKey:"shortcut."+$0.rawValue)}
    defer {for (key,value) in zip(keys,old) {UserDefaults.standard.set(value,forKey:key)}}
    for key in keys {UserDefaults.standard.removeObject(forKey:key)}
    let window=NSWindow();window.isReleasedWhenClosed=false;defer {window.close()}
    let reserved=GridShortcuts.assign(try event("b",.command,window:window),action:.format)
    #expect(reserved.tone == .warning && reserved.target == .definition && reserved.message.contains(GridShortcuts.title(.definition)))
    let native=GridShortcuts.assign(try event("c",.command,window:window),action:.format)
    #expect(native.tone == .warning && native.target == nil && native.message.contains("Kopyala"))
    let chosen=try event("g",[.control,.shift],window:window)
    #expect(GridShortcuts.assign(chosen,action:.format).tone == .success)
    let original=GridShortcuts.binding(.comment)
    let conflict=GridShortcuts.assign(chosen,action:.comment)
    #expect(conflict.tone == .warning && conflict.target == .format && conflict.message.contains(GridShortcuts.title(.format)))
    #expect(GridShortcuts.binding(.comment) == original)
    let target=try #require(conflict.target)
    let destination=try #require(SettingsSearch.entries.first {$0.id == "shortcut."+target.rawValue})
    #expect(destination.section == .shortcuts && ShortcutCatalog.target(destination.id) == .format)
    #expect(GridShortcuts.assign(try event("g",.option,window:window),action:.comment).target == nil)
  }
  @Test func movedExplorerShortcutReleasesItsOldDefaultAndNamesItsCurrentOwner() throws {
    _=NSApplication.shared
    let keys=GridShortcuts.Action.allCases.map {"shortcut."+$0.rawValue}
    let old=keys.map {UserDefaults.standard.object(forKey:$0)}
    defer {for (key,value) in zip(keys,old) {UserDefaults.standard.set(value,forKey:key)}}
    for key in keys {UserDefaults.standard.removeObject(forKey:key)}
    let window=NSWindow();window.isReleasedWhenClosed=false;defer {window.close()}
    let replacement=try event("1",.command,window:window)
    #expect(GridShortcuts.assign(replacement,action:.explorer).tone == .success)
    let released=try event("b",[.command,.option],window:window)
    #expect(GridShortcuts.assign(released,action:.format).tone == .success)
    #expect(GridShortcuts.matches(.format,released) && !GridShortcuts.matches(.explorer,released))
    let conflict=GridShortcuts.assign(replacement,action:.comment)
    #expect(conflict.tone == .warning && conflict.target == .explorer)
    GridShortcuts.clear(.explorer)
    #expect(GridShortcuts.assign(replacement,action:.comment).tone == .success)
    #expect(GridShortcuts.assign(try event("c",.command,window:window),action:.newQuery).tone == .warning)
    GridShortcuts.clear(.undo)
    #expect(GridShortcuts.assign(try event("z",.command,window:window),action:.newQuery).target == .undo)
  }
  @Test func functionKeysSaveDisplayMatchAndKeepConflictValidation() throws {
    let keys = GridShortcuts.Action.allCases.map { "shortcut." + $0.rawValue }
    let old = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer { for (index, key) in keys.enumerated() {
      if let value = old[index] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    } }
    for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option, .command, .function], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 111))
    #expect(GridShortcuts.save(event, action: .format) == nil)
    #expect(GridShortcuts.binding(.format).label == "⌥⌘F12")
    #expect(GridShortcuts.matches(.format, event))
    #expect(GridShortcuts.save(event, action: .comment) != nil)
  }
  @Test func configurableFormatUsesFocusedEditorSelectionAndOneUndoWithoutExecutingSQL() throws {
    _ = NSApplication.shared
    let keys = GridShortcuts.Action.allCases.map { "shortcut." + $0.rawValue }
    let old = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer { for (index, key) in keys.enumerated() {
      if let value = old[index] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    } }
    for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    let server = ConnectedServer(profile: .init(), password: ""); server.online = false
    let doc = QueryDocument(server: server, database: "master", title: "Format shortcut")
    let source = "SELECT 1;\nselect a,b from dbo.t where a=1;"
    doc.sql = source
    let controller = EditorController(document: doc), editor = controller.editor
    let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 900, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = controller.surface
    defer { window.close() }
    window.makeKeyAndOrderFront(nil); window.makeFirstResponder(editor)
    editor.setSelectedRange((source as NSString).range(of: "select a,b from dbo.t where a=1;"))
    let undo = try #require(editor.undoManager); undo.removeAllActions()
    #expect(GridShortcuts.binding(.format).label == "⇧⌘F")
    undo.beginUndoGrouping(); #expect(editor.performKeyEquivalent(with: try event("f", [.command, .shift], window: window))); undo.endUndoGrouping()
    #expect(editor.string != source && editor.string.hasPrefix("SELECT 1;\n"))
    #expect(SQLFormatter.preservesSQLTokens(source, formatted: editor.string))
    undo.undo(); #expect(editor.string == source && doc.sql == source && !undo.canUndo)
    #expect(GridShortcuts.save(try event("l", [.control, .shift], window: window), action: .format) == nil)
    #expect(GridShortcuts.save(try event("l", [.control, .shift], window: window), action: .comment) != nil)
    #expect(GridShortcuts.save(try event("f", .command, window: window), action: .format) != nil)
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    undo.beginUndoGrouping(); editor.keyDown(with: try event("l", [.control, .shift], window: window)); undo.endUndoGrouping()
    #expect(editor.string != source && doc.sql == editor.string && doc.lastExecutedSQL == nil)
    undo.undo(); #expect(editor.string == source)
    undo.beginUndoGrouping()
    let menu = try #require(editor.menu(for: try event("l", [.control, .shift], window: window)))
    let formatItem = try #require(menu.items.first { $0.action == #selector(SQLTextView.formatSQLText(_:)) })
    #expect(formatItem.target === editor && formatItem.keyEquivalent == "l")
    #expect(NSApp.sendAction(try #require(formatItem.action), to: formatItem.target, from: formatItem))
    undo.endUndoGrouping()
    #expect(editor.string != source)
    undo.undo(); #expect(editor.string == source)
    editor.isEditable = false
    editor.keyDown(with: try event("l", [.control, .shift], window: window))
    #expect(editor.string == source)
    GridShortcuts.reset(.format); #expect(GridShortcuts.binding(.format).label == "⇧⌘F")
    #expect(SettingsSearch.results("formatla").contains { $0.id == "shortcut.format" })
  }
  @Test func wholeDocumentFormatKeepsCaretAtSameTokenAndScrolledViewport() throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Format caret")
    doc.sql=(0..<100).map {"select \($0) as Value\($0), '🦊' as Label from dbo.T;"}.joined(separator:"\n")
    let source=doc.sql,controller=EditorController(document:doc),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:900,height:500),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.orderFront(nil);defer {window.close()}
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport();window.makeFirstResponder(editor)
    let caret=(source as NSString).range(of:"Value50").location+3
    editor.setSelectedRange(NSRange(location:caret,length:0));editor.scrollRangeToVisible(editor.selectedRange())
    #expect(controller.scroll.contentView.bounds.minY>0)
    let undo=try #require(editor.undoManager);undo.removeAllActions();undo.beginUndoGrouping()
    controller.formatSQL(options:.init());undo.endUndoGrouping()
    let expected=(editor.string as NSString).range(of:"Value50").location+3
    #expect(editor.selectedRange()==NSRange(location:expected,length:0) && doc.selectedRange==editor.selectedRange())
    #expect(controller.scroll.contentView.bounds.minY>0 && expected<editor.string.utf16.count-100)
    let caretScreen=editor.firstRect(forCharacterRange:editor.selectedRange(),actualRange:nil)
    #expect(window.frame.intersects(caretScreen))
    #expect(SQLFormatter.preservesSQLTokens(source,formatted:editor.string))
    undo.undo();#expect(editor.string==source && doc.sql==source)
  }
  @Test func menuShortcutTracksSettingsAndTargetsNativeEditorResponder() throws {
    _ = NSApplication.shared
    let previous = NSApp.mainMenu, old = UserDefaults.standard.data(forKey: "shortcut.format")
    defer { NSApp.mainMenu = previous
      if let old { UserDefaults.standard.set(old, forKey: "shortcut.format") } else { UserDefaults.standard.removeObject(forKey: "shortcut.format") } }
    let binding = GridShortcuts.Binding(key: "l", modifiers: NSEvent.ModifierFlags([.control, .shift]).rawValue)
    UserDefaults.standard.set(try JSONEncoder().encode(binding), forKey: "shortcut.format")
    let menu = NSMenu(); let item = menu.addItem(withTitle: "SQL Formatla", action: #selector(SQLTextView.formatSQLText(_:)), keyEquivalent: "f")
    NSApp.mainMenu = menu
    let workbench = WorkbenchController(state: StudioState()); workbench.refreshShortcuts()
    #expect(item.keyEquivalent == "l" && item.keyEquivalentModifierMask == [.control, .shift])
    #expect(item.target == nil)
  }
  @Test func insertSecondColumnAutomaticallyCompletesInteriorMatchAndTabIsUndoable() async throws {
    _ = NSApplication.shared
    let keys = ["sqlAutomaticCompletion", "sqlAutomaticAliases", SQLEditorPreferences.completionDelayKey, SQLEditorPreferences.completionBracketsKey]
    let old = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer { for (index, key) in keys.enumerated() {
      if let value = old[index] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    } }
    UserDefaults.standard.set(true, forKey: keys[0]); UserDefaults.standard.set(false, forKey: keys[1])
    UserDefaults.standard.set(50, forKey: keys[2]); UserDefaults.standard.set(true, forKey: keys[3])
    let server = ConnectedServer(profile: .init(), password: ""); server.online = false
    let doc = QueryDocument(server: server, database: "master", title: "Insert completion")
    doc.sql = "INSERT INTO dbo.Products ([STOK], "
    doc.catalogDatabase = "master"; doc.catalogVerified = true
    doc.intelligenceCatalog = .init(snapshot: .init(symbols: [.init(schema: "dbo", name: "Products", columns: ["STOK", "ExternalCode", "CARI"])]))
    let controller = EditorController(document: doc), editor = controller.editor
    let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 900, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = controller.surface
    defer { editor.dismissSuggestions?(); window.close() }
    window.makeKeyAndOrderFront(nil); window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
    controller.scheduleIntelligence(manual: false)
    for _ in 0..<200 where !controller.completionShown { try await Task.sleep(for: .milliseconds(10)) }
    #expect(controller.completionShown)
    editor.dismissSuggestions?()
    editor.insertText("od", replacementRange: editor.selectedRange())
    let before = editor.string
    for _ in 0..<200 where !controller.completionShown { try await Task.sleep(for: .milliseconds(10)) }
    #expect(controller.completionShown && window.firstResponder === editor)
    let tab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
    editor.keyDown(with: tab)
    #expect(editor.string == "INSERT INTO dbo.Products ([STOK], [ExternalCode]" && doc.sql == editor.string)
    editor.undoManager?.undo(); #expect(editor.string == before && doc.lastExecutedSQL == nil)
  }

}
