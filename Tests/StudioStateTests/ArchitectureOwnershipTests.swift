import Foundation
import SQLServerKit
import Testing
@testable import MSSQLStudio

private actor ArchitectureGate<Value:Sendable> {
  private var waiting:[String:CheckedContinuation<Value,Never>]=[:]
  private(set) var started:[String]=[]
  func wait(_ key:String) async -> Value {
    started.append(key)
    return await withCheckedContinuation {waiting[key]=$0}
  }
  func resume(_ key:String,_ value:Value) {waiting.removeValue(forKey:key)?.resume(returning:value)}
}

@MainActor @Suite(.serialized) struct ArchitectureOwnershipTests {
  private func eventually(_ condition:() async -> Bool) async throws {
    for _ in 0..<200 {
      if await condition() {return}
      try await Task.sleep(for:.milliseconds(5))
    }
    #expect(await condition(),"Asenkron sahiplik koşulu tamamlanmadı")
  }
  @Test func explorerQueuesLatestRequestWithoutConcurrentSearchOrStalePublication() async throws {
    let gate=ArchitectureGate<ExplorerSearchController.Output>()
    let controller=ExplorerSearchController(delay:.zero) {request in await gate.wait(request.text)}
    let output=ExplorerSearchController.Output(matches:[],pending:0,truncated:false,staleDatabases:[])
    var published:[String]=[]
    func search(_ text:String) {
      controller.search(.init(profile:ServerProfile(),databases:["master"],text:text,operation:0,folder:nil)) {_ in published.append(text)}
    }
    search("old")
    try await eventually {await gate.started == ["old"]}
    search("intermediate");search("latest")
    #expect(await gate.started == ["old"])
    await gate.resume("old",output)
    try await eventually {await gate.started == ["old","latest"]}
    await gate.resume("latest",output)
    try await eventually {published == ["latest"]}
    search("cancelled")
    try await eventually {await gate.started.last == "cancelled"}
    controller.cancel();search("after-cancel")
    await gate.resume("cancelled",output)
    try await eventually {await gate.started.last == "after-cancel"}
    await gate.resume("after-cancel",output)
    try await eventually {published == ["latest","after-cancel"]}
    #expect(!(await gate.started).contains("intermediate"))
  }
  @Test func resultProjectionRejectsLateSnapshotEvenWhenWorkerIgnoresCancellation() async throws {
    let gate=ArchitectureGate<[Int]>()
    let controller=ResultProjectionController {request in await gate.wait(request.search)}
    var published:[[Int]]=[]
    func project(_ text:String) {
      controller.project(.init(rows:Rows(),search:text,rules:[:],sortColumn:nil,ascending:true),debounce:false) {result in
        if case .success(let indices)=result,let indices {published.append(indices)}
      }
    }
    project("old")
    try await eventually {await gate.started.contains("old")}
    project("new")
    try await eventually {await gate.started.contains("new")}
    await gate.resume("new",[2])
    try await eventually {published == [[2]]}
    await gate.resume("old",[1])
    project("barrier")
    try await eventually {await gate.started.contains("barrier")}
    await gate.resume("barrier",[3])
    try await eventually {published == [[2],[3]]}
    #expect(published == [[2],[3]])
  }
  @Test func explorerModelKeepsUnchangedNodesAndReplacesOnlyChangedGeneration() {
    let a=ConnectedServer(profile:ServerProfile(name:"A"),password:"")
    let b=ConnectedServer(profile:ServerProfile(name:"B"),password:"")
    a.online=false;b.online=false
    let tree=ExplorerTreeModel()
    #expect(!tree.synchronizeServers([a,b]))
    let first=tree.roots[0],second=tree.roots[1],child=first.children[0]
    a.startupError="offline"
    #expect(!tree.synchronizeServers([b,a]))
    #expect(tree.roots[0] === second && tree.roots[1] === first)
    #expect(first.children[0] === child && first.error == "offline")
    a.generation=UUID()
    #expect(!tree.synchronizeServers([b,a]))
    #expect(tree.roots[0] === second && tree.roots[1] !== first)
    #expect(tree.synchronizeServers([a]))
    #expect(tree.roots.count == 1 && tree.roots[0].server === a)
  }
}
