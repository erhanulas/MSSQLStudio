import AppKit
import SQLServerKit

extension StudioState {
  func rememberClosedTab(_ document:QueryDocument) {
    var record=QueryRecord(server:document.server.profile.name,database:document.database,text:document.sql,serverID:document.server.id,seconds:0,status:"Kapatılan Sekme")
    record.tabTitle=document.title;record.caret=document.selectedRange.location;record.selectionLength=document.selectedRange.length
    let cutoff=Date().addingTimeInterval(-Double(historyRetentionDays)*86400)
    var bytes=0
    closedTabs=Array(([record]+closedTabs).prefix(100)).filter {
      let size=$0.text.utf8.count
      guard $0.time>=cutoff,bytes+size<=16_000_000 else {return false}
      bytes+=size;return true
    }
    if historyEnabled {history.insert(record,at:0);saveHistory()}
  }
  var lastClosedTab:QueryRecord? {
    let cutoff=Date().addingTimeInterval(-Double(historyRetentionDays)*86400)
    return (closedTabs+(historyEnabled ? history.filter {$0.tabTitle != nil}:[]))
      .filter {$0.time>=cutoff && $0.reopenedAt == nil && historyServer($0) != nil}.max {$0.time<$1.time}
  }
  @discardableResult func reopenClosedTab(_ record:QueryRecord)->QueryDocument? {
    guard let server=historyServer(record) else {return nil}
    let document=newQuery(server:server,database:record.database,text:record.text,title:record.tabTitle ?? "History",selection:NSRange(location:max(0,record.caret ?? 0),length:max(0,record.selectionLength ?? 0)))
    for index in closedTabs.indices where closedTabs[index].id == record.id {closedTabs[index].reopenedAt=Date()}
    for index in history.indices where history[index].id == record.id {history[index].reopenedAt=Date()}
    if historyEnabled {saveHistory()}
    return document
  }
}

extension WorkbenchController {
  @objc func reopenLastClosedTab() {
    guard let record=state.lastClosedTab,let document=state.reopenClosedTab(record) else {return}

  }
}
