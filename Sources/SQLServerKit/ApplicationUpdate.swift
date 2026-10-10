import Foundation
import CryptoKit

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
  }
  public func check(feed: URL, currentVersion: String) async throws -> Release? {
    guard feed.scheme == "https",feed.user == nil,feed.password == nil else { throw SQLFailure("Güncelleme adresi HTTPS olmalı.") }
    var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      response.url?.scheme == "https", data.count < 65536 else {
      throw SQLFailure("Güncelleme bilgisi alınamadı. GitHub deposunun herkese açık olduğunu ve son yayında update.json bulunduğunu kontrol edin.")
    }
    let release = try JSONDecoder().decode(Release.self, from:data)
    guard Self.isNewer(release.version,than:"0"), release.downloadURL.scheme == "https", release.sha256.count == 64,
      release.sha256.allSatisfy({ $0.isHexDigit }) else { throw SQLFailure("Güncelleme bilgisi geçersiz.") }
    return Self.isNewer(release.version,than:currentVersion) ? release : nil
  }
  public func download(_ release: Release) async throws -> URL {
    guard release.downloadURL.scheme == "https" else { throw SQLFailure("Paket adresi HTTPS olmalı.") }
    let (url,response) = try await URLSession.shared.download(from:release.downloadURL)
    do {
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
  public init() {}
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
  // Kept beside the target on the same volume, inside the private staging directory.
  nonisolated static let installationScript = """
    #!/bin/sh
    stage="$1"
    target="$2"
    parent="$3"
    while kill -0 "$parent" 2>/dev/null; do sleep 1; done
    backup="${stage}/previous"
    log="${stage}/update.log"
    if [ -e "$target" ]; then /bin/mv "$target" "$backup" || exit 1; fi
    if /bin/mv "$stage/MSSQLStudio.app" "$target" && /usr/bin/codesign --verify --deep --strict "$target" 2>"$log" && /usr/bin/open -n "$target"; then
      /bin/rm -rf "$backup"
      /bin/rm -f "$stage/helper.sh" "$log"
      /bin/rmdir "$stage" 2>/dev/null
    else
      if [ -e "$target" ]; then /bin/mv "$target" "$stage/failed.app"; fi
      if [ -e "$backup" ]; then /bin/mv "$backup" "$target"; /usr/bin/open -n "$target"; fi
    fi
    """
  public func schedule(_ update: PreparedApplicationUpdate, parentPID: Int32) throws {
    let helper = update.stage.appendingPathComponent("helper.sh")
    try Self.installationScript.write(to:helper,atomically:true,encoding:.utf8)
    let process = Process(); process.executableURL = URL(fileURLWithPath:"/bin/sh")
    process.arguments = [helper.path,update.stage.path,update.target.path,String(parentPID)]
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    try process.run()
  }
}
