import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor enum SQLSourceHighlighting {
  static func foreground(_ token:Lexeme,unused:Bool,undeclared:Bool=false) -> NSColor {
    undeclared ? StudioTheme.undeclaredVariable : unused ? StudioTheme.unusedVariable : StudioTheme.syntax(TSQL.syntaxStyle(token))
  }
  static func attributed(_ source:String) -> NSAttributedString {
    let result=NSMutableAttributedString(string:source,attributes:[.font:StudioTheme.codeFont,.foregroundColor:StudioTheme.editorText])
    guard source.utf16.count <= 1_000_000 else {return result}
    let analysis=TSQL.variableAnalysis(source)
    let unused=Set(analysis.unused.map(\.location)),undeclared=Set(analysis.undeclared.map(\.location))
    for token in TSQL.lex(source) {
      result.addAttribute(.foregroundColor,value:foreground(token,unused:unused.contains(token.range.location),undeclared:undeclared.contains(token.range.location)),range:token.range)
      if undeclared.contains(token.range.location) {result.addAttribute(.toolTip,value:"Bu değişken bu SQL batch’inde tanımlanmamış: "+token.text,range:token.range)}
    }
    return result
  }
}

