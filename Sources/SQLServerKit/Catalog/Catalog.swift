import Foundation

public enum Folder: String, CaseIterable, Sendable {
  case databases = "Databases"
  case tables = "Tables"
  case views = "Views"
  case procedures = "Stored Procedures"
  case functions = "Functions"
  case synonyms = "Synonyms"
  case columns = "Columns"
  case parameters = "Parameters"
  case indexes = "Indexes"
  case keys = "Keys"
  case triggers = "Triggers"
  case constraints = "Constraints"
  case logins = "Logins"
  case users = "Users"
  case roles = "Server Roles"
  case linkedServers = "Linked Servers"
  case activity = "Activity Monitor"
  case sessions = "Sessions"
  case locks = "Locks & Blocking"
  case files = "Database Files"
  case jobs = "Jobs"
  case jobHistory = "Job History"
  case schedules = "Schedules"
}
public struct CatalogItem: Sendable {
  public let id: Int
  public let name: String
  public let schema: String
  public let detail: String
  public init(id: Int = 0, name: String, schema: String = "", detail: String = "") {
    self.id = id
    self.name = name
    self.schema = schema
    self.detail = detail
  }
  public var qualified: String {
    schema.isEmpty ? SQL.identifier(name) : SQL.identifier(schema) + "." + SQL.identifier(name)
  }
}
public enum Catalog {
  public static let databases =
    "SELECT database_id,name,CAST('' AS nvarchar(1)),state_desc FROM sys.databases WHERE HAS_DBACCESS(name)=1 ORDER BY CASE WHEN database_id<=4 THEN 0 ELSE 1 END,name;"
  public static func indexPage(after: Int) -> String {
    "SELECT TOP (1000) o.object_id,o.name,s.name,o.type_desc FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id WHERE o.object_id>\(max(0,after)) AND o.is_ms_shipped=0 AND o.type IN ('U','V','P','PC','FN','IF','TF','FS','FT','SN') ORDER BY o.object_id;"
  }
  public static func searchObjects(_ text: String, operation: Int, folder: Folder?) -> String {
    let value = SQL.literal(text)
    let name = "s.name + N'.' + o.name"
    let predicate: String
    switch operation {
    case 1: predicate = "(o.name=\(value) OR \(name)=\(value))"
    case 2: predicate = "(LEFT(o.name,LEN(\(value)))=\(value) OR LEFT(\(name),LEN(\(value)))=\(value))"
    case 3: predicate = "RIGHT(\(name),LEN(\(value)))=\(value)"
    case 4: predicate = "CHARINDEX(\(value),\(name))=0"
    default: predicate = "CHARINDEX(\(value),\(name))>0"
    }
    let types: String
    switch folder {
    case .tables: types = "'U'"
    case .views: types = "'V'"
    case .procedures: types = "'P','PC'"
    case .functions: types = "'FN','IF','TF','FS','FT'"
    case .synonyms: types = "'SN'"
    default: types = "'U','V','P','PC','FN','IF','TF','FS','FT','SN'"
    }
    return "SELECT TOP (501) o.object_id,o.name,s.name,o.type_desc FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id WHERE o.is_ms_shipped=0 AND o.type IN (\(types)) AND \(predicate) ORDER BY s.name,o.name;"
  }
  public static func objects(_ folder: Folder) -> String {
    let types: String
    switch folder {
    case .tables: types = "'U'"
    case .views: types = "'V'"
    case .procedures: types = "'P','PC'"
    case .functions: types = "'FN','IF','TF','FS','FT'"
    case .logins:
      return
        "SELECT principal_id,name,N'',type_desc FROM sys.server_principals WHERE type IN ('S','U','G','E','X') ORDER BY name;"
    case .roles:
      return
        "SELECT principal_id,name,N'',type_desc FROM sys.server_principals WHERE type='R' ORDER BY name;"
    case .users:
      return
        "SELECT principal_id,name,N'',type_desc FROM sys.database_principals WHERE principal_id>4 AND type IN ('S','U','G','E','X') ORDER BY name;"
    case .linkedServers:
      return
        "SELECT server_id,name,N'',product + ' · ' + COALESCE(data_source,'') FROM sys.servers WHERE is_linked=1 ORDER BY name;"
    case .jobs:
      return
        "SELECT 0,j.name,N'',CASE WHEN j.enabled=1 THEN 'Enabled' ELSE 'Disabled' END + CASE WHEN EXISTS(SELECT 1 FROM msdb.dbo.sysjobactivity a WHERE a.job_id=j.job_id AND a.session_id=(SELECT MAX(session_id) FROM msdb.dbo.syssessions) AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL) THEN ', Running' ELSE ', Idle' END FROM msdb.dbo.sysjobs j ORDER BY j.name;"
    case .schedules:
      return
        "SELECT schedule_id,name,N'',CASE WHEN enabled=1 THEN 'Enabled' ELSE 'Disabled' END FROM msdb.dbo.sysschedules ORDER BY name;"
    case .synonyms: types = "'SN'"
    case .triggers: return "SELECT object_id,name,N'',type_desc+CASE WHEN is_disabled=1 THEN N', Disabled' ELSE N', Enabled' END FROM sys.triggers WHERE parent_class=0 AND is_ms_shipped=0 ORDER BY name;"
    default: return "SELECT 0,N'',N'',N'' WHERE 1=0;"
    }
    return
      "SELECT o.object_id,o.name,s.name,o.type_desc FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id WHERE o.type IN (\(types)) AND o.is_ms_shipped=0 ORDER BY s.name,o.name;"
  }
  public static func children(_ folder: Folder, object: Int) -> String {
    switch folder {
    case .parameters:
      return
        "SELECT p.parameter_id,COALESCE(NULLIF(p.name,N''),N'Return Value'),N'',t.name + CASE WHEN p.is_output=1 THEN ', output' ELSE '' END FROM sys.parameters p JOIN sys.types t ON t.user_type_id=p.user_type_id WHERE p.object_id=\(object) ORDER BY p.parameter_id;"
    case .columns:
      return
        "SELECT c.column_id,c.name,N'',ty.name + CASE WHEN ty.name IN ('nvarchar','nchar') THEN '('+CASE WHEN c.max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),c.max_length/2) END+')' WHEN ty.name IN ('varchar','varbinary','char','binary') THEN '('+CASE WHEN c.max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),c.max_length) END+')' ELSE '' END + CASE WHEN c.is_nullable=1 THEN ', null' ELSE ', not null' END + CASE WHEN c.is_identity=1 THEN ', identity' ELSE '' END + CASE WHEN c.is_computed=1 THEN ', computed' ELSE '' END FROM sys.columns c JOIN sys.types ty ON ty.user_type_id=c.user_type_id WHERE c.object_id=\(object) ORDER BY c.column_id;"
    case .indexes:
      return
        "SELECT index_id,name,N'',type_desc+CASE WHEN is_unique=1 THEN ', unique' ELSE '' END FROM sys.indexes WHERE object_id=\(object) AND index_id>0 ORDER BY name;"
    case .keys:
      return
        "SELECT object_id,name,N'',type_desc FROM sys.key_constraints WHERE parent_object_id=\(object) UNION ALL SELECT object_id,name,N'',type_desc FROM sys.foreign_keys WHERE parent_object_id=\(object);"
    case .triggers:
      return "SELECT object_id,name,OBJECT_SCHEMA_NAME(object_id),type_desc+CASE WHEN is_disabled=1 THEN N', Disabled' ELSE N', Enabled' END FROM sys.triggers WHERE parent_id=\(object) AND parent_class=1 ORDER BY name;"
    case .constraints:
      return
        "SELECT object_id,name,N'',type_desc FROM sys.objects WHERE parent_object_id=\(object) AND type IN ('C','D');"
    default: return "SELECT 0,N'',N'',N'' WHERE 1=0;"
    }
  }
  public static func rows(_ execution: Execution) -> [CatalogItem] {
    (execution.results.first?.values ?? []).compactMap { row in
      guard row.count >= 4, let name = row[1] else { return nil }
      return CatalogItem(
        id: row[0].flatMap(Int.init) ?? 0, name: name, schema: row[2] ?? "", detail: row[3] ?? "")
    }
  }
  public static let symbols =
    "SELECT s.name,o.name,c.name FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id LEFT JOIN sys.columns c ON c.object_id=o.object_id WHERE o.is_ms_shipped=0 AND o.type IN ('U','V','IF','TF') ORDER BY s.name,o.name,c.column_id;"
  public static func symbols(_ execution: Execution) -> [CatalogSymbol] {
    var collected: [String: (String, String, [String])] = [:]
    for row in execution.results.first?.values ?? [] where row.count >= 3 {
      guard let schema = row[0], let name = row[1] else { continue }
      let key = schema + "." + name
      var value = collected[key] ?? (schema, name, [])
      if let column = row[2] { value.2.append(column) }
      collected[key] = value
    }
    return collected.values.map { CatalogSymbol(schema: $0.0, name: $0.1, columns: $0.2) }
  }
  /// Column-only preview, explicitly labelled as incomplete in the editor.
  public static func tableColumnDefinition(_ id: Int) -> String {
    """
    SELECT STRING_AGG(CONVERT(nvarchar(max),N'    '+QUOTENAME(c.name)+N' '+
      CASE WHEN cc.object_id IS NOT NULL THEN N'AS '+cc.definition+CASE WHEN cc.is_persisted=1 THEN N' PERSISTED' ELSE N'' END
      ELSE CASE WHEN t.is_user_defined=1 THEN QUOTENAME(SCHEMA_NAME(t.schema_id))+N'.' ELSE N'' END+QUOTENAME(t.name)+CASE WHEN t.is_user_defined=1 THEN N''
        WHEN t.name IN ('varchar','char','varbinary','binary') THEN N'('+CASE WHEN c.max_length=-1 THEN N'max' ELSE CONVERT(nvarchar(10),c.max_length) END+N')'
        WHEN t.name IN ('nvarchar','nchar') THEN N'('+CASE WHEN c.max_length=-1 THEN N'max' ELSE CONVERT(nvarchar(10),c.max_length/2) END+N')'
        WHEN t.name IN ('decimal','numeric') THEN N'('+CONVERT(nvarchar(10),c.precision)+N','+CONVERT(nvarchar(10),c.scale)+N')'
        WHEN t.name IN ('datetime2','datetimeoffset','time') THEN N'('+CONVERT(nvarchar(10),c.scale)+N')' ELSE N'' END
        +CASE WHEN ic.object_id IS NOT NULL THEN N' IDENTITY('+CONVERT(nvarchar(40),ic.seed_value)+N','+CONVERT(nvarchar(40),ic.increment_value)+N')' ELSE N'' END
        +CASE WHEN c.is_nullable=1 THEN N' NULL' ELSE N' NOT NULL' END
        +CASE WHEN dc.object_id IS NOT NULL THEN N' DEFAULT '+dc.definition ELSE N'' END END),N','+CHAR(10)) WITHIN GROUP (ORDER BY c.column_id)
    FROM sys.columns c JOIN sys.types t ON t.user_type_id=c.user_type_id
    LEFT JOIN sys.computed_columns cc ON cc.object_id=c.object_id AND cc.column_id=c.column_id
    LEFT JOIN sys.identity_columns ic ON ic.object_id=c.object_id AND ic.column_id=c.column_id
    LEFT JOIN sys.default_constraints dc ON dc.object_id=c.default_object_id WHERE c.object_id=\(id);
    """
  }
  public static func definition(_ id: Int) -> String { "SELECT OBJECT_DEFINITION(\(id));" }
  public static func monitoring(_ folder: Folder) -> String {
    switch folder {
    case .activity:
      return
        "SELECT r.session_id,s.login_name,DB_NAME(r.database_id) AS database_name,r.status,r.command,r.cpu_time,r.total_elapsed_time,r.logical_reads,r.wait_type,r.blocking_session_id,t.text FROM sys.dm_exec_requests r JOIN sys.dm_exec_sessions s ON s.session_id=r.session_id OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t WHERE s.is_user_process=1 AND r.session_id<>@@SPID ORDER BY r.total_elapsed_time DESC;"
    case .sessions:
      return
        "SELECT session_id,login_name,host_name,program_name,status,open_transaction_count,cpu_time,memory_usage,last_request_start_time FROM sys.dm_exec_sessions WHERE is_user_process=1 ORDER BY session_id;"
    case .locks:
      return
        "SELECT request_session_id,resource_type,DB_NAME(resource_database_id) AS database_name,resource_description,request_mode,request_status FROM sys.dm_tran_locks ORDER BY request_session_id;"
    case .files:
      return
        "SELECT DB_NAME(database_id) AS database_name,name,type_desc,physical_name,CONVERT(decimal(18,2),size*8.0/1024) AS size_mb FROM sys.master_files ORDER BY database_id,file_id;"
    case .jobs:
      return
        "SELECT j.name,j.enabled,j.description,SUSER_SNAME(j.owner_sid) AS owner_name,j.date_created,j.date_modified FROM msdb.dbo.sysjobs j ORDER BY j.name;"
    case .jobHistory:
      return
        "SELECT TOP(500) j.name,h.step_id,h.step_name,h.run_status,h.run_date,h.run_time,h.run_duration,h.message FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id=h.job_id ORDER BY h.instance_id DESC;"
    case .schedules:
      return
        "SELECT j.name AS job_name,s.name AS schedule_name,s.enabled,s.freq_type,s.freq_interval,s.active_start_time,s.active_start_date FROM msdb.dbo.sysschedules s LEFT JOIN msdb.dbo.sysjobschedules js ON js.schedule_id=s.schedule_id LEFT JOIN msdb.dbo.sysjobs j ON j.job_id=js.job_id;"
    case .logins:
      return
        "SELECT name,type_desc,is_disabled,default_database_name,create_date,modify_date FROM sys.server_principals WHERE type IN ('S','U','G','E','X') ORDER BY name;"
    case .users:
      return
        "SELECT name,type_desc,authentication_type_desc,default_schema_name,create_date FROM sys.database_principals WHERE principal_id>4 ORDER BY name;"
    case .roles:
      return
        "SELECT r.name AS role_name,m.name AS member_name FROM sys.server_principals r LEFT JOIN sys.server_role_members rm ON rm.role_principal_id=r.principal_id LEFT JOIN sys.server_principals m ON m.principal_id=rm.member_principal_id WHERE r.type='R' ORDER BY r.name,m.name;"
    case .linkedServers:
      return
        "SELECT name,product,provider,data_source,is_linked FROM sys.servers ORDER BY server_id;"
    default:
      return
        "SELECT DB_NAME() AS database_name,@@SPID AS session_id,SERVERPROPERTY('ProductVersion') AS server_version;"
    }
  }
}

/// Short-lived connections never alter query-tab sessions or save credentials.
public enum ServerDiscovery {
  public static func test(_ profile: ServerProfile, password: String) async throws -> String {
    let connection = ODBCConnection()
    do {
      try await connection.connect(profile, password: password)
      let result = try await connection.execute("SELECT DB_NAME();")
      let database = result.results.first?.values.first?.first.flatMap { $0 } ?? profile.database
      await connection.disconnect()
      return database
    } catch {
      await connection.disconnect()
      throw error
    }
  }
  public static func databases(_ profile: ServerProfile, password: String) async throws
    -> [CatalogItem]
  {
    let connection = ODBCConnection()
    do {
      try await connection.connect(profile, password: password)
      let items = Catalog.rows(try await connection.execute(Catalog.databases))
      await connection.disconnect()
      return items
    } catch {
      await connection.disconnect()
      throw error
    }
  }
}

public enum DatabaseListScope: String, CaseIterable, Sendable {
  case all, user, system
}
public enum DatabaseSelection {
  public static func filtered(
    _ items: [CatalogItem], search: String, scope: DatabaseListScope,
    selectedOnly: Bool, chosen: Set<String>
  ) -> [CatalogItem] {
    let words = search.split { $0.isWhitespace || $0 == "," || $0 == ";" }.map(String.init)
    return items.filter { item in
      let system = (1...4).contains(item.id)
      return (scope == .all || (scope == .system ? system : !system))
        && (!selectedOnly || chosen.contains(item.name))
        && words.allSatisfy { item.name.localizedStandardContains($0) }
    }.sorted {
      let order = $0.name.localizedStandardCompare($1.name)
      return order == .orderedSame ? $0.name < $1.name : order == .orderedAscending
    }
  }
  public static func changingVisible(_ visible: [CatalogItem], chosen: Set<String>, select: Bool)
    -> Set<String>
  {
    let names = Set(visible.map(\.name))
    return select ? chosen.union(names) : chosen.subtracting(names)
  }
  public static func defaultName(_ preferred: String, items: [CatalogItem], chosen: Set<String>)
    -> String
  {
    if chosen.contains(preferred), items.contains(where: { $0.name == preferred }) {
      return preferred
    }
    return filtered(items, search: "", scope: .all, selectedOnly: true, chosen: chosen).first?.name
      ?? ""
  }
}

/// OLE DB metadata, queried through the current SQL Server rather than a remote login.
public enum LinkedCatalog {
  public struct Relation: Equatable, Hashable, Sendable {
    public let server: String
    public let catalog: String?
    public let schema: String?
    public let name: String
    public let type: String
    public let remarks: String
    public init(server: String, catalog: String?, schema: String?, name: String, type: String, remarks: String = "") {
      self.server=server; self.catalog=catalog; self.schema=schema; self.name=name; self.type=type; self.remarks=remarks
    }
    public var qualified: String {
      [SQL.identifier(server), catalog.map(SQL.identifier) ?? "", schema.map(SQL.identifier) ?? "", SQL.identifier(name)].joined(separator: ".")
    }
    public var selectSQL: String { "SELECT TOP (1000) *\nFROM \(qualified);" }
    public var group: String {
      switch type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
      case "TABLE", "BASE TABLE": return "Tables"
      case "VIEW": return "Views"
      case "SYSTEM TABLE": return "System Tables"
      case "SYSTEM VIEW": return "System Views"
      case "SYNONYM", "ALIAS": return "Synonyms & Aliases"
      case "GLOBAL TEMPORARY", "LOCAL TEMPORARY": return "Temporary Tables"
      default: return "Other Objects"
      }
    }
  }
  public static func catalogsSQL(server: String) -> String {
    "EXEC master.sys.sp_catalogs @server_name=\(SQL.literal(server));"
  }
  public static func relationsSQL(server: String, catalog: String?) -> String {
    "EXEC master.sys.sp_tables_ex @table_server=\(SQL.literal(server)), @table_catalog=\(catalog.map(SQL.literal) ?? "NULL"), @fUsePattern=0;"
  }
  public static func columnsSQL(_ relation: Relation) -> String {
    "EXEC master.sys.sp_columns_ex @table_server=\(SQL.literal(relation.server)), @table_name=\(SQL.literal(relation.name)), @table_schema=\(relation.schema.map(SQL.literal) ?? "NULL"), @table_catalog=\(relation.catalog.map(SQL.literal) ?? "NULL"), @ODBCVer=3;"
  }
  public static func testSQL(server: String) -> String {
    "EXEC master.sys.sp_testlinkedserver @servername=\(SQL.literal(server));"
  }
  private static func value(_ row: [String?], _ fields: [Field], _ name: String) -> String? {
    guard let i=fields.firstIndex(where: {$0.name.caseInsensitiveCompare(name) == .orderedSame}), i<row.count else {return nil}
    return row[i]
  }
  private static func nonempty(_ value: String?) -> String? {value.flatMap {$0.isEmpty ? nil : $0}}
  public static func catalogs(_ result: Execution) throws -> [String] {
    guard let rows=result.results.first else {return []}
    guard rows.fields.contains(where: {$0.name.caseInsensitiveCompare("CATALOG_NAME") == .orderedSame}) else {throw SQLFailure("Sağlayıcı katalog bilgilerini beklenen biçimde döndürmedi.")}
    return Array(Set(rows.values.compactMap {nonempty(value($0,rows.fields,"CATALOG_NAME"))})).sorted {$0.localizedStandardCompare($1) == .orderedAscending}
  }
  public static func relations(_ result: Execution, server: String, catalog: String?) throws -> [Relation] {
    guard let rows=result.results.first else {return []}
    for name in ["TABLE_NAME", "TABLE_TYPE", "TABLE_CAT", "TABLE_SCHEM"] {
      guard rows.fields.contains(where: {$0.name.caseInsensitiveCompare(name) == .orderedSame}) else {throw SQLFailure("Sağlayıcı nesne bilgilerini beklenen biçimde döndürmedi: \(name)")}
    }
    var seen=Set<Relation>()
    return rows.values.compactMap { row -> Relation? in
      guard let name=nonempty(value(row,rows.fields,"TABLE_NAME")) else {return nil}
      let returnedCatalog=nonempty(value(row,rows.fields,"TABLE_CAT"))
      // Some providers ignore restrictions. Never attribute another catalog's object to this one.
      if let catalog, let returnedCatalog, catalog != returnedCatalog {return nil}
      let item=Relation(server:server,catalog:returnedCatalog ?? catalog,schema:nonempty(value(row,rows.fields,"TABLE_SCHEM")),name:name,type:value(row,rows.fields,"TABLE_TYPE") ?? "UNKNOWN",remarks:value(row,rows.fields,"REMARKS") ?? "")
      return seen.insert(item).inserted ? item : nil
    }.sorted {($0.schema ?? "",$0.name,$0.type)<($1.schema ?? "",$1.name,$1.type)}
  }
  public static func columns(_ result: Execution, relation: Relation) throws -> [CatalogItem] {
    guard let rows=result.results.first else {return []}
    guard rows.fields.contains(where: {$0.name.caseInsensitiveCompare("COLUMN_NAME") == .orderedSame}) else {throw SQLFailure("Sağlayıcı sütun bilgilerini beklenen biçimde döndürmedi.")}
    return rows.values.compactMap { row -> CatalogItem? in
      // Column providers can ignore name restrictions; retain only this exact relation.
      guard value(row,rows.fields,"TABLE_NAME") == relation.name,
        nonempty(value(row,rows.fields,"TABLE_SCHEM")) == relation.schema,
        relation.catalog == nil || nonempty(value(row,rows.fields,"TABLE_CAT")) == nil || nonempty(value(row,rows.fields,"TABLE_CAT")) == relation.catalog,
        let name=nonempty(value(row,rows.fields,"COLUMN_NAME")) else {return nil}
      let nullable=value(row,rows.fields,"IS_NULLABLE") ?? ""
      let detail=(value(row,rows.fields,"TYPE_NAME") ?? "") + (nullable == "YES" ? " · NULL" : nullable == "NO" ? " · NOT NULL" : "")
      return CatalogItem(id:value(row,rows.fields,"ORDINAL_POSITION").flatMap(Int.init) ?? 0,name:name,detail:detail)
    }.sorted {$0.id<$1.id}
  }
}
