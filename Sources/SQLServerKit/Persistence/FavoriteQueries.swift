import Foundation

public struct FavoriteQuery: Codable, Sendable, Identifiable, Equatable {
  public enum Scope: String, Codable, Sendable, CaseIterable { case global, connection, database }
  public var id: UUID
  public var name: String
  public var sql: String
  public var scope: Scope
  public var serverID: UUID?
  public var database: String?
  public var updated: Date
  public init(id: UUID = UUID(), name: String, sql: String, scope: Scope, serverID: UUID? = nil, database: String? = nil, updated: Date = Date()) throws {
    self.id=id;self.name=name.trimmingCharacters(in:.whitespacesAndNewlines);self.sql=sql;self.scope=scope
    self.serverID=scope == .global ? nil:serverID
    self.database=scope == .database ? database?.trimmingCharacters(in:.whitespacesAndNewlines):nil
    self.updated=updated
    try validate()
  }
  public func validate() throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=120,
      !sql.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,sql.utf8.count<=1_000_000,
      (scope == .global ? serverID == nil && database == nil:serverID != nil),
      (scope == .database ? database?.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty == false && (database?.utf8.count ?? 0)<=512:database == nil)
    else {throw SQLFailure("Favori için bir ad (en çok 120 karakter), SQL (en çok 1 MB) ve geçerli kapsam seçin.")}
  }
  public func visible(serverID: UUID?, database: String?) -> Bool {
    switch scope {
    case .global: return true
    case .connection: return self.serverID == serverID
    case .database: return self.serverID == serverID && self.database == database
    }
  }
}

public actor FavoriteQueryStore {
  private let url: URL
  public init(url: URL) {self.url=url}
  public func load() throws -> [FavoriteQuery] {
    guard FileManager.default.fileExists(atPath:url.path) else {return []}
    let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
    guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 16_000_000 else {throw SQLFailure("Favoriler dosyası 16 MB sınırını aşıyor.")}
    let values=try JSONDecoder().decode([FavoriteQuery].self,from:Data(contentsOf:url))
    guard values.count<=500,Set(values.map(\.id)).count == values.count else {throw SQLFailure("Favoriler dosyası geçersiz veya 500 kayıt sınırını aşıyor.")}
    for value in values {try value.validate()}
    return values.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
  }
  public func save(_ favorite: FavoriteQuery) throws -> [FavoriteQuery] {
    try favorite.validate()
    var values=try load()
    if let index=values.firstIndex(where:{$0.id == favorite.id}) {values[index]=favorite} else {values.append(favorite)}
    try write(values)
    return values.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
  }
  public func remove(_ id: UUID) throws -> [FavoriteQuery] {
    let values=try load().filter {$0.id != id}
    try write(values);return values
  }
  private func write(_ values:[FavoriteQuery]) throws {
    let data=try JSONEncoder().encode(values)
    guard values.count<=500,data.count<=16_000_000 else {throw SQLFailure("En çok 500 favori ve toplam 16 MB SQL saklanabilir.")}
    try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    try data.write(to:url,options:.atomic)
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
  }
}

/// The quick picker is tied to one editor target; its search never broadens that scope.
public enum FavoriteQuerySelection {
  public static func matches(_ values:[FavoriteQuery],serverID:UUID?,database:String?,search:String="") -> [FavoriteQuery] {
    let terms=search.split(whereSeparator:{$0.isWhitespace}).map(String.init)
    return values.filter {value in
      value.visible(serverID:serverID,database:database) && terms.allSatisfy {value.name.localizedStandardContains($0)}
    }.sorted {left,right in
      func priority(_ scope:FavoriteQuery.Scope) -> Int {scope == .database ? 0:scope == .connection ? 1:2}
      if left.scope != right.scope {return priority(left.scope)<priority(right.scope)}
      let order=left.name.localizedStandardCompare(right.name)
      return order == .orderedSame ? left.id.uuidString<right.id.uuidString:order == .orderedAscending
    }
  }
  public static func next(_ values:[FavoriteQuery],selected:UUID?,step:Int) -> UUID? {
    guard !values.isEmpty else {return nil}
    let index=values.firstIndex {$0.id == selected} ?? (step < 0 ? values.count: -1)
    return values[min(values.count-1,max(0,index+step))].id
  }
}
