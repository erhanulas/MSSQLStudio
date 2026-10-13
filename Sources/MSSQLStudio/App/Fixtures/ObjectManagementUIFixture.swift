import AppKit
import SQLServerKit
import SwiftUI

@MainActor enum ObjectManagementUIFixture {
  static func catalog(_ sql:String) -> Execution {
    if sql == DatabaseFilesMonitoring.inventorySQL || sql.hasPrefix(DatabaseFilesMonitoring.detailSQL.components(separatedBy:"FROM sys.database_files")[0]) {
      return DatabaseFilesUIFixture.catalog(sql)
    }
    var e=Execution()
    if sql == ActivityMonitoring.overviewSQL {
      let time=Date();let ticks=Int64(time.timeIntervalSince1970)
      let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
      let columns=["sampled_at","started_at","cpu_percent","waiting_tasks","io_bytes","batch_requests","active_requests","blocked_requests","backup_requests","open_transactions","idle_transactions","user_sessions","sql_memory_mb","available_memory_mb","memory_grants_pending","io_reads","io_writes","read_stall_ms","write_stall_ms","process_cpu_ms","logical_cpu_count"]
      let values:[String?]=[f.string(from:time),"fixture-start",nil,String(2+ticks%4),String(ticks*2_097_152),String(ticks*25),String(6+ticks%4),"2","1","5","2","48",String(6144+ticks%4*64),"32768",String(ticks%2),String(ticks*320),String(ticks*80),String(ticks*640),String(ticks*400),String(ticks*3200),"8"]
      e.results=[Rows(fields:columns.map {Field($0)},values:[values]),Rows(values:[])]
    } else if sql == ActivityMonitoring.diagnosticsSQL {
      let columns=["session_id","request_id","database_name","status","command","elapsed_ms","cpu_ms","reads","writes","blocker","wait_type","open_transactions","percent_complete","remaining_ms","sql_text"]
      func rows(_ values:[[String?]]) -> Rows {Rows(fields:columns.map {Field($0)},values:values)}
      e.results=[rows([
        ["71","0","DemoDB","suspended","SELECT","185000","4000","4500","0","63","LCK_M_S","1",nil,nil,"SELECT CustomerID, Name FROM dbo.Customers WHERE City = N'İstanbul';"],
        ["72","0","DemoDB","suspended","UPDATE","92000","1800","2300","15","71","LCK_M_U","1",nil,nil,"UPDATE dbo.Orders SET Status = N'Processing' WHERE OrderID = 1024;"]
      ]),rows([
        ["84","0","Reporting","running","SELECT","125000","48000","980000","0","0","PAGEIOLATCH_SH","0",nil,nil,"SELECT CustomerID, SUM(Amount) AS TotalAmount\nFROM dbo.OrderHistory\nGROUP BY CustomerID;"]
      ]),rows([
        ["91","0","DemoDB","suspended","BACKUP DATABASE","142000","800","740000","0","0","ASYNC_IO_COMPLETION","0","64.5",nil,"BACKUP DATABASE [DemoDB] TO DISK = N'/offline-fixture/DemoDB.bak' WITH COMPRESSION;"]
      ]),Rows(fields:["session_id","request_id","request_count","database_name","status","command","blocker","wait_type","wait_ms","wait_resource","open_transactions","login_name","host_name","program_name","sql_source","sql_text"].map {Field($0)},values:[
        ["63",nil,"0","DemoDB","sleeping",nil,nil,nil,nil,nil,"1","erp_user","ERP-APP","Order Service","recent","BEGIN TRANSACTION;\nUPDATE dbo.Customers SET Name = N'İstanbul' WHERE CustomerID = 10;\n-- Transaction henüz kapatılmadı."],
        ["71","0","1","DemoDB","suspended","SELECT","63","LCK_M_S","185000","KEY: 5:720575940000 (offline)","1","report_user","REPORT-APP","Reporting","current","SELECT CustomerID, Name FROM dbo.Customers WHERE City = N'İstanbul';"]
      ]),Rows(values:[])]
    } else if sql == Catalog.databases {
      e.results=[Rows(values:[["1","master","","ONLINE"],["5","DemoDB","","ONLINE"],["6","Reporting","","ONLINE"]])]
    } else if sql.contains("StudioAgent.history") {
      let id="00000000-0000-0000-0000-000000000027"
      var values:[[String?]]=[
        ["30","Demo Nightly","0","(Job outcome)","0","2026-10-10 21:00:00","0:02:05","Synthetic job failed. Expand the run to inspect every step.",id,"30","0","0","0","Test Server"],
        ["29","Demo Nightly","2","Import sample","0","2026-10-10 21:01:00","0:01:05","Synthetic error 50000. Import could not complete.\nThis is a multiline message for the details pane.",id,"30","16","50000","2","Test Server"],
        ["28","Demo Nightly","2","Import sample","2","2026-10-10 21:00:40","0:00:05","Retrying synthetic operation.",id,"30","16","50000","1","Test Server"],
        ["27","Demo Nightly","1","Read sample","1","2026-10-10 21:00:00","0:00:02","Synthetic read completed successfully.",id,"30","0","0","0","Test Server"],
        ["20","Demo Nightly","0","(Job outcome)","1","2026-10-09 21:00:00","0:00:02","Synthetic test completed successfully.",id,"20","0","0","0","Test Server"]]
      if !sql.contains("OR (h.step_id>0") {values=values.filter {$0[2] == "0"}}
      if sql.contains("h.run_status=0") {values=values.filter {$0[9] == "30"}}
      if sql.contains("h.run_status=1") {values=values.filter {$0[9] == "20"}}
      e.results=[Rows(values:values)]
    } else if sql.contains("StudioAgent.jobs") {
      e.results=[Rows(values:[["00000000-0000-0000-0000-000000000027","Demo Nightly","0","Synthetic UI test job","test-owner","Idle","2026-10-09T20:00:00.000","[Uncategorized (Local)]","2026-10-01T12:00:00.000","1","2","Test Operator","2","0","2026-10-10 21:00:00","0","2026-10-11 21:00:00","5"]])]
      if sql.contains("StudioAgent.details") {e.results += [Rows(values:[
        ["1","Read sample","TSQL","master","SELECT N'İstanbul';","3","0","2","0","0","0","","0",""],
        ["2","Import sample","TSQL","DemoDB","SELECT 2;","1","0","2","0","2","1","","4",""]]),
        Rows(values:[["27","Daily test","0","8","210000","10","1","0","1","1","20261001","99991231","235959","3","2026-10-09T20:00:00.000","2"]])]}
    } else if sql.contains("StudioAgent.schedule") {
      e.results=[Rows(values:[["27","Daily test","0","8","210000","10","1","0","1","1","20261001","99991231","235959","3","2026-10-09T20:00:00.000","2"],["28","Existing shared","1","4","090000","1","1","0","1","1","20261001","99991231","235959","1","2026-10-09T20:00:00.000","1"]])]
    } else if sql.contains("FROM msdb.dbo.sysjobs j ORDER BY j.name") {e.results=[Rows(values:[["0","Demo Nightly","","Disabled, Idle"]])]}
    else if sql.contains("FROM msdb.dbo.sysschedules ORDER BY") {e.results=[Rows(values:[["27","Daily test","","Disabled"]])]}
    else if sql.contains("sys.dm_server_services") {e.results=[Rows(values:[["SQL Server Agent (Synthetic)","Stopped","Disabled","2026-10-09"]])]}
    else if sql.contains("SELECT t.name,COALESCE") {
      let db=sql.contains("=1007"),disabled=sql.contains("=1006") || db
      e.results=[Rows(values:[[db ? "DDLGuard" : disabled ? "TR_CustomersAudit" : "TR_Customers",db ? "" : "dbo",db ? "0" : "1",db ? "" : "[dbo].[Customers]",disabled ? "1" : "0"]])]
    } else if sql.contains("FROM sys.triggers WHERE parent_id") {
      e.results=[Rows(values:[["1005","TR_Customers","dbo","SQL_TRIGGER, Enabled"],["1006","TR_CustomersAudit","dbo","SQL_TRIGGER, Disabled"]])]
    } else if sql.contains("p.parameter_id,p.name") {
      e.results=[Rows(values:sql.contains("=1003") ? [["1","@City","nvarchar(50)","0","0"],["2","@Count","int","1","0"]] : [["1","@City","nvarchar(50)","0","0"]])]
    } else if sql.contains("SELECT base_object_name") {e.results=[Rows(values:[["[dbo].[Customers]"]])]}
    else if sql.contains("t.parent_class_desc") {
      let db=sql.contains("=1007"),disabled=sql.contains("=1006") || db
      e.results=[Rows(fields:[Field("Name"),Field("State"),Field("Scope"),Field("Parent")],values:[[db ? "DDLGuard" : disabled ? "TR_CustomersAudit" : "TR_Customers",disabled ? "Disabled" : "Enabled",db ? "DATABASE" : "OBJECT_OR_COLUMN",db ? nil : "Customers"]])]
    }
    else if sql.contains("OBJECT_DEFINITION(1003)") {e.results=[Rows(values:[["CREATE PROCEDURE [dbo].[SalesByCity] @City nvarchar(50), @Count int OUTPUT AS BEGIN SELECT @City AS [City]; SET @Count=1; END;"]])]}
    else if sql.contains("OBJECT_DEFINITION(1004)") {e.results=[Rows(values:[["CREATE FUNCTION [dbo].[CityLabel] (@City nvarchar(50)) RETURNS nvarchar(50) AS BEGIN RETURN UPPER(@City); END;"]])]}
    else if sql.contains("OBJECT_DEFINITION(1008)") {e.results=[Rows(values:[["CREATE FUNCTION [dbo].[CityRows] (@City nvarchar(50)) RETURNS TABLE AS RETURN (SELECT @City AS [City]);"]])]}
    else if sql.contains("OBJECT_DEFINITION(1007)") {e.results=[Rows(values:[["CREATE TRIGGER [DDLGuard] ON DATABASE FOR CREATE_TABLE AS BEGIN SET NOCOUNT ON; END;"]])]}
    else if sql.contains("OBJECT_DEFINITION(1005)") || sql.contains("OBJECT_DEFINITION(1006)") {e.results=[Rows(values:[["CREATE TRIGGER [dbo].[TR_Customers] ON [dbo].[Customers] AFTER INSERT AS BEGIN SET NOCOUNT ON; END;"]])]}
    else     if sql.contains("sys.computed_columns") {
      e.results=[Rows(values:[
        ["1","Id","int","0","1","1","1",nil,nil,nil,nil,nil,"0","0","0"],
        ["2","Name","nvarchar(100)","0","0",nil,nil,nil,nil,nil,nil,"Latin1_General_100_CI_AS","0","0","0"],
        ["3","Active","bit","0","0",nil,nil,nil,nil,"DF_Active","((1))",nil,"0","0","0"],
        ["4","Version","timestamp","0","0",nil,nil,nil,nil,nil,nil,nil,"0","0","0"]
      ]),Rows(values:[["Id","PK_Customers"]]),Rows(values:[["PK_Customers","PK","ALTER TABLE [dbo].[Customers] ADD CONSTRAINT [PK_Customers] PRIMARY KEY ([Id]);"],["IX_Name","INDEX","CREATE INDEX [IX_Name] ON [dbo].[Customers] ([Name]);"]]),Rows(),Rows(values:[["CK_Id","CHECK","ALTER TABLE [dbo].[Customers] ADD CONSTRAINT [CK_Id] CHECK ([Id]>0);"]]),Rows(),Rows(values:[["0",nil]])]
    } else if sql.contains("SELECT TOP (200)") {
      e.results=[Rows(fields:[Field("Id"),Field("Name"),Field("Active"),Field("Version")],values:[["1","Example One","1","0x0000000000000001"],["2","Example Two","0","0x0000000000000002"]])]
    } else if sql.contains("OBJECT_DEFINITION") { e.results=[Rows(values:[["CREATE VIEW [dbo].[ActiveCustomers] AS SELECT [Id],[Name] FROM [dbo].[Customers] WHERE [Active]=1;"]])] }
    else if sql.contains("uses_ansi_nulls") { e.results=[Rows(values:[["1","1"]])] }
    else if sql.contains("HAS_PERMS_BY_NAME") { e.results=[Rows(fields:[Field("Name"),Field("Schema"),Field("Type"),Field("Created")],values:[["Customers","dbo","USER_TABLE","2026-10-09T10:00:00"]]),Rows(values:[["dbo","SELECT","GRANT"]])] }
    else if sql.contains("sys.sql_expression_dependencies") { e.results=[Rows(values:[["dbo.ActiveCustomers","dbo.Customers"]])] }
    else if sql.contains("SELECT c.name") { e.results=[Rows(values:[["Id"],["Name"],["Active"]])] }
    else if sql.contains("SELECT object_id") { e.results=[Rows(values:[[sql.contains("usp_GetCustomerDetails") || sql.contains("SalesByCity") ? "1003":"1001"]])] }
    return e
  }
}


