import Foundation
import Testing
import SQLServerKit
@testable import MSSQLStudio

@MainActor private final class TableDesignFixture {
  var table:TableDefinition
  var writes=0
  var failReadback=false
  var metadataChanged=false
  var refreshes=0
  init() throws {
    table=TableDefinition(schema:"dbo",name:"T",columns:[.init(id:1,name:"Id",type:"int",nullable:false),.init(id:2,name:"Name",type:"nvarchar(50)")],primaryKey:["Id"],primaryKeyName:"PK_T")
    table=try ObjectMetadata.decode(metadata(),schema:"dbo",name:"T");table.objectID=42
  }
  func metadata()->Execution {
    var result=Execution()
    result.results=[Rows(values:table.columns.map {c in [String(c.id),c.name,c.type,c.nullable ? "1":"0",c.identity ? "1":"0",c.seed,c.increment,c.computed,c.persisted ? "1":"0",c.defaultName,c.defaultSQL,c.collation,c.sparse ? "1":"0",c.rowGUID ? "1":"0","0",c.type]}),Rows(values:table.primaryKey.map {[$0,table.primaryKeyName]}),Rows(values:[]),Rows(values:[]),Rows(values:[]),Rows(values:[]),Rows(values:[["0",""]])]
    return result
  }
  func catalog(_ sql:String) throws -> Execution {
    if failReadback,writes>0 {throw SQLFailure("Synthetic readback failure")}
    var result=Execution()
    if sql==TableDataType.query {result.results=[Rows(values:[])];return result}
    if sql.hasPrefix("SELECT OBJECT_ID") {result.results=[Rows(values:[["42"]])];return result}
    if sql.contains("FROM sys.columns c") {
      if metadataChanged {table.columns[1].type="nvarchar(75)"}
      return metadata()
    }
    throw SQLFailure("Unexpected fixture read")
  }
  func write(_ sql:String) async throws -> Execution {
    writes+=1;table.columns[1].type="nvarchar(100)"
    return Execution()
  }
}
@MainActor @Suite(.serialized) struct TableDesignerApplicationTests {
  @Test func applyPreflightsWritesOnceRefreshesExplorerAndReadsBackMetadata() async throws {
    let fixture=try TableDesignFixture(),server=ConnectedServer(profile:ServerProfile(),password:"")
    server.online=true;server.asyncCatalogFixture={try fixture.catalog($0)}
    let node=TreeNode("T",kind:.object(.tables),server:server,database:"Demo",item:.init(id:42,name:"T",schema:"dbo"))
    let application=TableDesignerApplication(node:node)
    let model=TableDesignerModel(load:{fixture.table})
    await model.load();model.columns[1].type="nvarchar(100)"
    let plan=try model.prepare()
    let observer=NotificationCenter.default.addObserver(forName:.init("studioManagedObjectCompleted"),object:node,queue:.main) {_ in MainActor.assumeIsolated {fixture.refreshes+=1}}
    defer {NotificationCenter.default.removeObserver(observer)}
    let result=try await application.apply(plan,writer:fixture.write)
    #expect(fixture.writes==1 && fixture.refreshes==1 && result.columns[1].type=="nvarchar(100)" && result.objectID==42)
    do {_=try await application.apply(plan,writer:fixture.write);Issue.record("Stale metadata was accepted")}
    catch {#expect(error.localizedDescription.contains("başka bir oturumda"))}
    #expect(fixture.writes==1)
  }
  @Test func changedMetadataStopsBeforeWriteAndReadbackFailureNeverRetries() async throws {
    for changed in [true,false] {
      let fixture=try TableDesignFixture(),server=ConnectedServer(profile:ServerProfile(),password:"")
      server.online=true;server.asyncCatalogFixture={try fixture.catalog($0)}
      let node=TreeNode("T",kind:.object(.tables),server:server,database:"Demo",item:.init(id:42,name:"T",schema:"dbo"))
      let application=TableDesignerApplication(node:node),model=TableDesignerModel(load:{fixture.table})
      await model.load();model.columns[1].type="nvarchar(100)"
      let plan=try model.prepare()
      fixture.metadataChanged=changed;fixture.failReadback = !changed
      do {_=try await application.apply(plan,writer:fixture.write);Issue.record("Unsafe/failed operation was accepted")}
      catch {#expect(error.localizedDescription.contains(changed ? "başka bir oturumda":"güncel tasarım okunamadı"))}
      #expect(fixture.writes==(changed ? 0:1))
    }
  }
}
