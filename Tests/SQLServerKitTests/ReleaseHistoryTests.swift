import Foundation
import Testing
@testable import SQLServerKit

@Suite struct ReleaseHistoryTests {
  @Test func bundledHistoryIncludesCurrentAndPreviousGitHubRelease() throws {
    let notes = try ReleaseHistory.bundled()
    #expect(notes.first?.version == "0.2.31")
    #expect(notes.contains(where: { $0.version == "0.2.30" }))
    #expect(notes.allSatisfy { !$0.changes.isEmpty })
  }
  @Test func historySortsNumericallyAndKeepsChangesWithTheirVersion() throws {
    let data = Data(#"[{"version":"0.2.9","date":"2026-10-09","title":"Old","changes":["Old change"]},{"version":"0.2.31","date":"2026-10-10","title":"New","changes":["New change"]}]"#.utf8)
    let notes = try ReleaseHistory.decode(data)
    #expect(notes.map(\.version) == ["0.2.31", "0.2.9"])
    #expect(notes.first?.changes == ["New change"])
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
