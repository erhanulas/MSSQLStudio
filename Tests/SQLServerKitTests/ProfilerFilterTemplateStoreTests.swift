import Foundation
import Testing
@testable import SQLServerKit

struct ProfilerFilterTemplateStoreTests {
  private func value(name:String="İstemci SQL") throws -> ProfilerFilterTemplate {
    var capture=SQLProfiler.Configuration();capture.database="DB-A";capture.application="App-A";capture.host="HOST-A";capture.login="Login-A";capture.clientPID="123";capture.sessionID="71";capture.sqlLike="%SELECT%";capture.sqlNotLike="%internal%";capture.minimumDurationMS=20
    var filter=SQLProfilerFiltering.Filter();filter.hideInformational=false;filter.sqlSearch="stok"
    filter.rules=[.init(column:.reads,comparison:.atLeast,value:"10")]
    var column=ColumnRule();column.operation = .notContains;column.first="ignore";column.choices=[.null,.text(""),.text("Özel")]
    filter.columnRules[.message]=column
    return try ProfilerFilterTemplate(name:name,configuration:capture,displayFilter:filter)
  }
  @Test func savesAllFiltersAcrossStoreInstancesAndKeepsNullDistinctFromEmpty() async throws {
    let folder=URL(fileURLWithPath:"/tmp/ProfilerTemplate-"+UUID().uuidString);defer {try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("templates.json"),store=ProfilerFilterTemplateStore(url:url),first=try value()
    #expect(try await store.load().isEmpty)
    _=try await store.save(first)
    let reopened=try await ProfilerFilterTemplateStore(url:url).load()
    #expect(reopened==[first])
    #expect(reopened[0].displayFilter.columnRules[.message]?.choices==[.null,.text(""),.text("Özel")])
    var updated=first;updated.name="Yeni ad";updated.configuration.host="HOST-B"
    _=try await store.save(updated)
    #expect(try await store.load()==[updated])
    #expect(try await store.remove(first.id).isEmpty)
    let permissions=try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue==0o600)
  }
  @Test func duplicateInvalidAndCorruptFilesNeverOverwriteExistingTemplates() async throws {
    let folder=URL(fileURLWithPath:"/tmp/ProfilerTemplate-"+UUID().uuidString);defer {try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("templates.json"),store=ProfilerFilterTemplateStore(url:url),first=try value(name:"Genel")
    _=try await store.save(first)
    let original=try Data(contentsOf:url)
    await #expect(throws:(any Error).self) {try await store.save(value(name:"genel"))}
    #expect(try Data(contentsOf:url)==original)
    var invalid=first;invalid.configuration.clientPID="invalid"
    await #expect(throws:(any Error).self) {try await store.save(invalid)}
    #expect(try Data(contentsOf:url)==original)
    let corrupt=Data("{bad".utf8);try corrupt.write(to:url)
    await #expect(throws:(any Error).self) {try await store.save(first)}
    #expect(try Data(contentsOf:url)==corrupt)
    let newer=Data("{\"version\":2,\"templates\":[]}".utf8);try newer.write(to:url)
    await #expect(throws:(any Error).self) {try await store.remove(first.id)}
    #expect(try Data(contentsOf:url)==newer)
  }
  @Test func rejectsInvalidDisplayAndCaptureBeforeSaving() throws {
    var capture=SQLProfiler.Configuration();capture.sessionID="32768"
    #expect(throws:(any Error).self) {try ProfilerFilterTemplate(name:"Invalid",configuration:capture,displayFilter:.init())}
    var filter=SQLProfilerFiltering.Filter();filter.rules=[.init(column:.duration,comparison:.atLeast,value:"abc")]
    #expect(throws:(any Error).self) {try ProfilerFilterTemplate(name:"Invalid",configuration:.init(),displayFilter:filter)}
    #expect(throws:(any Error).self) {try value(name:" ")}
  }
}
