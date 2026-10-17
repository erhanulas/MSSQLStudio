import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct EditorExplorerRegressionTests {
  @Test func explorerHeaderCollapseAllPersistsWithoutDisconnectingOrReloading() throws {
    _=NSApplication.shared
    let suite="collapse-explorer-"+UUID().uuidString
    let defaults=try #require(UserDefaults(suiteName:suite));defer {defaults.removePersistentDomain(forName:suite)}
    let state=StudioState();state.explorerTreeDefaults=defaults;state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:.init(name:"Fixture"),password:"")
    server.online=false;server.databases=[CatalogItem(id:5,name:"Demo")];state.servers=[server]
    try state.changeExplorerOrganization {let parent=try $0.create("Müşteriler");let child=try $0.create("Üretim",parent:parent);try $0.assign(server.id,to:child)}
    let host=WorkbenchController(state:state);_=host.view
    func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
    let button=try #require(descendants(host.view).compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier()=="collapseExplorerBranches"})
    #expect(button.image != nil)
    let root=try #require(host.roots.first),databases=try #require(root.children.first),db=try #require(databases.children.first)
    databases.loaded=true;db.loaded=true
    let parent=try #require(host.outline.item(atRow:0) as? TreeNode)
    host.outline.expandItem(parent)
    let child=try #require(parent.children.first)
    host.outline.expandItem(child)
    host.outline.expandItem(root);host.outline.expandItem(databases);host.outline.expandItem(db)
    host.expansionState["remembered-unloaded-descendant"]=true
    let parentState=host.expansionState[parent.persistenceKey],childState=host.expansionState[child.persistenceKey]
    let generation=server.generation
    #expect(host.outline.isItemExpanded(db))
    #expect(NSApp.sendAction(try #require(button.action),to:button.target,from:button))
    #expect(!host.outline.isItemExpanded(root) && !host.outline.isItemExpanded(databases) && !host.outline.isItemExpanded(db))
    #expect(host.outline.isItemExpanded(parent) && host.outline.isItemExpanded(child))
    #expect(host.expansionState[parent.persistenceKey]==parentState && host.expansionState[child.persistenceKey]==childState)
    #expect(host.expansionState.filter {!$0.key.hasPrefix("connection-group|")}.values.allSatisfy {!$0})
    #expect(defaults.dictionary(forKey:"explorerExpansionState") as? [String:Bool]==host.expansionState)
    host.reloadExplorer()
    #expect(!host.outline.isItemExpanded(root) && host.outline.isItemExpanded(parent) && host.outline.isItemExpanded(child))
    host.outline.expandItem(root)
    #expect(!host.outline.isItemExpanded(databases))
    #expect(server.generation==generation && !server.online && !server.reconnecting && state.documents.isEmpty)
  }
  @Test func literalColorsStayCorrectAfterEveryNativeEditWithoutCompletionDelay() throws {
    _=NSApplication.shared
    let previous=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(previous ?? "light")}
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
      let doc=QueryDocument(server:server,database:"master",title:"String colors");doc.sql="SELECT ''"
      let controller=EditorController(document:doc),editor=controller.editor
      let window=NSWindow(contentRect:NSRect(x:-3000,y:0,width:800,height:600),styleMask:[.titled],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=controller.surface;defer {window.close()}
      window.makeFirstResponder(editor);editor.setSelectedRange(NSRange(location:8,length:0))
      let undo=try #require(editor.undoManager);undo.groupsByEvent=false
      for text in ["S","E","L","E","C","T"," İstanbul 😀","''","Brien"] {
        undo.beginUndoGrouping();editor.insertText(text,replacementRange:editor.selectedRange());undo.endUndoGrouping()
        let storage=try #require(editor.textContentStorage?.textStorage)
        let token=try #require(TSQL.lex(editor.string).first {$0.kind == .string})
        storage.enumerateAttribute(.foregroundColor,in:token.range) {value,_,_ in
          #expect(value as? NSColor == StudioTheme.syntax(.string),"\(theme) \(editor.string)")
        }
        #expect(editor.typingAttributes[.foregroundColor] as? NSColor == StudioTheme.syntax(.string))
        #expect(editor.string == doc.sql && editor.textLayoutManager != nil)
      }
      undo.undo();undo.redo()
      let token=try #require(TSQL.lex(editor.string).first {$0.kind == .string})
      let storage=try #require(editor.textContentStorage?.textStorage)
      #expect(storage.attribute(.foregroundColor,at:token.range.location+1,effectiveRange:nil) as? NSColor == StudioTheme.syntax(.string))
      undo.groupsByEvent=true
      editor.setSelectedRange(NSRange(location:(editor.string as NSString).length,length:0))
      editor.insertText(" + COUNT(*) -- comment",replacementRange:editor.selectedRange())
      for token in TSQL.lex(editor.string) where [.keyword,.string,.comment].contains(token.kind) {
        #expect(storage.attribute(.foregroundColor,at:token.range.location,effectiveRange:nil) as? NSColor == StudioTheme.syntax(TSQL.syntaxStyle(token)))
      }
      undo.groupsByEvent=true
    }
  }
  @Test func explorerExpansionSurvivesRecreationReloadAndIndependentConnections() throws {
    _=NSApplication.shared
    let suite="explorer-expansion-\(UUID())",defaults=try #require(UserDefaults(suiteName:suite))
    defer {defaults.removePersistentDomain(forName:suite)}
    let profiles=[ServerProfile(name:"Same name"),ServerProfile(name:"Same name")]
    func make()->(StudioState,WorkbenchController,NSOutlineView) {
      let state=StudioState();state.explorerTreeDefaults=defaults
      state.servers=profiles.map {profile in
        let server=ConnectedServer(profile:profile,password:"");server.online=false;server.catalogFixture=ObjectManagementUIFixture.catalog
        server.databases=[CatalogItem(id:5,name:"DemoDB")];return server
      }
      let host=WorkbenchController(state:state)
      func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
      let outline=descendants(host.view).compactMap {$0 as? NSOutlineView}.first!
      return (state,host,outline)
    }
    func roots(_ outline:NSOutlineView)->[TreeNode] {(0..<outline.numberOfRows).compactMap {outline.item(atRow:$0) as? TreeNode}.filter {if case .server=$0.kind {return true};return false}}
    let (state,host,outline)=make(),initial=roots(outline)
    let databases=try #require(initial[0].children.first),db=try #require(databases.children.first)
    outline.expandItem(databases);outline.expandItem(db)
    let tables=try #require(db.children.first);outline.expandItem(tables)
    outline.collapseItem(db);outline.collapseItem(initial[1])
    state.changed?()
    #expect(outline.isItemExpanded(databases) && !outline.isItemExpanded(db) && !outline.isItemExpanded(initial[1]))
    let (state2,host2,restored)=make(),again=roots(restored)
    let databases2=try #require(again[0].children.first),db2=try #require(databases2.children.first)
    #expect(restored.isItemExpanded(again[0]) && restored.isItemExpanded(databases2))
    #expect(!restored.isItemExpanded(db2) && !restored.isItemExpanded(again[1]))
    restored.expandItem(db2)
    #expect(restored.isItemExpanded(db2.children[0]))
    // Rebuilt node objects retain semantic IDs; connection rename does not change the root key.
    state2.servers[0].profile.name="Renamed";state2.servers[0].databases.append(CatalogItem(id:6,name:"OtherDB"));state2.changed?()
    let rebuilt=roots(restored)[0],newDB=try #require(rebuilt.children.first?.children.first)
    #expect(restored.isItemExpanded(newDB) && restored.isItemExpanded(newDB.children[0]))
    #expect(!restored.isItemExpanded(roots(restored)[1]))
    #expect(state2.servers.allSatisfy {!$0.online && !$0.reconnecting})
    restored.collapseItem(rebuilt)
    let (_,host3,third)=make(),thirdRoot=roots(third)[0]
    #expect(!third.isItemExpanded(thirdRoot))
    third.expandItem(thirdRoot)
    let thirdDB=try #require(thirdRoot.children.first?.children.first)
    #expect(third.isItemExpanded(thirdDB) && third.isItemExpanded(thirdDB.children[0]))
    withExtendedLifetime([host,host2,host3]) {}
  }
}
