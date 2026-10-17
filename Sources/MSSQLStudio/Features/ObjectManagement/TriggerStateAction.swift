import Foundation
import SQLServerKit

/// One explicit trigger command at a time; never stage or retry a database write.
@MainActor final class TriggerStateAction {
  private(set) var busy=false
  func apply(_ node:TreeNode,enabled:Bool,confirm:(TriggerDefinition)->Bool,refreshed:()->Void) async throws {
    guard !busy else {return}
    guard let item=node.item,node.objectFolder == .triggers,node.server.online else {throw SQLFailure("Bağlı bir trigger seçin.")}
    busy=true;defer {busy=false}
    let server=node.server,generation=server.generation,database=node.database
    func current()->Bool {server.online && server.generation==generation && !Task.isCancelled}
    let initial=try TriggerDefinition.decode(await server.catalog(TriggerDefinition.metadata(item.id),database:database))
    guard current(),initial.qualified==item.qualified else {throw SQLFailure("Trigger veya bağlantı değişmiş; Explorer listesini yenileyin.")}
    if initial.disabled == !enabled {refreshed();return}
    guard confirm(initial) else {return}
    guard current() else {throw CancellationError()}
    let result=try await server.catalog(initial.guardedStateScript(id:item.id,enabled:enabled),database:database)
    guard current() else {throw SQLFailure("Bağlantı değişti. Komut sonucu belirsiz; yeniden göndermeden durumu yenileyin.")}
    guard !result.partial,!result.stoppedEarly,result.failure==nil else {throw SQLFailure("Komut sonucu doğrulanamadı; yeniden göndermeden durumu yenileyin.")}
    // Read back state; a failed read must never trigger an automatic second write.
    do {
      let updated=try TriggerDefinition.decode(await server.catalog(TriggerDefinition.metadata(item.id),database:database))
      guard current(),updated.qualified==initial.qualified,updated.parent==initial.parent,updated.databaseScope==initial.databaseScope,updated.disabled == !enabled else {throw SQLFailure("Trigger durumu doğrulanamadı.")}
      refreshed()
    } catch {throw SQLFailure("Komut gönderildi; güncel durum okunamadı. Explorer listesini yenileyin. "+error.localizedDescription)}
  }
}
