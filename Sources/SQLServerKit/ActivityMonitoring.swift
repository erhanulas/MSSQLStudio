import Foundation

public enum ActivityMonitoring {
  // DMV visibility can silently be restricted to the caller. Check server scope
  // before counting; an unavailable measurement must never look like zero.
  private static let permissionSQL = """
  DECLARE @monitorPermission nvarchar(128)=CASE WHEN TRY_CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))>=16 THEN N'VIEW SERVER PERFORMANCE STATE' ELSE N'VIEW SERVER STATE' END;
  DECLARE @canMonitor bit=CASE WHEN HAS_PERMS_BY_NAME(NULL,NULL,@monitorPermission)=1 THEN 1 ELSE 0 END;
  DECLARE @permissionMessage nvarchar(2048)=@monitorPermission+N' izni gerekli; yalnız mevcut oturumun görünmesi sunucu ölçümü sayılmaz.';
  """
  private static let requestPredicate = """
  s.is_user_process=1 AND r.session_id<>@@SPID
    AND ISNULL(r.wait_type,N'') NOT IN (N'BROKER_RECEIVE_WAITFOR',N'TRACEWRITE',N'SP_SERVER_DIAGNOSTICS_SLEEP',N'WAITFOR')
  """
  // Each unavailable DMV leaves only its own measurements NULL.
  public static let overviewSQL = """
  SET NOCOUNT ON;
  \(permissionSQL)
  DECLARE @cpu int,@waiting bigint,@bytes decimal(38,0),@batches bigint,@started nvarchar(40),@processCPU decimal(38,0),@cpuCount int;
  DECLARE @active bigint,@blocked bigint,@backups bigint,@transactions bigint,@idle bigint,@sessions bigint,@grants bigint;
  DECLARE @sqlMemory decimal(28,3),@availableMemory decimal(28,3),@reads decimal(38,0),@writes decimal(38,0),@readStall decimal(38,0),@writeStall decimal(38,0);
  DECLARE @issues TABLE(metric nvarchar(40),message nvarchar(4000));
  BEGIN TRY
    SELECT @started=CONVERT(nvarchar(40),sqlserver_start_time,126),@processCPU=CONVERT(decimal(38,0),process_kernel_time_ms)+CONVERT(decimal(38,0),process_user_time_ms),@cpuCount=cpu_count FROM sys.dm_os_sys_info;
    IF @started IS NULL OR @processCPU IS NULL OR @cpuCount IS NULL INSERT @issues VALUES(N'CPU / örnekleme',N'Sunucu CPU sayacı veya başlangıç kimliği sağlamadı.');
  END TRY BEGIN CATCH INSERT @issues VALUES(N'CPU / örnekleme',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY
    IF @canMonitor=0 THROW 51000,@permissionMessage,1;
    SELECT @waiting=COUNT_BIG(*) FROM sys.dm_os_waiting_tasks w JOIN sys.dm_exec_sessions s ON s.session_id=w.session_id WHERE s.is_user_process=1 AND w.session_id<>@@SPID;
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Bekleyen görevler',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY
    SELECT @bytes=SUM(CONVERT(decimal(38,0),num_of_bytes_read)+CONVERT(decimal(38,0),num_of_bytes_written)),@reads=SUM(CONVERT(decimal(38,0),num_of_reads)),@writes=SUM(CONVERT(decimal(38,0),num_of_writes)),@readStall=SUM(CONVERT(decimal(38,0),io_stall_read_ms)),@writeStall=SUM(CONVERT(decimal(38,0),io_stall_write_ms)) FROM sys.dm_io_virtual_file_stats(NULL,NULL);
    IF @bytes IS NULL INSERT @issues VALUES(N'Veritabanı I/O',N'Sunucu dosya I/O sayacı sağlamadı.');
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Veritabanı I/O',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY
    SELECT @batches=cntr_value FROM sys.dm_os_performance_counters WHERE object_name LIKE N'%:SQL Statistics' AND counter_name=N'Batch Requests/sec' AND instance_name=N'' AND cntr_type IN (272696320,272696576);
    IF @batches IS NULL INSERT @issues VALUES(N'Batch hızı',N'Sunucu batch sayacı sağlamadı.');
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Batch hızı',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY
    IF @canMonitor=0 THROW 51000,@permissionMessage,1;
    SELECT @active=COALESCE(SUM(CONVERT(bigint,CASE WHEN r.command NOT IN (N'BACKUP DATABASE',N'BACKUP LOG') THEN 1 ELSE 0 END)),0),@blocked=COALESCE(SUM(CONVERT(bigint,CASE WHEN r.blocking_session_id>0 THEN 1 ELSE 0 END)),0),@backups=COALESCE(SUM(CONVERT(bigint,CASE WHEN r.command IN (N'BACKUP DATABASE',N'BACKUP LOG') THEN 1 ELSE 0 END)),0)
    FROM sys.dm_exec_requests r JOIN sys.dm_exec_sessions s ON s.session_id=r.session_id WHERE \(requestPredicate);
  END TRY BEGIN CATCH INSERT @issues VALUES(N'İstekler / bloklama / yedekleme',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY
    IF @canMonitor=0 THROW 51000,@permissionMessage,1;
    SELECT @sessions=COUNT_BIG(*),@transactions=COALESCE(SUM(CONVERT(bigint,s.open_transaction_count)),0),@idle=COALESCE(SUM(CONVERT(bigint,CASE WHEN s.status=N'sleeping' THEN s.open_transaction_count ELSE 0 END)),0)
    FROM sys.dm_exec_sessions s WHERE s.is_user_process=1 AND s.session_id<>@@SPID;
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Oturumlar / açık transaction',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY
    SELECT @sqlMemory=CONVERT(decimal(28,3),physical_memory_in_use_kb)/1024.0 FROM sys.dm_os_process_memory;
    IF @sqlMemory IS NULL INSERT @issues VALUES(N'SQL Server belleği',N'Sunucu işlem belleği sağlamadı.');
  END TRY BEGIN CATCH INSERT @issues VALUES(N'SQL Server belleği',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY
    SELECT @availableMemory=CONVERT(decimal(28,3),available_physical_memory_kb)/1024.0 FROM sys.dm_os_sys_memory;
    IF @availableMemory IS NULL INSERT @issues VALUES(N'Kullanılabilir sunucu belleği',N'Sunucu kullanılabilir fiziksel belleği sağlamadı.');
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Kullanılabilir sunucu belleği',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY
    IF @canMonitor=0 THROW 51000,@permissionMessage,1;
    SELECT @grants=COUNT_BIG(*) FROM sys.dm_exec_query_memory_grants WHERE grant_time IS NULL AND session_id<>@@SPID;
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Bellek bekleyen istekler',ERROR_MESSAGE()); END CATCH;
  SELECT CONVERT(nvarchar(40),SYSUTCDATETIME(),126)+N'Z' AS sampled_at,@started AS started_at,@cpu AS cpu_percent,@waiting AS waiting_tasks,@bytes AS io_bytes,@batches AS batch_requests,
    @active AS active_requests,@blocked AS blocked_requests,@backups AS backup_requests,@transactions AS open_transactions,@idle AS idle_transactions,@sessions AS user_sessions,@sqlMemory AS sql_memory_mb,@availableMemory AS available_memory_mb,@grants AS memory_grants_pending,
    @reads AS io_reads,@writes AS io_writes,@readStall AS read_stall_ms,@writeStall AS write_stall_ms,@processCPU AS process_cpu_ms,@cpuCount AS logical_cpu_count;
  SELECT metric,message FROM @issues;
  """

  // Fetch text only after TOP(30), and retain at most 2,000 characters of the
  // current statement. No query plans, temporary tables, or server writes.
  public static let diagnosticsSQL = """
  SET NOCOUNT ON;
  \(permissionSQL)
  DECLARE @issues TABLE(metric nvarchar(40),message nvarchar(4000));
  DECLARE @requests TABLE(category tinyint,session_id int,request_id int,database_name nvarchar(128),status nvarchar(60),command nvarchar(60),elapsed_ms bigint,cpu_ms bigint,reads bigint,writes bigint,blocker int,wait_type nvarchar(60),open_transactions bigint,percent_complete real,remaining_ms bigint,sql_text nvarchar(4000));
  \(diagnosticSection(category:0,title:"Bloklanan istekler",condition:"r.blocking_session_id>0",order:"r.wait_time DESC,r.total_elapsed_time DESC,r.session_id,r.request_id"))
  \(diagnosticSection(category:1,title:"Uzun süren istekler",condition:"r.total_elapsed_time>=30000 AND r.command NOT IN (N'BACKUP DATABASE',N'BACKUP LOG')",order:"r.total_elapsed_time DESC,r.session_id,r.request_id"))
  \(diagnosticSection(category:2,title:"Yedeklemeler",condition:"r.command IN (N'BACKUP DATABASE',N'BACKUP LOG')",order:"r.total_elapsed_time DESC,r.session_id,r.request_id"))
  SELECT session_id,request_id,database_name,status,command,elapsed_ms,cpu_ms,reads,writes,blocker,wait_type,open_transactions,percent_complete,remaining_ms,sql_text FROM @requests WHERE category=0 ORDER BY elapsed_ms DESC,session_id,request_id;
  SELECT session_id,request_id,database_name,status,command,elapsed_ms,cpu_ms,reads,writes,blocker,wait_type,open_transactions,percent_complete,remaining_ms,sql_text FROM @requests WHERE category=1 ORDER BY elapsed_ms DESC,session_id,request_id;
  SELECT session_id,request_id,database_name,status,command,elapsed_ms,cpu_ms,reads,writes,blocker,wait_type,open_transactions,percent_complete,remaining_ms,sql_text FROM @requests WHERE category=2 ORDER BY elapsed_ms DESC,session_id,request_id;
  SELECT metric,message FROM @issues;
  """
  private static func diagnosticSection(category:Int,title:String,condition:String,order:String) -> String {
    """
    BEGIN TRY
      IF @canMonitor=0 THROW 51000,@permissionMessage,1;
      INSERT @requests
      SELECT \(category),r.session_id,r.request_id,DB_NAME(r.database_id),r.status,r.command,CONVERT(bigint,r.total_elapsed_time),CONVERT(bigint,r.cpu_time),r.reads,r.writes,CASE WHEN r.blocking_session_id>0 THEN r.blocking_session_id ELSE NULL END,ISNULL(r.wait_type,N''),CONVERT(bigint,r.open_transaction_count),CASE WHEN r.command IN (N'BACKUP DATABASE',N'BACKUP LOG') THEN r.percent_complete ELSE NULL END,CONVERT(bigint,NULL),LEFT(CONVERT(nvarchar(max),SUBSTRING(CONVERT(varbinary(max),t.text),r.statement_start_offset+1,CASE WHEN r.statement_end_offset=-1 OR r.statement_end_offset-r.statement_start_offset>=7998 THEN 8000 ELSE r.statement_end_offset-r.statement_start_offset+2 END)) COLLATE Latin1_General_100_CI_AS_SC,2000)
      FROM (SELECT TOP(30) r.* FROM sys.dm_exec_requests r JOIN sys.dm_exec_sessions s ON s.session_id=r.session_id WHERE \(requestPredicate) AND \(condition) ORDER BY \(order)) r
      OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t;
    END TRY BEGIN CATCH INSERT @issues VALUES(N'\(title)',ERROR_MESSAGE()); END CATCH;
    """
  }

  public struct Health: Sendable, Equatable {
    public var activeRequests,blockedRequests,backupRequests,openTransactions,idleTransactions,userSessions:Int64?
    public var sqlMemoryMB,availableMemoryMB:Double?
    public var memoryGrantsPending:Int64?
    public init(activeRequests:Int64?=nil,blockedRequests:Int64?=nil,backupRequests:Int64?=nil,openTransactions:Int64?=nil,idleTransactions:Int64?=nil,userSessions:Int64?=nil,sqlMemoryMB:Double?=nil,availableMemoryMB:Double?=nil,memoryGrantsPending:Int64?=nil) {
      self.activeRequests=activeRequests;self.blockedRequests=blockedRequests;self.backupRequests=backupRequests;self.openTransactions=openTransactions;self.idleTransactions=idleTransactions;self.userSessions=userSessions;self.sqlMemoryMB=sqlMemoryMB;self.availableMemoryMB=availableMemoryMB;self.memoryGrantsPending=memoryGrantsPending
    }
  }
  public struct Snapshot: Sendable {
    public var time:Date
    public var started:String?
    public var cpu:Double?
    public var waiting:Int64?
    public var bytes:Int64?
    public var batches:Int64?
    public var issues:[String]
    public var health:Health
    public var reads,writes,readStallMS,writeStallMS,processCPUMS,logicalCPUCount:Int64?
    public init(time:Date,started:String?,cpu:Double?,waiting:Int64?,bytes:Int64?,batches:Int64?,issues:[String]=[],health:Health = .init(),reads:Int64?=nil,writes:Int64?=nil,readStallMS:Int64?=nil,writeStallMS:Int64?=nil,processCPUMS:Int64?=nil,logicalCPUCount:Int64?=nil) {
      self.time=time;self.started=started;self.cpu=cpu;self.waiting=waiting;self.bytes=bytes;self.batches=batches;self.issues=issues;self.health=health;self.reads=reads;self.writes=writes;self.readStallMS=readStallMS;self.writeStallMS=writeStallMS;self.processCPUMS=processCPUMS;self.logicalCPUCount=logicalCPUCount
    }
  }
  public struct Sample: Identifiable, Sendable {
    public var id:Date {time}
    public var time:Date
    public var beginsSequence:Bool
    public var cpu:Double?
    public var waiting:Double?
    public var megabytesPerSecond:Double?
    public var batchesPerSecond:Double?
    public var health:Health
    public var readLatencyMS,writeLatencyMS:Double?
    public init(time:Date,beginsSequence:Bool,cpu:Double?,waiting:Double?,megabytesPerSecond:Double?,batchesPerSecond:Double?,health:Health = .init(),readLatencyMS:Double?=nil,writeLatencyMS:Double?=nil) {
      self.time=time;self.beginsSequence=beginsSequence;self.cpu=cpu;self.waiting=waiting;self.megabytesPerSecond=megabytesPerSecond;self.batchesPerSecond=batchesPerSecond;self.health=health;self.readLatencyMS=readLatencyMS;self.writeLatencyMS=writeLatencyMS
    }
  }
  public struct Request: Identifiable, Sendable, Equatable {
    public var id:String {"\(sessionID):\(requestID)"}
    public var sessionID,requestID:Int64
    public var database,status,command,wait,sql:String
    public var elapsedMS,cpuMS,reads,writes,blocker,openTransactions,remainingMS:Int64?
    public var percentComplete:Double?
    public init(sessionID:Int64,requestID:Int64,database:String="",status:String="",command:String="",elapsedMS:Int64?=nil,cpuMS:Int64?=nil,reads:Int64?=nil,writes:Int64?=nil,blocker:Int64?=nil,wait:String="",openTransactions:Int64?=nil,percentComplete:Double?=nil,remainingMS:Int64?=nil,sql:String="") {
      self.sessionID=sessionID;self.requestID=requestID;self.database=database;self.status=status;self.command=command;self.elapsedMS=elapsedMS;self.cpuMS=cpuMS;self.reads=reads;self.writes=writes;self.blocker=blocker;self.wait=wait;self.openTransactions=openTransactions;self.percentComplete=percentComplete;self.remainingMS=remainingMS;self.sql=sql
    }
  }
  public struct Diagnostics: Sendable, Equatable {
    public var blocked,longRunning,backups:[Request]
    public var issues:[String]
    public init(blocked:[Request]=[],longRunning:[Request]=[],backups:[Request]=[],issues:[String]=[]) {self.blocked=blocked;self.longRunning=longRunning;self.backups=backups;self.issues=issues}
  }

  private static let overviewColumns=["sampled_at","started_at","cpu_percent","waiting_tasks","io_bytes","batch_requests","active_requests","blocked_requests","backup_requests","open_transactions","idle_transactions","user_sessions","sql_memory_mb","available_memory_mb","memory_grants_pending","io_reads","io_writes","read_stall_ms","write_stall_ms","process_cpu_ms","logical_cpu_count"]
  private static let requestColumns=["session_id","request_id","database_name","status","command","elapsed_ms","cpu_ms","reads","writes","blocker","wait_type","open_transactions","percent_complete","remaining_ms","sql_text"]
  private static func validate(_ execution:Execution) throws {
    guard !execution.partial,!execution.stoppedEarly,!execution.results.contains(where:{$0.truncated}) else {throw SQLFailure("Activity Monitor sonucu eksik veya kısmi; güncel ölçüm olarak kullanılmadı.")}
  }
  private static func schema(_ rows:Rows,_ expected:[String]) throws {
    guard rows.fields.isEmpty || rows.fields.map({$0.name.lowercased()}) == expected,rows.values.allSatisfy({$0.count == expected.count}) else {throw SQLFailure("Activity Monitor sonuç şeması beklenen alanlarla eşleşmiyor.")}
  }
  private static func issues(_ rows:Rows) throws -> [String] {
    try schema(rows,["metric","message"])
    guard rows.values.count<=30 else {throw SQLFailure("Activity Monitor tanı sonucu sınırı aşıldı.")}
    return rows.values.map {$0.compactMap {$0}.joined(separator:": ")}.filter {!$0.isEmpty}
  }
  private static func counter(_ text:String?) -> Int64? {text.flatMap(Int64.init).flatMap {$0>=0 ? $0:nil}}
  private static func measurement(_ text:String?) -> Double? {text.flatMap(Double.init).flatMap {$0.isFinite && $0>=0 ? $0:nil}}
  private static func percentage(_ text:String?) -> Double? {measurement(text).flatMap {$0<=100 ? $0:nil}}
  public static func decode(_ execution:Execution) throws -> Snapshot {
    try validate(execution)
    guard let rows=execution.results.first,rows.values.count == 1,let row=rows.values.first,(row.count == 6 || row.count == overviewColumns.count),let timeText=row[0],execution.results.count == 2 || (row.count == 6 && execution.results.count == 1) else {throw SQLFailure("Activity Monitor örneği eksik veya kısmi.")}
    try schema(rows,Array(overviewColumns.prefix(row.count)))
    let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
    guard let time=formatter.date(from:timeText) ?? ISO8601DateFormatter().date(from:timeText) else {throw SQLFailure("Activity Monitor örnek zamanı geçersiz.")}
    let messages=try execution.results.dropFirst().flatMap {try issues($0)}
    var result=Snapshot(time:time,started:row[1]?.isEmpty == false ? row[1]:nil,cpu:percentage(row[2]),waiting:counter(row[3]),bytes:counter(row[4]),batches:counter(row[5]),issues:messages)
    if row.count == overviewColumns.count {
      result.health = .init(activeRequests:counter(row[6]),blockedRequests:counter(row[7]),backupRequests:counter(row[8]),openTransactions:counter(row[9]),idleTransactions:counter(row[10]),userSessions:counter(row[11]),sqlMemoryMB:measurement(row[12]),availableMemoryMB:measurement(row[13]),memoryGrantsPending:counter(row[14]))
      result.reads=counter(row[15]);result.writes=counter(row[16]);result.readStallMS=counter(row[17]);result.writeStallMS=counter(row[18]);result.processCPUMS=counter(row[19]);result.logicalCPUCount=counter(row[20]).flatMap {$0>0 ? $0:nil}
    }
    return result
  }
  public static func decodeDiagnostics(_ execution:Execution) throws -> Diagnostics {
    try validate(execution)
    guard execution.results.count == 4 else {throw SQLFailure("Activity Monitor DBA sonucu eksik; üç istek listesi ve tanı sonucu gerekli.")}
    func requests(_ rows:Rows) throws -> [Request] {
      try schema(rows,requestColumns)
      guard rows.values.count<=30 else {throw SQLFailure("Activity Monitor DBA istek listesi sınırı aşıldı.")}
      var ids=Set<String>()
      return try rows.values.map {row in
        guard let sessionID=counter(row[0]),sessionID>0,let requestID=counter(row[1]) else {throw SQLFailure("Activity Monitor DBA istek kimliği geçersiz.")}
        let request=Request(sessionID:sessionID,requestID:requestID,database:row[2] ?? "",status:row[3] ?? "",command:row[4] ?? "",elapsedMS:counter(row[5]),cpuMS:counter(row[6]),reads:counter(row[7]),writes:counter(row[8]),blocker:counter(row[9]).flatMap {$0>0 ? $0:nil},wait:row[10] ?? "",openTransactions:counter(row[11]),percentComplete:percentage(row[12]),remainingMS:counter(row[13]),sql:String((row[14] ?? "").prefix(2000)))
        guard ids.insert(request.id).inserted else {throw SQLFailure("Activity Monitor DBA istek kimliği yinelendi.")}
        return request
      }
    }
    return try Diagnostics(blocked:requests(execution.results[0]),longRunning:requests(execution.results[1]),backups:requests(execution.results[2]),issues:issues(execution.results[3]))
  }
  public static func sample(_ current:Snapshot,previous:Snapshot?) -> Sample {
    let seconds=previous.map {current.time.timeIntervalSince($0.time)}
    let continuous=previous != nil && current.started == previous?.started && seconds.map {$0>0 && $0<=180} == true
    func delta(_ value:Int64?,_ old:Int64?) -> Int64? {guard continuous,current.started != nil,let value,let old,value>=0,old>=0,value>=old else {return nil};return value-old}
    func rate(_ value:Int64?,_ old:Int64?) -> Double? {guard let change=delta(value,old),let seconds else {return nil};return Double(change)/seconds}
    func latency(_ stall:Int64?,_ oldStall:Int64?,_ count:Int64?,_ oldCount:Int64?) -> Double? {
      guard let duration=delta(stall,oldStall),let operations=delta(count,oldCount),operations>0 else {return nil};return Double(duration)/Double(operations)
    }
    let cpu:Double?
    if current.processCPUMS != nil || current.logicalCPUCount != nil {
      if let elapsed=delta(current.processCPUMS,previous?.processCPUMS),let cpus=current.logicalCPUCount,cpus>0,cpus == previous?.logicalCPUCount,let seconds {cpu=min(100,Double(elapsed)/(seconds*1000*Double(cpus))*100)} else {cpu=nil}
    } else {cpu=current.cpu.flatMap {$0.isFinite && (0...100).contains($0) ? $0:nil}}
    return Sample(time:current.time,beginsSequence:!continuous,cpu:cpu,waiting:current.waiting.map(Double.init),megabytesPerSecond:rate(current.bytes,previous?.bytes).map {$0/1_048_576},batchesPerSecond:rate(current.batches,previous?.batches),health:current.health,readLatencyMS:latency(current.readStallMS,previous?.readStallMS,current.reads,previous?.reads),writeLatencyMS:latency(current.writeStallMS,previous?.writeStallMS,current.writes,previous?.writes))
  }
}
