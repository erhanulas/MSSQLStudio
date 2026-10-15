import Foundation
import SQLServerKit

/// Database row status is independent of the selected database/header summary.
@MainActor final class ExplorerIndexStatusController {
  struct Snapshot {
    var objectsReady=false
    var definitionsReady=false
    var definitionsWarning=false
    var readError:String?
  }
  private struct Key:Hashable {let server:UUID;let database:String}
  @MainActor private final class Entry {
    let token=UUID()
    let generation:UUID
    let revision:UUID
    let profile:ServerProfile
    var value:Snapshot?
    var invalidated=false
    var task:Task<Void,Never>?
    init(_ server:ConnectedServer) {generation=server.generation;revision=server.catalogIndexRevision;profile=server.profile}
    deinit {task?.cancel()}
  }
  private var entries:[Key:Entry]=[:]
  func snapshot(server:ConnectedServer,database:String)->Snapshot? {
    let entry=entries[Key(server:server.id,database:database)]
    guard entry?.generation==server.generation,entry?.revision==server.catalogIndexRevision,
      entry?.profile==server.profile,entry?.invalidated==false else {return nil}
    return entry?.value
  }
  func invalidate(server:ConnectedServer,database:String?) {
    for (key,entry) in entries where key.server==server.id && (database==nil || key.database==database) {
      entry.invalidated=true;entry.task?.cancel()
    }
  }
  func retain(servers:Set<UUID>) {
    entries=entries.filter {servers.contains($0.key.server)}
  }
  func request(server:ConnectedServer,database:String,changed:@escaping @MainActor ()->Void) {
    let key=Key(server:server.id,database:database),old=entries[key]
    if let old,!old.invalidated,old.generation==server.generation,
      old.revision==server.catalogIndexRevision,old.profile==server.profile {return}
    old?.task?.cancel()
    let entry=Entry(server),token=entry.token,generation=entry.generation,revision=entry.revision,profile=entry.profile
    let previous=old?.task
    entries[key]=entry
    entry.task=Task { [weak self] in
      if let previous {await previous.value}
      guard !Task.isCancelled else {return}
      var value=Snapshot()
      do {
        let definition=try await server.definitionIndex.presentation(database:database)
        value.definitionsReady=definition.enabled && definition.stored?.synchronizedAt != nil && definition.stored?.incomplete == false
        value.definitionsWarning=definition.warning
        value.objectsReady=try await server.catalogIndexStatus(database:database) != nil
      } catch is CancellationError {return}
      catch {value.readError=error.localizedDescription}
      guard !Task.isCancelled,let self,entries[key]?.token==token,
        server.generation==generation,server.catalogIndexRevision==revision,server.profile==profile else {return}
      entries[key]?.value=value;entries[key]?.task=nil
      changed()
    }
  }
}
