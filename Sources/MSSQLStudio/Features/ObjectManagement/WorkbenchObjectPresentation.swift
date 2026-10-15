import AppKit
import SQLServerKit
import SwiftUI

extension WorkbenchController {
  @discardableResult private func openManagedSQL(_ sql:String,node:TreeNode,title:String) -> QueryDocument {
    let document=state.newQuery(server:node.server,database:node.database,text:sql,title:title)
    view.window?.makeKeyAndOrderFront(nil)
    let folder=node.objectFolder ?? {if case .folder(let f)=node.kind {return f};return nil}()
    if let folder, [.triggers,.indexes,.keys,.constraints].contains(folder) || title.hasPrefix("Rename") {
      document.managedObjectApplied={ [weak document] in
        guard let query=document?.lastExecutedSQL,ModuleEditing.changes(query).isEmpty,TSQL.lex(query).contains(where:{ ![.space,.comment,.string].contains($0.kind) && ["TRIGGER","INDEX","CONSTRAINT","SP_RENAME"].contains($0.text.uppercased()) }) else {return}
        NotificationCenter.default.post(name:.init("studioManagedObjectCompleted"),object:node)
      }
    }
    return document
  }
  func selectScript(_ node:TreeNode,top:Int?=nil) async throws -> String {
    guard let item=node.item else {throw SQLFailure("Tablo veya view seçin.")}
    let output=try await node.server.catalog(Catalog.children(.columns,object:item.id),database:node.database)
    guard !output.partial,!output.stoppedEarly,!output.results.contains(where:{$0.truncated}) else {throw SQLFailure("Kolon listesi tam okunamadı; script oluşturulmadı.")}
    let columns=Catalog.rows(output)
    guard !columns.isEmpty else {throw SQLFailure("Kolonlar okunamadı; metadata izinlerini kontrol edin.")}
    return try Catalog.selectScript(item:item,columns:columns,top:top)
  }
  func loadManagedTable(_ node:TreeNode) async throws -> TableDefinition {
    guard let item=node.item else { throw SQLFailure("Tablo seçin.") }
    let fetched=Date(),generation=node.server.generation
    let table=try ObjectMetadata.decode(await node.server.catalog(ObjectMetadata.table(item.id),database:node.database),schema:item.schema,name:item.name)
    if node.server.allowsDefinitionIndex(node.database) {
      let indexed=try? await Task.detached(priority:.utility) {
        IndexedObjectDefinition(id:item.id,schema:item.schema,name:item.name,type:"U",sql:try table.createScript(),fetchedAt:fetched)
      }.value
      if let indexed {await node.server.definitionIndex.record(indexed,database:node.database,generation:generation)}
    }
    return table
  }
  func showManagedTable(_ node:TreeNode?,create:Bool=false,initialKind:String="") {
    guard let node else { return }
    let open:(String)->Void = { [weak self] sql in self?.openManagedSQL(sql,node:node,title:create ? "CREATE TABLE" : "ALTER TABLE · "+(node.item?.name ?? "")) }
    present(TableDesignerPanel(server:node.server.profile.name,database:node.database,initialKind:initialKind,load:create ? nil : { try await self.loadManagedTable(node) },open:open),title:create ? "New Table" : "Design · "+(node.item?.qualified ?? ""),width:1080,height:720,minWidth:800,minHeight:600)
  }
  func showManagedView(_ node:TreeNode?,create:Bool=false) {
    guard let node else { return }
    if !create,let id=node.item?.id,activateObjectEditor(server:node.server,database:node.database,objectID:id) {return}
    let draft=QueryDocument(server:node.server,database:node.database,title:"View Designer")
    draft.sql=create ? "CREATE VIEW [dbo].[NewView]\nAS\nSELECT 1 AS [Value];" : ""
    let load:(() async throws -> String)? = create ? nil : {
      guard let item=node.item else { throw SQLFailure("View seçin.") }
      let fetched=Date(),generation=node.server.generation
      let execution=try await node.server.catalog(Catalog.definition(item.id),database:node.database)
      guard !execution.partial, let source=execution.results.first?.values.first?.first, let source else { throw SQLFailure("View tanımı alınamadı; VIEW DEFINITION izni / şifreleme durumunu kontrol edin.") }
      let settings=try await node.server.catalog("SELECT uses_ansi_nulls,uses_quoted_identifier FROM sys.sql_modules WHERE object_id=\(item.id);",database:node.database)
      guard !settings.partial, let row=settings.results.first?.values.first, row.count == 2 else { throw SQLFailure("View session ayarları okunamadı.") }
      if node.server.allowsDefinitionIndex(node.database) {
        let preview=try ExplorerScripts.module(source,verb:"CREATE",qualified:item.qualified,ansi:row[0]=="1",quoted:row[1]=="1")
        await node.server.definitionIndex.record(.init(id:item.id,schema:item.schema,name:item.name,type:"V",sql:preview,original:source,fetchedAt:fetched),database:node.database,generation:generation)
      }
      draft.moduleOriginal=source
      return "SET ANSI_NULLS \(row[0] == "1" ? "ON" : "OFF");\nGO\nSET QUOTED_IDENTIFIER \(row[1] == "1" ? "ON" : "OFF");\nGO\n" + (try ObjectScripts.module(source,verb:"ALTER"))
    }
    present(ViewDesignerPanel(document:draft,load:load,open:{ [weak self] sql in
      guard let self else {return}
      if !create,let id=node.item?.id {
        if activateObjectEditor(server:node.server,database:node.database,objectID:id) {return}
        let doc=openObjectEditor(server:node.server,database:node.database,objectID:id,sql:draft.savedText,title:"ALTER VIEW · "+(node.item?.name ?? ""),original:draft.moduleOriginal)
        doc.sql=sql;doc.changed?()
      } else {openManagedSQL(sql,node:node,title:"CREATE VIEW · NewView")}
    }),title:create ? "New View" : "Design View · "+(node.item?.qualified ?? ""),width:1000,height:700)
  }
  func showManagedData(_ node:TreeNode?) {
    guard let node else { return }
    present(DataEditorPanel(load:{
      let table=try await self.loadManagedTable(node)
      guard !table.primaryKey.isEmpty else { throw SQLFailure("Edit Top 200 Rows için primary key gerekli. Anahtarsız tabloya UPDATE/DELETE gönderilmez.") }
      let columns=table.columns.map { SQL.identifier($0.name) }.joined(separator:", ")
      let order=table.primaryKey.map(SQL.identifier).joined(separator:", ")
      let data=try await node.server.catalog("SELECT TOP (200) \(columns) FROM \(table.qualified) ORDER BY \(order);",database:node.database)
      guard !data.partial, let rows=data.results.first, rows.fields.count == table.columns.count else { throw SQLFailure("Veri kısmi/eksik; düzenleme açılmadı.") }
      return (table,rows.values.map { DataEditRow(original:$0,values:$0) })
    },open:{ [weak self] sql in self?.openManagedSQL(sql,node:node,title:"Edit Data · "+(node.item?.name ?? "")) }),title:"Edit Top 200 Rows · "+(node.item?.qualified ?? ""),width:1100,height:680)
  }
  func managedDrop(_ node:TreeNode) async throws -> String {
    guard let item=node.item, let folder=node.objectFolder else {throw SQLFailure("Nesne seçin.")}
    if folder == .triggers {return try TriggerDefinition.decode(await node.server.catalog(TriggerDefinition.metadata(item.id),database:node.database)).dropScript}
    return try ExplorerScripts.drop(kind:folder,qualified:item.qualified)
  }
  func showManagedDelete(_ node:TreeNode?) {
    guard let node,let item=node.item,let folder=node.objectFolder else {return}
    present(DeleteObjectPanel(qualified:item.qualified,warning:folder == .tables ? "DROP TABLE tabloyu ve içindeki verileri kaldırır." : "Nesne tanımı kaldırılır; bağımlı sorgular ve uygulamalar etkilenebilir.",load:{try await node.server.catalog(Self.dependencySQL(item.id),database:node.database)},open:{ [weak self] in
      Task { [weak self] in do { guard let self else {return};openManagedSQL(try await managedDrop(node),node:node,title:"DROP · "+item.name) } catch {self?.state.showError(error.localizedDescription)} }
    }),title:"Delete Object · "+item.name,width:760,height:540)
  }
  func showManagedRename(_ node:TreeNode?) {
    guard let node, let item=node.item else { return }
    present(RenameObjectPanel(qualified:item.qualified,name:item.name,open:{ [weak self] sql in self?.openManagedSQL(sql,node:node,title:"Rename · "+item.name) }),title:"Rename · "+item.name,width:660,height:480)
  }
  static func dependencySQL(_ id:Int) -> String {
    "SELECT COALESCE(OBJECT_SCHEMA_NAME(referencing_id)+N'.'+OBJECT_NAME(referencing_id),N'(bilinmeyen)') AS [Referencing], COALESCE(referenced_schema_name+N'.',N'')+referenced_entity_name AS [Referenced] FROM sys.sql_expression_dependencies WHERE referencing_id=\(id) OR referenced_id=\(id);"
  }
  func showManagedProperties(_ node:TreeNode?) {
    guard let node, let item=node.item else { return }
    let trigger=node.objectFolder == .triggers
    present(ObjectPropertiesPanel(qualified:item.qualified,permissions:!trigger,load:{
      if trigger {return try await node.server.catalog("SELECT t.name AS [Name],t.type_desc AS [Type],t.parent_class_desc AS [Scope],OBJECT_NAME(t.parent_id) AS [Parent],CASE WHEN t.is_disabled=1 THEN N'Disabled' ELSE N'Enabled' END AS [State],t.is_instead_of_trigger AS [Instead Of],t.is_not_for_replication AS [Not For Replication],t.create_date AS [Created],t.modify_date AS [Modified] FROM sys.triggers t WHERE t.object_id=\(item.id);",database:node.database)}
      return try await node.server.catalog("SELECT o.name AS [Name],s.name AS [Schema],o.type_desc AS [Type],CONVERT(nvarchar(30),o.create_date,126) AS [Created],CONVERT(nvarchar(30),o.modify_date,126) AS [Modified],USER_NAME(o.principal_id) AS [Owner],CONVERT(nvarchar(10),HAS_PERMS_BY_NAME(QUOTENAME(s.name)+'.'+QUOTENAME(o.name),'OBJECT','ALTER')) AS [Can ALTER] FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id WHERE o.object_id=\(item.id); SELECT USER_NAME(grantee_principal_id) AS [Principal],permission_name,state_desc FROM sys.database_permissions WHERE class=1 AND major_id=\(item.id);",database:node.database)
    },open:{ [weak self] sql in self?.openManagedSQL(sql,node:node,title:"Permissions · "+item.name) }),title:"Properties · "+item.qualified,width:780,height:600)
  }
  func loadManagedModule(_ node:TreeNode,verb:String) async throws -> (script:String, original:String) {
    guard let item=node.item else {throw SQLFailure("Nesne seçin.")}
    let fetched=Date(),generation=node.server.generation
    let execution=try await node.server.catalog(Catalog.definition(item.id),database:node.database)
    guard !execution.partial,let source=execution.results.first?.values.first?.first,let source else {throw SQLFailure("T-SQL tanımı alınamadı; şifreli/CLR modülü veya VIEW DEFINITION iznini kontrol edin.")}
    let settings=try await node.server.catalog("SELECT uses_ansi_nulls,uses_quoted_identifier FROM sys.sql_modules WHERE object_id=\(item.id);",database:node.database)
    guard !settings.partial,let row=settings.results.first?.values.first,row.count == 2 else {throw SQLFailure("Modül session ayarları okunamadı.")}
    var script=try ExplorerScripts.module(source,verb:verb,qualified:item.qualified,ansi:row[0]=="1",quoted:row[1]=="1")
    if node.objectFolder == .triggers {
      let trigger=try TriggerDefinition.decode(await node.server.catalog(TriggerDefinition.metadata(item.id),database:node.database))
      script += "\nGO\n"+(try trigger.stateScript(enabled:!trigger.disabled))
    }
    if node.server.allowsDefinitionIndex(node.database) {
      let preview=try ExplorerScripts.module(source,verb:"CREATE",qualified:item.qualified,ansi:row[0]=="1",quoted:row[1]=="1")
      let type:String
      switch node.objectFolder {case .views:type="V";case .procedures:type="P";case .functions:type=item.detail.contains("INLINE") ? "IF":item.detail.contains("TABLE") ? "TF":"FN";default:type=item.schema.isEmpty ? "TRD":"TR"}
      await node.server.definitionIndex.record(.init(id:item.id,schema:item.schema,name:item.name,type:type,sql:preview,original:source,parentID:node.ownerObject?.item?.id,fetchedAt:fetched),database:node.database,generation:generation)
    }
    return (script,source)
  }
  func scriptManagedObject(_ node:TreeNode,mode:String,destination:String) {
    guard let item=node.item,let folder=node.objectFolder else {return}
    let isEditor=["MODIFY","ALTER","CREATE","CREATE OR ALTER"].contains(mode) && destination == "New Query Editor Window"
    if isEditor, activateObjectEditor(server:node.server,database:node.database,objectID:item.id) {return}
    Task { [weak self] in
      guard let self else {return}
      do {
        var script:String
        var moduleSource:String?
        switch mode {
        case "DROP":
          script=[Folder.indexes,.keys,.constraints].contains(folder) ? try await structureScript(node,drop:true) : try await managedDrop(node)
        case "CREATE","ALTER","CREATE OR ALTER","DROP And CREATE","MODIFY":
          if [.views,.procedures,.functions,.triggers].contains(folder) {let loaded=try await loadManagedModule(node,verb:mode == "DROP And CREATE" ? "CREATE" : mode == "MODIFY" ? "ALTER" : mode);script=loaded.script;moduleSource=loaded.original}
          else if folder == .synonyms {
            let fetched=Date(),generation=node.server.generation
            let r=try await node.server.catalog("SELECT base_object_name FROM sys.synonyms WHERE object_id=\(item.id);",database:node.database)
            guard !r.partial,let target=r.results.first?.values.first?.first,let target else {throw SQLFailure("Synonym hedefi alınamadı.")}
            script=try ExplorerScripts.synonym(qualified:item.qualified,target:target)
            if node.server.allowsDefinitionIndex(node.database) {
              await node.server.definitionIndex.record(.init(id:item.id,schema:item.schema,name:item.name,type:"SN",sql:script,fetchedAt:fetched),database:node.database,generation:generation)
            }
          } else if [.indexes,.keys,.constraints].contains(folder) {script=try await structureScript(node,drop:false)}
          else {script=try await loadManagedTable(node).createScript()}
          if mode == "DROP And CREATE" {
            let drop=[Folder.indexes,.keys,.constraints].contains(folder) ? try await structureScript(node,drop:true) : try await managedDrop(node)
            script="-- DROP nesneyi kaldırır; tablo verisi / izinler kaybolabilir. İnceleyin.\n"+drop+"\nGO\n"+script
          }
        case "SELECT":script=try await selectScript(node)
        case "INSERT","UPDATE":
          let columns=Catalog.rows(try await node.server.catalog(Catalog.children(.columns,object:item.id),database:node.database)).filter { !$0.detail.contains("identity") && !$0.detail.contains("computed") && !$0.detail.hasPrefix("timestamp") && !$0.detail.hasPrefix("rowversion") }
          guard !columns.isEmpty else {throw SQLFailure("Yazılabilir kolon bulunamadı.")}
          script=mode == "INSERT" ? "INSERT INTO \(item.qualified) (\(columns.map {SQL.identifier($0.name)}.joined(separator:", ")))\nVALUES (\(columns.map {_ in "NULL"}.joined(separator:", ")));" : "UPDATE \(item.qualified)\nSET \(columns.map {SQL.identifier($0.name)+" = NULL"}.joined(separator:",\n    "))\nWHERE 1 = 0; -- WHERE koşulunu belirleyin."
        case "DELETE":script="DELETE FROM \(item.qualified) WHERE 1 = 0; -- WHERE koşulunu belirleyin."
        default:throw SQLFailure("Script türü desteklenmiyor.")
        }
        switch destination {
        case "Clipboard":NSPasteboard.general.clearContents();NSPasteboard.general.setString(script,forType:.string)
        case "File…":let panel=NSSavePanel();panel.nameFieldStringValue=item.name+".sql";if panel.runModal() == .OK,let url=panel.url {try script.write(to:url,atomically:true,encoding:.utf8)}
        default:
          if isEditor {
            let doc=openObjectEditor(server:node.server,database:node.database,objectID:item.id,sql:script,title:(mode == "MODIFY" ? "ALTER" : mode)+" · "+item.name,original:moduleSource)
            // Static trigger DDL uses the shared targeted metadata observer.
          } else {openManagedSQL(script,node:node,title:mode+" · "+item.name)}
        }
      } catch {state.showError(error.localizedDescription)}
    }
  }
  func stageTriggerState(_ node:TreeNode?,enabled:Bool) {
    guard let node,let item=node.item else {return}
    Task { [weak self] in do {
      guard let self else {return}
      let trigger=try TriggerDefinition.decode(await node.server.catalog(TriggerDefinition.metadata(item.id),database:node.database))
      openManagedSQL(try trigger.stateScript(enabled:enabled),node:node,title:(enabled ? "Enable" : "Disable")+" Trigger · "+item.name)
    } catch {self?.state.showError(error.localizedDescription)} }
  }
  func showRoutineInvocation(_ node:TreeNode?) {
    guard let node,let item=node.item else {return}
    present(RoutineInvocationPanel(qualified:item.qualified,function:node.objectFolder == .functions,tableValued:item.detail.contains("TABLE_VALUED"),load:{try RoutineScripts.decode(await node.server.catalog(RoutineScripts.parameters(item.id),database:node.database))},open:{[weak self] sql in self?.openManagedSQL(sql,node:node,title:"Invoke · "+item.name)}),title:"Parameters · "+item.qualified,width:850,height:560)
  }
  func stageNewModule(_ node:TreeNode?,kind:String) {
    guard let node else {return};let sql:String
    switch kind {
    case "PROCEDURE":sql="CREATE PROCEDURE [dbo].[NewProcedure]\n    @Value int\nAS\nBEGIN\n    SET NOCOUNT ON;\n    SELECT @Value AS [Value];\nEND;"
    case "SCALAR FUNCTION":sql="CREATE FUNCTION [dbo].[NewFunction] (@Value int)\nRETURNS int\nAS\nBEGIN\n    RETURN @Value;\nEND;"
    case "TABLE FUNCTION":sql="CREATE FUNCTION [dbo].[NewTableFunction] (@Value int)\nRETURNS TABLE\nAS\nRETURN (SELECT @Value AS [Value]);"
    default:
      if let parent=node.item {
        let timing=node.ownerObject?.objectFolder == .views ? "INSTEAD OF" : "AFTER"
        sql="CREATE TRIGGER \(SQL.identifier(parent.schema.isEmpty ? "dbo" : parent.schema)).[NewTrigger]\nON \(parent.qualified)\n\(timing) INSERT, UPDATE\nAS\nBEGIN\n    SET NOCOUNT ON;\n    -- inserted/deleted birden fazla satır içerir.\nEND;"
      }
      else {sql="CREATE TRIGGER [NewDatabaseTrigger] ON DATABASE\nFOR CREATE_TABLE, ALTER_TABLE\nAS\nBEGIN\n    SET NOCOUNT ON;\n    -- EVENTDATA() ile DDL olayını inceleyin.\nEND;"}
    }
    openManagedSQL(sql,node:node,title:"New · "+kind)
  }
  func showSynonymDesigner(_ node:TreeNode?,create:Bool=false) {
    guard let node else {return}
    present(SynonymDesignerPanel(schema:node.item?.schema ?? "dbo",name:create ? "NewSynonym" : node.item?.name ?? "NewSynonym",existing:!create,load:create ? nil : {
      guard let item=node.item else {return ""}
      let fetched=Date(),generation=node.server.generation
      let r=try await node.server.catalog("SELECT base_object_name FROM sys.synonyms WHERE object_id=\(item.id);",database:node.database)
      guard !r.partial,let target=r.results.first?.values.first?.first,let target else {throw SQLFailure("Synonym hedefi alınamadı.")}
      if node.server.allowsDefinitionIndex(node.database),let sql=try? ExplorerScripts.synonym(qualified:item.qualified,target:target) {
        await node.server.definitionIndex.record(.init(id:item.id,schema:item.schema,name:item.name,type:"SN",sql:sql,fetchedAt:fetched),database:node.database,generation:generation)
      }
      return target
    },open:{[weak self] sql in self?.openManagedSQL(sql,node:node,title:"Synonym")}),title:create ? "New Synonym" : "Modify Synonym",width:700,height:480)
  }
  func showChildStructure(_ node:TreeNode?) {
    guard let node,let owner=node.ownerObject else {return}
    if owner.objectFolder == .views || owner.objectFolder == .procedures || owner.objectFolder == .functions {scriptManagedObject(owner,mode:"MODIFY",destination:"New Query Editor Window");return}
    guard owner.objectFolder == .tables else {state.showError("View indeks/kolon değişikliklerini ALTER VIEW / SQL editöründe yapın.");return}
    let folder=node.objectFolder ?? {if case .folder(let f)=node.kind {return f};return .columns}()
    showManagedTable(owner,initialKind:folder == .columns ? "" : node.item?.detail.contains("FOREIGN_KEY") == true ? "FK" : folder == .constraints ? "CHECK" : "INDEX")
  }
  func structureScript(_ node:TreeNode,drop:Bool) async throws -> String {
    guard let owner=node.ownerObject,let item=node.item else {throw SQLFailure("Üst tablo bulunamadı.")}
    let table=try await loadManagedTable(owner)
    // Index IDs belong to the table; match only the requested kind, never a same-name key index.
    let allowed:Set<String>=node.objectFolder == .indexes ? ["INDEX","PK","UQ"] : ["PK","UQ","FK","CHECK"]
    if let definition=table.definitions.first(where:{$0.name==item.name && allowed.contains($0.kind)}) {
      if !drop {return definition.sql}
      return definition.kind == "INDEX" ? "DROP INDEX \(SQL.identifier(item.name)) ON \(table.qualified);" : "ALTER TABLE \(table.qualified) DROP CONSTRAINT \(SQL.identifier(item.name));"
    }
    if node.objectFolder == .constraints,let c=table.columns.first(where:{$0.defaultName==item.name}) {
      return drop ? "ALTER TABLE \(table.qualified) DROP CONSTRAINT \(SQL.identifier(item.name));" : "ALTER TABLE \(table.qualified) ADD CONSTRAINT \(SQL.identifier(item.name)) DEFAULT \(c.defaultSQL) FOR \(SQL.identifier(c.name));"
    }
    throw SQLFailure("Nesne tanımı değişmiş veya desteklenmiyor; Explorer'ı yenileyin.")
  }
  func stageStructureAction(_ node:TreeNode?,action:String) {
    guard let node,let owner=node.ownerObject,let table=owner.item,let item=node.item else {return}
    let sql:String
    if node.objectFolder == .indexes {sql="ALTER INDEX \(SQL.identifier(item.name)) ON \(table.qualified) \(action);"}
    else {sql="ALTER TABLE \(table.qualified) \(action == "CHECK" ? "WITH CHECK CHECK" : "NOCHECK") CONSTRAINT \(SQL.identifier(item.name));"}
    openManagedSQL(sql,node:node,title:action+" · "+item.name)
  }

}
