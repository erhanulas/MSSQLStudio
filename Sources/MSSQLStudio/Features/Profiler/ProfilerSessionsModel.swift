import AppKit
import SQLServerKit

/// Explicit server-session inspection uses its own bounded connection, never the capture worker.
@MainActor final class ProfilerSessionsModel:ObservableObject {
  typealias Reader=@Sendable (String) async throws -> Execution
  @Published private(set) var sessions:[SQLProfiler.ServerSession]=[]
  @Published private(set) var busy=false
  @Published private(set) var error=""
  private let reader:Reader
  init(server:ConnectedServer,reader:Reader?=nil) {
    var profile=server.profile;profile.database="master"
    let snapshot=profile,password=server.password
    self.reader=reader ?? {sql in
      let connection=ODBCConnection()
      do {
        try await connection.connect(snapshot,password:password)
        var limits=Limits();limits.rows=501;limits.resultSets=1;limits.cellBytes=1024;limits.totalBytes=524288;limits.timeout=10
        let result=try await connection.execute(sql,limits:limits)
        await connection.disconnect();return result
      } catch {await connection.disconnect();throw error}
    }
  }
  func refresh() async {
    guard !busy else {return};busy=true;defer {busy=false}
    do {sessions=try SQLProfiler.decodeSessions(await reader(SQLProfiler.sessionsSQL));error=""}
    catch {self.error=error.localizedDescription}
  }
  func remove(_ session:SQLProfiler.ServerSession,currentSession:String?) async {
    guard !busy,session.name != currentSession,sessions.contains(session) else {return}
    busy=true;defer {busy=false}
    do {
      let result=try await reader(SQLProfiler.dropSQL(name:session.name))
      guard !result.partial,!result.stoppedEarly else {throw SQLFailure("Oturum temizliği tamamlanamadı; listeyi yenileyin.")}
      sessions=try SQLProfiler.decodeSessions(await reader(SQLProfiler.sessionsSQL));error=""
    } catch {self.error=error.localizedDescription}
  }
}
