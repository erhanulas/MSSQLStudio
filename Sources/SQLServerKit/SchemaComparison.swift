import Foundation
import CryptoKit

/// Database-local identity, deliberately case-sensitive: never merge two objects in a CS database.
public struct SchemaObjectKey: Hashable, Sendable, Comparable {
  public let schema: String
  public let name: String
  public let databaseTrigger: Bool
  public init(schema:String,name:String,databaseTrigger:Bool=false) {self.schema=schema;self.name=name;self.databaseTrigger=databaseTrigger}
  public var qualified: String {schema.isEmpty ? SQL.identifier(name):SQL.identifier(schema)+"."+SQL.identifier(name)}
  public static func < (a:Self,b:Self)->Bool {(a.databaseTrigger ? "1":"0",a.schema,a.name) < (b.databaseTrigger ? "1":"0",b.schema,b.name)}
}
public struct SchemaObject: Identifiable, Equatable, Sendable {
  public var id: SchemaObjectKey {key}
  public let key: SchemaObjectKey
  public let objectID: Int
  public let type: String
  public let digest: String?
  public let issue: String
  public let comparisonDigest: String?
  public let definitionDigest: String?
  public let structuralDigest: String?
  public init(key:SchemaObjectKey,objectID:Int,type:String,digest:String?,issue:String="",comparisonDigest:String?=nil,definitionDigest:String?=nil,structuralDigest:String?=nil) {self.key=key;self.objectID=objectID;self.type=type;self.digest=digest;self.issue=issue;self.comparisonDigest=comparisonDigest;self.definitionDigest=definitionDigest;self.structuralDigest=structuralDigest}
  public var kind: String {switch type {case "U":return "Tablo";case "V":return "View";case "P","PC":return "Prosedür";case "FN","IF","TF","FS","FT":return "Fonksiyon";case "TR","TA","TRD":return "Trigger";case "SN":return "Synonym";default:return type}}
}
public struct SchemaSnapshot: Sendable {
  public var objects: [SchemaObjectKey:SchemaObject]
  public var dependencies: [SchemaObjectKey:Set<SchemaObjectKey>]
  public init(objects:[SchemaObject],dependencies:[SchemaObjectKey:Set<SchemaObjectKey>]=[:]) throws {
    guard objects.count<=50_000,Set(objects.map(\.key)).count == objects.count else {throw SQLFailure("DDL listesi çok büyük veya yinelenen nesne kimliği içeriyor.")}
    self.objects=Dictionary(uniqueKeysWithValues:objects.map {($0.key,$0)});self.dependencies=dependencies
  }
}
public struct SchemaDifference: Identifiable, Sendable {
  public enum Status: String, CaseIterable, Sendable {case changed="Farklı",sourceOnly="Yalnız kaynakta",targetOnly="Yalnız hedefte",equal="Aynı",unavailable="Karşılaştırılamıyor",typeConflict="Tür uyuşmazlığı"}
  public var id: SchemaObjectKey {key}
  public let key: SchemaObjectKey
  public let source: SchemaObject?
  public let target: SchemaObject?
  public var status: Status {
    if let source,let target,source.type != target.type {return .typeConflict}
    if [source,target].compactMap({$0}).contains(where:{$0.digest == nil}) {return .unavailable}
    guard let source else {return .targetOnly};guard let target else {return .sourceOnly}
    return (source.comparisonDigest ?? source.digest) == (target.comparisonDigest ?? target.digest) ? .equal:.changed
  }
  public var migrationIssue: String {
    if let issue=[source,target].compactMap({$0}).first(where:{!$0.issue.isEmpty})?.issue {return issue}
    if let source,let target,source.type=="V",source.definitionDigest != nil,source.definitionDigest==target.definitionDigest,source.structuralDigest != target.structuralDigest {
      return "View kodu aynı; kolon farkı bağımlı nesnelerden veya saklanan view metadata’sından geliyor. Önce bağımlı tablo/view farklarını çözün; aynı kodu taşımak kolon tipini eşitlemez."
    }
    return ""
  }
  public var canStage: Bool {(status == .changed || status == .sourceOnly) && migrationIssue.isEmpty}
}

/// Column metadata is independent of table scripting: special tables remain inspectable.
/// maxLength is the SQL Server byte length; dataType handles Unicode character lengths.
public struct SchemaColumn: Identifiable, Equatable, Sendable {
  public var id: String {name}
  public let ordinal: Int
  public let name: String
  public let typeSchema: String
  public let typeName: String
  public let baseType: String
  public let userDefined: Bool
  public let assemblyType: Bool
  public let maxLength: Int
  public let precision: Int
  public let scale: Int
  public let nullable: Bool
  public let collation: String
  public let identity: Bool
  public let identitySeed: String
  public let identityIncrement: String
  public let computed: String
  public let persisted: Bool
  public let defaultSQL: String
  public let sparse: Bool
  public let rowGUID: Bool
  public let hidden: Bool
  public let generatedAlways: Int
  public let xmlCollection: String
  public let xmlDocument: Bool
  public init(ordinal:Int,name:String,typeSchema:String="sys",typeName:String,baseType:String="",userDefined:Bool=false,assemblyType:Bool=false,maxLength:Int=0,precision:Int=0,scale:Int=0,nullable:Bool=true,collation:String="",identity:Bool=false,identitySeed:String="",identityIncrement:String="",computed:String="",persisted:Bool=false,defaultSQL:String="",sparse:Bool=false,rowGUID:Bool=false,hidden:Bool=false,generatedAlways:Int=0,xmlCollection:String="",xmlDocument:Bool=false) {
    self.ordinal=ordinal;self.name=name;self.typeSchema=typeSchema;self.typeName=typeName;self.baseType=baseType.isEmpty ? typeName:baseType;self.userDefined=userDefined;self.assemblyType=assemblyType;self.maxLength=maxLength;self.precision=precision;self.scale=scale;self.nullable=nullable;self.collation=collation;self.identity=identity;self.identitySeed=identitySeed;self.identityIncrement=identityIncrement;self.computed=computed;self.persisted=persisted;self.defaultSQL=defaultSQL;self.sparse=sparse;self.rowGUID=rowGUID;self.hidden=hidden;self.generatedAlways=generatedAlways;self.xmlCollection=xmlCollection;self.xmlDocument=xmlDocument
  }
  public var dataType: String {
    if userDefined || assemblyType {return SQL.identifier(typeSchema)+"."+SQL.identifier(typeName)}
    if typeName.lowercased()=="sysname" {return typeName}
    return baseDataType
  }
  public var baseDataType: String {
    let type=baseType.lowercased()
    switch type {
    case "nvarchar","nchar":return type+"("+(maxLength == -1 ? "max":String(maxLength/2))+")"
    case "varchar","char","varbinary","binary":return type+"("+(maxLength == -1 ? "max":String(maxLength))+")"
    case "decimal","numeric":return "\(type)(\(precision),\(scale))"
    case "datetime2","datetimeoffset","time":return "\(type)(\(scale))"
    case "float":return "float(\(precision))"
    case "xml" where !xmlCollection.isEmpty:return "xml(\(xmlDocument ? "DOCUMENT":"CONTENT") \(xmlCollection))"
    default:return baseType
    }
  }
  public var attributes: String {
    var values:[String]=[]
    if identity {values.append("IDENTITY(\(identitySeed),\(identityIncrement))")}
    if !computed.isEmpty {values.append("AS \(computed)\(persisted ? " PERSISTED":"")")}
    if !defaultSQL.isEmpty {values.append("DEFAULT \(defaultSQL)")}
    if sparse {values.append("SPARSE")};if rowGUID {values.append("ROWGUIDCOL")};if hidden {values.append("HIDDEN")}
    if generatedAlways != 0 {values.append("GENERATED ALWAYS (\(generatedAlways))")}
    return values.joined(separator:" · ")
  }
}
public struct SchemaColumnDifference: Identifiable, Sendable {
  public enum Change: String, CaseIterable, Sendable {case added="Yalnız kaynakta",removed="Yalnız hedefte",dataType="Veri tipi",nullability="NULL",order="Sıra",collation="Collation",identity="Identity",computed="Hesaplama",defaultValue="Varsayılan",attributes="Özellikler"}
  public var id: String {name}
  public let name: String
  public let source: SchemaColumn?
  public let target: SchemaColumn?
  public let changes: Set<Change>
  public var isEqual: Bool {changes.isEmpty}
  public var summary: String {isEqual ? "Aynı":Change.allCases.filter {changes.contains($0)}.map(\.rawValue).joined(separator:", ")}
}
public struct SchemaObjectContent: Sendable {
  public let object: SchemaObject
  public let sql: String
  public let definition: String
  public let ansi: Bool
  public let quoted: Bool
  public let disabled: Bool
  public let triggerParent: String
  public let table: TableDefinition?
  public init(object:SchemaObject,sql:String,ansi:Bool=true,quoted:Bool=true,disabled:Bool=false,triggerParent:String="",table:TableDefinition?=nil,definition:String?=nil) {
    self.object=object;self.sql=sql;self.definition=definition ?? sql;self.ansi=ansi;self.quoted=quoted;self.disabled=disabled;self.triggerParent=triggerParent;self.table=table
  }
}
public enum SchemaComparison {
  public static func compare(source:SchemaSnapshot,target:SchemaSnapshot) throws -> [SchemaDifference] {
    let keys=Set(source.objects.keys).union(target.objects.keys).sorted()
    return try keys.map {key in try Task.checkCancellation();return SchemaDifference(key:key,source:source.objects[key],target:target.objects[key])}
  }
  public static var limits: Limits {var l=Limits();l.rows=50_001;l.totalBytes=64*1024*1024;l.cellBytes=4*1024*1024;l.timeout=90;return l}
  /// A lazy, read-only metadata request, including tables that cannot be scripted safely.
  public static func columnsQuery(_ object:SchemaObject)->String {
    guard ["U","V"].contains(object.type) else {return "-- StudioSchemaColumns\nSELECT 1 WHERE 1=0; SELECT 1 WHERE 1=0;"}
    return """
    -- StudioSchemaColumns
    SELECT o.object_id,RTRIM(o.type),HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'VIEW DEFINITION') FROM sys.objects o WHERE o.object_id=\(object.objectID) AND o.type IN ('U','V') AND o.is_ms_shipped=0;
    SELECT TOP (30001) ROW_NUMBER() OVER(ORDER BY c.column_id),c.name,SCHEMA_NAME(ty.schema_id),ty.name,ISNULL(base.name,ty.name),ty.is_user_defined,ty.is_assembly_type,c.max_length,c.precision,c.scale,c.is_nullable,c.collation_name,c.is_identity,
      CONVERT(nvarchar(40),ic.seed_value),CONVERT(nvarchar(40),ic.increment_value),cc.definition,ISNULL(cc.is_persisted,0),dc.definition,c.is_sparse,c.is_rowguidcol,c.is_hidden,c.generated_always_type,
      CASE WHEN xc.xml_collection_id IS NOT NULL THEN QUOTENAME(SCHEMA_NAME(xc.schema_id))+N'.'+QUOTENAME(xc.name) ELSE N'' END,c.is_xml_document
    FROM sys.columns c JOIN sys.types ty ON ty.user_type_id=c.user_type_id LEFT JOIN sys.types base ON base.user_type_id=c.system_type_id AND base.user_type_id=base.system_type_id
    LEFT JOIN sys.identity_columns ic ON ic.object_id=c.object_id AND ic.column_id=c.column_id
    LEFT JOIN sys.computed_columns cc ON cc.object_id=c.object_id AND cc.column_id=c.column_id
    LEFT JOIN sys.default_constraints dc ON dc.object_id=c.default_object_id
    LEFT JOIN sys.xml_schema_collections xc ON xc.xml_collection_id=c.xml_collection_id AND xc.xml_collection_id<>0
    WHERE c.object_id=\(object.objectID) ORDER BY c.column_id;
    """
  }
  public static func decodeColumns(_ result:Execution,object:SchemaObject) throws -> [SchemaColumn] {
    guard ["U","V"].contains(object.type),!result.partial,!result.stoppedEarly,result.results.count==2,result.results.allSatisfy({!$0.truncated}),
      result.results[0].values.count==1,let header=result.results[0].values.first,header.count==3,header[0]==String(object.objectID),header[1]==object.type,header[2]=="1",result.results[1].values.count<=30_000 else {throw SQLFailure("Kolon listesi eksik veya nesne değişti. VIEW DEFINITION iznini kontrol edip yeniden karşılaştırın.")}
    var names=Set<String>(),ordinals=Set<Int>()
    let columns=try result.results[1].values.map {r -> SchemaColumn in
      try Task.checkCancellation()
      guard r.count==24,let ordinal=Int(r[0] ?? ""),ordinal>0,let name=r[1],!name.isEmpty,names.insert(name).inserted,ordinals.insert(ordinal).inserted,
        let schema=r[2],!schema.isEmpty,let type=r[3],!type.isEmpty,let base=r[4],!base.isEmpty,
        let length=Int(r[7] ?? ""),length >= -1,let precision=Int(r[8] ?? ""),(0...53).contains(precision),let scale=Int(r[9] ?? ""),(0...38).contains(scale),
        let generated=Int(r[21] ?? ""),(0...255).contains(generated),[5,6,10,12,16,18,19,20,23].allSatisfy({["0","1"].contains(r[$0] ?? "")}) else {throw SQLFailure("Geçersiz veya yinelenen kolon metadata’sı; kısmi kolon farkı gösterilmedi.")}
      return SchemaColumn(ordinal:ordinal,name:name,typeSchema:schema,typeName:type,baseType:base,userDefined:r[5]=="1",assemblyType:r[6]=="1",maxLength:length,precision:precision,scale:scale,nullable:r[10]=="1",collation:r[11] ?? "",identity:r[12]=="1",identitySeed:r[13] ?? "",identityIncrement:r[14] ?? "",computed:r[15] ?? "",persisted:r[16]=="1",defaultSQL:r[17] ?? "",sparse:r[18]=="1",rowGUID:r[19]=="1",hidden:r[20]=="1",generatedAlways:generated,xmlCollection:r[22] ?? "",xmlDocument:r[23]=="1")
    }
    guard !columns.isEmpty,ordinals==Set(1...columns.count) else {throw SQLFailure("Tam kolon sırası alınamadı; boş/kısmi liste karşılaştırılmadı.")}
    return columns.sorted {$0.ordinal<$1.ordinal}
  }
  public static func compareColumns(source:[SchemaColumn],target:[SchemaColumn]) throws -> [SchemaColumnDifference] {
    guard source.count<=30_000,target.count<=30_000,Set(source.map(\.name)).count==source.count,Set(target.map(\.name)).count==target.count else {throw SQLFailure("Kolon karşılaştırması çok büyük veya yinelenen kolon adı içeriyor.")}
    let a=Dictionary(uniqueKeysWithValues:source.map {($0.name,$0)}),b=Dictionary(uniqueKeysWithValues:target.map {($0.name,$0)})
    // Source order is the desired order; target-only columns follow in their existing order.
    let names=source.sorted {$0.ordinal<$1.ordinal}.map(\.name)+target.sorted {$0.ordinal<$1.ordinal}.filter {a[$0.name]==nil}.map(\.name)
    return try names.map {name in
      try Task.checkCancellation()
      let source=a[name],target=b[name]
      var changes=Set<SchemaColumnDifference.Change>()
      if source==nil {changes.insert(.removed)}
      else if target==nil {changes.insert(.added)}
      else if let source,let target {
        if source.typeSchema != target.typeSchema || source.typeName != target.typeName || source.baseType != target.baseType || source.userDefined != target.userDefined || source.assemblyType != target.assemblyType || source.maxLength != target.maxLength || source.precision != target.precision || source.scale != target.scale || source.xmlCollection != target.xmlCollection || source.xmlDocument != target.xmlDocument {changes.insert(.dataType)}
        if source.nullable != target.nullable {changes.insert(.nullability)}
        if source.ordinal != target.ordinal {changes.insert(.order)}
        if source.collation != target.collation {changes.insert(.collation)}
        if source.identity != target.identity || source.identitySeed != target.identitySeed || source.identityIncrement != target.identityIncrement {changes.insert(.identity)}
        if source.computed != target.computed || source.persisted != target.persisted {changes.insert(.computed)}
        if source.defaultSQL != target.defaultSQL {changes.insert(.defaultValue)}
        if source.sparse != target.sparse || source.rowGUID != target.rowGUID || source.hidden != target.hidden || source.generatedAlways != target.generatedAlways {changes.insert(.attributes)}
      }
      return SchemaColumnDifference(name:name,source:source,target:target,changes:changes)
    }
  }
  private static var columnInventoryXML: String {"""
    SELECT c.name,SCHEMA_NAME(ty.schema_id) AS type_schema,ty.name AS type_name,ISNULL(base.name,ty.name) AS base_type,ty.is_user_defined,ty.is_assembly_type,c.max_length,c.precision,c.scale,c.is_nullable,c.collation_name,c.is_identity,c.is_sparse,c.is_rowguidcol,c.is_ansi_padded,c.is_filestream,c.generated_always_type,c.is_hidden,c.encryption_type,c.is_xml_document,
      ic.is_not_for_replication,CONVERT(nvarchar(40),ic.seed_value) AS seed,CONVERT(nvarchar(40),ic.increment_value) AS increment,cc.definition AS computed,cc.is_persisted,dc.name AS default_name,dc.definition AS default_sql,
      (SELECT SCHEMA_NAME(x.schema_id)+N'.'+x.name FROM sys.xml_schema_collections x WHERE x.xml_collection_id=c.xml_collection_id AND x.xml_collection_id<>0) AS xml_namespace
    FROM sys.columns c JOIN sys.types ty ON ty.user_type_id=c.user_type_id LEFT JOIN sys.types base ON base.user_type_id=c.system_type_id AND base.user_type_id=base.system_type_id LEFT JOIN sys.identity_columns ic ON ic.object_id=c.object_id AND ic.column_id=c.column_id LEFT JOIN sys.computed_columns cc ON cc.object_id=c.object_id AND cc.column_id=c.column_id LEFT JOIN sys.default_constraints dc ON dc.object_id=c.default_object_id WHERE c.object_id=o.object_id ORDER BY c.column_id FOR XML PATH('column'),TYPE
    """}
  private static var indexInventoryXML: String {"""
    SELECT i.name,i.type,i.is_unique,i.is_primary_key,i.is_unique_constraint,i.has_filter,i.filter_definition,i.fill_factor,i.is_padded,i.ignore_dup_key,i.allow_row_locks,i.allow_page_locks,i.is_disabled,ds.name AS storage,
      (SELECT c.name,ic.key_ordinal,ic.is_descending_key,ic.is_included_column FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id ORDER BY ic.index_column_id FOR XML PATH('column'),TYPE) AS columns
    FROM sys.indexes i LEFT JOIN sys.data_spaces ds ON ds.data_space_id=i.data_space_id WHERE i.object_id=o.object_id ORDER BY i.name FOR XML PATH('index'),TYPE
    """}
  /// One bounded catalog round-trip, hashes computed on the server; no table data or full module bodies transferred.
  public static func inventory(keys:[SchemaObjectKey]?=nil) -> String {
    let filter=keys.map {keys in keys.isEmpty ? " AND 1=0" : " AND ("+keys.map {"(s.name="+SQL.literal($0.schema)+" AND o.name="+SQL.literal($0.name)+")"}.joined(separator:" OR ")+")"} ?? ""
    let triggerFilter=keys.map {keys in " AND t.name IN ("+(keys.filter(\.databaseTrigger).map {SQL.literal($0.name)}.isEmpty ? "N''":keys.filter(\.databaseTrigger).map {SQL.literal($0.name)}.joined(separator:","))+")"} ?? ""
    // Explicit ordered metadata avoids object IDs / modification dates / identity current values.
    let columns=columnInventoryXML
    let indexes=indexInventoryXML
    let checks="SELECT c.name,c.definition,c.is_disabled,c.is_not_trusted,c.is_not_for_replication FROM sys.check_constraints c WHERE c.parent_object_id=o.object_id ORDER BY c.name FOR XML PATH('check'),TYPE"
    let fks="""
    SELECT f.name,OBJECT_SCHEMA_NAME(f.referenced_object_id) AS target_schema,OBJECT_NAME(f.referenced_object_id) AS target_table,f.delete_referential_action,f.update_referential_action,f.is_disabled,f.is_not_trusted,f.is_not_for_replication,
      (SELECT pc.name AS parent_column,rc.name AS target_column FROM sys.foreign_key_columns k JOIN sys.columns pc ON pc.object_id=k.parent_object_id AND pc.column_id=k.parent_column_id JOIN sys.columns rc ON rc.object_id=k.referenced_object_id AND rc.column_id=k.referenced_column_id WHERE k.constraint_object_id=f.object_id ORDER BY k.constraint_column_id FOR XML PATH('column'),TYPE) AS columns
    FROM sys.foreign_keys f WHERE f.parent_object_id=o.object_id ORDER BY f.name FOR XML PATH('fk'),TYPE
    """
    let dependencies=keys == nil ? """
    SELECT OBJECT_SCHEMA_NAME(owner.object_id),OBJECT_NAME(owner.object_id),OBJECT_SCHEMA_NAME(d.referenced_id),OBJECT_NAME(d.referenced_id),CASE WHEN EXISTS(SELECT 1 FROM sys.triggers t WHERE t.object_id=d.referencing_id AND t.parent_class=0) THEN 1 ELSE 0 END
    FROM sys.sql_expression_dependencies d LEFT JOIN sys.objects referencing ON referencing.object_id=d.referencing_id
    CROSS APPLY (SELECT CASE WHEN referencing.type IN ('D','C') AND referencing.parent_object_id>0 THEN referencing.parent_object_id ELSE d.referencing_id END AS object_id) owner
    JOIN sys.objects ref ON ref.object_id=d.referenced_id AND ref.is_ms_shipped=0 WHERE d.referenced_class=1 AND d.referenced_database_name IS NULL AND d.referenced_server_name IS NULL
    UNION SELECT OBJECT_SCHEMA_NAME(f.parent_object_id),OBJECT_NAME(f.parent_object_id),OBJECT_SCHEMA_NAME(f.referenced_object_id),OBJECT_NAME(f.referenced_object_id),0 FROM sys.foreign_keys f
    UNION SELECT OBJECT_SCHEMA_NAME(t.object_id),t.name,OBJECT_SCHEMA_NAME(t.parent_id),OBJECT_NAME(t.parent_id),0 FROM sys.triggers t WHERE t.parent_class=1 AND t.is_ms_shipped=0;
    """ : "SELECT CAST(NULL AS nvarchar(128)),CAST(NULL AS nvarchar(128)),CAST(NULL AS nvarchar(128)),CAST(NULL AS nvarchar(128)),0 WHERE 1=0;"
    return """
    -- StudioSchemaInventory v1
    IF TRY_CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))<14 THROW 51000,N'DDL karşılaştırma SQL Server 2017 veya üstünü gerektirir.',1;
    SELECT HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'VIEW DEFINITION'),DB_NAME();
    SELECT o.object_id,s.name,o.name,RTRIM(o.type),
      CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),payload.value)),2),
      CASE WHEN o.type IN ('PC','FS','FT','TA') THEN N'CLR tanımı otomatik taşınamaz.'
      WHEN o.type NOT IN ('U','SN') AND m.definition IS NULL THEN N'Tanım şifreli veya görünmüyor.'
      WHEN EXISTS(SELECT 1 FROM sys.crypt_properties cp WHERE cp.class=1 AND cp.major_id=o.object_id) THEN N'İmzalı modül için yeniden imzalama gerekli; otomatik taşıma kapalı.'
      WHEN EXISTS(SELECT 1 FROM sys.trigger_events te WHERE te.object_id=o.object_id AND (te.is_first=1 OR te.is_last=1)) THEN N'Trigger çalışma sırası ayrıca taşınmalı; otomatik taşıma kapalı.'
      WHEN m.uses_native_compilation=1 OR m.execute_as_principal_id>=0 THEN N'Native compilation / EXECUTE AS principal eşlemesi gerekli.'
      WHEN o.type='V' AND EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=o.object_id AND index_id>0) THEN N'İndeksli view yalnız karşılaştırılır; ALTER VIEW indeksleri kaldırır.'
      WHEN o.type='U' AND (tb.temporal_type<>0 OR tb.is_memory_optimized=1 OR tb.is_filetable=1 OR tb.is_node=1 OR tb.is_edge=1
        OR tb.lock_escalation<>0 OR tb.is_replicated=1 OR tb.is_merge_published=1 OR tb.is_tracked_by_cdc=1
        OR EXISTS(SELECT 1 FROM sys.partitions WHERE object_id=o.object_id AND data_compression<>0)
        OR EXISTS(SELECT 1 FROM sys.indexes i LEFT JOIN sys.data_spaces ds ON ds.data_space_id=i.data_space_id WHERE i.object_id=o.object_id AND (i.type>2 OR ds.type='PS'))
        OR EXISTS(SELECT 1 FROM sys.columns c JOIN sys.types ty ON ty.user_type_id=c.user_type_id WHERE c.object_id=o.object_id AND (c.is_filestream=1 OR c.generated_always_type<>0 OR c.is_hidden=1 OR c.encryption_type IS NOT NULL OR c.xml_collection_id<>0 OR (c.system_type_id=62 AND c.precision<>53) OR c.rule_object_id<>0 OR ty.is_assembly_type=1 OR c.is_column_set=1 OR (c.system_type_id IN (165,167,173,175) AND c.is_ansi_padded=0)
          OR (c.default_object_id<>0 AND NOT EXISTS(SELECT 1 FROM sys.default_constraints d WHERE d.object_id=c.default_object_id))))
        OR EXISTS(SELECT 1 FROM sys.identity_columns ic WHERE ic.object_id=o.object_id AND ic.is_not_for_replication=1)
        OR EXISTS(SELECT 1 FROM sys.security_predicates sp WHERE sp.target_object_id=o.object_id)) THEN N'Özel tablo özellikleri için otomatik taşıma kapalı.' ELSE N'' END
    FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id
    LEFT JOIN sys.sql_modules m ON m.object_id=o.object_id LEFT JOIN sys.tables tb ON tb.object_id=o.object_id
    LEFT JOIN sys.triggers tr ON tr.object_id=o.object_id LEFT JOIN sys.synonyms sn ON sn.object_id=o.object_id
    CROSS APPLY (SELECT CASE WHEN o.type='U' THEN CONVERT(nvarchar(max),(\(columns)))+CONVERT(nvarchar(max),(\(indexes)))+CONVERT(nvarchar(max),(\(checks)))+CONVERT(nvarchar(max),(\(fks)))
      +CONVERT(nvarchar(max),(SELECT tb.temporal_type,tb.is_memory_optimized,tb.is_filetable,tb.is_node,tb.is_edge,tb.lock_escalation FOR XML PATH('table'),TYPE))
      WHEN o.type='SN' THEN CONVERT(nvarchar(max),sn.base_object_name)
      ELSE CONVERT(nvarchar(max),m.definition)+NCHAR(10)+CONVERT(nvarchar(1),m.uses_ansi_nulls)+CONVERT(nvarchar(1),m.uses_quoted_identifier)+ISNULL(CONVERT(nvarchar(1),tr.is_disabled),N'')
        +ISNULL(OBJECT_SCHEMA_NAME(tr.parent_id)+N'.'+OBJECT_NAME(tr.parent_id),N'')+CASE WHEN o.type='V' THEN CONVERT(nvarchar(max),(\(columns)))+CONVERT(nvarchar(max),(\(indexes))) ELSE N'' END END AS value) payload
    WHERE o.is_ms_shipped=0 AND o.type IN ('U','V','P','PC','FN','IF','TF','FS','FT','TR','TA','SN')\(filter)
    UNION ALL
    SELECT t.object_id,N'',t.name,'TRD',CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),m.definition+NCHAR(10)+CONVERT(nvarchar(1),m.uses_ansi_nulls)+CONVERT(nvarchar(1),m.uses_quoted_identifier)+CONVERT(nvarchar(1),t.is_disabled))),2),CASE WHEN m.definition IS NULL THEN N'Tanım şifreli veya görünmüyor.' WHEN EXISTS(SELECT 1 FROM sys.crypt_properties cp WHERE cp.class=1 AND cp.major_id=t.object_id) OR EXISTS(SELECT 1 FROM sys.trigger_events te WHERE te.object_id=t.object_id AND (te.is_first=1 OR te.is_last=1)) THEN N'İmza / trigger çalışma sırası ayrıca taşınmalı.' WHEN m.execute_as_principal_id>=0 THEN N'EXECUTE AS principal eşlemesi gerekli.' ELSE N'' END FROM sys.triggers t LEFT JOIN sys.sql_modules m ON m.object_id=t.object_id WHERE t.parent_class=0 AND t.is_ms_shipped=0\(triggerFilter);
    \(dependencies)
    """
  }
  public static func decode(_ result:Execution) throws -> SchemaSnapshot {
    guard !result.partial,!result.stoppedEarly,result.results.count == 3,result.results.allSatisfy({!$0.truncated}),result.results[0].values.first?.first == "1" else {throw SQLFailure("Tam DDL listesi alınamadı. İki veritabanında da VIEW DEFINITION izni gerekli; kısmi sonuç karşılaştırılmaz.")}
    let objects=try result.results[1].values.map {r -> SchemaObject in
      guard r.count==6,let rawID=r[0],let id=Int(rawID),id>0,let schema=r[1],let name=r[2],!name.isEmpty,let type=r[3],let issue=r[5] else {throw SQLFailure("Geçersiz DDL metadata satırı.")}
      if let digest=r[4],digest.range(of:"^[A-Fa-f0-9]{64}$",options:.regularExpression)==nil {throw SQLFailure("DDL özeti eksik veya geçersiz.")}
      return SchemaObject(key:.init(schema:schema,name:name,databaseTrigger:type=="TRD"),objectID:id,type:type,digest:r[4],issue:issue)
    }
    var dependencies:[SchemaObjectKey:Set<SchemaObjectKey>]=[:]
    for r in result.results[2].values {
      guard r.count==5,let name=r[1],let schema=r[2],let ref=r[3] else {throw SQLFailure("Bağımlılık listesi eksik.")}
      let key=SchemaObjectKey(schema:r[4]=="1" ? "":r[0] ?? "",name:name,databaseTrigger:r[4]=="1")
      let dependency=SchemaObjectKey(schema:schema,name:ref)
      if key != dependency {dependencies[key,default:[]].insert(dependency)}
    }
    return try SchemaSnapshot(objects:objects,dependencies:dependencies)
  }
  public static func contentQuery(_ object:SchemaObject)->String {
    if object.type=="U" {return ObjectMetadata.table(object.objectID)}
    if object.type=="SN" {return "SELECT base_object_name FROM sys.synonyms WHERE object_id=\(object.objectID);"}
    return "SELECT m.definition,m.uses_ansi_nulls,m.uses_quoted_identifier,ISNULL(t.is_disabled,0),CASE WHEN t.parent_class=0 THEN N'DATABASE' ELSE QUOTENAME(OBJECT_SCHEMA_NAME(t.parent_id))+N'.'+QUOTENAME(OBJECT_NAME(t.parent_id)) END FROM sys.sql_modules m LEFT JOIN sys.triggers t ON t.object_id=m.object_id WHERE m.object_id=\(object.objectID);"
  }
  public static func decodeContent(_ result:Execution,object:SchemaObject) throws -> SchemaObjectContent {
    guard !result.partial,!result.stoppedEarly,!result.results.contains(where:{$0.truncated}) else {throw SQLFailure("Tanım kısmi; karşılaştırma veya taşıma yapılmadı.")}
    if object.type=="U" {
      var table=try ObjectMetadata.decode(result,schema:object.key.schema,name:object.key.name)
      table.definitions=table.definitions.filter {$0.kind != "TRIGGER"}.sorted {a,b in let rank=["PK":0,"UQ":1,"INDEX":2,"CHECK":3,"FK":4];return (rank[a.kind] ?? 5,a.name)<(rank[b.kind] ?? 5,b.name)}
      return .init(object:object,sql:try table.createScript(),table:table)
    }
    guard result.results.count==1,let r=result.results.first?.values.first,let sql=r.first ?? nil else {throw SQLFailure("Nesne tanımı alınamadı; izin/şifreleme durumunu kontrol edin.")}
    if object.type=="SN" {return .init(object:object,sql:try ExplorerScripts.synonym(qualified:object.key.qualified,target:sql))}
    guard r.count==5,["0","1"].contains(r[1] ?? ""),["0","1"].contains(r[2] ?? "") else {throw SQLFailure("Modül oturum ayarları eksik.")}
    let preview=try ExplorerScripts.module(sql,verb:"CREATE",qualified:object.key.qualified,ansi:r[1]=="1",quoted:r[2]=="1")
    return .init(object:object,sql:preview,ansi:r[1]=="1",quoted:r[2]=="1",disabled:r[3]=="1",triggerParent:r[4] ?? "",definition:sql)
  }
}

public struct SchemaMigrationPlan: Sendable {
  public let keys: [SchemaObjectKey]
  public let sql: String
  public let source: SchemaSnapshot
  public let target: SchemaSnapshot
  public let warnings: [String]
  public let originalSQL: String
  public let desiredSQL: String
}
public enum SchemaMigration {
  private static func sameBaseline(_ a:SchemaObject?,_ b:SchemaObject?)->Bool {
    guard let a,let b else {return a == nil && b == nil}
    return a.key==b.key && a.objectID==b.objectID && a.type==b.type && a.digest==b.digest && a.issue==b.issue
  }
  public static func validateBaseline(_ expected:SchemaSnapshot,current:SchemaSnapshot,keys:[SchemaObjectKey]) throws {
    for key in keys where !sameBaseline(expected.objects[key],current.objects[key]) {throw SQLFailure("\(key.qualified) karşılaştırmadan sonra değişti. Yeniden karşılaştırın.")}
  }
  public static func orderedKeys(_ selected:Set<SchemaObjectKey>,source:SchemaSnapshot,target:SchemaSnapshot) throws -> [SchemaObjectKey] {
    guard !selected.isEmpty,selected.count<=100 else {throw SQLFailure("Önizleme için 1–100 nesne seçin.")}
    var visiting=Set<SchemaObjectKey>(),done=Set<SchemaObjectKey>(),ordered:[SchemaObjectKey]=[]
    func visit(_ key:SchemaObjectKey) throws {
      try Task.checkCancellation()
      if done.contains(key) {return}
      guard !visiting.contains(key) else {throw SQLFailure("Bağımlılık döngüsü: \(key.qualified). Nesneleri ayrı adımlarda uygulayın.")}
      guard let object=source.objects[key],object.digest != nil,object.issue.isEmpty else {throw SQLFailure("\(key.qualified) taşınabilir bir kaynak tanımı değil.")}
      if let old=target.objects[key],old.type != object.type || !old.issue.isEmpty || old.digest == nil {throw SQLFailure("\(key.qualified) hedef türü/özellikleri otomatik değiştirilemez.")}
      let difference=SchemaDifference(key:key,source:object,target:target.objects[key])
      guard difference.migrationIssue.isEmpty else {throw SQLFailure("\(key.qualified): \(difference.migrationIssue)")}
      visiting.insert(key)
      for dependency in (source.dependencies[key] ?? []).sorted() {
        if selected.contains(dependency) {try visit(dependency)}
        else if target.objects[dependency] == nil {throw SQLFailure("\(key.qualified) için \(dependency.qualified) hedefte yok. Bağımlı nesneyi de seçin.")}
      }
      visiting.remove(key);done.insert(key);ordered.append(key)
    }
    for key in selected.sorted() {try visit(key)}
    return ordered
  }
  public static func plan(selected:Set<SchemaObjectKey>,source:SchemaSnapshot,target:SchemaSnapshot,sourceContent:[SchemaObjectKey:SchemaObjectContent],targetContent:[SchemaObjectKey:SchemaObjectContent]) throws -> SchemaMigrationPlan {
    let keys=try orderedKeys(selected,source:source,target:target)
    var commands:[String]=[],warnings=Set<String>()
    for key in keys {
      try Task.checkCancellation()
      guard let content=sourceContent[key],content.object==source.objects[key] else {throw SQLFailure("Kaynak tanımı güncel değil: \(key.qualified)")}
      let old=target.objects[key]
      if let old,old.digest == content.object.digest {continue}
      if let old, targetContent[key]?.object != old {throw SQLFailure("Hedef tanımı güncel değil: \(key.qualified)")}
      let guardSQL:String
      if key.databaseTrigger {
        guardSQL="IF \(old.map {"ISNULL((SELECT object_id FROM sys.triggers WHERE parent_class=0 AND name=\(SQL.literal(key.name))),-1) <> \($0.objectID)"} ?? "EXISTS(SELECT 1 FROM sys.triggers WHERE parent_class=0 AND name=\(SQL.literal(key.name)))") THROW 51000,N'Hedef trigger değişti; yeniden karşılaştırın.',1;"
      } else {
        guardSQL="IF \(old.map {"ISNULL(OBJECT_ID(\(SQL.literal(key.qualified)),\(SQL.literal($0.type))),-1) <> \($0.objectID)"} ?? "OBJECT_ID(\(SQL.literal(key.qualified))) IS NOT NULL") THROW 51000,N'Hedef nesne değişti; yeniden karşılaştırın.',1;\nIF SCHEMA_ID(\(SQL.literal(key.schema))) IS NULL THROW 51000,N'Hedefte nesnenin şeması yok; önce şemayı oluşturun.',1;"
      }
      var script:String
      switch content.object.type {
      case "U":
        guard let table=content.table else {throw SQLFailure("Tablo metadata eksik.")}
        if old == nil {script=try table.createScript()}
        else {guard let previous=targetContent[key]?.table else {throw SQLFailure("Hedef tablo metadata eksik.")};script=try tableChanges(source:table,target:previous)}
        warnings.insert("Tablo verileri taşınmaz. Tip/NULL değişiklikleri mevcut verilere göre başarısız olabilir ve şema kilidi alabilir.")
      case "SN":
        script=(old == nil ? "":"DROP SYNONYM \(key.qualified);\n")+content.sql
      default:
        script=try ExplorerScripts.module(content.definition,verb:old == nil ? "CREATE":"ALTER",qualified:key.qualified,ansi:content.ansi,quoted:content.quoted)
        if ["TR","TRD"].contains(content.object.type) {
          guard !content.triggerParent.isEmpty else {throw SQLFailure("Trigger hedefi okunamadı.")}
          script+="\nGO\n\(content.disabled ? "DISABLE":"ENABLE") TRIGGER \(key.qualified) ON \(content.triggerParent);"
        }
        warnings.insert("Tanımdaki diğer veritabanı/sunucu adları yeniden yazılmaz; izinler, sahiplik ve extended properties taşınmaz.")
      }
      // Dynamic batches let CREATE/ALTER remain first in their batch inside one rollback-capable transaction.
      // Session SET options run in the outer session so the following dynamic module captures them.
      let batches=try TSQL.batches(script)
      var statements:[String]=[]
      for batch in batches {
        let text=batch.text.trimmingCharacters(in:.whitespacesAndNewlines)
        if text.hasPrefix("SET ANSI_NULLS ") || text.hasPrefix("SET QUOTED_IDENTIFIER ") {statements.append(text)}
        else {statements.append("EXEC sys.sp_executesql \(SQL.literal(text));")}
      }
      commands.append("-- \(key.qualified.replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\r",with:" "))\n"+guardSQL+"\n"+statements.joined(separator:"\n"))
    }
    guard !commands.isEmpty else {throw SQLFailure("Seçilen nesnelerde uygulanacak fark yok.")}
    let sql=ObjectScripts.transaction(commands.joined(separator:"\n\n"))
    guard sql.utf8.count<=8*1024*1024 else {throw SQLFailure("Taşıma SQL'i 8 MB sınırını aşıyor; daha az nesne seçin.")}
    func heading(_ key:SchemaObjectKey)->String {"-- "+key.qualified.replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\r",with:" ")+"\n"}
    let before=keys.map {heading($0)+(targetContent[$0]?.sql ?? "-- Hedefte yok.")}.joined(separator:"\n\n")
    let after=keys.map {heading($0)+(sourceContent[$0]?.sql ?? "")}.joined(separator:"\n\n")
    guard max(sql.utf16.count,before.utf16.count,after.utf16.count)<=900_000 else {throw SQLFailure("Taşıma önizlemesi büyük; daha az nesne seçin (900.000 karakter sınırı).")}
    return SchemaMigrationPlan(keys:keys,sql:sql,source:source,target:target,warnings:warnings.sorted(),originalSQL:before,desiredSQL:after)
  }
  /// Conservative rowstore migration: no table rebuild, column removal, rename or ordinal rewrite.
  public static func tableChanges(source:TableDefinition,target:TableDefinition) throws -> String {
    guard source.schema==target.schema,source.name==target.name,source.heapFilegroup==target.heapFilegroup else {throw SQLFailure("Tablo kimliği/depolama konumu otomatik değiştirilemez.")}
    let sourceNames=source.columns.map(\.name),targetNames=target.columns.map(\.name)
    guard Array(sourceNames.prefix(targetNames.count))==targetNames else {throw SQLFailure("Kolon silme/sıralama/yeniden adlandırma veri korumak için otomatik uygulanmaz; SQL editöründe ayrıca inceleyin.")}
    var actions:[String]=[]
    let q=source.qualified
    let sourceDefs=Dictionary(uniqueKeysWithValues:source.definitions.filter {$0.kind != "TRIGGER"}.map {($0.kind+"|"+$0.name,$0)})
    let targetDefs=Dictionary(uniqueKeysWithValues:target.definitions.filter {$0.kind != "TRIGGER"}.map {($0.kind+"|"+$0.name,$0)})
    for key in targetDefs.keys.sorted() {
      let old=targetDefs[key]!
      if sourceDefs[key]?.sql != old.sql {
        actions.append(old.kind=="INDEX" ? "DROP INDEX \(SQL.identifier(old.name)) ON \(q);":"ALTER TABLE \(q) DROP CONSTRAINT \(SQL.identifier(old.name));")
      }
    }
    for (index,old) in target.columns.enumerated() {
      let c=source.columns[index]
      if c.type==old.type,(c.type.hasPrefix("[") || c.type.lowercased()=="sysname"),c.valueType != old.valueType {throw SQLFailure("\(c.name) kolonunun özel veri tipi \(c.type) iki veritabanında farklı temel tipe sahip. Önce veri tipi tanımlarını eşitleyin; tablo ALTER işlemi özel tip tanımını değiştirmez.")}
      guard c.identity==old.identity,c.seed==old.seed,c.increment==old.increment,c.computed==old.computed,c.persisted==old.persisted,c.sparse==old.sparse,c.rowGUID==old.rowGUID else {throw SQLFailure("Identity/computed/sparse/ROWGUID değişikliği otomatik uygulanamaz: \(c.name)")}
      let defaultChanged=c.defaultSQL != old.defaultSQL || c.defaultName != old.defaultName
      if defaultChanged,!old.defaultSQL.isEmpty {
        guard !old.defaultName.isEmpty else {throw SQLFailure("Eski default constraint adı eksik.")}
        actions.append("ALTER TABLE \(q) DROP CONSTRAINT \(SQL.identifier(old.defaultName));")
      }
      if c.type != old.type || c.nullable != old.nullable || c.collation != old.collation {
        guard !old.generated else {throw SQLFailure("Üretilen kolon değiştirilemez: \(c.name)")}
        actions.append("ALTER TABLE \(q) ALTER COLUMN \(SQL.identifier(c.name)) \(c.type)\(c.collation.isEmpty ? "":" COLLATE "+(try ObjectScripts.collation(c.collation)))\(c.nullable ? " NULL":" NOT NULL");")
      }
      if defaultChanged,!c.defaultSQL.isEmpty {
        actions.append("ALTER TABLE \(q) ADD \(c.defaultName.isEmpty ? "":"CONSTRAINT "+SQL.identifier(c.defaultName)+" ")DEFAULT \(c.defaultSQL) FOR \(SQL.identifier(c.name));")
      }
    }
    for c in source.columns.dropFirst(target.columns.count) {actions.append("ALTER TABLE \(q) ADD \(try ObjectScripts.column(c,validateType:false));")}
    for key in sourceDefs.keys.sorted {a,b in let rank=["PK":0,"UQ":1,"INDEX":2,"CHECK":3,"FK":4];return (rank[sourceDefs[a]!.kind] ?? 5,a)<(rank[sourceDefs[b]!.kind] ?? 5,b)} where sourceDefs[key]?.sql != targetDefs[key]?.sql {actions.append(sourceDefs[key]!.sql)}
    guard !actions.isEmpty else {throw SQLFailure("Tablo farkı desteklenen ALTER kapsamı dışında; otomatik eksik script üretilmedi.")}
    return actions.joined(separator:"\nGO\n")
  }
}

extension SchemaComparison {
  /// Only modules whose raw server hashes differ need a body read; page the read, never N+1.
  public static func refinementQuery(_ objects:[SchemaObject])->String {
    guard !objects.isEmpty else {return "-- StudioSchemaRefinement\nSELECT 1 WHERE 1=0;"}
    return """
    -- StudioSchemaRefinement
    SELECT m.object_id,m.definition,m.uses_ansi_nulls,m.uses_quoted_identifier,ISNULL(t.is_disabled,0),CASE WHEN t.parent_class=0 THEN N'DATABASE' ELSE QUOTENAME(OBJECT_SCHEMA_NAME(t.parent_id))+N'.'+QUOTENAME(OBJECT_NAME(t.parent_id)) END,
      CASE WHEN o.type='V' THEN CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),CONVERT(nvarchar(max),(\(columnInventoryXML)))+CONVERT(nvarchar(max),(\(indexInventoryXML))))),2) ELSE NULL END
    FROM sys.sql_modules m LEFT JOIN sys.objects o ON o.object_id=m.object_id LEFT JOIN sys.triggers t ON t.object_id=m.object_id WHERE m.object_id IN (\(objects.map {String($0.objectID)}.joined(separator:",")));
    """
  }
  public static func refine(_ snapshot:SchemaSnapshot,objects:[SchemaObject],result:Execution) throws -> SchemaSnapshot {
    guard !result.partial,!result.stoppedEarly,result.results.count==1,result.results.first?.truncated==false else {throw SQLFailure("Farklı modüllerin tanımları kısmi; karşılaştırma tamamlanmadı.")}
    var updated=snapshot,seen=Set<Int>()
    guard Set(objects.map(\.objectID)).count==objects.count else {throw SQLFailure("Yinelenen modül kimliği.")}
    let indexed=Dictionary(uniqueKeysWithValues:objects.map {($0.objectID,$0)})
    for row in result.results[0].values {
      guard [6,7].contains(row.count),let id=Int(row[0] ?? ""),let object=indexed[id],seen.insert(id).inserted else {throw SQLFailure("Farklı modül tanımı eksik veya yinelenmiş.")}
      let structuralDigest:String?
      if object.type=="V" {
        guard row.count==7,let value=row[6],value.range(of:"^[A-Fa-f0-9]{64}$",options:.regularExpression) != nil else {throw SQLFailure("View kolon/indeks özeti eksik; karşılaştırma tamamlanmadı.")}
        structuralDigest=value.lowercased()
      } else {structuralDigest=nil}
      var execution=Execution();execution.results=[Rows(values:[Array(row[1...5])])]
      let content=try decodeContent(execution,object:object)
      // CREATE / ALTER and stale names retained by sp_rename are delivery details.
      // Preserve all body whitespace, comments, literal text and case exactly.
      let canonical=content.sql+"\n--trigger-state:"+String(content.disabled)+"|"+content.triggerParent
      func hash(_ value:String)->String {SHA256.hash(data:Data(value.utf8)).map {String(format:"%02x",$0)}.joined()}
      let definitionDigest=hash(canonical)
      let digest=structuralDigest.map {hash(canonical+"\n--view-structure:"+$0)} ?? definitionDigest
      updated.objects[object.key]=SchemaObject(key:object.key,objectID:id,type:object.type,digest:object.digest,issue:object.issue,comparisonDigest:digest,definitionDigest:definitionDigest,structuralDigest:structuralDigest)
    }
    guard seen.count==objects.count else {throw SQLFailure("Karşılaştırma sırasında nesne kaldırıldı; yeniden karşılaştırın.")}
    return updated
  }
}
