import Foundation
import Testing
@testable import SQLServerKit

struct ObjectManagementTests {
  @Test func tableChangePlanEscapesNamesPreservesDataAndRejectsGeneratedChanges() throws {
    let original=TableDefinition(schema:"dbo",name:"Odd]Table",columns:[.init(id:1,name:"Id",type:"int",nullable:false,identity:true),.init(id:2,name:"Name",type:"nvarchar(50)",defaultName:"DF_Name",defaultSQL:"(N'initial')")],primaryKey:["Id"],primaryKeyName:"PK_Test")
    var columns=original.columns; columns[1].name="Display]Name"; columns[1].type="nvarchar(100)"; columns[1].defaultSQL="(N'next')"; columns.append(.init(id:-1,name:"NewColumn",type:"int"))
    let sql=try ObjectScripts.tableChanges(original:original,schema:original.schema,name:original.name,columns:columns,primaryKey:["Id"])
    #expect(sql.contains("[dbo].[Odd]]Table]"))
    #expect(sql.contains("DROP CONSTRAINT [DF_Name]"))
    #expect(sql.contains("sp_rename"))
    #expect(sql.contains("ALTER COLUMN [Display]]Name] nvarchar(100)"))
    #expect(sql.contains("ADD [NewColumn] int NULL"))
    #expect(!sql.contains("DROP TABLE"))
    #expect(sql.contains("ROLLBACK TRANSACTION"))
    columns[0].identity=false
    #expect(throws:SQLFailure.self) { try ObjectScripts.tableChanges(original:original,schema:original.schema,name:original.name,columns:columns,primaryKey:["Id"]) }
    #expect(throws:SQLFailure.self) { try ObjectScripts.validatedType("int); DROP TABLE anything;--") }
  }
  @Test func moduleModesKeepBodyAndNeverExecute() throws {
    let source="-- CREATE fake\nALTER VIEW [dbo].[v] AS SELECT N'ALTER VIEW' AS [value];"
    #expect(try ObjectScripts.module(source,verb:"CREATE").hasPrefix("-- CREATE fake\nCREATE VIEW"))
    #expect(try ObjectScripts.module(source,verb:"CREATE OR ALTER").contains("CREATE OR ALTER VIEW"))
    #expect(try ObjectScripts.rename(qualified:"[dbo].[v]",name:"x'y]").contains("N'x''y]'"))
    #expect(try ObjectScripts.foreignKey(table:"[dbo].[t]",name:"FK]x",columns:["A","B"],referencedSchema:"dbo",referencedTable:"Parent",referencedColumns:["Id","Code"]).contains("FOREIGN KEY ([A], [B])"))
  }
  @Test func dataChangesUseOriginalValuesNullsAndRowCountGuard() throws {
    let table=TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int",nullable:false),.init(id:2,name:"Text",type:"nvarchar(100)")],primaryKey:["Id"])
    let row=DataEditRow(original:["1",nil],values:["1","O'Hara"])
    let sql=try DataEditScripts.changes(table:table,rows:[row])
    #expect(sql.contains("N'O''Hara'")); #expect(sql.contains("[Text] IS NULL")); #expect(sql.contains("@@ROWCOUNT <> 1"))
    var changedKey=row; changedKey.values[0]="2"
    #expect(throws:SQLFailure.self) { try DataEditScripts.changes(table:table,rows:[changedKey]) }
    var noKey=table; noKey.primaryKey=[]
    #expect(throws:SQLFailure.self) { try DataEditScripts.changes(table:noKey,rows:[row]) }
    let insert=DataEditRow(original:nil,values:["2",nil],touched:[0])
    #expect(try DataEditScripts.changes(table:table,rows:[insert]).contains("INSERT INTO [dbo].[T] ([Id])"))
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func liveStandardTableMetadataAndCreateRoundtripRollback() async throws {
    let password=try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let c=ODBCConnection(); try await c.connect(ServerProfile(trustCertificate:true),password:password)
    let name="StudioObjects_"+UUID().uuidString.replacingOccurrences(of:"-",with:"")
    let q="[dbo]."+SQL.identifier(name), copy="[dbo]."+SQL.identifier(name+"Copy")
    do {
      _=try await c.execute("BEGIN TRANSACTION; CREATE TABLE \(q) ([Id] int IDENTITY(1,1) NOT NULL CONSTRAINT \(SQL.identifier("PK_"+name)) PRIMARY KEY, [ParentId] int NULL, [Name] nvarchar(80) COLLATE Latin1_General_100_CI_AS NOT NULL CONSTRAINT \(SQL.identifier("DF_"+name)) DEFAULT N'initial', [Active] bit NOT NULL DEFAULT 1, [Version] rowversion, [Twice] AS ([Id]*2) PERSISTED, CONSTRAINT \(SQL.identifier("CK_"+name)) CHECK ([Id]>0), CONSTRAINT \(SQL.identifier("FK_"+name)) FOREIGN KEY ([ParentId]) REFERENCES \(q)([Id])); CREATE NONCLUSTERED INDEX \(SQL.identifier("IX_"+name)) ON \(q)([Name] DESC) INCLUDE ([Active]) WHERE [Active]=1;")
      _=try await c.execute("CREATE TRIGGER [dbo].\(SQL.identifier("TR_"+name)) ON \(q) AFTER UPDATE AS BEGIN SET NOCOUNT ON; END;")
      let idValue=try #require(try await c.execute("SELECT OBJECT_ID(\(SQL.literal(q)));").results.first?.values.first?.first ?? nil)
      let id=try #require(Int(idValue))
      var table=try ObjectMetadata.decode(await c.execute(ObjectMetadata.table(id)),schema:"dbo",name:name)
      #expect(table.columns.count == 6); #expect(table.primaryKey == ["Id"])
      #expect(Set(table.definitions.map(\.kind)) == Set(["PK","INDEX","FK","CHECK","TRIGGER"]))
      let original=try table.createScript(); #expect(original.contains("DESC")); #expect(original.contains("PERSISTED"))
      for i in table.columns.indices where !table.columns[i].defaultName.isEmpty { table.columns[i].defaultName += "Copy" }
      var script=try table.createScript().replacingOccurrences(of:q,with:copy)
      for d in table.definitions { script=script.replacingOccurrences(of:SQL.identifier(d.name),with:SQL.identifier(d.name+"Copy")) }
      _=try await TSQL.run(script,on:c)
      _=try await c.execute("INSERT INTO \(copy)([Name]) VALUES(N'test');")
      let data=try await c.execute("SELECT [Name],[Active],[Twice] FROM \(copy);")
      #expect(data.results.first?.values.first == ["test","1","2"])
      let view="[dbo]."+SQL.identifier(name+"View")
      let definition="CREATE VIEW \(view) AS SELECT [Id],[Name] FROM \(copy);"
      _=try await c.execute(definition)
      let alter=try ObjectScripts.module(definition,verb:"ALTER").replacingOccurrences(of:"SELECT [Id],[Name]",with:"SELECT [Id],[Name] AS [DisplayName]")
      _=try await c.execute(alter)
      #expect(try await c.execute("SELECT [DisplayName] FROM \(view);").results.first?.values.first == ["test"])
      _=try await c.execute(ObjectScripts.drop(qualified:view,view:true))
      _=try await c.execute(ObjectScripts.module(definition,verb:"CREATE OR ALTER"))
      _=try await c.execute(ObjectScripts.rename(qualified:view,name:name+"RenamedView"))
      #expect(try await c.execute("SELECT [Name] FROM [dbo].\(SQL.identifier(name+"RenamedView"));").results.first?.values.first == ["test"])
      _=try await c.execute("ROLLBACK;")
      #expect(try await c.execute("SELECT OBJECT_ID(\(SQL.literal(q)));").results.first?.values.first?.first.flatMap{$0} == nil)
      await c.disconnect()
    } catch { _=try? await c.execute("IF @@TRANCOUNT>0 ROLLBACK;"); await c.disconnect(); throw error }
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func liveDataEditsDetectConflictAndRollback() async throws {
    let password=try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let c=ODBCConnection(); try await c.connect(ServerProfile(trustCertificate:true),password:password)
    let table=TableDefinition(schema:"dbo",name:"#StudioEdit",columns:[.init(id:1,name:"Id",type:"int",nullable:false),.init(id:2,name:"Text",type:"nvarchar(100)"),.init(id:3,name:"Version",type:"timestamp",nullable:false)],primaryKey:["Id"])
    do {
      _=try await c.execute("CREATE TABLE #StudioEdit ([Id] int PRIMARY KEY,[Text] nvarchar(100) NULL,[Version] rowversion); INSERT INTO #StudioEdit([Id],[Text]) VALUES(1,N'old');")
      let old=try #require(try await c.execute("SELECT [Id],[Text],[Version] FROM #StudioEdit;").results.first?.values.first)
      var row=DataEditRow(original:old,values:old); row.values[1]="O'Hara"
      let script=try DataEditScripts.changes(table:table,rows:[row])
      _=try await c.execute(script.replacingOccurrences(of:"COMMIT TRANSACTION;",with:"ROLLBACK TRANSACTION;"))
      #expect(try await c.execute("SELECT [Text] FROM #StudioEdit;").results.first?.values.first?.first == "old")
      _=try await c.execute("UPDATE #StudioEdit SET [Text]=N'concurrent' WHERE [Id]=1;")
      do { let failure=try await c.execute(script); #expect(failure.partial); #expect(failure.messages.contains { $0.contains("Satır değişmiş") }) }
      catch { #expect(error.localizedDescription.contains("Satır değişmiş")) }
      #expect(try await c.execute("SELECT [Text] FROM #StudioEdit;").results.first?.values.first?.first == "concurrent")
      let fresh=try #require(try await c.execute("SELECT [Id],[Text],[Version] FROM #StudioEdit;").results.first?.values.first)
      let deletion=DataEditRow(original:fresh,values:fresh,deleted:true)
      _=try await c.execute(DataEditScripts.changes(table:table,rows:[deletion]).replacingOccurrences(of:"COMMIT TRANSACTION;",with:"ROLLBACK TRANSACTION;"))
      let insertion=DataEditRow(original:nil,values:["2",nil,nil],touched:[0,1])
      _=try await c.execute(DataEditScripts.changes(table:table,rows:[insertion]).replacingOccurrences(of:"COMMIT TRANSACTION;",with:"ROLLBACK TRANSACTION;"))
      #expect(try await c.execute("SELECT COUNT(*) FROM #StudioEdit;").results.first?.values.first?.first == "1")
      var columns=table.columns; columns.append(.init(id:-1,name:"Extra",type:"int"))
      let ddl=try ObjectScripts.tableChanges(original:table,schema:"dbo",name:"#StudioEdit",columns:columns,primaryKey:["Id"])
      _=try await c.execute(ddl.replacingOccurrences(of:"COMMIT TRANSACTION;",with:"ROLLBACK TRANSACTION;"))
      #expect(try await c.execute("SELECT COL_LENGTH('tempdb..#StudioEdit','Extra');").results.first?.values.first?.first.flatMap{$0} == nil)
      await c.disconnect()
    } catch { _=try? await c.execute("IF @@TRANCOUNT>0 ROLLBACK;"); await c.disconnect(); throw error }
  }

}
