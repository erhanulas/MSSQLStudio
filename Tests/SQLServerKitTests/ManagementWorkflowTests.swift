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
  @Test func jobCommandsUseValidatedGUIDAndPreserveSharedSchedules() throws {
    let id=UUID().uuidString
    #expect(try SQLAgent.command(.enable,id:id).contains("@enabled=1"))
    #expect(try SQLAgent.command(.disable,id:id).contains("@enabled=0"))
    #expect(try SQLAgent.command(.start,id:id).contains("sp_start_job"))
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
    #expect(!SQLAgent.history(includeSteps:true).contains("AND h.step_id=0"))
    var data=Execution();data.results=[Rows(values:[["123","Test","0","(Job outcome)","1","2026-10-09 21:00:00","127:04:03","İş tamamlandı"]])]
    let row=try #require(SQLAgent.decodeHistory(data).first)
    #expect(row.duration == "127:04:03" && row.statusLabel == "Succeeded" && row.message == "İş tamamlandı")
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
