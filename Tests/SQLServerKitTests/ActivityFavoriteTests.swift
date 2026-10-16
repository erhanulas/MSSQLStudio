import Foundation
import Testing
@testable import SQLServerKit

struct ActivityFavoriteTests {
  func snapshot(_ seconds:Double=0,start:String?="A",cpu:Double?=25,waiting:Int64?=3,bytes:Int64?=0,batches:Int64?=0) -> ActivityMonitoring.Snapshot {
    .init(time:Date(timeIntervalSince1970:1_800_000_000+seconds),started:start,cpu:cpu,waiting:waiting,bytes:bytes,batches:batches)
  }
  @Test func ratesUseElapsedTimeAndDoNotInventInitialZero() {
    let old=snapshot(bytes:10_485_760,batches:1000)
    let current=snapshot(5,bytes:20_971_520,batches:1100)
    let initial=ActivityMonitoring.sample(old,previous:nil)
    #expect(initial.megabytesPerSecond == nil && initial.batchesPerSecond == nil)
    let sample=ActivityMonitoring.sample(current,previous:old)
    #expect(sample.megabytesPerSecond == 2 && sample.batchesPerSecond == 20)
    #expect(sample.cpu == 25 && sample.waiting == 3 && !sample.beginsSequence)
    #expect(ActivityMonitoring.sample(snapshot(10,bytes:20_971_520,batches:1100),previous:current).batchesPerSecond == 0)
  }
  @Test func resetsMissingValuesAndClockDiscontinuitiesHaveNoRate() {
    let old=snapshot(bytes:100,batches:100)
    for current in [snapshot(5,start:"B",bytes:500,batches:500),snapshot(5,start:nil,bytes:500,batches:500),snapshot(0,bytes:500,batches:500),snapshot(-5,bytes:500,batches:500),snapshot(181,bytes:500,batches:500),snapshot(5,bytes:99,batches:99),snapshot(5,bytes:nil,batches:nil)] {
      let sample=ActivityMonitoring.sample(current,previous:old)
      #expect(sample.megabytesPerSecond == nil && sample.batchesPerSecond == nil)
    }
  }
  @Test func decodingPreservesUnavailableMetricsAndPermissionMessages() throws {
    var e=Execution();e.results=[Rows(values:[["2026-10-11T08:00:00.1234567Z","server-start","32",nil,"9007199254740993","30"]]),Rows(values:[["Bekleyen görevler","VIEW SERVER PERFORMANCE STATE izni gerekli."]])]
    let s=try ActivityMonitoring.decode(e)
    #expect(s.cpu == 32 && s.waiting == nil && s.bytes == 9_007_199_254_740_993)
    #expect(s.issues == ["Bekleyen görevler: VIEW SERVER PERFORMANCE STATE izni gerekli."])
    e.partial=true;#expect(throws:SQLFailure.self) {try ActivityMonitoring.decode(e)}
    e.partial=false;e.results=[Rows(values:[["invalid",nil,nil,nil,nil,nil]])]
    #expect(throws:SQLFailure.self) {try ActivityMonitoring.decode(e)}
    e.results=[Rows(values:[["2026-10-11T08:00:00Z",nil,"101","-1","overflow","-5"]])]
    let invalid=try ActivityMonitoring.decode(e)
    #expect(invalid.cpu == nil && invalid.waiting == nil && invalid.bytes == nil && invalid.batches == nil)
  }
  @Test func overviewKeepsIndependentMetricsAndCumulativeCounters() throws {
    let sql=ActivityMonitoring.overviewSQL
    #expect(sql.contains("process_kernel_time_ms") && sql.contains("process_user_time_ms") && sql.contains("cpu_count"))
    #expect(!sql.contains("sys.dm_os_ring_buffers"))
    #expect(sql.contains("s.is_user_process=1") && sql.contains("w.session_id<>@@SPID"))
    #expect(sql.contains("sys.dm_io_virtual_file_stats") && !sql.contains("sys.dm_os_performance_counters"))
    #expect(sql.components(separatedBy:"BEGIN CATCH").count == 9)
    #expect(sql.contains("HAS_PERMS_BY_NAME(NULL,NULL,@monitorPermission)") && sql.contains("VIEW SERVER PERFORMANCE STATE") && sql.contains("VIEW SERVER STATE"))
    #expect(sql.contains("ISNULL(r.wait_type,N'') NOT IN") && !sql.contains("last_wait_type"))
    #expect(sql.contains("s.status=N'sleeping' THEN s.open_transaction_count"))
    #expect(sql.contains("FROM sys.dm_exec_sessions s WHERE s.is_user_process=1 AND s.session_id<>@@SPID;"))
    #expect(sql.contains("physical_memory_in_use_kb)/1024.0") && sql.contains("available_physical_memory_kb)/1024.0"))
    #expect(sql.contains("grant_time IS NULL AND session_id<>@@SPID"))
    if let directory=ProcessInfo.processInfo.environment["MSSQL_ACTIVITY_SQL_DUMP"] {
      let url=URL(fileURLWithPath:directory,isDirectory:true)
      try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
      try sql.write(to:url.appendingPathComponent("overview.sql"),atomically:true,encoding:.utf8)
      try ActivityMonitoring.diagnosticsSQL.write(to:url.appendingPathComponent("diagnostics.sql"),atomically:true,encoding:.utf8)
    }
  }
  func overviewExecution(_ health:[String?]=["4","1","2","8","3","20","8192.125","4096.5","1"],io:[String?]=["100","200","500","2000"],cpu:[String?]=["6000","8"]) -> Execution {
    var result=Execution()
    result.results=[Rows(values:[["2026-10-12T10:00:00.1234567Z","engine-start",nil,"3","9007199254740993","30"]+health+io+cpu]),Rows()]
    return result
  }
  @Test func extendedOverviewPreservesCurrentHealthAndLargeCounters() throws {
    let result=try ActivityMonitoring.decode(overviewExecution())
    #expect(result.health == .init(activeRequests:4,blockedRequests:1,backupRequests:2,openTransactions:8,idleTransactions:3,userSessions:20,sqlMemoryMB:8192.125,availableMemoryMB:4096.5,memoryGrantsPending:1))
    #expect(result.reads == 100 && result.writes == 200 && result.readStallMS == 500 && result.writeStallMS == 2000)
    #expect(result.processCPUMS == 6000 && result.logicalCPUCount == 8 && result.cpu == nil)
    #expect(result.bytes == 9_007_199_254_740_993)
    #expect(ActivityMonitoring.sample(result,previous:nil).health == result.health)
    #expect(ActivityMonitoring.sample(result,previous:nil).cpu == nil)
  }
  @Test func extendedOverviewDistinguishesUnavailableFromZeroAndRetainsOtherMetrics() throws {
    var e=overviewExecution(["0",nil,"0",nil,"-1","overflow","NaN","inf",nil],io:[nil,"0","-1","oops"],cpu:[nil,"0"])
    e.results[1]=Rows(values:[["İstekler","VIEW SERVER PERFORMANCE STATE izni gerekli."],["I/O","Dosya sayacı okunamadı."]])
    let result=try ActivityMonitoring.decode(e)
    #expect(result.health.activeRequests == 0 && result.health.backupRequests == 0 && result.health.blockedRequests == nil)
    #expect(result.health.openTransactions == nil && result.health.idleTransactions == nil && result.health.userSessions == nil)
    #expect(result.health.sqlMemoryMB == nil && result.health.availableMemoryMB == nil && result.health.memoryGrantsPending == nil)
    #expect(result.reads == nil && result.writes == 0 && result.readStallMS == nil && result.writeStallMS == nil && result.logicalCPUCount == nil)
    #expect(result.waiting == 3 && result.batches == 30 && result.issues.count == 2)
  }
  @Test func overviewRejectsTruncatedMissingExtraRowsAndWrongSchemas() throws {
    let base=overviewExecution()
    var variants:[Execution]=[]
    var e=base;e.stoppedEarly=true;variants.append(e)
    e=base;e.results[1].truncated=true;variants.append(e)
    e=base;e.results.removeLast();variants.append(e)
    e=base;e.results.append(Rows());variants.append(e)
    e=base;e.results[0]=Rows(values:[Array(e.results[0].values[0].prefix(20))]);variants.append(e)
    e=base;e.results[0]=Rows(values:[e.results[0].values[0],e.results[0].values[0]]);variants.append(e)
    e=base;e.results[0].fields=[Field("wrong")];variants.append(e)
    e=base;e.results[1]=Rows(values:[["missing-message"]]);variants.append(e)
    for variant in variants {#expect(throws:SQLFailure.self) {try ActivityMonitoring.decode(variant)}}
  }
  @Test func cpuUsesProcessDeltaAndMachineLogicalCapacity() {
    var old=snapshot(cpu:99);old.processCPUMS=100_000;old.logicalCPUCount=8
    var current=snapshot(5,cpu:99);current.processCPUMS=110_000;current.logicalCPUCount=8
    #expect(ActivityMonitoring.sample(old,previous:nil).cpu == nil)
    #expect(ActivityMonitoring.sample(current,previous:old).cpu == 25)
    current.processCPUMS=100_000;#expect(ActivityMonitoring.sample(current,previous:old).cpu == 0)
    current.processCPUMS=200_000;#expect(ActivityMonitoring.sample(current,previous:old).cpu == 100)
  }
  @Test func cpuAndLatencyRejectRestartMissingResetAndTimeDiscontinuity() {
    var old=snapshot();old.processCPUMS=100;old.logicalCPUCount=4;old.reads=100;old.readStallMS=500;old.writes=200;old.writeStallMS=1000
    var current=snapshot(5);current.processCPUMS=200;current.logicalCPUCount=4;current.reads=110;current.readStallMS=550;current.writes=204;current.writeStallMS=1040
    var variants:[ActivityMonitoring.Snapshot]=[]
    var invalid=current;invalid.started="B";variants.append(invalid)
    invalid=current;invalid.started=nil;variants.append(invalid)
    for seconds in [0.0,-5,181] {invalid=current;invalid.time=old.time.addingTimeInterval(seconds);variants.append(invalid)}
    for invalid in variants {
      let sample=ActivityMonitoring.sample(invalid,previous:old)
      #expect(sample.cpu == nil && sample.readLatencyMS == nil && sample.writeLatencyMS == nil && sample.beginsSequence)
    }
    current.processCPUMS=99;current.readStallMS=499;current.writes=199
    let reset=ActivityMonitoring.sample(current,previous:old)
    #expect(reset.cpu == nil && reset.readLatencyMS == nil && reset.writeLatencyMS == nil)
    current.processCPUMS=200;current.logicalCPUCount=8;#expect(ActivityMonitoring.sample(current,previous:old).cpu == nil)
    current.logicalCPUCount=nil;#expect(ActivityMonitoring.sample(current,previous:old).cpu == nil)
    current.logicalCPUCount=4;current.processCPUMS=nil;#expect(ActivityMonitoring.sample(current,previous:old).cpu == nil)
  }
  @Test func latencyUsesPerIntervalOperationCountAndNoActivityIsUnavailable() {
    var old=snapshot();old.reads=100;old.readStallMS=500;old.writes=200;old.writeStallMS=1000
    var current=snapshot(5);current.reads=110;current.readStallMS=550;current.writes=204;current.writeStallMS=1040
    let sample=ActivityMonitoring.sample(current,previous:old)
    #expect(sample.readLatencyMS == 5 && sample.writeLatencyMS == 10)
    #expect(ActivityMonitoring.sample(old,previous:nil).readLatencyMS == nil)
    current.reads=100;current.readStallMS=500;current.writes=nil
    let idle=ActivityMonitoring.sample(current,previous:old)
    #expect(idle.readLatencyMS == nil && idle.writeLatencyMS == nil)
    current.reads=101;#expect(ActivityMonitoring.sample(current,previous:old).readLatencyMS == 0)
  }
  @Test func unavailableEngineIdentityDisablesRatesWithoutBreakingIndependentGauges() {
    let old=snapshot(start:nil,waiting:1,bytes:100,batches:100)
    var current=snapshot(5,start:nil,waiting:2,bytes:200,batches:200)
    current.health = .init(blockedRequests:2,memoryGrantsPending:1)
    let sample=ActivityMonitoring.sample(current,previous:old)
    #expect(!sample.beginsSequence && sample.waiting == 2 && sample.health.blockedRequests == 2)
    #expect(sample.megabytesPerSecond == nil && sample.batchesPerSecond == nil)
    #expect(ActivityMonitoring.sample(current,previous:nil).beginsSequence)
  }
  func diagnosticExecution() -> Execution {
    var result=Execution()
    result.results=[Rows(values:[["71","0","Sales","suspended","SELECT","60000","30","10","2","72","LCK_M_S","1",nil,nil,"SELECT N'İstanbul';"]]),Rows(values:[["71","1","Sales","running","SELECT","120000","500","30","0",nil,nil,"2",nil,nil,"SELECT 2;"]]),Rows(values:[["90","0","Sales","running","BACKUP DATABASE","100000","100","0","40",nil,"BACKUPIO","0","25.5",nil,"BACKUP DATABASE Sales TO DISK = N'backup.bak';"]]),Rows(),Rows()]
    for index in 0..<3 {result.results[index]=Rows(values:result.results[index].values.map {$0+["report_user","REPORT-APP","Reporting","1000","200","KEY: fixture"]})}
    return result
  }
  @Test func dbaIdentityAndWaitDetailsDecodeAndToolsStayReadOnly() throws {
    let diagnostics=try ActivityMonitoring.decodeDiagnostics(diagnosticExecution())
    let request=try #require(diagnostics.blocked.first)
    #expect(request.login=="report_user" && request.host=="REPORT-APP" && request.program=="Reporting")
    #expect(request.logicalReads==1000 && request.waitMS==200 && request.waitResource=="KEY: fixture")
    for tool in ActivityMonitoring.DBATool.allCases {
      #expect(tool.sql.contains("TOP (100)") && tool.sql.contains("@canMonitor=0 THROW"))
      #expect(!tool.sql.contains("KILL ") && !tool.sql.contains("DBCC ") && !tool.sql.contains("sys.dm_exec_query_plan"))
    }
    #expect(!ActivityMonitoring.overviewSQL.contains("Batch hızı") && !ActivityMonitoring.overviewSQL.contains("sys.dm_os_performance_counters"))
  }
  @Test func diagnosticsDecodeCategoriesRequestIdentityAndBackupProgress() throws {
    let result=try ActivityMonitoring.decodeDiagnostics(diagnosticExecution())
    #expect(result.blocked.count == 1 && result.longRunning.count == 1 && result.backups.count == 1)
    #expect(result.blocked[0].id == "71:0" && result.longRunning[0].id == "71:1")
    #expect(result.blocked[0].blocker == 72 && result.blocked[0].wait == "LCK_M_S" && result.blocked[0].sql == "SELECT N'İstanbul';")
    #expect(result.longRunning[0].reads == 30 && result.longRunning[0].openTransactions == 2)
    #expect(result.backups[0].percentComplete == 25.5 && result.backups[0].remainingMS == nil && result.backups[0].elapsedMS == 100000)
  }
  @Test func diagnosticsPreserveOtherCategoriesAndPermissionFailures() throws {
    var e=diagnosticExecution();e.results[0]=Rows();e.results[4]=Rows(values:[["Bloklanan istekler","VIEW SERVER STATE izni gerekli."]])
    let result=try ActivityMonitoring.decodeDiagnostics(e)
    #expect(result.blocked.isEmpty && result.longRunning.count == 1 && result.backups.count == 1 && result.issues.count == 1)
    e.results[2]=Rows(values:[["90","0",nil,nil,nil,"-1","NaN","overflow",nil,"-5",nil,"-2","101",nil,String(repeating:"🙂",count:2200),nil,nil,nil,nil,nil,nil]])
    let invalid=try ActivityMonitoring.decodeDiagnostics(e).backups[0]
    #expect(invalid.elapsedMS == nil && invalid.cpuMS == nil && invalid.reads == nil && invalid.blocker == nil && invalid.openTransactions == nil && invalid.percentComplete == nil)
    #expect(invalid.sql.count == 2000)
  }
  @Test func diagnosticsRejectPartialWrongSchemaDuplicateIdentityAndOversizedResults() throws {
    let base=diagnosticExecution()
    var variants:[Execution]=[]
    var e=base;e.partial=true;variants.append(e)
    e=base;e.stoppedEarly=true;variants.append(e)
    e=base;e.results[2].truncated=true;variants.append(e)
    e=base;e.results.removeLast();variants.append(e)
    e=base;e.results.append(contentsOf:[Rows(),Rows()]);variants.append(e)
    e=base;e.results[0].fields=[Field("wrong")];variants.append(e)
    e=base;e.results[0]=Rows(values:[["1","0"]]);variants.append(e)
    e=base;var row=e.results[0].values[0];row[0]="0";e.results[0]=Rows(values:[row]);variants.append(e)
    e=base;e.results[0]=Rows(values:[e.results[0].values[0],e.results[0].values[0]]);variants.append(e)
    e=base;e.results[1]=Rows(values:(0..<31).map {index in var row=e.results[1].values[0];row[1]=String(index);return row});variants.append(e)
    for variant in variants {#expect(throws:SQLFailure.self) {try ActivityMonitoring.decodeDiagnostics(variant)}}
  }
  @Test func diagnosticsSQLUsesBoundedCurrentStatementReadsAndIndependentCategories() {
    let sql=ActivityMonitoring.diagnosticsSQL
    #expect(sql.components(separatedBy:"SELECT TOP(30)").count == 5 && sql.components(separatedBy:"BEGIN CATCH").count == 6)
    #expect(sql.contains("r.total_elapsed_time>=30000") && sql.contains("r.blocking_session_id>0"))
    #expect(sql.contains("IF @canMonitor=0 THROW") && !sql.contains("last_wait_type"))
    #expect(sql.contains("SUBSTRING(CONVERT(varbinary(max),t.text),r.statement_start_offset+1") && sql.contains("r.statement_end_offset-r.statement_start_offset+2"))
    #expect(sql.contains("COLLATE Latin1_General_100_CI_AS_SC,2000)") && sql.contains("sql_text nvarchar(4000)"))
    #expect(sql.contains("r.reads,r.writes") && sql.contains("THEN r.percent_complete ELSE NULL END"))
    #expect(!sql.contains("estimated_completion_time") && !sql.contains("dm_exec_query_plan") && !sql.contains("CREATE TABLE") && !sql.contains("KILL "))
    #expect(sql.contains("WHILE @depth<7") && sql.contains("SET @capacity=60-") && sql.contains("TOP(@capacity)"))
    #expect(sql.contains("SELECT TOP(4) q.*,COUNT_BIG(*) OVER() AS request_count"))
    #expect(sql.contains("r.request_id IS NULL") && sql.contains("c.most_recent_sql_handle") && sql.contains("N'recent'"))
  }
  func blockingRow(_ session:String="72",request:String?=nil,count:String="0",blocker:String?=nil,source:String="recent",sql:String="UPDATE dbo.Items SET Value=N'🙂';") -> [String?] {
    [session,request,count,"Sales",request == nil ? "sleeping":"suspended",request == nil ? nil:"SELECT",blocker,"LCK_M_S","5000","KEY: 5:123","2","app_user","ERP-01","ERP",source,sql]
  }
  @Test func blockerContextPreservesSleepingHeadCurrentRequestAndUnicode() throws {
    var e=diagnosticExecution()
    let sql="-- 🙂\nSELECT N'İstanbul';"
    e.results[3]=Rows(values:[blockingRow("72",request:"4",count:"1",blocker:"63",source:"current",sql:sql),blockingRow("63")])
    let d=try ActivityMonitoring.decodeDiagnostics(e)
    #expect(d.blockingContexts.count == 2)
    let current=d.blockingContexts[0],head=d.blockingContexts[1]
    #expect(current.id == "72:4" && current.blocker == 63 && current.sqlSource == .current && current.sql == sql)
    #expect(current.waitMS == 5000 && current.waitResource == "KEY: 5:123")
    #expect(head.requestID == nil && head.requestCount == 0 && head.status == "sleeping" && head.sqlSource == .recent && head.openTransactions == 2)
    #expect(head.login == "app_user" && head.host == "ERP-01" && head.program == "ERP")
    let chain=d.blockingChain(for:d.blocked[0])
    #expect(chain.sessionIDs == [63,72,71] && chain.termination == .root && chain.notice == nil)
  }
  @Test func malformedBlockerResultsNeverBecomeCompleteChains() throws {
    var base=diagnosticExecution();base.results[3]=Rows(values:[blockingRow()])
    var variants:[Execution]=[]
    var e=base;e.results[3].truncated=true;variants.append(e)
    e=base;e.results[3].fields=[Field("wrong")];variants.append(e)
    for row in [blockingRow("0"),blockingRow(request:"0",count:"0",source:"current"),blockingRow(count:"1"),blockingRow(source:"invented"),blockingRow(request:"0",count:"2",source:"current")] {
      e=base;e.results[3]=Rows(values:[row]);variants.append(e)
    }
    e=base;e.results[3]=Rows(values:[blockingRow(),blockingRow()]);variants.append(e)
    e=base;e.results[3]=Rows(values:(1...61).map {blockingRow(String($0))});variants.append(e)
    for variant in variants {#expect(throws:SQLFailure.self) {try ActivityMonitoring.decodeDiagnostics(variant)}}
  }
  @Test func chainsDetectMissingCycleAmbiguitySpecialOwnerAndDepthLimits() {
    let leaf=ActivityMonitoring.Request(sessionID:100,requestID:0,blocker:90)
    func node(_ id:Int64,_ parent:Int64?,request:Int64=0,count:Int64=1) -> ActivityMonitoring.BlockingContext {
      .init(sessionID:id,requestID:request,requestCount:count,blocker:parent,sqlSource:.current)
    }
    var d=ActivityMonitoring.Diagnostics()
    #expect(d.blockingChain(for:leaf).termination == .missing(90))
    d.blockingContexts=[node(90,80),node(80,90)]
    let cycle=d.blockingChain(for:leaf)
    #expect(cycle.sessionIDs == [80,90,100] && cycle.termination == .cycle(90) && cycle.notice?.contains("deadlock kanıtı değildir") == true)
    d.blockingContexts=[node(90,80,count:2),node(90,70,request:1,count:2)]
    #expect(d.blockingChain(for:leaf).termination == .ambiguous(90))
    d.blockingContexts=[node(90,-2)]
    #expect(d.blockingChain(for:leaf).termination == .special(-2))
    d.blockingContexts=[node(90,80,count:5)]
    #expect(d.blockingChain(for:leaf).termination == .requestLimit(90))
    d.blockingContexts=(0..<10).map {node(90-Int64($0),89-Int64($0))}
    let deep=d.blockingChain(for:leaf)
    #expect(deep.sessionIDs.count == 9 && deep.termination == .depthLimit)
    d.blockingContexts=[node(90,100)]
    #expect(d.blockingChain(for:leaf).termination == .cycle(100))
  }
  @Test func marsRequestsWithCommonParentRetainAllSQLInsteadOfChoosingOne() throws {
    var e=diagnosticExecution()
    e.results[3]=Rows(values:[blockingRow("72",request:"0",count:"2",blocker:"63",source:"current",sql:"SELECT 1;"),blockingRow("72",request:"1",count:"2",blocker:"63",source:"current",sql:"SELECT 2;"),blockingRow("63",source:"unavailable",sql:"")])
    let d=try ActivityMonitoring.decodeDiagnostics(e)
    #expect(d.blockingContexts.filter {$0.sessionID == 72}.map(\.sql) == ["SELECT 1;","SELECT 2;"])
    #expect(d.blockingChain(for:d.blocked[0]).sessionIDs == [63,72,71])
    #expect(d.blockingContexts.last?.sqlSource == .unavailable)
  }
  @Test func favoritesMatchProfileIdentityAndExactDatabase() throws {
    let a=UUID(),b=UUID()
    let global=try FavoriteQuery(name:" Genel ",sql:"SELECT N'İstanbul';",scope:.global,serverID:a,database:"DB")
    #expect(global.name == "Genel" && global.serverID == nil && global.database == nil)
    #expect(global.visible(serverID:nil,database:nil) && global.visible(serverID:b,database:"Other"))
    let connection=try FavoriteQuery(name:"Server",sql:"SELECT 1",scope:.connection,serverID:a,database:"Ignored")
    #expect(connection.database == nil && connection.visible(serverID:a,database:"Other"))
    #expect(!connection.visible(serverID:b,database:"DB"))
    let db=try FavoriteQuery(name:"DB",sql:"SELECT 1",scope:.database,serverID:a,database:" Sales ")
    #expect(db.database == "Sales" && db.visible(serverID:a,database:"Sales"))
    #expect(!db.visible(serverID:a,database:"sales") && !db.visible(serverID:b,database:"Sales"))
  }
  @Test func invalidFavoritesCannotBeSaved() {
    for args in [("","SELECT 1",FavoriteQuery.Scope.global,nil as UUID?,nil as String?),("Name"," ",.global,nil,nil),("Name","SELECT 1",.connection,nil,nil),("Name","SELECT 1",.database,UUID(),"  "),(String(repeating:"x",count:121),"SELECT 1",.global,nil,nil)] {
      #expect(throws:SQLFailure.self) {try FavoriteQuery(name:args.0,sql:args.1,scope:args.2,serverID:args.3,database:args.4)}
    }
  }
  @Test func storeRoundTripsUpdatesRemovesAndRestrictsFilePermissions() async throws {
    let dir=URL(fileURLWithPath:"/tmp/favorite-tests-\(UUID())")
    defer {try? FileManager.default.removeItem(at:dir)}
    let url=dir.appendingPathComponent("favorites.json"),store=FavoriteQueryStore(url:url)
    #expect(try await store.load().isEmpty)
    var f=try FavoriteQuery(name:"Sales",sql:"-- unchanged\nSELECT N'İstanbul', 999999999999.12345678;",scope:.database,serverID:UUID(),database:"Sales")
    #expect(try await store.save(f) == [f])
    f.name="Daily Sales";f.sql+="\nGO\nSELECT NULL;"
    #expect(try await store.save(f) == [f])
    #expect(try await FavoriteQueryStore(url:url).load() == [f])
    #expect((try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try await store.remove(f.id).isEmpty)
  }
  @Test func malformedStoreIsNotOverwritten() async throws {
    let url=URL(fileURLWithPath:"/tmp/favorite-bad-\(UUID()).json")
    defer {try? FileManager.default.removeItem(at:url)}
    let data=Data("invalid existing JSON".utf8);try data.write(to:url)
    let f=try FavoriteQuery(name:"New",sql:"SELECT 1",scope:.global)
    await #expect(throws:(any Error).self) {try await FavoriteQueryStore(url:url).save(f)}
    #expect(try Data(contentsOf:url) == data)
  }
  @Test func activeRequestsDecodeIncludesBackupsWithSeparateIdentityAndReadBudget() throws {
    var execution=diagnosticExecution()
    let active=Array(execution.results[1].values)+Array(execution.results[2].values)
    execution.results.insert(Rows(values:active.map {$0+["2026-10-16 12:00:00.000","2026-10-16 12:01:00.000"]}),at:4)
    let decoded=try ActivityMonitoring.decodeDiagnostics(execution)
    #expect(decoded.active.count==2 && decoded.backups.count==1)
    let query=try #require(decoded.active.first {$0.command=="SELECT"})
    let backup=try #require(decoded.active.first {$0.command=="BACKUP DATABASE"})
    #expect(ActivityRequestTermination.canTerminate(query) && !ActivityRequestTermination.canTerminate(backup))
    #expect(throws:SQLFailure.self) {try ActivityRequestTermination.sql(for:backup)}
    #expect(ActivityMonitoring.diagnosticsSQL.contains("Aktif sorgular") && ActivityMonitoring.diagnosticsSQL.contains("category=3"))
    #expect(try ActivityMonitoring.decodeDiagnostics(diagnosticExecution()).active.isEmpty)
  }

}
