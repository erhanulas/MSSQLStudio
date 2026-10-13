import Foundation

public struct TableColumn: Identifiable, Equatable, Sendable, Codable {
  public var id: Int
  public var name: String
  public var type: String
  public var baseType: String?
  public var valueType: String { (type.hasPrefix("[") || type.lowercased() == "sysname") ? (baseType ?? type) : type }
  public var nullable: Bool
  public var identity: Bool
  public var seed: String
  public var increment: String
  public var computed: String
  public var persisted: Bool
  public var defaultName: String
  public var defaultSQL: String
  public var collation: String
  public var sparse: Bool
  public var rowGUID: Bool
  public init(id: Int, name: String, type: String = "nvarchar(100)", nullable: Bool = true, identity: Bool = false, seed: String = "1", increment: String = "1", computed: String = "", persisted: Bool = false, defaultName: String = "", defaultSQL: String = "", collation: String = "", sparse: Bool = false, rowGUID: Bool = false, baseType: String? = nil) {
    self.id=id; self.name=name; self.type=type; self.baseType=baseType; self.nullable=nullable; self.identity=identity; self.seed=seed; self.increment=increment; self.computed=computed; self.persisted=persisted; self.defaultName=defaultName; self.defaultSQL=defaultSQL; self.collation=collation; self.sparse=sparse; self.rowGUID=rowGUID
  }
  public var generated: Bool { identity || !computed.isEmpty || ["timestamp","rowversion"].contains(valueType.lowercased()) }
  public var editableValue: Bool { comparable || ["text", "ntext", "image", "xml"].contains(valueType.lowercased()) }
  public var comparable: Bool { !["text","ntext","image","xml","geography","geometry","hierarchyid","sql_variant"].contains(valueType.lowercased()) && !valueType.hasPrefix("[") }
}
public struct ManagedDefinition: Identifiable, Sendable {
  public var id: String { name }
  public var name: String
  public var kind: String
  public var sql: String
  public init(name:String,kind:String,sql:String) { self.name=name; self.kind=kind; self.sql=sql }
}
public struct TableDefinition: Sendable {
  public var schema: String
  public var name: String
  public var columns: [TableColumn]
  public var primaryKey: [String]
  public var primaryKeyName: String
  public var heapFilegroup = ""
  public var definitions: [ManagedDefinition]
  public var qualified: String { SQL.identifier(schema)+"."+SQL.identifier(name) }
  public init(schema:String,name:String,columns:[TableColumn],primaryKey:[String]=[],primaryKeyName:String="",definitions:[ManagedDefinition]=[]) {
    self.schema=schema; self.name=name; self.columns=columns; self.primaryKey=primaryKey; self.primaryKeyName=primaryKeyName; self.definitions=definitions
  }
  public func createScript() throws -> String {
    guard !columns.isEmpty else { throw SQLFailure("Tablo kolonları okunamadı.") }
    let body = try columns.map { try ObjectScripts.column($0,validateType:false) }.joined(separator:",\n    ")
    return "-- Standard rowstore schema: permissions / extended properties / statistics are not included.\nCREATE TABLE \(qualified)\n(\n    \(body)\n)\(heapFilegroup.isEmpty ? "" : " ON "+SQL.identifier(heapFilegroup));\nGO\n" + definitions.map(\.sql).joined(separator:"\nGO\n") + "\n"
  }
}
public enum ObjectScripts {
  public static func collation(_ value:String) throws -> String {
    guard value.range(of:#"^[A-Za-z0-9_]+$"#,options:.regularExpression) != nil else { throw SQLFailure("Collation adı geçersiz.") }; return value
  }
  public static func validatedType(_ value:String) throws -> String {
    let value=value.trimmingCharacters(in:.whitespacesAndNewlines)
    let pattern = #"^(?:(?:bigint|int|smallint|tinyint|bit|money|smallmoney|real|date|datetime|smalldatetime|uniqueidentifier|xml|sql_variant|rowversion|timestamp)|(?:nvarchar|varchar|varbinary)\((?:max|[1-9][0-9]{0,4})\)|(?:nchar|char|binary)\([1-9][0-9]{0,4}\)|(?:decimal|numeric)\([1-9][0-9]?,[0-9]{1,2}\)|(?:datetime2|datetimeoffset|time)(?:\([0-7]\))?|float(?:\((?:[1-9]|[1-4][0-9]|5[0-3])\))?)$"#
    guard value.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil else { throw SQLFailure("Veri tipi desteklenen SQL Server tipi ve boyutuyla girilmeli: nvarchar(100), decimal(18,2), int…") }
    return value
  }
  public static func column(_ c:TableColumn,validateType:Bool=true) throws -> String {
    guard !c.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw SQLFailure("Kolon adı boş olamaz.") }
    if !c.computed.isEmpty { return SQL.identifier(c.name)+" AS "+c.computed+(c.persisted ? " PERSISTED" : "") }
    let type = validateType ? try validatedType(c.type) : c.type
    if c.identity && (c.nullable || c.seed.range(of:#"^-?[0-9]+$"#,options:.regularExpression) == nil || c.increment.range(of:#"^-?[0-9]+$"#,options:.regularExpression) == nil || Decimal(string:c.increment) == 0) { throw SQLFailure("Identity seed / increment sayısal olmalı.") }
    return SQL.identifier(c.name)+" "+type+(c.collation.isEmpty ? "" : " COLLATE "+(try collation(c.collation)))+(c.sparse ? " SPARSE" : "")+(c.identity ? " IDENTITY(\(c.seed),\(c.increment))" : "")+(c.rowGUID ? " ROWGUIDCOL" : "")+(c.nullable ? " NULL" : " NOT NULL")+(c.defaultSQL.isEmpty ? "" : (c.defaultName.isEmpty ? " DEFAULT " : " CONSTRAINT "+SQL.identifier(c.defaultName)+" DEFAULT ")+c.defaultSQL)
  }
  public static func transaction(_ sql:String) -> String {
    """
    IF @@TRANCOUNT <> 0 THROW 51000, N'Bu değişiklik için açık transaction olmayan bir sorgu sekmesi kullanın.', 1;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
    \(sql)
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
    """
  }
  public static func tableChanges(original:TableDefinition?,schema:String,name:String,columns:[TableColumn],primaryKey:[String]) throws -> String {
    guard !schema.isEmpty, !name.isEmpty, !columns.isEmpty, columns.count <= 1024, Set(columns.map { $0.name.lowercased() }).count == columns.count else { throw SQLFailure("Şema, tablo ve benzersiz kolon adları gerekli.") }
    guard primaryKey.allSatisfy({ key in columns.contains { $0.name == key && !$0.nullable } }) else { throw SQLFailure("Primary key kolonları NOT NULL olmalı.") }
    let table=SQL.identifier(schema)+"."+SQL.identifier(name)
    guard let original else {
      let body=try columns.map { try column($0) }.joined(separator:",\n    ")
      let pk=primaryKey.isEmpty ? "" : ",\n    CONSTRAINT \(SQL.identifier("PK_"+name)) PRIMARY KEY (\(primaryKey.map(SQL.identifier).joined(separator:", ")))"
      return transaction("CREATE TABLE \(table) (\n    \(body)\(pk)\n);")
    }
    guard original.schema == schema, original.name == name else { throw SQLFailure("Tablo adını Rename penceresinden değiştirin.") }
    var actions:[String]=[]
    let pkChanged=original.primaryKey != primaryKey || original.primaryKey.contains { old in !columns.contains { $0.name == old } }
    if pkChanged && !original.primaryKeyName.isEmpty { actions.append("ALTER TABLE \(table) DROP CONSTRAINT \(SQL.identifier(original.primaryKeyName));") }
    for old in original.columns {
      let updated=columns.first { $0.id == old.id }
      if (!old.defaultName.isEmpty && (updated == nil || updated?.defaultSQL != old.defaultSQL)) { actions.append("ALTER TABLE \(table) DROP CONSTRAINT \(SQL.identifier(old.defaultName));") }
      guard let c=updated else { actions.append("ALTER TABLE \(table) DROP COLUMN \(SQL.identifier(old.name));"); continue }
      if c.identity != old.identity || c.computed != old.computed { throw SQLFailure("Mevcut identity/computed kolonu yeniden oluşturmadan değiştirilemez.") }
      if c.name != old.name { actions.append("EXEC sys.sp_rename @objname=\(SQL.literal(table+"."+SQL.identifier(old.name))), @newname=\(SQL.literal(c.name)), @objtype=N'COLUMN';") }
      if c.type != old.type || c.nullable != old.nullable {
        guard !old.generated else { throw SQLFailure("Üretilen kolonun tipi/NULL özelliği tasarım ekranından değiştirilemez.") }
        let type=c.type == old.type ? c.type : try validatedType(c.type)
        actions.append("ALTER TABLE \(table) ALTER COLUMN \(SQL.identifier(c.name)) \(type)\(c.collation.isEmpty ? "" : " COLLATE "+(try collation(c.collation)))\(c.nullable ? " NULL" : " NOT NULL");")
      }
      if c.defaultSQL != old.defaultSQL && !c.defaultSQL.isEmpty { actions.append("ALTER TABLE \(table) ADD DEFAULT \(c.defaultSQL) FOR \(SQL.identifier(c.name));") }
    }
    for c in columns where !original.columns.contains(where: { $0.id == c.id }) { actions.append("ALTER TABLE \(table) ADD \(try column(c));") }
    if pkChanged && !primaryKey.isEmpty { actions.append("ALTER TABLE \(table) ADD CONSTRAINT \(SQL.identifier(original.primaryKeyName.isEmpty ? "PK_"+name : original.primaryKeyName)) PRIMARY KEY (\(primaryKey.map(SQL.identifier).joined(separator:", ")));") }
    guard !actions.isEmpty else { throw SQLFailure("Değişiklik yok.") }
    return transaction(actions.joined(separator:"\n"))
  }
  public static func module(_ source:String,verb:String) throws -> String {
    let tokens=TSQL.lex(source).filter { ![.space,.comment].contains($0.kind) }
    guard let first=tokens.first, ["CREATE","ALTER"].contains(first.text.uppercased()) else { throw SQLFailure("CREATE/ALTER modül tanımı okunamadı.") }
    let end = tokens.count > 2 && tokens[1].text.uppercased() == "OR" && tokens[2].text.uppercased() == "ALTER" ? NSMaxRange(tokens[2].range) : NSMaxRange(first.range)
    guard ["CREATE","ALTER","CREATE OR ALTER"].contains(verb) else { throw SQLFailure("Script türü geçersiz.") }
    return (source as NSString).replacingCharacters(in:NSRange(location:first.range.location,length:end-first.range.location),with:verb)
  }
  public static func drop(qualified:String,view:Bool) -> String { "DROP \(view ? "VIEW" : "TABLE") \(qualified);" }
  public static func rename(qualified:String,name:String) throws -> String {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw SQLFailure("Yeni ad boş olamaz.") }
    return "EXEC sys.sp_rename @objname=\(SQL.literal(qualified)), @newname=\(SQL.literal(name)), @objtype=N'OBJECT';"
  }
  public static func foreignKey(table:String,name:String,columns:[String],referencedSchema:String,referencedTable:String,referencedColumns:[String],onDelete:String="NO ACTION",onUpdate:String="NO ACTION") throws -> String {
    guard !name.isEmpty, !columns.isEmpty, columns.count == referencedColumns.count, !referencedSchema.isEmpty, !referencedTable.isEmpty, ["NO ACTION","CASCADE","SET NULL","SET DEFAULT"].contains(onDelete), ["NO ACTION","CASCADE","SET NULL","SET DEFAULT"].contains(onUpdate) else { throw SQLFailure("İlişki adı ve eşleşen kaynak/hedef kolonlar gerekli.") }
    return "ALTER TABLE \(table) WITH CHECK ADD CONSTRAINT \(SQL.identifier(name)) FOREIGN KEY (\(columns.map(SQL.identifier).joined(separator:", "))) REFERENCES \(SQL.identifier(referencedSchema)).\(SQL.identifier(referencedTable)) (\(referencedColumns.map(SQL.identifier).joined(separator:", "))) ON DELETE \(onDelete) ON UPDATE \(onUpdate);"
  }
}

public enum ObjectMetadata {
  public static func table(_ id:Int) -> String { tableSQL(String(id), includeDefinitions: true) }
  public static func editingTable(schema: String, name: String) -> String {
    let objectID = "OBJECT_ID(\(SQL.literal(SQL.identifier(schema)+"."+SQL.identifier(name))), N'U')"
    return "SELECT object_id FROM sys.tables WHERE object_id=\(objectID);\n" + tableSQL(objectID, includeDefinitions: false)
  }
  public static func decodeEditing(_ result: Execution, schema: String, name: String) throws -> (objectID: Int, table: TableDefinition) {
    guard !result.partial, result.results.count == 4, result.results[0].values.count == 1,
      let objectID = result.results[0].values.first?.first.flatMap({ $0 }).flatMap(Int.init), objectID > 0 else { throw SQLFailure("Kaynak bir yerel kullanıcı tablosu değil veya metadata eksik.") }
    var compatible = Execution()
    compatible.results = [result.results[1], result.results[2], Rows(), Rows(), Rows(), Rows(), result.results[3]]
    return (objectID, try decode(compatible, schema: schema, name: name))
  }
  private static func tableSQL(_ id:String, includeDefinitions: Bool) -> String {
    let columns = """
    SELECT c.column_id,c.name,
      CASE WHEN t.is_user_defined=1 THEN (QUOTENAME(SCHEMA_NAME(t.schema_id)) COLLATE DATABASE_DEFAULT)+'.'+(QUOTENAME(t.name) COLLATE DATABASE_DEFAULT) ELSE t.name END+
      CASE WHEN t.is_user_defined=1 THEN '' WHEN t.name IN ('varchar','char','binary','varbinary') THEN '('+CASE WHEN c.max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),c.max_length) END+')'
      WHEN t.name IN ('nvarchar','nchar') THEN '('+CASE WHEN c.max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),c.max_length/2) END+')'
      WHEN t.name IN ('numeric','decimal') THEN '('+CONVERT(varchar(10),c.precision)+','+CONVERT(varchar(10),c.scale)+')'
      WHEN t.name IN ('time','datetime2','datetimeoffset') THEN '('+CONVERT(varchar(10),c.scale)+')' ELSE '' END,
      c.is_nullable,c.is_identity,CONVERT(nvarchar(40),ic.seed_value),CONVERT(nvarchar(40),ic.increment_value),cc.definition,cc.is_persisted,dc.name,dc.definition,c.collation_name,c.is_sparse,c.is_rowguidcol,
      CASE WHEN c.is_filestream=1 OR c.generated_always_type<>0 OR c.encryption_type IS NOT NULL OR c.is_hidden=1 THEN 1 ELSE 0 END,
      CASE WHEN t.is_assembly_type=0 AND t.is_table_type=0 THEN st.name+
        CASE WHEN st.name IN ('varchar','char','binary','varbinary') THEN '('+CASE WHEN c.max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),c.max_length) END+')'
        WHEN st.name IN ('nvarchar','nchar') THEN '('+CASE WHEN c.max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),c.max_length/2) END+')'
        WHEN st.name IN ('numeric','decimal') THEN '('+CONVERT(varchar(10),c.precision)+','+CONVERT(varchar(10),c.scale)+')'
        WHEN st.name IN ('time','datetime2','datetimeoffset') THEN '('+CONVERT(varchar(10),c.scale)+')' ELSE '' END END
    FROM sys.columns c JOIN sys.types t ON t.user_type_id=c.user_type_id
    LEFT JOIN sys.types st ON st.user_type_id=t.system_type_id AND st.user_type_id=st.system_type_id
    LEFT JOIN sys.identity_columns ic ON ic.object_id=c.object_id AND ic.column_id=c.column_id
    LEFT JOIN sys.computed_columns cc ON cc.object_id=c.object_id AND cc.column_id=c.column_id
    LEFT JOIN sys.default_constraints dc ON dc.object_id=c.default_object_id WHERE c.object_id=\(id) ORDER BY c.column_id;
    SELECT c.name,k.name FROM sys.key_constraints k JOIN sys.index_columns ic ON ic.object_id=k.parent_object_id AND ic.index_id=k.unique_index_id JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE k.parent_object_id=\(id) AND k.type='PK' ORDER BY ic.key_ordinal;
    """
    let definitions = """
    SELECT i.name,CASE WHEN i.is_primary_key=1 THEN 'PK' WHEN i.is_unique_constraint=1 THEN 'UQ' ELSE 'INDEX' END,
      CASE WHEN i.is_primary_key=1 OR i.is_unique_constraint=1 THEN N'ALTER TABLE '+(QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id)) COLLATE DATABASE_DEFAULT)+N'.'+(QUOTENAME(OBJECT_NAME(i.object_id)) COLLATE DATABASE_DEFAULT)+N' ADD CONSTRAINT '+(QUOTENAME(i.name) COLLATE DATABASE_DEFAULT)+CASE WHEN i.is_primary_key=1 THEN N' PRIMARY KEY ' ELSE N' UNIQUE ' END
      ELSE N'CREATE '+CASE WHEN i.is_unique=1 THEN N'UNIQUE ' ELSE N'' END END+
      CASE WHEN i.type=1 THEN N'CLUSTERED' ELSE N'NONCLUSTERED' END+
      CASE WHEN i.is_primary_key=0 AND i.is_unique_constraint=0 THEN N' INDEX '+(QUOTENAME(i.name) COLLATE DATABASE_DEFAULT)+N' ON '+(QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id)) COLLATE DATABASE_DEFAULT)+N'.'+(QUOTENAME(OBJECT_NAME(i.object_id)) COLLATE DATABASE_DEFAULT) ELSE N'' END+
      N' ('+k.keys+N')'+CASE WHEN inc.cols IS NOT NULL THEN N' INCLUDE ('+inc.cols+N')' ELSE N'' END+
      CASE WHEN i.has_filter=1 THEN N' WHERE '+i.filter_definition COLLATE DATABASE_DEFAULT ELSE N'' END+
      N' WITH (PAD_INDEX = '+CASE WHEN i.is_padded=1 THEN N'ON' ELSE N'OFF' END+N', IGNORE_DUP_KEY = '+CASE WHEN i.ignore_dup_key=1 THEN N'ON' ELSE N'OFF' END+N', ALLOW_ROW_LOCKS = '+CASE WHEN i.allow_row_locks=1 THEN N'ON' ELSE N'OFF' END+N', ALLOW_PAGE_LOCKS = '+CASE WHEN i.allow_page_locks=1 THEN N'ON' ELSE N'OFF' END+N', FILLFACTOR = '+CONVERT(nvarchar(3),CASE WHEN i.fill_factor=0 THEN 100 ELSE i.fill_factor END)+N')'+CASE WHEN ds.type='FG' THEN N' ON '+(QUOTENAME(ds.name) COLLATE DATABASE_DEFAULT) ELSE N'' END+N';'+CASE WHEN i.is_disabled=1 THEN N' ALTER INDEX '+(QUOTENAME(i.name) COLLATE DATABASE_DEFAULT)+N' ON '+(QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id)) COLLATE DATABASE_DEFAULT)+N'.'+(QUOTENAME(OBJECT_NAME(i.object_id)) COLLATE DATABASE_DEFAULT)+N' DISABLE;' ELSE N'' END
    FROM sys.indexes i LEFT JOIN sys.data_spaces ds ON ds.data_space_id=i.data_space_id
    OUTER APPLY (SELECT STRING_AGG(CONVERT(nvarchar(max),(QUOTENAME(c.name) COLLATE DATABASE_DEFAULT)+CASE WHEN ic.is_descending_key=1 THEN N' DESC' ELSE N' ASC' END),N', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS keys FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.key_ordinal>0) k
    OUTER APPLY (SELECT STRING_AGG(CONVERT(nvarchar(max),(QUOTENAME(c.name) COLLATE DATABASE_DEFAULT)),N', ') WITHIN GROUP (ORDER BY ic.index_column_id) AS cols FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.is_included_column=1) inc
    WHERE i.object_id=\(id) AND i.index_id>0 AND i.type IN (1,2) ORDER BY i.is_primary_key DESC,i.is_unique_constraint DESC,i.index_id;
    SELECT fk.name,'FK',N'ALTER TABLE '+(QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) COLLATE DATABASE_DEFAULT)+N'.'+(QUOTENAME(OBJECT_NAME(fk.parent_object_id)) COLLATE DATABASE_DEFAULT)+CASE WHEN fk.is_not_trusted=1 THEN N' WITH NOCHECK' ELSE N' WITH CHECK' END+N' ADD CONSTRAINT '+(QUOTENAME(fk.name) COLLATE DATABASE_DEFAULT)+N' FOREIGN KEY ('+a.cols+N') REFERENCES '+(QUOTENAME(OBJECT_SCHEMA_NAME(fk.referenced_object_id)) COLLATE DATABASE_DEFAULT)+N'.'+(QUOTENAME(OBJECT_NAME(fk.referenced_object_id)) COLLATE DATABASE_DEFAULT)+N' ('+b.cols+N') ON DELETE '+REPLACE(fk.delete_referential_action_desc COLLATE DATABASE_DEFAULT,'_',' ')+N' ON UPDATE '+REPLACE(fk.update_referential_action_desc COLLATE DATABASE_DEFAULT,'_',' ')+CASE WHEN fk.is_not_for_replication=1 THEN N' NOT FOR REPLICATION' ELSE N'' END+N';'+CASE WHEN fk.is_disabled=1 THEN N' ALTER TABLE '+(QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) COLLATE DATABASE_DEFAULT)+N'.'+(QUOTENAME(OBJECT_NAME(fk.parent_object_id)) COLLATE DATABASE_DEFAULT)+N' NOCHECK CONSTRAINT '+(QUOTENAME(fk.name) COLLATE DATABASE_DEFAULT)+N';' ELSE N'' END
    FROM sys.foreign_keys fk
    CROSS APPLY (SELECT STRING_AGG(CONVERT(nvarchar(max),(QUOTENAME(pc.name) COLLATE DATABASE_DEFAULT)),N', ') WITHIN GROUP (ORDER BY c.constraint_column_id) AS cols FROM sys.foreign_key_columns c JOIN sys.columns pc ON pc.object_id=c.parent_object_id AND pc.column_id=c.parent_column_id WHERE c.constraint_object_id=fk.object_id) a
    CROSS APPLY (SELECT STRING_AGG(CONVERT(nvarchar(max),(QUOTENAME(rc.name) COLLATE DATABASE_DEFAULT)),N', ') WITHIN GROUP (ORDER BY c.constraint_column_id) AS cols FROM sys.foreign_key_columns c JOIN sys.columns rc ON rc.object_id=c.referenced_object_id AND rc.column_id=c.referenced_column_id WHERE c.constraint_object_id=fk.object_id) b WHERE fk.parent_object_id=\(id);
    SELECT c.name,'CHECK',N'ALTER TABLE '+(QUOTENAME(OBJECT_SCHEMA_NAME(c.parent_object_id)) COLLATE DATABASE_DEFAULT)+N'.'+(QUOTENAME(OBJECT_NAME(c.parent_object_id)) COLLATE DATABASE_DEFAULT)+CASE WHEN c.is_not_trusted=1 THEN N' WITH NOCHECK' ELSE N' WITH CHECK' END+N' ADD CONSTRAINT '+(QUOTENAME(c.name) COLLATE DATABASE_DEFAULT)+N' CHECK '+CASE WHEN c.is_not_for_replication=1 THEN N'NOT FOR REPLICATION ' ELSE N'' END+(c.definition COLLATE DATABASE_DEFAULT)+N';'+CASE WHEN c.is_disabled=1 THEN N' ALTER TABLE '+(QUOTENAME(OBJECT_SCHEMA_NAME(c.parent_object_id)) COLLATE DATABASE_DEFAULT)+N'.'+(QUOTENAME(OBJECT_NAME(c.parent_object_id)) COLLATE DATABASE_DEFAULT)+N' NOCHECK CONSTRAINT '+(QUOTENAME(c.name) COLLATE DATABASE_DEFAULT)+N';' ELSE N'' END FROM sys.check_constraints c WHERE c.parent_object_id=\(id);
    SELECT t.name,'TRIGGER',(OBJECT_DEFINITION(t.object_id) COLLATE DATABASE_DEFAULT)+CASE WHEN t.is_disabled=1 THEN CHAR(10)+N'GO'+CHAR(10)+N'DISABLE TRIGGER '+(QUOTENAME(OBJECT_SCHEMA_NAME(t.object_id)) COLLATE DATABASE_DEFAULT)+N'.'+(QUOTENAME(t.name) COLLATE DATABASE_DEFAULT)+N' ON '+(QUOTENAME(OBJECT_SCHEMA_NAME(t.parent_id)) COLLATE DATABASE_DEFAULT)+N'.'+(QUOTENAME(OBJECT_NAME(t.parent_id)) COLLATE DATABASE_DEFAULT)+N';' ELSE N'' END FROM sys.triggers t WHERE t.parent_id=\(id);
    """
    let flags = """
    SELECT CASE WHEN t.temporal_type<>0 OR t.is_memory_optimized=1 OR t.is_filetable=1 OR t.is_node=1 OR t.is_edge=1
      OR EXISTS(SELECT 1 FROM sys.indexes i LEFT JOIN sys.data_spaces d ON d.data_space_id=i.data_space_id WHERE i.object_id=t.object_id AND (i.type>2 OR d.type='PS'))
      OR EXISTS(SELECT 1 FROM sys.partitions p WHERE p.object_id=t.object_id AND p.data_compression<>0)
      THEN 1 ELSE 0 END,ds.name FROM sys.tables t LEFT JOIN sys.indexes i ON i.object_id=t.object_id AND i.index_id=0 LEFT JOIN sys.data_spaces ds ON ds.data_space_id=i.data_space_id WHERE t.object_id=\(id);
    """
    return columns + "\n" + (includeDefinitions ? definitions + "\n" : "") + flags
  }
  public static func decode(_ result:Execution,schema:String,name:String) throws -> TableDefinition {
    guard !result.partial, result.results.count == 7 else { throw SQLFailure("Tablo metadata eksik/kısmi; script oluşturulmadı.") }
    func value(_ row:[String?],_ i:Int) -> String { row.indices.contains(i) ? row[i] ?? "" : "" }
    guard let flags=result.results[6].values.first, flags.first != "1", flags.first != nil else { throw SQLFailure("Temporal/graph/memory-optimized/partition/compression gibi özel tablo özellikleri bu tasarım sürümünde desteklenmiyor.") }
    var columns:[TableColumn]=[]
    for row in result.results[0].values {
      guard let id=Int(value(row,0)), row.count >= 15, value(row,14) != "1" else { throw SQLFailure("Şifreli/FILESTREAM/generated kolon desteklenmiyor; eksik CREATE üretilmedi.") }
      columns.append(TableColumn(id:id,name:value(row,1),type:value(row,2),nullable:value(row,3)=="1",identity:value(row,4)=="1",seed:value(row,5).isEmpty ? "1" : value(row,5),increment:value(row,6).isEmpty ? "1" : value(row,6),computed:value(row,7),persisted:value(row,8)=="1",defaultName:value(row,9),defaultSQL:value(row,10),collation:value(row,11),sparse:value(row,12)=="1",rowGUID:value(row,13)=="1",baseType:value(row,15).isEmpty ? nil : value(row,15)))
    }
    var definitions:[ManagedDefinition]=[]
    for group in result.results[2...5] { for row in group.values {
      guard row.count == 3, let name=row[0], let kind=row[1], let sql=row[2], !sql.isEmpty else { throw SQLFailure("Constraint/trigger tanımı okunamadı; VIEW DEFINITION izni veya şifreli modülü kontrol edin.") }
      definitions.append(.init(name:name,kind:kind,sql:sql))
    } }
    // Keep heap filegroup rather than silently relocating table storage.
    var table=TableDefinition(schema:schema,name:name,columns:columns,primaryKey:result.results[1].values.compactMap { $0.first ?? nil },primaryKeyName:result.results[1].values.first.flatMap { $0.count > 1 ? $0[1] : nil } ?? "",definitions:definitions)
    if columns.isEmpty { throw SQLFailure("Kolon bilgisi görünmüyor; VIEW DEFINITION iznini kontrol edin.") }
    if let heap=flags.count > 1 ? flags[1] : nil, !heap.isEmpty { table.heapFilegroup=heap }
    return table
  }
}

public struct DataEditRow: Identifiable, Sendable {
  public let id: UUID
  public var original: [String?]?
  public var values: [String?]
  public var touched: Set<Int>
  public var deleted: Bool
  public init(original:[String?]?,values:[String?],touched:Set<Int>=[],deleted:Bool=false) { id=UUID(); self.original=original; self.values=values; self.touched=touched; self.deleted=deleted }
}
public enum DataEditScripts {
  public enum RowMatching { case optimistic, primaryKeyOrOriginalValues }
  public static func value(_ value:String?,column:TableColumn) throws -> String {
    try ResultValueValidation.validate(value, column: column)
    guard let value else { return "NULL" }
    var column = column
    column.type = column.valueType
    if let type = ["text":"varchar(max)", "ntext":"nvarchar(max)", "image":"varbinary(max)"][column.type.lowercased()] { column.type = type }
    let type=column.type.lowercased()
    if type.hasPrefix("varbinary") || type.hasPrefix("binary") || ["timestamp","rowversion"].contains(type) {
      guard value.range(of:#"^0x(?:[0-9a-fA-F]{2})*$"#,options:.regularExpression) != nil else { throw SQLFailure("Binary değer 0x… biçiminde olmalı.") }
      return value
    }
    _ = try ObjectScripts.validatedType(column.type)
    return "CONVERT(\(column.type), \(SQL.literal(value))\(column.collation.isEmpty ? "" : " COLLATE "+(try ObjectScripts.collation(column.collation))))"
  }
  public static func changes(table:TableDefinition,rows:[DataEditRow],expectedObjectID:Int? = nil,rowMatching:RowMatching = .optimistic) throws -> String {
    guard !table.primaryKey.isEmpty || rowMatching == .primaryKeyOrOriginalValues else { throw SQLFailure("Veri düzenlemesi için primary key gerekli; anahtarsız satırlar yazılmaz.") }
    guard rows.count <= 400 else { throw SQLFailure("En fazla 200 mevcut + 200 yeni satır düzenlenebilir.") }
    let keyIndices=table.primaryKey.compactMap { key in table.columns.firstIndex { $0.name == key } }
    guard keyIndices.count == table.primaryKey.count else { throw SQLFailure("Primary key metadata eksik.") }
    let version=table.columns.firstIndex { ["timestamp","rowversion"].contains($0.valueType.lowercased()) }
    var statements:[String]=[]
    for row in rows {
      guard row.values.count == table.columns.count else { throw SQLFailure("Veri kolonları metadata ile eşleşmiyor.") }
      if row.original == nil {
        if row.deleted { continue }
        let ordinals=row.touched.sorted().filter { table.columns.indices.contains($0) && !table.columns[$0].generated }
        if ordinals.isEmpty { statements.append("INSERT INTO \(table.qualified) DEFAULT VALUES;") }
        else {
          statements.append("INSERT INTO \(table.qualified) (\(ordinals.map { SQL.identifier(table.columns[$0].name) }.joined(separator:", "))) VALUES (\(try ordinals.map { try value(row.values[$0],column:table.columns[$0]) }.joined(separator:", ")));")
        }
        continue
      }
      guard let original=row.original, original.count == row.values.count else { throw SQLFailure("Orijinal satır eksik.") }
      let changed=table.columns.indices.filter { row.values[$0] != original[$0] }
      if changed.isEmpty && !row.deleted { continue }
      guard changed.allSatisfy({ !table.columns[$0].generated && table.columns[$0].editableValue }) else { throw SQLFailure("Üretilen veya desteklenmeyen türdeki kolon değiştirilemez.") }
      let compared:[Int]
      if rowMatching == .primaryKeyOrOriginalValues {
        compared = keyIndices.isEmpty ? table.columns.indices.filter { table.columns[$0].editableValue || ["rowversion", "timestamp"].contains(table.columns[$0].valueType.lowercased()) } : keyIndices
      } else if let version { compared=Array(Set(keyIndices+[version])).sorted() }
      else {
        compared=table.columns.indices.filter { keyIndices.contains($0) || table.columns[$0].editableValue }
      }
      guard !compared.isEmpty else { throw SQLFailure("Satırı güvenle tanımlayacak karşılaştırılabilir kolon yok.") }
      let predicate=try compared.map { i -> String in
        let c=table.columns[i], name=SQL.identifier(c.name)
        guard original[i] != nil else { return name+" IS NULL" }
        let literal=try value(original[i],column:c)
        if ["text", "ntext", "xml"].contains(c.valueType.lowercased()) {
          let cast = c.valueType.lowercased() == "text" ? "varchar(max)" : "nvarchar(max)"
          return "CONVERT(varbinary(max),CONVERT(\(cast),\(name))) = CONVERT(varbinary(max),CONVERT(\(cast),\(literal)))"
        }
        if c.valueType.lowercased() == "image" { return "CONVERT(varbinary(max),\(name)) = \(literal)" }
        if (rowMatching == .optimistic || keyIndices.isEmpty), ["varchar","nvarchar","char","nchar"].contains(where:{ c.valueType.lowercased().hasPrefix($0+"(") }) {
          return "CONVERT(varbinary(max),\(name)) = CONVERT(varbinary(max),\(literal))"
        }
        return name+" = "+literal
      }.joined(separator:" AND ")
      let action = row.deleted ? "DELETE FROM \(table.qualified)" : "UPDATE \(table.qualified) SET \(try changed.map { SQL.identifier(table.columns[$0].name)+" = "+(try value(row.values[$0],column:table.columns[$0])) }.joined(separator:", "))"
      if keyIndices.isEmpty {
        statements.append("IF (SELECT COUNT_BIG(*) FROM \(table.qualified) WITH (UPDLOCK, HOLDLOCK) WHERE \(predicate)) <> 1 THROW 51003, N'Anahtarsız satır tekil olarak bulunamadı; değişiklik gönderilmedi.', 1;")
      }
      statements.append(action+" WHERE "+predicate+";\nIF @@ROWCOUNT <> 1 THROW 51001, N'Satır değişmiş veya bulunamadı; tüm düzenleme geri alındı. Yenileyip tekrar deneyin.', 1;")
    }
    guard !statements.isEmpty else { throw SQLFailure("Değişiklik yok.") }
    if let expectedObjectID {
      guard expectedObjectID > 0 else { throw SQLFailure("Geçersiz kaynak kimliği.") }
      let object = "OBJECT_ID(\(SQL.literal(table.qualified)), N'U')"
      statements.insert("IF \(object) IS NULL OR \(object) <> \(expectedObjectID) THROW 51002, N'Kaynak tablo değişmiş; güncel sonucu yeniden yükleyin.', 1;", at: 0)
    }
    return ObjectScripts.transaction(statements.joined(separator:"\n"))
  }
}


public struct RoutineParameter: Identifiable, Sendable {
  public var id:Int
  public var name:String
  public var type:String
  public var output:Bool
  public var tableType:Bool
  public init(id:Int,name:String,type:String,output:Bool=false,tableType:Bool=false) { self.id=id; self.name=name; self.type=type; self.output=output; self.tableType=tableType }
}
public struct RoutineArgument: Sendable {
  public var value:String
  public var mode:String
  public init(value:String="",mode:String="NULL") { self.value=value; self.mode=mode }
}
public enum RoutineScripts {
  public static func parameters(_ id:Int) -> String {
    """
    SELECT p.parameter_id,p.name,
      CASE WHEN t.is_user_defined=1 THEN QUOTENAME(SCHEMA_NAME(t.schema_id))+'.'+QUOTENAME(t.name) ELSE t.name END+
      CASE WHEN t.is_user_defined=1 THEN '' WHEN t.name IN ('varchar','char','binary','varbinary') THEN '('+CASE WHEN p.max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),p.max_length) END+')'
      WHEN t.name IN ('nvarchar','nchar') THEN '('+CASE WHEN p.max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),p.max_length/2) END+')'
      WHEN t.name IN ('decimal','numeric') THEN '('+CONVERT(varchar(10),p.precision)+','+CONVERT(varchar(10),p.scale)+')'
      WHEN t.name IN ('time','datetime2','datetimeoffset') THEN '('+CONVERT(varchar(10),p.scale)+')' ELSE '' END,p.is_output,t.is_table_type
    FROM sys.parameters p JOIN sys.types t ON t.user_type_id=p.user_type_id WHERE p.object_id=\(id) AND p.parameter_id>0 ORDER BY p.parameter_id;
    """
  }
  public static func decode(_ result:Execution) throws -> [RoutineParameter] {
    guard !result.partial, let rows=result.results.first else { throw SQLFailure("Parametreler eksik/kısmi geldi.") }
    return try rows.values.map { row in
      guard row.count >= 5, let id=row[0].flatMap(Int.init),let name=row[1],let type=row[2] else {throw SQLFailure("Parametre metadata eksik.")}
      return RoutineParameter(id:id,name:name,type:type,output:row[3]=="1",tableType:row[4]=="1")
    }
  }
  public static func invocation(qualified:String,function:Bool,tableValued:Bool=false,parameters:[RoutineParameter],arguments:[Int:RoutineArgument]) throws -> String {
    var declarations:[String]=[],bindings:[String]=[],outputs:[String]=[]
    for p in parameters.sorted(by:{$0.id<$1.id}) {
      guard !p.tableType else { throw SQLFailure("Table-valued parametreyi SQL editöründe DECLARE / INSERT ile hazırlayın.") }
      guard p.name.range(of:#"^@[\p{L}_][\p{L}\p{N}_@$#]*$"#,options:.regularExpression) != nil else {throw SQLFailure("Parametre adı SQL editöründe elle kullanılmalı.")}
      let type=try ObjectScripts.validatedType(p.type)
      let a=arguments[p.id] ?? RoutineArgument()
      guard ["Value","NULL","DEFAULT"].contains(a.mode) else {throw SQLFailure("Parametre seçimi geçersiz.")}
      if a.mode == "DEFAULT" {
        guard !p.output else {throw SQLFailure("OUTPUT parametresi için değer veya NULL seçin.")}
        if function {bindings.append("DEFAULT")}; continue
      }
      let value:String
      if a.mode == "NULL" {value="NULL"}
      else if type.lowercased().hasPrefix("binary") || type.lowercased().hasPrefix("varbinary") {
        guard a.value.range(of:#"^0x(?:[0-9A-Fa-f]{2})*$"#,options:.regularExpression) != nil else {throw SQLFailure("Binary değer 0x ile başlayan çift sayıda hex karakter olmalı.")}; value=a.value
      } else {value="CONVERT(\(type), \(SQL.literal(a.value)))"}
      let variable="@StudioP\(p.id)"
      declarations.append("DECLARE \(variable) \(type) = \(value);")
      bindings.append(function ? variable : "\(p.name) = \(variable)\(p.output ? " OUTPUT" : "")")
      if p.output {outputs.append("\(variable) AS \(SQL.identifier(p.name))")}
    }
    if function {
      return (declarations+[tableValued ? "SELECT TOP (1000) * FROM \(qualified)(\(bindings.joined(separator:", ")));" : "SELECT \(qualified)(\(bindings.joined(separator:", "))) AS [Value];"]).joined(separator:"\n")
    }
    return (["-- Parametreler ve yan etkileri inceleyip Çalıştır kullanın.","DECLARE @StudioReturnValue int;"]+declarations+["EXEC @StudioReturnValue = \(qualified)\(bindings.isEmpty ? "" : "\n    "+bindings.joined(separator:",\n    "));","SELECT "+(["@StudioReturnValue AS [Return Value]"]+outputs).joined(separator:", ")+";"]).joined(separator:"\n")
  }
}
public struct TriggerDefinition: Sendable {
  public var qualified:String
  public var parent:String
  public var databaseScope:Bool
  public var disabled:Bool
  public init(qualified:String,parent:String="",databaseScope:Bool=false,disabled:Bool=false) {self.qualified=qualified;self.parent=parent;self.databaseScope=databaseScope;self.disabled=disabled}
  public var scope:String {databaseScope ? "DATABASE" : parent}
  public func stateScript(enabled:Bool) throws -> String {
    guard databaseScope || !parent.isEmpty else {throw SQLFailure("Trigger'ın bağlı olduğu tablo/view bulunamadı.")}
    return "\(enabled ? "ENABLE" : "DISABLE") TRIGGER \(qualified) ON \(scope);"
  }
  public var dropScript:String {"DROP TRIGGER \(qualified)\(databaseScope ? " ON DATABASE" : "");"}
  public static func metadata(_ id:Int) -> String {
    "SELECT t.name,COALESCE(OBJECT_SCHEMA_NAME(t.object_id),N''),t.parent_class,COALESCE(QUOTENAME(OBJECT_SCHEMA_NAME(t.parent_id))+N'.'+QUOTENAME(OBJECT_NAME(t.parent_id)),N''),t.is_disabled FROM sys.triggers t WHERE t.object_id=\(id);"
  }
  public static func decode(_ result:Execution) throws -> TriggerDefinition {
    guard !result.partial, let row=result.results.first?.values.first,row.count >= 5,let name=row[0],let scope=row[2], ["0","1"].contains(scope) else {throw SQLFailure("Trigger metadata okunamadı.")}
    return TriggerDefinition(qualified:scope == "0" ? SQL.identifier(name) : SQL.identifier(row[1] ?? "dbo")+"."+SQL.identifier(name),parent:row[3] ?? "",databaseScope:scope == "0",disabled:row[4]=="1")
  }
}
public enum ExplorerScripts {
  public static func drop(kind:Folder,qualified:String) throws -> String {
    let type:String
    switch kind {case .tables:type="TABLE";case .views:type="VIEW";case .procedures:type="PROCEDURE";case .functions:type="FUNCTION";case .synonyms:type="SYNONYM";default:throw SQLFailure("Nesne için DROP desteklenmiyor.")}
    return "DROP \(type) \(qualified);"
  }
  public static func module(_ source:String,verb:String,qualified:String,ansi:Bool=true,quoted:Bool=true) throws -> String {
    let tokens=TSQL.lex(source).filter { ![.space,.comment].contains($0.kind) }
    guard let first=tokens.first,["CREATE","ALTER"].contains(first.text.uppercased()) else {throw SQLFailure("T-SQL modül tanımı okunamadı (şifreli/CLR olabilir).")}
    var typeIndex=1
    if tokens.count>3 && tokens[1].text.uppercased()=="OR" && tokens[2].text.uppercased()=="ALTER" {typeIndex=3}
    guard tokens.count>typeIndex+1,["PROC","PROCEDURE","FUNCTION","VIEW","TRIGGER"].contains(tokens[typeIndex].text.uppercased()) else {throw SQLFailure("Modül türü desteklenmiyor.")}
    let start=typeIndex+1;var end=start
    while end+2<tokens.count && tokens[end+1].text=="." {end+=2}
    let normalized=(source as NSString).replacingCharacters(in:NSRange(location:tokens[start].range.location,length:NSMaxRange(tokens[end].range)-tokens[start].range.location),with:qualified)
    return "SET ANSI_NULLS \(ansi ? "ON" : "OFF");\nGO\nSET QUOTED_IDENTIFIER \(quoted ? "ON" : "OFF");\nGO\n"+(try ObjectScripts.module(normalized,verb:verb))
  }
  public static func synonym(qualified:String,target:String) throws -> String {
    let t=TSQL.lex(target).filter { ![.space,.comment].contains($0.kind) }
    guard !t.isEmpty,t.count<=7,t.count%2==1 else {throw SQLFailure("Hedef 1–4 parçalı SQL nesne adı olmalı.")}
    var parts:[String]=[]
    for i in t.indices {
      if i%2==1 {guard t[i].text=="." else {throw SQLFailure("Hedef nesne adı geçersiz.")};continue}
      guard [.word,.keyword].contains(t[i].kind) else {throw SQLFailure("Hedef nesne adı geçersiz.")}
      let x=t[i].text
      let raw=x.hasPrefix("[") ? String(x.dropFirst().dropLast()).replacingOccurrences(of:"]]",with:"]") : x.hasPrefix("\"") ? String(x.dropFirst().dropLast()).replacingOccurrences(of:"\"\"",with:"\"") : x
      guard !raw.isEmpty else {throw SQLFailure("Hedef nesne adı boş olamaz.")};parts.append(SQL.identifier(raw))
    }
    return "CREATE SYNONYM \(qualified) FOR \(parts.joined(separator:"."));"
  }
}

/// Server-supplied provenance, never a table name guessed from SELECT text.
public struct ResultEditSource: Sendable {
  public let database: String
  public let schema: String
  public let table: String
  public let columns: [String]
  public static func metadata(_ sql: String) throws -> String {
    let tokens = TSQL.lex(sql).filter { $0.kind != .space && $0.kind != .comment }
    guard TSQL.canRepeatRead(sql), tokens.filter({ $0.text.uppercased() == "SELECT" }).count == 1,
      !tokens.contains(where: { $0.kind != .string && ["DECLARE", "SET", "JOIN", "APPLY", "UNION", "EXCEPT", "INTERSECT", "GROUP", "DISTINCT", "OVER"].contains($0.text.uppercased()) })
    else { throw SQLFailure("Düzenleme yalnızca tek tabloyu okuyan bir SELECT için desteklenir; JOIN, toplama ve çoklu sorgular salt okunur.") }
    return "SELECT name,source_server,source_database,source_schema,source_table,source_column,error_number,error_message,column_ordinal FROM sys.dm_exec_describe_first_result_set(\(SQL.literal(sql)),NULL,1) WHERE is_hidden=0 OR error_number IS NOT NULL ORDER BY column_ordinal;"
  }
  public static func decode(_ execution: Execution, fields: [Field], database: String) throws -> ResultEditSource {
    guard !execution.partial, let rows = execution.results.first, !fields.isEmpty, rows.values.count == fields.count else { throw SQLFailure("Sonuç kolonlarının kaynağı doğrulanamadı.") }
    var schema: String?, table: String?, columns: [String] = []
    for (i, row) in rows.values.enumerated() {
      guard row.count == 9, row[0] == fields[i].name, row[1] == nil, row[2] == database,
        let s = row[3], let t = row[4], let c = row[5], row[6] == nil, row[8] == String(i+1),
        schema == nil || schema == s, table == nil || table == t else {
        throw SQLFailure("Kolonlar tek yerel tabloya ait değil veya kaynak metadata eksik. Sonuç salt okunur.")
      }
      schema = s; table = t; columns.append(c)
    }
    guard let schema, let table, Set(columns).count == columns.count else { throw SQLFailure("Tekrarlanan/eksik kaynak kolonları düzenlenemez.") }
    return .init(database: database, schema: schema, table: table, columns: columns)
  }
  public func projected(_ definition: TableDefinition) throws -> TableDefinition {
    guard definition.schema == schema, definition.name == table,
      Set(columns) == Set(definition.columns.map(\.name)), columns.count == definition.columns.count else {
      throw SQLFailure("Güvenli düzenleme için tablonun tüm kolonları sonuçta bulunmalı. SELECT * ile tekrar deneyin.")
    }
    var result = definition
    result.columns = try columns.map { name in
      guard let column = definition.columns.first(where: { $0.name == name }) else { throw SQLFailure("Kaynak kolon bulunamadı.") }
      return column
    }
    return result
  }
}
