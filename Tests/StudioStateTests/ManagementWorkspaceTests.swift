import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ManagementWorkspaceTests {
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
  @Test func closeAllIncludesPinnedTabsWithoutWarningForGeneratedSQL() throws {
    let state=StudioState(),server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let host=WorkbenchController(state:state);_=host.view
    let a=state.newQuery(server:server,text:"SELECT 1"),b=state.newQuery(server:server,text:"SELECT 2");a.pinned=true
    let item=try #require(host.tabMenu(for:b).items.first {$0.title == "Close All Tabs"})
    #expect(NSApp.sendAction(try #require(item.action),to:item.target,from:item))
    #expect(state.documents.isEmpty)
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
