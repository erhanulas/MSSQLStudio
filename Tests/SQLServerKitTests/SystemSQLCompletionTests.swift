import Foundation
import Testing
@testable import SQLServerKit

struct SystemSQLCompletionTests {
  private func analyze(_ sql:String,caret:Int?=nil) throws->SQLIntelligence.Analysis {
    try SQLIntelligence.analyze(source:sql,caret:caret ?? sql.utf16.count,catalog:.init(snapshot:.init(symbols:[])),verified:true)
  }
  @Test func builtInCallsInsertParenthesesAndPutCaretInsideWithoutDuplicatingExistingCalls() throws {
    for word in ["SUM","ISNULL","COALESCE","ROUND","GETDATE","JSON_VALUE","COUNT"] {
      let sql="SELECT "+word
      let result=try analyze(sql)
      let suggestion=try #require(result.suggestions.first {$0.label == word})
      #expect(suggestion.text==word+"()" && suggestion.caretOffset==word.utf16.count+1 && suggestion.kind == .function)
      let existing="SELECT "+word+" (Amount)"
      let same=try #require(try analyze(existing,caret:sql.utf16.count).suggestions.first {$0.label == word})
      #expect(same.text==word && same.caretOffset==nil)
    }
  }
  @Test func bareExpressionsAreNeverConvertedIntoCalls() throws {
    for word in TSQL.bareFunctions {
      let result=try analyze("SELECT "+word)
      let suggestion=try #require(result.suggestions.first {$0.label==word})
      #expect(suggestion.text==word && suggestion.caretOffset==nil)
    }
  }
  @Test func knownSystemRoutinesDoNotBecomeUnknownObjectsAndUnknownSpNamesStillValidate() throws {
    for sql in ["EXEC SP_HELP;","EXEC sys.sp_help N'dbo.T';","EXEC dbo.sp_helptext N'dbo.V';","EXEC sp_executesql N'SELECT 1';"] {
      #expect(try analyze(sql).diagnostics.isEmpty,Comment(rawValue:sql))
    }
    for sql in ["EXEC SP_UNKNOWN_THING;","EXEC other.sp_help;","SELECT * FROM SP_HELP;"] {
      #expect(try analyze(sql).diagnostics.count==1,Comment(rawValue:sql))
    }
    #expect(TSQL.syntaxStyle(try #require(TSQL.lex("SP_HELP").first)) == .procedure)
    #expect(TSQL.syntaxStyle(try #require(TSQL.lex("SUM").first)) == .function)
  }
  @Test func execSuggestionsKeepSystemProceduresUnparenthesizedAndDoNotPolluteTables() throws {
    let suggestion=try #require(try analyze("EXEC SP_HE").suggestions.first {$0.label=="SP_HELP"})
    #expect(suggestion.kind == .procedure && suggestion.text=="SP_HELP" && suggestion.caretOffset==nil)
    #expect(try analyze("SELECT * FROM SP_HE").suggestions.allSatisfy {$0.label != "SP_HELP"})
    #expect(try analyze("SELECT 'SU").suggestions.isEmpty)
  }
  @Test func joinKeywordsNeverBecomeCallsAndTableFunctionsUseRelationContext() throws {
    for word in ["LEFT","RIGHT"] {
      let sql="SELECT * FROM dbo.T "+word
      let suggestion=try #require(try analyze(sql).suggestions.first {$0.label==word})
      #expect(suggestion.text==word && suggestion.kind == .keyword)
    }
    let call=try #require(try analyze("SELECT * FROM OPENJ").suggestions.first {$0.label=="OPENJSON"})
    #expect(call.text=="OPENJSON()" && call.caretOffset==9)
    #expect(try analyze("SELECT * FROM OPENJSON(N'[]');").diagnostics.isEmpty)
    #expect(try analyze("SELECT OPENJ").suggestions.allSatisfy {$0.label != "OPENJSON"})
    #expect(TSQL.syntaxStyle(try #require(TSQL.lex("OPENJSON").first)) == .systemObject)
  }

}
