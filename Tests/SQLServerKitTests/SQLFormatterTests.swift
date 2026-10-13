import Foundation
import Testing
@testable import SQLServerKit

struct SQLFormatterTests {
  @Test func complexTSQLRetainsTokensCommentsAndIsIdempotent() {
    let samples = [
      "with c as(select a,b from dbo.t where a>=1 and b between 1 and 9), d as(select * from c) select c.a,case when c.b=1 then N'İ 🦊' else N'END' end as [where] from c left outer join d on c.a=d.a where c.b!=2 order by c.a;",
      "update t set a=1,b=2 from dbo.t t join dbo.u u on t.id=u.id where t.id=1; delete from dbo.t where id=2; insert into dbo.t(a,b) values(1,2);",
      "SELECT dbo.select, [a]]b], \"case\", .25, -.5, 1e-2, @a+=1 FROM dbo.t; -- exact comment\r\nGO 2 -- keep\r\n/* nested /* x */ end */ SELECT N'from\r\nselect';",
      "IF 1=1 BEGIN SELECT CASE WHEN 1=1 THEN 2 ELSE 3 END AS Value; END;",
      "SELECT a FROM dbo.t WHERE EXISTS(SELECT 1 FROM dbo.u WHERE u.id=t.id);"
    ]
    for options in [SQLFormattingOptions(), .init(indentWidth:2,keywordCase:.lower,commaStyle:.leading), .init(keywordCase:.preserve,multilineLists:false,breakConditions:false)] {
      for source in samples {
        let result=TSQL.format(source,options:options)
        if let directory=ProcessInfo.processInfo.environment["MSSQL_FORMAT_OUTPUT_DIRECTORY"], !source.contains("@a+=") {
          let folder=URL(fileURLWithPath:directory)
          try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
          try? result.write(to:folder.appendingPathComponent(UUID().uuidString+".sql"),atomically:true,encoding:.utf8)
        }
        #expect(TSQL.format(result,options:options)==result,"\(result)")
        let original=TSQL.lex(source).filter {$0.kind != .space}
        let changed=TSQL.lex(result).filter {$0.kind != .space}
        #expect(original.count==changed.count)
        #expect(zip(original,changed).allSatisfy {$0.kind == .keyword ? $0.text.uppercased()==$1.text.uppercased() : $0.text==$1.text})
        #expect((try? TSQL.batches(source).count)==(try? TSQL.batches(result).count))
      }
    }
  }
  @Test func contextualKeywordIdentifiersKeepTheirOriginalCase() {
    for options in [SQLFormattingOptions(), .init(keywordCase:.lower)] {
      let source="select 1 as Go, 2 as Try from dbo.Go as Catch"
      let formatted=TSQL.format(source,options:options)
      for name in ["Go","Try","Catch"] { #expect(formatted.contains(name),"\(formatted)") }
      #expect(!SQLFormatter.preservesSQLTokens("SELECT 1 AS Go",formatted:"SELECT 1 AS GO"))
      for name in ["Try","Catch","Go","Apply","Offset","Rows","Only","Output","Partition","Include","Next"] {
        let sql="select "+name+" from dbo.t"
        #expect(TSQL.format(sql,options:options).contains(name))
      }
    }
  }
  @Test func preferencesAffectListsCaseAndIndentWithoutChangingAliases() {
    let source="select a,b from dbo.t AS Alias where a=1 and b=2"
    let upper=TSQL.format(source)
    #expect(upper.contains("SELECT a,\n    b\nFROM dbo.t AS Alias\nWHERE"))
    let lower=TSQL.format(source,options:.init(indentWidth:2,keywordCase:.lower,commaStyle:.leading))
    #expect(lower.contains("select a\n  , b\nfrom dbo.t as Alias\nwhere"))
    #expect(TSQL.format(source,options:.init(multilineLists:false)).contains("SELECT a, b"))
    #expect(TSQL.format(":setvar database Foo\nSELECT 1") == ":setvar database Foo\nSELECT 1")
  }
}
