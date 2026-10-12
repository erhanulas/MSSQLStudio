import Foundation
import Testing
@testable import SQLServerKit

@Suite(.serialized) struct ManagementWorkflowTests {
  @Test func diffAlignsDisjointChangesWithoutMarkingUnchangedMiddle() {
    let diff=SQLTextDiff.compare("A\nB\nC\nD\nE","A\nNew B\nC\nD\nNew E\nF")
    #expect(diff.added == 3 && diff.removed == 2 && !diff.simplified)
    #expect(diff.lines.filter {!$0.changed}.map(\.old) == ["A","C","D"])
    #expect(diff.lines.compactMap(\.old).joined(separator:"\n") == "A\nB\nC\nD\nE")
    #expect(diff.lines.compactMap(\.new).joined(separator:"\n") == "A\nNew B\nC\nD\nNew E\nF")
    #expect(SQLTextDiff.compare("İstanbul 😀\n","İstanbul 😀\n").added == 0)
    #expect(SQLTextDiff.compare("A\nB","A").removed == 1)
  }
  @Test func largeDiffFallsBackWithoutLosingOrReorderingSQL() {
    let old=(0..<5000).map {"old \($0)"}.joined(separator:"\n"),new=(0..<5001).map {"new \($0)"}.joined(separator:"\n")
    let diff=SQLTextDiff.compare(old,new)
    #expect(diff.simplified && diff.added == 5001 && diff.removed == 5000)
    #expect(diff.lines.compactMap(\.old).joined(separator:"\n") == old)
    #expect(diff.lines.compactMap(\.new).joined(separator:"\n") == new)
  }
  @Test func viewWhitespaceDiffHighlightsOnlyAddedProjectionAndKeepsOriginalPhysicalRows() throws {
    let original="CREATE VIEW dbo.v AS   \r\nSELECT    A.ID,  -- Müşteri kodu  \r\n    C.InvoiceDate,   \r\n    A.Amount   -- Fatura tutarı  \r\nFROM dbo.T A;  "
    let edited="CREATE VIEW dbo.v AS     \nSELECT A.ID, -- Müşteri kodu    \n\tC.InvoiceDate,\n\tC.INCKEYNO AS ExternalOrderId,\n\tA.Amount -- Fatura tutarı    \nFROM dbo.T A;    "
    let diff=SQLTextDiff.compareIgnoringSQLWhitespace(original,edited)
    #expect(diff.added==1 && diff.removed==0 && !diff.simplified)
    let changed=try #require(diff.lines.filter(\.changed).first)
    #expect(diff.lines.filter(\.changed).count==1)
    #expect(changed.old==nil && changed.new=="\tC.INCKEYNO AS ExternalOrderId,")
    #expect(changed.newNumber==4 && changed.newChanged && !changed.oldChanged)
    #expect(diff.lines.compactMap(\.oldNumber)==[1,2,3,4,5])
    #expect(diff.lines.compactMap(\.newNumber)==[1,2,3,4,5,6])
    #expect(diff.lines.compactMap(\.old).joined(separator:"\r\n")==original)
    #expect(diff.lines.compactMap(\.new).joined(separator:"\n")==edited)
    #expect(diff.lines.first?.oldLineEnding=="\r\n")
    #expect(diff.lines.filter {!$0.changed}.allSatisfy {$0.oldChanges?.isEmpty==true && $0.newChanges?.isEmpty==true})
    #expect(SQLTextDiff.compare(original,edited).removed>1)
  }
  @Test func viewWhitespaceDiffIgnoresReflowBlankLinesAndLineDelimiterStyle() {
    let original="CREATE VIEW dbo.v AS SELECT A.ID,A.Name FROM dbo.T A; -- comment"
    let edited="CREATE\rVIEW dbo.v AS\r\rSELECT\r    A.ID,\r    A.Name\rFROM dbo.T A; -- comment  \r"
    let diff=SQLTextDiff.compareIgnoringSQLWhitespace(original,edited)
    #expect(diff.added==0 && diff.removed==0 && diff.lines.allSatisfy {!$0.changed})
    #expect(diff.lines.compactMap(\.oldNumber)==[1])
    #expect(diff.lines.compactMap(\.newNumber)==Array(1...8))
    #expect(diff.lines.compactMap(\.new).joined(separator:"\r")==edited)
  }
  @Test func viewWhitespaceDiffKeepsRealChangesLocalizedWhenOtherExpressionsWrap() {
    let original="CREATE VIEW dbo.v AS\nSELECT A.ID, A.Name,\n    C.InvoiceDate,\n    A.Amount\nFROM dbo.T A;"
    let edited="CREATE VIEW dbo.v\nAS SELECT A.ID,\n    A.Name,\n    C.InvoiceDate,\n    C.INCKEYNO AS ExternalOrderId,\n    A.Amount\nFROM\n    dbo.T A;"
    let diff=SQLTextDiff.compareIgnoringSQLWhitespace(original,edited)
    #expect(diff.removed==0 && diff.added==1)
    #expect(diff.lines.filter(\.changed).count==1)
    #expect(diff.lines.first(where:\.changed)?.new?.contains("ExternalOrderId")==true)
  }
  @Test func viewWhitespaceDiffPreservesProtectedMultilineWhitespaceAndLineCommentBoundaries() {
    for (original,edited) in [
      ("SELECT N'a  b';","SELECT N'a b';"),
      ("SELECT [a  b];","SELECT [a b];"),
      ("SELECT \"a  b\";","SELECT \"a b\";"),
      ("SELECT N'a\n\nb';","SELECT N'a\nb';"),
      ("SELECT /* a\n\n b */ 1;","SELECT /* a\n b */ 1;"),
      ("SELECT N'a\r\nb';","SELECT N'a\nb';"),
      ("SELECT 1; -- comment\nSELECT 2;","SELECT 1; -- comment SELECT 2;")
    ] {
      let diff=SQLTextDiff.compareIgnoringSQLWhitespace(original,edited)
      #expect(diff.lines.contains(where:\.changed) && diff.added+diff.removed>0)
    }
    let equal=SQLTextDiff.compareIgnoringSQLWhitespace("SELECT N'a\n\nb', 1;"," SELECT N'a\n\nb',\n 1; ")
    #expect(equal.lines.allSatisfy {!$0.changed})
    #expect(equal.lines.compactMap(\.oldNumber)==[1,2,3])
  }
  @Test func viewWhitespaceDiffKeepsByteDistinctCanonicallyEquivalentLiteralsMeaningful() {
    for (a,b) in [("é","e\u{301}"),("Å","Å")] {
      let original="SELECT N'\(a)' AS [Name];",edited="SELECT N'\(b)' AS [Name];"
      let diff=SQLTextDiff.compareIgnoringSQLWhitespace(original,edited)
      #expect(diff.added==1 && diff.removed==1 && diff.lines.first?.changed==true)
      #expect(Data((diff.lines.first?.old ?? "").utf8)==Data(original.utf8))
      #expect(Data((diff.lines.first?.new ?? "").utf8)==Data(edited.utf8))
    }
  }
  @Test func viewWhitespaceDiffHasBoundedFallbackForDenseSemanticReplacements() {
    let original=(0..<1001).map {"SELECT [old\($0)] + \($0);"}.joined(separator:"\n")
    let edited=(0..<1001).map {"SELECT [new\($0)] - \($0+1);"}.joined(separator:"\n")
    let diff=SQLTextDiff.compareIgnoringSQLWhitespace(original,edited)
    #expect(diff.simplified && diff.added==1001 && diff.removed==1001)
    #expect(diff.lines.compactMap(\.old).joined(separator:"\n")==original)
    #expect(diff.lines.compactMap(\.new).joined(separator:"\n")==edited)
  }
  @Test func jobCommandsUseValidatedGUIDAndPreserveSharedSchedules() throws {
    let id=UUID().uuidString
    #expect(try SQLAgent.command(.enable,id:id).contains("@enabled=1"))
    #expect(try SQLAgent.command(.disable,id:id).contains("@enabled=0"))
    #expect(try SQLAgent.command(.start,id:id).contains("sp_start_job"))
    #expect(try SQLAgent.command(.start,id:id,stepName:"Step ' X").contains("@step_name=N'Step '' X'"))
    #expect(throws:SQLFailure.self) {try SQLAgent.command(.start,id:id,stepName:" ")}
    #expect(try SQLAgent.command(.stop,id:id).contains("sp_stop_job"))
    #expect(try SQLAgent.command(.delete,id:id).contains("@delete_unused_schedule=0"))
    #expect(throws:SQLFailure.self) {try SQLAgent.command(.delete,id:"'; DROP DATABASE msdb;--")}
    #expect(throws:SQLFailure.self) {try SQLAgent.scheduleState(id:0,enabled:true)}
  }
  @Test func agentDecodingAndPropertyScriptsHandleUnicodeQuotesAndSubsystems() throws {
    var data=Execution();let id=UUID().uuidString
    data.results=[Rows(values:[[id,"İş ' One","1","Description","sa","Idle","2026-10-09"]]),Rows(values:[["1","T-SQL","TSQL","master","SELECT 1;"]]),Rows(values:[["5","Daily","0","4","210000"]])]
    let (job,steps,schedules)=try SQLAgent.decodeDetails(data)
    #expect(job.enabled && steps.count == 1 && !schedules[0].enabled)
    let script=try SQLAgent.update(job,name:"İş ' Two",description:"It's test",enabled:false)
    #expect(script.contains("@new_name=N'İş '' Two'") && script.contains("@description=N'It''s test'"))
    #expect(try SQLAgent.updateStep(jobID:id,step:steps[0],name:"Step",database:"master",command:"SELECT N'İstanbul';").contains("N'SELECT N''İstanbul'';'"))
    #expect(throws:SQLFailure.self) {try SQLAgent.updateStep(jobID:id,step:SQLAgent.Step(id:1,name:"Shell",subsystem:"CmdExec",database:"master",command:"echo"),name:"Shell",database:"master",command:"echo changed")}
    #expect(throws:SQLFailure.self) {try SQLAgent.update(job,name:String(repeating:"😀",count:65),description:"",enabled:false)}
    data.partial=true;#expect(throws:SQLFailure.self) {try SQLAgent.decodeDetails(data)}
  }
  @Test func historyIsBoundedFilteredAndDecodesDurationsMessages() throws {
    let sql=SQLAgent.history(name:"Job ' X",status:0,days:99999,includeSteps:false)
    #expect(sql.contains("TOP (500)") && sql.contains("N'Job '' X'") && sql.contains("h.run_status=0") && sql.contains("h.step_id=0") && sql.contains("-3650"))
    #expect(!sql.contains("SELECT MAX(p.instance_id)"))
    #expect(SQLAgent.history(includeSteps:true).contains("SELECT MAX(p.instance_id)"))
    #expect(!SQLAgent.history(includeSteps:true).contains("AND h.step_id=0"))
    var data=Execution();data.results=[Rows(values:[["123","Test","0","(Job outcome)","1","2026-10-09 21:00:00","127:04:03","İş tamamlandı"]])]
    let row=try #require(SQLAgent.decodeHistory(data).first)
    #expect(row.duration == "127:04:03" && row.statusLabel == "Succeeded" && row.message == "İş tamamlandı")
  }
  @Test func historyFilteringRetainsStepContextAndGroupsByRunAndJob() throws {
    let query=SQLAgent.history(status:0,includeSteps:true)
    #expect(query.contains("WITH runs AS") && query.contains("h.run_status=0"))
    #expect(query.contains("h.instance_id>r.previous_id") && query.contains("h.instance_id<r.instance_id"))
    #expect(query.components(separatedBy:"h.run_status=0").count == 2)
    let a=UUID().uuidString,b=UUID().uuidString
    var data=Execution()
    data.results=[Rows(values:[
      ["30","A","0","Outcome","0","2026-10-10 01:00:00","27:02:01","Failed",a,"30","16","50000","0","test"],
      ["29","A","2","Failing step","0","2026-10-10 01:00:00","0:01:00","Failure",a,"30","16","50000","2","test"],
      ["28","A","1","Successful step","1","2026-10-10 00:00:00","0:00:01","OK",a,"30","0","0","0","test"],
      ["27","B","1","Other job","1","","","",b,"30","0","0","0","test"],
      ["20","A","0","Outcome","1","","","OK",a,"20","0","0","0","test"]])]
    let rows=try SQLAgent.decodeHistory(data),tree=SQLAgent.historyTree(rows)
    #expect(tree.map(\.id) == [30,20])
    #expect(tree[0].children?.map(\.id) == [28,29] && tree[1].children == nil)
    #expect(rows[0].duration == "27:02:01" && rows[1].retries == 2 && rows[0].messageID == 50000)
    data.partial=true;#expect(throws:SQLFailure.self) {try SQLAgent.decodeHistory(data)}
  }
  @Test func stepFlowScriptsValidateReferencesAndPreserveOutputFlags() throws {
    let id=UUID().uuidString
    var step=SQLAgent.Step(id:2,name:"It's İstanbul",subsystem:"TSQL",database:"master",command:"SELECT N'😀';")
    step.successAction=4;step.successStep=1;step.retryAttempts=7;step.retryInterval=3;step.flags=22;step.databaseUser="some'user"
    let sql=try SQLAgent.stepScript(jobID:id,step:step,existingIDs:[1,2])
    #expect(sql.contains("@on_success_step_id=1") && sql.contains("@retry_attempts=7") && sql.contains("@flags=22"))
    #expect(sql.contains("N'It''s İstanbul'") && sql.contains("N'some''user'"))
    step.successStep=9;#expect(throws:SQLFailure.self) {try SQLAgent.stepScript(jobID:id,step:step,existingIDs:[1,2])}
    step.successStep=1;step.retryInterval=10000;#expect(throws:SQLFailure.self) {try SQLAgent.stepScript(jobID:id,step:step,existingIDs:[1,2])}
    step.retryInterval=3;step.id=3
    #expect(try SQLAgent.stepScript(jobID:id,step:step,existingIDs:[1,2],isNew:true).contains("sp_add_jobstep"))
    #expect(throws:SQLFailure.self) {try SQLAgent.stepScript(jobID:id,step:step,existingIDs:[1,2])}
    #expect(try SQLAgent.deleteStep(jobID:id,stepID:1).contains("sp_delete_jobstep"))
  }
  @Test func jobGeneralAndNotificationScriptsPreserveUnchangedSecuritySettings() throws {
    let id=UUID().uuidString
    var job=SQLAgent.Job(id:id,name:"A",enabled:true,description:"",owner:"owner",state:"Idle",modified:"2026-10-10T01:02:03.000")
    job.category="Category";job.version=9
    let sql=try SQLAgent.generalScript(job,name:"B",description:"",enabled:true,owner:"owner",category:"Category",startStep:1,stepIDs:[1])
    #expect(!sql.contains("@owner_login_name") && !sql.contains("@category_name"))
    #expect(try SQLAgent.generalScript(job,name:"Empty job rename",description:"",enabled:false,owner:"owner",category:"Category",startStep:1,stepIDs:[]).contains("@new_name"))
    #expect(throws:SQLFailure.self) {try SQLAgent.generalScript(job,name:"B",description:"",enabled:true,owner:"owner",category:"Category",startStep:7,stepIDs:[1])}
    let notify=try SQLAgent.notifications(jobID:id,emailLevel:0,operatorName:"",eventLogLevel:2,deleteLevel:0)
    #expect(!notify.contains("@notify_email_operator_name") && !notify.contains("@notify_level_page"))
    #expect(throws:SQLFailure.self) {try SQLAgent.notifications(jobID:id,emailLevel:2,operatorName:"",eventLogLevel:0,deleteLevel:0)}
    let guarded=try SQLAgent.checkedScript([sql,notify],job:job)
    #expect(guarded.contains("UPDLOCK,HOLDLOCK") && guarded.contains("date_modified=CONVERT(datetime") && guarded.contains("version_number=9"))
    #expect(guarded.contains("IF @@TRANCOUNT <> 0") && guarded.contains("ROLLBACK TRANSACTION"))
    #expect(guarded.components(separatedBy:"IF @studio_agent_rc <> 0").count == 3)
    #expect(guarded.contains("EXEC @studio_agent_rc = msdb.dbo.sp_update_job"))
    #expect(!guarded.contains("sp_start_job"))
    #expect(try SQLAgent.details(id:id).contains("j.job_id=N'"))
  }
  @Test func schedulesDescribeWeekdaysAndValidateCalendarAndTime() throws {
    var s=SQLAgent.Schedule(id:5,name:"Week ' X",enabled:true,frequency:"8",time:"093000")
    s.interval=10;s.recurrence=2
    #expect(s.summary.contains("Pzt, Çar") && s.summary.contains("09:30:00"))
    let sql=try SQLAgent.scheduleScript(s)
    #expect(sql.contains("sp_update_schedule") && sql.contains("@freq_interval=10") && sql.contains("N'Week '' X'"))
    #expect(try SQLAgent.scheduleScript(s,jobID:UUID().uuidString).contains("sp_add_jobschedule"))
    s.startDate=20260230;#expect(throws:SQLFailure.self) {try SQLAgent.scheduleScript(s)}
    s.startDate=20260228;s.time="246000";#expect(throws:SQLFailure.self) {try SQLAgent.scheduleScript(s)}
    s.time="093000";s.interval=0;#expect(throws:SQLFailure.self) {try SQLAgent.scheduleScript(s)}
    s.interval=10;s.subdayType=2;s.subdayInterval=9;#expect(throws:SQLFailure.self) {try SQLAgent.scheduleScript(s)}
    s.subdayInterval=10;#expect(try SQLAgent.scheduleScript(s).contains("@freq_subday_interval=10"))
    #expect(try SQLAgent.detachSchedule(jobID:UUID().uuidString,scheduleID:5).contains("@delete_unused_schedule=0"))
    #expect(try SQLAgent.attachSchedule(jobID:UUID().uuidString,scheduleID:5).contains("sp_attach_schedule"))
    #expect(!(try SQLAgent.availableSchedules()).contains("WHERE s.schedule_id=1"))
    s.modified="2026-10-10T00:00:00.000"
    #expect(try SQLAgent.scheduleScript(s).contains("date_modified=CONVERT(datetime"))
    #expect(!(try SQLAgent.scheduleScript(s,jobID:UUID().uuidString)).contains("UPDLOCK"))
  }
  @Test func detailedAgentMetadataRetainsAdvancedAndSharedScheduleValues() throws {
    let id=UUID().uuidString
    var data=Execution()
    data.results=[Rows(values:[[id,"Test","1","Description","Owner","Running","2026-10-10T00:00:00.000","Category","2026-10-01","2","2","Operator","3","0","2026-10-10 00:00:00","0","2026-10-11 00:00:00"]]),
      Rows(values:[["2","Step","TSQL","master","SELECT 1;","4","1","2","0","5","10","C:\\out.txt","22","dbo"]]),
      Rows(values:[["5","Shared","1","32","093000","9","4","10","16","2","20261001","99991231","173000","4","2026-10-10T00:00:00.000"]])]
    let (job,steps,schedules)=try SQLAgent.decodeDetails(data)
    #expect(job.startStep == 2 && job.emailLevel == 2 && job.emailOperator == "Operator" && job.lastStatus == 0)
    #expect(steps[0].successStep == 1 && steps[0].retryAttempts == 5 && steps[0].flags == 22 && steps[0].databaseUser == "dbo")
    #expect(schedules[0].jobCount == 4 && !schedules[0].modified.isEmpty)
    #expect(schedules[0].summary.contains("son hafta içi günü"))
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["MSSQL_AGENT_TEST_PASSWORD"] != nil))
  func liveAgentJobPropertiesEnableDisableStepAndHistoryRollback() async throws {
    let password=try #require(ProcessInfo.processInfo.environment["MSSQL_AGENT_TEST_PASSWORD"])
    let c=ODBCConnection();var profile=ServerProfile(trustCertificate:true);profile.database="msdb"
    try await c.connect(profile,password:password)
    let name="StudioAgent_"+UUID().uuidString.replacingOccurrences(of:"-",with:"")
    do {
      _=try await c.execute("BEGIN TRANSACTION;")
      _=try await c.execute("EXEC dbo.sp_add_job @job_name=\(SQL.literal(name)), @enabled=0;")
      _=try await c.execute("EXEC dbo.sp_add_jobstep @job_name=\(SQL.literal(name)), @step_name=N'Test', @subsystem=N'TSQL', @database_name=N'master', @command=N'SELECT 1;';")
      let (job,steps,_)=try SQLAgent.decodeDetails(await c.execute(SQLAgent.details(name:name)))
      #expect(!job.enabled && steps.count == 1)
      _=try await c.execute(SQLAgent.command(.enable,id:job.id));#expect(try SQLAgent.decodeJobs(await c.execute(SQLAgent.jobs(name:name))).first?.enabled == true)
      _=try await c.execute(SQLAgent.command(.disable,id:job.id));#expect(try SQLAgent.decodeJobs(await c.execute(SQLAgent.jobs(name:name))).first?.enabled == false)
      _=try await c.execute(SQLAgent.updateStep(jobID:job.id,step:steps[0],name:"Renamed Step",database:"master",command:"SELECT 2;"))
      let (_,changed,_)=try SQLAgent.decodeDetails(await c.execute(SQLAgent.details(name:name)));#expect(changed[0].command == "SELECT 2;")
      #expect(try SQLAgent.decodeHistory(await c.execute(SQLAgent.history(name:name))).isEmpty)
      _=try await c.execute(SQLAgent.serviceStatus)
      _=try await c.execute("ROLLBACK TRANSACTION;")
      #expect(try SQLAgent.decodeJobs(await c.execute(SQLAgent.jobs(name:name))).isEmpty)
      await c.disconnect()
    } catch {_=try? await c.execute("IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;");await c.disconnect();throw error}
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["MSSQL_AGENT_TEST_PASSWORD"] != nil))
  func liveModulePreparedAlterKeepsRawConflictBaselineAndAppliesRollback() async throws {
    let password=try #require(ProcessInfo.processInfo.environment["MSSQL_AGENT_TEST_PASSWORD"])
    let connection=ODBCConnection();let profile=ServerProfile(trustCertificate:true)
    try await connection.connect(profile,password:password)
    let name="StudioModule_"+UUID().uuidString.replacingOccurrences(of:"-",with:"")
    let qualified="[dbo]."+SQL.identifier(name)
    do {
      _=try await TSQL.run("BEGIN TRANSACTION;\nGO\nCREATE PROCEDURE \(qualified) AS SELECT 1 AS [Value];",on:connection)
      let found=try await connection.execute("SELECT OBJECT_ID(\(SQL.literal(qualified)));")
      let objectID=try #require(found.results.first?.values.first?.first.flatMap {$0}.flatMap(Int.init))
      let before=try await connection.execute(Catalog.definition(objectID))
      let raw=try #require(before.results.first?.values.first?.first.flatMap {$0})
      let script="SET ANSI_NULLS ON;\nGO\nSET QUOTED_IDENTIFIER ON;\nGO\n"+(try ObjectScripts.module(raw,verb:"ALTER"))
      let edited=script.replacingOccurrences(of:"SELECT 1 AS",with:"SELECT 2 AS")
      #expect(edited != script && script != raw)
      let current=try await connection.execute(Catalog.definition(objectID))
      #expect(current.results.first?.values.first?.first.flatMap {$0} == raw)
      let applied=try await TSQL.run(edited,on:connection);#expect(!applied.partial)
      let after=try await connection.execute(Catalog.definition(objectID))
      let changed=try #require(after.results.first?.values.first?.first.flatMap {$0})
      #expect(changed.contains("SELECT 2 AS") && changed != raw && !changed.hasPrefix("SET ANSI_NULLS"))
      _=try await connection.execute("ROLLBACK TRANSACTION;")
      let removed=try await connection.execute("SELECT OBJECT_ID(\(SQL.literal(qualified)));")
      #expect(removed.results.first?.values.first?.first.flatMap {$0} == nil)
      await connection.disconnect()
    } catch {_=try? await connection.execute("IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;");await connection.disconnect();throw error}
  }

}
