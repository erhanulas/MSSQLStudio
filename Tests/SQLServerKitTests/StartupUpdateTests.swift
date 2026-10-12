import Foundation
import Testing
import Security
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
    let prepared = try await ApplicationUpdate().prepare(zip:URL(fileURLWithPath:path),target:root.appendingPathComponent("MSSQLStudio.app"),currentVersion:"0")
    #expect(ApplicationUpdate.isNewer(prepared.version,than:"0"))
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

@Suite struct PersonalSigningTests {
  @Test func pinnedRequirementParsesAndAdhocReplacementIsRejected() async throws {
    let requirement = try PersonalSigningIdentity.requirement()
    var compiled: SecRequirement?
    #expect(SecRequirementCreateWithString(requirement as CFString,SecCSFlags(),&compiled) == errSecSuccess)
    #expect(compiled != nil)
    guard let path = ProcessInfo.processInfo.environment["MSSQL_UPDATE_ZIP"] else {return}
    let root = URL(fileURLWithPath:"/tmp/StudioWrongSigner-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:root)}
    func run(_ executable:String,_ arguments:[String]) throws {
      let process=Process();process.executableURL=URL(fileURLWithPath:executable);process.arguments=arguments
      process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
      try process.run();process.waitUntilExit()
      #expect(process.terminationStatus == 0)
    }
    let extracted=root.appendingPathComponent("extracted")
    try run("/usr/bin/ditto",["-x","-k",path,extracted.path])
    let app=extracted.appendingPathComponent("MSSQLStudio.app")
    try run("/usr/bin/codesign",["--force","--sign","-",app.path])
    try run("/usr/bin/codesign",["--verify","--deep","--strict",app.path])
    let archive=root.appendingPathComponent("wrong.zip")
    try run("/usr/bin/ditto",["-c","-k","--keepParent","--norsrc",app.path,archive.path])
    do {
      _ = try await ApplicationUpdate().prepare(zip:archive,target:root.appendingPathComponent("target/MSSQLStudio.app"),currentVersion:"0")
      Issue.record("A valid ad-hoc signature must not replace the pinned personal identity")
    } catch is SQLFailure { }
  }
}

extension StartupUpdateTests {
  @Test func installerValidatesPinnedPayloadWithoutInstalling() async throws {
    guard let path=ProcessInfo.processInfo.environment["MSSQL_UPDATE_PKG"] else {return}
    let package=URL(fileURLWithPath:path)
    let version=package.deletingPathExtension().lastPathComponent.replacingOccurrences(of:"MSSQLStudio-",with:"")
    let prepared=try await ApplicationUpdate().prepareInstaller(package:package,expectedVersion:version,currentVersion:"0")
    defer {try? FileManager.default.removeItem(at:prepared.directory)}
    #expect(prepared.version == version)
    #expect(FileManager.default.fileExists(atPath:prepared.package.path))
    #expect(!FileManager.default.fileExists(atPath:prepared.directory.appendingPathComponent("expanded").path))
    do {
      _ = try await ApplicationUpdate().prepareInstaller(package:package,expectedVersion:"999.0",currentVersion:"0")
      Issue.record("Mismatched payload version was accepted")
    } catch is SQLFailure {}
  }
  @Test func oldFeedCannotSilentlyUseLegacyUpdateHelper() async throws {
    let release=try JSONDecoder().decode(ApplicationUpdate.Release.self,from:Data(#"{"version":"1.0","downloadURL":"https://example.invalid/release.zip","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#.utf8))
    do {_ = try await ApplicationUpdate().downloadInstaller(release);Issue.record("ZIP-only feed accepted")}
    catch {#expect(error.localizedDescription.contains("PKG"))}
  }
}

extension StartupUpdateTests {
  @Test func installationCompletionRequiresNewVersionAtCanonicalLocation() {
    #expect(ApplicationUpdate.installationCompleted(expected:"0.2.52",runningVersion:"0.2.52",bundleURL:URL(fileURLWithPath:"/Applications/MSSQLStudio.app")))
    #expect(!ApplicationUpdate.installationCompleted(expected:"0.2.52",runningVersion:"0.2.50",bundleURL:URL(fileURLWithPath:"/Applications/MSSQLStudio.app")))
    #expect(!ApplicationUpdate.installationCompleted(expected:"0.2.52",runningVersion:"0.2.52",bundleURL:URL(fileURLWithPath:"/tmp/MSSQLStudio.app")))
  }
}

@Suite struct SilentInstallationTests {
  @Test func acknowledgesOnlyCompletedCanonicalInstallation() throws {
    let name = "local.mssqlstudio.install-test." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let canonical = URL(fileURLWithPath: "/Applications/MSSQLStudio.app")
    defaults.set("0.2.66", forKey: "pendingInstallerVersion")
    #expect(!ApplicationUpdate.consumeCompletedInstallation(in: defaults, runningVersion: "0.2.65", bundleURL: canonical))
    #expect(defaults.string(forKey: "pendingInstallerVersion") == "0.2.66")
    #expect(!ApplicationUpdate.consumeCompletedInstallation(in: defaults, runningVersion: "0.2.69", bundleURL: URL(fileURLWithPath: "/tmp/MSSQLStudio.app")))
    #expect(defaults.string(forKey: "pendingInstallerVersion") == "0.2.66")
    #expect(ApplicationUpdate.consumeCompletedInstallation(in: defaults, runningVersion: "0.2.69", bundleURL: canonical))
    #expect(defaults.string(forKey: "pendingInstallerVersion") == nil)
    #expect(!ApplicationUpdate.consumeCompletedInstallation(in: defaults, runningVersion: "0.2.69", bundleURL: canonical))
  }
  @Test func rejectsUnsignedCredentialAgentBeforeSendingData() throws {
    let agent = CredentialAgent(executable: URL(fileURLWithPath: "/usr/bin/true"), testService: nil, testKeychain: nil)
    #expect(throws: SQLFailure.self) { try agent.request("save", account: UUID(), data: Data("synthetic-only".utf8)) }
  }
}
