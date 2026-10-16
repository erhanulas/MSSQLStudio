import AppKit
import SQLServerKit

/// Read-only Explorer metadata and retained trace values; never uses the capture connection.
@MainActor final class ProfilerChoicesModel:ObservableObject {
  struct ExplorerSnapshot {
    var databases:[String]
    /// nil means the Explorer login branch has not been loaded yet.
    var logins:[String]?
  }
  typealias Reader=@MainActor (String,Limits) async throws -> Execution
  private let server:ConnectedServer
  private let profile:ServerProfile
  private let explorer:(()->ExplorerSnapshot)?
  private let reader:Reader
  private var task:Task<Void,Never>?
  private var loginGeneration:UUID?
  @Published private(set) var databases:[String]=[]
  @Published private(set) var logins:[String]=[]
  @Published private(set) var loading=false
  @Published private(set) var error=""
  @Published private(set) var note=""
  private var options:[SQLProfilerFiltering.Column:[String]]=[:]
  @Published private(set) var captured:[SQLProfilerFiltering.Column:[String]]=[:]
  init(server:ConnectedServer,explorer:(()->ExplorerSnapshot)?=nil,reader:Reader?=nil) {
    self.server=server;profile=server.profile;self.explorer=explorer
    self.reader=reader ?? {sql,limits in try await server.catalog(sql,database:"master",limits:limits)}
    databases=Self.sorted(server.databases.map(\.name));logins=Self.sorted([profile.login]);rebuildOptions()
  }
  deinit {task?.cancel()}
  private static func sorted(_ values:[String])->[String] {Array(Set(values.filter {!$0.isEmpty})).sorted {$0.localizedStandardCompare($1) == .orderedAscending}}
  func values(for column:SQLProfilerFiltering.Column)->[String] {
    options[column] ?? [""]
  }
  private func rebuildOptions() {
    for column in [SQLProfilerFiltering.Column.database,.login,.application,.host,.clientPID,.session] {
      let existing=column == .database ? databases:column == .login ? logins:[]
      options[column]=[""]+Self.sorted(existing+(captured[column] ?? []))
    }
  }
  func updateCaptured(_ events:[SQLProfiler.Event]) {
    var sets:[SQLProfilerFiltering.Column:Set<String>]=[:]
    for event in events {
      for column in [SQLProfilerFiltering.Column.database,.login,.application,.host,.clientPID,.session] {
        let value=column.value(event)
        if !value.isEmpty {sets[column,default:[]].insert(value)}
      }
    }
    captured=sets.mapValues {Self.sorted(Array($0))};rebuildOptions()
  }
  /// Existing Explorer lists are instant; only missing/explicitly refreshed login metadata is read.
  func refresh(automatic:Bool=false) {
    guard !loading else {return}
    guard profile.hasSameConnectionSettings(as:server.profile) else {
      error="Bağlantı ayarları değişti; Profiler penceresini yeniden açın.";return
    }
    let snapshot=explorer?() ?? ExplorerSnapshot(databases:server.databases.map(\.name),logins:nil)
    databases=Self.sorted(snapshot.databases)
    if let names=snapshot.logins {logins=Self.sorted(names+[profile.login])}
    rebuildOptions()
    error="";note="Listeler sunucudaki görünürlük izinleriyle sınırlıdır. Uygulama/Host/PID/SPID seçenekleri yakalanan olaylardan gelir; listede olmayan değer elle girilebilir."
    if automatic,snapshot.logins != nil || loginGeneration==server.generation {return}
    guard server.online || server.catalogFixture != nil || server.asyncCatalogFixture != nil else {
      note="Çevrimdışı: Explorer’daki mevcut listeler kullanılıyor. Yeniden bağlantı kurulmadı.";return
    }
    let generation=server.generation
    loading=true
    task=Task { [weak self,reader] in
      var limits=Limits();limits.rows=5001;limits.resultSets=1;limits.totalBytes=2_000_000;limits.timeout=10
      do {
        let result=try await reader(Catalog.objects(.logins),limits)
        try Task.checkCancellation()
        guard let self else {return}
        defer {loading=false;task=nil}
        guard generation==server.generation,profile.hasSameConnectionSettings(as:server.profile) else {
          error="Bağlantı değişti; eski seçenekler uygulanmadı. Listeyi yeniden yükleyin.";return
        }
        guard !result.partial,!result.stoppedEarly,result.results.count==1,let rows=result.results.first,!rows.truncated,
          rows.values.count<=5000,rows.fields.count==4,rows.fields[0].name.lowercased()=="principal_id",rows.fields[1].name.lowercased()=="name",rows.fields[3].name.lowercased()=="type_desc",rows.values.allSatisfy({$0.count==4 && $0[1] != nil}) else {throw SQLFailure("Login listesi eksik veya sınırı aşıyor; önceki seçenekler korundu.")}
        logins=Self.sorted(Catalog.rows(result).map(\.name)+[profile.login]);loginGeneration=generation;rebuildOptions()
      } catch {
        guard let self else {return};loading=false;task=nil
        if !(error is CancellationError) {self.error=error.localizedDescription}
      }
    }
  }
  func cancel() {task?.cancel()}
}
