import Foundation

public enum SQLAgent {
  public enum Action: String, CaseIterable, Sendable {case start,stop,enable,disable,delete}
  public struct Job: Identifiable, Sendable {
    public let id:String
    public let name:String
    public let enabled:Bool
    public let description:String
    public let owner:String
    public let state:String
    public let modified:String
  }
  public struct Step: Identifiable, Sendable {
    public let id:Int
    public let name:String
    public let subsystem:String
    public let database:String
    public let command:String
  }
  public struct Schedule: Identifiable, Sendable {
    public let id:Int
    public let name:String
    public let enabled:Bool
    public let frequency:String
    public let time:String
  }
  public struct History:Identifiable,Sendable {
    public let id:Int
    public let job:String
    public let step:Int
    public let stepName:String
    public let status:Int
    public let started:String
    public let duration:String
    public let message:String
    public var statusLabel:String {switch status {case 0:"Failed";case 1:"Succeeded";case 2:"Retry";case 3:"Canceled";case 4:"In Progress";default:"Unknown"}}
  }
  public static func jobs(name:String?=nil) -> String {
    """
    /* StudioAgent.jobs */
    SELECT TOP (1000) CONVERT(nvarchar(36),j.job_id),j.name,j.enabled,j.description,COALESCE(SUSER_SNAME(j.owner_sid),N''),
    CASE WHEN a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL THEN N'Running' ELSE N'Idle' END,
    CONVERT(nvarchar(30),j.date_modified,126)
    FROM msdb.dbo.sysjobs j OUTER APPLY (SELECT TOP (1) start_execution_date,stop_execution_date FROM msdb.dbo.sysjobactivity WHERE job_id=j.job_id AND session_id=(SELECT MAX(session_id) FROM msdb.dbo.syssessions)) a
    \(name.map {"WHERE j.name="+SQL.literal($0)} ?? "") ORDER BY j.name;
    """
  }
  public static func details(name:String) -> String {
    jobs(name:name)+"\n/* StudioAgent.details */\nSELECT s.step_id,s.step_name,s.subsystem,COALESCE(s.database_name,N'master'),s.command FROM msdb.dbo.sysjobsteps s JOIN msdb.dbo.sysjobs j ON j.job_id=s.job_id WHERE j.name=\(SQL.literal(name)) ORDER BY s.step_id;\nSELECT s.schedule_id,s.name,s.enabled,CONVERT(nvarchar(20),s.freq_type),RIGHT('000000'+CONVERT(varchar(6),s.active_start_time),6) FROM msdb.dbo.sysschedules s JOIN msdb.dbo.sysjobschedules js ON js.schedule_id=s.schedule_id JOIN msdb.dbo.sysjobs j ON j.job_id=js.job_id WHERE j.name=\(SQL.literal(name)) ORDER BY s.name;"
  }
  public static func history(name:String?=nil,status:Int?=nil,days:Int=30,includeSteps:Bool=false) -> String {
    let statusFilter=status.flatMap {(0...4).contains($0) ? " AND h.run_status=\($0)":nil} ?? ""
    return """
    /* StudioAgent.history */
    SELECT TOP (500) h.instance_id,j.name,h.step_id,h.step_name,h.run_status,
      CONVERT(nvarchar(10),CONVERT(date,CONVERT(char(8),NULLIF(h.run_date,0))),120)+N' '+STUFF(STUFF(RIGHT('000000'+CONVERT(varchar(6),h.run_time),6),3,0,':'),6,0,':'),
      CONVERT(varchar(12),h.run_duration/10000)+':'+RIGHT('00'+CONVERT(varchar(2),(h.run_duration/100)%100),2)+':'+RIGHT('00'+CONVERT(varchar(2),h.run_duration%100),2),h.message
    FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id=h.job_id
    WHERE h.run_date>=CONVERT(int,CONVERT(char(8),DATEADD(day,-\(max(1,min(3650,days))),GETDATE()),112))
    \(name.map {" AND j.name="+SQL.literal($0)} ?? "") \(includeSteps ? "":" AND h.step_id=0") \(statusFilter)
    ORDER BY h.instance_id DESC;
    """
  }
  public static let serviceStatus="SELECT servicename,status_desc,startup_type_desc,last_startup_time FROM sys.dm_server_services WHERE servicename LIKE N'SQL Server Agent%';"
  private static func jobID(_ id:String) throws -> String {
    guard let uuid=UUID(uuidString:id) else {throw SQLFailure("Geçerli Job ID gerekli.")}
    return SQL.literal(uuid.uuidString)
  }
  public static func command(_ action:Action,id:String) throws -> String {
    let id=try jobID(id)
    switch action {
    case .start:return "EXEC msdb.dbo.sp_start_job @job_id=\(id);"
    case .stop:return "EXEC msdb.dbo.sp_stop_job @job_id=\(id);"
    case .enable,.disable:return "EXEC msdb.dbo.sp_update_job @job_id=\(id), @enabled=\(action == .enable ? 1:0);"
    case .delete:return "EXEC msdb.dbo.sp_delete_job @job_id=\(id), @delete_unused_schedule=0;"
    }
  }
  public static func update(_ job:Job,name:String,description:String,enabled:Bool) throws -> String {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=128,description.utf16.count<=512 else {throw SQLFailure("İş adı 1–128, açıklama en çok 512 karakter olmalı.")}
    return "EXEC msdb.dbo.sp_update_job @job_id=\(try jobID(job.id)), @new_name=\(SQL.literal(name)), @description=\(SQL.literal(description)), @enabled=\(enabled ? 1:0);"
  }
  public static func updateStep(jobID id:String,step:Step,name:String,database:String,command:String) throws -> String {
    guard step.subsystem == "TSQL",step.id>0,!name.isEmpty,name.utf16.count<=128,!database.isEmpty,database.utf16.count<=128,!command.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw SQLFailure("Yalnızca mevcut T-SQL adımları düzenlenebilir; ad, veritabanı ve komut gerekli.")}
    return "EXEC msdb.dbo.sp_update_jobstep @job_id=\(try jobID(id)), @step_id=\(step.id), @step_name=\(SQL.literal(name)), @database_name=\(SQL.literal(database)), @command=\(SQL.literal(command));"
  }
  public static func scheduleState(id:Int,enabled:Bool) throws -> String {
    guard id>0 else {throw SQLFailure("Schedule ID gerekli.")}
    return "EXEC msdb.dbo.sp_update_schedule @schedule_id=\(id), @enabled=\(enabled ? 1:0);"
  }
  public static func decodeJobs(_ result:Execution) throws -> [Job] {
    guard !result.partial else {throw SQLFailure("Agent listesi kısmi; yenileyin.")}
    return try (result.results.first?.values ?? []).map {r in
      guard r.count>=7,let id=r[0],UUID(uuidString:id) != nil,let name=r[1] else {throw SQLFailure("Job bilgisi eksik.")}
      return Job(id:id,name:name,enabled:r[2]=="1",description:r[3] ?? "",owner:r[4] ?? "",state:r[5] ?? "Unknown",modified:r[6] ?? "")
    }
  }
  public static func decodeDetails(_ result:Execution) throws -> (Job,[Step],[Schedule]) {
    guard let job=try decodeJobs(result).first,result.results.count>=3 else {throw SQLFailure("İş bulunamadı veya msdb okuma izni eksik.")}
    let steps=try result.results[1].values.map {r -> Step in
      guard r.count>=5,let id=r[0].flatMap(Int.init) else {throw SQLFailure("Adım bilgisi eksik.")}
      return Step(id:id,name:r[1] ?? "",subsystem:r[2] ?? "",database:r[3] ?? "master",command:r[4] ?? "")
    }
    let schedules=try result.results[2].values.map {r -> Schedule in
      guard r.count>=5,let id=r[0].flatMap(Int.init) else {throw SQLFailure("Zamanlama bilgisi eksik.")}
      return Schedule(id:id,name:r[1] ?? "",enabled:r[2]=="1",frequency:r[3] ?? "",time:r[4] ?? "")
    }
    return (job,steps,schedules)
  }
  public static func decodeHistory(_ result:Execution) throws -> [History] {
    guard !result.partial else {throw SQLFailure("İş geçmişi kısmi; yenileyin.")}
    return try (result.results.first?.values ?? []).map {r in
      guard r.count>=8,let id=r[0].flatMap(Int.init),let step=r[2].flatMap(Int.init),let status=r[4].flatMap(Int.init) else {throw SQLFailure("Geçmiş satırı eksik.")}
      return History(id:id,job:r[1] ?? "",step:step,stepName:r[3] ?? "",status:status,started:r[5] ?? "",duration:r[6] ?? "",message:r[7] ?? "")
    }
  }
}
