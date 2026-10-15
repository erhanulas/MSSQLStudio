import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct FavoriteQueryPickerTests {
  private func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
  private func fixture()->(StudioState,ConnectedServer,FavoriteQueriesModel,URL) {
    _=NSApplication.shared
    let folder=URL(fileURLWithPath:"/tmp/mssql-favorite-picker-\(UUID())")
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:ServerProfile(name:"Favorite fixture",database:"DefaultDB"),password:"");server.online=false
    let model=FavoriteQueriesModel(url:folder.appendingPathComponent("favorites.json"));state.favorites=model;state.servers=[server]
    return (state,server,model,folder)
  }
  @Test func pickerSearchKeyboardAndDoubleClickOpenOnlyApplicableSQLWithoutExecuting() async throws {
    let (state,server,model,folder)=fixture();defer {try? FileManager.default.removeItem(at:folder)}
    let values=[
      try FavoriteQuery(name:"Global report",sql:"DELETE FROM dbo.Important; -- open only",scope:.global),
      try FavoriteQuery(name:"Connection report",sql:"SELECT 2",scope:.connection,serverID:server.id),
      try FavoriteQuery(name:"Database report",sql:"SELECT 3",scope:.database,serverID:server.id,database:"Sales"),
      try FavoriteQuery(name:"Other report",sql:"SELECT 4",scope:.database,serverID:server.id,database:"Other")]
    for value in values {try await model.save(value)}
    let picker=FavoriteQueryPickerController(model:model,serverID:server.id,database:"Sales",contextLabel:"Fixture / Sales",open:{try state.openFavorite($0,contextServerID:server.id,contextDatabase:"Sales")},manage:{})
    let window=NSWindow(contentViewController:picker);window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:840,height:540));defer {window.close()}
    let search=try #require(descendants(picker.view).compactMap {$0 as? NSSearchField}.first)
    let table=try #require(descendants(picker.view).compactMap {$0 as? NSTableView}.first)
    let sidebar = try #require(descendants(picker.view).first { $0.accessibilityIdentifier() == "favoritePickerSidebar" })
    for width: CGFloat in [720, 840, 1246] {
      window.setContentSize(NSSize(width: width, height: 540))
      picker.view.layoutSubtreeIfNeeded()
      #expect(abs(sidebar.frame.width - 220) < 1)
      #expect(table.frame.width <= 220)
    }
    #expect(picker.visible.map(\.id) == [values[2].id,values[1].id,values[0].id])
    let editor=NSTextView()
    #expect(picker.control(search,textView:editor,doCommandBy:#selector(NSResponder.moveDown(_:))))
    #expect(picker.selectedFavorite?.id == values[1].id)
    #expect(picker.control(search,textView:editor,doCommandBy:#selector(NSResponder.moveUp(_:))))
    #expect(picker.selectedFavorite?.id == values[2].id)
    search.stringValue="global report";#expect(NSApp.sendAction(try #require(search.action),to:search.target,from:search))
    #expect(picker.visible.map(\.id) == [values[0].id] && picker.selectedFavorite?.id == values[0].id)
    #expect(NSApp.sendAction(try #require(table.doubleAction),to:table.target,from:table))
    let opened=try #require(state.active)
    #expect(opened.sql == values[0].sql && opened.database == "Sales" && opened.server === server && opened.favoriteID == values[0].id)
    #expect(opened.lastExecutedSQL == nil && !opened.runAfterConnect && state.documents.count == 1)
  }
  @Test func pickerReflectsLocalSaveDeleteEmptySearchAndKeyboardEnter() async throws {
    let (_,server,model,folder)=fixture();defer {try? FileManager.default.removeItem(at:folder)}
    var opened:[UUID]=[]
    let picker=FavoriteQueryPickerController(model:model,serverID:server.id,database:"Sales",contextLabel:"Fixture / Sales",open:{opened.append($0.id)},manage:{})
    let window=NSWindow(contentViewController:picker);window.isReleasedWhenClosed=false;defer {window.close()}
    let controls=descendants(picker.view),search=try #require(controls.compactMap {$0 as? NSSearchField}.first)
    let open=try #require(controls.compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier() == "favoritePickerOpen"})
    #expect(picker.visible.isEmpty && !open.isEnabled)
    let value=try FavoriteQuery(name:"Sales totals",sql:"SELECT 1",scope:.global)
    try await model.save(value);#expect(picker.visible.map(\.id) == [value.id] && open.isEnabled)
    search.stringValue="no match";picker.reloadItems();#expect(picker.visible.isEmpty && !open.isEnabled)
    #expect(picker.control(search,textView:NSTextView(),doCommandBy:#selector(NSResponder.insertNewline(_:))))
    #expect(opened.isEmpty)
    search.stringValue="totals";picker.reloadItems()
    #expect(picker.control(search,textView:NSTextView(),doCommandBy:#selector(NSResponder.insertNewline(_:))))
    #expect(opened == [value.id])
    try await model.delete(value.id);#expect(picker.visible.isEmpty && !open.isEnabled)
  }
  @Test func menuPickerUsesActiveEditorInsteadOfExplorerAndReusesTheTargetWindow() async throws {
    let (state,a,_,folder)=fixture();defer {try? FileManager.default.removeItem(at:folder)}
    let b=ConnectedServer(profile:ServerProfile(name:"Explorer selection",database:"OtherDB"),password:"");b.online=false;state.servers.append(b)
    let doc=QueryDocument(server:a,database:"EditorDB",title:"Editor target");state.documents=[doc];state.active=doc
    let host=WorkbenchController(state:state),main=NSWindow(contentViewController:host);main.isReleasedWhenClosed=false
    defer {for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("favorite-picker|") == true || window.identifier?.rawValue.hasPrefix("favorites|") == true {window.close()};main.close()}
    let outline=try #require(descendants(host.view).compactMap {$0 as? NSOutlineView}.first)
    let root=try #require((0..<outline.numberOfRows).compactMap {outline.item(atRow:$0) as? TreeNode}.first {if case .server=$0.kind {return $0.server === b};return false})
    outline.selectRowIndexes(IndexSet(integer:outline.row(forItem:root)),byExtendingSelection:false)
    host.showFavorites()
    let pickerWindow=try #require(NSApp.windows.first {$0.identifier?.rawValue == "favorite-picker|\(a.id)|EditorDB"})
    let picker=try #require(pickerWindow.contentViewController as? FavoriteQueryPickerController)
    #expect(picker.serverID == a.id && picker.database == "EditorDB" && state.active === doc)
    host.showFavorites();#expect(NSApp.windows.filter {$0.isVisible && $0.identifier == pickerWindow.identifier}.count == 1)
    #expect(NSApp.sendAction(NSSelectorFromString("manageFavorites"),to:host,from:nil))
    #expect(NSApp.windows.contains {$0.identifier?.rawValue == "favorites|\(a.id)|EditorDB" && $0.isVisible})
  }
  @Test func detachedKeyWindowUsesItsOwnFavoriteTarget() async throws {
    let (state,server,_,folder)=fixture();defer {try? FileManager.default.removeItem(at:folder)}
    let detached=QueryDocument(server:server,database:"DetachedDB",title:"Detached favorite target")
    let docked=QueryDocument(server:server,database:"DockedDB",title:"Docked favorite target")
    state.documents=[detached,docked];state.active=detached
    let host=WorkbenchController(state:state),main=NSWindow(contentViewController:host);main.isReleasedWhenClosed=false
    defer {host.redockQueries();for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("favorite-picker|") == true {window.close()};main.close()}
    host.detachQuery()
    let detachedWindow=try #require(NSApp.windows.first {$0.title == detached.title})
    // Resolve the native window directly; the test runner need not become the frontmost app.
    #expect(state.active === docked && host.favoriteContextDocument(in:detachedWindow) === detached)
    host.presentFavoritePicker(from:detachedWindow)
    let picker=try #require(NSApp.windows.first {$0.identifier?.rawValue == "favorite-picker|\(server.id)|DetachedDB"}?.contentViewController as? FavoriteQueryPickerController)
    #expect(picker.database == detached.database && picker.serverID == detached.server.id)
    let pickerWindow=try #require(picker.view.window)
    host.presentFavoritePicker(from:pickerWindow)
    #expect(NSApp.windows.filter {$0.isVisible && $0.identifier?.rawValue.hasPrefix("favorite-picker|") == true}.count == 1)
    host.presentFavoritesManagement(from:pickerWindow)
    let manager=try #require(NSApp.windows.first {$0.identifier?.rawValue == "favorites|\(server.id)|DetachedDB"})
    manager.close()
  }
  @Test func favoriteShortcutCanBeCustomizedAndRejectsOtherBindings() throws {
    _=NSApplication.shared
    let keys=GridShortcuts.Action.allCases.map {"shortcut.\($0.rawValue)"},oldMenu=NSApp.mainMenu
    let old=keys.map {UserDefaults.standard.object(forKey:$0)}
    defer {for (key,value) in zip(keys,old) {if let value {UserDefaults.standard.set(value,forKey:key)} else {UserDefaults.standard.removeObject(forKey:key)}};NSApp.mainMenu=oldMenu}
    for key in keys {UserDefaults.standard.removeObject(forKey:key)}
    #expect(GridShortcuts.binding(.favorites).label == "⇧⌘P")
    func event(_ key:String,_ flags:NSEvent.ModifierFlags)throws->NSEvent {try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:0))}
    #expect(GridShortcuts.save(try event("n",.command),action:.favorites) != nil)
    #expect(GridShortcuts.save(try event("k",[.control,.option]),action:.favorites) == nil)
    #expect(GridShortcuts.save(try event("k",[.control,.option]),action:.columns) != nil)
    let menu=NSMenu(),item=NSMenuItem(title:"Favori Sorgular…",action:#selector(WorkbenchController.showFavorites),keyEquivalent:"");menu.addItem(item);NSApp.mainMenu=menu
    WorkbenchController(state:StudioState()).refreshShortcuts()
    #expect(item.keyEquivalent == "k" && item.keyEquivalentModifierMask == [.control,.option])
  }
  @Test func closingFavoriteWindowsReleasesTheirEditorsAndModelSubscriptions() async throws {
    let (state,server,model,folder)=fixture();defer {try? FileManager.default.removeItem(at:folder)}
    let doc=QueryDocument(server:server,database:"Sales",title:"Local favorite");doc.sql="SELECT N'İstanbul';";doc.savedText=doc.sql
    state.documents=[doc];state.active=doc
    let host=WorkbenchController(state:state),main=NSWindow(contentViewController:host);main.isReleasedWhenClosed=false;defer {main.close()}
    for _ in 0..<3 {
      host.addFavorite()
      let editor=try #require(NSApp.windows.first {$0.identifier?.rawValue.hasPrefix("favorite-editor|") == true && $0.isVisible})
      weak var content=editor.contentViewController
      editor.close()
      for _ in 0..<100 where content != nil {try await Task.sleep(for:.milliseconds(5))}
      #expect(content == nil && editor.contentViewController == nil)
    }
    host.showFavorites()
    let picker=try #require(NSApp.windows.first {$0.identifier?.rawValue == "favorite-picker|\(server.id)|Sales" && $0.isVisible})
    weak var content=picker.contentViewController
    picker.close()
    for _ in 0..<100 where content != nil {try await Task.sleep(for:.milliseconds(5))}
    #expect(content == nil && picker.contentViewController == nil)
    try await model.save(FavoriteQuery(name:"Still responsive",sql:doc.sql,scope:.global))
    #expect(model.items.count == 1 && state.active === doc)
  }
  @Test func saveIsSingleFlightRemainsResponsiveAndRecoversFromDiskFailure() async throws {
    let value=try FavoriteQuery(name:"Saved SQL",sql:"SELECT N'İstanbul';",scope:.global)
    var calls=0,closed=0,fail=true,heartbeat=false
    let submission=FavoriteQuerySubmission {saved in
      calls+=1;#expect(saved == value)
      try await Task.sleep(for:.milliseconds(60))
      if fail {throw SQLFailure("Sentetik disk hatası")}
    }
    submission.save(value) {closed+=1};submission.save(value) {closed+=1}
    #expect(submission.saving && submission.error.isEmpty)
    Task {@MainActor in heartbeat=true}
    for _ in 0..<100 where submission.saving {try await Task.sleep(for:.milliseconds(5))}
    #expect(heartbeat && calls == 1 && closed == 0 && !submission.saving && submission.error.contains("Sentetik disk"))
    fail=false;submission.save(value) {closed+=1}
    for _ in 0..<100 where submission.saving {try await Task.sleep(for:.milliseconds(5))}
    #expect(calls == 2 && closed == 1 && !submission.saving && submission.error.isEmpty)
  }
  @Test func delayedSaveCannotCloseAReopenedEditorWithTheSameFavoriteIdentity() async throws {
    let (state,server,model,folder)=fixture();defer {try? FileManager.default.removeItem(at:folder)}
    let favorite=try FavoriteQuery(name:"Same saved favorite",sql:"SELECT 1;",scope:.global)
    try await model.save(favorite)
    let host=WorkbenchController(state:state),main=NSWindow(contentViewController:host);main.isReleasedWhenClosed=false;defer {main.close()}
    let oldTarget=host.presentFavoriteEditor(favorite:favorite,serverID:server.id,database:"Sales")
    let oldWindow=try #require(oldTarget.window)
    var pending:CheckedContinuation<Void,Never>?
    let submission=FavoriteQuerySubmission {value in
      await withCheckedContinuation {pending=$0}
      try await model.save(value)
    }
    submission.save(favorite,close:oldTarget.close)
    for _ in 0..<100 where pending == nil {try await Task.sleep(for:.milliseconds(5))}
    #expect(submission.saving && pending != nil)
    oldWindow.close()
    for _ in 0..<100 where oldWindow.contentViewController != nil {try await Task.sleep(for:.milliseconds(5))}
    #expect(oldWindow.contentViewController == nil)
    let newTarget=host.presentFavoriteEditor(favorite:favorite,serverID:server.id,database:"Sales")
    let newWindow=try #require(newTarget.window);defer {newWindow.close()}
    #expect(newWindow !== oldWindow && newWindow.identifier == oldWindow.identifier && newWindow.isVisible)
    let view=try #require(newWindow.contentView)
    var editor:NSTextView?
    for _ in 0..<100 where editor == nil {
      editor=descendants(view).compactMap {$0 as? NSTextView}.first {$0.accessibilityIdentifier() == "agentCommandEditor"}
      if editor == nil {try await Task.sleep(for:.milliseconds(5))}
    }
    let draft=try #require(editor)
    let sql="SELECT N'New unsaved draft';"
    draft.string=sql;draft.didChangeText()
    pending?.resume();pending=nil
    for _ in 0..<100 where submission.saving {try await Task.sleep(for:.milliseconds(5))}
    for _ in 0..<3 {await Task.yield()}
    #expect(!submission.saving && submission.error.isEmpty && newWindow.isVisible && newWindow.contentViewController != nil)
    #expect(draft.string == sql && model.items == [favorite])
  }
  @Test func largeFavoritePreviewIsBoundedWhileOpeningPreservesTheEntireSQL() async throws {
    let (_,server,model,folder)=fixture();defer {try? FileManager.default.removeItem(at:folder)}
    let sql="SELECT N'"+String(repeating:"İstanbul 👩🏽‍💻 ",count:12_000)+"'; -- final SQL"
    let value=try FavoriteQuery(name:"Large query",sql:sql,scope:.global)
    try await model.save(value)
    var opened:String?
    let picker=FavoriteQueryPickerController(model:model,serverID:server.id,database:"Sales",contextLabel:"Fixture / Sales",open:{opened=$0.sql},manage:{})
    let window=NSWindow(contentViewController:picker);window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:840,height:540));defer {window.close()}
    try await Task.sleep(for:.milliseconds(40))
    let preview=try #require(descendants(picker.view).compactMap {$0 as? SQLPreviewView}.first?.textView as? NSTextView)
    #expect(preview.string.count == 64_000 && preview.string == String(sql.prefix(64_000)))
    picker.openSelected()
    #expect(opened == sql && opened?.hasSuffix("-- final SQL") == true)
  }
  @Test func pickerHasUsableMinimumGeometryAndSQLColorsInBothThemes() async throws {
    let (_,server,model,folder)=fixture();defer {try? FileManager.default.removeItem(at:folder)}
    let oldTheme=UserDefaults.standard.string(forKey:"ssmsTheme");defer {StudioTheme.apply(oldTheme ?? "light")}
    try await model.save(FavoriteQuery(name:"Günlük satış özeti",sql:"SELECT N'İstanbul', 123.456; -- saved SQL",scope:.global))
    for theme in ["light","dark"] {
      StudioTheme.apply(theme)
      let picker=FavoriteQueryPickerController(model:model,serverID:server.id,database:"Sales",contextLabel:"Offline fixture / Sales",open:{_ in},manage:{})
      let window=NSWindow(contentViewController:picker);window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:720,height:440))
      try await Task.sleep(for:.milliseconds(80))
      picker.view.frame=NSRect(x:0,y:0,width:720,height:440);picker.view.layoutSubtreeIfNeeded()
      for control in descendants(picker.view).compactMap({$0 as? NSControl}) where !control.isHiddenOrHasHiddenAncestor && !(control is NSScroller) {
        let rect=picker.view.convert(control.bounds,from:control)
        #expect(rect.minX>=0 && rect.maxX<=721 && rect.minY>=0 && rect.maxY<=441,"\(theme): \(rect)")
      }
      let preview=try #require(descendants(picker.view).compactMap {$0 as? SQLPreviewView}.first)
      let editor=try #require(preview.textView as? NSTextView)
      #expect(editor.string.contains("N'İstanbul'") && editor.backgroundColor == StudioTheme.editorCanvas)
      if let rep=picker.view.bitmapImageRepForCachingDisplay(in:picker.view.bounds) {picker.view.cacheDisplay(in:picker.view.bounds,to:rep);try rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/mssql-favorite-picker-\(theme).png"))}
      window.close()
    }
  }
}
