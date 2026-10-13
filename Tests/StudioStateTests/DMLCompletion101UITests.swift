import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct DMLCompletion101UITests {
  @Test func oneAtSignAutomaticallyShowsDeclaredVariablesAndTabPreservesUndo() async throws {
    _=NSApplication.shared
    let key="sqlAutomaticCompletion",old=UserDefaults.standard.object(forKey:key);UserDefaults.standard.set(true,forKey:key)
    defer {if let old {UserDefaults.standard.set(old,forKey:key)} else {UserDefaults.standard.removeObject(forKey:key)}}
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Variables");doc.sql="DECLARE @DEGISKEN int; SELECT "
    let controller=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:50,y:50,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=controller.surface
    defer {controller.editor.dismissSuggestions?();window.close()}
    window.makeKeyAndOrderFront(nil);window.makeFirstResponder(controller.editor)
    let editor=controller.editor;editor.setSelectedRange(NSRange(location:editor.string.utf16.count,length:0));editor.insertText("@",replacementRange:editor.selectedRange())
    let before=editor.string
    for _ in 0..<200 where !controller.completionShown {try await Task.sleep(for:.milliseconds(10))}
    #expect(controller.completionShown && window.firstResponder === editor)
    let tab=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48))
    editor.keyDown(with:tab)
    #expect(editor.string=="DECLARE @DEGISKEN int; SELECT @DEGISKEN" && doc.sql==editor.string)
    editor.undoManager?.undo();#expect(editor.string==before && editor.textLayoutManager != nil)
    #expect(SQLSuggestionStyle.title(.variable)=="Değişken" && SQLSuggestionStyle.symbol(.variable)=="at")
  }
}
