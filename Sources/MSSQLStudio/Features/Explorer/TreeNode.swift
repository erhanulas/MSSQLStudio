import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class DatabaseIndexButton:NSButton { weak var node:TreeNode? }
@MainActor final class TreeNode: NSObject {
  enum Kind {
    case server, group, database, favorites, favorite, connectionGroup
    case folder(Folder)
    case object(Folder)
    case detail
  }
  enum LinkedBranch {
    case catalogs(String), catalog(String, String?), group
    case relation(LinkedCatalog.Relation), columns(LinkedCatalog.Relation), detail
  }
  var connectionGroupID:UUID?
  var linked: LinkedBranch?
  var title: String
  var favorite: FavoriteQuery?
  var favoriteScope: FavoriteQuery.Scope?
  let generation: UUID
  let kind: Kind
  let server: ConnectedServer
  let database: String
  var item: CatalogItem?
  weak var parent: TreeNode?
  var children: [TreeNode] = [] { didSet { for child in children { child.parent=self } } }
  var databaseIdentity:[String]?
  var loaded = false
  var loading = false
  var error: String?
  init(
    _ title: String, kind: Kind, server: ConnectedServer, database: String = "master",
    item: CatalogItem? = nil
  ) {
    self.title = title
    self.generation = server.generation
    self.kind = kind
    self.server = server
    self.database = database
    self.item = item
  }
  var displayTitle: String {
    if case .server = kind {
      return server.profile.name + (server.updatingProfile ? " · Kaydediliyor…" : server.reconnecting ? " · Bağlanıyor…" : server.online ? " · Bağlı" : " · Bağlantı kapalı")
    }
    if case .object(.triggers)=kind { return title }
    if case .object(.jobs)=kind { return item?.name ?? title }
    return title
  }
  var persistenceKey:String {
    if let id=connectionGroupID {return "connection-group|"+id.uuidString}
    var parts:[String]=[];var cursor:TreeNode?=self
    while let node=cursor {
      if case .connectionGroup=node.kind {cursor=node.parent;continue}
      let kind:String
      switch node.kind {
      case .connectionGroup:kind="connectionGroup"
      case .server:kind="server"
      case .group:kind="group"
      case .database:kind="database"
      case .favorites:kind="favorites:"+(node.favoriteScope?.rawValue ?? "root")
      case .favorite:kind="favorite"
      case .folder(let folder):kind="folder:"+folder.rawValue
      case .object(let folder):kind="object:"+folder.rawValue
      case .detail:kind="detail"
      }
      parts.insert(contentsOf:[kind,node.database,node.favorite?.id.uuidString ?? node.item.map {String($0.id)+":"+$0.schema+":"+$0.name} ?? (kind == "server" ? node.server.id.uuidString:node.title)],at:0)
      cursor=node.parent
    }
    return String(decoding:try! JSONEncoder().encode(parts),as:UTF8.self)
  }
  var triggerDisabled:Bool { item?.detail.contains("Disabled") == true }
  var ownerObject:TreeNode? {
    var node=parent
    while let current=node { if case .object(let f)=current.kind, [.tables,.views,.procedures,.functions].contains(f) {return current}; node=current.parent }
    return nil
  }
  var objectFolder:Folder? { if case .object(let f)=kind { return f }; return nil }
  var expandable: Bool {
    if case .detail = linked {return false}
    if linked != nil {return true}
    if case .object(.linkedServers) = kind {return true}
    switch kind {
    case .server, .group, .database, .favorites, .connectionGroup: return true
    case .folder(let folder):
      return [
        .databases, .tables, .views, .procedures, .functions, .synonyms, .columns, .indexes, .keys,
        .triggers, .constraints, .parameters, .logins, .users, .roles, .linkedServers, .jobs,
        .schedules,
      ].contains(folder)
    case .object(let folder): return [.tables, .views, .procedures, .functions].contains(folder)
    case .detail, .favorite: return false
    }
  }
  private var category: Folder? {
    switch kind {
    case .folder(let folder), .object(let folder): return folder
    default: return nil
    }
  }
  var tint: NSColor {
    switch kind {
    case .server:
      return server.profile.appearance?.isMarked == true
        ? server.profile.appearance!.color : StudioTheme.accent
    case .favorites, .favorite: return StudioTheme.warning
    case .database: return StudioTheme.color(0x278A91, 0x69C3C7)
    case .group:
      if title == "Security" { return StudioTheme.color(0xB77A36, 0xDDB17F) }
      if title == "SQL Server Agent" { return StudioTheme.color(0x8B69B6, 0xBA9AD7) }
      if title == "Management" { return StudioTheme.color(0x43866C, 0x87C0AA) }
      return StudioTheme.accent
    default: break
    }
    switch category {
    case .databases: return StudioTheme.color(0x278A91, 0x69C3C7)
    case .tables, .columns: return StudioTheme.accent
    case .views: return StudioTheme.color(0x278A91, 0x69C3C7)
    case .procedures, .functions, .parameters, .synonyms: return StudioTheme.color(0x8B69B6, 0xBA9AD7)
    case .logins, .users, .roles, .keys, .constraints: return StudioTheme.color(0xB77A36, 0xDDB17F)
    case .activity, .sessions, .locks, .files: return StudioTheme.color(0x43866C, 0x87C0AA)
    case .jobs where item?.detail.contains("Disabled") == true:return .secondaryLabelColor
    case .jobs, .jobHistory, .schedules: return StudioTheme.color(0xA46B9D, 0xD7A3CF)
    case .triggers: return triggerDisabled ? .secondaryLabelColor : StudioTheme.color(0x43866C, 0x87C0AA)
    case .indexes: return StudioTheme.color(0xB77A36, 0xDDB17F)
    default: return .secondaryLabelColor
    }
  }
  var icon: String {
    switch kind {
    case .favorites: return favoriteScope == .global ? "globe" : favoriteScope == .database ? "cylinder.split.1x2" : "star.circle"
    case .favorite: return "star.fill"
    case .connectionGroup:return "folder.fill"
    case .server: return "server.rack"
    case .database: return "cylinder.split.1x2"
    case .group:
      if title == "Security" { return "lock.shield" }
      if title == "SQL Server Agent" { return "clock.badge.checkmark" }
      if title == "Management" { return "waveform.path.ecg" }
      return "folder"
    case .detail: return "rectangle.split.1x2"
    default: break
    }
    switch category {
    case .databases: return "externaldrive"
    case .tables: return "tablecells"
    case .views: return "eye"
    case .procedures: return "terminal"
    case .functions: return "function"
    case .parameters: return "at"
    case .triggers: return triggerDisabled ? "bolt.slash.fill" : "bolt.fill"
    case .constraints: return "checkmark.shield"
    case .linkedServers: return "network"
    case .synonyms: return "link"
    case .columns: return "rectangle.split.1x2"
    case .logins, .users: return "person.crop.circle"
    case .roles: return "lock.shield"
    case .keys: return "key"
    case .indexes: return "list.number"
    case .activity, .sessions: return "waveform.path.ecg"
    case .locks: return "lock"
    case .jobs: return item?.detail.contains("Running") == true ? "play.circle.fill":item?.detail.contains("Disabled") == true ? "pause.circle":"clock.badge.checkmark"
    case .schedules, .jobHistory: return "clock"
    default: return "folder"
    }
  }
}
