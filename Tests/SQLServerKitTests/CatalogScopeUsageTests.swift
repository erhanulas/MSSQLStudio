import Foundation
import Testing
@testable import SQLServerKit

struct CatalogScopeUsageTests {
  @Test func usageIsScopedCountsUTF8AndIgnoresStaging() async throws {
    let folder=URL(fileURLWithPath:"/tmp/StudioUsage-\(UUID())")
    defer {try? FileManager.default.removeItem(at:folder)}
    let disk=CatalogDiskIndex(url:folder.appendingPathComponent("index.sqlite"))
    try await disk.append(scope:"stage",items:[.init(id:1,name:"İş",schema:"dbo",detail:"VIEW")])
    try await disk.finishBuild(staging:"stage",scope:"a")
    let before=try await disk.scopeUsage(scope:"a")
    #expect(before.objects>0 && before.columns==0 && before.definitions==0)
    let stamp=Date(timeIntervalSince1970:1_700_000_000)
    let snapshot=SQLCatalogSnapshot(symbols:[],synchronizedAt:stamp)
    try await disk.saveCompletionSnapshot(scope:"a",snapshot:snapshot)
    let after=try await disk.scopeUsage(scope:"a")
    #expect(after.columns==Int64(try JSONEncoder().encode(snapshot).count))
    #expect(after.objects==before.objects && after.total==before.total+after.columns)
    #expect(try await disk.completionDate(scope:"a")==stamp)
    try await disk.saveCompletionSnapshot(scope:"b",snapshot:snapshot)
    try await disk.append(scope:"unpublished",items:[.init(id:2,name:"Other",schema:"dbo",detail:"VIEW")])
    #expect(try await disk.scopeUsage(scope:"a").total==after.total)
    #expect(try await disk.scopeUsage(scope:"missing").total==0)
    #expect(try await disk.completionDate(scope:"missing")==nil)
    let owner=UUID(),lease=try #require(try await disk.configureDefinitions(owner:owner,enabled:true))
    let generation=try await disk.generation(scope:"a")
    let definition=IndexedObjectDefinition(id:1,schema:"dbo",name:"Türkçe",type:"V",sql:"CREATE VIEW dbo.[Türkçe] AS SELECT N'İçerik'")
    try await disk.saveDefinition(definition,owner:owner,lease:lease,scope:"a",generation:generation)
    #expect(try await disk.scopeUsage(scope:"a").definitions==Int64(try JSONEncoder().encode(definition).count))
    try await disk.setExcluded(true,scope:"a")
    #expect(try await disk.scopeUsage(scope:"a").total==0)
    #expect(try await disk.completionDate(scope:"a")==nil)
    #expect(try await disk.scopeUsage(scope:"b").columns>0)
  }
}
