import Foundation

/// Explorer configuration only. Credentials, query text and cached SQL never enter this format.
public struct ExplorerArchive:Codable,Sendable {
  public var version=1
  public var profiles:[ServerProfile]
  public var organization:ExplorerOrganization
  public init(profiles:[ServerProfile],organization:ExplorerOrganization) {
    self.profiles=profiles;self.organization=organization
  }
  public func encoded()throws->Data {
    let value=try validated()
    let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
    let data=try encoder.encode(value)
    guard data.count<=2_000_000 else {throw SQLFailure("Explorer aktarımı 2 MB sınırını aşıyor.")}
    return data
  }
  public static func decode(_ data:Data)throws->Self {
    guard data.count<=2_000_000 else {throw SQLFailure("Explorer aktarımı 2 MB sınırını aşıyor.")}
    return try JSONDecoder().decode(Self.self,from:data).validated()
  }
  public func validated()throws->Self {
    guard version==1,profiles.count<=500,Set(profiles.map(\.id)).count==profiles.count else {throw SQLFailure("Explorer aktarım sürümü veya bağlantı listesi geçersiz.")}
    _=try ExplorerOrganization.load(JSONEncoder().encode(organization))
    var copy=self
    for index in copy.profiles.indices {
      let p=copy.profiles[index]
      guard !p.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,p.name.count<=120,
        !p.host.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,p.host.count<=255,
        (1...65535).contains(p.port),!p.database.isEmpty,p.database.count<=128,p.login.count<=256,
        (p.visibleDatabases?.count ?? 0)<=5000,(p.definitionIndexDatabases?.count ?? 0)<=5000,
        p.visibleDatabases?.allSatisfy({!$0.isEmpty && $0.count<=128}) != false,
        p.definitionIndexDatabases?.keys.allSatisfy({!$0.isEmpty && $0.count<=128}) != false
      else {throw SQLFailure("Aktarılan bağlantı alanları geçersiz: \(p.name.prefix(120))")}
      copy.profiles[index].appearance=try p.appearance?.validated()
    }
    return copy
  }
  public struct Merge:Sendable {
    public let added:[ServerProfile]
    public let organization:ExplorerOrganization
    public let skipped:Int
  }
  public func merged(existing:[ServerProfile],organization current:ExplorerOrganization)throws->Merge {
    let archive=try validated()
    var added:[ServerProfile]=[],ids:[UUID:UUID]=[:],org=current,skipped=0
    for profile in archive.profiles {
      if let old=existing.first(where:{$0.name==profile.name && $0.hasSameConnectionSettings(as:profile,includeDatabase:true)}) {
        ids[profile.id]=old.id;skipped+=1;continue
      }
      var value=profile
      if existing.contains(where:{$0.id==value.id}) {value.id=UUID()}
      ids[profile.id]=value.id;added.append(value)
    }
    var groups:[UUID:UUID]=[:]
    let sorted=try archive.organization.groups.sorted {
      try archive.organization.ancestors($0.id).count < archive.organization.ancestors($1.id).count
    }
    for group in sorted {
      let parent=group.parent.flatMap {groups[$0]}
      if let old=org.groups.first(where:{$0.parent==parent && $0.name.caseInsensitiveCompare(group.name) == .orderedSame}) {groups[group.id]=old.id}
      else {
        let id=try org.create(group.name,parent:parent);groups[group.id]=id
        try org.setColor(id,hex:group.colorHex)
      }
    }
    for (source,destination) in archive.organization.assignments {
      guard let server=ids[source],added.contains(where:{$0.id==server}),let group=groups[destination] else {continue}
      try org.assign(server,to:group)
    }
    _=try ExplorerOrganization.load(JSONEncoder().encode(org))
    return Merge(added:added,organization:org,skipped:skipped)
  }
}
