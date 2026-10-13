import AppKit
import SQLServerKit
import Testing
@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ExplorerContextMenuTests {
  private func menu(_ host:WorkbenchController,_ node:TreeNode?) -> NSMenu {
    let menu=StudioMenu();host.populateExplorerMenu(menu,for:node);return menu
  }
  private func descendants(_ menu:NSMenu)->[NSMenuItem] {
    menu.items.flatMap {item in [item]+(item.submenu.map(descendants) ?? [])}
  }
  private func fixture()->(StudioState,ConnectedServer,WorkbenchController) {
    _=NSApplication.shared
    let state=StudioState();state.historyEnabled=false;state.recoveryEnabled=false
    let server=ConnectedServer(profile:ServerProfile(name:"Menu Fixture"),password:"")
    server.catalogFixture=ObjectManagementUIFixture.catalog
    return (state,server,WorkbenchController(state:state))
  }
  @Test func explorerMenusHaveNoDuplicateCommandsAcrossAllNodeKinds() {
    let (_,server,host)=fixture()
    var nodes=[TreeNode("Server",kind:.server,server:server),TreeNode("DB",kind:.database,server:server),TreeNode("SQL Server Agent",kind:.group,server:server),TreeNode("Details",kind:.detail,server:server)]
    for folder in Folder.allCases {
      nodes.append(TreeNode(folder.rawValue,kind:.folder(folder),server:server))
      nodes.append(TreeNode("Object",kind:.object(folder),server:server,item:.init(id:1003,name:"Object",schema:"dbo")))
    }
    for node in nodes {
      let result=menu(host,node),commands=result.items.filter {!$0.isSeparatorItem}
      #expect(Set(commands.map(\.title)).count == commands.count)
      let actions=descendants(result).compactMap {item->String? in
        guard item.submenu == nil,let action=item.action else {return nil}
        let payload=(item.representedObject as? [String])?.joined(separator:"|") ?? item.identifier?.rawValue ?? ""
        return NSStringFromSelector(action)+"|"+payload
      }
      #expect(Set(actions).count == actions.count)
    }
    #expect(menu(host,nil).items.map(\.title)==["Yeni Klasör…","Yeni Bağlantı…"])
    let jobs=menu(host,TreeNode("Jobs",kind:.folder(.jobs),server:server))
    #expect(jobs.items.filter {$0.title=="New SQL Agent Job…"}.count==1)
  }
  @Test func moduleAlterHasOneEditorEntryAndRetainsClipboardAndFileDestinations() throws {
    let (_,server,host)=fixture()
    for folder in [Folder.views,.procedures,.functions,.triggers] {
      let result=menu(host,TreeNode("Module",kind:.object(folder),server:server,item:.init(id:1003,name:"Module",schema:"dbo")))
      #expect(result.items.filter {$0.title=="Modify · ALTER…"}.count==1)
      let alter=try #require(descendants(result).first {$0.title=="ALTER To"}?.submenu)
      #expect(alter.items.map(\.title)==["Clipboard","File…"])
      #expect(alter.items.allSatisfy {($0.representedObject as? [String])?.first=="ALTER"})
    }
  }
  @Test func monitoringAndDetailMenusExposeOnlyApplicableActions() {
    let (_,server,host)=fixture()
    for folder in [Folder.activity,.sessions,.locks,.files,.jobHistory] {
      let result=menu(host,TreeNode(folder.rawValue,kind:.folder(folder),server:server))
      #expect(!result.items.contains {$0.title=="Nesneleri Yenile"})
      if folder == .jobHistory {
        #expect(result.items.contains {$0.title=="View History…"})
        #expect(!result.items.contains {$0.title=="Verileri Aç"})
      }
      if folder == .files {#expect(result.items.contains {$0.title=="Veritabanı Dosyaları…"})}
    }
    let detail=TreeNode("Detail",kind:.detail,server:server)
    #expect(menu(host,detail).items.map(\.title)==["Adı Kopyala"])
    let parent=TreeNode("Tables",kind:.folder(.tables),server:server);parent.error="Fixture error";parent.children=[detail]
    #expect(menu(host,detail).items.map(\.title)==["Yüklemeyi Tekrar Dene","Adı Kopyala"])
    for folder in [Folder.users,.logins,.roles] {
      let result=menu(host,TreeNode("Principal",kind:.object(folder),server:server,item:.init(id:5,name:"Principal")))
      #expect(result.items.contains {$0.title=="Properties…" && $0.action==NSSelectorFromString("objectProperties")})
    }
  }
  @Test func connectionCommandsExplainDistinctEffectsAndRemainDisabledWhileBusy() throws {
    let (_,server,host)=fixture(),node=TreeNode("Server",kind:.server,server:server)
    for online in [true,false] {
      server.online=online
      let result=menu(host,node)
      let remove=try #require(result.items.first {$0.title=="Explorer’dan Kaldır…"})
      let delete=try #require(result.items.first {$0.title=="Kayıtlı Bağlantıyı Sil…"})
      #expect(remove.action != delete.action && remove.toolTip != delete.toolTip)
      #expect(remove.isEnabled && delete.isEnabled)
      #expect(result.items.contains {$0.title==(online ? "Aktif Bağlantıyı Kapat":"Yeniden Bağlan")})
      let move=try #require(result.items.first {$0.title=="Klasöre Taşı"}?.submenu)
      #expect(move.items.first?.state == .on && move.items.first?.isEnabled == false)
      server.reconnecting=true
      let busy=menu(host,node);busy.update()
      #expect(!busy.autoenablesItems)
      #expect(busy.items.filter {$0.submenu == nil && $0.action != nil}.allSatisfy {!$0.isEnabled})
      #expect(!busy.items.contains {$0.title=="Nesneleri Yenile"})
      server.reconnecting=false
    }
  }
  @Test func groupRefreshActuallyReloadsLoadedBranchesAndLeavesLazyBranchesUntouched() async throws {
    let (state,server,host)=fixture()
    var requests:[String]=[]
    server.catalogFixture={sql in requests.append(sql);return Execution()}
    let group=TreeNode("Programmability",kind:.group,server:server)
    let loaded=TreeNode("Procedures",kind:.folder(.procedures),server:server);loaded.loaded=true
    let lazy=TreeNode("Functions",kind:.folder(.functions),server:server)
    let nested=TreeNode("Nested",kind:.group,server:server);nested.children=[loaded,lazy];group.children=[nested]
    let result=menu(host,group),refresh=try #require(result.items.first {$0.title=="Nesneleri Yenile"})
    #expect(requests.isEmpty)
    #expect(NSApp.sendAction(try #require(refresh.action),to:refresh.target,from:refresh))
    for _ in 0..<200 where loaded.loading {await Task.yield()}
    #expect(requests==[Catalog.objects(.procedures)])
    #expect(loaded.loaded && !lazy.loaded && state.documents.isEmpty)
  }
  @Test func viewColumnModifyOpensOwningViewAlterEditor() async throws {
    let (state,server,host)=fixture()
    let view=TreeNode("View",kind:.object(.views),server:server,database:"DemoDB",item:.init(id:1002,name:"ActiveCustomers",schema:"dbo"))
    let folder=TreeNode("Columns",kind:.folder(.columns),server:server,database:"DemoDB")
    let column=TreeNode("Id",kind:.object(.columns),server:server,database:"DemoDB",item:.init(id:1,name:"Id"))
    view.children=[folder];folder.children=[column]
    let result=menu(host,column),modify=try #require(result.items.first {$0.title=="Modify · ALTER…"})
    #expect(NSApp.sendAction(try #require(modify.action),to:modify.target,from:modify))
    for _ in 0..<200 where state.documents.isEmpty {await Task.yield()}
    let document=try #require(state.documents.first)
    #expect(document.server === server && document.database=="DemoDB")
    #expect(document.sql.contains("ALTER VIEW [dbo].[ActiveCustomers]"))
    #expect(document.moduleOriginal?.hasPrefix("CREATE VIEW")==true)
    #expect(document.lastExecutedSQL == nil)
  }
}
