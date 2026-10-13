import Foundation
import Testing
@testable import SQLServerKit

struct ExplorerOrganizationTests {
  @Test func foldersPersistMembershipNestedPathsAndInheritedColorsWithoutChangingProfiles() throws {
    var model=ExplorerOrganization()
    let parent=try model.create("Üretim"),child=try model.create("Raporlar",parent:parent),server=UUID()
    try model.assign(server,to:child);try model.setColor(parent,hex:"#aabbcc")
    let restored=try ExplorerOrganization.load(JSONEncoder().encode(model))
    #expect(restored == model && restored.path(child)=="Üretim / Raporlar")
    #expect(restored.assignments[server]==child && restored.color(for:server)=="AABBCC")
    try model.setColor(child,hex:"238B65");#expect(model.color(for:server)=="238B65")
    try model.setColor(child,hex:nil);#expect(model.color(for:server)=="AABBCC")
  }
  @Test func movesRejectCyclesAndDuplicateNamesAtomically() throws {
    var model=ExplorerOrganization()
    let a=try model.create("A"),b=try model.create("B",parent:a)
    let original=model
    #expect(throws:SQLFailure.self) {try model.move(a,to:b)}
    #expect(model == original)
    #expect(throws:SQLFailure.self) {try model.create("a")}
    #expect(throws:SQLFailure.self) {try model.rename(b,name:" ")}
    try model.move(b,to:nil);#expect(model.path(b)=="B")
  }
  @Test func removingFolderPromotesChildrenAndPreservesAllConnectionIdentities() throws {
    var model=ExplorerOrganization()
    let parent=try model.create("Group"),nested=try model.create("Reports",parent:parent)
    _ = try model.create("Reports")
    let server=UUID(),nestedServer=UUID()
    try model.assign(server,to:parent);try model.assign(nestedServer,to:nested)
    try model.remove(parent)
    #expect(model.assignments[server]==nil && model.assignments[nestedServer]==nested)
    #expect(model.path(nested)=="Reports (2)" && model.groups.count==2)
    #expect(try ExplorerOrganization.load(JSONEncoder().encode(model)) == model)
  }
  @Test func invalidPersistenceDepthAndColorCannotCorruptOrganization() throws {
    var model=ExplorerOrganization(),parent:UUID?
    for index in 0..<8 {parent=try model.create("Level \(index)",parent:parent)}
    #expect(throws:SQLFailure.self) {try model.create("Too deep",parent:parent)}
    let original=model
    #expect(throws:SQLFailure.self) {try model.setColor(parent!,hex:"GG0000")}
    #expect(model == original)
    #expect(throws:(any Error).self) {try ExplorerOrganization.load(Data("broken".utf8))}
    #expect(throws:SQLFailure.self) {try ExplorerOrganization.load(Data(repeating:32,count:256_001))}
  }
}
