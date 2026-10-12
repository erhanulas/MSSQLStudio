import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct LoadingNavigationTests {
  @Test func definitionOpensImmediatelyDeduplicatesAndPreservesEdits() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let original="CREATE PROCEDURE dbo.Example AS BEGIN SELECT 1; END"
    server.asyncCatalogFixture={sql in
      try await Task.sleep(for:.milliseconds(80))
      var e=Execution();e.results=[Rows(values:[[sql.contains("SELECT object_id") ? "42":original]])];return e
    }
    let state=StudioState(),host=WorkbenchController(state:state)
    let source=state.newQuery(server:server,text:"EXEC dbo.Example")
    let symbol=CatalogSymbol(schema:"dbo",name:"Example",columns:[],kind:"SQL_STORED_PROCEDURE")
    host.openEditorDefinition(symbol,document:source)
    let target=try #require(state.active)
    #expect(target !== source && target.definitionLoading && target.sql.isEmpty)
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let status=try #require(descendants(host.view).compactMap {$0 as? NSTextField}.first {$0.accessibilityIdentifier() == "definitionStatus"})
    #expect(status.stringValue == "Nesne tanımı yükleniyor…" && !status.isHiddenOrHasHiddenAncestor)
    let textView=try #require(descendants(host.view).compactMap {$0 as? SQLTextView}.first)
    #expect(!textView.isEditable)
    host.openEditorDefinition(symbol,document:source)
    #expect(state.documents.count == 2 && state.active === target)
    state.active=source;state.changed?()
    for _ in 0..<100 where target.definitionLoading {try await Task.sleep(for:.milliseconds(10))}
    #expect(!target.definitionLoading && target.definitionError == nil)
    #expect(target.sql.contains("ALTER PROCEDURE") && target.moduleOriginal == original)
    #expect(!target.dirty && !target.hasPendingDatabaseChanges && state.active === source)
    target.sql += "\n-- edit"
    host.openEditorDefinition(symbol,document:source)
    #expect(state.active === target && target.sql.hasSuffix("-- edit") && state.documents.count == 2)
  }
  @Test func closedLoadingTabCannotReappearAndFailureStaysInTab() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    server.asyncCatalogFixture={_ in
      // An uncooperative request still cannot publish to a closed tab.
      try? await Task.sleep(for:.milliseconds(100))
      throw SQLFailure("Fixture permission denied")
    }
    let state=StudioState(),host=WorkbenchController(state:state)
    let source=state.newQuery(server:server)
    let symbol=CatalogSymbol(schema:"dbo",name:"Example",columns:[],kind:"SQL_STORED_PROCEDURE")
    host.openEditorDefinition(symbol,document:source)
    let target=try #require(state.active)
    #expect(state.close(target));#expect(state.documents.count == 1)
    try await Task.sleep(for:.milliseconds(150))
    #expect(state.active === source && state.documents.count == 1 && target.sql.isEmpty)
    host.openEditorDefinition(symbol,document:source)
    let failed=try #require(state.active)
    for _ in 0..<100 where failed.definitionLoading {try await Task.sleep(for:.milliseconds(10))}
    #expect(failed.definitionError == "Fixture permission denied" && !failed.definitionLoading)
    #expect(state.active === failed && failed.sql.isEmpty && !failed.dirty)
  }
  @Test func resolvedIdentityReusesExistingEditedObjectTabAndTablesLoadCreate() async throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    server.catalogFixture=ObjectManagementUIFixture.catalog
    let state=StudioState(),host=WorkbenchController(state:state)
    let source=state.newQuery(server:server)
    let existing=host.openObjectEditor(server:server,database:source.database,objectID:1001,sql:"CREATE TABLE original",title:"Existing")
    existing.sql += " -- edit"
    let symbol=CatalogSymbol(schema:"dbo",name:"Customers",columns:[],kind:"USER_TABLE")
    host.openEditorDefinition(symbol,document:source)
    for _ in 0..<100 where state.active !== existing {try await Task.sleep(for:.milliseconds(10))}
    #expect(state.active === existing && existing.sql == "CREATE TABLE original -- edit" && state.documents.count == 2)
    existing.sql=existing.savedText;#expect(state.close(existing))
    host.openEditorDefinition(symbol,document:source)
    let table=try #require(state.active)
    for _ in 0..<100 where table.definitionLoading {try await Task.sleep(for:.milliseconds(10))}
    #expect(!table.definitionLoading && table.definitionError == nil && table.sql.contains("CREATE TABLE"))
    #expect(table.moduleOriginal == nil && !table.dirty)
  }
  @Test func blockDecorationPreservesNativeTextAndColors() throws {
    _=NSApplication.shared
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=QueryDocument(server:server,database:"master",title:"Blocks");doc.sql="BEGIN SELECT 'BEGIN'; BEGIN SELECT 2; END END"
    let controller=EditorController(document:doc),editor=controller.editor
    editor.setSelectedRange(NSRange(location:2,length:0));controller.updateOccurrences()
    #expect(controller.occurrenceHighlights.blockRanges == [NSRange(location:0,length:5),NSRange(location:42,length:3)])
    #expect(editor.string == doc.sql && editor.textLayoutManager != nil)
    let storage=try #require(editor.textContentStorage?.textStorage)
    #expect(storage.attribute(.foregroundColor,at:1,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.keyword))
    editor.setSelectedRange(NSRange(location:15,length:0));controller.updateOccurrences()
    #expect(controller.occurrenceHighlights.blockRanges.isEmpty)
  }
  @Test func updateProgressRemainsBusyUntilResult() {
    _=NSApplication.shared
    let progress=UpdateProgressController()
    #expect(!progress.done.isEnabled && !progress.spinner.isHidden)
    progress.phase("İndiriliyor…")
    #expect(progress.status.stringValue == "İndiriliyor…" && !progress.done.isEnabled)
    progress.finish("Güncel")
    #expect(progress.status.stringValue == "Güncel" && progress.done.isEnabled && progress.spinner.isHidden)
    progress.close()
  }
}
