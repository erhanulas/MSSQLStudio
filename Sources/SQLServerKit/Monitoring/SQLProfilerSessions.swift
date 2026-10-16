import Foundation

extension SQLProfiler {
  public struct ServerSession:Sendable,Identifiable,Equatable {
    public let name:String
    public let running:Bool
    public let started:String
    public var id:String {name}
  }
  public static let sessionsSQL="""
  SET NOCOUNT ON;
  SELECT TOP (501) e.name AS session_name,
    CASE WHEN s.name IS NULL THEN N'0' ELSE N'1' END AS is_running,
    CONVERT(nvarchar(23),s.create_time,121) AS started
  FROM sys.server_event_sessions e
  LEFT JOIN sys.dm_xe_sessions s ON s.name=e.name
  WHERE LEFT(e.name,21)=N'MSSQLStudio_Profiler_'
  ORDER BY e.name;
  """
  public static func decodeSessions(_ execution:Execution)throws->[ServerSession] {
    guard !execution.partial,!execution.stoppedEarly,execution.results.count==1,
      let rows=execution.results.first,!rows.truncated,rows.values.count<=500,
      rows.fields.map(\.name)==["session_name","is_running","started"] else {throw SQLFailure("Profiler oturum listesi eksik veya kısmi.")}
    var names=Set<String>()
    return try rows.values.map {row in
      guard row.count==3,let name=row[0],names.insert(name).inserted,
        row[1]=="0" || row[1]=="1",(row[2]?.count ?? 0)<=23 else {throw SQLFailure("Profiler oturum bilgisi geçersiz.")}
      _ = try dropSQL(name:name) // Exact prefix + UUID validation, never a wildcard drop.
      return ServerSession(name:name,running:row[1]=="1",started:row[2] ?? "—")
    }
  }
}
