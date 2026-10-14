import Foundation
import SQLServerKit

/// One bounded metadata flight per Explorer connection, independent of query sessions.
@MainActor final class SQLHoverMetadata {
  private weak var server:ConnectedServer?
  private var running:Task<SQLObjectHover.Info?,any Error>?
  private var cache:[String:(Date,SQLObjectHover.Info?)]=[:]
  init(server:ConnectedServer) {self.server=server}
  func lookup(targets:[[String]],column:String?=nil,database:String) async throws->SQLObjectHover.Info? {
    guard let server,server.online else {return nil}
    let generation=server.generation,sql=try SQLObjectHover.query(targets:targets,column:column)
    let key=generation.uuidString+"|"+database+"|"+sql
    while let previous=running {
      _=try? await previous.value
      try Task.checkCancellation()
    }
    try Task.checkCancellation()
    guard server.online,server.generation==generation else {return nil}
    if let value=cache[key],Date().timeIntervalSince(value.0)<300 {return value.1}
    let work=Task { [weak self,weak server] () throws->SQLObjectHover.Info? in
      defer {self?.running=nil}
      guard let server else {return nil}
      var limits=Limits();limits.rows=8193;limits.timeout=5;limits.totalBytes=8_000_000
      let info=SQLObjectHover.decode(try await server.catalog(sql,database:database,limits:limits),column:column)
      guard server.generation==generation else {return nil}
      if let self {if cache.count>=64 {cache.removeAll()};cache[key]=(Date(),info)}
      return info
    }
    running=work
    let value=try await work.value
    try Task.checkCancellation()
    return value
  }
}
