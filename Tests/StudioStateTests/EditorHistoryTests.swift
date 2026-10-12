import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorHistoryTests {
  func fixture(_ sql:String = "")->(controller:EditorController,document:QueryDocument,editor:SQLTextView,window:NSWindow) {
    _=NSApplication.shared
    let document=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Undo fixture")
    document.server.online=false;document.sql=sql
    let controller=EditorController(document:document)
    let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.makeFirstResponder(controller.editor)
    return (controller,document,controller.editor,window)
  }
  // Simulate separate keyboard events without imposing artificial coalescing breaks.
  func edit(_ editor:SQLTextView,_ action:()->Void) throws {
    let manager=try #require(editor.undoManager)
    manager.groupsByEvent=true;action()
    RunLoop.current.run(until:Date(timeIntervalSinceNow:0.002))
  }
  func type(_ text:String,in editor:SQLTextView) throws {
    for character in text {let key=try event(String(character),[]);try edit(editor) {editor.keyDown(with:key)}}
  }
  func event(_ key:String,_ flags:NSEvent.ModifierFlags) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:0))
  }
  @Test func undoStopsAtWordsAndRedoRestoresOnlyThatStepAndDocument() throws {
    let controller=fixture(),editor=controller.editor,manager=try #require(editor.undoManager)
    defer {controller.window.close()}
    try type("SELECT alpha beta",in:editor)
    for expected in ["SELECT alpha ","SELECT ",""] {
      editor.keyDown(with:try event("z",.control))
      #expect(editor.string == expected)
      #expect(controller.document.sql == expected)
    }
    for expected in ["SELECT ","SELECT alpha ","SELECT alpha beta"] {
      editor.keyDown(with:try event("y",.control))
      #expect(editor.string == expected)
      #expect(controller.document.sql == expected)
    }
    #expect(!manager.canRedo && editor.textLayoutManager != nil)
    #expect(editor.textContentStorage?.textStorage?.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.keyword))
    editor.keyDown(with:try event("z",.control))
    try type("gamma",in:editor)
    #expect(!manager.canRedo && editor.string == "SELECT alpha gamma")
    manager.groupsByEvent=true
  }
  @Test func pauseAndDeletionDirectionDoNotJoinEarlierTyping() async throws {
    let controller=fixture(),editor=controller.editor,manager=try #require(editor.undoManager)
    defer {controller.window.close()}
    try type("alpha",in:editor)
    try await Task.sleep(for:.milliseconds(1100))
    try type("beta",in:editor)
    editor.undoSQL(nil);#expect(editor.string == "alpha")
    editor.redoSQL(nil);#expect(editor.string == "alphabeta")
    for _ in 0..<4 {try edit(editor) {editor.deleteBackward(nil)}}
    #expect(editor.string == "alpha")
    editor.undoSQL(nil);#expect(editor.string == "alphabeta")
    editor.redoSQL(nil);#expect(editor.string == "alpha" && controller.document.sql == editor.string)
    manager.groupsByEvent=true
  }
  @Test func unicodeBulkEditsAndFormatRemainIndependentAndOtherDocumentsKeepHistory() throws {
    let controller=fixture(),editor=controller.editor,manager=try #require(editor.undoManager)
    let other=fixture()
    defer {controller.window.close();other.window.close()}
    controller.controller.surface.addSubview(other.controller.surface)
    let otherManager=try #require(other.editor.undoManager)
    #expect(manager !== otherManager)
    try type("select ",in:editor)
    try edit(editor) {editor.insertText("N'İstanbul 😀'",replacementRange:editor.selectedRange())}
    try edit(editor) {controller.controller.replaceText("SELECT N'İstanbul 😀'")}
    editor.undoSQL(nil);#expect(editor.string == "select N'İstanbul 😀'")
    editor.undoSQL(nil);#expect(editor.string == "select ")
    editor.redoSQL(nil);#expect(editor.string == "select N'İstanbul 😀'")
    try type("SELECT 7",in:other.editor)
    #expect(editor.string == "select N'İstanbul 😀'" && other.document.sql == "SELECT 7")
    other.controller.surface.removeFromSuperview()
    other.window.contentView=controller.controller.surface
    #expect(editor.undoManager === manager)
    editor.redoSQL(nil);#expect(editor.string == "SELECT N'İstanbul 😀'" && controller.document.sql == editor.string)
    manager.groupsByEvent=true;otherManager.groupsByEvent=true
  }
  @Test func changingDeleteDirectionCaretAndNewlineKeepSeparateUndoSteps() throws {
    let controller=fixture("abcdef"),editor=controller.editor
    defer {controller.window.close()}
    editor.setSelectedRange(NSRange(location:3,length:0))
    try edit(editor) {editor.deleteBackward(nil)}
    try edit(editor) {editor.deleteForward(nil)}
    #expect(editor.string == "abef")
    editor.undoSQL(nil);#expect(editor.string == "abdef")
    editor.undoSQL(nil);#expect(editor.string == "abcdef")
    editor.setSelectedRange(NSRange(location:6,length:0))
    try type(" xy",in:editor)
    editor.setSelectedRange(NSRange(location:0,length:0))
    try type("ab",in:editor)
    editor.undoSQL(nil);#expect(editor.string == "abcdef xy")
    editor.setSelectedRange(NSRange(location:editor.string.utf16.count,length:0))
    try edit(editor) {editor.insertNewline(nil)}
    try type("SELECT",in:editor)
    editor.undoSQL(nil);#expect(editor.string == "abcdef xy\n")
    editor.undoSQL(nil);#expect(editor.string == "abcdef xy" && controller.document.sql == editor.string)
  }
  @Test func configurableHistoryShortcutsPreserveNativeAliasesConflictsAndMenuValidation() throws {
    let keys=GridShortcuts.Action.allCases.map {"shortcut.\($0.rawValue)"}
    let previous=keys.map {UserDefaults.standard.object(forKey:$0)}
    defer {for (key,value) in zip(keys,previous) {if let value {UserDefaults.standard.set(value,forKey:key)} else {UserDefaults.standard.removeObject(forKey:key)}}}
    for key in keys {UserDefaults.standard.removeObject(forKey:key)}
    #expect(GridShortcuts.binding(.undo).label == "⌃Z" && GridShortcuts.binding(.redo).label == "⌃Y")
    #expect(GridShortcuts.save(try event("z",.command),action:.undo) == nil)
    #expect(GridShortcuts.save(try event("z",[.command,.shift]),action:.redo) == nil)
    #expect(GridShortcuts.save(try event("y",.control),action:.newQuery) != nil)
    #expect(GridShortcuts.save(try event("z",.control),action:.redo) != nil)
    #expect(GridShortcuts.save(try event("u",[.control,.shift]),action:.undo) == nil)
    #expect(GridShortcuts.save(try event("u",[.control,.shift]),action:.redo) != nil)
    #expect(GridShortcuts.save(try event("r",[.control,.shift]),action:.redo) == nil)
    let controller=fixture(),editor=controller.editor,manager=try #require(editor.undoManager)
    defer {controller.window.close()}
    let undoItem=NSMenuItem(title:"Geri Al",action:#selector(SQLTextView.undoSQL(_:)),keyEquivalent:"")
    let redoItem=NSMenuItem(title:"İleri Al",action:#selector(SQLTextView.redoSQL(_:)),keyEquivalent:"")
    #expect(!editor.validateUserInterfaceItem(undoItem) && !editor.validateUserInterfaceItem(redoItem))
    let nativeUndo=NSMenuItem(title:"Geri Al",action:Selector(("undo:")),keyEquivalent:"z")
    let nativeRedo=NSMenuItem(title:"İleri Al",action:Selector(("redo:")),keyEquivalent:"Z")
    #expect(editor.responds(to:nativeUndo.action!) && editor.responds(to:nativeRedo.action!))
    #expect(!editor.validateUserInterfaceItem(nativeUndo) && !editor.validateUserInterfaceItem(nativeRedo))
    try type("SELECT x",in:editor)
    #expect(editor.validateUserInterfaceItem(nativeUndo))
    #expect(editor.tryToPerform(nativeUndo.action!,with:nil));#expect(editor.string == "SELECT ")
    #expect(editor.validateUserInterfaceItem(nativeRedo))
    #expect(editor.tryToPerform(nativeRedo.action!,with:nil));#expect(editor.string == "SELECT x")
    editor.keyDown(with:try event("u",[.control,.shift]));#expect(editor.string == "SELECT ")
    #expect(editor.validateUserInterfaceItem(redoItem))
    editor.keyDown(with:try event("r",[.control,.shift]));#expect(editor.string == "SELECT x")
    editor.keyDown(with:try event("z",.command));#expect(editor.string == "SELECT ")
    editor.keyDown(with:try event("z",[.command,.shift]));#expect(editor.string == "SELECT x")
    editor.keyDown(with:try event("z",.control));editor.keyDown(with:try event("z",[.control,.shift]));#expect(editor.string == "SELECT x")
    let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.controller.surface;defer {window.close()}
    let field=NSTextField(frame:NSRect(x:0,y:0,width:100,height:24));controller.controller.surface.addSubview(field);window.makeFirstResponder(field)
    #expect(!editor.performKeyEquivalent(with:try event("u",[.control,.shift])))
    #expect(editor.string == "SELECT x")
    manager.groupsByEvent=true
  }
}
