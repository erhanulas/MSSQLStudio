import Foundation

public enum ActivityMonitoring {
  // Independent TRY/CATCH blocks keep one unavailable DMV from hiding the other metrics.
  public static let overviewSQL = """
  SET NOCOUNT ON;
  DECLARE @cpu int,@waiting bigint,@bytes decimal(38,0),@batches bigint,@started nvarchar(40);
  DECLARE @issues TABLE(metric nvarchar(40),message nvarchar(4000));
  BEGIN TRY
    SELECT @started=CONVERT(nvarchar(40),sqlserver_start_time,126) FROM sys.dm_os_sys_info;
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Örnekleme',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY
    SELECT TOP(1) @cpu=CONVERT(xml,record).value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int')
    FROM sys.dm_os_ring_buffers WHERE ring_buffer_type=N'RING_BUFFER_SCHEDULER_MONITOR' AND record LIKE N'%<SystemHealth>%' ORDER BY timestamp DESC;
    IF @cpu IS NULL INSERT @issues VALUES(N'CPU',N'Sunucu CPU örneği sağlamadı.');
  END TRY BEGIN CATCH INSERT @issues VALUES(N'CPU',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY SELECT @waiting=COUNT_BIG(*) FROM sys.dm_os_waiting_tasks w JOIN sys.dm_exec_sessions s ON s.session_id=w.session_id WHERE s.is_user_process=1 AND w.session_id<>@@SPID;
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Bekleyen görevler',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY SELECT @bytes=SUM(CONVERT(decimal(38,0),num_of_bytes_read)+CONVERT(decimal(38,0),num_of_bytes_written)) FROM sys.dm_io_virtual_file_stats(NULL,NULL);
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Veritabanı I/O',ERROR_MESSAGE()); END CATCH;
  BEGIN TRY
    SELECT @batches=cntr_value FROM sys.dm_os_performance_counters WHERE object_name LIKE N'%:SQL Statistics' AND counter_name=N'Batch Requests/sec' AND instance_name=N'' AND cntr_type IN (272696320,272696576);
    IF @batches IS NULL INSERT @issues VALUES(N'Batch hızı',N'Sunucu batch sayacı sağlamadı.');
  END TRY BEGIN CATCH INSERT @issues VALUES(N'Batch hızı',ERROR_MESSAGE()); END CATCH;
  SELECT CONVERT(nvarchar(40),SYSUTCDATETIME(),126)+N'Z' AS sampled_at,@started AS started_at,@cpu AS cpu_percent,@waiting AS waiting_tasks,@bytes AS io_bytes,@batches AS batch_requests;
  SELECT metric,message FROM @issues;
  """
  public struct Snapshot: Sendable {
    public var time:Date
    public var started:String?
    public var cpu:Double?
    public var waiting:Int64?
    public var bytes:Int64?
    public var batches:Int64?
    public var issues:[String]
    public init(time:Date,started:String?,cpu:Double?,waiting:Int64?,bytes:Int64?,batches:Int64?,issues:[String]=[]) {
      self.time=time;self.started=started;self.cpu=cpu;self.waiting=waiting;self.bytes=bytes;self.batches=batches;self.issues=issues
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
  }
  public static func decode(_ execution:Execution) throws -> Snapshot {
    guard !execution.partial,let row=execution.results.first?.values.first,row.count>=6,let timeText=row[0] else {throw SQLFailure("Activity Monitor örneği eksik veya kısmi.")}
    let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
    guard let time=formatter.date(from:timeText) ?? ISO8601DateFormatter().date(from:timeText) else {throw SQLFailure("Activity Monitor örnek zamanı geçersiz.")}
    let cpu=row[2].flatMap(Double.init).flatMap { (0...100).contains($0) ? $0:nil }
    func counter(_ index:Int) -> Int64? {row[index].flatMap(Int64.init).flatMap {$0>=0 ? $0:nil}}
    let issues=execution.results.dropFirst().flatMap {Array($0.values)}.map {$0.compactMap {$0}.joined(separator:": ")}
    return Snapshot(time:time,started:row[1],cpu:cpu,waiting:counter(3),bytes:counter(4),batches:counter(5),issues:issues)
  }
  public static func sample(_ current:Snapshot,previous:Snapshot?) -> Sample {
    func rate(_ value:Int64?,_ old:Int64?) -> Double? {
      guard let previous,let value,let old,value>=old,current.started != nil,current.started == previous.started else {return nil}
      let seconds=current.time.timeIntervalSince(previous.time)
      guard seconds>0,seconds<=180 else {return nil}
      return Double(value-old)/seconds
    }
    return Sample(time:current.time,beginsSequence:previous == nil || previous?.started != current.started,cpu:current.cpu,waiting:current.waiting.map(Double.init),megabytesPerSecond:rate(current.bytes,previous?.bytes).map {$0/1_048_576},batchesPerSecond:rate(current.batches,previous?.batches))
  }
}
