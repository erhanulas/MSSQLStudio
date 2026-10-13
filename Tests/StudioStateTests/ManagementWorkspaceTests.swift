import AppKit
import SQLServerKit
import Testing
import SwiftUI
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ManagementWorkspaceTests {
  @Test func submitEligibilityTracksConnectionTransactionAndPendingChanges() {
    let server=ConnectedServer(profile:ServerProfile(),password:"")
    server.online=true
    let doc=QueryDocument(server:server,database:"Demo",title:"P")
    doc.state = .ready;doc.moduleObjectID=42
    doc.objectEditorKey=ObjectEditorKey(serverID:server.id,database:"Demo",objectID:42)
    doc.moduleOriginal="CREATE PROC dbo.P AS SELECT 1;"
    doc.moduleInitialSQL="ALTER PROC dbo.P AS SELECT 1;";doc.sql=doc.moduleInitialSQL!
    #expect(!doc.canSubmitModule)
    doc.sql="ALTER PROC dbo.P AS SELECT 2;";#expect(doc.canSubmitModule)
    doc.transactionCount=1;#expect(!doc.canSubmitModule);doc.transactionCount=0
    doc.state = .running;#expect(!doc.canSubmitModule);doc.state = .ready
    doc.database="Other";#expect(!doc.canSubmitModule);doc.database="Demo"
    server.online=false;#expect(!doc.canSubmitModule)
  }
  @Test func reviewUsesSourceColorsAcrossAlignedMultilineRowsAndSubmitsOnlyOnClick() async throws {
    let previousTheme=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previousTheme ?? "light");if previousTheme == nil {UserDefaults.standard.removeObject(forKey:"ssmsTheme")}}
    let parent=NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:800),styleMask:[.titled],backing:.buffered,defer:false)
    parent.isReleasedWhenClosed=false
    var submitted=0
    let old="ALTER PROC dbo.P AS\n/* first\nsecond */\nDECLARE @unused int;\nSELECT N'İstanbul 😀', 1;"
    let edited=old.replacingOccurrences(of:"/* first",with:"-- inserted\n/* first").replacingOccurrences(of:", 1;",with:", 2;")
    let review=ModuleReviewController(parent:parent,title:"Fixture / Demo / P",original:old,edited:edited,canApply:true,approved:{submitted+=1},finished:{})
    defer {withExtendedLifetime(review) {};parent.close()}
    let sheet=try #require(parent.attachedSheet)
    let expectedWidth=max(960,min(1400,(parent.screen?.visibleFrame.width ?? (1400/0.94))*0.94))
    #expect(abs((sheet.contentView?.bounds.width ?? 0)-expectedWidth) < 2)
    func descendants(_ view:NSView) -> [NSView] { [view]+view.subviews.flatMap(descendants) }
    StudioTheme.decorate(try #require(sheet.contentView))
    let children=descendants(try #require(sheet.contentView))
    let texts=children.compactMap {$0 as? NSTextView}
    let submit=try #require(children.compactMap {$0 as? NSButton}.first {$0.title == "Veritabanına Gönder"})
    let deadline=ContinuousClock.now.advanced(by:.seconds(2))
    while !submit.isEnabled && ContinuousClock.now < deadline {try await Task.sleep(for:.milliseconds(20))}
    #expect(texts.count == 3)
    for text in texts {text.setSelectedRange((text.string as NSString).range(of:"İstanbul 😀"))}
    let sources=texts.map(\.string),selections=texts.map {$0.selectedRange()},viewports=texts.map {$0.enclosingScrollView?.contentView.bounds.origin}
    for theme in ["light","dark","light"] {
      StudioTheme.apply(theme)
      for (index,text) in texts.enumerated() {
      let storage=try #require(text.textContentStorage?.textStorage)
      let source=text.string as NSString
      for (needle,color) in [("ALTER",StudioTheme.syntax(.keyword)),("second */",StudioTheme.syntax(.comment)),("@unused",StudioTheme.unusedVariable),("N'İstanbul 😀'",StudioTheme.syntax(.string))] {
        let range=source.range(of:needle)
        #expect(range.location != NSNotFound)
        #expect(storage.attribute(.foregroundColor,at:range.location,effectiveRange:nil) as? NSColor == color)
      }
      #expect(text.textLayoutManager != nil && !text.isEditable)
      #expect(text.enclosingScrollView?.contentView.bounds.minX == 0)
      #expect(text.backgroundColor == StudioTheme.editorCanvas)
      #expect(text.string == sources[index] && text.selectedRange() == selections[index])
      #expect(text.enclosingScrollView?.contentView.bounds.origin == viewports[index])
      }
    }
    #expect(submit.isEnabled && submitted == 0)
    submit.performClick(nil)
    #expect(submitted == 1 && parent.attachedSheet == nil)
  }

  @Test func generatedSQLIsCleanTypingAndUndoDetermineCloseConfirmation() {
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=state.newQuery(server:server,text:"SELECT 1;",title:"Generated")
    #expect(!doc.dirty && !doc.needsCloseConfirmation)
    doc.sql+="\n-- user edit";#expect(doc.needsCloseConfirmation)
    doc.sql=doc.savedText;#expect(!doc.needsCloseConfirmation)
    #expect(state.close(doc) && state.documents.isEmpty)
  }
  @Test func moduleSaveAndApplyBaselinesPreserveSubsequentEdits() {
    let doc=QueryDocument(server:ConnectedServer(profile:ServerProfile(),password:""),database:"master",title:"Module")
    doc.moduleOriginal="CREATE PROC dbo.P AS SELECT 1;";doc.moduleInitialSQL="ALTER PROC dbo.P AS SELECT 1;";doc.sql=doc.moduleInitialSQL!;doc.savedText=doc.sql
    #expect(!doc.needsCloseConfirmation)
    let submitted="ALTER PROC dbo.P AS SELECT 2;";doc.sql=submitted;doc.savedText=submitted
    #expect(!doc.dirty && doc.hasPendingDatabaseChanges && doc.needsCloseConfirmation)
    doc.sql="ALTER PROC dbo.P AS SELECT 3;"
    doc.acceptAppliedModule(sql:submitted,original:submitted)
    #expect(doc.dirty && doc.hasPendingDatabaseChanges)
    doc.sql=submitted;#expect(!doc.needsCloseConfirmation)
    doc.file=URL(fileURLWithPath:"/tmp/Studio-file.sql");doc.savedText="disk baseline"
    doc.acceptAppliedModule(sql:submitted,original:submitted);#expect(doc.dirty)
  }
  @Test func reopeningObjectPreservesEditsAndSeparatesServersAndDatabases() {
    let state=StudioState(),a=ConnectedServer(profile:ServerProfile(),password:""),b=ConnectedServer(profile:ServerProfile(),password:"")
    a.online=false;b.online=false
    let host=WorkbenchController(state:state);_=host.view
    let first=host.openObjectEditor(server:a,database:"DB1",objectID:42,sql:"ALTER PROC P AS SELECT 1",title:"P",original:"CREATE PROC P AS SELECT 1")
    first.sql+=" -- keep edits"
    let duplicate=host.openObjectEditor(server:a,database:"DB1",objectID:42,sql:"overwrite",title:"Other")
    #expect(duplicate === first && first.sql.hasSuffix("keep edits") && state.documents.count == 1)
    _=host.openObjectEditor(server:a,database:"DB2",objectID:42,sql:"DB2",title:"P")
    _=host.openObjectEditor(server:b,database:"DB1",objectID:42,sql:"Server2",title:"P")
    #expect(state.documents.count == 3)
    #expect(host.activateObjectEditor(server:a,database:"DB1",objectID:42) && state.active === first)
  }
  @Test func alterOpeningUsesRawServerDefinitionForConflictAndScriptForDirtyBaseline() async throws {
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let raw="CREATE PROCEDURE [dbo].[Example] AS SELECT 1;"
    server.catalogFixture={sql in var e=Execution();e.results=[Rows(values:sql.contains("uses_ansi_nulls") ? [["1","1"]]:[[raw]])];return e}
    let host=WorkbenchController(state:state);_=host.view
    let node=TreeNode("dbo.Example",kind:.object(.procedures),server:server,database:"Sample",item:CatalogItem(id:99,name:"Example",schema:"dbo"))
    host.scriptManagedObject(node,mode:"MODIFY",destination:"New Query Editor Window")
    try await Task.sleep(for:.milliseconds(80))
    let doc=try #require(state.active)
    #expect(doc.moduleOriginal == raw && doc.moduleInitialSQL == doc.sql && !doc.needsCloseConfirmation)
    #expect(doc.sql.contains("SET ANSI_NULLS ON") && doc.sql.contains("ALTER PROCEDURE"))
    doc.sql+="\n-- keep";host.scriptManagedObject(node,mode:"ALTER",destination:"New Query Editor Window")
    try await Task.sleep(for:.milliseconds(30))
    #expect(state.documents.count == 1 && state.active === doc && doc.sql.hasSuffix("-- keep"))
  }
  @Test func closeAllIncludesPinnedTabsWithoutWarningForGeneratedSQL() async throws {
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let host=WorkbenchController(state:state);_=host.view
    let a=state.newQuery(server:server,text:"SELECT 1"),b=state.newQuery(server:server,text:"SELECT 2");a.pinned=true
    let item=try #require(host.tabMenu(for:b).items.first {$0.title == "Close All Tabs"})
    #expect(NSApp.sendAction(try #require(item.action),to:item.target,from:item))
    for _ in 0..<100 where !state.documents.isEmpty {await Task.yield()}
    #expect(state.documents.isEmpty)
  }
  @Test func agentPanelsOnlyReadOnOpenAndHistoryUsesNativeExpandableRows() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    var requests:[String]=[];var scripts:[String]=[]
    server.catalogFixture={sql in requests.append(sql);return ObjectManagementUIFixture.catalog(sql)}
    let host=WorkbenchController(state:StudioState())
    let history=host.present(AgentHistoryPanel(server:server,job:"Demo Nightly",includeSteps:true),title:"Synthetic Agent History",width:1200,height:800)
    let properties=host.present(AgentPropertiesPanel(server:server,name:"Demo Nightly",open:{scripts.append($0)}),title:"Synthetic Agent Properties",width:1200,height:800)
    defer {history.close();properties.close()}
    for _ in 0..<100 {
      if requests.contains(where:{$0.contains("StudioAgent.history")}) && requests.contains(where:{$0.contains("StudioAgent.details")}) {break}
      try await Task.sleep(for:.milliseconds(20))
    }
    #expect(requests.count == 2 && scripts.isEmpty)
    #expect(requests.allSatisfy {!$0.contains("EXEC msdb.dbo.sp_")})
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    var outline:NSOutlineView?
    for _ in 0..<50 {
      history.contentView?.layoutSubtreeIfNeeded()
      outline=descendants(try #require(history.contentView)).compactMap {$0 as? NSOutlineView}.first
      if outline?.numberOfRows == 2 {break}
      try await Task.sleep(for:.milliseconds(20))
    }
    let table=try #require(outline)
    #expect(table.numberOfRows == 2)
    table.expandItem(table.item(atRow:0))
    #expect(table.numberOfRows == 5)
    #expect(scripts.isEmpty && requests.count == 2)
  }
  @Test func databaseIndexControlFitsNextToNameInNarrowRow() throws {
    _ = NSApplication.shared
    let state=StudioState();state.recoveryEnabled=false
    let host=WorkbenchController(state:state);host.loadViewIfNeeded()
    let server=ConnectedServer(profile:ServerProfile(name:"Badge fixture"),password:"")
    let node=TreeNode("DemoDB",kind:.database,server:server,database:"DemoDB")
    let cell=try #require(host.outlineView(NSOutlineView(),viewFor:nil,item:node) as? NSTableCellView)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:210,height:25),styleMask:[],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    window.contentView=cell;cell.layoutSubtreeIfNeeded()
    defer {window.close()}
    let badge=try #require(cell.subviews.compactMap {$0 as? NSButton}.first)
    let label=try #require(cell.textField)
    #expect(badge.frame.minX >= label.frame.maxX)
    #expect(badge.frame.maxX <= cell.bounds.width)
    #expect(badge.frame.width == 24 && badge.frame.height == 24)
    #expect(badge.accessibilityLabel()?.contains("DemoDB") == true)
  }
  @Test func databaseRefreshReadsLoadedBranchesAndPreservesFolderIdentity() async throws {
    _ = NSApplication.shared
    let state=StudioState();state.recoveryEnabled=false
    let host=WorkbenchController(state:state);host.loadViewIfNeeded()
    let server=ConnectedServer(profile:ServerProfile(name:"Refresh fixture"),password:"")
    server.online=true
    var requests:[String]=[]
    server.catalogFixture={sql in requests.append(sql);return ObjectManagementUIFixture.catalog(sql)}
    let database=TreeNode("DemoDB",kind:.database,server:server,database:"DemoDB",item:CatalogItem(id:5,name:"DemoDB"))
    let tables=TreeNode("Tables",kind:.folder(.tables),server:server,database:"DemoDB")
    tables.loaded=true
    let views=TreeNode("Views",kind:.folder(.views),server:server,database:"DemoDB")
    let group=TreeNode("Programmability",kind:.group,server:server,database:"DemoDB")
    let procedures=TreeNode("Procedures",kind:.folder(.procedures),server:server,database:"DemoDB")
    procedures.loaded=true;group.children=[procedures]
    database.children=[tables,views,group]
    let document=QueryDocument(server:server,database:"DemoDB",title:"Keep SQL")
    document.sql="SELECT 1;";state.documents=[document];state.active=document
    host.refresh(database)
    for _ in 0..<100 {
      if requests.count == 2 && !tables.loading && !procedures.loading {break}
      try await Task.sleep(for:.milliseconds(20))
    }
    #expect(requests.count == 2)
    #expect(database.children[0] === tables && database.children[1] === views && database.children[2] === group)
    #expect(group.children[0] === procedures)
    #expect(tables.loaded && procedures.loaded && !views.loaded)
    #expect(requests.contains(Catalog.objects(.tables)) && requests.contains(Catalog.objects(.procedures)))
    #expect(document.sql == "SELECT 1;" && document.lastExecutedSQL == nil)
  }
  @Test func agentStepEditorOnlyReadsDatabaseMetadataOnOpen() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    var requests:[String]=[]
    server.catalogFixture={sql in requests.append(sql);return ObjectManagementUIFixture.catalog(sql)}
    let step=SQLAgent.Step(id:1,name:"Read",subsystem:"TSQL",database:"ArchivedDB",command:"SELECT 1;")
    let host=WorkbenchController(state:StudioState())
    let window=host.present(AgentStepEditor(server:server,step:step,steps:[step],isNew:false,open:{_ in}),title:"Synthetic Step Picker",width:900,height:650)
    defer {window.close()}
    for _ in 0..<100 {
      if !requests.isEmpty {break}
      try await Task.sleep(for:.milliseconds(20))
    }
    #expect(requests == [Catalog.databases])
    var external=step;external.subsystem="CmdExec"
    let readOnly=host.present(AgentStepEditor(server:server,step:external,steps:[external],isNew:false,open:{_ in Issue.record("Read-only editor submitted changes")}),title:"Synthetic Read-only Step",width:900,height:650)
    defer {readOnly.close()}
    try await Task.sleep(for:.milliseconds(60))
    #expect(requests == [Catalog.databases])
  }

  @Test func agentCommandSharesSQLColorsAndPreservesSelectionAndUndoAcrossThemes() async throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme")
    defer {StudioTheme.apply(previous ?? "light");if previous == nil {UserDefaults.standard.removeObject(forKey:"ssmsTheme")}}
    StudioTheme.apply("light")
    let original="DECLARE @unused int;\n/* first\nsecond */\nSELECT N'İstanbul 😀', GETDATE(), 42;"
    var command=original
    let host=WorkbenchController(state:StudioState())
    let window=host.present(AgentCommandEditor(text:Binding(get:{command},set:{command=$0})),title:"Synthetic Command Colors",width:900,height:650)
    defer {window.close()}
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    var editor:NSTextView?
    for _ in 0..<100 {
      window.contentView?.layoutSubtreeIfNeeded()
      editor=descendants(try #require(window.contentView)).compactMap {$0 as? NSTextView}.first {$0.identifier?.rawValue == "agentCommandEditor"}
      if editor?.string == original {break}
      try await Task.sleep(for:.milliseconds(20))
    }
    let view=try #require(editor),storage=try #require(view.textContentStorage?.textStorage)
    func expectColors() {
      for (needle,color) in [("DECLARE",StudioTheme.syntax(.keyword)),("second */",StudioTheme.syntax(.comment)),("N'İstanbul 😀'",StudioTheme.syntax(.string)),("@unused",StudioTheme.unusedVariable)] {
        let offset=(view.string as NSString).range(of:needle).location
        #expect(offset != NSNotFound)
        if offset != NSNotFound {#expect(storage.attribute(.foregroundColor,at:offset,effectiveRange:nil) as? NSColor == color)}
      }
      #expect(view.backgroundColor == StudioTheme.editorCanvas && view.textLayoutManager != nil)
    }
    expectColors()
    let selection=(original as NSString).range(of:"İstanbul 😀")
    view.setSelectedRange(selection)
    let viewport=view.enclosingScrollView?.contentView.bounds.origin
    StudioTheme.apply("dark")
    expectColors()
    #expect(view.selectedRange() == selection && view.string == original && command == original)
    #expect(view.enclosingScrollView?.contentView.bounds.origin == viewport)
    #expect(window.makeFirstResponder(view))
    view.setSelectedRange(NSRange(location:storage.length,length:0));view.breakUndoCoalescing()
    view.insertText("\nSELECT @unused;",replacementRange:view.selectedRange())
    #expect(command == view.string && view.undoManager?.canUndo == true)
    let variable=(view.string as NSString).range(of:"@unused")
    #expect(storage.attribute(.foregroundColor,at:variable.location,effectiveRange:nil) as? NSColor != StudioTheme.unusedVariable)
    view.undoManager?.undo()
    for _ in 0..<100 {
      if command == original && storage.attribute(.foregroundColor,at:variable.location,effectiveRange:nil) as? NSColor == StudioTheme.unusedVariable {break}
      try await Task.sleep(for:.milliseconds(20))
    }
    #expect(view.string == original && command == original)
    expectColors()
    #expect(view.undoManager?.canRedo == true)
    view.undoManager?.redo()
    #expect(view.string == original+"\nSELECT @unused;" && command == view.string)
    #expect(storage.attribute(.foregroundColor,at:variable.location,effectiveRange:nil) as? NSColor != StudioTheme.unusedVariable)
  }

  @Test func agentMenusExposeStateAwareCommandsAndDistinctIcons() {
    let server=ConnectedServer(profile:ServerProfile(),password:""),host=WorkbenchController(state:StudioState())
    let disabled=TreeNode("DisabledJob",kind:.object(.jobs),server:server,item:CatalogItem(name:"DisabledJob",detail:"Disabled, Idle"))
    let running=TreeNode("RunningJob",kind:.object(.jobs),server:server,item:CatalogItem(name:"RunningJob",detail:"Enabled, Running"))
    let off=host.agentMenu(for:disabled),on=host.agentMenu(for:running)
    #expect(off.items.contains {$0.title == "Enable…"} && on.items.contains {$0.title == "Disable…"})
    #expect(off.items.first {$0.title == "Stop Job…"}?.isEnabled == false)
    #expect(on.items.first {$0.title == "Stop Job…"}?.isEnabled == true)
    #expect(on.items.first {$0.title == "Start Job…"}?.isEnabled == false)
    #expect(off.items.contains {$0.title == "View History…"} && off.items.contains {$0.title == "Properties…"})
    #expect(disabled.icon != running.icon)
    #expect(off.items.filter {$0.title == "Stop Job…"}.allSatisfy {!host.validateUserInterfaceItem($0)})
    #expect(on.items.filter {$0.title == "Start Job…"}.allSatisfy {!host.validateUserInterfaceItem($0)})
  }
}
