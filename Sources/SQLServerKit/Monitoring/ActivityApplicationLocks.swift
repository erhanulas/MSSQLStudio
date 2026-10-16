import Foundation

/// APPLICATION resources include granted locks held by idle sessions, not only waiting SQL.
public enum ActivityApplicationLocks {
  public struct Lock:Identifiable,Sendable,Equatable {
    public let id:[String]
    public var sessionLoginTime:String?=nil
    public var databaseID:Int?=nil
    public let sessionID:Int64
    public let requestID:Int64?
    public let database,resource,mode,status,ownerType,ownerID,login,host,program,sqlSource,sql:String
  }
  public struct Snapshot:Sendable {
    public let locks:[Lock]
    public let issues:[String]
  }
  private static let columns=["lock_id","session_id","request_id","database_name","resource","mode","status","owner_type","owner_id","login_name","host_name","program_name","sql_source","sql_text"]
  public static let sql="""
  SET NOCOUNT ON;
  \(ActivityMonitoring.permissionSQL)
  DECLARE @issues TABLE(metric nvarchar(40),message nvarchar(4000));
  DECLARE @locks TABLE(lock_id varchar(64),session_id int,request_id int,database_name nvarchar(128),resource nvarchar(256),mode nvarchar(60),status nvarchar(60),owner_type nvarchar(60),owner_id bigint,login_name nvarchar(128),host_name nvarchar(128),program_name nvarchar(128),sql_source nvarchar(20),sql_text nvarchar(4000),session_login_time varchar(23),database_id int);
  BEGIN TRY
    IF @canMonitor=0 THROW 51000,@permissionMessage,1;
    INSERT @locks
    SELECT CONVERT(varchar(34),l.lock_owner_address,1)+N':' + CONVERT(varchar(12),l.resource_lock_partition),l.request_session_id,l.request_request_id,DB_NAME(l.resource_database_id),l.resource_description,l.request_mode,l.request_status,l.request_owner_type,l.request_owner_id,s.login_name,s.host_name,s.program_name,
      CASE WHEN r.request_id IS NOT NULL THEN N'current' WHEN t.text IS NOT NULL THEN N'recent' ELSE N'unavailable' END,LEFT(t.text COLLATE Latin1_General_100_CI_AS_SC,2000),CONVERT(varchar(23),s.login_time,121),l.resource_database_id
    FROM (SELECT TOP(101) * FROM sys.dm_tran_locks WHERE resource_type=N'APPLICATION' AND request_session_id<>@@SPID
      ORDER BY CASE WHEN request_status=N'GRANTED' THEN 1 ELSE 0 END,request_session_id,resource_database_id,resource_description,request_owner_id,lock_owner_address) l
    LEFT JOIN sys.dm_exec_sessions s ON s.session_id=l.request_session_id
    LEFT JOIN sys.dm_exec_requests r ON r.session_id=l.request_session_id AND r.request_id=l.request_request_id
    OUTER APPLY(SELECT TOP(1) c.most_recent_sql_handle FROM sys.dm_exec_connections c WHERE c.session_id=l.request_session_id AND r.request_id IS NULL ORDER BY c.connect_time DESC,c.connection_id) c
    OUTER APPLY sys.dm_exec_sql_text(CASE WHEN r.request_id IS NOT NULL THEN r.sql_handle ELSE c.most_recent_sql_handle END) t;
    IF (SELECT COUNT(*) FROM @locks)>100 INSERT @issues VALUES(N'Uygulama kilitleri',N'İlk 100 application lock gösteriliyor; devamı okunmadı.');
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Uygulama kilitleri',ERROR_MESSAGE()); END CATCH;
  SELECT TOP(100) lock_id,session_id,request_id,database_name,resource,mode,status,owner_type,CONVERT(varchar(30),owner_id) AS owner_id,login_name,host_name,program_name,sql_source,sql_text,session_login_time,database_id FROM @locks
    ORDER BY CASE WHEN status=N'GRANTED' THEN 1 ELSE 0 END,session_id,database_name,resource,owner_id,lock_id;
  SELECT metric,message FROM @issues;
  """
  public static func decode(_ execution:Execution) throws -> Snapshot {
    guard !execution.partial,!execution.stoppedEarly,execution.results.count==2,
      !execution.results.contains(where:{$0.truncated}),execution.results[0].values.count<=100,
      execution.results[1].values.count<=30 else {throw SQLFailure("Uygulama kilitleri sonucu eksik veya sınırı aşıyor.")}
    let rows=execution.results[0],issues=execution.results[1]
    let hasIdentity=rows.values.first?.count==16 || rows.fields.count==16
    let expected=hasIdentity ? columns+["session_login_time","database_id"]:columns
    guard (rows.fields.isEmpty || rows.fields.map(\.name)==expected),
      rows.values.allSatisfy({$0.count==expected.count}),
      (issues.fields.isEmpty || issues.fields.map(\.name)==["metric","message"]),issues.values.allSatisfy({$0.count==2}) else {throw SQLFailure("Uygulama kilitleri sonuç şeması geçersiz.")}
    var ids=Set<[String]>()
    let locks=try rows.values.map {row -> Lock in
      guard let address=row[0],!address.isEmpty,let session=row[1].flatMap(Int64.init),session != 0,
        row[2]==nil || row[2].flatMap(Int64.init).map({$0>=0})==true,
        let source=row[12],["current","recent","unavailable"].contains(source) else {throw SQLFailure("Uygulama kilidi kimliği geçersiz.")}
      let id=Array(row.prefix(9)).map {$0 ?? ""}
      guard ids.insert(id).inserted else {throw SQLFailure("Uygulama kilidi kimliği yinelendi.")}
      return Lock(id:id,sessionLoginTime:hasIdentity ? row[14]:nil,databaseID:hasIdentity ? row[15].flatMap(Int.init):nil,sessionID:session,requestID:row[2].flatMap(Int64.init),database:row[3] ?? "",resource:row[4] ?? "",mode:row[5] ?? "",status:row[6] ?? "",ownerType:row[7] ?? "",ownerID:row[8] ?? "",login:row[9] ?? "",host:row[10] ?? "",program:row[11] ?? "",sqlSource:source,sql:String((row[13] ?? "").prefix(2000)))
    }
    return Snapshot(locks:locks,issues:issues.values.map {$0.compactMap {$0}.joined(separator:": ")})
  }
}
