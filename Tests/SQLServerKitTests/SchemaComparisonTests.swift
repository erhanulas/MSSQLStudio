import Foundation
import Testing
@testable import SQLServerKit

struct SchemaComparisonTests {
  private func object(_ name:String,type:String="P",digest:String?=String(repeating:"a",count:64),id:Int=1,issue:String="",schema:String="dbo")->SchemaObject {.init(key:.init(schema:schema,name:name),objectID:id,type:type,digest:digest,issue:issue)}
  private func columnExecution(_ object:SchemaObject,rows:[[String?]]) -> Execution {
    var result=Execution();result.results=[Rows(values:[[String(object.objectID),object.type,"1"]]),Rows(values:rows)];return result
  }
  private func columnRow(_ name:String,ordinal:Int=1,type:String="int",base:String="int",schema:String="sys",alias:Bool=false,length:Int=4,precision:Int=10,scale:Int=0,nullable:Bool=true)->[String?] {
    [String(ordinal),name,schema,type,base,alias ? "1":"0","0",String(length),String(precision),String(scale),nullable ? "1":"0",nil,"0",nil,nil,nil,"0",nil,"0","0","0","0","","0"]
  }
  @Test func statusesExactIdentityAndLargeInventory() throws {
    let a=try SchemaSnapshot(objects:[object("same"),object("changed"),object("new"),object("encrypted",digest:nil),object("kind"),object("Name"),object("name")])
    let b=try SchemaSnapshot(objects:[object("same",id:50),object("changed",digest:String(repeating:"b",count:64)),object("old"),object("encrypted",digest:nil),object("kind",type:"V")])
    let rows=try SchemaComparison.compare(source:a,target:b),states=Dictionary(uniqueKeysWithValues:rows.map {($0.key.name,$0.status)})
    #expect(states["same"] == .equal && states["changed"] == .changed)
    #expect(states["new"] == .sourceOnly && states["old"] == .targetOnly)
    #expect(states["encrypted"] == .unavailable && states["kind"] == .typeConflict)
    #expect(rows.filter(\.canStage).count==4)
    #expect(throws:SQLFailure.self) {try SchemaSnapshot(objects:[object("dup"),object("dup")])}
    let many=(0..<20_000).map {object("p\($0)",id:$0+1)}
    let snapshot=try SchemaSnapshot(objects:many),start=Date()
    #expect(try SchemaComparison.compare(source:snapshot,target:snapshot).allSatisfy {$0.status == .equal})
    #expect(Date().timeIntervalSince(start)<5)
  }
  @Test func inventoryRejectsPartialInvisibleMalformedAndHashesAllSupportedMetadata() throws {
    var execution=Execution();execution.results=[Rows(values:[["1","A"]]),Rows(values:[["1","dbo","p","P",String(repeating:"a",count:64),"",nil]]),Rows()]
    #expect(try SchemaComparison.decode(execution).objects.count==1)
    execution.partial=true;#expect(throws:SQLFailure.self) {try SchemaComparison.decode(execution)}
    execution.partial=false;execution.results[0]=Rows(values:[["0","A"]]);#expect(throws:SQLFailure.self) {try SchemaComparison.decode(execution)}
    execution.results[0]=Rows(values:[["1","A"]]);execution.results[1]=Rows(values:[["1","dbo","p","P","bad","",nil]]);#expect(throws:SQLFailure.self) {try SchemaComparison.decode(execution)}
    let sql=SchemaComparison.inventory(keys:[.init(schema:"odd']",name:"x'y")])
    for token in ["SHA2_256","sys.columns","base.user_type_id=c.system_type_id","ISNULL(base.name,ty.name) AS base_type","sys.index_columns","sys.foreign_key_columns","sys.check_constraints","uses_quoted_identifier","parent_class=0","VIEW DEFINITION","N'odd'']'"] {#expect(sql.contains(token))}
    #expect(!sql.contains("SELECT * FROM"))
    if let path=ProcessInfo.processInfo.environment["MSSQL_SCHEMA_SQL_DUMP"] {
      try SchemaComparison.inventory().write(toFile:path,atomically:true,encoding:.utf8)
      try sql.write(toFile:path+".filtered.sql",atomically:true,encoding:.utf8)
      try SchemaComparison.inventory(keys:[.init(schema:"",name:"StudioDatabaseTrigger",databaseTrigger:true)]).write(toFile:path+".trigger-filtered.sql",atomically:true,encoding:.utf8)
      try SchemaComparison.inventory(keys:[]).write(toFile:path+".empty-filtered.sql",atomically:true,encoding:.utf8)
      try SchemaComparison.refinementQuery([object("p")]).write(toFile:path+".refine.sql",atomically:true,encoding:.utf8)
      try SchemaComparison.columnsQuery(object("T",type:"U")).write(toFile:path+".columns.sql",atomically:true,encoding:.utf8)
    }
  }
  @Test func scopedInventoryKeepsDirectDependencyOwnersAndDatabaseTriggerIdentity() throws {
    let normal=SchemaObjectKey(schema:"odd']",name:"same'name")
    let trigger=SchemaObjectKey(schema:"",name:"same'name",databaseTrigger:true)
    let scoped=SchemaComparison.inventory(keys:[normal,trigger])
    let dependencies=try #require(scoped.range(of:"SELECT dependency.owner_schema"))
    let query=String(scoped[dependencies.lowerBound...])
    #expect(query.contains("sys.sql_expression_dependencies") && query.contains("sys.foreign_keys") && query.contains("t.parent_class=1"))
    #expect(query.contains("dependency.owner_schema=N'odd'']' AND dependency.owner_name=N'same''name' AND dependency.database_trigger=0"))
    #expect(query.contains("dependency.owner_schema=N'' AND dependency.owner_name=N'same''name' AND dependency.database_trigger=1"))
    #expect(query.contains("THEN db_trigger.name ELSE OBJECT_NAME(owner.object_id)"))
    #expect(!query.contains("WITH RECURSIVE") && !query.contains("m.definition"))
    #expect(!SchemaComparison.inventory().contains("WHERE (dependency.owner_schema="))
    #expect(SchemaComparison.inventory(keys:[]).hasSuffix(") dependency WHERE 1=0;"))

    // The same name in schema and database trigger namespaces cannot merge.
    let referenced=SchemaObjectKey(schema:"dbo",name:"Customers")
    var result=Execution();result.results=[Rows(values:[["1","TestDB"]]),Rows(),Rows(values:[
      [normal.schema,normal.name,referenced.schema,referenced.name,"0"],
      [nil,trigger.name,referenced.schema,referenced.name,"1"]])]
    let snapshot=try SchemaComparison.decode(result)
    #expect(snapshot.dependencies.count==2)
    #expect(snapshot.dependencies[normal]==[referenced] && snapshot.dependencies[trigger]==[referenced])
  }
  @Test func tableListUsesColumnDigestWhileFullBaselineProtectsEveryDDLChange() throws {
    let rawA=String(repeating:"a",count:64),rawB=String(repeating:"b",count:64),columns=String(repeating:"c",count:64),changedColumns=String(repeating:"d",count:64)
    func decoded(raw:String?,columnDigest:String?,issue:String="",name:String="T") throws -> SchemaSnapshot {
      var execution=Execution();execution.results=[Rows(values:[["1","A"]]),Rows(values:[["1","dbo",name,"U",raw,issue,columnDigest]]),Rows()]
      return try SchemaComparison.decode(execution)
    }
    let source=try decoded(raw:rawA,columnDigest:columns.uppercased())
    let indexOnly=try decoded(raw:rawB,columnDigest:columns)
    let key=SchemaObjectKey(schema:"dbo",name:"T")
    let equal=try #require(SchemaComparison.compare(source:source,target:indexOnly).first)
    #expect(equal.status == .equal && !equal.canStage)
    #expect(source.objects[key]?.digest==rawA && indexOnly.objects[key]?.digest==rawB)
    #expect(source.objects[key]?.comparisonDigest==columns)
    #expect(throws:SQLFailure.self) {try SchemaMigration.validateBaseline(source,current:indexOnly,keys:[key])}
    let changed=try decoded(raw:rawB,columnDigest:changedColumns)
    #expect(try SchemaComparison.compare(source:source,target:changed).first?.status == .changed)
    let special=try decoded(raw:rawB,columnDigest:changedColumns,issue:"Özel tablo özellikleri için otomatik taşıma kapalı.")
    let specialDifference=try #require(SchemaComparison.compare(source:source,target:special).first)
    #expect(specialDifference.status == .changed && !specialDifference.canStage)
    #expect(try SchemaComparison.compare(source:source,target:.init(objects:[])).first?.status == .sourceOnly)
    #expect(try SchemaComparison.compare(source:.init(objects:[]),target:source).first?.status == .targetOnly)
    #expect(try SchemaComparison.compare(source:source,target:.init(objects:[object("T",type:"V")])).first?.status == .typeConflict)
    let unavailable=try decoded(raw:nil,columnDigest:columns,issue:"Tanım şifreli veya görünmüyor.")
    #expect(try SchemaComparison.compare(source:source,target:unavailable).first?.status == .unavailable)
    #expect(throws:SQLFailure.self) {try decoded(raw:rawA,columnDigest:nil)}
    #expect(throws:SQLFailure.self) {try decoded(raw:rawA,columnDigest:"invalid")}
  }
  @Test func tableComparisonHashContainsOnlyDisplayedColumnPropertiesInOneInventoryRequest() throws {
    let sql=SchemaComparison.inventory()
    let start=try #require(sql.range(of:"CASE WHEN o.type='U' THEN CONVERT(varchar(64),HASHBYTES"))
    let end=try #require(sql.range(of:"AS comparison_digest",range:start.lowerBound..<sql.endIndex))
    let projection=String(sql[start.lowerBound..<end.upperBound])
    for token in ["c.name","type_schema","type_name","base_type","is_user_defined","is_assembly_type","max_length","precision","scale","is_nullable","collation_name","is_identity","seed_value","increment_value","computed","is_persisted","default_sql","is_sparse","is_rowguidcol","is_hidden","generated_always_type","xml_namespace","is_xml_document","ORDER BY c.column_id"] {#expect(projection.contains(token))}
    for excluded in ["dc.name","sys.indexes","sys.check_constraints","sys.foreign_keys","temporal_type","is_memory_optimized","lock_escalation","is_ansi_padded","is_filestream","encryption_type","is_not_for_replication","SELECT c.column_id"] {#expect(!projection.contains(excluded))}
    #expect(sql.contains("dc.name AS default_name") && sql.contains("sys.indexes") && sql.contains("sys.foreign_keys"))
    #expect(sql.contains("-- StudioSchemaInventory v2"))
  }
  @Test func emptyXMLMetadataIsCoalescedWithoutHidingUnreadableModuleDefinitions() throws {
    func count(_ pattern:String,in sql:String) throws -> Int {try NSRegularExpression(pattern:pattern).numberOfMatches(in:sql,range:NSRange(location:0,length:(sql as NSString).length))}
    for (sql,minimum) in [(SchemaComparison.inventory(),8),(SchemaComparison.refinementQuery([object("v",type:"V")]),2)] {
      let serialized=try count(#"CONVERT\(nvarchar\(max\),\(\s*SELECT"#,in:sql)
      let coalesced=try count(#"ISNULL\(CONVERT\(nvarchar\(max\),\(\s*SELECT"#,in:sql)
      #expect(serialized>=minimum && serialized==coalesced)
      #expect(sql.contains("FOR XML PATH('index'),TYPE"))
      #expect(!sql.contains("ISNULL(CONVERT(nvarchar(max),m.definition)"))
    }
    let inventory=SchemaComparison.inventory()
    #expect(inventory.contains("ELSE CONVERT(nvarchar(max),m.definition)+NCHAR(10)"))
    var encrypted=Execution();encrypted.results=[Rows(values:[["1","A"]]),Rows(values:[["1","dbo","EncryptedView","V",nil,"Tanım şifreli veya görünmüyor.",nil]]),Rows()]
    let snapshot=try SchemaComparison.decode(encrypted)
    #expect(try SchemaComparison.compare(source:snapshot,target:snapshot).first?.status == .unavailable)
    encrypted.results[1]=Rows(values:[["1","dbo","ReadableView","V",nil,"",nil]])
    #expect(throws:SQLFailure.self) {try SchemaComparison.decode(encrypted)}
  }
  @Test func refinementIgnoresDeliveryHeaderButPreservesBodyLiteralsAndSettings() throws {
    let obj=object("renamed")
    let snapshot=try SchemaSnapshot(objects:[obj])
    func refined(_ sql:String,_ quoted:String="1") throws -> SchemaObject {
      var e=Execution();e.results=[Rows(values:[["1",sql,"1",quoted,"0",nil]])]
      return try #require(SchemaComparison.refine(snapshot,objects:[obj],result:e).objects[obj.key])
    }
    let a=try refined("CREATE PROC oldName AS SELECT N'ALTER  x';")
    let b=try refined("ALTER PROC dbo.renamed AS SELECT N'ALTER  x';")
    #expect(a.comparisonDigest==b.comparisonDigest)
    #expect(try refined("ALTER PROC dbo.renamed AS SELECT N'ALTER x';").comparisonDigest != a.comparisonDigest)
    #expect(try refined("ALTER PROC dbo.renamed AS SELECT N'ALTER  x';","0").comparisonDigest != a.comparisonDigest)
    try SchemaMigration.validateBaseline(try .init(objects:[a]),current:snapshot,keys:[obj.key])
  }
  @Test func independentColumnsPreserveAliasBaseTypesUnicodeMaxAndSpecialTableMetadata() throws {
    let obj=object("SpecialTable",type:"U",issue:"Özel tablo özellikleri için otomatik taşıma kapalı.")
    var alias=columnRow("Amount",ordinal:1,type:"TDBFLOAT",base:"decimal",schema:"custom]schema",alias:true,length:13,precision:28,scale:8,nullable:false)
    alias[11]="Turkish_100_CI_AS";alias[12]="1";alias[13]="-1000000000000000000000000000";alias[14]="2";alias[18]="1";alias[20]="1";alias[21]="1"
    var computed=columnRow("Total",ordinal:4,type:"numeric",base:"numeric",length:17,precision:38,scale:12)
    computed[15]="([Amount]*(2))";computed[16]="1";computed[17]="((0))"
    let rows=[alias,columnRow("Title",ordinal:2,type:"nvarchar",base:"nvarchar",length:200,precision:0),columnRow("Notes",ordinal:3,type:"nvarchar",base:"nvarchar",length:-1,precision:0),computed]
    let columns=try SchemaComparison.decodeColumns(columnExecution(obj,rows:rows),object:obj)
    #expect(columns[0].dataType=="[custom]]schema].[TDBFLOAT]")
    #expect(columns[0].baseDataType=="decimal(28,8)" && !columns[0].nullable)
    #expect(columns[0].identitySeed=="-1000000000000000000000000000" && columns[0].attributes.contains("HIDDEN"))
    #expect(columns[1].dataType=="nvarchar(100)" && columns[2].dataType=="nvarchar(max)")
    #expect(columns[3].dataType=="numeric(38,12)" && columns[3].attributes.contains("PERSISTED") && columns[3].defaultSQL=="((0))")
    #expect(SchemaColumn(ordinal:1,name:"B",typeName:"varbinary",maxLength:-1).dataType=="varbinary(max)")
    #expect(SchemaColumn(ordinal:1,name:"T",typeName:"datetime2",scale:7).dataType=="datetime2(7)")
    #expect(SchemaColumn(ordinal:1,name:"F",typeName:"float",precision:24).dataType=="float(24)")
    #expect(SchemaColumn(ordinal:1,name:"M",typeName:"money",precision:19,scale:4).dataType=="money")
    #expect(SchemaColumn(ordinal:1,name:"X",typeName:"xml",xmlCollection:"[dbo].[Doc]",xmlDocument:true).dataType=="xml(DOCUMENT [dbo].[Doc])")
    let other=object("SpecialTable",type:"U",digest:String(repeating:"b",count:64),issue:obj.issue)
    let diff=try #require(SchemaComparison.compare(source:.init(objects:[obj]),target:.init(objects:[other])).first)
    #expect(diff.status == .changed && !diff.canStage && !diff.migrationIssue.isEmpty)
  }
  @Test func columnComparisonMatchesExactNamesAndExplainsEveryChangedProperty() throws {
    let source=[SchemaColumn(ordinal:1,name:"Code",typeName:"TDBFLOAT",baseType:"decimal",userDefined:true,maxLength:13,precision:28,scale:8,nullable:false,collation:"Turkish_100_CI_AS",identity:true,identitySeed:"1",identityIncrement:"2",computed:"([Id]+(1))",persisted:true,defaultSQL:"(1)",sparse:true),SchemaColumn(ordinal:2,name:"Added",typeName:"int"),SchemaColumn(ordinal:3,name:"same",typeName:"int")]
    let target=[SchemaColumn(ordinal:1,name:"Missing",typeName:"int"),SchemaColumn(ordinal:2,name:"Code",typeName:"TDBFLOAT",baseType:"decimal",userDefined:true,maxLength:13,precision:28,scale:6),SchemaColumn(ordinal:3,name:"same",typeName:"int")]
    let differences=try SchemaComparison.compareColumns(source:source,target:target)
    #expect(differences.map(\.name)==["Code","Added","same","Missing"])
    #expect(differences[0].changes==[.dataType,.nullability,.order,.collation,.identity,.computed,.defaultValue,.attributes])
    #expect(differences[1].changes==[.added] && differences[2].isEqual && differences[3].changes==[.removed])
    #expect(differences[0].summary.contains("Veri tipi") && differences[2].summary=="Aynı")
    #expect(try SchemaComparison.compareColumns(source:[.init(ordinal:1,name:"Name",typeName:"int")],target:[.init(ordinal:1,name:"name",typeName:"int")]).count==2)
    #expect(throws:SQLFailure.self) {try SchemaComparison.compareColumns(source:[source[0],source[0]],target:[])}
    let decimalAlias=SchemaColumn(ordinal:1,name:"Amount",typeSchema:"dbo",typeName:"TDBFLOAT",baseType:"decimal",userDefined:true,maxLength:13,precision:28,scale:8)
    let numericAlias=SchemaColumn(ordinal:1,name:"Amount",typeSchema:"dbo",typeName:"TDBFLOAT",baseType:"numeric",userDefined:true,maxLength:13,precision:28,scale:8)
    #expect(decimalAlias.dataType==numericAlias.dataType)
    #expect(try SchemaComparison.compareColumns(source:[decimalAlias],target:[numericAlias]).first?.changes==[.dataType])
  }
  @Test func columnDecoderRejectsIncompleteInvisibleDuplicateAndMalformedRows() throws {
    let obj=object("v",type:"V"),row=columnRow("Id")
    var result=columnExecution(obj,rows:[row])
    #expect(try SchemaComparison.decodeColumns(result,object:obj).count==1)
    result.partial=true;#expect(throws:SQLFailure.self) {try SchemaComparison.decodeColumns(result,object:obj)}
    result=columnExecution(obj,rows:[row]);result.results[0]=Rows(values:[["1","V","0"]]);#expect(throws:SQLFailure.self) {try SchemaComparison.decodeColumns(result,object:obj)}
    result=columnExecution(obj,rows:[row,row]);#expect(throws:SQLFailure.self) {try SchemaComparison.decodeColumns(result,object:obj)}
    var malformed=row;malformed[8]="100";result=columnExecution(obj,rows:[malformed]);#expect(throws:SQLFailure.self) {try SchemaComparison.decodeColumns(result,object:obj)}
    malformed=row;malformed[0]="2";result=columnExecution(obj,rows:[malformed]);#expect(throws:SQLFailure.self) {try SchemaComparison.decodeColumns(result,object:obj)}
    result=columnExecution(obj,rows:[]);#expect(throws:SQLFailure.self) {try SchemaComparison.decodeColumns(result,object:obj)}
    result=columnExecution(obj,rows:[row]);result.stoppedEarly=true;#expect(throws:SQLFailure.self) {try SchemaComparison.decodeColumns(result,object:obj)}
    result=columnExecution(obj,rows:[row]);result.results[1].truncated=true;#expect(throws:SQLFailure.self) {try SchemaComparison.decodeColumns(result,object:obj)}
  }
  @Test func viewListUsesOnlyCanonicalCodeWhileStructureStillGuardsMigration() throws {
    let source=object("v",type:"V"),target=object("v",type:"V",digest:String(repeating:"b",count:64),id:2)
    func refine(_ object:SchemaObject,sql:String,structure:String?) throws -> SchemaSnapshot {
      var result=Execution();result.results=[Rows(values:[[String(object.objectID),sql,"1","1","0",nil,structure]])]
      return try SchemaComparison.refine(.init(objects:[object]),objects:[object],result:result)
    }
    let a=try refine(source,sql:"CREATE VIEW old AS SELECT Code FROM dbo.T;",structure:String(repeating:"c",count:64))
    let b=try refine(target,sql:"ALTER VIEW dbo.v AS SELECT Code FROM dbo.T;",structure:String(repeating:"d",count:64))
    let difference=try #require(SchemaComparison.compare(source:a,target:b).first)
    #expect(difference.status == .equal && !difference.canStage)
    #expect(a.objects[source.key]?.definitionDigest==b.objects[target.key]?.definitionDigest)
    #expect(a.objects[source.key]?.comparisonDigest==b.objects[target.key]?.comparisonDigest)
    #expect(a.objects[source.key]?.structuralDigest != b.objects[target.key]?.structuralDigest)
    #expect(a.objects[source.key]?.digest==source.digest && b.objects[target.key]?.digest==target.digest)
    #expect(throws:SQLFailure.self) {try SchemaMigration.validateBaseline(a,current:b,keys:[source.key])}
    #expect(difference.migrationIssue.contains("bağımlı"))
    #expect(throws:SQLFailure.self) {try SchemaMigration.orderedKeys([source.key],source:a,target:b)}
    let same=try refine(target,sql:"ALTER VIEW dbo.v AS SELECT Code FROM dbo.T;",structure:String(repeating:"C",count:64))
    #expect(try SchemaComparison.compare(source:a,target:same).first?.status == .equal)
    let codeDifferent=try refine(target,sql:"ALTER VIEW dbo.v AS SELECT Other FROM dbo.T;",structure:String(repeating:"d",count:64))
    #expect(try SchemaComparison.compare(source:a,target:codeDifferent).first?.canStage == true)
    #expect(throws:SQLFailure.self) {try refine(source,sql:"CREATE VIEW dbo.v AS SELECT 1 AS Code;",structure:nil)}
    let query=SchemaComparison.refinementQuery([source])
    #expect(query.contains("sys.columns") && query.contains("sys.indexes") && query.contains("o.type='V'"))
    #expect(query.contains("base.user_type_id=c.system_type_id") && query.contains("ISNULL(base.name,ty.name) AS base_type"))
  }
  @Test func viewSelectProjectionAdditionSurvivesHeaderNormalizationAndEqualStoredColumnMetadata() throws {
    let source=object("TEDARIK_FIYAT_FARKI_VW",type:"V",id:41)
    let target=object("TEDARIK_FIYAT_FARKI_VW",type:"V",digest:String(repeating:"b",count:64),id:83)
    // The reported difference is a SELECT projection after InvoiceDate. Stored
    // view column metadata can be stale; code equality must not depend on it.
    let targetSQL="""
    CREATE VIEW [dbo].[TEDARIK_FIYAT_FARKI_VW]
    AS
    SELECT
        C.TARIH AS InvoiceDate,
        C.CARI_KODU AS SupplierCode
    FROM dbo.TBLCASABIT AS C;
    """
    let sourceSQL=targetSQL.replacingOccurrences(of:"C.TARIH AS InvoiceDate,",with:"C.TARIH AS InvoiceDate,\n    C.INCKEYNO AS ExternalOrderId,")
    let originalSource=try SchemaSnapshot(objects:[source]),originalTarget=try SchemaSnapshot(objects:[target])
    #expect(try SchemaComparison.compare(source:originalSource,target:originalTarget).first?.status == .changed)
    func refined(_ object:SchemaObject,_ sql:String) throws -> SchemaSnapshot {
      var execution=Execution();execution.results=[Rows(values:[[String(object.objectID),sql,"1","1","0",nil,String(repeating:"c",count:64)]])]
      return try SchemaComparison.refine(.init(objects:[object]),objects:[object],result:execution)
    }
    let a=try refined(source,sourceSQL),b=try refined(target,targetSQL)
    let difference=try #require(SchemaComparison.compare(source:a,target:b).first)
    #expect(difference.status == .changed && difference.canStage)
    #expect(a.objects[source.key]?.comparisonDigest != b.objects[target.key]?.comparisonDigest)
    #expect(a.objects[source.key]?.structuralDigest == b.objects[target.key]?.structuralDigest)
    let deliveryOnly=try refined(target,sourceSQL.replacingOccurrences(of:"CREATE VIEW [dbo].[TEDARIK_FIYAT_FARKI_VW]",with:"ALTER VIEW oldName"))
    #expect(try SchemaComparison.compare(source:a,target:deliveryOnly).first?.status == .equal)
    #expect(try ExplorerScripts.module(sourceSQL,verb:"CREATE",qualified:source.key.qualified).contains("C.INCKEYNO AS ExternalOrderId,"))
  }
  @Test func viewsIgnoreFormattingButKeepRealProjectionProtectedTextAndSessionDifferences() throws {
    let source=object("TEDARIK_FIYAT_FARKI_VW",type:"V",id:41)
    let target=object("TEDARIK_FIYAT_FARKI_VW",type:"V",digest:String(repeating:"b",count:64),id:83)
    let original="CREATE VIEW oldName AS\nSELECT\n    C.STHAR_GCMIK AS OrderQuantity, -- Siparis Miktari      \n    C.STHAR_TARIH AS InvoiceDate, -- Fatura  Tarihi      \n    N'a  b' AS [Description Text]\nFROM dbo.T AS C\nWHERE C.STHAR_GCMIK >= 1.2e-3;"
    let formatted="ALTER VIEW dbo.TEDARIK_FIYAT_FARKI_VW AS\r\n\r\n SELECT C.STHAR_GCMIK\tAS OrderQuantity ,    -- Siparis Miktari        \r\nC.STHAR_TARIH AS InvoiceDate, -- Fatura  Tarihi\t \r\n N'a  b' AS [Description Text]\r\nFROM dbo . T AS C WHERE C.STHAR_GCMIK>=1.2e-3 ;\r\n"
    func refined(_ object:SchemaObject,_ sql:String,ansi:String="1",quoted:String="1") throws -> SchemaSnapshot {
      var execution=Execution();execution.results=[Rows(values:[[String(object.objectID),sql,ansi,quoted,"0",nil,String(repeating:"c",count:64)]])]
      return try SchemaComparison.refine(.init(objects:[object]),objects:[object],result:execution)
    }
    let a=try refined(source,original),b=try refined(target,formatted)
    let equal=try #require(SchemaComparison.compare(source:a,target:b).first)
    #expect(equal.status == .equal && !equal.canStage)
    #expect(a.objects[source.key]?.digest==source.digest && b.objects[target.key]?.digest==target.digest)
    #expect(throws:SQLFailure.self) {try SchemaMigration.validateBaseline(a,current:b,keys:[source.key])}
    let added=formatted.replacingOccurrences(of:" N'a  b'",with:" C.INCKEYNO AS ExternalOrderId,\r\n N'a  b'")
    #expect(try SchemaComparison.compare(source:a,target:refined(target,added)).first?.status == .changed)
    for changed in [
      formatted.replacingOccurrences(of:"N'a  b'",with:"N'a b'"),
      formatted.replacingOccurrences(of:"[Description Text]",with:"[Description  Text]"),
      formatted.replacingOccurrences(of:"-- Siparis Miktari",with:"-- Siparis  Miktari"),
      formatted.replacingOccurrences(of:"C.STHAR_GCMIK>=",with:"C.STHAR_GCMIK>=".lowercased())
    ] {#expect(try SchemaComparison.compare(source:a,target:refined(target,changed)).first?.status == .changed)}
    #expect(try SchemaComparison.compare(source:a,target:refined(target,formatted,ansi:"0")).first?.status == .changed)
    #expect(try SchemaComparison.compare(source:a,target:refined(target,formatted,quoted:"0")).first?.status == .changed)
    let procedure=object("p",type:"P"),function=object("f",type:"FN")
    for module in [procedure,function] {
      let kind=module.type=="P" ? "PROC":"FUNCTION"
      let compact="CREATE \(kind) dbo.\(module.key.name) AS SELECT 1;"
      #expect(try SchemaComparison.compare(source:refined(module,compact),target:refined(module,compact.replacingOccurrences(of:"SELECT 1",with:"SELECT\n  1"))).first?.status == .equal)
    }
    var content=Execution();content.results=[Rows(values:[[added,"1","1","0",nil]])]
    let decoded=try SchemaComparison.decodeContent(content,object:target)
    #expect(decoded.definition.utf8.elementsEqual(added.utf8))
    #expect(decoded.sql.contains("C.INCKEYNO AS ExternalOrderId,\r\n"))
  }
  @Test func readableSQLModuleComparisonPolicyExcludesCLRAndNonModuleObjects() throws {
    for type in ["V","P","FN","IF","TF","TR","TRD"] {#expect(object("module",type:type).usesSQLCodeComparison)}
    for type in ["U","SN","PC","FS","FT","TA","unknown"] {#expect(!object("module",type:type).usesSQLCodeComparison)}
    for type in ["PC","FS","FT","TA"] {
      var result=Execution();result.results=[Rows(values:[["1","A"]]),Rows(values:[["1","dbo","CLRModule",type,nil,"CLR tanımı otomatik taşınamaz.",nil]]),Rows()]
      let snapshot=try SchemaComparison.decode(result)
      #expect(try SchemaComparison.compare(source:snapshot,target:snapshot).first?.status == .unavailable)
    }
  }
  @Test(arguments:["P","FN","IF","TF","TR","TRD"])
  func proceduresFunctionsAndTriggersIgnoreOnlyFormatting(_ type:String) throws {
    let key=SchemaObjectKey(schema:type=="TRD" ? "":"dbo",name:"module",databaseTrigger:type=="TRD")
    let source=SchemaObject(key:key,objectID:41,type:type,digest:String(repeating:"a",count:64))
    // Keep the object ID equal to isolate the raw-hash conflict assertion below.
    let target=SchemaObject(key:key,objectID:41,type:type,digest:String(repeating:"b",count:64))
    let declarations:[String:String]=[
      "P":"CREATE PROC oldName @value int AS -- note  text      \nBEGIN SELECT @value + 1 AS [Value Text], N'a  b' AS Note; END;",
      "FN":"CREATE FUNCTION oldName(@value int) RETURNS int AS -- note  text      \nBEGIN DECLARE @result int; SELECT @result = @value + 1 FROM dbo.[Value Text] WHERE Note = N'a  b'; RETURN @result; END;",
      "IF":"CREATE FUNCTION oldName(@value int) RETURNS TABLE AS -- note  text      \nRETURN (SELECT @value + 1 AS [Value Text], N'a  b' AS Note);",
      "TF":"CREATE FUNCTION oldName(@value int) RETURNS @result TABLE ([Value Text] int, Note nvarchar(20)) AS -- note  text      \nBEGIN INSERT @result SELECT @value + 1, N'a  b'; RETURN; END;",
      "TR":"CREATE TRIGGER oldName ON dbo.T AFTER UPDATE AS -- note  text      \nBEGIN DECLARE @value int=0; SELECT @value + 1 AS [Value Text], N'a  b' AS Note; END;",
      "TRD":"CREATE TRIGGER oldName ON DATABASE FOR CREATE_TABLE AS -- note  text      \nBEGIN DECLARE @value int=0; SELECT @value + 1 AS [Value Text], N'a  b' AS Note; END;"
    ]
    let original=try #require(declarations[type]).replacingOccurrences(of:"\n",with:"\n/* outer\n/* nested */ tail */\n")
    let formatted=original.replacingOccurrences(of:"CREATE ",with:"ALTER ").replacingOccurrences(of:"oldName",with:key.qualified)
      .replacingOccurrences(of:"\n",with:"\r\n").replacingOccurrences(of:"      \r\n",with:"\t \r\n")
      .replacingOccurrences(of:" AS ",with:"\r\nAS\t").replacingOccurrences(of:" + 1",with:"\t+\t1")
      .replacingOccurrences(of:" = ",with:"\t=\t").replacingOccurrences(of:"; END",with:";\r\n\r\nEND")
    let parent=type=="TRD" ? "DATABASE":type=="TR" ? "[dbo].[T]":""
    func refined(_ object:SchemaObject,_ sql:String,ansi:String="1",quoted:String="1") throws -> SchemaSnapshot {
      var result=Execution();result.results=[Rows(values:[[String(object.objectID),sql,ansi,quoted,"0",parent]])]
      return try SchemaComparison.refine(.init(objects:[object]),objects:[object],result:result)
    }
    let a=try refined(source,original),b=try refined(target,formatted)
    let equal=try #require(SchemaComparison.compare(source:a,target:b).first)
    #expect(equal.status == .equal && !equal.canStage)
    #expect(a.objects[key]?.comparisonDigest==b.objects[key]?.comparisonDigest)
    #expect(a.objects[key]?.digest==source.digest && b.objects[key]?.digest==target.digest)
    #expect(throws:SQLFailure.self) {try SchemaMigration.validateBaseline(a,current:b,keys:[key])}
    for changed in [
      formatted.replacingOccurrences(of:"\t+\t1",with:"\t+\t2"),
      formatted.replacingOccurrences(of:"N'a  b'",with:"N'a b'"),
      formatted.replacingOccurrences(of:"[Value Text]",with:"[Value  Text]"),
      formatted.replacingOccurrences(of:"-- note  text",with:"-- note text"),
      formatted.replacingOccurrences(of:"/* nested */",with:"/*  nested */")
    ] {#expect(try SchemaComparison.compare(source:a,target:refined(target,changed)).first?.status == .changed)}
    #expect(try SchemaComparison.compare(source:a,target:refined(target,formatted,ansi:"0")).first?.status == .changed)
    #expect(try SchemaComparison.compare(source:a,target:refined(target,formatted,quoted:"0")).first?.status == .changed)
    var execution=Execution();execution.results=[Rows(values:[[formatted,"1","1","0",parent]])]
    let content=try SchemaComparison.decodeContent(execution,object:try #require(b.objects[key]))
    #expect(content.definition.utf8.elementsEqual(formatted.utf8))
    #expect(content.sql.contains("N'a  b'"))
  }
  @Test(arguments:["TR","TRD"])
  func triggerStateParentAndOriginalMigrationSQLRemainSignificant(_ type:String) throws {
    let key=SchemaObjectKey(schema:type=="TRD" ? "":"dbo",name:"trigger",databaseTrigger:type=="TRD")
    let source=SchemaObject(key:key,objectID:41,type:type,digest:String(repeating:"a",count:64))
    let target=SchemaObject(key:key,objectID:41,type:type,digest:String(repeating:"b",count:64))
    let parent=type=="TRD" ? "DATABASE":"[dbo].[T]"
    let scope=type=="TRD" ? "ON DATABASE FOR CREATE_TABLE":"ON [dbo].[T] AFTER UPDATE"
    let sql="CREATE TRIGGER oldName \(scope) AS\r\nBEGIN\r\n\tSELECT N'keep  original'; -- retained      \r\nEND;"
    func refined(_ object:SchemaObject,disabled:Bool,parent:String) throws -> SchemaSnapshot {
      var result=Execution();result.results=[Rows(values:[[String(object.objectID),sql,"0","0",disabled ? "1":"0",parent]])]
      return try SchemaComparison.refine(.init(objects:[object]),objects:[object],result:result)
    }
    let a=try refined(source,disabled:true,parent:parent)
    let b=try refined(target,disabled:false,parent:parent)
    #expect(try SchemaComparison.compare(source:a,target:b).first?.status == .changed)
    let differentParent=try refined(target,disabled:true,parent:parent+"_changed")
    #expect(try SchemaComparison.compare(source:a,target:differentParent).first?.status == .changed)
    let left=try #require(a.objects[key]),right=try #require(b.objects[key])
    let desired=SchemaObjectContent(object:left,sql:try ExplorerScripts.module(sql,verb:"CREATE",qualified:key.qualified,ansi:false,quoted:false),ansi:false,quoted:false,disabled:true,triggerParent:parent,definition:sql)
    let existing=SchemaObjectContent(object:right,sql:desired.sql,ansi:false,quoted:false,disabled:false,triggerParent:parent,definition:sql)
    let plan=try SchemaMigration.plan(selected:[key],source:a,target:b,sourceContent:[key:desired],targetContent:[key:existing])
    #expect(plan.sql.contains("SET ANSI_NULLS OFF;") && plan.sql.contains("SET QUOTED_IDENTIFIER OFF;"))
    #expect(plan.sql.contains("DISABLE TRIGGER \(key.qualified) ON \(parent);"))
    #expect(plan.sql.contains("N''keep  original''; -- retained      \r\n"))
    #expect(desired.definition.utf8.elementsEqual(sql.utf8))
  }
  @Test func migrationOrdersDependenciesEscapesSQLAndNeverDropsModules() throws {
    let table=object("T",type:"U",id:10),view=object("v",type:"V",id:11),proc=object("p']\n--",id:12)
    let source=try SchemaSnapshot(objects:[table,view,proc],dependencies:[view.key:[table.key],proc.key:[view.key]])
    let target=try SchemaSnapshot(objects:[])
    let content:[SchemaObjectKey:SchemaObjectContent]=[
      table.key:.init(object:table,sql:"",table:.init(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int")])),
      view.key:.init(object:view,sql:"CREATE VIEW old AS SELECT 1 AS Id;"),proc.key:.init(object:proc,sql:"CREATE PROC old AS SELECT N'O''Hara';")]
    #expect(throws:SQLFailure.self) {try SchemaMigration.orderedKeys([proc.key],source:source,target:target)}
    let plan=try SchemaMigration.plan(selected:[proc.key,table.key,view.key],source:source,target:target,sourceContent:content,targetContent:[:])
    #expect(plan.keys == [table.key,view.key,proc.key])
    #expect(plan.sql.contains("ROLLBACK TRANSACTION") && plan.sql.contains("EXEC sys.sp_executesql N'CREATE VIEW"))
    #expect(plan.sql.contains("N''O''''Hara''") && !plan.sql.contains("DROP TABLE") && !plan.sql.contains("DROP PROCEDURE"))
    #expect(try TSQL.batches(plan.sql).count==1)
    if let path=ProcessInfo.processInfo.environment["MSSQL_SCHEMA_SQL_DUMP"] {try plan.sql.write(toFile:path+".plan.sql",atomically:true,encoding:.utf8)}
    let cycle=try SchemaSnapshot(objects:[view,proc],dependencies:[view.key:[proc.key],proc.key:[view.key]])
    #expect(throws:SQLFailure.self) {try SchemaMigration.orderedKeys([view.key,proc.key],source:cycle,target:target)}
  }
  @Test func existingModulesUseAlterAndTriggerStateAndConflictsAreGuarded() throws {
    let obj=object("tr",type:"TR"),old=object("tr",type:"TR",digest:String(repeating:"b",count:64),id:9)
    let a=try SchemaSnapshot(objects:[obj]),b=try SchemaSnapshot(objects:[old])
    let content=SchemaObjectContent(object:obj,sql:"CREATE TRIGGER [dbo].[tr] ON [dbo].[T] AFTER UPDATE AS SELECT 1;",disabled:true,triggerParent:"[dbo].[T]")
    let plan=try SchemaMigration.plan(selected:[obj.key],source:a,target:b,sourceContent:[obj.key:content],targetContent:[old.key:.init(object:old,sql:"old")])
    #expect(plan.sql.contains("ALTER TRIGGER") && plan.sql.contains("DISABLE TRIGGER [dbo].[tr] ON [dbo].[T]"))
    #expect(plan.sql.contains("<> 9") && plan.sql.contains("SCHEMA_ID"))
    #expect(plan.originalSQL.hasPrefix("-- [dbo].[tr]\n") && plan.desiredSQL.hasPrefix("-- [dbo].[tr]\n"))
    #expect(throws:SQLFailure.self) {try SchemaMigration.validateBaseline(b,current:a,keys:[obj.key])}
    let unsupported=try SchemaSnapshot(objects:[object("tr",type:"TR",issue:"indexed")])
    #expect(throws:SQLFailure.self) {try SchemaMigration.orderedKeys([obj.key],source:unsupported,target:b)}
  }
  @Test func tableAlterAddsColumnsAndConstraintsButRejectsDestructiveRebuilds() throws {
    let target=TableDefinition(schema:"dbo",name:"T",columns:[.init(id:10,name:"Id",type:"int",nullable:false),.init(id:20,name:"Name",type:"nvarchar(50)",defaultName:"DF_Old",defaultSQL:"(N'old')")])
    var source=target;source.columns[1].type="nvarchar(100)";source.columns[1].defaultName="DF_New";source.columns[1].defaultSQL="(N'new')";source.columns.append(.init(id:30,name:"City",type:"nvarchar(100)"))
    source.definitions=[.init(name:"PK_T",kind:"PK",sql:"ALTER TABLE [dbo].[T] ADD CONSTRAINT [PK_T] PRIMARY KEY ([Id]);"),.init(name:"FK_T",kind:"FK",sql:"ALTER TABLE [dbo].[T] ADD CONSTRAINT [FK_T] FOREIGN KEY ([Id]) REFERENCES [dbo].[T] ([Id]);")]
    let sql=try SchemaMigration.tableChanges(source:source,target:target)
    #expect(sql.contains("DROP CONSTRAINT [DF_Old]") && sql.contains("ALTER COLUMN [Name] nvarchar(100)"))
    #expect(sql.contains("ADD [City]") && !sql.contains("DROP TABLE") && !sql.contains("DROP COLUMN"))
    #expect(try #require(sql.range(of:"ADD CONSTRAINT [PK_T]")).lowerBound < #require(sql.range(of:"ADD CONSTRAINT [FK_T]")).lowerBound)
    source.columns.removeFirst();#expect(throws:SQLFailure.self) {try SchemaMigration.tableChanges(source:source,target:target)}
    source=target;source.columns[0].identity=true;#expect(throws:SQLFailure.self) {try SchemaMigration.tableChanges(source:source,target:target)}
    let aliasTarget=TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Amount",type:"[dbo].[TDBFLOAT]",baseType:"decimal(28,4)")])
    var aliasSource=aliasTarget;aliasSource.columns[0].baseType="decimal(28,8)";aliasSource.columns.append(.init(id:2,name:"NewColumn",type:"int"))
    #expect(throws:SQLFailure.self) {try SchemaMigration.tableChanges(source:aliasSource,target:aliasTarget)}
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func liveInventoryUsesCompleteServerHashesAndDetectsDDLChangeWithRollback() async throws {
    let password=try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let c=ODBCConnection();try await c.connect(ServerProfile(trustCertificate:true),password:password)
    let key=SchemaObjectKey(schema:"dbo",name:"StudioCompare_"+UUID().uuidString.replacingOccurrences(of:"-",with:""))
    let view=SchemaObjectKey(schema:"dbo",name:"StudioView_"+UUID().uuidString.replacingOccurrences(of:"-",with:""))
    do {
      _=try await c.execute("BEGIN TRANSACTION; CREATE TABLE \(key.qualified) ([Id] int NOT NULL);")
      _=try await c.execute("CREATE VIEW \(view.qualified) AS SELECT [Id] FROM \(key.qualified);")
      let a=try SchemaComparison.decode(await c.execute(SchemaComparison.inventory(keys:[key,view]),limits:SchemaComparison.limits))
      #expect(try #require(a.objects[key]?.digest).count==64)
      #expect(try #require(a.objects[key]?.comparisonDigest).count==64)
      #expect(try #require(a.objects[view]?.digest).count==64)
      #expect(a.dependencies[view]==[key] && a.dependencies[key]==nil)
      let viewOnly=try SchemaComparison.decode(await c.execute(SchemaComparison.inventory(keys:[view]),limits:SchemaComparison.limits))
      #expect(Set(viewOnly.objects.keys)==[view] && viewOnly.dependencies==[view:[key]])
      let tableOnly=try SchemaComparison.decode(await c.execute(SchemaComparison.inventory(keys:[key]),limits:SchemaComparison.limits))
      #expect(Set(tableOnly.objects.keys)==[key] && tableOnly.dependencies.isEmpty)
      let empty=try SchemaComparison.decode(await c.execute(SchemaComparison.inventory(keys:[]),limits:SchemaComparison.limits))
      #expect(empty.objects.isEmpty && empty.dependencies.isEmpty)
      _=try await c.execute("CREATE INDEX [IX_StudioCompare] ON \(key.qualified) ([Id]);")
      let indexOnly=try SchemaComparison.decode(await c.execute(SchemaComparison.inventory(keys:[key,view]),limits:SchemaComparison.limits))
      #expect(a.objects[key]?.digest != indexOnly.objects[key]?.digest)
      #expect(try SchemaComparison.compare(source:a,target:indexOnly).allSatisfy {$0.status == .equal})
      #expect(throws:SQLFailure.self) {try SchemaMigration.validateBaseline(a,current:indexOnly,keys:[key])}
      _=try await c.execute("DROP INDEX [IX_StudioCompare] ON \(key.qualified);")
      let viewBefore=try #require(a.objects[view])
      let refinedBefore=try SchemaComparison.refine(a,objects:[viewBefore],result:await c.execute(SchemaComparison.refinementQuery([viewBefore]),limits:SchemaComparison.limits))
      _=try await c.execute("ALTER TABLE \(key.qualified) ADD [Code] decimal(28,8) NULL;")
      _=try await c.execute("ALTER TABLE \(key.qualified) ALTER COLUMN [Id] bigint NOT NULL;")
      _=try await c.execute("EXEC sys.sp_refreshview \(SQL.literal(view.qualified));")
      let b=try SchemaComparison.decode(await c.execute(SchemaComparison.inventory(keys:[key,view]),limits:SchemaComparison.limits))
      let viewAfter=try #require(b.objects[view])
      let refinedAfter=try SchemaComparison.refine(b,objects:[viewAfter],result:await c.execute(SchemaComparison.refinementQuery([viewAfter]),limits:SchemaComparison.limits))
      #expect(try SchemaComparison.compare(source:refinedBefore,target:refinedAfter).first(where:{$0.key==key})?.status == .changed)
      #expect(try SchemaComparison.compare(source:refinedBefore,target:refinedAfter).first(where:{$0.key==view})?.status == .equal)
      #expect(try SchemaComparison.compare(source:refinedBefore,target:refinedAfter).first(where:{$0.key==view})?.canStage == false)
      let columns=try SchemaComparison.decodeColumns(await c.execute(SchemaComparison.columnsQuery(viewAfter),limits:SchemaComparison.limits),object:viewAfter)
      #expect(columns.first?.dataType=="bigint" && columns.first?.nullable==false)
      _=try await c.execute("ROLLBACK TRANSACTION;");await c.disconnect()
    } catch {_=try? await c.execute("IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;");await c.disconnect();throw error}
  }
}
