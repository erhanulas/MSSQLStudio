import Foundation
import Testing
@testable import SQLServerKit

struct DDLChangeTests {
  @Test func triggerCreationRefreshesItsParentWithoutExecutingBodyDDL() {
    let changes=ModuleEditing.changes("CREATE OR ALTER TRIGGER dbo.tr ON dbo.Customers AFTER INSERT AS BEGIN UPDATE dbo.Other SET ID=1; END")
    #expect(changes.map(\.name) == ["tr","Customers"])
    #expect(changes.map(\.folder) == [.triggers,.tables])
  }
  @Test func identifiersKeepSchemaDatabaseAndEscapedDotsAsSeparateParts() {
    let changes=ModuleEditing.changes("USE [Target DB]; CREATE TABLE [sales.area].[News]]Log] (ID int); ALTER TABLE [Other DB]..[News] ADD Title nvarchar(100);")
    #expect(changes.count==2)
    #expect(changes.first?.database=="Target DB" && changes.first?.schema=="sales.area" && changes.first?.name=="News]Log")
    #expect(changes.last?.database=="Other DB" && changes.last?.schema==nil && changes.last?.name=="News")
  }
  @Test func dropsRefreshEveryStaticNameAndIndexesRefreshTheirOwner() {
    let changes=ModuleEditing.changes("DROP TABLE IF EXISTS dbo.A, [audit].[B]; CREATE UNIQUE INDEX IX_News ON dbo.News(ID); DROP INDEX IX_News ON dbo.News;")
    #expect(changes.map(\.name)==["A","B","News"])
    #expect(changes.allSatisfy {$0.folder == .tables})
  }
  @Test func moduleBodyAndDynamicStringsAreNotExecutedDDLChanges() {
    let changes=ModuleEditing.changes("CREATE OR ALTER PROC dbo.p AS BEGIN CREATE TABLE dbo.Future(ID int); END;\nGO\nEXEC(N'CREATE TABLE dbo.Dynamic(ID int)');\nCREATE TABLE dbo.Actual(ID int);")
    #expect(changes.map(\.name)==["p","Actual"])
    #expect(changes.first?.folder == .procedures)
    #expect(ModuleEditing.changes("-- DROP TABLE dbo.Fake\nSELECT N'ALTER VIEW dbo.Fake';").isEmpty)
  }
  @Test func triggerScopeAndCrossServerNamesStayExplicit() {
    let trigger=ModuleEditing.changes("CREATE TRIGGER AuditDDL ON DATABASE FOR CREATE_TABLE AS SELECT 1;").first
    #expect(trigger?.databaseTrigger == true && trigger?.schema=="" && trigger?.type=="TRD")
    #expect(ModuleEditing.changes("DROP TABLE Server.Db.dbo.Table1;").isEmpty)
    let change=ModuleEditing.changes("ALTER VIEW dbo.V AS SELECT 1;").first?.inDatabase("Source")
    #expect(change?.database=="Source" && change?.name=="V")
  }
  @Test func indexVariantsAndEveryDropOwnerStayWithinTheirStatement() {
    let sql="""
    CREATE CLUSTERED COLUMNSTORE INDEX CCI ON dbo.A;
    CREATE PRIMARY XML INDEX PX ON dbo.B(XmlValue);
    CREATE SELECTIVE XML INDEX SX ON dbo.C(XmlValue) FOR (p='/a' AS XQUERY 'xs:string');
    CREATE SPATIAL INDEX SI ON dbo.D(Location);
    CREATE FULLTEXT INDEX ON dbo.E(TextValue) KEY INDEX PK_E;
    DROP INDEX IF EXISTS IX ON dbo.F WITH(MAXDOP=2), IY ON [OtherDb].[audit].[G];
    DROP INDEX dbo.H.IX, [I].[IY];
    ALTER INDEX ALL ON dbo.J REBUILD;
    CREATE STATISTICS ST ON dbo.K(ID);
    DROP STATISTICS dbo.L.ST, audit.M.ST;
    """
    let changes=ModuleEditing.changes(sql)
    #expect(changes.map(\.name)==["A","B","C","D","E","F","G","H","I","J","K","L","M"])
    #expect(changes.first {$0.name=="G"}?.database=="OtherDb")
    #expect(ModuleEditing.changes("DROP INDEX Unknown; SELECT * FROM dbo.Wrong ON 1=1;").isEmpty)
    #expect(ModuleEditing.changes("DROP INDEX Unknown\nCREATE INDEX IX ON dbo.Actual(ID);").map(\.name)==["Actual"])
    #expect(ModuleEditing.changes("CREATE INDEX IX ON Server.Db.dbo.Remote(ID);").isEmpty)
  }
  @Test func supportedObjectsAndSubobjectsUseTheSameTargets() {
    let sql="""
    ALTER TABLE dbo.A ADD CONSTRAINT CK_A CHECK(ID>0);
    CREATE VIEW dbo.V AS SELECT 1 AS ID;
    GO
    CREATE PROC dbo.P AS SELECT 1;
    GO
    CREATE FUNCTION dbo.F() RETURNS int AS BEGIN RETURN 1; END;
    GO
    CREATE SYNONYM dbo.S FOR dbo.A;
    DISABLE TRIGGER dbo.TR ON dbo.A;
    ENABLE TRIGGER dbo.TR ON dbo.A;
    TRUNCATE TABLE dbo.Z;
    """
    let changes=ModuleEditing.changes(sql)
    #expect(changes.map(\.name)==["A","V","P","F","S","TR","Z"])
    #expect(changes.map(\.folder)==[.tables,.views,.procedures,.functions,.synonyms,.triggers,.tables])
    #expect(ModuleEditing.changes("CREATE TRIGGER ServerTrigger ON ALL SERVER FOR CREATE_DATABASE AS SELECT 1;").isEmpty)
  }

  @Test func securityObjectsHaveExplicitScopesRatherThanTriggerFallback() {
    let changes=ModuleEditing.changes("CREATE USER [Domain\\User] FOR LOGIN [Domain\\User]; ALTER LOGIN [AppLogin] DISABLE; DROP SERVER ROLE [Ops];")
    #expect(changes.map(\.folder)==[.users,.logins,.roles])
    #expect(changes.map(\.type)==["USER","LOGIN","SERVER_ROLE"])
    #expect(changes.allSatisfy {$0.schema=="" && !$0.databaseTrigger})
    let all=ModuleEditing.changes("DISABLE TRIGGER ALL ON dbo.T;")
    #expect(all.map(\.name)==["T"])
    let database=ModuleEditing.changes("DISABLE TRIGGER A,B ON DATABASE;")
    #expect(database.count==2 && database.allSatisfy(\.databaseTrigger))
  }

}
