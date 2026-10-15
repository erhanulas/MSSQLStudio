import AppKit
import SwiftUI
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct Workspace128Tests {
  private func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(views)}
  @Test func shortcutCategoriesCoverEveryCommandAndSearchAcrossCategoriesWithAssignmentFilter() {
    let groups=ShortcutCatalog.Category.allCases.map {ShortcutCatalog.actions(category:$0)}
    #expect(groups.allSatisfy {!$0.isEmpty})
    #expect(Set(groups.flatMap {$0})==Set(GridShortcuts.Action.allCases))
    #expect(groups.flatMap {$0}.count==GridShortcuts.Action.allCases.count)
    #expect(ShortcutCatalog.actions(category:.workspace,query:"YORUM").contains(.comment))
    #expect(ShortcutCatalog.actions(category:.workspace,query:"eslesen ayirici").contains(.matchingPair))
    #expect(ShortcutCatalog.actions(category:.editor,query:"veritabanı nesneleri").contains(.contextNewManagedTable))
    #expect(ShortcutCatalog.actions(category:.editor,query:"olmayan arama 555").isEmpty)
    let old=UserDefaults.standard.object(forKey:"shortcut.format")
    defer {if let old {UserDefaults.standard.set(old,forKey:"shortcut.format")} else {UserDefaults.standard.removeObject(forKey:"shortcut.format")}}
    GridShortcuts.reset(.format)
    #expect(ShortcutCatalog.actions(category:.editor,assignment:.assigned).contains(.format))
    GridShortcuts.clear(.format)
    #expect(!ShortcutCatalog.actions(category:.editor,assignment:.assigned).contains(.format))
    #expect(ShortcutCatalog.actions(category:.editor,assignment:.unassigned).contains(.format))
    #expect(ShortcutCatalog.target("shortcut.format") == .format)
    #expect(ShortcutCatalog.target("format")==nil && ShortcutCatalog.target("shortcut.missing")==nil)
  }
  @Test func nativeShortcutSearchAndTargetRevealHiddenCategoryWithoutSavingPreferences() async throws {
    _=NSApplication.shared
    let host=NSHostingController(rootView:ShortcutSettings(target:nil,report:{_ in}));host.sizingOptions=[]
    let window=NSWindow(contentViewController:host);window.isReleasedWhenClosed=false;window.setContentSize(NSSize(width:960,height:720));host.view.frame=NSRect(x:0,y:0,width:960,height:720)
    defer {window.contentView=nil;window.close()}
    func settle() async throws {try await Task.sleep(for:.milliseconds(100));host.view.layoutSubtreeIfNeeded()}
    func field(_ placeholder:String) throws -> NSTextField {try #require(views(host.view).compactMap {$0 as? NSTextField}.first {$0.placeholderString==placeholder})}
    func type(_ text:String,in field:NSTextField) {field.stringValue=text;field.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:field))}
    func capture(_ action:GridShortcuts.Action)->NSButton? {views(host.view).compactMap {$0 as? NSButton}.first {$0.accessibilityLabel()==GridShortcuts.title(action)+" kısayolunu değiştir"}}
    try await settle()
    #expect(capture(.pinTab) != nil && capture(.comment)==nil)
    let query=try field("Tüm kısayollarda ara…");type("yorum",in:query);try await settle()
    #expect(capture(.comment) != nil && capture(.pinTab)==nil)
    type("missing xyz",in:query);try await settle();#expect(capture(.comment)==nil)
    let target=try #require(SettingsSearch.results("Editör Yorum yap").first {$0.id=="shortcut.comment"})
    host.rootView=ShortcutSettings(target:target.id,report:{_ in});try await settle()
    #expect(try field("Tüm kısayollarda ara…").stringValue.isEmpty)
    let button=try #require(capture(.comment));#expect(capture(.pinTab)==nil)
    #expect(!button.visibleRect.isEmpty)
    #expect(button.title.contains(GridShortcuts.binding(.comment).label))
  }
  @Test func menuPresentationIsSparseAndPreservesDisabledItemsSubmenusAndExplicitImages() {
    _=NSApplication.shared
    let menu=StudioMenu();menu.autoenablesItems=false
    let primary=menu.addItem(withTitle:"Yeni Sorgu",action:#selector(WorkbenchController.newQueryAtNode),keyEquivalent:"")
    let secondary=menu.addItem(withTitle:"Bağlantı ayarları…",action:#selector(WorkbenchController.editConnection),keyEquivalent:"");secondary.isEnabled=false
    menu.addItem(.separator())
    let child=StudioMenu();child.addItem(withTitle:"Seçenek",action:nil,keyEquivalent:"")
    let folder=NSMenuItem(title:"Klasöre Taşı",action:nil,keyEquivalent:"");folder.submenu=child;folder.image=NSImage(systemSymbolName:"folder",accessibilityDescription:nil);menu.addItem(folder)
    menu.update();menu.update()
    #expect(menu.font?.pointSize==14 && menu.minimumWidth>=280)
    #expect(primary.image != nil && primary.preferredImageVisibility == .visible && primary.keyEquivalent==GridShortcuts.binding(.newQuery).key)
    #expect(secondary.image != nil && !secondary.isEnabled && secondary.view==nil)
    #expect(folder.image?.size==NSSize(width:16,height:16) && folder.submenu === child && menu.items[2].isSeparatorItem)
  }
  @Test func regroupedExplorerMenuKeepsEveryRootActionAndBusyValidation() throws {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    state.explorerTreeDefaults=UserDefaults(suiteName:"menu128-"+UUID().uuidString)!
    let server=ConnectedServer(profile:ServerProfile(name:"Fixture"),password:"");server.online=false;state.servers=[server]
    let host=WorkbenchController(state:state);_=host.view
    let node=TreeNode("Fixture",kind:.server,server:server)
    for online in [false,true] {
      server.online=online
      let menu=StudioMenu();host.populateExplorerMenu(menu,for:node)
      let selectors=menu.items.compactMap {$0.action.map(NSStringFromSelector)}
      for action in ["newQueryAtNode","showFavoritesAtNode","editConnection","disconnectServer","deleteExplorerConnection","copyNodeName"] {#expect(selectors.filter {$0==action}.count==1)}
      #expect(selectors.contains(online ? "closeExplorerConnection:":"reconnectServer"))
      #expect(menu.items.first?.action == #selector(WorkbenchController.newQueryAtNode))
      #expect(menu.items.filter(\.isSeparatorItem).count>=4)
      if online {#expect(menu.items.first {$0.action == #selector(WorkbenchController.closeExplorerConnection(_:))}?.representedObject as? ConnectedServer === server)}
    }
    server.updatingProfile=true
    let busy=StudioMenu();host.populateExplorerMenu(busy,for:node)
    #expect(busy.items.first {$0.action == #selector(WorkbenchController.newQueryAtNode)}?.isEnabled==false)
    #expect(busy.items.last?.action == #selector(WorkbenchController.copyNodeName) && busy.items.last?.isEnabled==false)
  }

}
