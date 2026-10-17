import AppKit
import SQLServerKit

/// Stable Explorer node identities and local folder/favorite organization.
/// Native outline selection and scrolling belong to the presentation layer.
@MainActor final class ExplorerTreeModel {
  var roots: [TreeNode] = []
  var organization = ExplorerOrganization()
  private var groupNodes: [UUID:TreeNode] = [:]
  private(set) var displayRoots: [TreeNode] = []
  var expansionState: [String:Bool] = [:]

  func collapseAllBranches() {
    for key in expansionState.keys where !key.hasPrefix("connection-group|") {expansionState[key]=false}
    func collapse(_ node:TreeNode) {
      if node.expandable,node.connectionGroupID==nil {expansionState[node.persistenceKey]=false}
      for child in node.children {collapse(child)}
    }
    for root in displayRoots {collapse(root)}
  }

  @discardableResult func synchronizeServers(_ servers:[ConnectedServer]) -> Bool {
    let removed = roots.filter {root in !servers.contains(where:{$0 === root.server})}
    roots.removeAll {root in removed.contains(where:{$0 === root})}
    for server in servers {
      if let index = roots.firstIndex(where:{$0.server === server}) {
        roots[index].error = server.startupError
        if roots[index].generation != server.generation || roots[index].databaseIdentity != server.databases.map({"\($0.id)|\($0.name)"}) {
          roots[index] = serverTree(server)
        }
      } else { roots.append(serverTree(server)) }
    }
    roots=servers.compactMap {server in roots.first {$0.server === server}}
    return !removed.isEmpty
  }
  func databaseNode(server:ConnectedServer,database:String)->TreeNode? {
    guard let root=roots.first(where:{$0.server === server}),
      let folder=root.children.first(where:{if case .folder(.databases)=$0.kind {return true};return false}) else {return nil}
    let candidates=folder.children+folder.children.flatMap {node->[TreeNode] in if case .group=node.kind {return node.children};return []}
    return candidates.first {if case .database=$0.kind {return $0.database==database};return false}
  }
  func serverTree(_ server: ConnectedServer) -> TreeNode {
    func folder(_ value: Folder, database: String = "master", item: CatalogItem? = nil) -> TreeNode
    {
      TreeNode(value.rawValue, kind: .folder(value), server: server, database: database, item: item)
    }
    let root = TreeNode(
      server.profile.name + " (" + server.profile.host + ")", kind: .server, server: server)
    root.loaded = true
    root.databaseIdentity=server.databases.map {"\($0.id)|\($0.name)"}
    root.error = server.startupError
    let databases = folder(.databases)
    databases.loaded = true
    let system = TreeNode("System Databases", kind: .group, server: server)
    system.loaded = true
    for db in server.databases {
      let node = databaseTree(db, server: server)
      if db.id <= 4 { system.children.append(node) } else { databases.children.append(node) }
    }
    if !system.children.isEmpty { databases.children.insert(system, at: 0) }
    let security = TreeNode("Security", kind: .group, server: server)
    security.loaded = true
    security.children = [folder(.logins), folder(.roles)]
    let objects = TreeNode("Server Objects", kind: .group, server: server)
    objects.loaded = true
    objects.children = [folder(.linkedServers)]
    let management = TreeNode("Management", kind: .group, server: server)
    management.loaded = true
    management.children = [.activity, .sessions, .locks, .files].map { folder($0) }
    let agent = TreeNode("SQL Server Agent", kind: .group, server: server)
    agent.loaded = true
    agent.children = [.jobs, .jobHistory, .schedules].map { folder($0) }
    root.children = [databases, security, objects, management, agent]
    return root
  }
  private func databaseTree(_ db: CatalogItem, server: ConnectedServer) -> TreeNode {
    let node = TreeNode(db.name, kind: .database, server: server, database: db.name, item: db)
    node.loaded = true
    func folder(_ f: Folder) -> TreeNode {
      TreeNode(f.rawValue, kind: .folder(f), server: server, database: db.name)
    }
    let programming = TreeNode("Programmability", kind: .group, server: server, database: db.name)
    programming.loaded = true
    programming.children = [.procedures, .functions, .synonyms, .triggers].map(folder)
    let security = TreeNode("Security", kind: .group, server: server, database: db.name)
    security.loaded = true
    security.children = [folder(.users)]
    node.children = [folder(.tables), folder(.views), programming, security]
    if server.catalogFixture != nil {
      node.children[0].loaded=true; node.children[1].loaded=true
      node.children[0].children=[TreeNode("dbo.Customers",kind:.object(.tables),server:server,database:db.name,item:CatalogItem(id:1001,name:"Customers",schema:"dbo",detail:"USER_TABLE"))]
      node.children[1].children=[TreeNode("dbo.ActiveCustomers",kind:.object(.views),server:server,database:db.name,item:CatalogItem(id:1002,name:"ActiveCustomers",schema:"dbo",detail:"VIEW"))]
      for branch in programming.children {branch.loaded=true}
      programming.children[0].children=[TreeNode("dbo.SalesByCity",kind:.object(.procedures),server:server,database:db.name,item:CatalogItem(id:1003,name:"SalesByCity",schema:"dbo",detail:"SQL_STORED_PROCEDURE"))]
      programming.children[1].children=[TreeNode("dbo.CityLabel",kind:.object(.functions),server:server,database:db.name,item:CatalogItem(id:1004,name:"CityLabel",schema:"dbo",detail:"SQL_SCALAR_FUNCTION")),TreeNode("dbo.CityRows",kind:.object(.functions),server:server,database:db.name,item:CatalogItem(id:1008,name:"CityRows",schema:"dbo",detail:"SQL_INLINE_TABLE_VALUED_FUNCTION"))]
      programming.children[2].children=[TreeNode("dbo.CustomerAlias",kind:.object(.synonyms),server:server,database:db.name,item:CatalogItem(id:1009,name:"CustomerAlias",schema:"dbo",detail:"SYNONYM"))]
      programming.children[3].children=[TreeNode("DDLGuard",kind:.object(.triggers),server:server,database:db.name,item:CatalogItem(id:1007,name:"DDLGuard",detail:"SQL_TRIGGER, Disabled"))]
    }
    return node
  }
  @discardableResult func synchronizeFavorites(in root:TreeNode,favorites:[FavoriteQuery]) -> TreeNode {
    let folder=root.children.first {if case .favorites=$0.kind {return true};return false}
      ?? TreeNode("Favori Sorgular",kind:.favorites,server:root.server,database:root.server.profile.database)
    folder.loaded=true
    if !root.children.contains(where:{$0 === folder}) {root.children.append(folder)}
    let items=favorites.filter {$0.scope == .global || $0.serverID == root.server.id}
    let databases=Set(items.filter {$0.scope == .database}.compactMap(\.database)).sorted {$0.localizedStandardCompare($1) == .orderedAscending}
    let groups:[(FavoriteQuery.Scope,String,String)] = [(.global,"Genel",root.server.profile.database),(.connection,"Bu Bağlantı",root.server.profile.database)] + databases.map {(.database,$0,$0)}
    folder.children=groups.compactMap {scope,title,database in
      let values=items.filter {$0.scope == scope && (scope != .database || $0.database == database)}
      guard !values.isEmpty else {return nil}
      let group=folder.children.first {$0.favoriteScope == scope && $0.database == database}
        ?? TreeNode(title,kind:.favorites,server:root.server,database:database)
      group.favoriteScope=scope;group.loaded=true
      group.children=values.map {value in
        let node=group.children.first {$0.favorite?.id == value.id}
          ?? TreeNode(value.name,kind:.favorite,server:root.server,database:database)
        node.title=value.name;node.favorite=value;node.loaded=true
        return node
      }
      return group
    }
    return folder
  }
  func rebuildOrganizationRoots(_ value:ExplorerOrganization) {
    organization=value
    let ids=Set(organization.groups.map(\.id))
    groupNodes=groupNodes.filter {ids.contains($0.key)}
    for root in roots {root.parent=nil}
    for group in organization.groups {
      let node:TreeNode
      if let existing=groupNodes[group.id] {node=existing}
      else {
        let server=ConnectedServer(profile:ServerProfile(id:group.id,name:group.name),password:"");server.online=false
        node=TreeNode(group.name,kind:.connectionGroup,server:server);node.connectionGroupID=group.id;node.loaded=true
        groupNodes[group.id]=node
      }
      node.title=group.name;node.children=[]
    }
    func children(_ parent:UUID?)->[TreeNode] {
      organization.groups.filter {$0.parent==parent}.compactMap {groupNodes[$0.id]} + roots.filter {organization.assignments[$0.server.id]==parent}
    }
    for group in organization.groups {groupNodes[group.id]?.children=children(group.id)}
    displayRoots=children(nil)
  }
  func groupColor(_ id:UUID)->NSColor? {
    (try? organization.ancestors(id).compactMap(\.colorHex).first).map {ServerAppearance(colorHex:$0).color}
  }
  func sourceColor(for server:ConnectedServer)->NSColor? {
    if let appearance=server.profile.appearance,appearance.isMarked {return appearance.color}
    return organization.color(for:server.id).map {ServerAppearance(colorHex:$0).color}
  }
}
