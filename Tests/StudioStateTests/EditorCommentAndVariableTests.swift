import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

// Offscreen native geometry fixtures do not receive desktop key-window status.
@MainActor private final class CommentFixtureWindow:NSWindow {
  override var isKeyWindow:Bool {true}
}

@MainActor @Suite(.serialized) struct EditorCommentAndVariableTests {
  private func fixture(_ sql:String)->(EditorController,QueryDocument,NSWindow) {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let document=QueryDocument(server:server,database:"master",title:"Editor features");document.sql=sql
    let controller=EditorController(document:document)
    let window=CommentFixtureWindow(contentRect:NSRect(x:-20_000,y:0,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.makeFirstResponder(controller.editor)
    controller.surface.layoutSubtreeIfNeeded();controller.resizeToViewport()
    return (controller,document,window)
  }
  @Test func missingVariablesAreRedAcrossThemesAndDeclarationEditsUndoAndRedo() throws {
    let old=StudioTheme.mode;defer {StudioTheme.apply(old)}
    let source="DECLARE @known int;\nSELECT @known, @missing, @@SPID;"
    let (controller,document,window)=fixture(source);defer {window.close()}
    let editor=controller.editor,storage=try #require(editor.textContentStorage?.textStorage),undo=try #require(editor.undoManager)
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let range=(editor.string as NSString).range(of:"@missing")
      #expect(storage.attribute(.foregroundColor,at:range.location,effectiveRange:nil) as? NSColor == StudioTheme.undeclaredVariable)
      #expect(storage.attribute(.toolTip,at:range.location,effectiveRange:nil) != nil)
      #expect(SQLSourceHighlighting.attributed(source).attribute(.foregroundColor,at:range.location,effectiveRange:nil) as? NSColor == StudioTheme.undeclaredVariable)
    }
    undo.beginUndoGrouping();editor.insertText("DECLARE @missing int;\n",replacementRange:NSRange(location:0,length:0));undo.endUndoGrouping()
    let last=(editor.string as NSString).range(of:"@missing",options:.backwards).location
    #expect(storage.attribute(.foregroundColor,at:last,effectiveRange:nil) as? NSColor == StudioTheme.editorText)
    #expect(storage.attribute(.toolTip,at:last,effectiveRange:nil)==nil)
    undo.undo();#expect(document.sql==source)
    #expect(storage.attribute(.foregroundColor,at:(source as NSString).range(of:"@missing").location,effectiveRange:nil) as? NSColor == StudioTheme.undeclaredVariable)
    undo.redo();#expect(document.sql.hasPrefix("DECLARE @missing"))
    #expect(document.lastExecutedSQL==nil)
  }
  @Test func shortcutAndSelectionHintCommentWithAtomicUndoAndNoSQLExecution() throws {
    let source="SELECT @missing;\nSELECT 2;"
    let (controller,document,window)=fixture(source);defer {window.close()}
    let editor=controller.editor,undo=try #require(editor.undoManager)
    editor.setSelectedRange(NSRange(location:0,length:source.utf16.count));controller.updateCommentHint()
    #expect(!controller.commentHint.isHidden && controller.commentHint.toolTip?.contains("Yorum Yap") == true)
    for rect in editor.rects(forCharacterRange:editor.selectedRange()) ?? [] {
      #expect(!controller.commentHint.frame.intersects(controller.surface.convert(rect.rectValue,from:editor)))
    }
    #expect(controller.commentHint.frame.width == 28)
    editor.setSelectedRange(NSRange(location:0,length:6));controller.updateCommentHint()
    #expect(controller.commentHint.isHidden)
    editor.setSelectedRange((source as NSString).range(of:"\n"));controller.updateCommentHint()
    #expect(controller.commentHint.isHidden)
    editor.setSelectedRange(NSRange(location:0,length:source.utf16.count));controller.updateCommentHint()
    let binding=GridShortcuts.binding(.comment)
    let event=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:binding.flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:binding.key,charactersIgnoringModifiers:binding.key,isARepeat:false,keyCode:44))
    undo.beginUndoGrouping();#expect(editor.performKeyEquivalent(with:event));undo.endUndoGrouping()
    #expect(editor.string=="-- SELECT @missing;\n-- SELECT 2;" && document.sql==editor.string)
    #expect(controller.commentHint.toolTip?.contains("Yorumu Kaldır") == true)
    let storage=try #require(editor.textContentStorage?.textStorage)
    #expect(storage.attribute(.foregroundColor,at:10,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.comment))
    undo.undo();#expect(editor.string==source && document.sql==source)
    undo.redo();#expect(editor.string.hasPrefix("-- "))
    editor.selectAll(nil);controller.updateCommentHint()
    undo.beginUndoGrouping();controller.commentHint.performClick(nil);undo.endUndoGrouping()
    #expect(editor.string==source && document.sql==source)
    #expect(document.lastExecutedSQL==nil && document.state == .disconnected)
  }
  @Test func foldedSelectionUsesOriginalSQLForCommentingAndMissingNameColors() throws {
    let source="IF 1=1\nBEGIN\n SELECT @missing;\nEND;\nSELECT @missing;"
    let (controller,document,window)=fixture(source);defer {window.close()}
    controller.toggleFold(try #require(controller.regions.first))
    let storage=try #require(controller.editor.textContentStorage?.textStorage)
    let visible=(controller.editor.string as NSString).range(of:"@missing",options:.backwards).location
    #expect(storage.attribute(.foregroundColor,at:visible,effectiveRange:nil) as? NSColor == StudioTheme.undeclaredVariable)
    controller.editor.selectAll(nil)
    controller.editor.toggleSQLComment(nil)
    #expect(!document.sql.contains("…") && document.sql.contains(" -- SELECT @missing;"))
    #expect(document.sql==controller.editor.string && document.lastExecutedSQL==nil)
  }
  @Test func commentShortcutsCanBeCustomizedAndDoNotOverrideHistoryOrFind() throws {
    let key="shortcut.comment",old=UserDefaults.standard.object(forKey:key)
    defer {if let old {UserDefaults.standard.set(old,forKey:key)} else {UserDefaults.standard.removeObject(forKey:key)}}
    func event(_ text:String,_ flags:NSEvent.ModifierFlags)throws->NSEvent {try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:0))}
    #expect(GridShortcuts.save(try event("z",.command),action:.comment) != nil)
    #expect(GridShortcuts.save(try event("f",.command),action:.comment) != nil)
    #expect(GridShortcuts.save(try event("k",[.command,.shift]),action:.comment)==nil)
    #expect(GridShortcuts.matches(.comment,try event("k",[.command,.shift])))
    GridShortcuts.reset(.comment)
    #expect(GridShortcuts.binding(.comment).key=="/")
    #expect(GridShortcuts.matches(.comment,try event("/",[.command,.shift])))
    #expect(GridShortcuts.matches(.uncomment,try event("/",[.command,.option,.shift])))
    #expect(GridShortcuts.save(try event("/",[.command,.shift]),action:.comment)==nil)
    #expect(GridShortcuts.binding(.comment).flags == .command)
  }
}
