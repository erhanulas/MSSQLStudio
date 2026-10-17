import Foundation

@MainActor enum QueryExecutionPreferences {
  static let timeoutKey="sqlExecutionTimeoutSeconds"
  static let timeoutRange=0...86_400
  static var timeoutSeconds:Int {
    let value=UserDefaults.standard.object(forKey:timeoutKey) as? Int ?? 0
    return timeoutRange.contains(value) ? value:0
  }
  static func save(timeout:Int) {
    precondition(timeoutRange.contains(timeout))
    UserDefaults.standard.set(timeout,forKey:timeoutKey)
  }
}
