import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct FavoriteManagementSaveTests {
  private func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
  private func button(_ window:NSWindow,_ identifier:String) throws->NSButton {
    let result=views(try #require(window.contentView)).compactMap {$0 as? NSButton}.first {$0.accessibilityIdentifier() == identifier}
    return try #require(result)
  }
  private func press(_ button:NSButton,in window:NSWindow) throws {
    let location=button.convert(NSPoint(x:button.bounds.midX,y:button.bounds.midY),to:nil)
    let hit=try #require(window.contentView?.hitTest(location))
    #expect(hit === button || hit.isDescendant(of:button),"The action must receive mouse input without an editor overlay.")
    // Keep hit-testing and target/action here; actual pointer clicks use the isolated app.
    #expect(NSApp.sendAction(try #require(button.action),to:button.target,from:button))
  }
  private func fill(_ window:NSWindow,name:String,sql:String) async throws {
    let fields=views(try #require(window.contentView)).compactMap {$0 as? NSTextField}
    let field=try #require(fields.first {$0.placeholderString == "Örneğin günlük satış özeti"})
    #expect(window.makeFirstResponder(field))
    let input=try #require(window.firstResponder as? NSTextView)
    input.insertText(name,replacementRange:NSRange(location:0,length:(input.string as NSString).length))
    let editor=try #require(views(window.contentView!).compactMap {$0 as? NSTextView}.first {$0.accessibilityIdentifier() == "agentCommandEditor"})
    editor.insertText(sql,replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
    try await Task.sleep(for:.milliseconds(40))
  }
  private func fixture(url:URL)->(StudioState,FavoriteQueriesModel,WorkbenchController,NSWindow,NSWindow) {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let model=FavoriteQueriesModel(url:url);state.favorites=model
    let server=ConnectedServer(profile:ServerProfile(name:"Anonymous fixture"),password:"");server.online=false;state.servers=[server]
    let host=WorkbenchController(state:state),main=NSWindow(contentViewController:host);main.isReleasedWhenClosed=false
    let panel=FavoriteQueriesPanel(state:state,model:model,contextServerID:nil,contextDatabase:"",editFavorite:{[weak host] favorite,id,database in
      host?.presentFavoriteEditor(favorite:favorite,serverID:id,database:database)
    })
    let manager=host.present(panel,title:"Anonymous favorite manager",width:1100,height:760)
    StudioTheme.decorate(manager.contentView!)
    return (state,model,host,main,manager)
  }
  private func editorWindow()->NSWindow? {
    NSApp.windows.first {$0.isVisible && $0.identifier?.rawValue.hasPrefix("favorite-editor|") == true}
  }
  @Test func managerNewAndEditSaveDoNotLeaveAnyModalBlocker() async throws {
    let folder=URL(fileURLWithPath:"/tmp/mssql-favorite-manager-\(UUID())");defer {try? FileManager.default.removeItem(at:folder)}
    let (state,model,_,main,manager)=fixture(url:folder.appendingPathComponent("favorites.json"))
    defer {editorWindow()?.close();manager.close();main.close()}
    try await Task.sleep(for:.milliseconds(100))
    var ticks=0
    let heartbeat=Task {@MainActor in while !Task.isCancelled {ticks+=1;try? await Task.sleep(for:.milliseconds(5))}}
    defer {heartbeat.cancel()}
    let sql="DECLARE @sample int = 1; SELECT CASE WHEN @sample > 0 THEN N'Anonymous' ELSE N'' END;"
    for index in 0..<3 {
      try press(button(manager,"favoriteNew"),in:manager)
      for _ in 0..<100 where editorWindow() == nil {try await Task.sleep(for:.milliseconds(5))}
      let editor=try #require(editorWindow())
      #expect(manager.attachedSheet == nil && main.attachedSheet == nil && NSApp.modalWindow == nil)
      try await fill(editor,name:"Anonymous monitoring \(index)",sql:sql)
      try press(button(editor,"favoriteSave"),in:editor)
      for _ in 0..<200 where model.items.count != index+1 || editor.isVisible {try await Task.sleep(for:.milliseconds(5))}
      #expect(model.items.count == index+1 && !editor.isVisible && manager.attachedSheet == nil && NSApp.modalWindow == nil)
      StudioTheme.decorate(manager.contentView!)
    }
    let list=try #require(views(manager.contentView!).compactMap {$0 as? NSTableView}.first)
    list.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
    let edit=try button(manager,"favoriteEdit")
    for _ in 0..<100 where !edit.isEnabled {try await Task.sleep(for:.milliseconds(5))}
    #expect(edit.isEnabled);try press(edit,in:manager)
    for _ in 0..<100 where editorWindow() == nil {try await Task.sleep(for:.milliseconds(5))}
    let editor=try #require(editorWindow())
    try await fill(editor,name:"Anonymous edited",sql:"SELECT N'Edited locally';")
    try press(button(editor,"favoriteSave"),in:editor)
    for _ in 0..<200 where editor.isVisible {try await Task.sleep(for:.milliseconds(5))}
    #expect(!editor.isVisible && model.items.count == 3 && model.items.contains {$0.name == "Anonymous edited"})
    #expect(ticks>3 && manager.attachedSheet == nil && main.attachedSheet == nil && NSApp.modalWindow == nil && state.documents.isEmpty)
  }
  @Test func failedManagerSaveKeepsItsWindowAndNativeActionsUsable() async throws {
    let folder=URL(fileURLWithPath:"/tmp/mssql-favorite-manager-error-\(UUID())");defer {try? FileManager.default.removeItem(at:folder)}
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let url=folder.appendingPathComponent("favorites.json"),invalid=Data("invalid anonymous fixture".utf8);try invalid.write(to:url)
    let (_,model,_,main,manager)=fixture(url:url)
    defer {editorWindow()?.close();manager.close();main.close()}
    try await Task.sleep(for:.milliseconds(100))
    try press(button(manager,"favoriteNew"),in:manager)
    for _ in 0..<100 where editorWindow() == nil {try await Task.sleep(for:.milliseconds(5))}
    let editor=try #require(editorWindow())
    try await fill(editor,name:"Cannot overwrite malformed data",sql:"SELECT 1;")
    let save=try button(editor,"favoriteSave")
    try press(save,in:editor)
    try await Task.sleep(for:.milliseconds(100))
    #expect(editor.isVisible && save.isEnabled && model.items.isEmpty && manager.attachedSheet == nil && NSApp.modalWindow == nil)
    #expect(try Data(contentsOf:url) == invalid)
    try press(save,in:editor)
    try await Task.sleep(for:.milliseconds(40))
    #expect(editor.isVisible && save.isEnabled && NSApp.modalWindow == nil)
  }
  @Test func themePreservesGridlessTableSeparatorOwnership() {
    let gridless=NSTableView(),grid=NSTableView()
    let untouched=gridless.gridColor
    grid.gridStyleMask=[.solidHorizontalGridLineMask,.solidVerticalGridLineMask]
    StudioTheme.decorate(gridless);StudioTheme.decorate(grid)
    #expect(gridless.gridStyleMask.isEmpty && gridless.gridColor == untouched)
    #expect(grid.gridColor == StudioTheme.border)
  }
}
