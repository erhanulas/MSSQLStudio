import Foundation
import Testing
@testable import SQLServerKit

struct TableDesignerTests {
  @Test func indexEditingPreservesOptionsStorageOrderAndDisabledState() throws {
    let original=ManagedDefinition(name:"IX_Old",kind:"INDEX",sql:"CREATE UNIQUE NONCLUSTERED INDEX [IX_Old] ON [dbo].[T] ([B] DESC, [A] ASC) INCLUDE ([C]) WHERE ([C]>(0)) WITH (PAD_INDEX = ON, FILLFACTOR = 80) ON [Archive]; ALTER INDEX [IX_Old] ON [dbo].[T] DISABLE;")
    var draft=try TableStructureDraft(original)
    #expect(draft.keys==["B","A"] && draft.descending==["B"] && draft.included==["C"] && draft.unique)
    draft.name="IX_New";draft.unique=false;draft.expression="[C] > 10"
    let sql=try draft.createSQL(table:"[dbo].[T]",columns:["A","B","C"])
    #expect(sql.contains("[B] DESC, [A] ASC") && sql.contains("INCLUDE ([C])"))
    #expect(sql.contains("WHERE [C] > 10") && sql.contains("FILLFACTOR = 80") && sql.contains("ON [Archive]"))
    #expect(sql.contains("ALTER INDEX [IX_New]") && !sql.contains("[IX_Old]") && !sql.contains("UNIQUE"))
    #expect(draft.dropSQL(table:"[dbo].[T]",original:original)=="DROP INDEX [IX_Old] ON [dbo].[T];")
  }
  @Test func addingIncludeAndFilterKeepsSQLClauseOrder() throws {
    var draft=try TableStructureDraft(.init(name:"IX",kind:"INDEX",sql:"CREATE NONCLUSTERED INDEX [IX] ON [dbo].[T] ([A] ASC) WITH (FILLFACTOR = 100) ON [PRIMARY];"))
    draft.included=["B"];draft.expression="[B] IS NOT NULL"
    let sql=try draft.createSQL(table:"[dbo].[T]",columns:["A","B"])
    let source=sql as NSString
    #expect(source.range(of:"INCLUDE").location<source.range(of:"WHERE").location)
    #expect(source.range(of:"WHERE").location<source.range(of:"WITH").location)
    #expect(sql.contains("ON [PRIMARY]"))
    draft.keys=["A","B"]
    #expect(throws:SQLFailure.self) {try draft.createSQL(table:"[dbo].[T]",columns:["A","B"])}
  }
  @Test func relationshipEditingKeepsTrustReplicationAndQuotedColumnNames() throws {
    var draft=try TableStructureDraft(.init(name:"FK_Old",kind:"FK",sql:"ALTER TABLE [dbo].[T] WITH NOCHECK ADD CONSTRAINT [FK_Old] FOREIGN KEY ([A,B], [C]]) REFERENCES [dbo].[Parent] ([Id,One], [Id2]) ON DELETE NO ACTION ON UPDATE CASCADE NOT FOR REPLICATION; ALTER TABLE [dbo].[T] NOCHECK CONSTRAINT [FK_Old];".replacingOccurrences(of:"[C]])",with:"[C]]x])")))
    #expect(draft.keys==["A,B","C]x"] && draft.targetColumns=="[Id,One], [Id2]")
    draft.name="FK_New";draft.deleteAction="CASCADE"
    let sql=try draft.createSQL(table:"[dbo].[T]",columns:draft.keys)
    #expect(sql.contains("WITH NOCHECK") && sql.contains("NOT FOR REPLICATION") && sql.contains("NOCHECK CONSTRAINT [FK_New]"))
    #expect(sql.contains("FOREIGN KEY ([A,B], [C]]x])") && !sql.contains(" ASC"))
    #expect(sql.contains("ON DELETE CASCADE ON UPDATE CASCADE"))
  }
  @Test func checkAndPrimaryKeyPropertiesAreLoadedWithoutChangingOtherOptions() throws {
    var check=try TableStructureDraft(.init(name:"CK",kind:"CHECK",sql:"ALTER TABLE [dbo].[T] WITH NOCHECK ADD CONSTRAINT [CK] CHECK NOT FOR REPLICATION (([A]>(0)) AND ([B]<>N'CHECK'));"))
    #expect(check.expression.contains("N'CHECK'"))
    check.expression="[A] >= 0"
    #expect(try check.createSQL(table:"[dbo].[T]",columns:["A","B"]).contains("CHECK NOT FOR REPLICATION ([A] >= 0)"))
    let pk=try TableStructureDraft(.init(name:"PK_T",kind:"PK",sql:"ALTER TABLE [dbo].[T] ADD CONSTRAINT [PK_T] PRIMARY KEY CLUSTERED ([B] DESC, [A] ASC) WITH (FILLFACTOR = 90) ON [PRIMARY];"))
    #expect(pk.keys==["B","A"] && pk.descending==["B"])
    #expect(try pk.createSQL(table:"[dbo].[T]",columns:["A","B"]).contains("PRIMARY KEY CLUSTERED"))
    #expect(throws:SQLFailure.self) {try TableStructureDraft(.init(name:"TR",kind:"TRIGGER",sql:"CREATE TRIGGER TR ON T AS SELECT 1;"))}
  }
  @Test func columnPrimaryKeyChangesPreserveIndexOptionsAndDisabledReferences() throws {
    let definition=ManagedDefinition(name:"PK_T",kind:"PK",sql:"ALTER TABLE [dbo].[T] ADD CONSTRAINT [PK_T] PRIMARY KEY NONCLUSTERED ([B] DESC, [A] ASC) WITH (FILLFACTOR = 70) ON [Archive]; ALTER INDEX [PK_T] ON [dbo].[T] DISABLE;")
    let original=TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"A",type:"int",nullable:false),.init(id:2,name:"B",type:"int",nullable:false),.init(id:3,name:"C",type:"int",nullable:false)],primaryKey:["B","A"],primaryKeyName:"PK_T",definitions:[definition])
    let sql=try ObjectScripts.tableChanges(original:original,schema:"dbo",name:"T",columns:original.columns,primaryKey:["C","B"])
    #expect(sql.contains("PRIMARY KEY NONCLUSTERED ([C] ASC, [B] DESC)"))
    #expect(sql.contains("FILLFACTOR = 70") && sql.contains("ON [Archive]") && sql.contains("DISABLE;"))
    var draft=try TableStructureDraft(definition);draft.name="PK_New"
    #expect(try draft.createSQL(table:"[dbo].[T]",columns:original.columns.map(\.name)).contains("ALTER INDEX [PK_New]"))
  }
  @Test func dataTypesAreQuotedWhitelistedAndRejectPartialOrInvalidValues() throws {
    var result=Execution();result.results=[Rows(values:[["app]schema","Code"]])]
    let types=try TableDataType.decode(result)
    #expect(types[0].defaultSQL=="[app]]schema].[Code]")
    #expect(try ObjectScripts.validatedType(types[0].defaultSQL,allowedTypes:Set(types.map(\.defaultSQL)))==types[0].defaultSQL)
    #expect(throws:SQLFailure.self) {try ObjectScripts.validatedType("[dbo].[Code]")}
    let injected="[dbo].[Code]; DROP TABLE T;"
    #expect(throws:SQLFailure.self) {try ObjectScripts.validatedType(injected,allowedTypes:[injected])}
    result.partial=true
    #expect(throws:SQLFailure.self) {try TableDataType.decode(result)}
    for type in ["nvarchar(4001)","varchar(8001)","decimal(39,0)","decimal(10,11)"] {
      #expect(throws:SQLFailure.self) {try ObjectScripts.validatedType(type)}
    }
    for type in ["nvarchar(max)","decimal(38,12)","int","geometry"] {#expect(try ObjectScripts.validatedType(type)==type)}
  }
  @Test func sharedTransactionSeparatesWorkFromTransactionScaffolding() {
    let sql=ObjectScripts.transaction("ALTER TABLE [dbo].[T] DROP COLUMN [A];")
    #expect(sql.contains("BEGIN TRANSACTION;\n\nALTER TABLE"))
    #expect(sql.contains("DROP COLUMN [A];\n\n    COMMIT TRANSACTION;"))
    #expect(sql.contains("IF @@TRANCOUNT <> 0") && sql.contains("ROLLBACK TRANSACTION"))
  }
}
