import Foundation
import Testing
@testable import SQLServerKit

@Suite struct ReleaseHistoryTests {
  @Test func bundledHistoryIsOrderedAndContainsUsableReleaseNotes() throws {
    let notes = try ReleaseHistory.bundled()
    #expect(!notes.isEmpty)
    #expect(Set(notes.map(\.version)).count == notes.count)
    #expect(zip(notes, notes.dropFirst()).allSatisfy { ApplicationUpdate.isNewer($0.version,than:$1.version) })
    #expect(notes.allSatisfy { !$0.changes.isEmpty })
  }
  @Test func historySortsNumericallyAndKeepsChangesWithTheirVersion() throws {
    let data = Data(#"[{"version":"0.2.9","date":"2026-10-09","title":"Old","changes":["Old change"]},{"version":"0.2.31","date":"2026-10-10","title":"New","changes":["New change"]}]"#.utf8)
    let notes = try ReleaseHistory.decode(data)
    #expect(notes.map(\.version) == ["0.2.31", "0.2.9"])
    #expect(notes.first?.changes == ["New change"])
  }
  @Test func updateRangeExcludesInstalledAndFutureVersions() throws {
    let data=Data(#"[{"version":"0.2.31","date":"2026-10-10","title":"Latest","changes":["Latest change"]},{"version":"0.2.30","date":"2026-10-10","title":"Between","changes":["Middle change"]},{"version":"0.2.29","date":"2026-10-09","title":"Installed","changes":["Old change"]}]"#.utf8)
    let notes=try ReleaseHistory.decode(data)
    #expect(try ReleaseHistory.updates(notes,after:"0.2.29",through:"0.2.31").map(\.version)==["0.2.31","0.2.30"])
    #expect(try ReleaseHistory.updates(notes,after:"0.2.29",through:"0.2.30").map(\.version)==["0.2.30"])
    #expect(throws:(any Error).self) {try ReleaseHistory.updates(notes,after:"0.2.29",through:"0.2.32")}
  }
  @Test func remoteNotesUseExactTagAndNeverRequestInstaller() async throws {
    let notes=Data(#"[{"version":"0.2.31","date":"2026-10-10","title":"Latest","changes":["Latest change"]}]"#.utf8)
    let release=ApplicationUpdate.Release(version:"0.2.31",downloadURL:URL(string:"https://example.invalid/app.zip")!,sha256:String(repeating:"a",count:64),installerURL:nil,installerSHA256:nil)
    let feed=try GitHubUpdateSource.feed("example/studio")
    let expected=try GitHubUpdateSource.releaseNotesURL(feed:feed,version:release.version)
    #expect(expected.absoluteString=="https://raw.githubusercontent.com/example/studio/v0.2.31/Sources/SQLServerKit/Resources/ReleaseNotes.json")
    let updater=ApplicationUpdate(manifestTransport:{request in
      #expect(request.url==expected && request.timeoutInterval==10 && request.value(forHTTPHeaderField:"Authorization")==nil)
      return (notes,HTTPURLResponse(url:expected,statusCode:200,httpVersion:nil,headerFields:nil)!)
    })
    #expect(try await updater.releaseNotes(feed:feed,release:release,currentVersion:"0.2.29").count==1)
    #expect(throws:(any Error).self) {try GitHubUpdateSource.releaseNotesURL(feed:feed,version:"../31")}
    #expect(throws:(any Error).self) {try GitHubUpdateSource.releaseNotesURL(feed:URL(string:"https://example.invalid/feed")!,version:"0.2.31")}
    let oversized=ApplicationUpdate(manifestTransport:{_ in (Data(repeating:32,count:512*1024+1),HTTPURLResponse(url:expected,statusCode:200,httpVersion:nil,headerFields:nil)!)})
    await #expect(throws:(any Error).self) {try await oversized.releaseNotes(feed:feed,release:release,currentVersion:"0.2.29")}
  }
  @Test func malformedHistoryCannotMasqueradeAsReleaseNotes() throws {
    let valid = #"{"version":"0.2.31","date":"2026-10-10","title":"Title","changes":["Change"]}"#
    for json in ["[]", "[\(valid),\(valid)]", "[" + valid.replacingOccurrences(of:"0.2.31",with:"../31") + "]", "[" + valid.replacingOccurrences(of:"2026-10-10",with:"2026-02-30") + "]", "[" + valid.replacingOccurrences(of:"[\"Change\"]",with:"[]") + "]"] {
      #expect(throws: (any Error).self) { try ReleaseHistory.decode(Data(json.utf8)) }
    }
  }
  @Test func installedVersionComesFromBundleMetadataRatherThanNewestHistory() {
    let identity = ApplicationIdentity(info: ["CFBundleShortVersionString":"0.2.29", "CFBundleVersion":"30"])
    #expect(identity.version == "0.2.29")
    #expect(identity.build == "30")
    #expect(ApplicationIdentity(info: [:]).version == "Bilinmiyor")
  }
}
