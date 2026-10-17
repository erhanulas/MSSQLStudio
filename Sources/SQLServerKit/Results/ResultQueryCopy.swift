import Foundation

/// A conservative SELECT projection, based only on executed rowset provenance.
public struct ResultQueryCopy:Sendable {
  private let prefix:String
  private let suffix:String
  private let references:[String?]
  private let fields:[Field]
  public init(source:SQLResultSource,fields:[Field]) throws {
    func unsupported()->SQLFailure {SQLFailure("Sorgu kopyalama tek tablo/view içeren doğrudan SELECT sonuçlarında kullanılabilir.")}
    guard source.kind == .statement,source.sql.utf16.count<=250_000 else {throw unsupported()}
    let sql=source.sql as NSString
    let tokens=TSQL.lex(source.sql).filter {$0.kind != .space && $0.kind != .comment}
    func word(_ t:Lexeme)->String {t.kind == .keyword || t.kind == .word && !t.text.hasPrefix("[") && !t.text.hasPrefix("\"") ? t.text.uppercased():""}
    func identifier(_ t:Lexeme)->Bool {t.kind == .word || t.kind == .keyword}
    var depth=0,top:[Int]=[]
    for i in tokens.indices {
      if tokens[i].text==")" {depth-=1}
      guard depth>=0 else {throw unsupported()}
      if depth==0 {top.append(i)}
      if tokens[i].text=="(" {depth+=1}
    }
    guard depth==0,tokens.first.map(word)=="SELECT",let from=top.first(where:{word(tokens[$0])=="FROM"}),
      top.filter({word(tokens[$0])=="SELECT"}).count==1,
      !top.contains(where:{["INTO","JOIN","APPLY","UNION","EXCEPT","INTERSECT","GROUP","HAVING","INSERT","UPDATE","DELETE","MERGE","EXEC","EXECUTE","GO"].contains(word(tokens[$0]))}),
      !top.contains(where:{tokens[$0].text==";" && $0 != tokens.count-1}) else {throw unsupported()}
    let whereIndex=top.first {word(tokens[$0])=="WHERE"}
    let tail=top.first { ["ORDER","OPTION"].contains(word(tokens[$0])) || tokens[$0].text==";" }
    let relationEnd=min(whereIndex ?? tokens.count,tail ?? tokens.count)
    var cursor=from+1
    guard cursor<relationEnd,identifier(tokens[cursor]) else {throw unsupported()}
    cursor+=1;var parts=1
    while cursor+1<relationEnd,tokens[cursor].text==".",identifier(tokens[cursor+1]) {cursor+=2;parts+=1}
    guard parts<=3 else {throw unsupported()}
    var alias:String?
    if cursor<relationEnd,word(tokens[cursor])=="AS" {
      cursor+=1;guard cursor<relationEnd,identifier(tokens[cursor]) else {throw unsupported()}
      alias=tokens[cursor].text;cursor+=1
    } else if cursor<relationEnd,identifier(tokens[cursor]),word(tokens[cursor]) != "WITH" {
      alias=tokens[cursor].text;cursor+=1
    }
    if cursor<relationEnd,word(tokens[cursor])=="WITH" {cursor+=1}
    if cursor<relationEnd,tokens[cursor].text=="(" {
      var hintDepth=0
      repeat {
        if tokens[cursor].text=="(" {hintDepth+=1}
        if tokens[cursor].text==")" {hintDepth-=1}
        cursor+=1
      } while cursor<relationEnd && hintDepth>0
      guard hintDepth==0 else {throw unsupported()}
    }
    guard cursor==relationEnd else {throw unsupported()}
    var projection=1
    if projection<from,["DISTINCT","ALL"].contains(word(tokens[projection])) {projection+=1}
    if projection<from,word(tokens[projection])=="TOP" {
      projection+=1
      if projection<from,tokens[projection].text=="(" {
        var nesting=0
        repeat {
          if tokens[projection].text=="(" {nesting+=1};if tokens[projection].text==")" {nesting-=1}
          projection+=1
        } while projection<from && nesting>0
      } else {projection+=1}
      while projection<from,["PERCENT","WITH","TIES"].contains(word(tokens[projection])) {projection+=1}
    }
    guard projection<from else {throw unsupported()}
    var groups:[[Lexeme]]=[[]],nesting=0
    for t in tokens[projection..<from] {
      if t.text=="," && nesting==0 {groups.append([]);continue}
      groups[groups.count-1].append(t)
      if t.text=="(" {nesting+=1};if t.text==")" {nesting-=1}
    }
    let star=groups.count==1 && (groups[0].map(\.text)==["*"] || groups[0].count==3 && groups[0][1].text=="." && groups[0][2].text=="*")
    if star {
      references=fields.map { (alias.map {$0+"."} ?? "")+Self.name($0.name) }
    } else {
      guard groups.count==fields.count else {throw unsupported()}
      references=groups.map {group in
        var expression=group
        if expression.count>2,expression[1].text=="=" {expression=Array(expression.dropFirst(2))}
        else if let index=expression.firstIndex(where:{word($0)=="AS"}) {expression=Array(expression.prefix(index))}
        else if expression.count==2 || expression.count==4 && expression[1].text=="." {expression.removeLast()}
        if expression.count==1,identifier(expression[0]) {return (alias.map {$0+"."} ?? "")+expression[0].text}
        if expression.count==3,identifier(expression[0]),expression[1].text==".",identifier(expression[2]) {return expression.map(\.text).joined()}
        return nil
      }
    }
    let cut=tokens[(whereIndex ?? tail) ?? tokens.count-1].range.location
    let prefixEnd=whereIndex == nil && tail == nil ? sql.length:cut
    var head=sql.substring(to:prefixEnd).trimmingCharacters(in:.whitespacesAndNewlines)
    // Do not append a WHERE clause inside an existing line comment.
    let raw=TSQL.lex(head).last {$0.kind != .space}
    head += raw?.kind == .comment && raw?.text.hasPrefix("--") == true ? "\n":" "
    prefix=head
    suffix=tail.map {(tokens[$0].text==";" ? "":" ")+sql.substring(from:tokens[$0].range.location)} ?? ";"
    self.fields=fields
  }
  public func supports(columns:[Int])->Bool {columns.allSatisfy {references.indices.contains($0) && references[$0] != nil}}
  public func sql(cells:[(column:Int,value:String?)]) throws -> String {
    guard !cells.isEmpty else {throw SQLFailure("Bir veya birden fazla hücre seçin.")}
    let columns=Set(cells.map(\.column)),vertical=columns.count==1 && cells.count>1
    guard vertical ? cells.count<=1000:cells.count<=64 && columns.count==cells.count else {
      throw SQLFailure("Tek satırda en fazla 64 kolon veya tek kolonda en fazla 1.000 satır seçin.")
    }
    var inputBytes=0
    for cell in cells {
      inputBytes += cell.value?.utf8.count ?? 0
      guard inputBytes<=4_000_000 else {throw SQLFailure("Seçili hücreler kopyalama sınırını aşıyor; daha az satır seçin.")}
    }
    func reference(_ column:Int) throws -> String {
      guard fields.indices.contains(column),let reference=references[column] else {throw SQLFailure("Seçili hesaplanan kolon doğrudan WHERE koşuluna çevrilemiyor.")}
      return reference
    }
    let predicate:String
    if vertical {
      let column=cells[0].column,ref=try reference(column)
      var values:[String]=[],seen=Set<String>(),hasNull=false
      for cell in cells {
        guard let value=cell.value else {hasNull=true;continue}
        let literal=try Self.literal(value,field:fields[column])
        if seen.insert(literal).inserted {values.append(literal)}
      }
      if values.isEmpty {predicate=ref+" IS NULL"}
      else {
        let list=ref+" IN ("+values.joined(separator:", ")+")"
        predicate=hasNull ? "("+list+" OR "+ref+" IS NULL)":list
      }
    } else {
      predicate=try cells.map {cell -> String in
        let ref=try reference(cell.column)
        guard let value=cell.value else {return ref+" IS NULL"}
        return ref+" = "+(try Self.literal(value,field:fields[cell.column]))
      }.joined(separator:" AND ")
    }
    let result=prefix+"WHERE "+predicate+suffix
    guard result.utf8.count<=4_000_000 else {throw SQLFailure("Sorgu kopyası çok büyük; daha az hücre seçin.")}
    return result
  }
  private static func name(_ text:String)->String {
    !TSQL.keywords.contains(text.uppercased()) && text.range(of:#"^[A-Za-z_][A-Za-z0-9_@$#]*$"#,options:.regularExpression) != nil ? text:SQL.identifier(text)
  }
  private static func literal(_ value:String,field:Field) throws -> String {
    guard value.utf8.count<=1_000_000 else {throw SQLFailure("Seçili hücre kopyalama sınırını aşıyor.")}
    let base=field.declaredType?.lowercased().split(separator:"(").first.map(String.init)
    guard !["xml","text","ntext","image","geography","geometry"].contains(base ?? "") else {throw SQLFailure("Bu veri tipi WHERE eşitliği için desteklenmiyor.")}
    let text=value.trimmingCharacters(in:.whitespacesAndNewlines)
    if field.type == -7 {
      guard ["0","1","true","false"].contains(text.lowercased()) else {throw SQLFailure("Bit değeri geçersiz.")}
      return ["1","true"].contains(text.lowercased()) ? "1":"0"
    }
    if field.numeric {
      guard text.range(of:#"\A[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\z"#,options:.regularExpression) != nil else {throw SQLFailure("Sayısal hücre değeri geçersiz.")}
      return text
    }
    if [-2,-3,-4].contains(field.type) {
      guard text.range(of:#"\A0x(?:[0-9a-fA-F]{2})*\z"#,options:.regularExpression) != nil else {throw SQLFailure("Binary hücre değeri geçersiz.")}
      return text
    }
    guard field.type != -151,
      [1,12,-1,-8,-9,-10,91,92,93,-11,-154,-155].contains(field.type) else {throw SQLFailure("Bu veri tipi WHERE eşitliği için desteklenmiyor.")}
    return SQL.literal(value)
  }
}
