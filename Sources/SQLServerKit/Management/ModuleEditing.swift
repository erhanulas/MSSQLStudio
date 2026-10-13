import Foundation

public enum ModuleEditing {
  public static func changedObjects(_ sql: String) -> [(name: String, folder: Folder)] {
    changes(sql).map {(($0.schema.map {$0+"."} ?? "")+$0.name,$0.folder)}
  }
  public static func alter(_ source: String) -> String {
    let tokens = TSQL.lex(source).filter { $0.kind != .space && $0.kind != .comment }
    guard let first = tokens.first, first.text.uppercased() == "CREATE" else { return source }
    let length: Int
    if tokens.count > 3 && tokens[1].text.uppercased() == "OR" && tokens[2].text.uppercased() == "ALTER" {
      length = NSMaxRange(tokens[2].range) - first.range.location
    } else { length = first.range.length }
    return (source as NSString).replacingCharacters(in: NSRange(location: first.range.location, length: length), with: "ALTER")
  }
  /// Linear prefix/suffix comparison: no quadratic diff allocation for large modules.
  public static func difference(original: String, edited: String) -> String {
    let a = alter(original).components(separatedBy: "\n"), b = edited.components(separatedBy: "\n")
    var prefix = 0
    while prefix < min(a.count,b.count), a[prefix] == b[prefix] { prefix += 1 }
    if prefix == a.count && prefix == b.count { return "Değişiklik yok." }
    var suffix = 0
    while suffix < min(a.count,b.count) - prefix, a[a.count - suffix - 1] == b[b.count - suffix - 1] { suffix += 1 }
    let old = a[prefix..<(a.count-suffix)].prefix(1000).map { "− " + String($0.prefix(2000)) }
    let new = b[prefix..<(b.count-suffix)].prefix(1000).map { "+ " + String($0.prefix(2000)) }
    return "@@ Satır \(prefix + 1) · −\(a.count-prefix-suffix) / +\(b.count-prefix-suffix) @@\n" + (old + new).joined(separator: "\n") + "\n(Önizleme: her tarafta en fazla 1.000 satır; aradaki değişmeyen satırlar da blokta olabilir.)"
  }
}

