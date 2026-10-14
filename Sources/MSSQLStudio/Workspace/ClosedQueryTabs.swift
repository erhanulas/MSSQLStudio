import AppKit
import SQLServerKit

extension StudioState {
  func rememberClosedTab(_ document:QueryDocument) {
    var record=QueryRecord(server:document.server.profile.name,database:document.database,text:document.sql,serverID:document.server.id,seconds:0,status:"Kapatılan Sekme")
    record.tabTitle=document.title;record.caret=document.selectedRange.location;record.selectionLength=document.selectedRange.length
    guard !document.sql.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return}
    closedTabs=QueryHistoryPolicy.closedTabs([record]+closedTabs,limit:closedTabLimit)
    if historyEnabled {history.insert(record,at:0);saveHistory()}
    else {NotificationCenter.default.post(name:.init("queryHistoryChanged"),object:self)}
  }
  var lastClosedTab:QueryRecord? {lastClosedTab(for:active)}
  func lastClosedTab(for document:QueryDocument?)->QueryRecord? {
    let server=document?.server,db=document?.database
    return (closedTabs+(historyEnabled ? history.filter {$0.tabTitle != nil}:[]))
      .filter {$0.reopenedAt == nil && historyServer($0) != nil && (server == nil || historyServer($0) === server && $0.database == db)}.max {$0.time<$1.time}
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
  @objc func reopenLastClosedTab(_ sender:Any? = nil) {
    let context=(sender as? NSMenuItem)?.representedObject as? QueryDocument
    guard let record=state.lastClosedTab(for:context ?? state.active) else {return}
    _=state.reopenClosedTab(record)
  }
}
