import Foundation

/// Serialized atomic history writes; SQL encoding and disk work never run on the UI actor.
public actor QueryHistoryStore {
  public init() {}
  public func save(_ records:[QueryRecord],to url:URL,days:Int) throws -> [QueryRecord] {
    let retained=QueryHistoryPolicy.retained(records,days:days)
    let data=try JSONEncoder().encode(retained)
    guard data.count<20_000_000 else {throw SQLFailure("Sorgu geçmişi boyut sınırını aşıyor.")}
    try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    try data.write(to:url,options:.atomic)
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    return retained
  }
}
