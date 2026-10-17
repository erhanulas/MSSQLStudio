import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct DMLCompletion101UITests {
  @Test func mergeTargetSourceAndInsertColumnSuggestionsAcceptWithOneUndo() async throws {
    _=NSApplication.shared
    let key=SQLEditorPreferences.completionBracketsKey,old=UserDefaults.standard.object(forKey:key)
    UserDefaults.standard.set(true,forKey:key)
    defer {if let old {UserDefaults.standard.set(old,forKey:key)} else {UserDefaults.standard.removeObject(forKey:key)}}
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"MERGE")
    doc.intelligenceCatalog = .init(snapshot:.init(symbols:[CatalogSymbol(schema:"dbo",name:"Target",columns:["STOK_KODU","HUCREKODU","MIKTAR"])]))
    doc.catalogDatabase="master";doc.catalogVerified=true
    let controller=EditorController(document:doc)
    let window=NSWindow(contentRect:NSRect(x:50,y:50,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface
    defer {controller.editor.dismissSuggestions?();window.close()}
    window.makeKeyAndOrderFront(nil);window.makeFirstResponder(controller.editor)
    for (action,typed,accepted) in [
      ("WHEN MATCHED THEN UPDATE SET T.MI§=S.MIKTAR","MI","[MIKTAR]"),
      ("WHEN MATCHED THEN UPDATE SET T.MIKTAR=S.MI§","MI","[MIKTAR]"),
      ("WHEN NOT MATCHED THEN INSERT (STOK_KODU, HUCR§) VALUES (S.STOK_KODU, 1)","HUCR","[HUCREKODU]")
    ] {
      let marked="MERGE dbo.Target T USING (SELECT STOK_KODU='X', MIKTAR=1) S ON T.STOK_KODU=S.STOK_KODU "+action+";"
      let caret=(marked as NSString).range(of:"§").location,source=marked.replacingOccurrences(of:"§",with:"")
      controller.replaceText(source);controller.editor.setSelectedRange(NSRange(location:caret,length:0))
      controller.editor.undoManager?.removeAllActions();controller.scheduleIntelligence(manual:true)
      for _ in 0..<200 where !controller.completionShown {try await Task.sleep(for:.milliseconds(10))}
      #expect(controller.completionShown && window.firstResponder === controller.editor)
      let tab=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48))
      controller.editor.keyDown(with:tab)
      let expected=(source as NSString).replacingCharacters(in:NSRange(location:caret-typed.utf16.count,length:typed.utf16.count),with:accepted)
      #expect(controller.editor.string==expected && doc.sql==expected)
      controller.editor.undoManager?.undo();#expect(controller.editor.string==source)
      controller.editor.dismissSuggestions?()
    }
  }
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
