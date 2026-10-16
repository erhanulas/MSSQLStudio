import Foundation

/// SQL Server XE timestamps remain UTC; formatting never changes retained/exported source.
enum ProfilerTimestamp {
  static func display(_ source:String)->String {
    guard (20...40).contains(source.utf8.count) else {return source}
    let bytes=Array(source.utf8)
    guard (20...40).contains(bytes.count),bytes.last==90,bytes[4]==45,bytes[7]==45,bytes[10]==84,bytes[13]==58,bytes[16]==58 else {return source}
    let digits=[0,1,2,3,5,6,8,9,11,12,14,15,17,18]
    guard digits.allSatisfy({(48...57).contains(bytes[$0])}) else {return source}
    var fraction="000"
    if bytes.count>20 {
      guard bytes[19]==46,bytes[20..<bytes.count-1].allSatisfy({(48...57).contains($0)}),bytes.count>21 else {return source}
      fraction=String(decoding:bytes[20..<bytes.count-1].prefix(3),as:UTF8.self)
      fraction+=String(repeating:"0",count:3-fraction.count)
    }
    func text(_ range:Range<Int>)->String {String(decoding:bytes[range],as:UTF8.self)}
    return text(8..<10)+"."+text(5..<7)+"."+text(0..<4)+" "+text(11..<19)+"."+fraction
  }
}
