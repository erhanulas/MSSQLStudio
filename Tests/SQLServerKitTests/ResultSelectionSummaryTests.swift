import Foundation
import Testing
@testable import SQLServerKit

@Suite struct ResultSelectionSummaryTests {
  private func sum(_ values:[String?],type:Int16=3) throws -> ResultSelectionSummary {
    let rows=Rows(fields:[Field("N",type:type)],values:values.map {[$0]})
    return try .compute(.init(rows:rows,selection:IndexSet(integersIn:0..<values.count),columns:[0]))
  }
  @Test func preservesBigintFullPrecisionCarryBorrowAndScale() throws {
    #expect(try sum(["9223372036854775807","9223372036854775807"],type:-5).sum=="18446744073709551614")
    #expect(try sum([String(repeating:"9",count:38),"1"]).sum=="1"+String(repeating:"0",count:38))
    #expect(try sum(["99999999999999999999.123456789012345678","0.000000000000000001"]).sum=="99999999999999999999.123456789012345679")
    #expect(try sum(["0.01","-1.02","2.000","-.25","+.005"]).sum=="0.745")
    #expect(try sum(["-1000000001.00","1000000000.00"]).sum=="-1.00")
    #expect(try sum(["0.0","-0.00","1.000","-1"]).sum=="0.000")
    #expect(try sum(["1E+3","-2.5e2","1e-3"],type:8).sum=="750.001")
    #expect(try sum(["1e-324","1e-324"],type:8).sum=="0."+String(repeating:"0",count:323)+"2")
  }
  @Test func countsNonNullIncludesEmptyTextButOnlySumsNumericBaseTypes() throws {
    let rows=Rows(fields:[Field("Alias",type:3,declaredType:"dbo.Amount"),Field("Text"),Field("Bit",type:-7)],values:[["1.25","100","1"],[nil,"",nil],["2.5",nil,"0"]])
    let summary=try ResultSelectionSummary.compute(.init(rows:rows,selection:IndexSet(integersIn:0..<3),columns:[0,1,2,0]))
    #expect(summary.sum=="3.75" && summary.count==6 && summary.numericCount==2)
    #expect(try ResultSelectionSummary.compute(.init(rows:rows,selection:IndexSet(integersIn:0..<3),columns:[1,2])).sum==nil)
    #expect(try sum([nil,nil]).sum==nil && sum([nil,nil]).count==0)
    #expect(try sum([]).count==0)
  }
  @Test func projectionPagePrefixAndDraftSnapshotUseOnlySelectedDisplayedCells() throws {
    let spool=try ResultSpool()
    var rows=Rows(fields:[Field("N",type:4),Field("Text")])
    rows.values=try spool.append([["10","a"],["20","b"],["30","c"],["9999","hidden"]]).prefixSnapshot(3)
    let request=ResultSelectionSummary.Request(rows:rows,selection:IndexSet(integersIn:0..<3),columns:[0,1],projection:[2,0,1],pageStart:1,basePageCount:2,newRows:[-1],overrides:[1:["21",nil],-1:["5","new"]])
    let summary=try ResultSelectionSummary.compute(request)
    #expect(summary.sum=="36" && summary.count==5 && summary.numericCount==3)
    #expect(rows.values[1][0]=="20" && rows.values.count==3 && rows.values.diskBacked)
  }
  @Test func invalidNumericAndStaleMappingsFailWithoutPartialResults() throws {
    for text in ["NaN","Infinity","1oops","1,23","1e401","",String(repeating:"1",count:513)] {
      #expect(throws:SQLFailure.self) {try sum(["1",text])}
    }
    let rows=Rows(fields:[Field("N",type:4)],values:[["1"]])
    for request in [ResultSelectionSummary.Request(rows:rows,selection:IndexSet(integer:2),columns:[0]),.init(rows:rows,selection:IndexSet(integer:0),columns:[2]),.init(rows:rows,selection:IndexSet(integer:0),columns:[0],projection:[5],basePageCount:1),.init(rows:rows,selection:IndexSet(integer:Int.max-1),columns:[0],pageStart:Int.max)] {
      #expect(throws:SQLFailure.self) {try ResultSelectionSummary.compute(request)}
    }
  }
  @Test func oversizedSelectionFailsBeforeAnyPartialCountIsPublished() throws {
    let count=1_666_667
    let rows=Rows(fields:[Field("A",type:4),Field("B",type:4),Field("C",type:4)],values:Array(repeating:[nil,nil,nil],count:count))
    do {
      _=try ResultSelectionSummary.compute(.init(rows:rows,selection:IndexSet(integersIn:0..<count),columns:[0,1,2]))
      Issue.record("Selection cell budget was ignored")
    } catch {#expect(error.localizedDescription.contains("5.000.000 hücre"))}
  }
  @Test func randomizedSignedScaledSumsMatchIntegerReference() throws {
    var seed:UInt64=42,values:[String?]=[],total:Int64=0
    for _ in 0..<2000 {
      seed=seed &* 6364136223846793005 &+ 1
      let cents=Int64(seed%2_000_001)-1_000_000;total+=cents
      values.append((cents<0 ? "-":"")+String(abs(cents)/100)+"."+String(format:"%02lld",abs(cents)%100))
    }
    let expected=(total<0 ? "-":"")+String(abs(total)/100)+"."+String(format:"%02lld",abs(total)%100)
    #expect(try sum(values).sum==expected)
  }
  @Test func largeDiskSelectionRunsOffActorAndCancellationIsHonored() async throws {
    let spool=try ResultSpool()
    var rows=Rows(fields:[Field("N",type:3)])
    for _ in 0..<10 {rows.values=try spool.append(Array(repeating:["12345678901234567890.00000001"],count:10_000))}
    let request=ResultSelectionSummary.Request(rows:rows,selection:IndexSet(integersIn:0..<100_000),columns:[0])
    let worker=Task.detached {try ResultSelectionSummary.compute(request)}
    #expect(try await worker.value.sum=="1234567890123456789000000.00100000")
    let cancelled=Task.detached {withUnsafeCurrentTask {$0?.cancel()};return try ResultSelectionSummary.compute(request)}
    do {_=try await cancelled.value;Issue.record("Cancelled selection was calculated")} catch {#expect(error is CancellationError)}
  }
}
