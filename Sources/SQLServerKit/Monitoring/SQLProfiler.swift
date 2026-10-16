import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Bounded, server-scoped Extended Events capture. Never adopts another session.
public enum SQLProfiler {
  public struct Configuration:Sendable,Equatable {
    public var database=""
    public var application=""
    public var login=""
    public var host=""
    public var clientPID=""
    public var sessionID=""
    public var sqlLike=""
    public var sqlNotLike=""
    public var minimumDurationMS=0
    public init() {}
  }
  public static func sessionName(_ id:UUID)->String {"MSSQLStudio_Profiler_"+id.uuidString.replacingOccurrences(of:"-",with:"")}
  private static func checked(_ name:String) throws -> String {
    guard name.hasPrefix("MSSQLStudio_Profiler_"),name.count==53,
      name.suffix(32).allSatisfy({"0123456789ABCDEFabcdef".contains($0)}) else {throw SQLFailure("Geçersiz Profiler oturum kimliği.")}
    return SQL.identifier(name)
  }
  public static func createSQL(name:String,configuration:Configuration) throws -> String {
    let identifier=try checked(name)
    guard (0...86_400_000).contains(configuration.minimumDurationMS),
      [configuration.database,configuration.application,configuration.login,configuration.host].allSatisfy({$0.utf16.count<=128 && !$0.contains("\0") && !$0.contains("__PROFILER_SPID__")}) else {throw SQLFailure("Profiler filtreleri geçersiz veya çok uzun.")}
    guard [configuration.sqlLike,configuration.sqlNotLike].allSatisfy({$0.utf16.count<=1024 && !$0.contains("\0") && !$0.contains("__PROFILER_SPID__")}),
      [configuration.clientPID,configuration.sessionID].allSatisfy({$0.isEmpty || ($0.allSatisfy({"0123456789".contains($0)}) && UInt32($0).map {$0>0} == true)}) else {throw SQLFailure("ClientProcessID/SPID veya SQL LIKE filtresi geçersiz.")}
    guard configuration.sessionID.isEmpty || UInt32(configuration.sessionID).map {$0<=32767} == true else {throw SQLFailure("SPID 1–32.767 aralığında olmalıdır.")}
    var predicates=["[sqlserver].[is_system]=(0)","[sqlserver].[session_id]<>@@SPID"]
    // @@SPID cannot appear inside a DDL event predicate. Resolve once into dynamic DDL.
    predicates[1]="[sqlserver].[session_id]<>(__PROFILER_SPID__)"
    for (key,value) in [("database_name",configuration.database),("client_app_name",configuration.application),("server_principal_name",configuration.login),("client_hostname",configuration.host)] where !value.isEmpty {
      predicates.append("[sqlserver].[\(key)]=\(SQL.literal(value))")
    }
    for (key,value) in [("client_pid",configuration.clientPID),("session_id",configuration.sessionID)] where !value.isEmpty {
      predicates.append("[sqlserver].[\(key)]=(\(UInt32(value)!))")
    }
    for (pattern,negative) in [(configuration.sqlLike,false),(configuration.sqlNotLike,true)] where !pattern.isEmpty {
      let expression="[sqlserver].[like_i_sql_unicode_string]([sqlserver].[sql_text],\(SQL.literal(pattern)))"
      predicates.append(negative ? "NOT (\(expression))":expression)
    }
    let actions="package0.event_sequence,sqlserver.session_id,sqlserver.client_pid,sqlserver.database_name,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.server_principal_name,sqlserver.sql_text"
    func event(_ name:String,completed:Bool)->String {
      let filter=predicates+(completed && configuration.minimumDurationMS>0 ? ["[duration]>=(\(Int64(configuration.minimumDurationMS)*1000))"]:[])
      return "ADD EVENT sqlserver.\(name)(ACTION(\(actions)) WHERE (\(filter.joined(separator:" AND "))))"
    }
    let ddl="""
    CREATE EVENT SESSION \(identifier) ON SERVER
    \(event("sql_batch_completed",completed:true)),
    \(event("rpc_completed",completed:true)),
    \(event("error_reported",completed:false))
    ADD TARGET package0.ring_buffer(SET max_memory=512,max_events_limit=2000)
    WITH (MAX_MEMORY=2048 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=1 SECONDS,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF);
    ALTER EVENT SESSION \(identifier) ON SERVER STATE=START;
    """
    return """
    SET NOCOUNT ON;
    IF CONVERT(int,SERVERPROPERTY('EngineEdition'))=5 THROW 51000,N'Profiler sunucu kapsamlı SQL Server / Managed Instance gerektirir.',1;
    IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name=\(SQL.literal(name))) THROW 51071,N'Profiler oturum kimliği zaten kullanılıyor.',1;
    DECLARE @ddl nvarchar(max)=\(SQL.literal(ddl));
    SET @ddl=REPLACE(@ddl,N'__PROFILER_SPID__',CONVERT(nvarchar(20),@@SPID));
    EXEC sys.sp_executesql @ddl;
    """
  }
  public static func readSQL(name:String) throws -> String {
    _ = try checked(name)
    return """
    SET NOCOUNT ON;
    SELECT t.target_data AS profiler_xml,s.dropped_event_count AS dropped_events
    FROM sys.dm_xe_sessions s JOIN sys.dm_xe_session_targets t ON t.event_session_address=s.address
    WHERE s.name=\(SQL.literal(name)) AND t.target_name=N'ring_buffer';
    """
  }
  public static func dropSQL(name:String) throws -> String {
    let identifier=try checked(name)
    return """
    SET NOCOUNT ON;
    IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name=\(SQL.literal(name)))
      DROP EVENT SESSION \(identifier) ON SERVER;
    """
  }
  public struct Event:Sendable,Identifiable,Equatable,Codable {
    public let id:UInt64
    public let timestamp:String
    public let kind:String
    public let database:String
    public let application:String
    public let host:String
    public let login:String
    public let session:String
    public var clientPID:String=""
    public let durationMS:Double?
    public let cpu:String
    public let reads:String
    public let writes:String
    public let sql:String
    public let message:String
    public var retainedBytes:Int {[timestamp,kind,database,application,host,login,session,clientPID,cpu,reads,writes,sql,message].reduce(128) {$0+$1.utf8.count}}
  }
  public struct Snapshot:Sendable {
    public let events:[Event]
    public let processed:UInt64
    public let dropped:UInt64
    public let truncated:Bool
  }
  public static func decode(_ execution:Execution) throws -> Snapshot {
    guard !execution.partial,!execution.stoppedEarly,execution.results.count==1,
      let rows=execution.results.first,!rows.truncated,rows.values.count==1,
      rows.fields.map(\.name)==["profiler_xml","dropped_events"],let row=rows.values.first,row.count==2,
      let xml=row[0],!xml.contains("<!DOCTYPE"),let data=xml.data(using:.utf8),data.count<=4_194_304,
      let dropped=row[1].flatMap(UInt64.init) else {throw SQLFailure("Profiler oturumu bulunamadı veya olay verisi eksik/kısmi.")}
    let delegate=ProfilerXMLDecoder()
    let parser=XMLParser(data:data);parser.shouldResolveExternalEntities=false;parser.delegate=delegate
    guard parser.parse(),delegate.validRoot,!delegate.invalid else {throw SQLFailure("Profiler olay XML’i geçersiz veya eksik.")}
    let combined=dropped.addingReportingOverflow(delegate.dropped)
    guard !combined.overflow else {throw SQLFailure("Profiler kayıp sayacı geçersiz.")}
    return Snapshot(events:delegate.events,processed:delegate.processed,dropped:combined.partialValue,truncated:delegate.truncated)
  }
  /// Local retention is independent from the server ring. Sequence IDs prevent duplicates.
  public struct Buffer:Sendable {
    public private(set) var events:[Event]=[]
    public private(set) var lastSequence:UInt64?
    public private(set) var discarded=0
    public private(set) var possibleLoss=false
    public private(set) var serverDropped:UInt64=0
    private var bytes=0
    private var lastProcessed:UInt64=0
    public init() {}
    public mutating func append(_ snapshot:Snapshot) {
      let incoming=snapshot.events.filter {event in lastSequence.map {event.id>$0} ?? true}.sorted {$0.id<$1.id}
      let delta=snapshot.processed>=lastProcessed ? snapshot.processed-lastProcessed:0
      if delta>UInt64(incoming.count) || snapshot.truncated || snapshot.dropped>0 {possibleLoss=true}
      lastProcessed=snapshot.processed;serverDropped=max(serverDropped,snapshot.dropped)
      for event in incoming {events.append(event);bytes+=event.retainedBytes;lastSequence=max(lastSequence ?? event.id,event.id)}
      var count=0
      while events.count-count>5000 || bytes>8_388_608,count<events.count {bytes-=events[count].retainedBytes;count+=1}
      if count>0 {events.removeFirst(count);discarded+=count}
    }
    public mutating func clearDisplay() {events=[];bytes=0;discarded=0}
  }
}

private final class ProfilerXMLDecoder:NSObject,XMLParserDelegate {
  var validRoot=false,invalid=false,truncated=false
  var processed:UInt64=0,dropped:UInt64=0
  var events:[SQLProfiler.Event]=[]
  private var kind="",timestamp="",field="",value=""
  private var values:[String:String]=[:]
  private var inValue=false
  private var decodedBytes=0
  func parser(_ parser:XMLParser,didStartElement element:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
    switch element {
    case "RingBufferTarget":validRoot=true;truncated=attributes["truncated"]=="1";processed=UInt64(attributes["totalEventsProcessed"] ?? "") ?? 0;dropped=UInt64(attributes["droppedCount"] ?? "") ?? 0
    case "event":kind=attributes["name"] ?? "";timestamp=attributes["timestamp"] ?? "";values=[:]
    case "data","action":field=attributes["name"] ?? ""
    case "value":inValue=true;value=""
    default:break
    }
  }
  func parser(_ parser:XMLParser,foundCharacters string:String) {
    decodedBytes+=string.utf8.count
    guard decodedBytes<=4_194_304 else {invalid=true;parser.abortParsing();return}
    if inValue {value+=string}
  }
  func parser(_ parser:XMLParser,foundCDATA data:Data) {
    guard let text=String(data:data,encoding:.utf8) else {invalid=true;parser.abortParsing();return}
    self.parser(parser,foundCharacters:text)
  }
  func parser(_ parser:XMLParser,didEndElement element:String,namespaceURI:String?,qualifiedName:String?) {
    if element=="value" {values[field]=value;inValue=false}
    if element=="event" {
      guard events.count<2000,let sequence=values["event_sequence"].flatMap(UInt64.init),!timestamp.isEmpty,
        ["sql_batch_completed","rpc_completed","error_reported"].contains(kind) else {invalid=true;return}
      events.append(.init(id:sequence,timestamp:timestamp,kind:kind,database:values["database_name"] ?? "",application:values["client_app_name"] ?? "",host:values["client_hostname"] ?? "",login:values["server_principal_name"] ?? "",session:values["session_id"] ?? "",clientPID:values["client_pid"].flatMap(UInt32.init).flatMap {$0>0 ? String($0):nil} ?? "",durationMS:values["duration"].flatMap(UInt64.init).map {Double($0)/1000},cpu:values["cpu_time"] ?? "",reads:values["logical_reads"] ?? "",writes:values["writes"] ?? "",sql:values["batch_text"] ?? values["statement"] ?? values["sql_text"] ?? "",message:values["message"] ?? ""))
    }
  }
}
