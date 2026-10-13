import Foundation

/// Local organization only. Group changes never alter a connection or credentials.
public struct ExplorerOrganization:Codable,Equatable,Sendable {
  public struct Group:Codable,Equatable,Identifiable,Sendable {
    public let id:UUID
    public var name:String
    public var parent:UUID?
    public var colorHex:String?
  }
  public private(set) var groups:[Group]=[]
  public private(set) var assignments:[UUID:UUID]=[:]
  public init() {}
  public static func load(_ data:Data?)throws->Self {
    guard let data else {return Self()}
    guard data.count<=256_000 else {throw SQLFailure("Explorer klasör kaydı çok büyük.")}
    let value=try JSONDecoder().decode(Self.self,from:data)
    guard value.groups.count<=100,Set(value.groups.map(\.id)).count==value.groups.count,value.assignments.count<=10_000 else {throw SQLFailure("Explorer klasör kaydı geçersiz.")}
    for group in value.groups {
      _ = try value.validName(group.name,parent:group.parent,excluding:group.id)
      if let color=group.colorHex,ServerAppearance.normalizedHex(color)==nil {throw SQLFailure("Klasör rengi geçersiz.")}
      _ = try value.ancestors(group.id)
    }
    guard value.assignments.values.allSatisfy({id in value.groups.contains {$0.id==id}}) else {throw SQLFailure("Explorer klasör eşleştirmesi geçersiz.")}
    return value
  }
  public func ancestors(_ id:UUID?)throws->[Group] {
    var result:[Group]=[],seen=Set<UUID>(),cursor=id
    while let current=cursor {
      guard seen.insert(current).inserted,result.count<8,let group=groups.first(where:{$0.id==current}) else {throw SQLFailure("Klasör döngüsü veya derinlik sınırı.")}
      result.append(group);cursor=group.parent
    }
    return result
  }
  private func validName(_ name:String,parent:UUID?,excluding:UUID?=nil)throws->String {
    let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
    guard !name.isEmpty else {throw SQLFailure("Klasör adını girin.")}
    guard name.count<=80 else {throw SQLFailure("Klasör adı en fazla 80 karakter olabilir.")}
    guard !name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else {throw SQLFailure("Klasör adı görünmeyen bir kontrol karakteri içeriyor.")}
    guard !groups.contains(where:{$0.id != excluding && $0.parent==parent && $0.name.caseInsensitiveCompare(name) == .orderedSame}) else {throw SQLFailure("Bu konumda aynı adlı bir klasör zaten var.")}
    return name
  }
  @discardableResult public mutating func create(_ name:String,parent:UUID?=nil)throws->UUID {
    guard groups.count<100,try ancestors(parent).count<8 else {throw SQLFailure("En fazla 100 klasör ve 8 seviye desteklenir.")}
    let name=try validName(name,parent:parent),id=UUID()
    groups.append(Group(id:id,name:name,parent:parent,colorHex:nil));return id
  }
  public mutating func rename(_ id:UUID,name:String)throws {
    guard let i=groups.firstIndex(where:{$0.id==id}) else {throw SQLFailure("Klasör bulunamadı.")}
    groups[i].name=try validName(name,parent:groups[i].parent,excluding:id)
  }
  public mutating func move(_ id:UUID,to parent:UUID?)throws {
    guard let i=groups.firstIndex(where:{$0.id==id}),id != parent,try !ancestors(parent).contains(where:{$0.id==id}) else {throw SQLFailure("Klasör kendi içine taşınamaz.")}
    _ = try validName(groups[i].name,parent:parent,excluding:id)
    // Validate depth for every descendant before committing the move.
    var copy=self;copy.groups[i].parent=parent
    for group in copy.groups {_ = try copy.ancestors(group.id)}
    self=copy
  }
  public mutating func assign(_ server:UUID,to group:UUID?)throws {
    if let group, !groups.contains(where:{$0.id==group}) {throw SQLFailure("Klasör bulunamadı.")}
    assignments[server]=group
  }
  public mutating func setColor(_ id:UUID,hex:String?)throws {
    guard let i=groups.firstIndex(where:{$0.id==id}),hex == nil || ServerAppearance.normalizedHex(hex) != nil else {throw SQLFailure("Klasör rengi geçersiz.")}
    groups[i].colorHex=ServerAppearance.normalizedHex(hex)
  }
  public mutating func remove(_ id:UUID)throws {
    guard let group=groups.first(where:{$0.id==id}) else {throw SQLFailure("Klasör bulunamadı.")}
    groups.removeAll {$0.id==id}
    for i in groups.indices where groups[i].parent==id {
      groups[i].parent=group.parent
      let base=String(groups[i].name.prefix(70));var name=groups[i].name,suffix=2
      while groups.contains(where:{$0.id != groups[i].id && $0.parent==group.parent && $0.name.caseInsensitiveCompare(name) == .orderedSame}) {name="\(base) (\(suffix))";suffix+=1}
      groups[i].name=name
    }
    for server in assignments.keys where assignments[server]==id {assignments[server]=group.parent}
  }
  public func color(for server:UUID)->String? {try? ancestors(assignments[server]).compactMap(\.colorHex).first}
  public func path(_ id:UUID)->String {(try? ancestors(id).reversed().map(\.name).joined(separator:" / ")) ?? ""}
}
