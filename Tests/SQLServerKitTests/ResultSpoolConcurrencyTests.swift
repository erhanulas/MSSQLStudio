import Foundation
import Testing
@testable import SQLServerKit

@Suite(.serialized) struct ResultSpoolConcurrencyTests {
  private func signaled(_ semaphore:DispatchSemaphore,seconds:Double) async -> Bool {
    await withCheckedContinuation {continuation in
      DispatchQueue.global().async {continuation.resume(returning:semaphore.wait(timeout:.now()+seconds) == .success)}
    }
  }
  @Test func cachedRowsAndCountsRemainReadableWhileNextBatchIsEncoding() async throws {
    let encoding=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0),readDone=DispatchSemaphore(value:0)
    let spool=try ResultSpool(encode:{rows in
      if rows.first?.first == "slow" {
        encoding.signal()
        guard release.wait(timeout:.now()+5) == .success else {throw SQLFailure("Fixture encoding timed out")}
      }
      var data=Data(),sizes:[Int]=[]
      for row in rows {let bytes=try JSONEncoder().encode(row);sizes.append(bytes.count);data.append(bytes)}
      return (data,sizes)
    })
    let first=try spool.append([["seed"]]);#expect(first[0]==["seed"])
    let writer=Task.detached {try spool.append([["slow"]])}
    #expect(await signaled(encoding,seconds:2))
    #expect(first.count==1 && first.prefixSnapshot(1000).count==1)
    let reader=Task.detached {let row=first[0];readDone.signal();return row}
    let readable=await signaled(readDone,seconds:0.2)
    release.signal()
    let second=try await writer.value
    #expect(await reader.value==["seed"])
    #expect(readable,"UI readers must not wait for JSON encoding of a later batch")
    #expect(second.count==2 && second[0]==["seed"] && second[1]==["slow"] && first.count==1)
  }
  @Test(arguments:[1000,2000]) func encodingReaderLatencyBenchmark(rowCount:Int) async throws {
    let encoding=DispatchSemaphore(value:0)
    let spool=try ResultSpool(encode:{rows in
      if rows.first?.first != "seed" {encoding.signal()}
      var data=Data(),sizes:[Int]=[]
      let encoder=JSONEncoder()
      for row in rows {let bytes=try encoder.encode(row);sizes.append(bytes.count);data.append(bytes)}
      return (data,sizes)
    })
    let first=try spool.append([["seed"]]);#expect(first[0]==["seed"])
    let batch=(0..<rowCount).map {row in (0..<64).map {column in "\(row):\(column) · "+String(repeating:"research",count:4)}}
    let countStart=ContinuousClock.now
    var sum=0
    for _ in 0..<100_000 {sum+=first.count}
    let countTime=countStart.duration(to:.now)
    #expect(sum==100_000)
    let writer=Task.detached {
      var final=first
      for start in stride(from:0,to:batch.count,by:256) {final=try spool.append(Array(batch[start..<min(start+256,batch.count)]))}
      return final
    }
    #expect(await signaled(encoding,seconds:2))
    let readStart=ContinuousClock.now
    let value=await Task.detached {first[0]}.value
    let readTime=readStart.duration(to:.now)
    let final=try await writer.value
    #expect(value==["seed"] && final.count==rowCount+1 && final[rowCount]==batch.last)
    print("SPOOL_ENCODING_BENCHMARK rows=\(rowCount) columns=64 count100k=\(countTime) cachedRead=\(readTime)")
  }
  @Test func concurrentDefaultWritersPreserveAllRecords() async throws {
    let spool=try ResultSpool()
    let snapshots=try await withThrowingTaskGroup(of:RowCollection.self) {group in
      for batch in 0..<8 {group.addTask {try spool.append((0..<128).map {["\(batch):\($0)"]})}}
      var result:[RowCollection]=[]
      for try await rows in group {result.append(rows)}
      return result
    }
    let final=try #require(snapshots.max(by:{$0.count<$1.count}))
    #expect(final.count==1024 && Set(final.compactMap {$0.first ?? nil}).count==1024)
    #expect(spool.readFailure==nil)
  }
}
