import Foundation
import Testing
@testable import SQLServerKit

struct QueryHistoryStoreTests {
  @Test func closedTabsRetainNewestPerServerDatabaseAndIgnoreEmptySQL() async throws {
    let first=UUID(),second=UUID(),now=Date()
    func record(_ server:UUID,_ db:String,_ n:Int,_ text:String="SELECT 1")->QueryRecord {
      var value=QueryRecord(server:"Same name",database:db,text:text,serverID:server,seconds:0,status:"Kapatılan Sekme")
      value.tabTitle="Tab \(n)";value.time=now.addingTimeInterval(Double(n)-4000000);return value
    }
    let values=[record(first,"A",1),record(first,"A",2),record(first,"A",3),record(first,"B",1),record(second,"A",1),record(first,"B",2," \n\t")]
    let kept=QueryHistoryPolicy.retained(values,days:1,closedTabLimit:2)
    #expect(kept.count==4 && !kept.contains {$0.serverID==first && $0.database=="A" && $0.tabTitle=="Tab 1"})
    #expect(QueryHistoryPolicy.closedTabs(values,limit:2).map(\.id)==kept.map(\.id))
    let folder=URL(fileURLWithPath:"/tmp/StudioHistoryScopes-\(UUID())")
    defer {try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("history.json")
    _=try await QueryHistoryStore().save(values,to:url,days:1,closedTabLimit:2)
    #expect(try JSONDecoder().decode([QueryRecord].self,from:Data(contentsOf:url)).count==4)
  }
  @Test func optionalTabMetadataPreservesLegacyRecordsAndAtomicWrites() async throws {
    let folder=URL(fileURLWithPath:"/tmp/StudioHistory119-\(UUID())")
    defer {try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("history.json"),store=QueryHistoryStore()
    let legacy=QueryRecord(server:"Fixture",database:"DemoDB",text:"SELECT 1",seconds:0,status:"Başarılı")
    let decoded=try JSONDecoder().decode(QueryRecord.self,from:JSONEncoder().encode(legacy))
    #expect(decoded.tabTitle==nil && decoded.caret==nil && decoded.reopenedAt==nil)
    var closed=legacy;closed.id=UUID();closed.tabTitle="Closed";closed.caret=7;closed.selectionLength=1;closed.status="Kapatılan Sekme"
    _=try await store.save([legacy,closed],to:url,days:30)
    let values=try JSONDecoder().decode([QueryRecord].self,from:Data(contentsOf:url))
    #expect(values.count==2 && values.contains {$0.tabTitle=="Closed" && $0.caret==7})
    let permissions=try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue==0o600)
    let blocker=folder.appendingPathComponent("blocker");try Data("keep".utf8).write(to:blocker)
    await #expect(throws:(any Error).self) {try await store.save([],to:blocker.appendingPathComponent("history.json"),days:30)}
    #expect(try String(contentsOf:blocker,encoding:.utf8)=="keep")
    #expect(try JSONDecoder().decode([QueryRecord].self,from:Data(contentsOf:url)).count==2)
  }
}
