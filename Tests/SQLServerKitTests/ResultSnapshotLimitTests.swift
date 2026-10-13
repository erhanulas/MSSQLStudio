import Foundation
import Testing
@testable import SQLServerKit

struct ResultSnapshotLimitTests {
  @Test func prefixSnapshotsShareBackingWithoutRemovingLoadedRowsOrInventingRows() throws {
    let values=(0..<1200).map {row in [String(row),row.isMultiple(of:2) ? nil:"İstanbul 👩🏽‍💻", "12345678901234567890.00000000"]}
    let spool=try ResultSpool(),disk=try spool.append(values),memory=RowCollection(values)
    for source in [memory,disk] {
      let limited=source.prefixSnapshot(10)
      #expect(limited.count == 10 && limited.diskBacked == source.diskBacked)
      #expect(limited[0] == values[0] && limited[9] == values[9])
      #expect(source.count == 1200 && source[1199] == values[1199])
      #expect(source.prefixSnapshot(700).count == 700 && source.prefixSnapshot(700)[699] == values[699])
      #expect(source.prefixSnapshot(2000).count == 1200)
      #expect(source.prefixSnapshot(0).isEmpty && source.prefixSnapshot(-2).isEmpty)
      #expect(limited.prefixSnapshot(100).count == 10)
      var appended=limited;appended.append(["appended"])
      #expect(appended.count == 11 && appended[10] == ["appended"] && source.count == 1200)
      var extended=limited;extended.append(contentsOf:[[nil],["last"]])
      #expect(extended.count == 12 && extended[11] == ["last"] && source[1199] == values[1199])
    }
    let later=try spool.append([["later"]])
    #expect(disk.count == 1200 && later.count == 1201 && disk.prefixSnapshot(10).count == 10)
  }
  @Test func prefixLimitRunsBeforeFilteringSortingAndColumnValueChoices() throws {
    var source=Rows(fields:[Field("ID",type:4),Field("Text")],values:(0..<100).map {[String($0),$0 < 10 ? "inside":"outside"]})
    source.values=source.values.prefixSnapshot(10)
    let sorted=try ResultFiltering.projection(source,search:"",rules:[:],sortColumn:0,ascending:false)
    #expect(sorted == Array((0..<10).reversed()))
    #expect(try ResultFiltering.projection(source,search:"outside",rules:[:],sortColumn:nil,ascending:true) == [])
    let choices=try ResultFiltering.choices(source,column:1,search:"")
    #expect(choices.values == [.text("inside")] && !choices.truncated)
    var rule=ColumnRule();rule.operation = .greater;rule.first="8"
    #expect(try ResultFiltering.projection(source,search:"",rules:[0:rule],sortColumn:0,ascending:true) == [9])
  }
  @Test func allAndPageExportsUseOnlyTheBoundedSnapshotWhileOriginalValuesRemainAvailable() throws {
    let spool=try ResultSpool()
    var source=Rows(fields:[Field("ID",type:4),Field("Exact"),Field("Missing")])
    source.values=try spool.append((0..<40).map {[String($0),"964.80000000",nil]})
    var limited=source;limited.values=source.values.prefixSnapshot(10)
    let folder=URL(fileURLWithPath:"/tmp/result-prefix-export-\(UUID())")
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:folder)}
    for (name,indices,count) in [("all",nil as [Int]?,10),("page",[7,8,9],3)] {
      let path=folder.appendingPathComponent(name+".json")
      try ResultFileExport.write(limited,indices:indices,json:true,to:path)
      let object=try #require(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
      let values=try #require(object["rows"] as? [[Any]])
      #expect(values.count == count && values.last?[0] as? String == "9")
      #expect(values.last?[1] as? String == "964.80000000" && values.last?[2] is NSNull)
    }
    let csv=folder.appendingPathComponent("all.csv")
    try ResultFileExport.write(limited,indices:nil,json:false,to:csv)
    let text=try String(contentsOf:csv,encoding:.utf8)
    #expect(text.components(separatedBy:"\r\n").count == 12 && !text.contains("\"10\""))
    #expect(source.values.count == 40 && source.values[39][0] == "39" && limited.values.diskBacked)
  }
}
