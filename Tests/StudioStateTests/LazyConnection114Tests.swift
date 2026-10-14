import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct LazyConnection114Tests {
  private func document() -> QueryDocument {
    let server=ConnectedServer(profile:ServerProfile(visibleDatabases:[]),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Lazy fixture");doc.sql="SELECT 1;"
    doc.sessionProbeFixture={_,_ in var result=Execution();result.results=[Rows(values:[["0","master"]])];return result}
    return doc
  }
  private func wait(_ condition:()->Bool) async throws {
    for _ in 0..<400 {if condition() {return};try await Task.sleep(for:.milliseconds(5))}
    Issue.record("Fixture did not finish")
  }
  private func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}

  @Test func offlineNewQueryOpensImmediatelyWithoutExplorerOrQueryConnection() throws {
    _=NSApplication.shared
    let state=StudioState(),doc=document();let server=doc.server
    state.servers=[server]
    var reconnects=0;server.reconnectFixture={reconnects += 1}
    let workbench=WorkbenchController(state:state);_ = workbench.view
    server.reconnecting=true
    workbench.openNewQuery(server:server,database:"other")
    let opened=try #require(state.active)
    #expect(state.documents.count == 1 && opened.database == "other" && opened.state == .disconnected)
    #expect(opened.task == nil && reconnects == 0 && !server.online)
    opened.useDatabase("third");#expect(opened.database == "third" && opened.task == nil)
    server.reconnecting=false
  }
  @Test func explicitExecuteConnectsOnceAndUsesClickedSelectionSnapshot() async throws {
    let doc=document();doc.sql="SELECT 1; SELECT 2;";doc.selectedRange=NSRange(location:0,length:9)
    var continuation:CheckedContinuation<Void,Never>?,connections=0,executions:[String]=[]
    doc.connectionFixture={profile,_ in
      #expect(profile.database == "master");connections += 1
      await withCheckedContinuation {continuation=$0}
    }
    doc.executionFixture={sql,_ in executions.append(sql);return Execution()}
    doc.execute();#expect(doc.state == .connecting)
    try await wait {continuation != nil}
    doc.sql="DELETE FROM dbo.Example;";doc.selectedRange=NSRange(location:0,length:0)
    doc.execute();#expect(connections == 1 && executions.isEmpty)
    continuation?.resume();try await wait {doc.state == .ready && doc.task == nil}
    #expect(executions == ["SELECT 1;"] && doc.sql == "DELETE FROM dbo.Example;" && !doc.server.online)
  }
  @Test func failureIsVisibleRetryIsExplicitAndNeverRunsSQL() async throws {
    let doc=document();var connections=0,executions=0
    doc.connectionFixture={_,_ in connections += 1;throw SQLFailure("Synthetic login failure")}
    doc.executionFixture={_,_ in executions += 1;return Execution()}
    doc.execute();try await wait {doc.state == .disconnected && doc.task == nil}
    #expect(doc.connectionError == "Synthetic login failure" && connections == 1 && executions == 0)
    doc.execute();try await wait {doc.state == .disconnected && doc.task == nil}
    #expect(connections == 2 && executions == 0 && doc.canExecute)
  }
  @Test func cancelledOrChangedTargetConnectionNeverSendsSQL() async throws {
    for cancel in [true,false] {
      let doc=document();var continuation:CheckedContinuation<Void,Never>?,executions=0
      doc.connectionFixture={_,_ in await withCheckedContinuation {continuation=$0}}
      doc.executionFixture={_,_ in executions += 1;return Execution()}
      doc.execute();try await wait {continuation != nil}
      if cancel {doc.cancel()} else {doc.server.generation=UUID()}
      continuation?.resume();try await wait {doc.state == .disconnected && doc.task == nil}
      #expect(executions == 0 && doc.connectionError != nil && doc.transactionCount == 0)
    }
  }
  @Test func savedSQLPasteUsesCaretAndSelectionWithOneUndoWithoutConnection() throws {
    _=NSApplication.shared
    let doc=document();doc.sql="SELECT 1;";doc.savedText=doc.sql
    let controller=EditorController(document:doc),editor=controller.editor
    let undo=try #require(editor.undoManager);undo.groupsByEvent=false
    editor.setSelectedRange(NSRange(location:7,length:1))
    undo.beginUndoGrouping();try controller.insertSQLAtCaret("N'İzmir 😀'");undo.endUndoGrouping()
    #expect(doc.sql == "SELECT N'İzmir 😀';" && doc.dirty && doc.state == .disconnected && doc.task == nil)
    undo.undo();#expect(doc.sql == "SELECT 1;" && !doc.dirty)
    undo.redo();#expect(doc.sql == "SELECT N'İzmir 😀';")
    editor.setSelectedRange(NSRange(location:0,length:0));undo.beginUndoGrouping();try controller.insertSQLAtCaret("-- note\n");undo.endUndoGrouping()
    #expect(doc.sql.hasPrefix("-- note\nSELECT"))
    undo.groupsByEvent=true
  }
  @Test func inlinePreviewPreservesSQLSelectionUndoResultsAndTransaction() throws {
    _=NSApplication.shared
    let doc=document();doc.savedText=doc.sql
    let controller=QueryController(document:doc);_ = controller.view
    let editor=try #require(descendants(controller.view).compactMap {$0 as? SQLTextView}.first)
    editor.setSelectedRange(NSRange(location:7,length:0));editor.insertText("2 + ",replacementRange:editor.selectedRange());editor.finishUndoInput()
    let sql=doc.sql,selection=editor.selectedRange(),undo=editor.undoManager
    doc.results=[Rows(fields:[Field("n")],values:[["1"]])];doc.transactionCount=1
    let value=IndexedObjectDefinition(id:1,schema:"dbo",name:"Example",type:"V",sql:"CREATE VIEW dbo.Example AS SELECT 1 AS n;")
    doc.offlinePreview=OfflineDefinitionPreview(server:doc.server,database:"archive",value:value)
    controller.update()
    #expect(doc.sql == sql && editor.selectedRange() == selection && editor.undoManager === undo)
    #expect(!editor.isEditable && !doc.canExecute && doc.results.count == 1 && doc.transactionCount == 1 && doc.moduleOriginal == nil)
    #expect(throws:(any Error).self) {try controller.insertSQLAtCaret("DELETE")}
    doc.execute();#expect(doc.task == nil)
    doc.offlinePreview=nil;controller.update()
    #expect(editor.isEditable && editor.selectedRange() == selection && doc.sql == sql)
    undo?.undo();#expect(doc.sql == "SELECT 1;")
  }
  @Test func definitionReferenceIgnoresLiteralCommentAndCrossDatabaseNames() {
    #expect(DefinitionReference.parts(in:"SELECT * FROM [dbo].[Example]",at:24) == ["dbo","Example"])
    #expect(DefinitionReference.parts(in:"SELECT * FROM other.dbo.Example",at:26) == nil)
    #expect(DefinitionReference.parts(in:"SELECT 'Example' -- Example",at:11) == nil)
    #expect(DefinitionReference.parts(in:"SELECT 'Example' -- Example",at:23) == nil)
  }
  @Test func coldOfflineCommandBUsesDiskAndSameTabWithoutReplacingSQL() async throws {
    _=NSApplication.shared
    let url=URL(fileURLWithPath:"/tmp/Offline114-"+UUID().uuidString).appendingPathComponent("index.sqlite")
    defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url)
    let profile=ServerProfile(visibleDatabases:["master"],indexObjectDefinitions:true)
    let server=ConnectedServer(profile:profile,password:"",diskIndex:disk,objectIndexService:CatalogIndexService(index:disk),completionIndexService:SQLCatalogService(index:disk));server.online=false
    server.databases=[CatalogItem(id:1,name:"master")]
    await server.definitionIndex.configure()
    let lease=try #require(try await disk.configureDefinitions(owner:server.id,enabled:true))
    let scope=CatalogDiskIndex.scope(profile:profile,database:"master")
    try await disk.saveDefinition(.init(id:42,schema:"dbo",name:"Example",type:"V",sql:"CREATE VIEW dbo.Example AS SELECT 1 AS n;"),owner:server.id,lease:lease,scope:scope,generation:disk.generation(scope:scope))
    let state=StudioState();state.servers=[server]
    let doc=state.newQuery(server:server,text:"SELECT * FROM dbo.Example;")
    let workbench=WorkbenchController(state:state)
    let window=NSWindow(contentRect:NSRect(x:-20000,y:0,width:1200,height:800),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentViewController=workbench;window.orderFront(nil);defer {window.close()}
    let controller=try #require(workbench.queryController(for:doc))
    let editor=try #require(descendants(controller.view).compactMap {$0 as? SQLTextView}.first)
    editor.setSelectedRange(NSRange(location:22,length:0))
    let event=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,characters:"b",charactersIgnoringModifiers:"b",isARepeat:false,keyCode:11))
    #expect(editor.performKeyEquivalent(with:event))
    try await wait {doc.offlinePreview != nil}
    #expect(doc.intelligenceCatalog == nil && state.documents.count == 1 && state.active === doc)
    #expect(doc.offlinePreview?.value.id == 42 && doc.sql == "SELECT * FROM dbo.Example;" && doc.task == nil && !server.online)
    // The read-only preview itself supports Command+B with the indexed source scope.
    controller.update();controller.view.layoutSubtreeIfNeeded();window.displayIfNeeded()
    try await Task.sleep(for:.milliseconds(60))
    let preview=try #require(descendants(controller.view).compactMap {$0 as? NSTextView}.first {$0.identifier?.rawValue == "sqlSourcePreview"})
    preview.setSelectedRange(NSRange(location:19,length:0));preview.keyDown(with:event)
    try await Task.sleep(for:.milliseconds(30))
    #expect(state.documents.count == 1 && doc.sql == "SELECT * FROM dbo.Example;")
    doc.offlinePreview=nil;controller.update()
    #expect(editor.selectedRange().location == 22 && editor.isEditable)
    server.online=true
    workbench.openOfflineDefinition(named:["dbo","Example"],server:server,database:"master",in:doc)
    #expect(doc.offlinePreview == nil) // Online paths never substitute disk SQL.
  }
  @Test func nativeFavoriteDoubleClickInsertsIntoCapturedEditorWithoutNewTab() async throws {
    _=NSApplication.shared
    let state=StudioState(),base=document();state.servers=[base.server]
    let doc=state.newQuery(server:base.server,text:"SELECT 1;")
    let workbench=WorkbenchController(state:state);_ = workbench.view
    let query=try #require(workbench.queryController(for:doc))
    let editor=try #require(descendants(query.view).compactMap {$0 as? SQLTextView}.first)
    editor.setSelectedRange(NSRange(location:7,length:1))
    let url=URL(fileURLWithPath:"/tmp/Favorite114-"+UUID().uuidString).appendingPathComponent("favorites.json")
    defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let model=FavoriteQueriesModel(url:url)
    let favorite=try FavoriteQuery(name:"Fixture",sql:"42",scope:.global)
    try await model.save(favorite)
    var opens=0
    let picker=FavoriteQueryPickerController(model:model,serverID:doc.server.id,database:doc.database,contextLabel:"Fixture",open:{_ in opens += 1},insert:{favorite in try workbench.insertSavedSQL(favorite.sql,into:doc)},manage:{})
    _ = picker.view
    let table=try #require(descendants(picker.view).compactMap {$0 as? NSTableView}.first)
    table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
    picker.perform(try #require(table.doubleAction))
    #expect(doc.sql == "SELECT 42;" && state.documents.count == 1 && opens == 0 && doc.task == nil)
    #expect(throws:(any Error).self) {try workbench.insertSavedSQL("42",into:nil)}
  }

  @Test func pendingConnectionShowsStatusAndAllowsAnotherTabThenReportsFailure() async throws {
    _=NSApplication.shared
    let state=StudioState(),base=document();state.servers=[base.server]
    let doc=state.newQuery(server:base.server,text:"SELECT 1;")
    let host=WorkbenchController(state:state);_ = host.view
    var continuation:CheckedContinuation<Void,Never>?
    doc.connectionFixture={_,_ in await withCheckedContinuation {continuation=$0};throw SQLFailure("Synthetic status failure")}
    let status=try #require(descendants(host.view).compactMap {$0 as? NSTextField}.first {$0.accessibilityIdentifier() == "queryStatus"})
    doc.execute();try await wait {continuation != nil}
    #expect(status.stringValue.contains("Connecting"))
    host.openNewQuery(server:doc.server,database:"other")
    #expect(state.documents.count == 2 && state.active !== doc && status.stringValue.contains("Çalıştırıldığında bağlanacak"))
    continuation?.resume();try await wait {doc.state == .disconnected && doc.task == nil}
    state.active=doc;state.changed?()
    #expect(status.stringValue.contains("Synthetic status failure") && status.toolTip == "Synthetic status failure")
  }

}
