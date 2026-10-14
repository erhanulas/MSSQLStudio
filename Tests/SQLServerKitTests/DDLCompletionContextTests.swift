import Foundation
import Testing
@testable import SQLServerKit

@Suite struct DDLCompletionContextTests {
  let symbols=[
    CatalogSymbol(schema:"dbo",name:"DemoTable",columns:["Code"]),
    CatalogSymbol(schema:"dbo",name:"DemoView",columns:["Code"],kind:"VIEW"),
    CatalogSymbol(schema:"dbo",name:"DemoScalar",columns:[],kind:"SQL_SCALAR_FUNCTION"),
    CatalogSymbol(schema:"dbo",name:"DemoCLRScalar",columns:[],kind:"CLR_SCALAR_FUNCTION"),
    CatalogSymbol(schema:"dbo",name:"DemoRows",columns:["Code"],kind:"SQL_INLINE_TABLE_VALUED_FUNCTION"),
    CatalogSymbol(schema:"dbo",name:"DemoMultiRows",columns:["Code"],kind:"SQL_TABLE_VALUED_FUNCTION"),
    CatalogSymbol(schema:"dbo",name:"DemoCLRRows",columns:["Code"],kind:"CLR_TABLE_VALUED_FUNCTION"),
    CatalogSymbol(schema:"dbo",name:"DemoProcedure",columns:[],kind:"SQL_STORED_PROCEDURE"),
    CatalogSymbol(schema:"report",name:"DemoOtherScalar",columns:[],kind:"SQL_SCALAR_FUNCTION")
  ]
  private func analyze(_ marked:String,symbols:[CatalogSymbol]?=nil,schema:Bool=true,brackets:Bool=true)throws->SQLIntelligence.Analysis {
    let caret=(marked as NSString).range(of:"§").location
    let source=marked.replacingOccurrences(of:"§",with:"")
    return try SQLIntelligence.analyze(source:source,caret:caret==NSNotFound ? source.utf16.count:caret,catalog:.init(snapshot:.init(symbols:symbols ?? self.symbols)),verified:true,automaticAliases:true,automaticNoLock:true,includeSchema:schema,quoteIdentifiers:brackets)
  }
  @Test func selectSourcesIncludeTablesViewsAndTableFunctionsOnly() throws {
    for source in ["SELECT * FROM Demo","SELECT * FROM dbo.DemoTable t JOIN Demo","SELECT * FROM dbo.DemoTable t CROSS APPLY Demo","SELECT * FROM dbo.DemoTable, Demo"] {
      let items=try analyze(source).suggestions
      #expect(items.count==5)
      #expect(Set(items.map(\.kind))==[.table,.view,.function])
      #expect(items.filter {$0.kind == .function}.allSatisfy {$0.text.hasSuffix("()") && !$0.text.contains(" AS ") && !$0.text.contains("NOLOCK")})
    }
    let items=try analyze("SELECT * FROM Demo").suggestions
    #expect(items.first {$0.kind == .table}?.text=="[dbo].[DemoTable] AS DT WITH(NOLOCK)")
    #expect(items.first {$0.kind == .view}?.text=="[dbo].[DemoView] AS DV WITH(NOLOCK)")
    #expect(try analyze("UPDATE Demo").suggestions.map(\.kind).allSatisfy {$0 == .table || $0 == .view})
  }
  @Test func expressionCompletionUsesScalarFunctionsAndRespectsSQLClauses() throws {
    for source in ["SELECT Demo", "SELECT DISTINCT Demo", "SELECT TOP(10) Demo", "SELECT TOP 10 Demo", "SELECT 1, Demo", "SELECT COALESCE(Demo", "SELECT * FROM DemoTable t WHERE t.Code=Demo", "SELECT * FROM DemoRows(Demo"] {
      let items=try analyze(source).suggestions.filter {$0.kind == .function && !$0.detail.isEmpty}
      #expect(items.count==3,"\(source)")
      #expect(items.allSatisfy {$0.text.contains("Scalar") && $0.text.hasSuffix("()")})
    }
    #expect(try analyze("SELECT dbo.Demo").suggestions.map(\.text)==["[DemoCLRScalar]()","[DemoScalar]()"])
    #expect(try analyze("SELECT report.Demo").suggestions.map(\.text)==["[DemoOtherScalar]()"])
    #expect(try analyze("SELECT dbo.emoScalar").suggestions.map(\.text)==["[DemoScalar]()"])
  }
  @Test func executeIncludesProceduresAndExecutableScalarFunctionsButNotTableFunctions() throws {
    for source in ["EXEC Demo","EXECUTE Demo","EXEC @status = Demo"] {
      let items=try analyze(source).suggestions
      #expect(items.count==4)
      #expect(items.filter {$0.kind == .procedure}.count==1)
      #expect(items.allSatisfy {!$0.text.contains("Rows") && !$0.text.contains("()") && !$0.text.contains("NOLOCK") && !$0.text.contains(" AS ")})
    }
  }
  @Test func allUserFunctionsKeepSchemaWhenSchemaPreferenceIsDisabled() throws {
    for brackets in [true,false] {
      for (source,name) in [("SELECT DemoSc","DemoScalar"),("SELECT DemoCLRSc","DemoCLRScalar"),("SELECT * FROM DemoRo","DemoRows"),("SELECT * FROM DemoMultiRo","DemoMultiRows"),("SELECT * FROM DemoCLRRo","DemoCLRRows"),("EXEC DemoSc","DemoScalar")] {
        let result=try #require(analyze(source,schema:false,brackets:brackets).suggestions.first {$0.kind == .function})
        let expected=brackets ? "[dbo].[\(name)]":"dbo.\(name)"
        #expect(result.text==expected+(source.hasPrefix("EXEC") ? "":"()"))
      }
      let table=try #require(analyze("SELECT * FROM DemoTa",schema:false,brackets:brackets).suggestions.first {$0.kind == .table})
      #expect(!table.text.contains("dbo"))
      let view=try #require(analyze("SELECT * FROM DemoVi",schema:false,brackets:brackets).suggestions.first {$0.kind == .view})
      #expect(!view.text.contains("dbo"))
      let typed=try #require(analyze("SELECT * FROM dbo.DemoRo",schema:false,brackets:brackets).suggestions.first)
      #expect(typed.text==(brackets ? "[DemoRows]()":"DemoRows()"))
    }
  }
  @Test func callsKeepExistingParenthesesAndSchemaEscapingPreferences() throws {
    let fresh=try #require(analyze("SELECT DemoScalar",schema:false,brackets:false).suggestions.first {$0.kind == .function})
    #expect(fresh.text=="dbo.DemoScalar()" && fresh.caretOffset==fresh.text.utf16.count-1)
    let existing=try #require(analyze("SELECT dbo.DemoSc§(42)").suggestions.first)
    #expect(existing.text=="[DemoScalar]" && existing.caretOffset==nil)
    let rows=try #require(analyze("SELECT * FROM dbo.DemoRo§(@value) r").suggestions.first)
    #expect(rows.text=="[DemoRows]" && rows.caretOffset==nil)
    let special=[CatalogSymbol(schema:"sales area",name:"Rate]Value",columns:[],kind:"SQL_SCALAR_FUNCTION")]
    #expect(try analyze("SELECT [sales area].Rate",symbols:special,schema:false,brackets:false).suggestions.first?.text=="[Rate]]Value]()")
  }
  @Test func aliasesLiteralsModuleHeadersAndRemoteNamesNeverGetLocalFunctionSuggestions() throws {
    for source in ["SELECT 1 AS Demo","SELECT N'x' Demo", "SELECT (1) Demo", "DECLARE @x dbo.Demo", "CREATE FUNCTION dbo.Demo", "CREATE PROC dbo.p WITH EXECUTE ", "SELECT 'Demo", "-- SELECT Demo", "SELECT OtherDB.dbo.Demo", "SELECT * FROM OtherDB.dbo.Demo"] {
      #expect(try analyze(source).suggestions.allSatisfy {$0.kind != .function || $0.detail.isEmpty},"\(source)")
    }
    let alias=try analyze("SELECT dbo.Co§ FROM dbo.DemoTable dbo").suggestions
    #expect(alias.map(\.text)==["[Code]"])
    #expect(try analyze("SELECT f.Co§ FROM dbo.DemoRows(1) f").suggestions.map(\.text)==["[Code]"])
  }
  @Test func wrongObjectKindsCannotConsumeTheCompletionLimit() throws {
    let crowd=(0..<150).map {CatalogSymbol(schema:"dbo",name:String(format:"Demo_%03d",$0),columns:[],kind:"SQL_STORED_PROCEDURE")}
    #expect(try analyze("SELECT * FROM Demo",symbols:crowd+[symbols[0]]).suggestions.map(\.kind)==[.table])
    let tvfs=(0..<150).map {CatalogSymbol(schema:"dbo",name:String(format:"Demo_%03d",$0),columns:[],kind:"SQL_TABLE_VALUED_FUNCTION")}
    #expect(try analyze("EXEC Demo",symbols:tvfs+[symbols[7]]).suggestions.map(\.kind)==[.procedure])
    let columns=(0..<200).map {"Demo\($0)"}
    let busy=[CatalogSymbol(schema:"dbo",name:"Wide",columns:columns),symbols[2]]
    let result=try analyze("SELECT Demo§ FROM dbo.Wide w",symbols:busy)
    #expect(result.suggestions.count==100 && result.suggestions.contains {$0.text=="[dbo].[DemoScalar]()"})
  }
  @Test func objectPositionsAreAutomaticAtEmptyAndSingleCharacterPrefixes() throws {
    #expect(try analyze("SELECT * FROM ").objectCompletion)
    #expect(try analyze("SELECT * FROM D").objectCompletion)
    #expect(try analyze("SELECT dbo.D").objectCompletion)
    #expect(try analyze("EXEC ").procedureCompletion)
    #expect(try !analyze("SELECT ").objectCompletion)
    #expect(try !analyze("SELECT 'D").objectCompletion)
  }
}
