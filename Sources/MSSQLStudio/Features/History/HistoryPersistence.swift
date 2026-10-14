import Foundation
import SQLServerKit

extension StudioState {
  func saveHistory() {
    guard !historyLoadFailed else {return}
    let cutoff=Date().addingTimeInterval(-Double(historyRetentionDays)*86400)
    var counts:[String:Int]=[:]
    history=Array(history.filter {record in
      if record.tabTitle == nil {return record.time>=cutoff}
      let key=(record.serverID?.uuidString ?? record.server)+"|"+record.database
      guard !record.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,counts[key,default:0]<closedTabLimit else {return false}
      counts[key,default:0]+=1;return true
    }.prefix(20_000))
    let limit=closedTabLimit,days=historyRetentionDays,url=folder.appendingPathComponent("history.json"),store=historyStore
    let previous=historySaveTask,revision=UUID();historyWriteRevision=revision;historyWriteError=nil
    NotificationCenter.default.post(name:.init("queryHistoryChanged"),object:self)
    historySaveTask=Task { [weak self] in
      if let previous {_=await previous.value}
      // Coalesce queued snapshots; an in-flight atomic write finishes before its successor.
      guard let self,historyWriteRevision==revision else {return true}
      let snapshot=history
      do {
        let retained=try await store.save(snapshot,to:url,days:days,closedTabLimit:limit)
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
