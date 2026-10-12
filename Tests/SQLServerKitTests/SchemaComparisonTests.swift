import Foundation
import Testing
@testable import SQLServerKit

struct SchemaComparisonTests {
  private func object(_ name:String,type:String="P",digest:String?=String(repeating:"a",count:64),id:Int=1,issue:String="",schema:String="dbo")->SchemaObject {.init(key:.init(schema:schema,name:name),objectID:id,type:type,digest:digest,issue:issue)}
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
    var execution=Execution();execution.results=[Rows(values:[["1","A"]]),Rows(values:[["1","dbo","p","P",String(repeating:"a",count:64),""]]),Rows()]
    #expect(try SchemaComparison.decode(execution).objects.count==1)
    execution.partial=true;#expect(throws:SQLFailure.self) {try SchemaComparison.decode(execution)}
    execution.partial=false;execution.results[0]=Rows(values:[["0","A"]]);#expect(throws:SQLFailure.self) {try SchemaComparison.decode(execution)}
    execution.results[0]=Rows(values:[["1","A"]]);execution.results[1]=Rows(values:[["1","dbo","p","P","bad",""]]);#expect(throws:SQLFailure.self) {try SchemaComparison.decode(execution)}
    let sql=SchemaComparison.inventory(keys:[.init(schema:"odd']",name:"x'y")])
    for token in ["SHA2_256","sys.columns","sys.index_columns","sys.foreign_key_columns","sys.check_constraints","uses_quoted_identifier","parent_class=0","VIEW DEFINITION","N'odd'']'"] {#expect(sql.contains(token))}
    #expect(!sql.contains("SELECT * FROM"))
    if let path=ProcessInfo.processInfo.environment["MSSQL_SCHEMA_SQL_DUMP"] {
      try SchemaComparison.inventory().write(toFile:path,atomically:true,encoding:.utf8)
      try sql.write(toFile:path+".filtered.sql",atomically:true,encoding:.utf8)
      try SchemaComparison.refinementQuery([object("p")]).write(toFile:path+".refine.sql",atomically:true,encoding:.utf8)
    }
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
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func liveInventoryUsesCompleteServerHashesAndDetectsDDLChangeWithRollback() async throws {
    let password=try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let c=ODBCConnection();try await c.connect(ServerProfile(trustCertificate:true),password:password)
    let key=SchemaObjectKey(schema:"dbo",name:"StudioCompare_"+UUID().uuidString.replacingOccurrences(of:"-",with:""))
    do {
      _=try await c.execute("BEGIN TRANSACTION; CREATE TABLE \(key.qualified) ([Id] int NOT NULL);")
      let a=try SchemaComparison.decode(await c.execute(SchemaComparison.inventory(keys:[key]),limits:SchemaComparison.limits))
      _=try await c.execute("ALTER TABLE \(key.qualified) ADD [Code] decimal(28,8) NULL;")
      let b=try SchemaComparison.decode(await c.execute(SchemaComparison.inventory(keys:[key]),limits:SchemaComparison.limits))
      #expect(try SchemaComparison.compare(source:a,target:b).first?.status == .changed)
      _=try await c.execute("ROLLBACK TRANSACTION;");await c.disconnect()
    } catch {_=try? await c.execute("IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;");await c.disconnect();throw error}
  }
}
