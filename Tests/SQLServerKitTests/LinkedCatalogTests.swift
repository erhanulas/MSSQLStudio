import Testing
@testable import SQLServerKit

struct LinkedCatalogTests {
  func result(_ fields:[String],_ rows:[[String?]]) -> Execution {
    var e=Execution();e.results=[Rows(fields:fields.map {Field($0)},values:rows)];return e
  }
  @Test func literalsIdentifiersAndMissingQualifiersRemainSafe() {
    let r=LinkedCatalog.Relation(server:"L']nk",catalog:"D]b",schema:"s]c",name:"t]x_%",type:"TABLE")
    #expect(r.qualified == "[L']]nk].[D]]b].[s]]c].[t]]x_%]")
    #expect(r.selectSQL.contains(r.qualified))
    #expect(LinkedCatalog.catalogsSQL(server:"L'ink").contains("N'L''ink'"))
    #expect(LinkedCatalog.relationsSQL(server:"L",catalog:"D_%").contains("@fUsePattern=0"))
    #expect(LinkedCatalog.columnsSQL(r).contains("@table_name=N't]x_%'"))
    #expect(LinkedCatalog.testSQL(server:"L'ink").contains("N'L''ink'"))
    let noQualifiers=LinkedCatalog.Relation(server:"L",catalog:nil,schema:nil,name:"T",type:"TABLE")
    #expect(noQualifiers.qualified == "[L]...[T]")
    #expect(LinkedCatalog.columnsSQL(noQualifiers).contains("@table_catalog=NULL"))
  }
  @Test func providerTypesAndCatalogRestrictionsArePreserved() throws {
    let e=result(["table_type","table_name","table_schem","table_cat","remarks"],[
      ["TABLE","T","dbo","Db",nil],["VIEW","V","dbo","Db",nil],
      ["SYSTEM TABLE","S","sys","Db",nil],["SYSTEM VIEW","SV","sys","Db",nil],
      ["SYNONYM","Syn","dbo","Db",nil],["ALIAS","A",nil,"Db",nil],
      ["LOCAL TEMPORARY","Temp","dbo","Db",nil],["CUSTOM","Special",nil,"Db","custom type"],
      ["TABLE","Wrong","dbo","Other",nil],["TABLE","T","dbo","Db",nil]])
    let rows=try LinkedCatalog.relations(e,server:"Remote",catalog:"Db")
    #expect(rows.count == 8)
    #expect(Set(rows.map(\.group)) == Set(["Tables","Views","System Tables","System Views","Synonyms & Aliases","Temporary Tables","Other Objects"]))
    #expect(rows.first(where:{$0.name == "Special"})?.type == "CUSTOM")
    #expect(!rows.contains(where:{$0.name == "Wrong"}))
    #expect(try LinkedCatalog.catalogs(result(["CATALOG_NAME","DESCRIPTION"],[["Db",nil],["Db",nil],[nil,nil],["",nil]])) == ["Db"])
    #expect(throws:SQLFailure.self) {try LinkedCatalog.catalogs(result(["Unexpected"],[["Db"]]))}
    #expect(try LinkedCatalog.catalogs(Execution()).isEmpty)
  }
  @Test func columnsUseExactObjectIdentityAndProviderOrder() throws {
    let r=LinkedCatalog.Relation(server:"L",catalog:"Db",schema:"dbo",name:"T_%",type:"VIEW")
    let e=result(["TABLE_CAT","TABLE_SCHEM","TABLE_NAME","COLUMN_NAME","TYPE_NAME","IS_NULLABLE","ORDINAL_POSITION"],[
      [nil,"dbo","T_%","Second","nvarchar","YES","2"],
      ["Db","dbo","T_%","First","int","NO","1"],
      ["Db","dbo","T_XX","Other","int","NO","1"],
      ["Other","dbo","T_%","WrongCatalog","int","NO","1"],
      ["Db","other","T_%","WrongSchema","int","NO","1"]])
    let columns=try LinkedCatalog.columns(e,relation:r)
    #expect(columns.map(\.name) == ["First","Second"])
    #expect(columns[0].detail == "int · NOT NULL")
    #expect(columns[1].detail == "nvarchar · NULL")
  }
}
