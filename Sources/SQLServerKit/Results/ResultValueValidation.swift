import Foundation

/// Validates cell input without changing its exact text or converting decimals to Double.
public enum ResultValueValidation {
  public static func validate(_ value: String?, column: TableColumn) throws {
    func invalid(_ detail: String) -> SQLFailure { SQLFailure("\(column.name) · \(column.valueType): \(detail)") }
    guard let value else {
      if !column.nullable { throw invalid("NULL kabul edilmez.") }
      return
    }
    let type = column.valueType.lowercased()
    let base = String(type.prefix { $0 != "(" })
    let arguments = type.split(separator: "(").dropFirst().first?.dropLast().split(separator: ",").compactMap { Int($0) } ?? []
    let number = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if ["tinyint", "smallint", "int", "bigint"].contains(base) {
      guard number.range(of: #"^[+-]?[0-9]+$"#, options: .regularExpression) != nil, let integer = Int64(number) else { throw invalid("Tam sayı girin.") }
      let bounds: ClosedRange<Int64> = base == "tinyint" ? 0...255 : base == "smallint" ? -32768...32767 : base == "int" ? -2147483648...2147483647 : Int64.min...Int64.max
      guard bounds.contains(integer) else { throw invalid("Değer \(bounds.lowerBound)…\(bounds.upperBound) aralığında olmalı.") }
    } else if ["decimal", "numeric", "money", "smallmoney"].contains(base) {
      guard number.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil else { throw invalid("Ondalık sayı girin; ondalık ayırıcı nokta olmalı.") }
      let parts = number.trimmingCharacters(in: CharacterSet(charactersIn: "+-")).split(separator: ".", omittingEmptySubsequences: false)
      let whole = parts[0].drop { $0 == "0" }.count
      let fraction = parts.count > 1 ? parts[1].reversed().drop { $0 == "0" }.count : 0
      let precision = arguments.first ?? (["money", "smallmoney"].contains(base) ? 19 : 18)
      let scale = arguments.count > 1 ? arguments[1] : (["money", "smallmoney"].contains(base) ? 4 : 0)
      guard whole <= precision - scale, fraction <= scale else { throw invalid("En fazla \(precision - scale) tam ve \(scale) kesir basamağı girin; değer yuvarlanmaz.") }
      if ["money", "smallmoney"].contains(base) {
        let lower = base == "money" ? "-922337203685477.5808" : "-214748.3648"
        let upper = base == "money" ? "922337203685477.5807" : "214748.3647"
        let locale = Locale(identifier: "en_US_POSIX")
        guard let amount = Decimal(string: number, locale: locale), amount >= Decimal(string: lower, locale: locale)!, amount <= Decimal(string: upper, locale: locale)! else { throw invalid("Parasal değer türün aralığı dışında.") }
      }
    } else if ["float", "real"].contains(base) {
      guard number.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
        let numeric = Double(number), numeric.isFinite,
        base != "real" || abs(numeric) <= Double(Float.greatestFiniteMagnitude) else { throw invalid("Geçerli, sonlu bir sayı girin.") }
    } else if base == "bit" {
      guard ["0", "1", "true", "false"].contains(number.lowercased()) else { throw invalid("0 veya 1 girin.") }
    } else if base == "uniqueidentifier" {
      guard UUID(uuidString: number) != nil else { throw invalid("Geçerli UUID girin.") }
    } else if ["binary", "varbinary", "image", "rowversion", "timestamp"].contains(base) {
      guard value.range(of: #"^0x(?:[0-9a-fA-F]{2})*$"#, options: .regularExpression) != nil else { throw invalid("Binary değer 0x… biçiminde olmalı.") }
      if let length = arguments.first, (value.count - 2) / 2 > length { throw invalid("En fazla \(length) byte girin.") }
    } else if ["nvarchar", "nchar", "varchar", "char"].contains(base), let length = arguments.first {
      let count = base.hasPrefix("n") ? value.utf16.count : value.count
      guard count <= length else { throw invalid("En fazla \(length) karakter girin.") }
    } else if ["date", "datetime", "datetime2", "smalldatetime", "datetimeoffset", "time"].contains(base) {
      guard validDate(number, type: base) else { throw invalid(base == "time" ? "HH:mm:ss biçiminde saat girin." : "YYYY-MM-DD veya ISO 8601 tarih/saat girin.") }
    }
  }

  private static func validDate(_ value: String, type: String) -> Bool {
    let pattern = type == "time" ? #"^([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]{1,7})?$"# : #"^([0-9]{4})-([0-9]{2})-([0-9]{2})(?:[ T]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]{1,7})?(?: ?(?:Z|[+-][0-9]{2}:[0-9]{2}))?)?$"#
    guard let expression = try? NSRegularExpression(pattern: pattern), let match = expression.firstMatch(in: value, range: NSRange(location: 0, length: value.utf16.count)) else { return false }
    let text = value as NSString
    func part(_ index: Int) -> Int? { let range = match.range(at: index); return range.location == NSNotFound ? nil : Int(text.substring(with: range)) }
    if type == "time" { return (part(1) ?? 24) < 24 && (part(2) ?? 60) < 60 && (part(3) ?? 60) < 60 }
    guard let year = part(1), let month = part(2), let day = part(3), (1...9999).contains(year),
      (part(4) ?? 0) < 24, (part(5) ?? 0) < 60, (part(6) ?? 0) < 60 else { return false }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard components.year == year, components.month == month, components.day == day else { return false }
    if type == "date", value.count != 10 { return false }
    if type == "datetime", year < 1753 { return false }
    if type == "smalldatetime", value.prefix(10) < "1900-01-01" || value.prefix(10) > "2079-06-06" { return false }
    if let zone = value.range(of: #"[+-][0-9]{2}:[0-9]{2}$"#, options: .regularExpression) {
      let offset = value[zone].dropFirst().split(separator: ":").compactMap { Int($0) }
      if offset.count != 2 || offset[0] > 14 || offset[1] > 59 || offset[0] == 14 && offset[1] != 0 { return false }
    }
    return true
  }
}
