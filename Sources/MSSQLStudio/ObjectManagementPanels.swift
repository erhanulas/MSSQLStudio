import AppKit
import SwiftUI
import SQLServerKit

extension WorkbenchController {
  @discardableResult private func openManagedSQL(_ sql:String,node:TreeNode,title:String) -> QueryDocument {
    let document=state.newQuery(server:node.server,database:node.database,text:sql,title:title)
    view.window?.makeKeyAndOrderFront(nil)
    let folder=node.objectFolder ?? {if case .folder(let f)=node.kind {return f};return nil}()
    if let folder, [.triggers,.indexes,.keys,.constraints].contains(folder) || title.hasPrefix("Rename") {
      document.managedObjectApplied={ [weak document] in
        guard let query=document?.lastExecutedSQL,TSQL.lex(query).contains(where:{ ![.space,.comment,.string].contains($0.kind) && ["TRIGGER","INDEX","CONSTRAINT","SP_RENAME"].contains($0.text.uppercased()) }) else {return}
        NotificationCenter.default.post(name:.init("studioManagedObjectCompleted"),object:node)
      }
    }
    return document
  }
  func loadManagedTable(_ node:TreeNode) async throws -> TableDefinition {
    guard let item=node.item else { throw SQLFailure("Tablo seçin.") }
    return try ObjectMetadata.decode(await node.server.catalog(ObjectMetadata.table(item.id),database:node.database),schema:item.schema,name:item.name)
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
      let execution=try await node.server.catalog(Catalog.definition(item.id),database:node.database)
      guard !execution.partial, let source=execution.results.first?.values.first?.first, let source else { throw SQLFailure("View tanımı alınamadı; VIEW DEFINITION izni / şifreleme durumunu kontrol edin.") }
      let settings=try await node.server.catalog("SELECT uses_ansi_nulls,uses_quoted_identifier FROM sys.sql_modules WHERE object_id=\(item.id);",database:node.database)
      guard !settings.partial, let row=settings.results.first?.values.first, row.count == 2 else { throw SQLFailure("View session ayarları okunamadı.") }
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
    let execution=try await node.server.catalog(Catalog.definition(item.id),database:node.database)
    guard !execution.partial,let source=execution.results.first?.values.first?.first,let source else {throw SQLFailure("T-SQL tanımı alınamadı; şifreli/CLR modülü veya VIEW DEFINITION iznini kontrol edin.")}
    let settings=try await node.server.catalog("SELECT uses_ansi_nulls,uses_quoted_identifier FROM sys.sql_modules WHERE object_id=\(item.id);",database:node.database)
    guard !settings.partial,let row=settings.results.first?.values.first,row.count == 2 else {throw SQLFailure("Modül session ayarları okunamadı.")}
    var script=try ExplorerScripts.module(source,verb:verb,qualified:item.qualified,ansi:row[0]=="1",quoted:row[1]=="1")
    if node.objectFolder == .triggers {
      let trigger=try TriggerDefinition.decode(await node.server.catalog(TriggerDefinition.metadata(item.id),database:node.database))
      script += "\nGO\n"+(try trigger.stateScript(enabled:!trigger.disabled))
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
            let r=try await node.server.catalog("SELECT base_object_name FROM sys.synonyms WHERE object_id=\(item.id);",database:node.database)
            guard !r.partial,let target=r.results.first?.values.first?.first,let target else {throw SQLFailure("Synonym hedefi alınamadı.")}
            script=try ExplorerScripts.synonym(qualified:item.qualified,target:target)
          } else if [.indexes,.keys,.constraints].contains(folder) {script=try await structureScript(node,drop:false)}
          else {script=try await loadManagedTable(node).createScript()}
          if mode == "DROP And CREATE" {
            let drop=[Folder.indexes,.keys,.constraints].contains(folder) ? try await structureScript(node,drop:true) : try await managedDrop(node)
            script="-- DROP nesneyi kaldırır; tablo verisi / izinler kaybolabilir. İnceleyin.\n"+drop+"\nGO\n"+script
          }
        case "SELECT":script="SELECT TOP (1000) * FROM \(item.qualified);"
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
            if folder == .triggers {doc.managedObjectApplied={NotificationCenter.default.post(name:.init("studioManagedObjectCompleted"),object:node)}}
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
      guard let item=node.item else {return ""};let r=try await node.server.catalog("SELECT base_object_name FROM sys.synonyms WHERE object_id=\(item.id);",database:node.database)
      guard !r.partial,let target=r.results.first?.values.first?.first,let target else {throw SQLFailure("Synonym hedefi alınamadı.")};return target
    },open:{[weak self] sql in self?.openManagedSQL(sql,node:node,title:"Synonym")}),title:create ? "New Synonym" : "Modify Synonym",width:700,height:480)
  }
  func showChildStructure(_ node:TreeNode?) {
    guard let node,let owner=node.ownerObject else {return}
    if owner.objectFolder == .procedures || owner.objectFolder == .functions {scriptManagedObject(owner,mode:"MODIFY",destination:"New Query Editor Window");return}
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

private struct TableDesignerPanel: View {
  let server:String
  let database:String
  let initialKind:String
  @State private var tab="columns"
  let load:(() async throws -> TableDefinition)?
  let open:(String)->Void
  @State private var original:TableDefinition?
  @State private var schema="dbo"
  @State private var name="NewTable"
  @State private var columns:[SQLServerKit.TableColumn]=[SQLServerKit.TableColumn(id:-1,name:"Id",type:"int",nullable:false,identity:true)]
  @State private var primary:Set<Int>=[-1]
  @State private var selectedColumn=Int.min
  private struct ColumnFocus:Hashable {let id:Int;let field:Int}
  @FocusState private var focusedColumn:ColumnFocus?
  @State private var ready=false
  @State private var error=""
  @State private var preview=""
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:load == nil ? "New Table" : "Table Designer",icon:"tablecells",subtitle:server+" · "+database)
      VStack(alignment:.leading,spacing:10) { StudioFormField("Şema") {TextField("Şema",text:$schema).disabled(load != nil)}; StudioFormField("Tablo adı") {TextField("Tablo adı",text:$name).disabled(load != nil)}; Text("\(columns.count) kolon").foregroundStyle(.secondary) }
      if !ready { ProgressView("Metadata yükleniyor…") }
      TabView(selection:$tab) {
        columnEditor.tag("columns").tabItem { Label("Columns",systemImage:"tablecells") }
        if let original {
          StructureObjectsPanel(table:original,initialKind:initialKind,open:open).tag("management").tabItem { Label("Keys / Indexes / Relationships",systemImage:"link") }
        }
      }
      if !error.isEmpty { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        StudioActionButton("Değişiklik Scripti Oluştur", icon:"doc.badge.gearshape", tint:.accentColor) { generate() }.disabled(!ready)
        StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) { generate(); if !preview.isEmpty { open(preview) } }.disabled(!ready)
        Spacer()
        Text("Bağımlı nesneler varsa SQL Server değişikliği reddedebilir; otomatik tablo rebuild yapılmaz.").font(.caption).foregroundStyle(.secondary)
      }
      if !preview.isEmpty { ScrollView { Text(preview).font(.custom(StudioTheme.codeFont.fontName,size:12)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(height:130) }
    }.padding(18).studioPanel().task {
      do {
        if let load { let table=try await load(); original=table; schema=table.schema; name=table.name; columns=table.columns; primary=Set(table.columns.filter { table.primaryKey.contains($0.name) }.map(\.id)) }
        if !initialKind.isEmpty { tab="management" }
        ready=true
      } catch { self.error=error.localizedDescription }
    }
  }
  private var columnEditor:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Button {
          let id=min(0,columns.map(\.id).min() ?? 0)-1
          var name="NewColumn",suffix=2
          while columns.contains(where:{$0.name.caseInsensitiveCompare(name) == .orderedSame}) {name="NewColumn\(suffix)";suffix+=1}
          columns.append(SQLServerKit.TableColumn(id:id,name:name));selectedColumn=id;preview=""
        } label:{Label("Kolon Ekle",systemImage:"plus")}.accessibilityIdentifier("addDesignerColumn")
        Button(role:.destructive) {columns.removeAll {$0.id==selectedColumn};primary.remove(selectedColumn);selectedColumn=Int.min;preview=""} label:{Label("Seçili Kolonu Kaldır",systemImage:"minus.circle")}.disabled(!columns.contains {$0.id==selectedColumn}).accessibilityIdentifier("removeDesignerColumn")
        Spacer()
        Text(columns.first(where:{$0.id==selectedColumn}).map {"Seçili: "+$0.name} ?? "Düzenlemek için satıra tıklayın").font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }.fixedSize(horizontal:false,vertical:true)
      Divider()
      ScrollViewReader { proxy in
      ScrollView([.horizontal,.vertical]) {
        LazyVStack(alignment:.leading,spacing:6) {
          HStack {Color.clear.frame(width:28,height:1);Text("Kolon adı").frame(width:150);Text("Veri tipi").frame(width:150);Text("NULL").frame(width:45);Text("PK").frame(width:40);Text("Identity").frame(width:70);Text("Default / computed").frame(width:240,alignment:.leading)}.font(.caption).foregroundStyle(.secondary)
          ForEach($columns) { $column in
            HStack {
              Button {selectedColumn=column.id;focusedColumn=ColumnFocus(id:column.id,field:0)} label:{Image(systemName:selectedColumn == column.id ? "arrowtriangle.right.fill" : "circle").foregroundStyle(selectedColumn == column.id ? Color.accentColor : Color.secondary).frame(width:28,height:24).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel(column.name+" kolonunu seç").accessibilityIdentifier("selectDesignerColumn_\(column.id)").help("Bu kolonu seç; üstteki − düğmesi seçili kolonu kaldırır.")
              TextField("Kolon",text:$column.name).frame(width:150).focused($focusedColumn,equals:ColumnFocus(id:column.id,field:0))
              TextField("int / nvarchar(100)",text:$column.type).frame(width:150).disabled(original?.columns.first(where:{$0.id==column.id})?.generated == true).focused($focusedColumn,equals:ColumnFocus(id:column.id,field:1))
              Toggle("",isOn:$column.nullable).labelsHidden().frame(width:45).disabled(column.identity || !column.computed.isEmpty)
              Toggle("",isOn:Binding(get:{primary.contains(column.id)},set:{if $0 {primary.insert(column.id);if let i=columns.firstIndex(where:{$0.id==column.id}) {columns[i].nullable=false}} else {primary.remove(column.id)}})).labelsHidden().frame(width:40)
              Toggle("",isOn:Binding(get:{column.identity},set:{column.identity=$0;if $0 {column.nullable=false}})).labelsHidden().frame(width:70).disabled(original?.columns.contains(where:{$0.id==column.id}) == true)
              if column.computed.isEmpty {TextField("DEFAULT SQL",text:$column.defaultSQL).frame(width:240).focused($focusedColumn,equals:ColumnFocus(id:column.id,field:2))}
              else {Text("AS "+column.computed).lineLimit(1).frame(width:240,alignment:.leading).help(column.computed)}
            }.padding(.vertical,3).background(selectedColumn == column.id ? Color.accentColor.opacity(0.13) : Color.clear).overlay(alignment:.leading) {if selectedColumn == column.id {Rectangle().fill(Color.accentColor).frame(width:2)}}.contentShape(Rectangle()).simultaneousGesture(TapGesture().onEnded {selectedColumn=column.id}).id(column.id)
          }
        }.padding(.vertical,8)
      }.frame(minHeight:80,maxHeight:.infinity).layoutPriority(-1)
      .onChange(of:columns.count) {old,new in if new > old,let selected=columns.last,selected.id==selectedColumn {proxy.scrollTo(selected.id,anchor:.bottom)} }
      }
      Text("Identity seed/increment yeni kolonlarda 1,1. Computed/özel üretilen kolon değişikliği SQL editöründe yapılır.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
    }.padding(10).disabled(!ready).onChange(of:focusedColumn) {_,focus in if let focus {selectedColumn=focus.id} }
  }
  private func generate() {
    do { preview=try ObjectScripts.tableChanges(original:original,schema:schema,name:name,columns:columns,primaryKey:columns.filter { primary.contains($0.id) }.map(\.name)); error="" }
    catch { preview=""; self.error=error.localizedDescription }
  }
}

private struct StructureObjectsPanel:View {
  let table:TableDefinition
  let initialKind:String
  let open:(String)->Void
  @State private var kind="INDEX"
  @State private var name="IX_NewIndex"
  @State private var selected:Set<String>=[]
  @State private var includes:Set<String>=[]
  @State private var unique=false
  @State private var expression=""
  @State private var targetSchema="dbo"
  @State private var targetTable=""
  @State private var targetColumns=""
  @State private var deleteAction="NO ACTION"
  @State private var updateAction="NO ACTION"
  @State private var error=""
  var body:some View {
    HSplitView {
      VStack(alignment:.leading,spacing:8) {
        Text("Mevcut nesneler").font(.headline)
        List(table.definitions) { object in
          VStack(alignment:.leading) {
            Text(object.name+" · "+object.kind)
            HStack {
              Button("Script") { open(object.sql) }
              Button("DROP + CREATE") { open(drop(object)+"\nGO\n"+object.sql) }
              Button("Drop Script") { open(drop(object)) }
            }.buttonStyle(.borderless).font(.caption)
          }.padding(.vertical,4)
        }
      }.frame(minWidth:330)
      VStack(alignment:.leading,spacing:8) {
       ScrollView {
        VStack(alignment:.leading,spacing:12) {
          Text("Yeni nesne").font(.headline)
          StudioFormField("Tür") {Picker("Tür",selection:$kind) { Text("Index").tag("INDEX"); Text("Unique Key").tag("UQ"); Text("Foreign Key / Relationship").tag("FK"); Text("Check Constraint").tag("CHECK") }.labelsHidden()}
          StudioFormField("Ad") {TextField("Ad",text:$name)}
          if kind != "CHECK" {
            Text("Anahtar kolonları (tablo sırası)").font(.caption)
            ForEach(table.columns) { c in HStack {
              Toggle(c.name,isOn:membership(c.name,in:$selected))
              if kind == "INDEX" { Toggle("Include",isOn:membership(c.name,in:$includes)) }
            } }
          }
          if kind == "INDEX" { Toggle("UNIQUE",isOn:$unique); StudioFormField("Filtre") {TextField("Filtre: isteğe bağlı WHERE",text:$expression)} }
          if kind == "CHECK" { StudioFormField("CHECK koşulu") {TextField("Koşul: [Amount] >= 0",text:$expression)} }
          if kind == "FK" {
            StudioFormField("Hedef şema") {TextField("Hedef şema",text:$targetSchema)}; StudioFormField("Hedef tablo") {TextField("Hedef tablo",text:$targetTable)}; StudioFormField("Hedef kolonlar") {TextField("Hedef kolonlar: Id, Code",text:$targetColumns)}
            StudioFormField("ON DELETE") {Picker("ON DELETE",selection:$deleteAction) { ForEach(["NO ACTION","CASCADE","SET NULL","SET DEFAULT"],id:\.self) { Text($0) } }.labelsHidden()}
            StudioFormField("ON UPDATE") {Picker("ON UPDATE",selection:$updateAction) { ForEach(["NO ACTION","CASCADE","SET NULL","SET DEFAULT"],id:\.self) { Text($0) } }.labelsHidden()}
          }
        }.padding(12)
       }
       Divider()
       Text(error).foregroundStyle(.red)
       StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) {generate()}.padding(.horizontal,12)
       Text("SQL hazırlanır; bu pencereden veritabanına yazılmaz.").font(.caption).foregroundStyle(.secondary).padding(.horizontal,12)
      }.frame(minWidth:350)
    }.padding(8).onAppear { if !initialKind.isEmpty { kind=initialKind }; name=kind == "FK" ? "FK_NewRelationship" : kind == "CHECK" ? "CK_NewConstraint" : "IX_NewIndex" }
  }
  private func membership(_ name:String,in set:Binding<Set<String>>) -> Binding<Bool> { Binding(get:{set.wrappedValue.contains(name)},set:{ if $0 { set.wrappedValue.insert(name) } else { set.wrappedValue.remove(name) } }) }
  private func drop(_ object:ManagedDefinition) -> String {
    if object.kind == "INDEX" { return "DROP INDEX \(SQL.identifier(object.name)) ON \(table.qualified);" }
    if object.kind == "TRIGGER" { return "DROP TRIGGER \(SQL.identifier(table.schema)).\(SQL.identifier(object.name));" }
    return "ALTER TABLE \(table.qualified) DROP CONSTRAINT \(SQL.identifier(object.name));"
  }
  private func generate() {
    do {
      let keys=table.columns.filter { selected.contains($0.name) }.map(\.name)
      guard !name.isEmpty else { throw SQLFailure("Nesne adı gerekli.") }
      let sql:String
      switch kind {
      case "INDEX": sql=try Scripts.index(table:table.qualified,name:name,keys:keys,included:table.columns.filter { includes.contains($0.name) }.map(\.name),unique:unique,filter:expression)
      case "UQ": guard !keys.isEmpty else { throw SQLFailure("Anahtar kolonu seçin.") }; sql="ALTER TABLE \(table.qualified) ADD CONSTRAINT \(SQL.identifier(name)) UNIQUE (\(keys.map(SQL.identifier).joined(separator:", ")));"
      case "FK": sql=try ObjectScripts.foreignKey(table:table.qualified,name:name,columns:keys,referencedSchema:targetSchema,referencedTable:targetTable,referencedColumns:targetColumns.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) },onDelete:deleteAction,onUpdate:updateAction)
      default: guard !expression.isEmpty else { throw SQLFailure("CHECK koşulu gerekli.") }; sql="ALTER TABLE \(table.qualified) WITH CHECK ADD CONSTRAINT \(SQL.identifier(name)) CHECK (\(expression));"
      }
      open(sql); error=""
    } catch { self.error=error.localizedDescription }
  }
}

private struct ManagedSQLEditor:NSViewRepresentable {
  let document:QueryDocument
  // A value snapshot lets SwiftUI observe asynchronous loads on the reference document.
  let source:String
  func makeCoordinator() -> EditorController { EditorController(document:document) }
  func makeNSView(context:Context) -> NSView { context.coordinator.setText(); return context.coordinator.surface }
  func updateNSView(_ view:NSView,context:Context) { if context.coordinator.editor.string != document.sql { context.coordinator.setText() } }
}
private struct ViewDesignerPanel:View {
  let document:QueryDocument
  let load:(() async throws -> String)?
  let open:(String)->Void
  @State private var ready=false
  @State private var error=""
  @State private var schema="dbo"
  @State private var name="NewView"
  @State private var sourceSchema="dbo"
  @State private var sourceTable=""
  @State private var filter=""
  @State private var columns:[String]=[]
  @State private var selected:Set<String>=[]
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:load == nil ? "New View" : "View Designer",icon:"rectangle.on.rectangle",subtitle:document.server.profile.name+" · "+document.database)
      if load == nil {
        VStack(alignment:.leading,spacing:10) { StudioFormField("View şeması") {TextField("View şeması",text:$schema)}; StudioFormField("View adı") {TextField("View adı",text:$name)}; StudioFormField("Kaynak şema") {TextField("Kaynak şema",text:$sourceSchema)}; StudioFormField("Kaynak tablo / view") {TextField("Kaynak tablo / view",text:$sourceTable)}; HStack {Spacer();StudioActionButton("Kolonları Getir", icon:"arrow.down.square", tint:.accentColor) { Task { await loadColumns() } }} }
        if !columns.isEmpty {
          ScrollView(.horizontal) { HStack { ForEach(columns,id:\.self) { column in Toggle(column,isOn:Binding(get:{selected.contains(column)},set:{ if $0 {selected.insert(column)} else {selected.remove(column)} })) } } }.frame(height:35)
          HStack { TextField("WHERE koşulu (isteğe bağlı SQL)",text:$filter); Button("Seçimden View SQL'i Oluştur") { build() } }
        }
      }
      Text("SQL tanımı · Karmaşık JOIN/CTE/sorguları burada düzenleyin. Değişiklik otomatik çalıştırılmaz.").font(.caption).foregroundStyle(.secondary)
      if !ready { ProgressView("Tanım yükleniyor…") }
      ManagedSQLEditor(document:document,source:document.sql).disabled(!ready)
      Text(error).foregroundStyle(.red).textSelection(.enabled)
      HStack {
        if load != nil { StudioActionButton("Farkları Göster", icon:"rectangle.split.2x1", tint:.accentColor) { error=ModuleEditing.difference(original:document.savedText,edited:document.sql) } }
        Spacer(); StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) { open(document.sql) }.disabled(!ready)
      }
    }.padding(18).studioPanel().task {
      do { if let load { document.sql=try await load() }; document.savedText=document.sql; ready=true }
      catch { self.error=error.localizedDescription }
    }
  }
  private func loadColumns() async {
    do {
      guard !sourceSchema.isEmpty, !sourceTable.isEmpty else { throw SQLFailure("Kaynak şema ve tablo gerekli.") }
      let result=try await document.server.catalog("SELECT c.name FROM sys.columns c WHERE c.object_id=OBJECT_ID(\(SQL.literal(SQL.identifier(sourceSchema)+"."+SQL.identifier(sourceTable)))) ORDER BY c.column_id;",database:document.database)
      guard !result.partial else { throw SQLFailure("Kolon listesi kısmi geldi.") }
      columns=result.results.first?.values.compactMap { $0.first ?? nil } ?? []; selected=Set(columns); error=columns.isEmpty ? "Kaynak nesne/kolon bulunamadı." : ""
    } catch { self.error=error.localizedDescription }
  }
  private func build() {
    guard !schema.isEmpty, !name.isEmpty, !selected.isEmpty else { error="View adı ve kolon seçimi gerekli."; return }
    document.sql="CREATE VIEW \(SQL.identifier(schema)).\(SQL.identifier(name))\nAS\nSELECT \(columns.filter { selected.contains($0) }.map(SQL.identifier).joined(separator:",\n       "))\nFROM \(SQL.identifier(sourceSchema)).\(SQL.identifier(sourceTable))\(filter.isEmpty ? "" : "\nWHERE "+filter);"
    error=""; ready.toggle(); ready=true
  }
}

@MainActor final class ManagedDataModel:ObservableObject {
  var table:TableDefinition?
  var rows:[DataEditRow]=[]
  var selectedRow = -1
  @Published var revision=0
  func editable(row:Int,column:Int) -> Bool {
    guard let table, rows.indices.contains(row), table.columns.indices.contains(column), !rows[row].deleted, !table.columns[column].generated else { return false }
    return rows[row].original == nil || !table.primaryKey.contains(table.columns[column].name)
  }
  func set(_ value:String?,row:Int,column:Int) {
    guard editable(row:row,column:column) else { return }
    rows[row].values[column]=value; rows[row].touched.insert(column)
  }
}
private struct EditableDataGrid:NSViewRepresentable {
  @ObservedObject var model:ManagedDataModel
  func makeCoordinator() -> Coordinator { Coordinator(model:model) }
  func makeNSView(context:Context) -> NSScrollView {
    let scroll=NSScrollView(); scroll.hasHorizontalScroller=true; scroll.hasVerticalScroller=true; scroll.usesPredominantAxisScrolling=true
    let table=context.coordinator.table; table.delegate=context.coordinator; table.dataSource=context.coordinator
    table.usesAlternatingRowBackgroundColors=true; table.rowHeight=25; table.allowsMultipleSelection=false
    table.setAccessibilityIdentifier("managedDataGrid")
    scroll.documentView=table; return scroll
  }
  func updateNSView(_ view:NSScrollView,context:Context) {
    let c=context.coordinator
    if c.columns != model.table?.columns.map(\.name) ?? [] {
      c.columns=model.table?.columns.map(\.name) ?? []
      for column in c.table.tableColumns { c.table.removeTableColumn(column) }
      let row=NSTableColumn(identifier:.init("row")); row.title="#"; row.width=45; c.table.addTableColumn(row)
      for (i,name) in c.columns.enumerated() { let column=NSTableColumn(identifier:.init(String(i))); column.title=name; column.width=150; column.isEditable=true; column.headerToolTip=model.table?.columns[i].type; c.table.addTableColumn(column) }
    }
    c.table.reloadData()
  }
  @MainActor final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
    let model:ManagedDataModel
    let table=NSTableView()
    var columns:[String]=[]
    init(model:ManagedDataModel) { self.model=model }
    func numberOfRows(in tableView:NSTableView) -> Int { model.rows.count }
    func tableView(_ tableView:NSTableView,objectValueFor column:NSTableColumn?,row:Int) -> Any? {
      guard model.rows.indices.contains(row) else { return nil }
      guard let raw=column?.identifier.rawValue, let i=Int(raw) else { return (model.rows[row].deleted ? "− " : model.rows[row].original == nil ? "+ " : "")+String(row+1) }
      return model.rows[row].values[i] ?? "NULL"
    }
    func tableView(_ tableView:NSTableView,shouldEdit column:NSTableColumn?,row:Int) -> Bool { guard let raw=column?.identifier.rawValue, let i=Int(raw) else { return false }; return model.editable(row:row,column:i) }
    func tableView(_ tableView:NSTableView,setObjectValue object:Any?,for column:NSTableColumn?,row:Int) { guard let raw=column?.identifier.rawValue, let i=Int(raw) else { return }; model.set(object as? String ?? "",row:row,column:i) }
    func tableViewSelectionDidChange(_ notification:Notification) { model.selectedRow=table.selectedRow }
    func tableView(_ tableView:NSTableView,willDisplayCell cell:Any,for column:NSTableColumn?,row:Int) {
      guard let cell=cell as? NSTextFieldCell, model.rows.indices.contains(row) else { return }
      cell.font=StudioTheme.uiFont
      cell.textColor=model.rows[row].deleted ? .systemRed : .labelColor
    }
  }
}
private struct DataEditorPanel:View {
  let load:() async throws -> (TableDefinition,[DataEditRow])
  let open:(String)->Void
  @StateObject private var model=ManagedDataModel()
  @State private var ready=false
  @State private var error=""
  @State private var nullColumn=0
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Edit Top 200 Rows",icon:"pencil.and.list.clipboard",subtitle:model.table?.qualified ?? "Metadata yükleniyor")
      Text("Hücreye çift tıkla: düzenle · Primary key/identity/computed salt okunur · Yeni satırda dokunulmayan alanlar DEFAULT olur.").font(.caption).foregroundStyle(.secondary)
      HStack {
        Button { guard let table=model.table, model.rows.filter({$0.original==nil}).count < 200 else {return}; model.rows.append(.init(original:nil,values:Array(repeating:nil,count:table.columns.count))); model.revision += 1 } label:{ Label("Satır Ekle",systemImage:"plus") }.disabled(!ready)
        Button("Satırı Sil / Geri Al") { let i=model.selectedRow; guard model.rows.indices.contains(i) else {return}; model.rows[i].deleted.toggle(); model.revision += 1 }.disabled(!ready)
        Picker("NULL kolonu",selection:$nullColumn) { if let table=model.table { ForEach(table.columns.indices,id:\.self) { Text(table.columns[$0].name).tag($0) } } }.frame(width:250)
        StudioActionButton("NULL Yap", icon:"nosign", tint:.orange) { model.set(nil,row:model.selectedRow,column:nullColumn); model.revision += 1 }.disabled(!ready)
        Spacer()
        StudioActionButton("Yenile / Düzenlemeleri Sıfırla", icon:"arrow.clockwise", tint:.orange) { Task { await reload() } }.disabled(!ready)
      }
      if !ready { ProgressView() }
      EditableDataGrid(model:model)
      Text(error).foregroundStyle(.red).textSelection(.enabled)
      HStack {
        Text("Güncellemeler PK + rowversion veya orijinal kolonlarla denetlenir; eşzamanlı değişiklikte transaction geri alınır.").font(.caption).foregroundStyle(.secondary)
        Spacer()
        StudioActionButton("Değişiklikleri SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) {
          NSApp.keyWindow?.makeFirstResponder(nil)
          do { guard let table=model.table else {return}; open(try DataEditScripts.changes(table:table,rows:model.rows)); error="" }
          catch { self.error=error.localizedDescription }
        }.disabled(!ready)
      }
    }.padding(18).studioPanel().task { await reload() }
  }
  private func reload() async {
    ready=false
    do { let (table,rows)=try await load(); model.table=table; model.rows=rows; model.selectedRow = -1; model.revision += 1; ready=true; error="" }
    catch { self.error=error.localizedDescription; ready=false }
  }
}

private struct DeleteObjectPanel:View {
  let qualified:String
  let warning:String
  let load:() async throws -> Execution
  let open:()->Void
  @State private var rows:[[String?]]=[]
  @State private var confirm=""
  @State private var error=""
  @State private var loaded=false
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:"Delete Object",icon:"trash",subtitle:qualified)
      Text(warning).foregroundStyle(.red)
      Text("Bağımlılıklar (SQL Server tarafından kaydedilen)").font(.headline)
      ScrollView {
        LazyVStack(alignment:.leading,spacing:10) {
          if loaded && rows.isEmpty { Text("Kaydedilmiş bağımlılık bulunamadı.").foregroundStyle(.secondary) }
          ForEach(rows.indices,id:\.self) { i in
            Text(rows[i].map { $0 ?? "NULL" }.joined(separator:" → ")).textSelection(.enabled)
            Divider()
          }
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
      }.frame(maxHeight:.infinity).background(.background.opacity(0.5))
      Text("Dinamik SQL bağımlılıkları metadata içinde görünmeyebilir.").font(.caption).foregroundStyle(.secondary)
      TextField("Onay için nesnenin tam adını yazın: "+qualified,text:$confirm)
      Text(error).foregroundStyle(.red)
      HStack { Spacer(); StudioActionButton("DROP Scriptini SQL Editöründe Aç", icon:"trash", tint:.red) { open() }.disabled(!loaded || confirm != qualified) }
    }.padding(20).studioPanel().task {
      do { let result=try await load(); guard !result.partial else {throw SQLFailure("Bağımlılık listesi kısmi geldi.")}; rows=result.results.first?.values.map {$0} ?? []; loaded=true }
      catch { self.error=error.localizedDescription }
    }
  }
}
private struct RenameObjectPanel:View {
  let qualified:String
  @State var name:String
  let open:(String)->Void
  @State private var error=""
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      StudioPanelHeading(title:"Rename Object",icon:"character.cursor.ibeam",subtitle:qualified)
      StudioFormField("Yeni ad") {TextField("Yeni ad (şema hariç)",text:$name)}
      Text("sp_rename metin başvurularını ve sys.sql_modules içindeki eski adı güncellemez. Procedure/fonksiyon/trigger için bağımlılıkları inceleyin; CREATE/DROP ile taşıma SQL editöründe yapılabilir.").foregroundStyle(.secondary)
      Text(error).foregroundStyle(.red)
      Spacer(); HStack { Spacer(); StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) { do { open(try ObjectScripts.rename(qualified:qualified,name:name)) } catch { self.error=error.localizedDescription } } }
    }.padding(20).studioPanel()
  }
}
private struct ObjectPropertiesPanel:View {
  let qualified:String
  var permissions=true
  let load:() async throws -> Execution
  let open:(String)->Void
  @State private var result=Execution()
  @State private var principal=""
  @State private var permission="SELECT"
  @State private var operation="GRANT"
  @State private var error=""
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Object Properties",icon:"info.circle",subtitle:qualified)
      TabView {
        ScrollView { VStack(alignment:.leading,spacing:10) {
          if let rows=result.results.first, let row=rows.values.first { ForEach(rows.fields.indices,id:\.self) { i in HStack { Text(rows.fields[i].name).frame(width:150,alignment:.leading); Text(row[i] ?? "—").textSelection(.enabled) } } }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading) }.tabItem {Text("General")}
        if permissions { VStack(alignment:.leading,spacing:12) {
          List { if result.results.count > 1 { ForEach(Array(result.results[1].values.enumerated()),id:\.offset) { _,row in Text(row.map {$0 ?? ""}.joined(separator:" · ")) } } }
          HStack {
            StudioFormField("Kullanıcı / rol") {TextField("Kullanıcı / rol",text:$principal)}
            StudioFormField("İzin") {Picker("İzin",selection:$permission) { ForEach(["SELECT","EXECUTE","INSERT","UPDATE","DELETE","ALTER","REFERENCES","VIEW DEFINITION"],id:\.self) { Text($0) } }.labelsHidden()}
            StudioFormField("İşlem") {Picker("İşlem",selection:$operation) { ForEach(["GRANT","DENY","REVOKE"],id:\.self) { Text($0) } }.labelsHidden()}
          }
          StudioActionButton("İzin Scriptini SQL Editöründe Aç", icon:"lock.shield", tint:.accentColor) { guard !principal.isEmpty else {error="Kullanıcı / rol gerekli.";return}; open("\(operation) \(permission) ON OBJECT::\(qualified) \(operation == "REVOKE" ? "FROM" : "TO") \(SQL.identifier(principal));") }
        }.padding(12).tabItem {Text("Permissions")} }
      }
      Text(error).foregroundStyle(.red)
    }.padding(18).studioPanel().task { do { result=try await load(); if result.partial { error="Özellik listesi kısmi geldi." } } catch {self.error=error.localizedDescription} }
  }
}

/// Synthetic UI-only metadata. Assigned exclusively by the isolated UI-test launch branch.
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


private struct RoutineInvocationPanel:View {
  let qualified:String
  let function:Bool
  let tableValued:Bool
  let load:() async throws -> [RoutineParameter]
  let open:(String)->Void
  @State private var parameters:[RoutineParameter]=[]
  @State private var arguments:[Int:RoutineArgument]=[:]
  @State private var ready=false
  @State private var error=""
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:function ? "Invoke Function" : "Execute Stored Procedure",icon:function ? "function" : "terminal",subtitle:qualified)
      Text("Değerler metin olarak girilir, veri tipine çevrilir. DEFAULT seçimi procedure'de parametreyi atlar; zorunluysa SQL Server hata verir. SQL henüz çalıştırılmaz.").font(.caption).foregroundStyle(.secondary)
      if !ready {ProgressView("Parametreler yükleniyor…")}
      ScrollView {
        LazyVStack(alignment:.leading,spacing:10) {
          if ready && parameters.isEmpty {Text("Parametresiz nesne")}
          ForEach(parameters) { p in HStack {
            Text(p.name).frame(width:130,alignment:.leading)
            Text(p.type+(p.output ? " · OUTPUT" : "")).foregroundStyle(.secondary).frame(width:170,alignment:.leading)
            Picker("Gönderim",selection:Binding(get:{arguments[p.id]?.mode ?? "NULL"},set:{arguments[p.id,default:RoutineArgument()].mode=$0})) {Text("Değer").tag("Value");Text("NULL").tag("NULL");if !p.output {Text("DEFAULT").tag("DEFAULT")}}.labelsHidden().frame(width:110)
            TextField("Değer",text:Binding(get:{arguments[p.id]?.value ?? ""},set:{arguments[p.id,default:RoutineArgument()].value=$0})).disabled(arguments[p.id]?.mode != "Value")
          } }
        }.padding(8)
      }
      Text(error).foregroundStyle(.red).textSelection(.enabled)
      HStack {Spacer();StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) {do {open(try RoutineScripts.invocation(qualified:qualified,function:function,tableValued:tableValued,parameters:parameters,arguments:arguments));error=""} catch {self.error=error.localizedDescription}}.disabled(!ready)}
    }.padding(18).studioPanel().task {do {parameters=try await load();for p in parameters {arguments[p.id]=RoutineArgument()};ready=true} catch {self.error=error.localizedDescription}}
  }
}
private struct SynonymDesignerPanel:View {
  @State var schema:String
  @State var name:String
  let existing:Bool
  let load:(() async throws -> String)?
  let open:(String)->Void
  @State private var target=""
  @State private var error=""
  @State private var ready=false
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:existing ? "Modify Synonym" : "New Synonym",icon:"link",subtitle:"Synonym hedefi")
      VStack(spacing:12) {StudioFormField("Şema") {TextField("Şema",text:$schema)};StudioFormField("Ad") {TextField("Ad",text:$name)}}.disabled(existing)
      StudioFormField("Hedef nesne") {TextField("Hedef: [server].[database].[schema].[object]",text:$target)}
      Text(existing ? "SQL Server ALTER SYNONYM desteklemez. DROP + CREATE transaction scripti hazırlanır; nesne izinlerini ayrıca kontrol edin." : "1–4 parçalı hedef nesne adı girin.").foregroundStyle(.secondary)
      Text(error).foregroundStyle(.red);Spacer()
      HStack {Spacer();StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) {do {guard !schema.isEmpty,!name.isEmpty else {throw SQLFailure("Şema ve ad gerekli.")};let q=SQL.identifier(schema)+"."+SQL.identifier(name);let create=try ExplorerScripts.synonym(qualified:q,target:target);open(existing ? ObjectScripts.transaction("DROP SYNONYM \(q);\n"+create) : create)} catch {self.error=error.localizedDescription}}.disabled(!ready)}
    }.padding(18).studioPanel().task {do {if let load {target=try await load()};ready=true} catch {self.error=error.localizedDescription}}
  }
}
