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
    public var category=""
    public var created=""
    public var startStep=1
    public var emailLevel=0
    public var emailOperator=""
    public var eventLogLevel=0
    public var deleteLevel=0
    public var lastRun=""
    public var lastStatus = -1
    public var nextRun=""
    public var version:Int? = nil
  }
  public struct Step: Identifiable, Sendable {
    public var id:Int
    public var name:String
    public var subsystem:String
    public var database:String
    public var command:String
    public init(id:Int,name:String,subsystem:String,database:String,command:String) {self.id=id;self.name=name;self.subsystem=subsystem;self.database=database;self.command=command}
    public var successAction=1
    public var successStep=0
    public var failAction=2
    public var failStep=0
    public var retryAttempts=0
    public var retryInterval=0
    public var outputFile=""
    public var flags=0
    public var databaseUser=""
  }
  public struct Schedule: Identifiable, Sendable {
    public var id:Int
    public var name:String
    public var enabled:Bool
    public var frequency:String
    public var time:String
    public init(id:Int,name:String,enabled:Bool,frequency:String,time:String) {self.id=id;self.name=name;self.enabled=enabled;self.frequency=frequency;self.time=time}
    public var interval=1
    public var subdayType=1
    public var subdayInterval=0
    public var relativeInterval=1
    public var recurrence=1
    public var startDate=19900101
    public var endDate=99991231
    public var endTime=235959
    public var jobCount=1
    public var modified=""
    public var version:Int? = nil
    public var summary:String {SQLAgent.scheduleSummary(self)}
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
    public var jobID=""
    public var runID=0
    public var severity=0
    public var messageID=0
    public var retries=0
    public var server=""
    public var children:[History]?
    public var statusLabel:String {switch status {case 0:"Failed";case 1:"Succeeded";case 2:"Retry";case 3:"Canceled";case 4:"In Progress";default:"Unknown"}}
  }
  public static func displayDate(_ value:String)->String {
    guard !value.isEmpty else {return "—"}
    let normalized=String(value.prefix(19)).replacingOccurrences(of:"T",with:" ")
    let input=DateFormatter();input.locale=Locale(identifier:"en_US_POSIX");input.timeZone=TimeZone(secondsFromGMT:0);input.dateFormat="yyyy-MM-dd HH:mm:ss";input.isLenient=false
    guard let date=input.date(from:normalized) else {return value}
    let output=DateFormatter();output.locale=Locale(identifier:"tr_TR");output.timeZone=input.timeZone;output.dateFormat="dd.MM.yyyy HH:mm:ss"
    return output.string(from:date)
  }
  public static func saveProperties(statements:[String],job:Job,fetch:@Sendable (String) async throws -> Execution) async throws -> (Job,[Step],[Schedule]) {
    let script=try checkedScript(statements,job:job)
    try Task.checkCancellation()
    let result=try await fetch(script)
    guard !result.partial,!result.stoppedEarly else {throw SQLFailure("Kaydetme sonucu kesin değil; tekrar göndermeden önce sunucudan yenileyin.")}
    // Re-read by stable ID so renaming the job does not lose its identity.
    do {return try decodeDetails(await fetch(details(id:job.id)))}
    catch {throw SQLFailure("Değişiklik gönderildi, güncel Job bilgileri okunamadı. Yenile ile kontrol edin; kaydetmeyi tekrar etmeyin. "+error.localizedDescription)}
  }
  public static func jobs(name:String?=nil) -> String {
    """
    /* StudioAgent.jobs */
    SELECT TOP (1000) CONVERT(nvarchar(36),j.job_id),j.name,j.enabled,j.description,COALESCE(SUSER_SNAME(j.owner_sid),N''),
    CASE WHEN a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL THEN N'Running' ELSE N'Idle' END,
    CONVERT(nvarchar(30),j.date_modified,126),COALESCE(c.name,N''),CONVERT(nvarchar(30),j.date_created,126),
    j.start_step_id,j.notify_level_email,COALESCE(o.name,N''),j.notify_level_eventlog,j.delete_level,
    CASE WHEN h.run_date>0 THEN CONVERT(nvarchar(10),TRY_CONVERT(date,CONVERT(char(8),h.run_date)))+N' '+STUFF(STUFF(RIGHT('000000'+CONVERT(varchar(6),h.run_time),6),3,0,':'),6,0,':') ELSE N'' END,COALESCE(h.run_status,-1),
    CASE WHEN n.next_run_date>0 THEN CONVERT(nvarchar(10),TRY_CONVERT(date,CONVERT(char(8),n.next_run_date)))+N' '+STUFF(STUFF(RIGHT('000000'+CONVERT(varchar(6),n.next_run_time),6),3,0,':'),6,0,':') ELSE N'' END,j.version_number
    FROM msdb.dbo.sysjobs j OUTER APPLY (SELECT TOP (1) start_execution_date,stop_execution_date FROM msdb.dbo.sysjobactivity WHERE job_id=j.job_id AND session_id=(SELECT MAX(session_id) FROM msdb.dbo.syssessions)) a
    LEFT JOIN msdb.dbo.syscategories c ON c.category_id=j.category_id
    LEFT JOIN msdb.dbo.sysoperators o ON o.id=j.notify_email_operator_id
    OUTER APPLY (SELECT TOP (1) run_date,run_time,run_status FROM msdb.dbo.sysjobhistory WHERE job_id=j.job_id AND step_id=0 ORDER BY instance_id DESC) h
    OUTER APPLY (SELECT TOP (1) next_run_date,next_run_time FROM msdb.dbo.sysjobschedules WHERE job_id=j.job_id AND next_run_date>0 ORDER BY next_run_date,next_run_time) n
    \(name.map {"WHERE j.name="+SQL.literal($0)} ?? "") ORDER BY j.name;
    """
  }
  public static func details(name:String) -> String {
    jobs(name:name)+"""

    /* StudioAgent.details */
    SELECT s.step_id,s.step_name,s.subsystem,COALESCE(s.database_name,N'master'),s.command,
      s.on_success_action,s.on_success_step_id,s.on_fail_action,s.on_fail_step_id,s.retry_attempts,s.retry_interval,
      COALESCE(s.output_file_name,N''),s.flags,COALESCE(s.database_user_name,N'')
    FROM msdb.dbo.sysjobsteps s JOIN msdb.dbo.sysjobs j ON j.job_id=s.job_id WHERE j.name=\(SQL.literal(name)) ORDER BY s.step_id;
    SELECT s.schedule_id,s.name,s.enabled,CONVERT(nvarchar(20),s.freq_type),RIGHT('000000'+CONVERT(varchar(6),s.active_start_time),6),
      s.freq_interval,s.freq_subday_type,s.freq_subday_interval,s.freq_relative_interval,s.freq_recurrence_factor,
      s.active_start_date,s.active_end_date,s.active_end_time,(SELECT COUNT(*) FROM msdb.dbo.sysjobschedules x WHERE x.schedule_id=s.schedule_id),CONVERT(nvarchar(30),s.date_modified,126),s.version_number
    FROM msdb.dbo.sysschedules s JOIN msdb.dbo.sysjobschedules js ON js.schedule_id=s.schedule_id
    JOIN msdb.dbo.sysjobs j ON j.job_id=js.job_id WHERE j.name=\(SQL.literal(name)) ORDER BY s.name;
    """
  }
  public static func scheduleDetails(id:Int) throws -> String {
    guard id>0 else {throw SQLFailure("Schedule ID gerekli.")}
    return """
    /* StudioAgent.schedule */
    SELECT s.schedule_id,s.name,s.enabled,CONVERT(nvarchar(20),s.freq_type),RIGHT('000000'+CONVERT(varchar(6),s.active_start_time),6),
      s.freq_interval,s.freq_subday_type,s.freq_subday_interval,s.freq_relative_interval,s.freq_recurrence_factor,
      s.active_start_date,s.active_end_date,s.active_end_time,(SELECT COUNT(*) FROM msdb.dbo.sysjobschedules x WHERE x.schedule_id=s.schedule_id),CONVERT(nvarchar(30),s.date_modified,126),s.version_number
    FROM msdb.dbo.sysschedules s WHERE s.schedule_id=\(id);
    """
  }
  public static func details(id:String) throws -> String {
    details(name:"").replacingOccurrences(of:"j.name=N''",with:"j.job_id="+(try jobID(id)))
  }
  public static func history(name:String?=nil,status:Int?=nil,days:Int=30,includeSteps:Bool=false) -> String {
    let statusFilter=status.flatMap {(0...4).contains($0) ? " AND h.run_status=\($0)":nil} ?? ""
    // Filter outcomes first, then retain every available step (including retries)
    // belonging to each outcome. Never filter successful steps out of a failed run.
    return """
    /* StudioAgent.history */
    WITH runs AS (
      SELECT TOP (500) h.instance_id,h.job_id,
        \(includeSteps ? "COALESCE((SELECT MAX(p.instance_id) FROM msdb.dbo.sysjobhistory p WHERE p.job_id=h.job_id AND p.step_id=0 AND p.instance_id<h.instance_id),0)" : "0") AS previous_id
      FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id=h.job_id
      WHERE h.step_id=0 AND h.run_date>=CONVERT(int,CONVERT(char(8),DATEADD(day,-\(max(1,min(3650,days))),GETDATE()),112))
      \(name.map {" AND j.name="+SQL.literal($0)} ?? "") \(statusFilter)
      ORDER BY h.instance_id DESC
    )
    SELECT TOP (5001) h.instance_id,j.name,h.step_id,h.step_name,h.run_status,
      CONVERT(nvarchar(10),TRY_CONVERT(date,CONVERT(char(8),NULLIF(h.run_date,0))),120)+N' '+STUFF(STUFF(RIGHT('000000'+CONVERT(varchar(6),h.run_time),6),3,0,':'),6,0,':'),
      CONVERT(varchar(12),h.run_duration/10000)+':'+RIGHT('00'+CONVERT(varchar(2),(h.run_duration/100)%100),2)+':'+RIGHT('00'+CONVERT(varchar(2),h.run_duration%100),2),h.message,
      CONVERT(nvarchar(36),h.job_id),r.instance_id,h.sql_severity,h.sql_message_id,h.retries_attempted,h.server
    FROM runs r JOIN msdb.dbo.sysjobhistory h ON h.job_id=r.job_id AND
      (h.instance_id=r.instance_id \(includeSteps ? "OR (h.step_id>0 AND h.instance_id>r.previous_id AND h.instance_id<r.instance_id)":""))
    JOIN msdb.dbo.sysjobs j ON j.job_id=h.job_id
    ORDER BY r.instance_id DESC,h.instance_id DESC;
    """
  }
  public static func historyTree(_ rows:[History]) -> [History] {
    let children=Dictionary(grouping:rows.filter {$0.step>0},by:{$0.runID})
    return rows.filter {$0.step == 0}.map {row in
      var row=row
      let steps=(children[row.id] ?? []).filter {$0.jobID == row.jobID}.sorted {$0.id<$1.id}
      row.children=steps.isEmpty ? nil:steps
      return row
    }
  }
  public static func flowLabel(_ action:Int,step:Int) -> String {
    switch action {case 1:"Başarıyla bitir";case 2:"Başarısız bitir";case 3:"Sonraki adım";case 4:"Adıma git: \(step)";default:"Bilinmeyen (\(action))"}
  }
  public static func scheduleSummary(_ s:Schedule) -> String {
    let t=s.time.count == 6 ? "\(s.time.prefix(2)):\(s.time.dropFirst(2).prefix(2)):\(s.time.suffix(2))":s.time
    let cadence:String
    switch Int(s.frequency) {
    case 1:cadence="Bir kez · \(s.startDate)"
    case 4:cadence="Her \(s.interval) gün"
    case 8:
      let names=["Paz","Pzt","Sal","Çar","Per","Cum","Cmt"]
      cadence="Her \(s.recurrence) hafta · "+names.enumerated().filter {s.interval & (1 << $0.offset) != 0}.map(\.element).joined(separator:", ")
    case 16:cadence="Her \(s.recurrence) ay · \(s.interval). gün"
    case 32:
      let order=[1:"ilk",2:"ikinci",4:"üçüncü",8:"dördüncü",16:"son"][s.relativeInterval] ?? "?"
      let day=[1:"Pazar",2:"Pazartesi",3:"Salı",4:"Çarşamba",5:"Perşembe",6:"Cuma",7:"Cumartesi",8:"gün",9:"hafta içi günü",10:"hafta sonu günü"][s.interval] ?? "?"
      cadence="Her \(s.recurrence) ay · \(order) \(day)"
    case 64:return "Agent başladığında"
    case 128:return "İşlemci boşta olduğunda"
    default:return "Tür \(s.frequency)"
    }
    if s.subdayType == 1 {return cadence+" · "+t}
    let unit=s.subdayType == 2 ? "saniye":s.subdayType == 4 ? "dakika":"saat"
    return cadence+" · her \(s.subdayInterval) \(unit) · "+t
  }
  public static let serviceStatus="SELECT servicename,status_desc,startup_type_desc,last_startup_time FROM sys.dm_server_services WHERE servicename LIKE N'SQL Server Agent%';"
  private static func jobID(_ id:String) throws -> String {
    guard let uuid=UUID(uuidString:id) else {throw SQLFailure("Geçerli Job ID gerekli.")}
    return SQL.literal(uuid.uuidString)
  }
  public static func command(_ action:Action,id:String,stepName:String?=nil) throws -> String {
    let id=try jobID(id)
    switch action {
    case .start:
      if let stepName {guard !stepName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,stepName.utf16.count<=128 else {throw SQLFailure("Geçerli başlangıç adımı adı gerekli.")}}
      return "EXEC msdb.dbo.sp_start_job @job_id=\(id)\(stepName.map {", @step_name="+SQL.literal($0)} ?? "");"
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
  public static func stepScript(jobID id:String,step:Step,existingIDs:Set<Int>,isNew:Bool=false) throws -> String {
    guard step.subsystem == "TSQL",step.id>0,!step.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,step.name.utf16.count<=128,
      !step.database.isEmpty,step.database.utf16.count<=128,!step.command.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
      (0...9999).contains(step.retryAttempts),(0...9999).contains(step.retryInterval),step.outputFile.utf16.count<=200,
      step.databaseUser.utf16.count<=128 else {throw SQLFailure("T-SQL adımı, ad, veritabanı ve komut gerekli; tekrar sayısı/aralığı 0–9999 olmalı.")}
    for (action,target) in [(step.successAction,step.successStep),(step.failAction,step.failStep)] {
      guard (1...4).contains(action),action != 4 || existingIDs.contains(target) else {throw SQLFailure("Akış hedefi mevcut bir adım olmalı.")}
    }
    guard isNew ? !existingIDs.contains(step.id):existingIDs.contains(step.id) else {throw SQLFailure("Adım kimliği değişti; yenileyin.")}
    return "EXEC msdb.dbo.\(isNew ? "sp_add_jobstep":"sp_update_jobstep") @job_id=\(try jobID(id)), @step_id=\(step.id), @step_name=\(SQL.literal(step.name)), @subsystem=N'TSQL', @database_name=\(SQL.literal(step.database)), @command=\(SQL.literal(step.command)), @on_success_action=\(step.successAction), @on_success_step_id=\(step.successStep), @on_fail_action=\(step.failAction), @on_fail_step_id=\(step.failStep), @retry_attempts=\(step.retryAttempts), @retry_interval=\(step.retryInterval), @output_file_name=\(SQL.literal(step.outputFile)), @flags=\(step.flags), @database_user_name=\(SQL.literal(step.databaseUser));"
  }
  public static func deleteStep(jobID id:String,stepID:Int) throws -> String {
    guard stepID>0 else {throw SQLFailure("Adım kimliği gerekli.")}
    return "EXEC msdb.dbo.sp_delete_jobstep @job_id=\(try jobID(id)), @step_id=\(stepID);"
  }
  public static func generalScript(_ job:Job,name:String,description:String,enabled:Bool,owner:String,category:String,startStep:Int,stepIDs:Set<Int>) throws -> String {
    guard startStep>0,(stepIDs.isEmpty ? startStep == job.startStep:stepIDs.contains(startStep)),!owner.isEmpty,owner.utf16.count<=128,!category.isEmpty,category.utf16.count<=128 else {throw SQLFailure("Sahip, kategori ve geçerli başlangıç adımı gerekli.")}
    var script=String(try update(job,name:name,description:description,enabled:enabled).dropLast())
    if owner != job.owner {script+=", @owner_login_name=\(SQL.literal(owner))"}
    if category != job.category {script+=", @category_name=\(SQL.literal(category))"}
    if startStep != job.startStep {script+=", @start_step_id=\(startStep)"}
    return script+";"
  }
  public static func notifications(jobID id:String,emailLevel:Int,operatorName:String,eventLogLevel:Int,deleteLevel:Int) throws -> String {
    guard [emailLevel,eventLogLevel,deleteLevel].allSatisfy({(0...3).contains($0)}),emailLevel == 0 || (!operatorName.isEmpty && operatorName.utf16.count<=128) else {throw SQLFailure("Bildirim koşulu ve e-posta operatörü gerekli.")}
    return "EXEC msdb.dbo.sp_update_job @job_id=\(try jobID(id)), @notify_level_email=\(emailLevel), \(operatorName.isEmpty ? "":"@notify_email_operator_name="+SQL.literal(operatorName)+", ")@notify_level_eventlog=\(eventLogLevel), @delete_level=\(deleteLevel);"
  }
  public static func checkedScript(_ statements:[String],job:Job?=nil) throws -> String {
    guard !statements.isEmpty else {throw SQLFailure("Değişiklik yok.")}
    let guardSQL:String
    if let job {
      guard !job.modified.isEmpty else {throw SQLFailure("İş sürümü okunamadı; yenileyin.")}
      guardSQL="IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WITH (UPDLOCK,HOLDLOCK) WHERE job_id=\(try jobID(job.id)) AND date_modified=CONVERT(datetime,\(SQL.literal(job.modified)),126)\(job.version.map {" AND version_number=\($0)"} ?? "")) THROW 51000,N'İş başka bir oturumda değişti. Yenileyin.',1;"
    } else {guardSQL=""}
    let body=statements.map {statement in
      statement.replacingOccurrences(of:"EXEC msdb.dbo.",with:"EXEC @studio_agent_rc = msdb.dbo.")+"\nIF @studio_agent_rc <> 0 THROW 51001,N'Agent işlemi başarısız; değişiklikler geri alındı.',1;"
    }.joined(separator:"\n")
    return """
    -- Değişiklikleri inceleyip Çalıştır'a basın. Job çalıştırılmaz.
    IF @@TRANCOUNT <> 0 THROW 51002,N'Agent değişikliklerini açık transaction olmayan bir sekmede çalıştırın.',1;
    SET XACT_ABORT ON;
    BEGIN TRY
      BEGIN TRANSACTION;
      \(guardSQL)
      DECLARE @studio_agent_rc int;
      \(body)
      COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
      IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
      THROW;
    END CATCH;
    """
  }
  public static func scheduleScript(_ s:Schedule,jobID id:String?=nil) throws -> String {
    func validTime(_ n:Int)->Bool {n>=0 && n/10000<24 && (n/100)%100<60 && n%100<60}
    func validDate(_ n:Int)->Bool {
      var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
      let components=DateComponents(year:n/10000,month:(n/100)%100,day:n%100)
      guard n>=19900101,n<=99991231,let date=calendar.date(from:components) else {return false}
      return calendar.dateComponents([.year,.month,.day],from:date) == components
    }
    guard !s.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,s.name.utf16.count<=128,
      let frequency=Int(s.frequency),[1,4,8,16,32,64,128].contains(frequency),let startTime=Int(s.time),validTime(startTime),validTime(s.endTime),startTime<=s.endTime,
      validDate(s.startDate),validDate(s.endDate),s.startDate<=s.endDate,
      [1,2,4,8].contains(s.subdayType),s.subdayType == 1 || s.subdayInterval >= (s.subdayType == 2 ? 10:1),
      s.subdayInterval<=999999 else {throw SQLFailure("Zamanlama adı, geçerli tarih/saat ve tekrar aralığı gerekli. Saniye aralığı en az 10 olmalı.")}
    guard frequency != 4 || s.interval>=1,
      frequency != 8 || ((1...127).contains(s.interval) && s.recurrence>=1),
      frequency != 16 || ((1...31).contains(s.interval) && s.recurrence>=1),
      frequency != 32 || ((1...10).contains(s.interval) && [1,2,4,8,16].contains(s.relativeInterval) && s.recurrence>=1) else {throw SQLFailure("Gün/hafta/ay tekrarını ve gün seçimini kontrol edin.")}
    let prefix:String
    if let id {prefix="sp_add_jobschedule @job_id=\(try jobID(id)), @name=\(SQL.literal(s.name))"}
    else {guard s.id>0 else {throw SQLFailure("Schedule ID gerekli.")};prefix="sp_update_schedule @schedule_id=\(s.id), @new_name=\(SQL.literal(s.name))"}
    let guardSQL = id == nil && !s.modified.isEmpty ? "IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WITH (UPDLOCK,HOLDLOCK) WHERE schedule_id=\(s.id) AND date_modified=CONVERT(datetime,\(SQL.literal(s.modified)),126)\(s.version.map {" AND version_number=\($0)"} ?? "")) THROW 51003,N'Zamanlama başka bir oturumda değişti. Yenileyin.',1;\n":""
    return guardSQL+"EXEC msdb.dbo.\(prefix), @enabled=\(s.enabled ? 1:0), @freq_type=\(frequency), @freq_interval=\(s.interval), @freq_subday_type=\(s.subdayType), @freq_subday_interval=\(s.subdayInterval), @freq_relative_interval=\(s.relativeInterval), @freq_recurrence_factor=\(s.recurrence), @active_start_date=\(s.startDate), @active_end_date=\(s.endDate), @active_start_time=\(startTime), @active_end_time=\(s.endTime);"
  }
  public static func attachSchedule(jobID id:String,scheduleID:Int) throws -> String {
    guard scheduleID>0 else {throw SQLFailure("Schedule ID gerekli.")}
    return "EXEC msdb.dbo.sp_attach_schedule @job_id=\(try jobID(id)), @schedule_id=\(scheduleID);"
  }
  public static func availableSchedules() throws -> String {
    try scheduleDetails(id:1).replacingOccurrences(of:"WHERE s.schedule_id=1;",with:"ORDER BY s.name;")
  }
  public static func detachSchedule(jobID id:String,scheduleID:Int) throws -> String {
    guard scheduleID>0 else {throw SQLFailure("Schedule ID gerekli.")}
    return "EXEC msdb.dbo.sp_detach_schedule @job_id=\(try jobID(id)), @schedule_id=\(scheduleID), @delete_unused_schedule=0;"
  }
  public static func scheduleState(id:Int,enabled:Bool) throws -> String {
    guard id>0 else {throw SQLFailure("Schedule ID gerekli.")}
    return "EXEC msdb.dbo.sp_update_schedule @schedule_id=\(id), @enabled=\(enabled ? 1:0);"
  }
  public static func decodeJobs(_ result:Execution) throws -> [Job] {
    guard !result.partial else {throw SQLFailure("Agent listesi kısmi; yenileyin.")}
    return try (result.results.first?.values ?? []).map {r in
      guard r.count>=7,let id=r[0],UUID(uuidString:id) != nil,let name=r[1] else {throw SQLFailure("Job bilgisi eksik.")}
      var job=Job(id:id,name:name,enabled:r[2]=="1",description:r[3] ?? "",owner:r[4] ?? "",state:r[5] ?? "Unknown",modified:r[6] ?? "")
      if r.count>=17 {job.category=r[7] ?? "";job.created=r[8] ?? "";job.startStep=Int(r[9] ?? "") ?? 1;job.emailLevel=Int(r[10] ?? "") ?? 0;job.emailOperator=r[11] ?? "";job.eventLogLevel=Int(r[12] ?? "") ?? 0;job.deleteLevel=Int(r[13] ?? "") ?? 0;job.lastRun=r[14] ?? "";job.lastStatus=Int(r[15] ?? "") ?? -1;job.nextRun=r[16] ?? ""}
      if r.count>=18 {job.version=r[17].flatMap(Int.init)}
      return job
    }
  }
  public static func decodeDetails(_ result:Execution) throws -> (Job,[Step],[Schedule]) {
    guard let job=try decodeJobs(result).first,result.results.count>=3 else {throw SQLFailure("İş bulunamadı veya msdb okuma izni eksik.")}
    let steps=try result.results[1].values.map {r -> Step in
      guard r.count>=5,let id=r[0].flatMap(Int.init) else {throw SQLFailure("Adım bilgisi eksik.")}
      var step=Step(id:id,name:r[1] ?? "",subsystem:r[2] ?? "",database:r[3] ?? "master",command:r[4] ?? "")
      if r.count>=14 {step.successAction=Int(r[5] ?? "") ?? 1;step.successStep=Int(r[6] ?? "") ?? 0;step.failAction=Int(r[7] ?? "") ?? 2;step.failStep=Int(r[8] ?? "") ?? 0;step.retryAttempts=Int(r[9] ?? "") ?? 0;step.retryInterval=Int(r[10] ?? "") ?? 0;step.outputFile=r[11] ?? "";step.flags=Int(r[12] ?? "") ?? 0;step.databaseUser=r[13] ?? ""}
      return step
    }
    let schedules=try decodeSchedules(Array(result.results[2].values))
    return (job,steps,schedules)
  }
  public static func decodeSchedules(_ rows:[[String?]]) throws -> [Schedule] {
    return try rows.map {r -> Schedule in
      guard r.count>=5,let id=r[0].flatMap(Int.init) else {throw SQLFailure("Zamanlama bilgisi eksik.")}
      var schedule=Schedule(id:id,name:r[1] ?? "",enabled:r[2]=="1",frequency:r[3] ?? "",time:r[4] ?? "")
      if r.count>=14 {schedule.interval=Int(r[5] ?? "") ?? 1;schedule.subdayType=Int(r[6] ?? "") ?? 1;schedule.subdayInterval=Int(r[7] ?? "") ?? 0;schedule.relativeInterval=Int(r[8] ?? "") ?? 1;schedule.recurrence=Int(r[9] ?? "") ?? 1;schedule.startDate=Int(r[10] ?? "") ?? 19900101;schedule.endDate=Int(r[11] ?? "") ?? 99991231;schedule.endTime=Int(r[12] ?? "") ?? 235959;schedule.jobCount=Int(r[13] ?? "") ?? 1}
      if r.count>=15 {schedule.modified=r[14] ?? ""}
      if r.count>=16 {schedule.version=r[15].flatMap(Int.init)}
      return schedule
    }
  }
  public static func decodeHistory(_ result:Execution) throws -> [History] {
    guard !result.partial else {throw SQLFailure("İş geçmişi kısmi; yenileyin.")}
    return try (result.results.first?.values ?? []).map {r in
      guard r.count>=8,let id=r[0].flatMap(Int.init),let step=r[2].flatMap(Int.init),let status=r[4].flatMap(Int.init) else {throw SQLFailure("Geçmiş satırı eksik.")}
      var row=History(id:id,job:r[1] ?? "",step:step,stepName:r[3] ?? "",status:status,started:r[5] ?? "",duration:r[6] ?? "",message:r[7] ?? "")
      if r.count>=14 {row.jobID=r[8] ?? "";row.runID=Int(r[9] ?? "") ?? 0;row.severity=Int(r[10] ?? "") ?? 0;row.messageID=Int(r[11] ?? "") ?? 0;row.retries=Int(r[12] ?? "") ?? 0;row.server=r[13] ?? ""}
      return row
    }
  }
}
