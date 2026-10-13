import Foundation
import Security

/// A private, authenticated pipe to the frozen signed credential executable.
/// Its CDHash stays unchanged across app releases (a personal certificate alone cannot do that).
struct CredentialAgent: Sendable {
  let executable: URL
  let testService: String?
  let testKeychain: String?

  static func installed() throws -> CredentialAgent {
    guard Bundle.main.bundleIdentifier == "local.mssqlstudio.app" else {
      throw SQLFailure("Parola bileşeni yalnız kurulu MSSQL Studio’da kullanılabilir.")
    }
    return CredentialAgent(executable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MSSQLStudioCredentials"), testService: nil, testKeychain: nil)
  }

  func request(_ operation: String, account: UUID? = nil, data: Data? = nil) throws -> (records: [Data], count: Int) {
    var code: SecStaticCode?, requirement: SecRequirement?
    var caller: SecCode?
    try check(SecRequirementCreateWithString(try PersonalSigningIdentity.requirement() as CFString, [], &requirement))
    try check(SecCodeCopySelf([], &caller))
    guard let caller, let requirement else { throw SQLFailure("Uygulama imzası doğrulanamadı.") }
    try check(SecCodeCheckValidity(caller, [], requirement))
    try check(SecStaticCodeCreateWithPath(executable as CFURL, [], &code))
    guard let code else { throw SQLFailure("Güvenli parola bileşeni bulunamadı. Uygulamayı yeniden kurun.") }
    try check(SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement))
    var payload: [String: Any] = ["protocol": 1, "operation": operation]
    if let account { payload["account"] = account.uuidString }
    if let data { payload["data"] = data.base64EncodedString() }
    if let testService, let testKeychain { payload["testService"] = testService; payload["testKeychain"] = testKeychain }
    let request = try JSONSerialization.data(withJSONObject: payload)
    guard request.count <= 16 * 1024 * 1024 else { throw SQLFailure("Bağlantı kaydı çok büyük.") }
    let process = Process(), input = Pipe(), output = Pipe()
    process.executableURL = executable
    process.standardInput = input; process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    // No secrets in arguments, environment, files, or logs.
    try process.run()
    do { try input.fileHandleForWriting.write(contentsOf: request); try input.fileHandleForWriting.close() }
    catch { process.terminate(); process.waitUntilExit(); throw SQLFailure("Parola bileşenine erişilemedi.") }
    var response = Data()
    while let part = try output.fileHandleForReading.read(upToCount: 65536), !part.isEmpty {
      guard response.count + part.count <= 16 * 1024 * 1024 else {
        process.terminate(); process.waitUntilExit(); throw SQLFailure("Parola bileşeni yanıtı çok büyük.")
      }
      response.append(part)
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0,
      let result = try JSONSerialization.jsonObject(with: response) as? [String: Any],
      let status = result["status"] as? Int else { throw SQLFailure("Güvenli parola bileşeni isteği reddetti.") }
    try check(OSStatus(status))
    let records = try (result["records"] as? [String] ?? []).map { text in
      guard let value = Data(base64Encoded: text) else { throw SQLFailure("Bağlantı kaydı okunamadı.") }
      return value
    }
    return (records, result["count"] as? Int ?? 0)
  }
  private func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else {
      throw SQLFailure("Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))")
    }
  }
}
