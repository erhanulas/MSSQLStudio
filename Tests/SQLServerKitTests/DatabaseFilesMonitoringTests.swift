import Foundation
import Testing
@testable import SQLServerKit

@Suite struct DatabaseFilesMonitoringTests {
  private let data:[String?]=["5","1","D'B","Data","ROWS","/fixture/data.mdf","1024","-1","128","0","ONLINE","0","0"]
  private func inventory(_ values:[[String?]],issues:[[String?]]=[])->Execution {
    var result=Execution();result.results=[Rows(fields:DatabaseFilesMonitoring.columns.map {Field($0)},values:values),Rows(fields:[Field("issue")],values:issues)];return result
  }
  private func details(_ values:[[String?]])->Execution {
    var result=Execution();result.results=[Rows(fields:(DatabaseFilesMonitoring.columns+["used_pages"]).map {Field($0)},values:values)];return result
  }
  @Test func inventoryPreservesScopeGrowthAndUnknownUsage() throws {
    var log=data;log[1]="2";log[4]="LOG";log[7]="268435456";log[8]="10";log[9]="1"
    let decoded=try DatabaseFilesMonitoring.decodeInventory(inventory([data,log],issues:[["Limited metadata"]]))
    #expect(decoded.files.map(\.id) == ["5:1","5:2"] && decoded.issues == ["Limited metadata"] && !decoded.limited)
    #expect(decoded.files[0].database == "D'B" && decoded.files[0].sizePages == 1024 && decoded.files[0].usedPages == nil)
    #expect(decoded.files[0].maxPages == -1 && decoded.files[0].growth == 128 && decoded.files[0].percentGrowth == false)
    #expect(decoded.files[1].growth == 10 && decoded.files[1].percentGrowth == true)
  }
  @Test func usageIsOnlyForValidNonSparseDataInTheRequestedDatabase() throws {
    var log=data;log[1]="2";log[4]="LOG"
    var sparse=data;sparse[1]="3";sparse[12]="1"
    var uncertain=data;uncertain[1]="4";uncertain[12]=nil
    var filestream=data;filestream[1]="5";filestream[4]="FILESTREAM"
    let decoded=try DatabaseFilesMonitoring.decodeDetails(details([data+["768"],log+["12"],sparse+["12"],uncertain+["12"],filestream+["12"]]),database:"D'B")
    #expect(decoded.files[0].freePages == 256 && decoded.files[0].usedFraction == 0.75)
    #expect(decoded.files.dropFirst().allSatisfy {$0.usedPages == nil && $0.freePages == nil && $0.usedFraction == nil})
    #expect(throws:SQLFailure.self) {try DatabaseFilesMonitoring.decodeDetails(details([data+["768"]]),database:"Other")}
  }
  @Test func invalidNegativeOverflowAndOutOfRangeUsageNeverBecomeZero() throws {
    for value in [nil,"-1","NaN","9223372036854775807","1025"] as [String?] {
      let file=try #require(DatabaseFilesMonitoring.decodeDetails(details([data+[value]]),database:"D'B").files.first)
      #expect(file.usedPages == nil && file.freePages == nil && file.usedFraction == nil)
    }
    var row=data;row[6]="-1";row[7]="-2";row[8]="-1";row[9]="2"
    let file=try #require(DatabaseFilesMonitoring.decodeInventory(inventory([row])).files.first)
    #expect(file.sizePages == nil && file.maxPages == nil && file.growth == nil && file.percentGrowth == nil)
    let zero=try #require(DatabaseFilesMonitoring.decodeDetails(details([data+["0"]]),database:"D'B").files.first)
    #expect(zero.usedPages == 0 && zero.freePages == 1024 && zero.usedFraction == 0)
  }
  @Test func incompleteMalformedAndDuplicateMetadataAreRejected() {
    var partial=inventory([data]);partial.partial=true
    var stopped=inventory([data]);stopped.stoppedEarly=true
    var truncated=inventory([data]);truncated.results[0].truncated=true
    var header=inventory([data]);header.results[0].fields[0]=Field("wrong")
    var issueHeader=inventory([data]);issueHeader.results[1]=Rows(fields:[Field("wrong")],values:[])
    var missing=inventory([data]);missing.results.removeLast()
    for result in [partial,stopped,truncated,header,issueHeader,missing,inventory([data,data]),inventory([Array(data.dropLast())]),inventory([data],issues:[[nil]])] {
      #expect(throws:SQLFailure.self) {try DatabaseFilesMonitoring.decodeInventory(result)}
    }
  }
  @Test func intentionalInventoryCapIsExplicitAndRetainsOnlyFiveThousand() throws {
    let rows=(1...5001).map {index -> [String?] in var row=data;row[1]=String(index);return row}
    let decoded=try DatabaseFilesMonitoring.decodeInventory(inventory(rows))
    #expect(decoded.limited && decoded.files.count == 5000 && decoded.files.last?.fileID == 5000)
    #expect(throws:SQLFailure.self) {try DatabaseFilesMonitoring.decodeInventory(inventory(rows+[data]))}
  }
  @Test func queriesAreBoundedContextCorrectAndDoNotInventTempdbFilestreamOrLogUsage() throws {
    let inventory=DatabaseFilesMonitoring.inventorySQL,detail=DatabaseFilesMonitoring.detailSQL(database:"D'B]; DROP DATABASE x;--")
    #expect(inventory.contains("TOP (5001)") && inventory.contains("f.database_id=2 OR f.type=2 THEN NULL"))
    #expect(inventory.contains("VIEW ANY DEFINITION") && inventory.contains("ALTER ANY DATABASE") && inventory.contains("CREATE DATABASE"))
    #expect(detail.contains("WHERE DB_NAME()=N'D''B]; DROP DATABASE x;--'"))
    #expect(detail.contains("f.type=0 AND f.is_sparse=0") && !detail.contains("dm_db_log_space_usage"))
    if let root=ProcessInfo.processInfo.environment["MSSQL_DATABASE_FILES_SQL_DUMP"] {
      let directory=URL(fileURLWithPath:root,isDirectory:true);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
      try inventory.write(to:directory.appendingPathComponent("inventory.sql"),atomically:true,encoding:.utf8)
      try DatabaseFilesMonitoring.detailSQL(database:"D'B").write(to:directory.appendingPathComponent("detail.sql"),atomically:true,encoding:.utf8)
    }
  }
}
