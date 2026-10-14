import Foundation

/// Local SUM over numeric cells and COUNT of non-NULL cells. The request captures
/// the same immutable projection/page/draft values that the grid displays.
public struct ResultSelectionSummary:Sendable,Equatable {
  public let sum:String?
  public let count:Int
  public let numericCount:Int
  public struct Request:Sendable {
    public let rows:Rows
    public let selection:IndexSet
    public let columns:[Int]
    public let projection:[Int]?
    public let pageStart:Int
    public let basePageCount:Int
    public let newRows:[Int]
    public let overrides:[Int:[String?]]
    public init(rows:Rows,selection:IndexSet,columns:[Int],projection:[Int]?=nil,pageStart:Int=0,
                basePageCount:Int?=nil,newRows:[Int]=[],overrides:[Int:[String?]]=[:]) {
      self.rows=rows;self.selection=selection;self.columns=columns;self.projection=projection
      self.pageStart=pageStart;self.basePageCount=basePageCount ?? rows.values.count
      self.newRows=newRows;self.overrides=overrides
    }
  }
  public static func compute(_ request:Request) throws -> Self {
    try Task.checkCancellation()
    let columns=Array(Set(request.columns)).sorted()
    guard columns.allSatisfy({request.rows.fields.indices.contains($0)}),request.pageStart>=0,request.basePageCount>=0 else {
      throw SQLFailure("Seçim kapsamı geçersiz.")
    }
    let available=request.projection?.count ?? request.rows.values.count
    guard request.pageStart<=available,request.basePageCount<=available-request.pageStart else {
      throw SQLFailure("Seçim sayfası değişti.")
    }
    let (pageCount,overflow)=request.basePageCount.addingReportingOverflow(request.newRows.count)
    guard !overflow,request.selection.last.map({$0<pageCount}) ?? true else {throw SQLFailure("Seçim kapsamı değişti.")}
    guard !columns.isEmpty,!request.selection.isEmpty else {return Self(sum:nil,count:0,numericCount:0)}
    guard request.selection.count<=5_000_000/columns.count else {
      throw SQLFailure("Seçim özeti en fazla 5.000.000 hücre için hesaplanabilir. Daha küçük bir alan seçin.")
    }
    let numeric=Set(columns.filter {request.rows.fields[$0].numeric && request.rows.fields[$0].type != -7})
    let deadline=ContinuousClock.now.advanced(by:.seconds(10))
    var accumulator=SelectionDecimalSum(),count=0,numericCount=0,bytes=0,visited=0
    for row in request.selection {
      if visited.isMultiple(of:128) {
        try Task.checkCancellation()
        guard ContinuousClock.now<deadline else {throw SQLFailure("Seçim özeti süresi aşıldı. Daha küçük bir alan seçin.")}
      }
      visited+=1
      let index:Int
      if row<request.basePageCount {
        let position=request.pageStart+row
        if let projection=request.projection {
          guard projection.indices.contains(position) else {throw SQLFailure("Seçim kapsamı değişti.")}
          index=projection[position]
        } else {index=position}
      } else {
        let position=row-request.basePageCount
        guard request.newRows.indices.contains(position) else {throw SQLFailure("Seçim kapsamı değişti.")}
        index=request.newRows[position]
      }
      let values:[String?]
      if let override=request.overrides[index] {values=override}
      else {
        guard request.rows.values.indices.contains(index) else {throw SQLFailure("Seçim satırı okunamadı.")}
        values=request.rows.values[index]
      }
      for column in columns {
        guard values.indices.contains(column) else {throw SQLFailure("Seçim hücresi okunamadı.")}
        guard let value=values[column] else {continue}
        count+=1
        if numeric.contains(column) {
          let digits=Array(value.utf8.prefix(513));bytes+=digits.count
          guard digits.count<=512,bytes<=128*1024*1024,accumulator.add(digits) else {
            throw SQLFailure("Sayısal değer güvenli biçimde toplanamadı; kısmi toplam gösterilmedi.")
          }
          numericCount+=1
        }
      }
    }
    try Task.checkCancellation()
    guard request.rows.values.readFailure == nil else {throw SQLFailure("Geçici sonuç dosyası okunamadı; seçim özeti gösterilmedi.")}
    guard ContinuousClock.now<deadline else {throw SQLFailure("Seçim özeti süresi aşıldı. Daha küçük bir alan seçin.")}
    return Self(sum:numericCount==0 ? nil:accumulator.text,count:count,numericCount:numericCount)
  }
}

/// Base-10 limbs preserve decimal(38,s), bigint and sums wider than SQL precision.
/// No Decimal/Double conversion or locale-dependent parsing is used.
private struct SelectionDecimalSum {
  private static let base:Int64=1_000_000_000
  private var words:[Int64]=[]
  private var negative=false
  private var scale=0
  mutating func add(_ bytes:[UInt8])->Bool {
    guard !bytes.isEmpty else {return false}
    var i=0,sign=false
    if bytes[i]==45 || bytes[i]==43 {sign=bytes[i]==45;i+=1}
    var digits:[UInt8]=[],fraction=0,dot=false
    while i<bytes.count {
      let byte=bytes[i]
      if (48...57).contains(byte) {digits.append(byte);if dot {fraction+=1}}
      else if byte==46,!dot {dot=true}
      else {break}
      i+=1
    }
    guard !digits.isEmpty else {return false}
    var exponent=0
    if i<bytes.count,bytes[i]==101 || bytes[i]==69 {
      i+=1;var minus=false
      if i<bytes.count,bytes[i]==45 || bytes[i]==43 {minus=bytes[i]==45;i+=1}
      let start=i
      while i<bytes.count,(48...57).contains(bytes[i]) {
        exponent=exponent*10+Int(bytes[i]-48);i+=1
        guard exponent<=400 else {return false}
      }
      guard i>start else {return false}
      if minus {exponent = -exponent}
    }
    guard i==bytes.count else {return false}
    var valueScale=fraction-exponent
    guard valueScale<=400 else {return false}
    if valueScale<0 {digits+=Array(repeating:48,count:-valueScale);valueScale=0}
    var value:[Int64]=[],end=digits.count
    while end>0 {
      let start=max(0,end-9)
      var word:Int64=0
      for digit in digits[start..<end] {word=word*10+Int64(digit-48)}
      value.append(word);end=start
    }
    Self.trim(&value)
    if valueScale>scale {Self.shift(&words,by:valueScale-scale);scale=valueScale}
    else {Self.shift(&value,by:scale-valueScale)}
    if words.isEmpty {words=value;negative=sign;return true}
    if negative==sign {
      var carry:Int64=0
      for index in 0..<max(words.count,value.count) {
        if index==words.count {words.append(0)}
        let total=words[index]+(index<value.count ? value[index]:0)+carry
        words[index]=total % Self.base;carry=total/Self.base
      }
      if carry>0 {words.append(carry)}
    } else {
      let order=Self.compare(words,value)
      if order<0 {let previous=words;words=value;value=previous;negative=sign}
      var borrow:Int64=0
      for index in words.indices {
        var difference=words[index]-(index<value.count ? value[index]:0)-borrow
        borrow=difference<0 ? 1:0
        if difference<0 {difference+=Self.base}
        words[index]=difference
      }
      Self.trim(&words)
    }
    if words.isEmpty {negative=false}
    return true
  }
  var text:String {
    var text=words.last.map(String.init) ?? "0"
    for word in words.dropLast().reversed() {let part=String(word);text+=String(repeating:"0",count:9-part.count)+part}
    if scale>0 {
      if text.count<=scale {text=String(repeating:"0",count:scale+1-text.count)+text}
      text.insert(".",at:text.index(text.endIndex,offsetBy:-scale))
    }
    return (negative && !words.isEmpty ? "-":"")+text
  }
  private static func trim(_ words:inout [Int64]) {while words.last==0 {words.removeLast()}}
  private static func shift(_ words:inout [Int64],by digits:Int) {
    guard !words.isEmpty,digits>0 else {return}
    let whole=digits/9,remainder=digits%9
    if remainder>0 {
      var factor:Int64=1,carry:Int64=0
      for _ in 0..<remainder {factor*=10}
      for i in words.indices {let value=words[i]*factor+carry;words[i]=value%base;carry=value/base}
      if carry>0 {words.append(carry)}
    }
    if whole>0 {words.insert(contentsOf:repeatElement(0,count:whole),at:0)}
  }
  private static func compare(_ a:[Int64],_ b:[Int64])->Int {
    if a.count != b.count {return a.count<b.count ? -1:1}
    for i in a.indices.reversed() where a[i] != b[i] {return a[i]<b[i] ? -1:1}
    return 0
  }
}
