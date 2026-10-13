import Foundation
import Testing
@testable import SQLServerKit

struct DDLChangeTests {
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
}
