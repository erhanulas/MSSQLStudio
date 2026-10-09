import Foundation

public enum PersonalSigningIdentity {
  private struct Identity: Decodable {
    let certificateSHA1: String
    let bundleIdentifier: String
  }
  public static func requirement() throws -> String {
    guard let url = Bundle.module.url(forResource:"SigningIdentity",withExtension:"json") else {
      throw SQLFailure("Kalıcı imza kimliği pakette bulunamadı.")
    }
    let identity = try JSONDecoder().decode(Identity.self,from:Data(contentsOf:url))
    guard identity.certificateSHA1.count == 40,
      identity.certificateSHA1.allSatisfy({"0123456789abcdef".contains($0)}),
      identity.bundleIdentifier == "local.mssqlstudio.app" else {throw SQLFailure("İmza kimliği geçersiz.")}
    return "identifier \"\(identity.bundleIdentifier)\" and certificate leaf = H\"\(identity.certificateSHA1)\""
  }
}
