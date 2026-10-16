import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct DDLCompletionIntegrationTests {
  @Test func lateParameterResponseCannotReplaceVariableSuggestions() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    var pending:CheckedContinuation<Execution,Never>?
    server.asyncCatalogFixture={sql in
      if sql.contains("SELECT object_id") {var result=Execution();result.results=[Rows(values:[["42"]])];return result}
      return await withCheckedContinuation {pending=$0}
    }
    let doc=QueryDocument(server:server,database:"master",title:"Parameter completion race")
    doc.sql="DECLARE @city nvarchar(20); EXEC dbo.p @Name = @ci"
    doc.intelligenceCatalog = .init(snapshot:.init(symbols:[.init(schema:"dbo",name:"p",columns:[],kind:"SQL_STORED_PROCEDURE")]))
    doc.catalogDatabase="master"
    let controller=EditorController(document:doc),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:200,y:200,width:900,height:680),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface
    defer {controller.closeExecutionAssistance();window.close();if let pending {pending.resume(returning:Execution())}}
    window.makeKeyAndOrderFront(nil);window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location:doc.sql.utf16.count,length:0))
    controller.scheduleParameters(manual:true)
    for _ in 0..<100 where pending == nil {try await Task.sleep(for:.milliseconds(10))}
    #expect(pending != nil && controller.parameterShown)
    controller.scheduleIntelligence(manual:true)
    for _ in 0..<100 where !controller.completionShown {try await Task.sleep(for:.milliseconds(10))}
    #expect(controller.completionShown && !controller.parameterShown)
    var result=Execution();result.results=[Rows(values:[["1","@Name","nvarchar(20)","0","0"]])]
    pending?.resume(returning:result);pending=nil
    try await Task.sleep(for:.milliseconds(60))
    #expect(controller.completionShown && !controller.parameterShown)
    #expect(editor.string == doc.sql)
  }
  @Test func declaredVariableCompletionCanOpenWhileParameterHelpIsShown() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Variable completion")
    doc.sql="DECLARE @city nvarchar(20); EXEC dbo.p @Name = @ci"
    let controller=EditorController(document:doc),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:200,y:200,width:800,height:500),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface;window.makeKeyAndOrderFront(nil);window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location:doc.sql.utf16.count,length:0))
    let completion=EditorCompletionController(document:doc,editor:editor)
    defer {completion.cancel();window.close()}
    completion.parametersShown={true}
    completion.anchor={NSRect(x:20,y:20,width:1,height:20)}
    completion.scheduleIntelligence(manual:true)
    for _ in 0..<100 where !completion.isShown {try await Task.sleep(for:.milliseconds(10))}
    #expect(window.firstResponder === editor)
    #expect(completion.currentAnalysis?.variableCompletion == true)
    #expect(completion.currentAnalysis?.suggestions.contains(where:{$0.text == "@city"}) == true)
    #expect(completion.isShown)
  }
  @Test func tableViewFunctionAndProcedureAcceptancePreservesCaretUndoAndQuery() async throws {
    _=NSApplication.shared
    let keys=[SQLEditorPreferences.completionSchemaKey,SQLEditorPreferences.completionBracketsKey,"sqlAutomaticAliases","sqlAutomaticNoLock","sqlAutomaticCompletion",SQLEditorPreferences.completionDelayKey]
    let old=keys.map {UserDefaults.standard.object(forKey:$0)}
    defer {for (i,key) in keys.enumerated() {if let value=old[i] {UserDefaults.standard.set(value,forKey:key)} else {UserDefaults.standard.removeObject(forKey:key)}}}
    UserDefaults.standard.set(true,forKey:SQLEditorPreferences.completionSchemaKey)
    UserDefaults.standard.set(false,forKey:SQLEditorPreferences.completionBracketsKey)
    UserDefaults.standard.set(false,forKey:"sqlAutomaticAliases")
    UserDefaults.standard.set(false,forKey:"sqlAutomaticNoLock")
    UserDefaults.standard.set(true,forKey:"sqlAutomaticCompletion")
    UserDefaults.standard.set(50,forKey:SQLEditorPreferences.completionDelayKey)
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"DDL completion")
    doc.intelligenceCatalog=SQLIntelligence.Catalog(snapshot:.init(symbols:[
      .init(schema:"dbo",name:"Customers",columns:["Name"]),
      .init(schema:"dbo",name:"ActiveCustomers",columns:["Name"],kind:"VIEW"),
      .init(schema:"dbo",name:"ufn_Label",columns:[],kind:"SQL_SCALAR_FUNCTION"),
      .init(schema:"dbo",name:"ufn_Rows",columns:["Name"],kind:"SQL_INLINE_TABLE_VALUED_FUNCTION"),
      .init(schema:"dbo",name:"usp_LoadCustomers",columns:[],kind:"SQL_STORED_PROCEDURE")]))
    doc.catalogDatabase="master";doc.catalogVerified=true
    let controller=EditorController(document:doc),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:-20_000,y:0,width:900,height:680),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface
    defer {editor.dismissSuggestions?();window.close()}
    window.makeKeyAndOrderFront(nil);window.makeFirstResponder(editor)
    for (source,expected,call) in [
      ("SELECT * FROM Cu","SELECT * FROM dbo.Customers",false),
      ("SELECT * FROM dbo.Active","SELECT * FROM dbo.ActiveCustomers",false),
      ("SELECT dbo.ufn_La","SELECT dbo.ufn_Label()",true),
      ("SELECT * FROM dbo.ufn_Ro","SELECT * FROM dbo.ufn_Rows()",true),
      ("EXEC dbo.usp_Lo","EXEC dbo.usp_LoadCustomers",false)
    ] {
      editor.dismissSuggestions?();doc.sql=source;controller.setText()
      editor.setSelectedRange(NSRange(location:source.utf16.count,length:0));editor.undoManager?.removeAllActions()
      controller.scheduleIntelligence(manual:true)
      for _ in 0..<200 where !controller.completionShown {try await Task.sleep(for:.milliseconds(10))}
      #expect(controller.completionShown,"\(source)")
      let tab=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48))
      editor.keyDown(with:tab)
      #expect(editor.string==expected && doc.sql==expected)
      #expect(editor.selectedRange()==NSRange(location:expected.utf16.count-(call ? 1:0),length:0))
      #expect(window.firstResponder === editor && doc.lastExecutedSQL==nil)
      editor.undoManager?.undo();#expect(editor.string==source && doc.sql==source)
      editor.undoManager?.redo();#expect(editor.string==expected && doc.sql==expected)
    }
    for source in ["SELECT * FROM ","SELECT dbo.u","EXEC "] {
      editor.dismissSuggestions?();doc.sql=source;controller.setText();editor.setSelectedRange(NSRange(location:source.utf16.count,length:0))
      controller.scheduleIntelligence()
      for _ in 0..<200 where !controller.completionShown {try await Task.sleep(for:.milliseconds(10))}
      #expect(controller.completionShown,"Automatic DDL completion: \(source)")
    }
  }
}
