import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct TriggerStateActionTests {
  private func metadata(disabled:Bool)->Execution {
    var output=Execution();output.results=[Rows(values:[["TR_Test","dbo","1","[dbo].[T]",disabled ? "1":"0"]])];return output
  }
  private func node(_ server:ConnectedServer)->TreeNode {
    TreeNode("dbo.TR_Test",kind:.object(.triggers),server:server,database:"master",item:.init(id:17,name:"TR_Test",schema:"dbo",detail:"SQL_TRIGGER"))
  }
  @Test func explicitConfirmationWritesOnceReadsBackAndRefreshesWithoutOpeningQuery() async throws {
    let server=ConnectedServer(profile:.init(visibleDatabases:[]),password:"")
    var disabled=false,writes=0,reads=0,refreshes=0
    server.catalogFixture={sql in
      if sql==TriggerDefinition.metadata(17) {reads+=1;return metadata(disabled:disabled)}
      #expect(sql.contains("IF @@TRANCOUNT<>0") && sql.contains("t.object_id=17") && sql.contains("DISABLE TRIGGER [dbo].[TR_Test] ON [dbo].[T];"))
      writes+=1;disabled=true;return Execution()
    }
    let action=TriggerStateAction()
    try await action.apply(node(server),enabled:false,confirm:{_ in false},refreshed:{refreshes+=1})
    #expect(writes==0 && refreshes==0)
    try await action.apply(node(server),enabled:false,confirm:{_ in true},refreshed:{refreshes+=1})
    #expect(writes==1 && reads==3 && refreshes==1 && !action.busy)
    try await action.apply(node(server),enabled:false,confirm:{_ in Issue.record("Already disabled should not request another write");return true},refreshed:{refreshes+=1})
    #expect(writes==1 && refreshes==2)
  }
  @Test func changedConnectionOrUncertainReadbackNeverRetriesWrite() async throws {
    let server=ConnectedServer(profile:.init(visibleDatabases:[]),password:"")
    var writes=0,reads=0
    server.asyncCatalogFixture={sql in
      if sql==TriggerDefinition.metadata(17) {reads+=1;if writes>0 {throw SQLFailure("readback denied")};return metadata(disabled:false)}
      writes+=1;return Execution()
    }
    let action=TriggerStateAction()
    await #expect(throws:CancellationError.self) {
      try await action.apply(node(server),enabled:false,confirm:{_ in server.generation=UUID();return true},refreshed:{Issue.record("Changed generation")})
    }
    #expect(writes==0)
    await #expect(throws:SQLFailure.self) {
      try await action.apply(node(server),enabled:false,confirm:{_ in true},refreshed:{Issue.record("Unverified state")})
    }
    #expect(writes==1 && reads==3 && !action.busy)
  }
  @Test func openedTriggerScriptContainsOnlyDefinitionAndSessionSettings() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:.init(visibleDatabases:[]),password:"")
    let source="CREATE TRIGGER [dbo].[TR_Test] ON [dbo].[T] AFTER INSERT AS SELECT 1;"
    server.catalogFixture={sql in
      var output=Execution()
      if sql==Catalog.definition(17) {output.results=[Rows(values:[[source]])]}
      else if sql.contains("uses_ansi_nulls") {output.results=[Rows(values:[["1","1"]])]}
      else {Issue.record("Definition opening must not request or change trigger state")}
      return output
    }
    let state=StudioState()
    let workbench=WorkbenchController(state:state)
    let loaded=try await workbench.loadManagedModule(node(server),verb:"ALTER")
    #expect(loaded.script.contains("ALTER TRIGGER") && !loaded.script.contains("ENABLE TRIGGER") && !loaded.script.contains("DISABLE TRIGGER"))
    #expect(loaded.original==source && state.documents.isEmpty)
  }
  @Test func semanticMenuColorsPreserveSymbolsAndSurviveNativeUpdate() {
    let menu=StudioMenu()
    for title in ["Enable…","Disable…","Delete…","Refresh","Properties"] {menu.addItem(NSMenuItem(title:title,action:nil,keyEquivalent:""))}
    menu.applySemanticActionColors()
    let before=menu.items.map {$0.image?.tiffRepresentation}
    #expect(menu.items.allSatisfy {$0.image != nil && $0.image?.isTemplate==false})
    menu.update()
    #expect(menu.items.map {$0.image?.tiffRepresentation}==before)
  }
}
