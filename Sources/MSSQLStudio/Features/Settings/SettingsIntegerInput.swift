import SwiftUI

/// Retains incomplete typed text while making invalid drafts fail Apply validation.
struct SettingsIntegerInput: View {
  @Binding private var value: Int
  @State private var text: String
  private let unit: String
  init(_ unit: String, value: Binding<Int>) {
    self.unit = unit; _value = value; _text = State(initialValue: String(value.wrappedValue))
  }
  static func parsed(_ text: String) -> Int {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return Int.min }
    return Int(text) ?? Int.min
  }
  var body: some View {
    TextField(unit, text: Binding(get: { text }, set: { new in
      text = new; value = Self.parsed(new)
    }))
      .frame(width: 110)
      .onChange(of: value) { _, new in
        if new != Int.min && new != Self.parsed(text) { text = String(new) }
      }
  }
}
