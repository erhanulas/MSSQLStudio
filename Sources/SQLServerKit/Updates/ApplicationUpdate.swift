import Foundation
import CryptoKit
import Darwin

/// Public Releases source. No GitHub credential is embedded in the application.
public enum GitHubUpdateSource {
  public static func repository(_ input:String) throws -> String {
    var value=input.trimmingCharacters(in:.whitespacesAndNewlines)
    if value.hasPrefix("https://") {
      guard let url=URL(string:value),url.host?.lowercased() == "github.com",url.user == nil,url.password == nil,url.port == nil,url.query == nil,url.fragment == nil else {throw SQLFailure("GitHub depo adresini kullanıcı/depo veya https://github.com/kullanıcı/depo olarak girin.")}
      value=url.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
    }
    if value.hasSuffix(".git") {value=String(value.dropLast(4))}
    let parts=value.split(separator:"/",omittingEmptySubsequences:false)
    let allowed=CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
    guard parts.count == 2,parts.allSatisfy({!$0.isEmpty && $0.count<=100 && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains)}) else {throw SQLFailure("Geçerli bir GitHub kullanıcı/depo adresi girin.")}
    return value
  }
  public static func feed(_ input:String) throws -> URL {
    URL(string:"https://github.com/"+(try repository(input))+"/releases/latest/download/update.json")!
  }
}

public struct PreparedApplicationUpdate: Sendable {
  public let stage: URL
  public let target: URL
  public let version: String
}
public actor ApplicationUpdate {
  public struct Release: Codable, Sendable {
    public let version: String
    public let downloadURL: URL
    public let sha256: String
    public let installerURL: URL?
    public let installerSHA256: String?
  }
  typealias ManifestTransport = @Sendable (URLRequest) async throws -> (Data,URLResponse)
  private let manifestTransport:ManifestTransport
  init(manifestTransport:@escaping ManifestTransport) {self.manifestTransport=manifestTransport}
  public func check(feed: URL, currentVersion: String) async throws -> Release? {
    guard feed.scheme == "https",feed.user == nil,feed.password == nil else {throw SQLFailure("Güncelleme adresi HTTPS olmalı.")}
    for attempt in 0..<3 {
      try Task.checkCancellation()
      var address=feed
      // GitHub serves release assets, not its JSON API. Avoid stale CDN redirects.
      if feed.host?.lowercased() == "github.com",feed.path.hasSuffix("/releases/latest/download/update.json"),var parts=URLComponents(url:feed,resolvingAgainstBaseURL:false) {
        parts.queryItems=(parts.queryItems ?? [])+[URLQueryItem(name:"studio_update_check",value:UUID().uuidString)]
        address=parts.url ?? feed
      }
      var request=URLRequest(url:address,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:10)
      request.setValue("application/octet-stream",forHTTPHeaderField:"Accept")
      request.setValue("no-cache",forHTTPHeaderField:"Cache-Control")
      request.setValue("MSSQLStudio-Updater",forHTTPHeaderField:"User-Agent")
      let data:Data,response:URLResponse
      do {(data,response)=try await manifestTransport(request)}
      catch {
        try Task.checkCancellation()
        if let network=error as? URLError {
          if network.code == .cancelled {throw error}
          if attempt<2,[.timedOut,.networkConnectionLost,.cannotConnectToHost,.dnsLookupFailed].contains(network.code) {
            try await Task.sleep(for:.milliseconds(250*(attempt+1)));continue
          }
          throw SQLFailure("Güncelleme sunucusuna ulaşılamadı (ağ kodu \(network.code.rawValue)). İnternet bağlantınızı kontrol edip yeniden deneyin.")
        }
        throw error
      }
      try Task.checkCancellation()
      guard let http=response as? HTTPURLResponse,response.url?.scheme == "https" else {throw SQLFailure("Güncelleme sunucusu güvenli bir HTTPS yanıtı vermedi.")}
      if http.statusCode != 200 {
        if attempt<2,[408,429,500,502,503,504].contains(http.statusCode) {
          try await Task.sleep(for:.milliseconds(250*(attempt+1)));continue
        }
        let detail:String
        switch http.statusCode {
        case 404:detail="Güncelleme dosyası bulunamadı; yayın adresini kontrol edin."
        case 401,403:detail="Güncelleme sunucusu erişimi reddetti; ağ erişimini veya yayın adresini kontrol edin."
        case 429:detail="Güncelleme sunucusunun istek sınırına ulaşıldı; biraz sonra yeniden deneyin."
        case 500...599:detail="Güncelleme sunucusu geçici hata verdi; biraz sonra yeniden deneyin."
        default:detail="Güncelleme sunucusundan beklenmeyen yanıt alındı."
        }
        throw SQLFailure("Güncelleme bilgisi alınamadı (HTTP \(http.statusCode)). "+detail)
      }
      guard !data.isEmpty,data.count<65536 else {throw SQLFailure("Güncelleme bilgisi boş veya boyut sınırını aşıyor.")}
      let release:Release
      do {release=try JSONDecoder().decode(Release.self,from:data)}
      catch {throw SQLFailure("Güncelleme dosyası geçerli JSON biçiminde değil.")}
      guard Self.isNewer(release.version,than:"0"),release.downloadURL.scheme == "https",release.sha256.count == 64,
        release.sha256.allSatisfy({$0.isHexDigit}) else {throw SQLFailure("Güncelleme bilgisi geçersiz.")}
      return Self.isNewer(release.version,than:currentVersion) ? release:nil
    }
    throw SQLFailure("Güncelleme kontrolü tamamlanamadı.")
  }
  public func download(_ release: Release,progress:(@Sendable (UpdateDownloadProgress)->Void)?=nil) async throws -> URL {
    guard release.downloadURL.scheme == "https" else { throw SQLFailure("Paket adresi HTTPS olmalı.") }
    let url:URL,response:URLResponse
    if let progress {
      (url,response)=try await UpdateDownloadObserver(report:progress).download(from:release.downloadURL)
    } else {
      (url,response)=try await URLSession.shared.download(from:release.downloadURL)
    }
    do {
      try Task.checkCancellation()
      guard let http = response as? HTTPURLResponse, http.statusCode == 200,
        response.url?.scheme == "https" else { throw SQLFailure("Güncelleme indirilemedi.") }
      let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
      guard size > 0 && size < 512*1024*1024 else { throw SQLFailure("Paket boyutu geçersiz.") }
      let data = try Data(contentsOf:url,options:.mappedIfSafe)
      let digest = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
      guard digest == release.sha256.lowercased() else { throw SQLFailure("Paket bütünlüğü doğrulanamadı.") }
      return url
    } catch { try? FileManager.default.removeItem(at:url); throw error }
  }
  public nonisolated static func installationCompleted(expected:String,runningVersion:String,bundleURL:URL) -> Bool {
    bundleURL.standardizedFileURL.path == "/Applications/MSSQLStudio.app" && (runningVersion == expected || isNewer(runningVersion,than:expected))
  }
  /// Successful installation is acknowledged silently; failed/incomplete installs retain their marker.
  public nonisolated static func consumeCompletedInstallation(in defaults: UserDefaults, runningVersion: String, bundleURL: URL) -> Bool {
    guard let expected = defaults.string(forKey: "pendingInstallerVersion"),
      installationCompleted(expected: expected, runningVersion: runningVersion, bundleURL: bundleURL) else { return false }
    defaults.removeObject(forKey: "pendingInstallerVersion")
    return true
  }
  /// A separate invocation of the signed app waits without creating NSApplication,
  /// so Installer's must-close check can safely close the interactive application.
  public func waitForInstallation(expected:String,parentProcess:Int32,timeout:Duration = .seconds(1800),target:URL = URL(fileURLWithPath:"/Applications/MSSQLStudio.app")) async -> Bool {
    guard parentProcess > 1,Self.isNewer(expected,than:"0"),let identity=try? PersonalSigningIdentity.requirement() else {return false}
    let clock=ContinuousClock(),deadline=ContinuousClock.now.advanced(by:timeout)
    while clock.now < deadline {
      if Task.isCancelled {return false}
      if kill(parentProcess,0) == -1,errno == ESRCH,
        (try? installedApplicationReady(at:target,expected:expected,identity:identity)) == true {return true}
      do {try await clock.sleep(until:min(deadline,clock.now.advanced(by:.seconds(2))))}catch {return false}
    }
    return false
  }
  public func installedApplicationReady(at app:URL,expected:String) throws -> Bool {
    try installedApplicationReady(at:app,expected:expected,identity:PersonalSigningIdentity.requirement())
  }
  private func installedApplicationReady(at app:URL,expected:String,identity:String) throws -> Bool {
    // Read the plist from disk, bypassing Bundle's cached metadata during replacement.
    guard let data=try? Data(contentsOf:app.appendingPathComponent("Contents/Info.plist")),
      let info=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
      info["CFBundleIdentifier"] as? String == "local.mssqlstudio.app",
      info["CFBundleShortVersionString"] as? String == expected else {return false}
    _ = try run("/usr/bin/codesign",["--verify","--deep","--strict","-R","="+identity,app.path])
    let actual=try run("/usr/bin/codesign",["-d","-r-",app.path]).trimmingCharacters(in:.whitespacesAndNewlines)
    guard actual == "designated => " + identity else {return false}
    return true
  }
  public init() {manifestTransport={request in try await URLSession.shared.data(for:request)}}
  public nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
    let allowed = CharacterSet(charactersIn:"0123456789.")
    guard !candidate.isEmpty, candidate.unicodeScalars.allSatisfy(allowed.contains), !candidate.contains("..") else { return false }
    return candidate.compare(current,options:.numeric) == .orderedDescending
  }
  public nonisolated static func validEntries(_ entries: [String]) -> Bool {
    !entries.isEmpty && entries.allSatisfy { entry in
      let parts = entry.split(separator:"/",omittingEmptySubsequences:false)
      return parts.first == "MSSQLStudio.app" && !parts.contains("..") && !entry.contains("\\") && !entry.hasPrefix("/")
    }
  }
  private func run(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath:executable); process.arguments = arguments
    process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw SQLFailure("Güncelleme paketi doğrulanamadı (\(URL(fileURLWithPath:executable).lastPathComponent)).") }
    return String(decoding:data,as:UTF8.self)
  }
  public func prepare(zip: URL, target: URL, currentVersion: String) throws -> PreparedApplicationUpdate {
    let size = (try zip.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
    guard size > 0 && size < 512*1024*1024 else { throw SQLFailure("Güncelleme ZIP boyutu geçersiz.") }
    let entries = try run("/usr/bin/unzip",["-Z1",zip.path]).split(separator:"\n").map(String.init)
    guard Self.validEntries(entries) else { throw SQLFailure("Güncelleme paketinin dosya yolları geçersiz.") }
    let listing = try run("/usr/bin/zipinfo",["-l",zip.path])
    guard !listing.split(separator:"\n").contains(where: { $0.hasPrefix("l") }) else { throw SQLFailure("Sembolik bağlantılı güncelleme paketleri desteklenmiyor.") }
    let parent = target.deletingLastPathComponent()
    try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
    let stage = parent.appendingPathComponent(".MSSQLStudio-update-" + UUID().uuidString)
    try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    do {
      _ = try run("/usr/bin/ditto",["-x","-k",zip.path,stage.path])
      let app = stage.appendingPathComponent("MSSQLStudio.app")
      let identity = try PersonalSigningIdentity.requirement()
      _ = try run("/usr/bin/codesign",["--verify","--deep","--strict","-R","="+identity,app.path])
      let actual = try run("/usr/bin/codesign",["-d","-r-",app.path]).trimmingCharacters(in:.whitespacesAndNewlines)
      guard actual == "designated => " + identity else {throw SQLFailure("Güncellemenin kalıcı imza kimliği uyuşmuyor.") }
      let data = try Data(contentsOf:app.appendingPathComponent("Contents/Info.plist"))
      let info = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any]
      guard info?["CFBundleIdentifier"] as? String == "local.mssqlstudio.app", let version = info?["CFBundleShortVersionString"] as? String, Self.isNewer(version,than:currentVersion) else { throw SQLFailure("Bu paket MSSQL Studio için daha yeni bir sürüm değil.") }
      return PreparedApplicationUpdate(stage:stage,target:target,version:version)
    } catch { try? FileManager.default.removeItem(at:stage); throw error }
  }
  public struct Installer: Sendable {
    public let directory:URL
    public let package:URL
    public let version:String
  }
  public func downloadInstaller(_ release:Release,progress:(@Sendable (UpdateDownloadProgress)->Void)?=nil) async throws -> URL {
    guard let url=release.installerURL, let sha=release.installerSHA256, url.scheme == "https", sha.count == 64, sha.allSatisfy({$0.isHexDigit}) else {
      throw SQLFailure("Bu yayın uygulama içi PKG güncellemesini desteklemiyor. GitHub yayınındaki PKG paketini kullanın.")
    }
    return try await download(Release(version:release.version,downloadURL:url,sha256:sha,installerURL:nil,installerSHA256:nil),progress:progress)
  }
  public func prepareInstaller(package:URL,expectedVersion:String,currentVersion:String) throws -> Installer {
    guard Self.isNewer(expectedVersion,than:currentVersion) else {throw SQLFailure("Kurulum sürümü güncel sürümden yeni değil.")}
    let fm=FileManager.default
    let directory=fm.temporaryDirectory.appendingPathComponent("MSSQLStudio-installer-"+UUID().uuidString)
    try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    do {
      let copy=directory.appendingPathComponent("MSSQLStudio-"+expectedVersion+".pkg")
      try fm.copyItem(at:package,to:copy)
      try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:copy.path)
      let expanded=directory.appendingPathComponent("expanded")
      _ = try run("/usr/sbin/pkgutil",["--expand-full",copy.path,expanded.path])
      let component=expanded.appendingPathComponent("MSSQLStudio-component.pkg")
      let payload=component.appendingPathComponent("Payload/Applications/MSSQLStudio.app")
      guard !fm.fileExists(atPath:component.appendingPathComponent("Scripts").path) else {throw SQLFailure("Kurulum paketi beklenmeyen betikler içeriyor.")}
      let identity=try PersonalSigningIdentity.requirement()
      _ = try run("/usr/bin/codesign",["--verify","--deep","--strict","-R","="+identity,payload.path])
      let actual=try run("/usr/bin/codesign",["-d","-r-",payload.path]).trimmingCharacters(in:.whitespacesAndNewlines)
      guard actual == "designated => " + identity else {throw SQLFailure("Kurulum uygulamasının imza kimliği uyuşmuyor.")}
      let info=try PropertyListSerialization.propertyList(from:Data(contentsOf:payload.appendingPathComponent("Contents/Info.plist")),format:nil) as? [String:Any]
      guard info?["CFBundleIdentifier"] as? String == "local.mssqlstudio.app",info?["CFBundleShortVersionString"] as? String == expectedVersion else {throw SQLFailure("Kurulum paketinin uygulama kimliği veya sürümü uyuşmuyor.")}
      try fm.removeItem(at:expanded)
      return Installer(directory:directory,package:copy,version:expectedVersion)
    } catch {try? fm.removeItem(at:directory);throw error}
  }
}
