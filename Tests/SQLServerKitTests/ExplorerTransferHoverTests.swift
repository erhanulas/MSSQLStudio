import Foundation
import Testing
@testable import SQLServerKit

struct ExplorerTransferHoverTests {
  @Test func archiveRoundTripMergesFoldersAndPreservesExistingProfilesOnIDCollision() throws {
    let id=UUID(),old=ServerProfile(id:id,name:"Existing",host:"existing.fixture")
    let incoming=ServerProfile(id:id,name:"Imported",host:"import.fixture",visibleDatabases:["Demo"],appearance:.init(environment:.test),definitionIndexDatabases:["Demo":true])
    var org=ExplorerOrganization();let root=try org.create("Team");let child=try org.create("SQL",parent:root);try org.setColor(root,hex:"16804A");try org.assign(id,to:child)
    let archive=ExplorerArchive(profiles:[incoming],organization:org)
    let data=try archive.encoded(),decoded=try ExplorerArchive.decode(data)
    #expect(!String(decoding:data,as:UTF8.self).contains("password"))
    let plan=try decoded.merged(existing:[old],organization:ExplorerOrganization())
    #expect(plan.added.count==1 && plan.added[0].id != old.id && plan.added[0].host==incoming.host)
    #expect(plan.organization.path(try #require(plan.organization.assignments[plan.added[0].id]))=="Team / SQL")
    #expect(plan.organization.color(for:plan.added[0].id)=="16804A")
    let repeated=try decoded.merged(existing:[old]+plan.added,organization:plan.organization)
    #expect(repeated.added.isEmpty && repeated.skipped==1 && repeated.organization==plan.organization)
    #expect(old.name=="Existing" && decoded.profiles[0].definitionIndexDatabases?["Demo"]==true)
    var unsupported=archive;unsupported.version=99
    #expect(throws:SQLFailure.self) {try unsupported.encoded()}
    #expect(throws:SQLFailure.self) {try ExplorerArchive(profiles:[ServerProfile(port:0)],organization:org).encoded()}
    #expect(throws:SQLFailure.self) {try ExplorerArchive.decode(Data(repeating:32,count:2_000_001))}
  }
  @Test func hoverSeparatesScalarReturnTableProjectionAndAmbiguousColumns() throws {
    func execution(_ values:[[String?]])->Execution {var e=Execution();e.results=[Rows(values:values)];return e}
    let scalar=SQLObjectHover.decode(execution([["42","dbo","Price","SQL_SCALAR_FUNCTION","Return Value","decimal(18,2)"]]))
    #expect(scalar?.detail=="Scalar Function → decimal(18,2)")
    let table=SQLObjectHover.decode(execution([["43","dbo","Rows","SQL_INLINE_TABLE_VALUED_FUNCTION","Name","nvarchar(80) NULL"]]))
    #expect(table?.detail=="Table Function → TABLE\nName · nvarchar(80) NULL")
    let col=SQLObjectHover.decode(execution([["7","dbo","T","USER_TABLE","Amount","decimal(28,8) NOT NULL"]]),column:"Amount")
    #expect(col?.title=="dbo.T.Amount" && col?.detail=="decimal(28,8) NOT NULL")
    #expect(SQLObjectHover.decode(execution([["7","dbo","T","USER_TABLE","A","int"],["8","dbo","U","USER_TABLE","A","int"]]),column:"A")==nil)
    for kind in ["USER_TABLE","VIEW"] {
      #expect(SQLObjectHover.decode(execution([["7","dbo","T",kind,"Amount","AmountType (decimal(18,8)) NOT NULL"]]))==nil)
      #expect(SQLObjectHover.decode(execution([["7","dbo","T",kind,"Amount","AmountType (decimal(18,8)) NOT NULL"]]),column:"Amount")?.detail=="AmountType (decimal(18,8)) NOT NULL")
    }
    let objectQuery=try SQLObjectHover.query(targets:[["dbo","T"]])
    #expect(objectQuery.contains("o.type IN ('IF','TF','FT')") && !objectQuery.contains("o.type IN ('U','V'"))
    let sql=try SQLObjectHover.query(targets:[["dbo","T'x"]],column:"A'B")
    #expect(sql.contains("T''x") && sql.contains("A''B") && sql.contains("parameter_id=0") && sql.contains("precision"))
    #expect(throws:SQLFailure.self) {try SQLObjectHover.query(targets:Array(repeating:["T"],count:9))}
    #expect(sql.contains("b.user_type_id=c.system_type_id") && sql.contains("COALESCE(b.name,t.name)") && sql.contains("user_type_id<>t.system_type_id"))
    #expect(Catalog.children(.columns,object:7).contains("bt.user_type_id=c.system_type_id"))
    #expect(Catalog.children(.parameters,object:7).contains("bt.user_type_id=p.system_type_id"))
    #expect(Catalog.children(.columns,object:7).contains("precision"))
  }
  @Test func triggerContextCanOptIntoTableColumnsWithoutChangingOrdinaryHover() throws {
    var execution=Execution()
    execution.results=[Rows(values:[["7","dbo","T","USER_TABLE","ID","int NOT NULL","1"]])]
    #expect(SQLObjectHover.decode(execution) == nil)
    let info=try #require(SQLObjectHover.decode(execution,includeTableColumns:true))
    #expect(info.columns.map(\.name) == ["ID"] && info.detail.contains("int NOT NULL"))
  }
  @Test func tableHoverPreservesEveryReturnColumnInOrdinalOrderAndRejectsPartialMetadata() throws {
    var execution=Execution()
    execution.results=[Rows(values:(1...80).reversed().map { ordinal in
      ["43","dbo","Projection","SQL_TABLE_VALUED_FUNCTION","Column_\(81-ordinal)","AliasType (decimal(28,8)) NOT NULL",String(ordinal)]
    })]
    let info=try #require(SQLObjectHover.decode(execution))
    #expect(info.columns.count==80 && info.columns.map(\.ordinal)==Array(1...80))
    #expect(info.columns.first?.name=="Column_80" && info.columns.last?.name=="Column_1")
    #expect(info.detail.contains("Column_1 · AliasType (decimal(28,8)) NOT NULL") && !info.detail.contains("…"))
    let query=try SQLObjectHover.query(targets:[["dbo","Projection"]])
    #expect(query.contains("c.column_id") && query.contains("ORDER BY 1,7") && !query.contains("TOP(17)"))
    execution.results[0].truncated=true
    #expect(SQLObjectHover.decode(execution)==nil)
    execution.results[0].truncated=false;execution.partial=true
    #expect(SQLObjectHover.decode(execution)==nil)
  }
  @Test func unavailableDefinitionsDoNotWarnButMissingReadableDefinitionsStillDo() throws {
    let finished=DefinitionIndexStatus(count:7,lastFetched:Date(),synchronizedAt:Date(),expected:10,unavailable:3)
    let evicted=DefinitionIndexStatus(count:6,lastFetched:Date(),synchronizedAt:Date(),expected:10,unavailable:3)
    #expect(!finished.incomplete && evicted.incomplete)
    let legacy=ServerAppearance(environment:.live,customLabel:"Old custom")
    let normalized=try legacy.validated()
    #expect(legacy.badge=="Canlı" && normalized.customLabel.isEmpty)
    #expect(ServerAppearance(environment:.custom,customLabel:"Replica").badge=="Replica")
  }
}
