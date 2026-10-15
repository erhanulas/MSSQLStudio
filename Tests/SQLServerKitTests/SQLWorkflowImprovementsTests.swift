import Foundation
import Testing
@testable import SQLServerKit

struct SQLWorkflowImprovementsTests {
  private func analyze(_ marked:String,columns:[String]=["Id","STOK_KODU","Name"]) throws -> SQLIntelligence.Analysis {
    let caret=(marked as NSString).range(of:"§").location
    let source=marked.replacingOccurrences(of:"§",with:"")
    return try SQLIntelligence.analyze(source:source,caret:caret,catalog:.init(snapshot:.init(symbols:[.init(schema:"dbo",name:"T",columns:columns)])),verified:true,quoteIdentifiers:false)
  }
  @Test func wildcardExpandsOnlyProjectionAndPreservesQualifiersAndOrder() throws {
    for marked in ["SELECT *§ FROM T", "SELECT DISTINCT *§ FROM T", "SELECT TOP (100) *§ FROM T"] {
      let result=try analyze(marked)
      let item=try #require(result.suggestions.first)
      #expect(item.text=="Id,\n    STOK_KODU,\n    Name" && result.objectCompletion)
      let source=marked.replacingOccurrences(of:"§",with:"") as NSString
      #expect(source.substring(with:result.replacement)=="*")
    }
    let qualified=try analyze("SELECT t.*§ FROM T AS t")
    #expect(qualified.suggestions.first?.text=="Id, t.STOK_KODU, t.Name")
    for marked in ["SELECT COUNT(*§) FROM T", "SELECT 2 *§ 3 FROM T", "SELECT * FROM T WHERE Id *§ 2 > 0", "SELECT '*§' FROM T"] {
      #expect(try analyze(marked).suggestions.allSatisfy {$0.label != "Tüm kolonları listele"})
    }
    #expect(try analyze("SELECT *§ FROM T",columns:[]).suggestions.isEmpty)
  }
  @Test func noArgumentBuiltinsFinishOutsideParenthesesAndRequiredArgumentsStayInside() throws {
    for word in TSQL.noArgumentFunctions.intersection(Set(TSQL.functions)) {
      let sql="SELECT "+word
      let result=try SQLIntelligence.analyze(source:sql,caret:sql.utf16.count,catalog:nil,verified:false)
      let item=try #require(result.suggestions.first {$0.label==word})
      #expect(item.text==word+"()" && item.caretOffset==item.text.utf16.count)
    }
    let result=try SQLIntelligence.analyze(source:"SELECT SUM",caret:10,catalog:nil,verified:false)
    #expect(result.suggestions.first {$0.label=="SUM"}?.caretOffset==4)
  }
  @Test func selectScriptsUseOrdinalColumnsAndEscapedIdentifiers() throws {
    let item=CatalogItem(name:"T]Name",schema:"dbo")
    let columns=[CatalogItem(id:2,name:"N]ame"),CatalogItem(id:1,name:"Id")]
    #expect(try Catalog.selectScript(item:item,columns:columns,top:100)=="SELECT TOP (100)\n    [Id],\n    [N]]ame]\nFROM [dbo].[T]]Name];")
    #expect(try Catalog.selectScript(item:item,columns:columns).hasPrefix("SELECT\n"))
    #expect(throws:SQLFailure.self) {try Catalog.selectScript(item:item,columns:[])}
  }
  @Test func readableUpdatesKeepSafetyGuardsAndTypedKeylessMatching() throws {
    let columns:[TableColumn]=[.init(id:1,name:"Id",type:"int"),.init(id:2,name:"Name",type:"nvarchar(30)"),.init(id:3,name:"Enabled",type:"bit")]
    let row=DataEditRow(original:["1","A","0"],values:["2","O'Brien","true"])
    let script=try DataEditScripts.changes(table:.init(schema:"dbo",name:"T",columns:columns,primaryKey:["Id"]),rows:[row],expectedObjectID:42,rowMatching:.primaryKeyOrOriginalValues)
    #expect(script.contains("UPDATE [dbo].[T] SET [Id] = 2, [Name] = N'O''Brien', [Enabled] = 1 WHERE [Id] = 1;"))
    #expect(script.contains("OBJECT_ID") && script.contains("@@ROWCOUNT <> 1") && script.contains("ROLLBACK") && script.contains("@@TRANCOUNT"))
    let keyless=try DataEditScripts.changes(table:.init(schema:"dbo",name:"T",columns:columns),rows:[row],rowMatching:.primaryKeyOrOriginalValues)
    #expect(keyless.contains("COUNT_BIG(*)") && keyless.contains("CONVERT(varbinary(max),[Name])"))
    #expect(throws:SQLFailure.self) {try DataEditScripts.changes(table:.init(schema:"dbo",name:"T",columns:columns,primaryKey:["Id"]),rows:[.init(original:["1","A","0"],values:["1;DELETE T","B","1"])],rowMatching:.primaryKeyOrOriginalValues)}
  }
  @Test func jobSaveChecksVersionAndReadsRenamedJobByStableID() async throws {
    let id=UUID().uuidString
    var job=SQLAgent.Job(id:id,name:"Before",enabled:true,description:"",owner:"sa",state:"Idle",modified:"2026-10-15T12:00:00")
    job.version=3
    let fixture=AgentSaveFixture(id:id)
    let result=try await SQLAgent.saveProperties(statements:[SQLAgent.update(job,name:"After",description:"",enabled:true)],job:job) {try await fixture.fetch($0)}
    let requests=await fixture.requests
    #expect(requests.count==2 && requests[0].contains("version_number=3") && requests[0].contains("ROLLBACK"))
    #expect(requests[1].contains(id) && !requests[1].contains("j.name=N'Before'"))
    #expect(result.0.name=="After")
    #expect(SQLAgent.displayDate("2026-10-15T12:34:56.123")=="15.10.2026 12:34:56")
    #expect(SQLAgent.displayDate("")=="—")
    let failed=AgentSaveFixture(id:id,partial:true)
    await #expect(throws:SQLFailure.self) {try await SQLAgent.saveProperties(statements:[SQLAgent.update(job,name:"After",description:"",enabled:true)],job:job) {try await failed.fetch($0)}}
    #expect(await failed.requests.count==1)
    let baseline=job,readFailed=AgentSaveFixture(id:id,failRead:true)
    await #expect(throws:SQLFailure.self) {try await SQLAgent.saveProperties(statements:[SQLAgent.update(baseline,name:"After",description:"",enabled:true)],job:baseline) {try await readFailed.fetch($0)}}
    #expect(await readFailed.requests.count==2)
    let cancelled=AgentSaveFixture(id:id)
    let task=Task {
      withUnsafeCurrentTask {$0?.cancel()}
      return try await SQLAgent.saveProperties(statements:[SQLAgent.update(baseline,name:"After",description:"",enabled:true)],job:baseline) {try await cancelled.fetch($0)}
    }
    await #expect(throws:CancellationError.self) {try await task.value}
    #expect(await cancelled.requests.isEmpty)
  }
}
private actor AgentSaveFixture {
  let id:String
  let partial:Bool
  let failRead:Bool
  var requests:[String]=[]
  init(id:String,partial:Bool=false,failRead:Bool=false) {self.id=id;self.partial=partial;self.failRead=failRead}
  func fetch(_ sql:String) throws -> Execution {
    requests.append(sql)
    var result=Execution()
    if requests.count==1 {result.partial=partial}
    else {if failRead {throw SQLFailure("Read failed after save")};result.results=[Rows(values:[[id,"After","1","","sa","Idle","2026-10-15T13:00:00"]]),Rows(),Rows()]}
    return result
  }
}
