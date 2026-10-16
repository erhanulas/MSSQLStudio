import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ExecutionChooser115Tests {
  private func setup(_ sql:String)->(QueryDocument,EditorController) {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(visibleDatabases:[]),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Chooser fixture");doc.sql=sql;doc.savedText=sql;doc.state = .ready
    doc.executionFixture={_,_ in Execution()}
    return (doc,EditorController(document:doc))
  }
  private func wait(_ predicate:()->Bool) async throws {
    for _ in 0..<400 {if predicate() {return};try await Task.sleep(for:.milliseconds(5))}
    Issue.record("Chooser fixture did not finish")
  }
  private func commandEnter(_ controller:EditorController)throws {
    let event=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36))
    controller.editor.keyDown(with:event)
  }
  @Test func menuHighlightRevealsAndFramesSQLWithoutChangingCaretOrExecuting() async throws {
    let sql=(0..<100).map {"SELECT \($0);"}.joined(separator:"\n")
    let (doc,controller)=setup(sql),editor=controller.editor
    let window=NSWindow(contentRect:NSRect(x:200,y:200,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=controller.surface
    defer {window.close()}
    window.makeKeyAndOrderFront(nil);window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location:0,length:0))
    let source=sql as NSString,range=source.range(of:"SELECT 90;")
    let content=try #require(editor.textContentStorage)
    editor.textLayoutManager?.ensureLayout(for:content.documentRange)
    let menu=StudioMenu(),item=NSMenuItem(title:"Statement",action:nil,keyEquivalent:"")
    item.representedObject=NSValue(range:range);menu.addItem(item)
    let preview=SQLExecutionPreview {controller.previewExecutionRange($0)}
    preview.menu(menu,willHighlight:item)
    try await Task.sleep(for:.milliseconds(50))
    controller.surface.layoutSubtreeIfNeeded();window.displayIfNeeded()
    #expect(controller.occurrenceHighlights.executionRange == range)
    #expect(controller.occurrenceHighlights.executionFrame(in:controller.occurrenceHighlights.bounds) != nil)
    #expect((editor.enclosingScrollView?.contentView.bounds.minY ?? 0) > 0)
    #expect(editor.selectedRange() == NSRange(location:0,length:0) && doc.sql == sql && doc.lastExecutedSQL == nil)
    preview.menuDidClose(menu)
    #expect(controller.occurrenceHighlights.executionRange == nil)
  }
  @Test func commandEnterChoosesExactStatementAndKeepsSQLCaretUndo() async throws {
    let (doc,controller)=setup("SELECT 1;\nSELECT N'İzmir 😀';")
    controller.editor.setSelectedRange(NSRange(location:15,length:0))
    let selection=doc.selectedRange,undo=controller.editor.undoManager
    var executions:[String]=[],choices=0
    doc.executionFixture={sql,_ in executions.append(sql);return Execution()}
    controller.executionChoiceFixture={ranges in choices += 1;#expect(ranges.count == 3);return 1}
    try commandEnter(controller)
    #expect(executions.isEmpty)
    try await wait {doc.task == nil && !executions.isEmpty}
    #expect(executions == ["SELECT N'İzmir 😀';"] && choices == 1)
    #expect(doc.sql == "SELECT 1;\nSELECT N'İzmir 😀';" && !doc.dirty && doc.selectedRange == selection && controller.editor.undoManager === undo)
  }
  @Test func explicitSelectionBypassesChooserAndCancelDoesNotExecute() async throws {
    let (doc,controller)=setup("SELECT 1; SELECT 2;")
    var executions:[String]=[],choices=0
    doc.executionFixture={sql,_ in executions.append(sql);return Execution()}
    controller.executionChoiceFixture={_ in choices += 1;return nil}
    controller.editor.setSelectedRange(NSRange(location:10,length:9))
    try commandEnter(controller);try await wait {doc.task == nil && !executions.isEmpty}
    #expect(executions == ["SELECT 2;"] && choices == 0)
    controller.editor.setSelectedRange(NSRange(location:0,length:0));try commandEnter(controller)
    try await wait {choices == 1}
    #expect(executions.count == 1 && doc.task == nil)
  }
  @Test func allChoicePreservesDeclarationAndGoRepeatWhileStaleChoiceNeverRuns() async throws {
    let source="DECLARE @x int=1; SELECT @x;\nGO 2\nSELECT 3;"
    let (doc,controller)=setup(source)
    var executions:[String]=[]
    doc.executionFixture={sql,_ in executions.append(sql);return Execution()}
    controller.executionChoiceFixture={ranges in ranges.count-1}
    try commandEnter(controller);try await wait {!executions.isEmpty && doc.task == nil}
    #expect(executions == [source])
    var choices=0
    controller.executionChoiceFixture={_ in choices += 1;doc.sql="DELETE FROM dbo.Example;";return 0}
    try commandEnter(controller);try await wait {choices == 1}
    #expect(executions.count == 1)
  }
  @Test func oneStatementRunsDirectlyAndReadonlyBusyNeverPresentsChooser() async throws {
    let (doc,controller)=setup("SELECT 1 UNION ALL SELECT 2;")
    var executions=0,choices=0
    doc.executionFixture={_,_ in executions += 1;return Execution()}
    controller.executionChoiceFixture={_ in choices += 1;return 0}
    try commandEnter(controller);try await wait {executions == 1 && doc.task == nil}
    #expect(choices == 0)
    doc.state = .running;try commandEnter(controller);#expect(choices == 0 && executions == 1)
    doc.state = .ready
    doc.offlinePreview=OfflineDefinitionPreview(server:doc.server,database:"master",value:.init(id:1,schema:"dbo",name:"Example",type:"V",sql:"SELECT 1;"))
    try commandEnter(controller);#expect(choices == 0 && executions == 1)
  }
  @Test func formattingPreferencesLegacyAndSearchKeepExistingSettings() throws {
    let suite="local.mssqlstudio.format115-"+UUID().uuidString,defaults=try #require(UserDefaults(suiteName:suite))
    defer {defaults.removePersistentDomain(forName:suite)}
    let options=SQLFormattingOptions(indentWidth:8,keywordCase:.lower,commaStyle:.leading,blankLineAfterSelect:false,blankLineAfterDeclare:true)
    SQLEditorPreferences.saveFormatting(options,in:defaults)
    #expect(SQLEditorPreferences.formatting(in:defaults) == options)
    #expect(SettingsSearch.entries.contains {$0.id == "formatSelectGap"})
    #expect(SettingsSearch.entries.contains {$0.id == "formatDeclareGap"})
  }
}
