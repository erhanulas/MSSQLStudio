import Foundation
import Testing
@testable import SQLServerKit
struct StartupUpdateTests {
  @Test func explorerMigrationRestoresAllSavedButHonorsExplicitDisconnect() {
    let a=UUID(), b=UUID(), missing=UUID()
    #expect(ExplorerPersistence.selectedIDs(saved:[a,b],previous:nil) == [a,b])
    #expect(ExplorerPersistence.selectedIDs(saved:[a,b],previous:[]) == [])
    #expect(ExplorerPersistence.selectedIDs(saved:[a,b],previous:[b.uuidString,missing.uuidString]) == [b])
  }
  @Test func updateRejectsTraversalAndOldVersions() {
    #expect(ApplicationUpdate.validEntries(["MSSQLStudio.app/Contents/Info.plist"]))
    #expect(!ApplicationUpdate.validEntries(["MSSQLStudio.app/../../bad"]))
    #expect(!ApplicationUpdate.validEntries(["/MSSQLStudio.app/Contents"]))
    #expect(!ApplicationUpdate.validEntries(["Other.app/file"]))
    #expect(ApplicationUpdate.isNewer("0.2.14",than:"0.2.9"))
    #expect(!ApplicationUpdate.isNewer("0.2.13",than:"0.2.14"))
    #expect(!ApplicationUpdate.isNewer("0.2.14",than:"0.2.14"))
    #expect(!ApplicationUpdate.isNewer("../14",than:"0.2.14"))
  }
}

extension StartupUpdateTests {
  @Test func validatesRealSignedUpdateWithoutInstalling() async throws {
    guard let path = ProcessInfo.processInfo.environment["MSSQL_UPDATE_ZIP"] else { return }
    let root = URL(fileURLWithPath:"/tmp").appendingPathComponent("StudioUpdateTest-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let prepared = try await ApplicationUpdate().prepare(zip:URL(fileURLWithPath:path),target:root.appendingPathComponent("MSSQLStudio.app"),currentVersion:"0.2.29")
    #expect(prepared.version == "0.2.30")
    #expect(FileManager.default.fileExists(atPath:prepared.stage.appendingPathComponent("MSSQLStudio.app/Contents/Info.plist").path))
    #expect(!FileManager.default.fileExists(atPath:prepared.target.path))
  }
}

@Suite struct UpdateFeedTests {
  @Test func rejectsInsecureFeedWithoutRequest() async throws {
    do {
      _ = try await ApplicationUpdate().check(feed:URL(string:"http://example.invalid/update.json")!,currentVersion:"0.2.15")
      Issue.record("HTTP feed must fail")
    } catch { #expect(error.localizedDescription.contains("HTTPS")) }
  }
  @Test func githubRepositoryBuildsStablePublicFeedAndRejectsUnsafeURLs() throws {
    #expect(try GitHubUpdateSource.repository(" https://github.com/example/studio.git/ ") == "example/studio")
    #expect(try GitHubUpdateSource.feed("example/studio").absoluteString == "https://github.com/example/studio/releases/latest/download/update.json")
    for input in ["", "example", "../studio", "a/b/../../x", "http://github.com/a/b", "https://evil.example/a/b", "https://user:secret@github.com/a/b", "https://github.com/a/b?token=secret", "https://github.com/a/b/tree/main"] {
      #expect(throws:SQLFailure.self) {try GitHubUpdateSource.repository(input)}
    }
  }
  @Test func decodesReleaseManifest() throws {
    let json = #"{"version":"0.2.16","downloadURL":"https://example.invalid/release.zip","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#
    let release = try JSONDecoder().decode(ApplicationUpdate.Release.self,from:Data(json.utf8))
    #expect(release.version == "0.2.16")
    #expect(release.downloadURL.scheme == "https")
  }
}
