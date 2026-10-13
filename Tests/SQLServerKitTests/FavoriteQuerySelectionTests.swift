import Foundation
import Testing
@testable import SQLServerKit

struct FavoriteQuerySelectionTests {
  @Test func searchOnlyReturnsFavoritesUsableInTheExactEditorTarget() throws {
    let a=UUID(),b=UUID()
    let global=try FavoriteQuery(name:"Daily sales",sql:"SELECT 1",scope:.global)
    let connection=try FavoriteQuery(name:"Daily sales",sql:"SELECT 2",scope:.connection,serverID:a)
    let database=try FavoriteQuery(name:"Daily sales",sql:"SELECT 3",scope:.database,serverID:a,database:"Sales")
    let otherDB=try FavoriteQuery(name:"Daily sales",sql:"SELECT 4",scope:.database,serverID:a,database:"Other")
    let otherServer=try FavoriteQuery(name:"Daily sales",sql:"SELECT 5",scope:.database,serverID:b,database:"Sales")
    let values=[otherDB,global,otherServer,connection,database]
    #expect(FavoriteQuerySelection.matches(values,serverID:a,database:"Sales",search:"  SALES  daily ").map(\.id) == [database.id,connection.id,global.id])
    #expect(FavoriteQuerySelection.matches(values,serverID:b,database:"Sales").map(\.id) == [otherServer.id,global.id])
    #expect(FavoriteQuerySelection.matches(values,serverID:nil,database:nil).map(\.id) == [global.id])
    #expect(FavoriteQuerySelection.matches(values,serverID:a,database:"sales").map(\.id) == [connection.id,global.id])
    #expect(FavoriteQuerySelection.matches(values,serverID:a,database:"Sales",search:"DELETE").isEmpty)
  }
  @Test func keyboardSelectionStopsAtEdgesAndRecoversAfterFiltering() throws {
    let values=try ["A","B","C"].map {try FavoriteQuery(name:$0,sql:"SELECT 1",scope:.global)}
    #expect(FavoriteQuerySelection.next(values,selected:nil,step:1) == values[0].id)
    #expect(FavoriteQuerySelection.next(values,selected:values[0].id,step:-1) == values[0].id)
    #expect(FavoriteQuerySelection.next(values,selected:values[0].id,step:1) == values[1].id)
    #expect(FavoriteQuerySelection.next(values,selected:values[2].id,step:1) == values[2].id)
    #expect(FavoriteQuerySelection.next(values,selected:UUID(),step:-1) == values[2].id)
    #expect(FavoriteQuerySelection.next([],selected:nil,step:1) == nil)
  }
  @Test func saveReturnsTheSameValidatedOrderAsReloadWithoutChangingSQL() async throws {
    let folder=URL(fileURLWithPath:"/tmp/mssql-favorite-selection-\(UUID())")
    defer {try? FileManager.default.removeItem(at:folder)}
    let store=FavoriteQueryStore(url:folder.appendingPathComponent("favorites.json"))
    let a=try FavoriteQuery(name:"Query 10",sql:"SELECT N'İstanbul', NULL;\r\n",scope:.global)
    var b=try FavoriteQuery(name:"Query 2",sql:"SELECT -0.00000000;",scope:.global)
    _=try await store.save(a)
    let saved=try await store.save(b)
    let loaded=try await store.load()
    #expect(saved.map(\.id) == [b.id,a.id] && saved == loaded)
    b.sql="DECLARE @x int;\nSELECT @x;"
    #expect(try await store.save(b) == [b,a])
    #expect(try await store.load() == [b,a])
  }
}
