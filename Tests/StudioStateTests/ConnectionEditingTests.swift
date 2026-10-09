import Foundation
import SQLServerKit
import Testing

@testable import MSSQLStudio

@MainActor @Suite(.serialized) struct ConnectionEditingTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func editsPreserveOrReplaceSessionsAndRejectUnsafeChanges() async throws {
    let password = try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let state = StudioState()
    state.historyEnabled = false
    state.recoveryEnabled = false
    let server = try await state.connect(
      ServerProfile(trustCertificate: true, visibleDatabases: ["master"]), password: password,
      save: false)
    let doc = state.newQuery(server: server)
    await doc.task?.value
    #expect(doc.state == .ready)
    doc.sql = "CREATE TABLE #StudioEditSession (id int); SELECT @@SPID;"
    doc.execute()
    await doc.task?.value
    let initialID = doc.results.last?.values.first?.first.flatMap { $0 }
    var profile = server.profile
    profile.name = "Local Test Appearance"
    profile.appearance = ServerAppearance(environment: .live, colorHex: "#D92D20")
    _ = try await state.connect(profile, password: password, save: false)
    let same = try await doc.connection.execute(
      "SELECT @@SPID, OBJECT_ID('tempdb..#StudioEditSession');")
    #expect(same.results.first?.values.first?[0] == initialID)
    #expect(same.results.first?.values.first?[1] != nil)
    #expect(server.profile.appearance?.badge == "Canlı")
    let token = server.generation
    var invalid = profile
    invalid.login = "StudioMissing_" + UUID().uuidString
    do {
      _ = try await state.connect(invalid, password: "test-only-invalid-password", save: false)
      Issue.record("Invalid login must fail")
    } catch { #expect(!error.localizedDescription.contains("test-only-invalid-password")) }
    #expect(server.generation == token)
    #expect(server.profile == profile)
    #expect(doc.state == .ready)
    let stillConnected = try await doc.connection.execute(
      "SELECT OBJECT_ID('tempdb..#StudioEditSession');")
    #expect(stillConnected.results.first?.values.first?[0] != nil)
    doc.sql = "BEGIN TRANSACTION;"
    doc.execute()
    await doc.task?.value
    #expect(doc.transactionCount == 1)
    var alternate = profile
    alternate.host = "127.0.0.1"
    do {
      _ = try await state.connect(alternate, password: password, save: false)
      Issue.record("Open transaction must prevent replacing the session")
    } catch { #expect(error.localizedDescription.contains("transaction")) }
    #expect(server.generation == token)
    doc.sql = "ROLLBACK;"
    doc.execute()
    await doc.task?.value
    #expect(doc.transactionCount == 0)
    doc.sql = "WAITFOR DELAY '00:00:15'; SELECT 1;"
    doc.execute()
    let pending = doc.task
    do {
      _ = try await state.connect(alternate, password: password, save: false)
      Issue.record("A running query must prevent replacing the session")
    } catch { #expect(error.localizedDescription.contains("çalışan")) }
    doc.cancel()
    await pending?.value
    #expect(server.generation == token)
    doc.sql = "SELECT N'keep this text';"
    doc.savedText = doc.sql
    _ = try await state.connect(alternate, password: password, save: false)
    await doc.task?.value
    #expect(doc.state == .ready)
    #expect(doc.sql == "SELECT N'keep this text';")
    #expect(doc.savedText == doc.sql)
    #expect(doc.results.isEmpty)  // No automatic execution or results from the old endpoint.
    #expect(server.generation != token)
    let newSession = try await doc.connection.execute(
      "SELECT OBJECT_ID('tempdb..#StudioEditSession');")
    #expect(newSession.results.first?.values.first?[0] == nil)
    await doc.connection.disconnect()
    await server.metadata.disconnect()
  }
}
