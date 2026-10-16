import Foundation
import SQLServerKit

/// Portable captures, not SQL Server's binary .trc/.xel formats. No SQL is executed.
enum ProfilerExport {
  enum Format:String,CaseIterable,Identifiable,Sendable {
    case trace,sql
    var id:String {rawValue}
    var title:String {self == .trace ? "İz kaydı (JSON)":"SQL betiği"}
    var suffix:String {self == .trace ? "mssqltrace.json":"sql"}
  }
  private struct Capture:Encodable {
    let format="MSSQLStudio.Profiler"
    let version=1
    let scope="Retained events only; capture may contain gaps."
    let events:[SQLProfiler.Event]
  }
  static func sql(_ events:[SQLProfiler.Event])->String {
    events.map(\.sql).joined(separator:"\nGO\n")
  }
  static func data(_ events:[SQLProfiler.Event],format:Format)throws->Data {
    guard events.count<=5000,events.reduce(0,{$0+$1.retainedBytes})<=8*1024*1024 else {
      throw SQLFailure("Dışa aktarma olay bütçesini aşıyor.")
    }
    if format == .sql {return Data(sql(events).utf8)}
    let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
    return try encoder.encode(Capture(events:events))
  }
}
