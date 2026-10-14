import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

extension WorkbenchController {
  @objc func designTableObject() { showManagedTable(contextNode) }
  @objc func designViewObject() { showManagedView(contextNode) }
  @objc func newManagedTable() { showManagedTable(contextNode,create:true) }
  @objc func newManagedView() { showManagedView(contextNode,create:true) }
  @objc func editObjectData() { showManagedData(contextNode) }
  @objc func deleteManagedObject() { showManagedDelete(contextNode) }
  @objc func renameManagedObject() { showManagedRename(contextNode) }
  @objc func managedObjectProperties() { showManagedProperties(contextNode) }
  @objc func manageObjectIndexes() { showManagedTable(contextNode,initialKind:"INDEX") }
  @objc func manageObjectRelationships() { showManagedTable(contextNode,initialKind:"FK") }
  @objc func manageObjectChecks() { showManagedTable(contextNode,initialKind:"CHECK") }
  @objc func modifyManagedModule() { if let node=contextNode {scriptManagedObject(node,mode:"MODIFY",destination:"New Query Editor Window")} }
  @objc func invokeManagedRoutine() {showRoutineInvocation(contextNode)}
  @objc func enableManagedTrigger() {stageTriggerState(contextNode,enabled:true)}
  @objc func disableManagedTrigger() {stageTriggerState(contextNode,enabled:false)}
  @objc func newManagedProcedure() {stageNewModule(contextNode,kind:"PROCEDURE")}
  @objc func newManagedScalarFunction() {stageNewModule(contextNode,kind:"SCALAR FUNCTION")}
  @objc func newManagedTableFunction() {stageNewModule(contextNode,kind:"TABLE FUNCTION")}
  @objc func newManagedTrigger() {stageNewModule(contextNode,kind:"TRIGGER")}
  @objc func newManagedSynonym() {showSynonymDesigner(contextNode,create:true)}
  @objc func editManagedSynonym() {showSynonymDesigner(contextNode)}
  @objc func manageChildStructure() {showChildStructure(contextNode)}
  @objc func rebuildManagedIndex() {stageStructureAction(contextNode,action:"REBUILD")}
  @objc func reorganizeManagedIndex() {stageStructureAction(contextNode,action:"REORGANIZE")}
  @objc func disableManagedIndex() {stageStructureAction(contextNode,action:"DISABLE")}
  @objc func checkManagedConstraint() {stageStructureAction(contextNode,action:"CHECK")}
  @objc func disableManagedConstraint() {stageStructureAction(contextNode,action:"NOCHECK")}
  @objc func scriptManagedMenu(_ sender:NSMenuItem) {
    guard let node=contextNode, let request=sender.representedObject as? [String], request.count == 2 else { return }
    scriptManagedObject(node,mode:request[0],destination:request[1])
  }
  @objc func objectDependencies() {
    guard let node = contextNode, let item = node.item else { return }
    state.newQuery(server: node.server, database: node.database,
      text: "SELECT OBJECT_SCHEMA_NAME(referencing_id) AS [Schema], OBJECT_NAME(referencing_id) AS [Object], referenced_schema_name, referenced_entity_name FROM sys.sql_expression_dependencies WHERE referencing_id=\(item.id) OR referenced_id=\(item.id);",
      title: "Dependencies · " + item.name, run: true)
  }
  @objc func objectProperties() {
    guard let node = contextNode, let item = node.item, case .object(let folder) = node.kind else {
      return
    }
    let sql: String
    switch folder {
    case .jobs:
      sql =
        "SELECT name,enabled,description,date_created,date_modified FROM msdb.dbo.sysjobs WHERE name=\(SQL.literal(item.name)); SELECT s.step_id,s.step_name,s.subsystem,s.database_name,s.command FROM msdb.dbo.sysjobsteps s JOIN msdb.dbo.sysjobs j ON j.job_id=s.job_id WHERE j.name=\(SQL.literal(item.name)) ORDER BY s.step_id;"
    case .logins, .roles:
      sql =
        "SELECT name,type_desc,is_disabled,default_database_name,create_date,modify_date FROM sys.server_principals WHERE principal_id=\(item.id);"
    case .users:
      sql =
        "SELECT name,type_desc,default_schema_name,authentication_type_desc,create_date,modify_date FROM sys.database_principals WHERE principal_id=\(item.id);"
    case .linkedServers:
      sql =
        "SELECT name,product,provider,data_source,is_data_access_enabled,is_rpc_out_enabled FROM sys.servers WHERE server_id=\(item.id);"
    case .schedules: sql = "SELECT * FROM msdb.dbo.sysschedules WHERE schedule_id=\(item.id);"
    default: return
    }
    state.newQuery(
      server: node.server, database: node.database, text: sql, title: item.name, run: true)
  }
  private func jobScript(_ action: String) {
    guard let node = contextNode, let item = node.item else { return }
    stage(
      "USE [msdb];\nEXEC dbo.\(action) @job_name=\(SQL.literal(item.name));",
      title: action + " · " + item.name)
  }
  @objc private func startJob() { jobScript("sp_start_job") }
  @objc private func stopJob() { jobScript("sp_stop_job") }
  @objc private func enableJob() {
    if let item = contextNode?.item {
      stage(
        "USE [msdb];\nEXEC dbo.sp_update_job @job_name=\(SQL.literal(item.name)), @enabled=1;",
        title: "Enable Job")
    }
  }
  @objc private func disableJob() {
    if let item = contextNode?.item {
      stage(
        "USE [msdb];\nEXEC dbo.sp_update_job @job_name=\(SQL.literal(item.name)), @enabled=0;",
        title: "Disable Job")
    }
  }
  @objc func newQueryAtNode() {
    if let node = contextNode {
      let name = Self.queryDatabase(for: node)
      openNewQuery(server: node.server, database: name)
    }
  }
  @objc func refreshContextNode() { if let node = contextNode { refreshExplorerScope(node) } }
  @objc func refreshContextParent() {if let node=contextNode?.parent {refresh(node)}}
  @objc func selectRows() {
    if let node = contextNode, let item = node.item {
      state.newQuery(
        server: node.server, database: node.database,
        text: "SELECT TOP (1000) *\nFROM \(item.qualified);", title: item.name, run: true)
    }
  }
  func stage(_ sql: String, title: String) {
    if let node = contextNode {
      state.newQuery(server: node.server, database: node.database, text: sql, title: title)
    } else if let server = selectedServer {
      state.newQuery(server: server, database: selectedDatabase, text: sql, title: title)
    }
  }
  @objc private func scriptSelect() {
    if let item = contextNode?.item {
      stage("SELECT TOP (1000) *\nFROM \(item.qualified);", title: "SELECT \(item.name)")
    }
  }
  @objc private func scriptInsert() { scriptColumns(operation: "INSERT") }
  @objc private func scriptUpdate() { scriptColumns(operation: "UPDATE") }
  @objc private func scriptDelete() {
    if let item = contextNode?.item {
      stage(
        "-- Önce WHERE koşulunu belirleyin.\nDELETE FROM \(item.qualified)\nWHERE 1 = 0;",
        title: "DELETE \(item.name)")
    }
  }
  private func scriptColumns(operation: String) {
    guard let node = contextNode, let item = node.item else { return }
    Task { [weak self] in
      guard let self else { return }
      do {
        let columns = Catalog.rows(
          try await node.server.catalog(
            Catalog.children(.columns, object: item.id), database: node.database)
        ).filter {
          !$0.detail.contains("identity") && !$0.detail.contains("computed")
            && !$0.detail.hasPrefix("timestamp") && !$0.detail.hasPrefix("rowversion")
        }
        let sql =
          operation == "INSERT"
          ? "INSERT INTO \(item.qualified) (\(columns.map { SQL.identifier($0.name) }.joined(separator:", ")))\nVALUES (\(columns.map { _ in "NULL" }.joined(separator:", ")));"
          : "-- Değerleri ve WHERE koşulunu belirleyin.\nUPDATE \(item.qualified)\nSET \(columns.map { SQL.identifier($0.name)+" = NULL" }.joined(separator:",\n    "))\nWHERE 1 = 0;"
        state.newQuery(
          server: node.server, database: node.database, text: sql,
          title: "\(operation) \(item.name)")
      } catch { state.showError(error.localizedDescription) }
    }
  }
  @objc func copyNodeName() {
    if let node = contextNode {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(node.item?.qualified ?? node.title, forType: .string)
    }
  }
}
extension WorkbenchController {
  @objc private func tableProperties() {
    if let item = contextNode?.item {
      stage(
        "SELECT c.name,t.name AS type,c.max_length,c.precision,c.scale,c.is_nullable,c.is_identity FROM sys.columns c JOIN sys.types t ON t.user_type_id=c.user_type_id WHERE c.object_id=\(item.id);\nSELECT name,type_desc,is_unique,is_primary_key,is_disabled FROM sys.indexes WHERE object_id=\(item.id);",
        title: "Properties \(item.name)")
      state.active?.changed?()
    }
  }
  @objc func databaseProperties() {
    guard let node = contextNode else { return }
    present(ExplorerDatabasePanel(server:node.server,database:node.database),title:"Veritabanı bilgileri · \(node.database)",width:760,height:620,identity:"database-info|\(node.server.id)|\(node.database)")
  }
  @objc private func createTable() {
    stage(
      "CREATE TABLE [dbo].[NewTable]\n(\n    [Id] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_NewTable] PRIMARY KEY,\n    [Name] nvarchar(200) NOT NULL,\n    [CreatedAt] datetime2(7) NOT NULL CONSTRAINT [DF_NewTable_CreatedAt] DEFAULT SYSUTCDATETIME()\n);",
      title: "Create Table")
  }
}
