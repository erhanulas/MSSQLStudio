import Foundation
import SQLServerKit

extension StudioState {
  func saveHistory() {
    guard !historyLoadFailed else {return}
    let cutoff=Date().addingTimeInterval(-Double(historyRetentionDays)*86400)
    history=Array(history.filter {$0.time>=cutoff}.prefix(20_000))
    let days=historyRetentionDays,url=folder.appendingPathComponent("history.json"),store=historyStore
    let previous=historySaveTask,revision=UUID();historyWriteRevision=revision;historyWriteError=nil
    NotificationCenter.default.post(name:.init("queryHistoryChanged"),object:self)
    historySaveTask=Task { [weak self] in
      if let previous {_=await previous.value}
      // Coalesce queued snapshots; an in-flight atomic write finishes before its successor.
      guard let self,historyWriteRevision==revision else {return true}
      let snapshot=history
      do {
        let retained=try await store.save(snapshot,to:url,days:days)
        if historyWriteRevision==revision {history=retained;historySaveTask=nil;NotificationCenter.default.post(name:.init("queryHistoryChanged"),object:self)}
        return true
      } catch {
        if historyWriteRevision==revision {historyWriteError=error.localizedDescription;historySaveTask=nil;showError(error.localizedDescription)}
        return false
      }
    }
  }
  func flushHistory() async -> Bool {
    while let pending=historySaveTask {_=await pending.value}
    return historyWriteError == nil
  }
}
