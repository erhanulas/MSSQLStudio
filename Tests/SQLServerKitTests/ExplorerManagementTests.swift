import Foundation
import Testing
@testable import SQLServerKit

struct ExplorerManagementTests {
  @Test func invocationPreservesTypedInputsOutputsDefaultsAndNeverExecutes() throws {
    let p=[RoutineParameter(id:1,name:"@City",type:"nvarchar(50)"),RoutineParameter(id:2,name:"@Count",type:"int",output:true),RoutineParameter(id:3,name:"@Optional",type:"int")]
    let sql=try RoutineScripts.invocation(qualified:"[dbo].[Proc]]Name]",function:false,parameters:p,arguments:[1:.init(value:"O'Hara'; DROP anything;--",mode:"Value"),2:.init(value:"4",mode:"Value"),3:.init(mode:"DEFAULT")])
    #expect(sql.contains("N'O''Hara''; DROP anything;--'"))
    #expect(sql.contains("@Count = @StudioP2 OUTPUT"))
    #expect(!sql.contains("@Optional ="))
    #expect(sql.contains("@StudioP2 AS [@Count]"))
    #expect(sql.contains("EXEC @StudioReturnValue = [dbo].[Proc]]Name]"))
    #expect(throws:SQLFailure.self) {try RoutineScripts.invocation(qualified:"[p]",function:false,parameters:p,arguments:[2:.init(mode:"DEFAULT")])}
  }
  @Test func functionsUseOrderedPositionalArgumentsAndUnsupportedInputsAreExplicit() throws {
    let p=[RoutineParameter(id:2,name:"@B",type:"int"),RoutineParameter(id:1,name:"@A",type:"int")]
    let scalar=try RoutineScripts.invocation(qualified:"[dbo].[Fn]",function:true,parameters:p,arguments:[1:.init(mode:"DEFAULT"),2:.init(value:"3",mode:"Value")])
    #expect(scalar.contains("[dbo].[Fn](DEFAULT, @StudioP2) AS [Value]"))
    #expect(try RoutineScripts.invocation(qualified:"[dbo].[Fn]",function:true,tableValued:true,parameters:[],arguments:[:]).contains("FROM [dbo].[Fn]()"))
    #expect(throws:SQLFailure.self) {try RoutineScripts.invocation(qualified:"[p]",function:false,parameters:[.init(id:1,name:"@Rows",type:"[dbo].[Rows]",tableType:true)],arguments:[:])}
    #expect(throws:SQLFailure.self) {try RoutineScripts.invocation(qualified:"[p]",function:false,parameters:[.init(id:1,name:"@Bad;",type:"int")],arguments:[:])}
    #expect(throws:SQLFailure.self) {try RoutineScripts.invocation(qualified:"[p]",function:false,parameters:[.init(id:1,name:"@Bytes",type:"varbinary(max)")],arguments:[1:.init(value:"0x0ZZ",mode:"Value")])}
  }
  @Test func triggerCommandsRespectDMLAndDatabaseScopesAndDisabledState() throws {
    var result=Execution();result.results=[Rows(values:[["TR]Name","dbo","1","[dbo].[Table]]Name]","1"]])]
    let dml=try TriggerDefinition.decode(result)
    #expect(dml.disabled)
    #expect(try dml.stateScript(enabled:true)=="ENABLE TRIGGER [dbo].[TR]]Name] ON [dbo].[Table]]Name];")
    #expect(dml.dropScript=="DROP TRIGGER [dbo].[TR]]Name];")
    result.results=[Rows(values:[["DDL]Name","","0","","0"]])]
    let ddl=try TriggerDefinition.decode(result)
    #expect(!ddl.disabled)
    #expect(try ddl.stateScript(enabled:false)=="DISABLE TRIGGER [DDL]]Name] ON DATABASE;")
    #expect(ddl.dropScript=="DROP TRIGGER [DDL]]Name] ON DATABASE;")
    result.partial=true
    #expect(throws:SQLFailure.self) {try TriggerDefinition.decode(result)}
  }
  @Test func scriptsNormalizeOnlyModuleHeaderAfterRenameAndPreserveSettings() throws {
    let original="/* CREATE fake */ CREATE OR ALTER PROCEDURE [dbo].[OldName] @P int AS SELECT N'OldName', @P;"
    let sql=try ExplorerScripts.module(original,verb:"ALTER",qualified:"[dbo].[New]]Name]",ansi:false,quoted:true)
    #expect(sql.contains("SET ANSI_NULLS OFF;"))
    #expect(sql.contains("ALTER PROCEDURE [dbo].[New]]Name] @P"))
    #expect(sql.contains("SELECT N'OldName', @P;"))
    #expect(sql.contains("/* CREATE fake */"))
    #expect(try ExplorerScripts.drop(kind:.procedures,qualified:"[dbo].[P]")=="DROP PROCEDURE [dbo].[P];")
    #expect(try ExplorerScripts.drop(kind:.functions,qualified:"[dbo].[F]")=="DROP FUNCTION [dbo].[F];")
  }
  @Test func synonymTargetsAreQuotedAndStatementsRejected() throws {
    #expect(try ExplorerScripts.synonym(qualified:"[dbo].[Alias]",target:"[Server].[DB].[dbo].[Odd]]Name]")=="CREATE SYNONYM [dbo].[Alias] FOR [Server].[DB].[dbo].[Odd]]Name];")
    #expect(try ExplorerScripts.synonym(qualified:"[s]",target:"dbo.TableName").contains("[dbo].[TableName]"))
    #expect(throws:SQLFailure.self) {try ExplorerScripts.synonym(qualified:"[s]",target:"dbo.T; DROP TABLE dbo.T")}
    #expect(throws:SQLFailure.self) {try ExplorerScripts.synonym(qualified:"[s]",target:"server..dbo.T")}
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func liveRoutineFunctionsSynonymAndTriggerLifecycleRollback() async throws {
    let password=try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let c=ODBCConnection();try await c.connect(ServerProfile(trustCertificate:true),password:password)
    let name="StudioModules_"+UUID().uuidString.replacingOccurrences(of:"-",with:"")
    func q(_ suffix:String)->String {"[dbo]."+SQL.identifier(name+suffix)}
    do {
      _=try await c.execute("BEGIN TRANSACTION; CREATE TABLE \(q("T")) ([Id] int PRIMARY KEY);")
      _=try await c.execute("CREATE PROCEDURE \(q("P")) @City nvarchar(50), @Count int OUTPUT, @Optional int=9 AS BEGIN SET NOCOUNT ON; SET @Count=COALESCE(@Count,0)+1; SELECT @City AS [City],@Optional AS [Optional]; RETURN 7; END;")
      _=try await c.execute("CREATE FUNCTION \(q("F")) (@City nvarchar(50)) RETURNS nvarchar(50) AS BEGIN RETURN UPPER(@City); END;")
      _=try await c.execute("CREATE FUNCTION \(q("TF")) (@Id int) RETURNS TABLE AS RETURN (SELECT @Id AS [Id]);")
      _=try await c.execute("CREATE TRIGGER \(q("TR")) ON \(q("T")) AFTER INSERT AS BEGIN SET NOCOUNT ON; END;")
      let ddl=SQL.identifier(name+"DDL")
      _=try await c.execute("CREATE TRIGGER \(ddl) ON DATABASE FOR CREATE_TABLE AS BEGIN SET NOCOUNT ON; END;")
      func objectID(_ qualified:String) async throws -> Int {
        let raw=try #require(try await c.execute("SELECT OBJECT_ID(\(SQL.literal(qualified)));").results.first?.values.first?.first ?? nil)
        return try #require(Int(raw))
      }
      let parameters=try RoutineScripts.decode(await c.execute(RoutineScripts.parameters(try await objectID(q("P")))))
      #expect(parameters.count==3 && parameters[1].output)
      let invocation=try RoutineScripts.invocation(qualified:q("P"),function:false,parameters:parameters,arguments:[1:.init(value:"O'Hara",mode:"Value"),2:.init(value:"4",mode:"Value"),3:.init(mode:"DEFAULT")])
      let invoked=try await c.execute(invocation)
      #expect(!invoked.partial)
      #expect(invoked.results.first?.values.first == ["O'Hara","9"])
      #expect(invoked.results.last?.values.first == ["7","5"])
      let fp=try RoutineScripts.decode(await c.execute(RoutineScripts.parameters(try await objectID(q("F")))))
      #expect(try await c.execute(RoutineScripts.invocation(qualified:q("F"),function:true,parameters:fp,arguments:[1:.init(value:"native",mode:"Value")])).results.first?.values.first == ["NATIVE"])
      let tfp=try RoutineScripts.decode(await c.execute(RoutineScripts.parameters(try await objectID(q("TF")))))
      #expect(try await c.execute(RoutineScripts.invocation(qualified:q("TF"),function:true,tableValued:true,parameters:tfp,arguments:[1:.init(value:"12",mode:"Value")])).results.first?.values.first == ["12"])
      let triggerID=try await objectID(q("TR"))
      var trigger=try TriggerDefinition.decode(await c.execute(TriggerDefinition.metadata(triggerID)))
      #expect(!trigger.disabled)
      _=try await c.execute(trigger.stateScript(enabled:false))
      trigger=try TriggerDefinition.decode(await c.execute(TriggerDefinition.metadata(triggerID)))
      #expect(trigger.disabled)
      let source=try #require(try await c.execute(Catalog.definition(triggerID)).results.first?.values.first?.first ?? nil)
      _=try await TSQL.run(ExplorerScripts.module(source,verb:"ALTER",qualified:trigger.qualified)+"\nGO\n"+trigger.stateScript(enabled:!trigger.disabled),on:c)
      #expect(try TriggerDefinition.decode(await c.execute(TriggerDefinition.metadata(triggerID))).disabled)
      _=try await c.execute(trigger.stateScript(enabled:true))
      #expect(try !TriggerDefinition.decode(await c.execute(TriggerDefinition.metadata(triggerID))).disabled)
      let ddlRaw=try #require(try await c.execute("SELECT object_id FROM sys.triggers WHERE name=\(SQL.literal(name+"DDL"));").results.first?.values.first?.first ?? nil)
      let dbTrigger=try TriggerDefinition.decode(await c.execute(TriggerDefinition.metadata(try #require(Int(ddlRaw)))))
      #expect(dbTrigger.databaseScope)
      _=try await c.execute(dbTrigger.stateScript(enabled:false))
      _=try await c.execute(dbTrigger.stateScript(enabled:true))
      _=try await c.execute(dbTrigger.dropScript)
      _=try await c.execute(ExplorerScripts.synonym(qualified:q("Alias"),target:q("T")))
      #expect(try await c.execute("SELECT base_object_name FROM sys.synonyms WHERE name=\(SQL.literal(name+"Alias"));").results.first?.values.count==1)
      _=try await c.execute(ExplorerScripts.drop(kind:.synonyms,qualified:q("Alias")))
      let procedureSource=try #require(try await c.execute(Catalog.definition(try await objectID(q("P")))).results.first?.values.first?.first ?? nil)
      _=try await TSQL.run(ExplorerScripts.module(procedureSource,verb:"ALTER",qualified:q("P")),on:c)
      let children=Catalog.rows(try await c.execute(Catalog.children(.triggers,object:try await objectID(q("T")))))
      #expect(children.contains {$0.name==name+"TR" && $0.schema=="dbo" && $0.detail.contains("Enabled")})
      _=try await c.execute("ROLLBACK;")
      #expect(try await c.execute("SELECT OBJECT_ID(\(SQL.literal(q("T"))));").results.first?.values.first?.first.flatMap{$0} == nil)
      await c.disconnect()
    } catch {_=try? await c.execute("IF @@TRANCOUNT>0 ROLLBACK;");await c.disconnect();throw error}
  }
}
