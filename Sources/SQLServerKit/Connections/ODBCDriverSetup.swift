import CODBC
import Darwin
import Foundation

/// Read-only inspection uses the same unixODBC registry as the connection path.
/// Installation is a separate explicit operation; it never elevates privileges.
public enum ODBCDriverSetup {
  public struct Status: Sendable, Equatable {
    public let available: Bool
    public let version: String
    public let detail: String
    public let brew: String?
    public init(available: Bool, version: String, detail: String, brew: String?) {
      self.available = available; self.version = version; self.detail = detail; self.brew = brew
    }
  }
  public struct Command: Sendable, Equatable {
    public let arguments: [String]
    public let phase: String
  }
  public static func installationCommands(homebrewMajor: Int) -> [Command] {
    var commands = [Command(arguments: ["tap", "microsoft/mssql-release", "https://github.com/Microsoft/homebrew-mssql-release"], phase: "Microsoft sürücü kaynağı ekleniyor…")]
    if homebrewMajor >= 6 { commands.append(Command(arguments: ["trust", "microsoft/mssql-release"], phase: "Microsoft sürücü kaynağına izin veriliyor…")) }
    commands.append(Command(arguments: ["install", "microsoft/mssql-release/msodbcsql18"], phase: "ODBC Driver 18 kuruluyor…"))
    return commands
  }
  public static func inspect() async -> Status {
    await Task.detached(priority: .utility) {
      let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
      var environment: SQLHANDLE?
      guard SQLAllocHandle(SQLSMALLINT(SQL_HANDLE_ENV), nil, &environment) == SQL_SUCCESS else {
        return Status(available: false, version: "18", detail: "unixODBC sürücü kaydı okunamadı.", brew: brew)
      }
      defer { SQLFreeHandle(SQLSMALLINT(SQL_HANDLE_ENV), environment) }
      SQLSetEnvAttr(environment, SQLINTEGER(SQL_ATTR_ODBC_VERSION), UnsafeMutableRawPointer(bitPattern: Int(SQL_OV_ODBC3)), 0)
      var direction = SQLUSMALLINT(SQL_FETCH_FIRST)
      for _ in 0..<128 {
        var name = [SQLWCHAR](repeating: 0, count: 1024), attributes = [SQLWCHAR](repeating: 0, count: 8192)
        var nameLength: SQLSMALLINT = 0, attributeLength: SQLSMALLINT = 0
        let result = SQLDriversW(environment, direction, &name, 1024, &nameLength, &attributes, 8192, &attributeLength)
        guard result == SQL_SUCCESS || result == SQL_SUCCESS_WITH_INFO else { break }
        direction = SQLUSMALLINT(SQL_FETCH_NEXT)
        guard String(decoding: name.prefix(Int(nameLength)), as: UTF16.self) == "ODBC Driver 18 for SQL Server" else { continue }
        let entries = attributes.prefix(min(Int(attributeLength), attributes.count)).split(separator: 0).map { String(decoding: $0, as: UTF16.self) }
        guard let entry = entries.first(where: { $0.lowercased().hasPrefix("driver=") }) else { break }
        let path = String(entry.dropFirst(7))
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
          return Status(available: false, version: "18", detail: "Sürücü kayıtlı ancak yüklenemiyor; mimari ve bağımlılıkları kontrol edin.", brew: brew)
        }
        dlclose(library)
        let parts = URL(fileURLWithPath: path).resolvingSymlinksInPath().pathComponents
        let version = parts.firstIndex(of: "msodbcsql18").flatMap { $0 + 1 < parts.count ? parts[$0 + 1] : nil } ?? "18"
        return Status(available: true, version: version, detail: "Kayıtlı ve yüklenebilir · unixODBC", brew: brew)
      }
      return Status(available: false, version: "18", detail: "Microsoft ODBC Driver 18 bulunamadı.", brew: brew)
    }.value
  }
  public static func run(_ executable: String, arguments: [String], acceptLicense: Bool = false,
                         output: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
    let process = Process()
    return try await withTaskCancellationHandler {
      try await Task.detached(priority: .utility) {
        try Task.checkCancellation()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["NONINTERACTIVE"] = "1"
        if acceptLicense { environment["HOMEBREW_ACCEPT_EULA"] = "Y" }
        process.environment = environment
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1200, execute: deadline)
        defer { deadline.cancel() }
        var result = Data()
        while let part = try pipe.fileHandleForReading.read(upToCount: 8192), !part.isEmpty {
          output(String(decoding: part, as: UTF8.self))
          result.append(part)
          if result.count > 65536 { result = result.suffix(65536) }
        }
        process.waitUntilExit()
        let text = String(decoding: result, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw SQLFailure("Homebrew işlemi tamamlanamadı (\(process.terminationStatus)).\n\(text.suffix(4000))") }
        return text
      }.value
    } onCancel: { if process.isRunning { process.terminate() } }
  }
}
