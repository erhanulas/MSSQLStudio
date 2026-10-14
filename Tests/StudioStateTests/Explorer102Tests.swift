import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct Explorer102Tests {
  private func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
  private func state()->StudioState {
    let value=StudioState();value.historyEnabled=false;value.recoveryEnabled=false
    value.explorerTreeDefaults=UserDefaults(suiteName:"Studio102-\(UUID())")!
    return value
  }
  @Test func realFolderMenuCreatesNamedFolderAndInvalidDuplicateKeepsInputVisible() async throws {
    _=NSApplication.shared
    let state=state(),server=ConnectedServer(profile:ServerProfile(name:"Offline"),password:"");server.online=false;state.servers=[server]
    let host=WorkbenchController(state:state),main=NSWindow(contentViewController:host);main.isReleasedWhenClosed=false;defer {main.close()}
    let menu=NSMenuItem(title:"Create folder",action:NSSelectorFromString("createExplorerGroup:"),keyEquivalent:"");menu.target=host
    #expect(NSApp.sendAction(try #require(menu.action),to:host,from:menu))
    for _ in 0..<100 where !NSApp.windows.contains(where:{$0.title=="Yeni bağlantı klasörü" && $0.isVisible}) {await Task.yield()}
    let owner=try #require(NSApp.windows.first {$0.title=="Yeni bağlantı klasörü" && $0.isVisible}?.windowController as? StudioNameWindowController)
    defer {owner.window?.close()}
    #expect(NSApp.modalWindow==nil)
    #expect(owner.window?.makeFirstResponder(owner.nameField)==true)
    let editor=try #require(owner.nameField.currentEditor() as? NSTextView);editor.insertText("Geliştirme",replacementRange:NSRange(location:0,length:0))
    (owner.window as? StudioPanelWindow)?.advanceDialogFocus()
    owner.saveButton.performClick(nil)
    for _ in 0..<200 where owner.saving {try await Task.sleep(for:.milliseconds(5))}
    #expect(state.explorerOrganization.groups.map(\.name)==["Geliştirme"] && owner.window?.isVisible != true)
    let duplicate=host.presentExplorerName(title:"Duplicate",value:"") {name in try state.changeExplorerOrganization {try $0.create(name)}}
    duplicate.window?.makeFirstResponder(duplicate.nameField)
    let duplicateEditor=try #require(duplicate.nameField.currentEditor() as? NSTextView)
    duplicateEditor.insertText("Geliştirme",replacementRange:NSRange(location:0,length:0))
    (duplicate.window as? StudioPanelWindow)?.advanceDialogFocus()
    duplicate.saveName()
    for _ in 0..<200 where duplicate.saving {try await Task.sleep(for:.milliseconds(5))}
    #expect(duplicate.window?.isVisible==true && !duplicate.errorLabel.stringValue.isEmpty && duplicate.saveButton.isEnabled && duplicate.nameField.stringValue=="Geliştirme")
    duplicate.window?.cancelOperation(nil)
    #expect(duplicate.window?.isVisible != true && state.explorerOrganization.groups.count==1)
    await Task.yield()
  }
  @Test func nameDialogCyclesFocusAndRejectsEscapeDuringSaveThenReleases() async throws {
    _=NSApplication.shared
    var entered:String?
    let owner=StudioNameWindowController(title:"Name",value:"Before") {name in entered=name}
    owner.window?.setFrameOrigin(NSPoint(x:-20_000,y:-20_000));owner.showWindow(nil);defer {owner.window?.close()}
    let window=try #require(owner.window)
    #expect(window.makeFirstResponder(owner.nameField))
    (window as? StudioPanelWindow)?.advanceDialogFocus();#expect(window.firstResponder === owner.saveButton)
    (window as? StudioPanelWindow)?.advanceDialogFocus();#expect(window.firstResponder === owner.cancelButton)
    #expect(owner.cancelButton.keyEquivalent=="\u{1b}" && owner.saveButton.keyEquivalent=="\r")
    owner.nameField.stringValue="After";window.makeFirstResponder(owner.nameField);owner.saveName()
    #expect(!owner.windowShouldClose(window))
    #expect(owner.saving && window.isVisible)
    for _ in 0..<200 where owner.saving {await Task.yield()}
    #expect(!window.isVisible && entered=="After")
  }
  @Test func failedReconnectKeepsTwoExplorerIdentitiesSelectionAndExpansionUsable() async throws {
    _=NSApplication.shared
    let state=state(),a=ConnectedServer(profile:ServerProfile(name:"A"),password:""),b=ConnectedServer(profile:ServerProfile(name:"B"),password:"")
    a.online=false;b.online=false;a.databases=[.init(id:5,name:"A_DB")];b.databases=[.init(id:6,name:"B_DB")];state.servers=[a,b]
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;defer {window.close()}
    let outline=try #require(views(host.view).compactMap {$0 as? NSOutlineView}.first)
    let roots=(0..<outline.numberOfRows).compactMap {outline.item(atRow:$0) as? TreeNode}.filter {if case .server=$0.kind {return true};return false}
    #expect(roots.count==2)
    let first=roots[0],second=roots[1],dbFolder=first.children[0]
    outline.expandItem(first);outline.expandItem(dbFolder);outline.expandItem(second)
    outline.selectRowIndexes(IndexSet(integer:outline.row(forItem:second)),byExtendingSelection:false)
    a.reconnectFixture={throw SQLFailure("Anonymous offline fixture")}
    await state.reconnectExplorer(a)
    #expect(a.startupError == "Anonymous offline fixture")
    #expect(!a.reconnecting && !a.online && !b.online && state.servers.count==2)
    #expect(outline.row(forItem:first)>=0 && outline.row(forItem:second)>=0 && outline.isItemExpanded(first) && outline.isItemExpanded(dbFolder) && outline.isItemExpanded(second))
    #expect(outline.item(atRow:outline.selectedRow) as? TreeNode === second && outline.isEnabled && NSApp.modalWindow==nil)
    outline.selectRowIndexes(IndexSet(integer:outline.row(forItem:first)),byExtendingSelection:false)
    #expect(outline.selectedRow==outline.row(forItem:first))
  }
  @Test func appearanceUsesInheritedQueryAccentAndTooltipOnlyCustomLabel() throws {
    _=NSApplication.shared
    let state=state(),server=ConnectedServer(profile:ServerProfile(name:"Reports",appearance:.init(customLabel:"Özel Sunucum",colorHex:"238B65")),password:"");server.online=false;state.servers=[server]
    let host=WorkbenchController(state:state),window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;defer {window.close()}
    let outline=try #require(views(host.view).compactMap {$0 as? NSOutlineView}.first),root=try #require(outline.item(atRow:0) as? TreeNode)
    #expect(!root.displayTitle.contains("Özel") && server.profile.appearance?.badge=="Özel Sunucum")
    let cell=try #require(outline.view(atColumn:0,row:0,makeIfNecessary:true))
    #expect(cell.toolTip?.contains("Özel Sunucum")==true)
    server.profile.appearance=nil
    try state.changeExplorerOrganization {let id=try $0.create("Group");try $0.setColor(id,hex:"238B65");try $0.assign(server.id,to:id)}
    let doc=state.newQuery(server:server,text:"SELECT 1",title:"Inherited")
    #expect(state.active === doc)
    let tab=try #require(views(host.view).compactMap {$0 as? QueryTabSurface}.first)
    #expect(tab.sourceColor==host.sourceColor(for:server) && tab.sourceColor != nil)
    if !StudioTheme.dark {let color=try #require(StudioTheme.explorerCanvas.usingColorSpace(.sRGB));#expect(color.redComponent==1 && color.greenComponent==1 && color.blueComponent==1)}
  }
  @Test func bulkQuitChoiceCancelsOrDiscardsAllWithoutPerTabQuestionsAndSaveWritesFiles() throws {
    let state=state(),server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false;state.servers=[server]
    let first=state.newQuery(server:server,text:"SELECT 1",title:"First"),second=state.newQuery(server:server,text:"SELECT 2",title:"Second")
    first.sql+=" -- changed";second.sql+=" -- changed"
    var questions=0;first.confirmDiscardResultEdits={questions+=1;return false};second.confirmDiscardResultEdits=first.confirmDiscardResultEdits
    state.bulkCloseChoiceFixture={.cancel};#expect(!state.canQuit() && state.documents.count==2)
    state.bulkCloseChoiceFixture={.discard};#expect(state.canQuit() && state.documents.isEmpty && questions==0)
    let folder=URL(fileURLWithPath:"/tmp/Studio102-save-\(UUID())");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:folder)}
    let saved=state.newQuery(server:server,text:"SELECT 3",title:"Save");saved.file=folder.appendingPathComponent("Save.sql");saved.sql+=" -- keep"
    #expect(state.canQuit(choice:.save))
    let text=try String(contentsOf:try #require(saved.file),encoding:.utf8);#expect(text==saved.sql && !saved.needsCloseConfirmation)
  }
  @Test func bulkCloseProtectsRunningSQLTransactionsAndInFlightGridWrites() {
    let state=state(),server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    let doc=state.newQuery(server:server,text:"SELECT 1");var errors=0;state.closeErrorFixture={_ in errors+=1}
    doc.state = .running;#expect(!state.canQuit(choice:.discard))
    doc.state = .ready;doc.transactionCount=1;#expect(!state.canQuit(choice:.discard))
    doc.transactionCount=0;doc.closeOperationBlocked={true};#expect(!state.canQuit(choice:.discard))
    #expect(errors==3 && state.documents.first === doc)
  }
  @Test func contextualMenusKeepNativeActionsAndLegacyAuxiliaryWindowsSupportEscape() throws {
    _=NSApplication.shared
    let menu=StudioMenu();let item=menu.addItem(withTitle:"Klasöre Taşı",action:nil,keyEquivalent:"")
    #expect(item.image != nil && menu.minimumWidth>=220 && menu.font?.pointSize==13)
    let state=state(),host=WorkbenchController(state:state);_=host.view
    let window=host.present(Text("Legacy form"),title:"Old auxiliary",width:480,height:240,minWidth:400,minHeight:200)
    #expect(window is StudioPanelWindow && window.isVisible)
    window.cancelOperation(nil);#expect(!window.isVisible)
  }
}
