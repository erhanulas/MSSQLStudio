import Foundation

/// Global filter settings only: no server identity, credential, captured SQL or session ownership.
public struct ProfilerFilterTemplate:Codable,Sendable,Identifiable,Equatable {
  public let id:UUID
  public var name:String
  public var configuration:SQLProfiler.Configuration
  public var displayFilter:SQLProfilerFiltering.Filter
  public init(id:UUID=UUID(),name:String,configuration:SQLProfiler.Configuration,displayFilter:SQLProfilerFiltering.Filter) throws {
    self.id=id;self.name=name.trimmingCharacters(in:.whitespacesAndNewlines)
    self.configuration=configuration;self.displayFilter=displayFilter
    try validate()
  }
  public func validate() throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=120,!name.contains("\0") else {throw SQLFailure("Şablon adı 1–120 karakter olmalıdır.")}
    _=try SQLProfiler.createSQL(name:SQLProfiler.sessionName(id),configuration:configuration)
    _=try SQLProfilerFiltering.project([],filter:displayFilter)
  }
}

public actor ProfilerFilterTemplateStore {
  private struct Archive:Codable {let version:Int;let templates:[ProfilerFilterTemplate]}
  private let url:URL
  public init(url:URL) {self.url=url}
  public func load() throws -> [ProfilerFilterTemplate] {
    guard FileManager.default.fileExists(atPath:url.path) else {return []}
    let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
    guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max)<=524_288 else {throw SQLFailure("Profiler şablonları dosyası 512 KB sınırını aşıyor.")}
    let archive=try JSONDecoder().decode(Archive.self,from:Data(contentsOf:url))
    guard archive.version==1 else {throw SQLFailure("Profiler şablon dosyasının sürümü desteklenmiyor.")}
    try validate(archive.templates)
    return sorted(archive.templates)
  }
  public func save(_ template:ProfilerFilterTemplate) throws -> [ProfilerFilterTemplate] {
    try template.validate()
    var values=try load()
    if let index=values.firstIndex(where:{$0.id==template.id}) {values[index]=template} else {values.append(template)}
    try write(values);return sorted(values)
  }
  public func remove(_ id:UUID) throws -> [ProfilerFilterTemplate] {
    let values=try load().filter {$0.id != id}
    try write(values);return sorted(values)
  }
  private func validate(_ values:[ProfilerFilterTemplate]) throws {
    guard values.count<=100,Set(values.map(\.id)).count==values.count else {throw SQLFailure("En fazla 100 benzersiz Profiler şablonu saklanabilir.")}
    var names:Set<String>=[]
    for value in values {
      try value.validate()
      guard names.insert(value.name.trimmingCharacters(in:.whitespacesAndNewlines).folding(options:[.caseInsensitive],locale:Locale(identifier:"tr_TR"))).inserted else {throw SQLFailure("Bu adla bir Profiler şablonu var. Başka bir ad kullanın veya seçili şablonu güncelleyin.")}
    }
  }
  private func sorted(_ values:[ProfilerFilterTemplate])->[ProfilerFilterTemplate] {values.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}}
  private func write(_ values:[ProfilerFilterTemplate]) throws {
    try validate(values)
    let data=try JSONEncoder().encode(Archive(version:1,templates:values))
    guard data.count<=524_288 else {throw SQLFailure("Profiler şablonları toplam 512 KB sınırını aşıyor.")}
    try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    try data.write(to:url,options:.atomic)
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
  }
}
