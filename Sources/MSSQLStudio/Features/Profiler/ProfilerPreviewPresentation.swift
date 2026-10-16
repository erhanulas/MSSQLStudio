import Foundation
import Combine
import SQLServerKit

/// One physical worker; only the latest selection can publish its SQL and lexical snapshot.
@MainActor final class ProfilerPreviewPresentation:ObservableObject {
  @Published private(set) var sql="-- SQL metnini görmek için olay seçin."
  @Published private(set) var tokens:[Lexeme]=[]
  @Published private(set) var busy=false
  private var requested:[SQLProfiler.Event]?
  private var revision=0
  private var pending:(Int,[SQLProfiler.Event])?
  private var task:Task<Void,Never>?
  deinit {task?.cancel()}
  func request(_ events:[SQLProfiler.Event]) {
    guard requested != events else {return}
    requested=events
    revision+=1;pending=(revision,events);busy=true
    if task==nil {startNext()}
  }
  private func startNext() {
    guard let (generation,events)=pending else {busy=false;return}
    pending=nil
    task=Task { [weak self] in
      let result=await Task.detached(priority:.utility) {
        let sql=events.isEmpty ? "-- SQL metnini görmek için olay seçin.":ProfilerExport.sql(events)
        // Full source stays visible/copyable. Large captures use plain text instead of expensive color runs.
        return (sql,sql.utf16.count<=100_000 ? TSQL.lex(sql):[])
      }.value
      guard let self else {return}
      task=nil
      if generation==revision {sql=result.0;tokens=result.1;busy=false}
      startNext()
    }
  }
}
