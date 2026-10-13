import AppKit
import SwiftUI
import SQLServerKit

@MainActor enum SQLEditorPreferences {
  static let formattingKey = "sqlFormattingOptions"
  static func formatting(in defaults: UserDefaults = .standard) -> SQLFormattingOptions {
    guard let data = defaults.data(forKey: formattingKey), let options = try? JSONDecoder().decode(SQLFormattingOptions.self, from: data) else { return .init() }
    return options
  }
  static func saveFormatting(_ options: SQLFormattingOptions, in defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(options) { defaults.set(data,forKey:formattingKey) }
  }
  static let completionDelayKey = "sqlCompletionDelayMilliseconds"
  static let defaultCompletionDelay = 260
  static let completionSchemaKey = "sqlCompletionIncludeSchema"
  static let completionBracketsKey = "sqlCompletionQuoteIdentifiers"
  static func includeSchema(in defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey:completionSchemaKey) as? Bool ?? true
  }
  static func quoteIdentifiers(in defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey:completionBracketsKey) as? Bool ?? true
  }
  static func completionDelay(in defaults: UserDefaults = .standard) -> Int {
    guard defaults.object(forKey:completionDelayKey) != nil else {return defaultCompletionDelay}
    return max(50,min(1000,defaults.integer(forKey:completionDelayKey)))
  }
}
