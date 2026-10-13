import AppKit
import SQLServerKit

/// Keeps exact strings while using AppKit's native partial/final input validation.
final class ResultCellFormatter: Formatter {
  let column: TableColumn
  init(column: TableColumn) { self.column = column; super.init() }
  required init?(coder: NSCoder) { fatalError() }
  override func string(for obj: Any?) -> String? { obj as? String }
  override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
    // Untouched native NULL/DEFAULT displays are handled by the row-aware delegate.
    if string.isEmpty || string == "NULL" { obj?.pointee = string as NSString; return true }
    do { try ResultValueValidation.validate(string, column: column); obj?.pointee = string as NSString; return true }
    catch let failure { error?.pointee = failure.localizedDescription as NSString; return false }
  }
  override func isPartialStringValid(_ partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
    let type = String(column.valueType.lowercased().prefix { $0 != "(" })
    let pattern: String
    switch type {
    case "tinyint", "smallint", "int", "bigint": pattern = #"^[+-]?[0-9]*$"#
    case "decimal", "numeric", "money", "smallmoney": pattern = #"^[+-]?[0-9]*(?:\.[0-9]*)?$"#
    case "float", "real": pattern = #"^[0-9eE+.\-]*$"#
    case "bit": pattern = #"^[01]?$"#
    default: return true
    }
    let valid = partialString.range(of: pattern, options: .regularExpression) != nil
    if !valid { error?.pointee = "\(column.name): \(column.valueType) alanına sayısal değer girin." as NSString }
    return valid
  }
}

/// Programmatic focus changes can bypass a cell-based table's end-edit delegate.
/// The native field editor therefore validates before releasing its draft.
@MainActor final class ResultFieldEditor: NSTextView {
  weak var table: CopyTable?
  var valueFormatter: ResultCellFormatter?
  var allowsInvalidExit = false
  override func resignFirstResponder() -> Bool {
    if !allowsInvalidExit, let table, table.validateDraft?(table.editedRow, table.editedColumn, string) == false { return false }
    return super.resignFirstResponder()
  }
  override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
    if !hasMarkedText(), let replacementString, NSMaxRange(affectedCharRange) <= (string as NSString).length {
      let proposed = (string as NSString).replacingCharacters(in: affectedCharRange, with: replacementString)
      if valueFormatter?.isPartialStringValid(proposed, newEditingString: nil, errorDescription: nil) == false { return false }
    }
    return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
  }
}
