import AppKit
import Foundation
import SQLServerKit
import SwiftUI
import Testing

@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ObjectDefinitionIndexControllerTests {
  private func output(_ values: [[String?]]) -> Execution {
    var result = Execution()
    result.results = [
      Rows(fields: (0..<(values.first?.count ?? 5)).map { Field(String($0)) }, values: values)
    ]
    return result
  }
  private func wait(_ controller: ObjectDefinitionIndexController) async throws {
    for _ in 0..<400 where controller.isRefreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!controller.isRefreshing)
  }
  @Test func ddlRefreshBypassesFreshnessAndQueuesBehindTheActiveReader() async throws {
    let url=URL(fileURLWithPath:"/tmp/DDLDefinition-"+UUID().uuidString).appendingPathComponent("index.sqlite")
    defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),profile=ServerProfile(indexObjectDefinitions:true)
    let server=ConnectedServer(profile:profile,password:"",diskIndex:disk,objectIndexService:CatalogIndexService(index:disk),completionIndexService:SQLCatalogService(index:disk))
    server.databases=[CatalogItem(id:1,name:"master")]
    var created=false,inventoryReads=0,bodyReads=0
    let body="CREATE VIEW dbo.NewView AS SELECT 1 AS ID;"
    server.asyncCatalogFixture={sql in
      if sql.contains("StudioObjectDefinitionInventory") {
        inventoryReads+=1
        try await Task.sleep(for:.milliseconds(20))
        return output(created ? [["44","dbo","NewView","V","stamp","0"]]:[])
      }
      bodyReads+=1
      return output([["44",body,"1","1","0",nil,String(body.utf16.count*2)]])
    }
    await server.definitionIndex.configure()
    server.definitionIndex.refresh();try await wait(server.definitionIndex)
    #expect(inventoryReads == 1)
    created=true
    server.definitionIndex.refreshAfterDDL(database:"master")
    server.definitionIndex.refreshAfterDDL(database:"master")
    try await wait(server.definitionIndex)
    #expect(inventoryReads == 3 && bodyReads == 1)
    server.online=false
    #expect(try await server.definitionIndex.cached(database:"master",id:44).sql.contains("NewView"))
  }
  @Test func offlineTablePreviewIncludesOnlyItsIndexedTriggerScripts() async throws {
    let url=URL(fileURLWithPath:"/tmp/TriggerPreview-"+UUID().uuidString).appendingPathComponent("index.sqlite")
    defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url)
    let profile=ServerProfile(visibleDatabases:["master"],indexObjectDefinitions:true)
    let server=ConnectedServer(profile:profile,password:"",diskIndex:disk,objectIndexService:CatalogIndexService(index:disk),completionIndexService:SQLCatalogService(index:disk))
    server.online=false
    await server.definitionIndex.configure()
    let lease=try #require(try await disk.configureDefinitions(owner:server.id,enabled:true))
    let scope=CatalogDiskIndex.scope(profile:profile,database:"master")
    let values=[IndexedObjectDefinition(id:10,schema:"dbo",name:"T",type:"U",sql:"CREATE TABLE dbo.T(ID int);"),IndexedObjectDefinition(id:11,schema:"dbo",name:"tr",type:"TR",sql:"CREATE TRIGGER dbo.tr ON dbo.T AFTER INSERT AS SELECT 1;",parentID:10),IndexedObjectDefinition(id:12,schema:"dbo",name:"other",type:"TR",sql:"UNRELATED",parentID:99)]
    try await disk.saveDefinitions(values,owner:server.id,lease:lease,scope:scope,generation:disk.generation(scope:scope))
    let result=try await server.definitionIndex.cached(database:"master",id:10)
    #expect(result.sql.contains("GO\nCREATE TRIGGER dbo.tr") && !result.sql.contains("UNRELATED"))
    #expect(try await disk.definition(scope:scope,id:10)?.sql == values[0].sql)
  }
  @Test func incrementalIndexOfflineReadAndLiveOpenNeverFallsBack() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionController-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(visibleDatabases: ["master"], indexObjectDefinitions: true)
    let server = ConnectedServer(
      profile: profile, password: "", diskIndex: disk,
      objectIndexService: CatalogIndexService(index: disk),
      completionIndexService: SQLCatalogService(index: disk))
    server.databases = [CatalogItem(id: 1, name: "master")]
    var reads = 0
    var body = "CREATE VIEW [dbo].[Example] AS SELECT 1 AS n;"
    var stamp = "1"
    server.catalogFixture = { sql in
      if sql.contains("StudioObjectDefinitionInventory") {
        return output([["9", "dbo", "Example", "V", stamp, "0"]])
      }
      if sql.contains("m.definition") {
        reads += 1
        return output([["9", body, "1", "1", "0", nil, String(body.utf16.count*2)]])
      }
      if sql.contains("OBJECT_DEFINITION") {
        reads += 1
        return output([[body]])
      }
      return output([["1", "1"]])
    }
    await server.definitionIndex.configure()
    server.definitionIndex.refresh()
    try await wait(server.definitionIndex)
    #expect(reads == 1)
    await server.definitionIndex.configure()
    server.definitionIndex.refresh()
    try await wait(server.definitionIndex)
    #expect(reads == 1)
    server.online = false
    #expect(try await server.definitionIndex.cached(database: "master", id: 9).original == body)
    #expect(
      try await server.definitionIndex.items(database: "master", folder: .views).map(\.name) == [
        "Example"
      ])
    server.online = true
    await #expect(throws: SQLFailure.self) {
      try await server.definitionIndex.cached(database: "master", id: 9)
    }
    body = "CREATE VIEW [dbo].[Example] AS SELECT 2 AS n;"
    stamp = "2"
    let workbench = WorkbenchController(state: StudioState())
    let node = TreeNode(
      "dbo.Example", kind: .object(.views), server: server, database: "master",
      item: .init(id: 9, name: "Example", schema: "dbo", detail: "VIEW"))
    let loaded = try await workbench.loadManagedModule(node, verb: "ALTER")
    #expect(loaded.original == body && reads == 2)
    server.online = false
    #expect(try await server.definitionIndex.cached(database: "master", id: 9).original == body)
    server.online = true
    server.asyncCatalogFixture = { _ in throw SQLFailure("Live permission denied") }
    await #expect(throws: SQLFailure.self) {
      try await workbench.loadManagedModule(node, verb: "ALTER")
    }
    #expect(reads == 2)
    let oldGeneration = server.generation
    server.generation = UUID()
    await server.definitionIndex.record(
      .init(id: 9, schema: "dbo", name: "Example", type: "V", sql: "Stale response"),
      database: "master", generation: oldGeneration)
    server.online = false
    #expect(try await server.definitionIndex.cached(database: "master", id: 9).original == body)
    await server.definitionIndex.remove()
    server.online = false
    await #expect(throws: SQLFailure.self) {
      try await server.definitionIndex.cached(database: "master", id: 9)
    }
  }
  @Test func removalRevokesLateNetworkWritesAndPreservesOtherExplorer() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionLate-" + UUID().uuidString)
      .appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(indexObjectDefinitions: true)
    let server = ConnectedServer(
      profile: profile, password: "", diskIndex: disk,
      objectIndexService: CatalogIndexService(index: disk),
      completionIndexService: SQLCatalogService(index: disk))
    server.databases = [CatalogItem(id: 1, name: "master")]
    var continuation: CheckedContinuation<Execution, Never>?
    server.asyncCatalogFixture = { _ in await withCheckedContinuation { continuation = $0 } }
    await server.definitionIndex.configure()
    server.definitionIndex.refresh()
    for _ in 0..<100 where continuation == nil { try await Task.sleep(for: .milliseconds(5)) }
    #expect(continuation != nil)
    await server.definitionIndex.remove()
    continuation?.resume(returning: output([["9", "dbo", "Late", "V", "1", "0"]]))
    try await wait(server.definitionIndex)
    let scope = CatalogDiskIndex.scope(profile: profile, database: "master")
    #expect(try await disk.definition(scope: scope, id: 9) == nil)
    #expect(server.definitionIndex.status != "master · 1 tanım · 0 okunamadı")
  }
  @Test func partialPageSplitsWithoutPublishingPartialBodies() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionSplit-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(indexObjectDefinitions: true)
    let server = ConnectedServer(profile: profile, password: "", diskIndex: disk)
    server.databases = [.init(id: 1, name: "master")]
    var reads = 0
    server.catalogFixture = { sql in
      if sql.contains("StudioObjectDefinitionInventory") {
        return output([["1", "dbo", "P1", "P", "1", "0"], ["2", "dbo", "P2", "P", "1", "0"]])
      }
      reads += 1
      if sql.contains("IN (1,2)") { var partial = output([["1", "incomplete", "1", "1", "0", nil]]); partial.partial = true; return partial }
      let id = sql.contains("IN (1)") ? "1" : "2"
      let body="CREATE PROC dbo.P" + id + " AS SELECT 1;"
      return output([[id, body, "1", "1", "0", nil, String(body.utf16.count*2)]])
    }
    await server.definitionIndex.configure(); server.definitionIndex.refresh()
    try await wait(server.definitionIndex)
    #expect(reads == 3)
    let scope = CatalogDiskIndex.scope(profile: profile, database: "master")
    #expect(try await disk.definitionStatus(scope: scope).count == 2)
    #expect(try await disk.definition(scope: scope, id: 1)?.sql.contains("incomplete") == false)
  }
  @Test func sevenThousandModulesUseBoundedPagesAndSkipUnchangedBodies() async throws {
    let url = URL(fileURLWithPath: "/tmp/Definition7000-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let profile = ServerProfile(indexObjectDefinitions: true)
    let server = ConnectedServer(profile: profile, password: "", diskIndex: disk,
      objectIndexService: CatalogIndexService(index: disk), completionIndexService: SQLCatalogService(index: disk))
    server.databases = [.init(id: 1, name: "master")]
    var reads = 0
    server.catalogFixture = { sql in
      if sql.contains("StudioObjectDefinitionInventory") {
        return output((1...7000).map { [String($0), "dbo", "P" + String($0), "P", "1", "0"] })
      }
      reads += 1
      let list = sql.components(separatedBy: "IN (").last!.components(separatedBy: ")").first!
      let ids = list.split(separator: ",").map(String.init)
      #expect(ids.count <= 200)
      return output(ids.map { id in
        let body="CREATE PROCEDURE dbo.P" + id + " AS SELECT 1;"
        return [id,body,"1","1","0",nil,String(body.utf16.count*2)]
      })
    }
    let began = Date()
    await server.definitionIndex.configure(); server.definitionIndex.refresh()
    for _ in 0..<6000 where server.definitionIndex.isRefreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!server.definitionIndex.isRefreshing)
    #expect(reads == 35)
    let scope = CatalogDiskIndex.scope(profile: profile, database: "master")
    #expect(try await disk.definitionStatus(scope: scope).count == 7000)
    print("Definition7000: \(Date().timeIntervalSince(began)) seconds, \(reads) detail queries")
    await server.definitionIndex.configure(); server.definitionIndex.refresh()
    try await wait(server.definitionIndex)
    #expect(reads == 35)
  }
  @Test func sevenThousandTablesUseSharedMetadataRowsetsInsteadOfSevenPerObject() async throws {
    let url = URL(fileURLWithPath: "/tmp/DefinitionTables7000-" + UUID().uuidString).appendingPathComponent("index.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let disk = CatalogDiskIndex(url: url)
    let server = ConnectedServer(profile: .init(definitionIndexDatabases: ["master": true]), password: "", diskIndex: disk)
    server.databases = [.init(id: 1, name: "master")]
    var reads = 0, rowsets = 0
    server.catalogFixture = { sql in
      if sql.contains("Inventory") {
        return output((1...7000).map { [String($0), "dbo", "T" + String($0), "U", "1", "0"] })
      }
      reads += 1
      #expect(sql.components(separatedBy: "SELECT c.object_id,c.column_id").count == 2)
      let list = sql.components(separatedBy: "c.object_id IN (").last!.components(separatedBy: ")").first!
      let ids = list.split(separator: ",").map(String.init)
      #expect(ids.count <= 200)
      var result = Execution()
      result.results = [Rows(values: ids.map { [$0, "1", "A", "int", "0", "0", nil, nil, nil, "0", nil, nil, nil, "0", "0", "0"] }),
        Rows(), Rows(), Rows(), Rows(), Rows(), Rows(values: ids.map { [$0, "0", "PRIMARY"] })]
      rowsets += result.results.count
      return result
    }
    let began = Date()
    await server.definitionIndex.configure(); server.definitionIndex.refresh()
    for _ in 0..<6000 where server.definitionIndex.isRefreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!server.definitionIndex.isRefreshing && reads == 35 && rowsets == 245)
    let scope = CatalogDiskIndex.scope(profile: server.profile, database: "master")
    #expect(try await disk.definitionStatus(scope: scope).count == 7000)
    #expect(try await disk.definition(scope: scope, id: 7000)?.sql.contains("[T7000]") == true)
    print("DefinitionTables7000: \(Date().timeIntervalSince(began)) seconds, \(reads) detail queries, \(rowsets) rowsets")
  }
  @Test func offlinePreviewUsesReadOnlyNativeSQLAndFitsLightAndDark() async throws {
    _ = NSApplication.shared
    let value = IndexedObjectDefinition(
      id: 1, schema: "dbo", name: "Example", type: "V",
      sql: "CREATE VIEW [dbo].[Example]\nAS\nSELECT N'Çevrimdışı içerik' AS [Ad];")
    let host = NSHostingView(
      rootView: InlineOfflineDefinitionView(preview:OfflineDefinitionPreview(server:ConnectedServer(profile:ServerProfile(),password:""),database:"Synthetic",value:value),back:{},navigate:{_ in}))
    let window = NSWindow(
      contentRect: NSRect(x: -20000, y: 0, width: 820, height: 540), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    let old = StudioTheme.mode
    defer {
      window.close()
      StudioTheme.apply(old)
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    for mode in ["light", "dark"] {
      StudioTheme.apply(mode)
      window.orderFront(nil)
      try await Task.sleep(for: .milliseconds(60))
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      let text = try #require(
        descendants(host).compactMap { $0 as? NSTextView }.first {
          $0.identifier?.rawValue == "sqlSourcePreview"
        })
      #expect(!text.isEditable && text.isSelectable && text.string == value.sql)
      #expect(host.fittingSize.width <= 820 && host.fittingSize.height <= 540)
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try bitmap.representation(using: .png, properties: [:])?.write(
        to: URL(fileURLWithPath: "/tmp/MSSQLStudio-offline-definition-\(mode).png"))
    }
  }

  @Test(arguments:["timeout","persistent","permission","cancel","inventory"])
  func timeoutsDoNotShrinkGroupsAndPreserveOldDefinitions(_ mode:String) async throws {
    let url=URL(fileURLWithPath:"/tmp/DefinitionTimeout-"+UUID().uuidString).appendingPathComponent("index.sqlite")
    defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url),profile=ServerProfile(indexObjectDefinitions:true)
    let server=ConnectedServer(profile:profile,password:"",diskIndex:disk)
    server.databases=[.init(id:1,name:"master")]
    let timeout=SQLFailure("Query timeout expired",diagnostics:[.init(state:"HYT00",code:0,message:"Synthetic timeout")])
    var groups:[Int]=[],inventories=0
    server.asyncCatalogFixture={sql in
      if sql.contains("StudioObjectDefinitionInventory") {
        inventories+=1
        if mode=="inventory" {throw timeout}
        return output((1...16).map {[String($0),"dbo","P"+String($0),"P","new","0"]})
      }
      let clause=try #require(sql.range(of:"IN ("))
      let ids=sql[clause.upperBound...].prefix(while:{$0 != ")"}).split(separator:",").map(String.init)
      groups.append(ids.count)
      if mode=="persistent" {throw timeout}
      if mode=="permission" {throw SQLFailure("Denied",diagnostics:[.init(state:"42000",code:229,message:"Denied")])}
      if mode=="cancel" {throw CancellationError()}
      if ids.count>8 {var result=Execution();result.failure=timeout;return result}
      return output(ids.map {id in
        let body="CREATE PROC dbo.P"+id+" AS SELECT 1;"
        return [id,body,"1","1","0",nil,String(body.utf16.count*2)]
      })
    }
    await server.definitionIndex.configure()
    await server.definitionIndex.record(.init(id:1,schema:"dbo",name:"P1",type:"P",sql:"OLD_BODY"),database:"master",generation:server.generation)
    server.definitionIndex.refresh();try await wait(server.definitionIndex)
    let scope=CatalogDiskIndex.scope(profile:profile,database:"master")
    let status=try await disk.definitionStatus(scope:scope)
    #expect(inventories==1)
    #expect(groups.count==(mode=="inventory" ? 0:1))
    #expect(groups.isEmpty || groups==[16])
    #expect(status.synchronizedAt==nil && status.count==1)
    #expect(try await disk.definition(scope:scope,id:1)?.sql=="OLD_BODY")
    let activity=server.definitionIndex.activities["master"]
    if mode=="cancel" {#expect(activity?.phase == .paused)}
    else {#expect(activity?.phase == .failed && activity?.error?.contains(mode=="inventory" ? "Nesne envanteri":"SQL modülleri")==true && activity?.error?.contains("120 sn")==true)}
  }

  @Test func transientFailureAutomaticallyResumesAndReusesAlreadySavedGroups() async throws {
    let url=URL(fileURLWithPath:"/tmp/DefinitionAutoRetry-"+UUID().uuidString).appendingPathComponent("index.sqlite")
    defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
    let disk=CatalogDiskIndex(url:url)
    let server=ConnectedServer(profile:.init(definitionIndexDatabases:["master":true,"Other":true]),password:"",diskIndex:disk)
    server.databases=[.init(id:1,name:"master"),.init(id:2,name:"Other")]
    let controller=ObjectDefinitionIndexController(server:server,disk:disk,retryDelay:0.03);server.definitionIndex=controller
    var inventories=0,groups:[Int]=[],attempts=0,inFlight=0,maxInFlight=0
    server.asyncCatalogFixture={sql in
      inFlight+=1;maxInFlight=max(maxInFlight,inFlight);defer {inFlight-=1}
      try await Task.sleep(for:.milliseconds(2))
      if sql.contains("Inventory") {
        inventories+=1
        return output(inventories==2 ? []:(1...201).map {[String($0),"dbo","P"+String($0),"P","new","0"]})
      }
      let start=try #require(sql.range(of:"IN ("))
      let ids=sql[start.upperBound...].prefix(while:{$0 != ")"}).split(separator:",").map(String.init)
      groups.append(ids.count)
      if ids==["201"] {attempts+=1;if attempts==1 {throw SQLFailure("Synthetic timeout",diagnostics:[.init(state:"HYT00",code:0,message:"Timeout")])}}
      return output(ids.map {id in let body="CREATE PROC dbo.P"+id+" AS SELECT 1;";return [id,body,"1","1","0",nil,String(body.utf16.count*2)]})
    }
    await controller.configure();controller.refresh()
    for _ in 0..<500 where attempts<2 || controller.isRefreshing {try await Task.sleep(for:.milliseconds(5))}
    #expect(attempts==2 && inventories==3 && groups==[200,1,1] && maxInFlight==1)
    let status=try await disk.definitionStatus(scope:CatalogDiskIndex.scope(profile:server.profile,database:"master"))
    #expect(status.count==201 && status.synchronizedAt != nil && controller.activities["master"]==nil)
    controller.pause()
  }
  @Test(arguments:["pause","configure","generation"]) func pausingCancelsPendingRetryAndPermissionErrorsNeverScheduleOne(_ action:String) async throws {
    for state in ["HYT00","42000"] {
      let url=URL(fileURLWithPath:"/tmp/DefinitionRetryPause-"+UUID().uuidString).appendingPathComponent("index.sqlite")
      defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
      let disk=CatalogDiskIndex(url:url),server=ConnectedServer(profile:.init(indexObjectDefinitions:true),password:"",diskIndex:disk)
      server.databases=[.init(id:1,name:"master")]
      let controller=ObjectDefinitionIndexController(server:server,disk:disk,retryDelay:0.1);server.definitionIndex=controller
      var reads=0
      server.asyncCatalogFixture={_ in reads+=1;throw SQLFailure("Synthetic",diagnostics:[.init(state:state,code:0,message:"Synthetic")])}
      await controller.configure();controller.refresh();try await wait(controller)
      #expect((controller.activities["master"]?.retryAt != nil)==(state=="HYT00"))
      if action=="pause" {controller.pause()}
      else if action=="configure" {await controller.configure(enabled:false)}
      else {server.generation=UUID()}
      try await Task.sleep(for:.milliseconds(150))
      #expect(reads==1 && controller.activities["master"]?.retryAt==nil)
    }
  }

}
