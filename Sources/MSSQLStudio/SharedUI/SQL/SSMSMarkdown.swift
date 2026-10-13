import AppKit
import CoreText
import SQLServerKit
import SwiftUI

struct SSMSMarkdown: View {
  let text: String
  @State private var revision = 0
  var body: some View {
    let blocks = text.components(separatedBy: "```")
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
        if index.isMultiple(of: 2) {
          Text(LocalizedStringKey(block))
            .font(.custom(StudioTheme.uiFont.fontName, size: 12))
            .foregroundStyle(Color(nsColor: StudioTheme.text))
        } else {
          let sql = block.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
          Text(styled(sql))
            .font(.custom(StudioTheme.codeFont.fontName, size: 13))
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: StudioTheme.border)))
        }
      }
    }.textSelection(.enabled)
      .id(revision)
      .onReceive(NotificationCenter.default.publisher(for: StudioTheme.changed)) { _ in
        revision += 1
      }
  }
  private func styled(_ sql: String) -> AttributedString {
    var output = AttributedString()
    for token in TSQL.lex(sql) {
      var part = AttributedString(token.text)
      part.foregroundColor = Color(nsColor: StudioTheme.syntax(TSQL.syntaxStyle(token)))
      output.append(part)
    }
    return output
  }
}

/// A single visible surface survives the complete asynchronous update preparation.
