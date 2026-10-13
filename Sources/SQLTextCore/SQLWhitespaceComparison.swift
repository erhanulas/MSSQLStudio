import Foundation

/// A comparison-only token stream. It never rewrites displayed or executable SQL.
/// Literal/quoted-identifier text remains exact; comments keep their content with
/// canonical line endings and without trailing padding on single-line comments.
public enum SQLWhitespaceComparison {
  public struct Token: Sendable, Equatable {
    /// Canonical comparison text. Comments normalize CR/LF endings and single-line
    /// comments trim trailing spaces/tabs; ranges always cover the original text.
    public let text: String
    public let range: NSRange
  }

  /// Length prefixes retain token boundaries: `< =` must never equal `<=`, and
  /// numeric, Unicode-string and variable adjacency must remain meaningful.
  /// Hash/compare UTF-8 bytes when exact literal Unicode composition matters;
  /// Swift String equality itself treats canonically equivalent Unicode as equal.
  public static func key(_ sql: String) -> String {
    var result=""
    result.reserveCapacity(sql.utf8.count)
    for token in tokens(in:sql) {
      result += String(token.text.utf8.count)+":"+token.text
    }
    return result
  }

  public static func tokens(in sql: String) -> [Token] {
    let units=Array(sql.utf16)
    var index=0,result:[Token]=[]
    func digit(_ c:UInt16)->Bool {(48...57).contains(c)}
    func hex(_ c:UInt16)->Bool {digit(c) || (65...70).contains(c) || (97...102).contains(c)}
    func word(_ c:UInt16)->Bool {c>=128 || (65...90).contains(c) || (97...122).contains(c) || digit(c) || [95,64,35,36].contains(c)}
    func append(_ start:Int,_ end:Int,_ text:String?=nil) {
      result.append(.init(text:text ?? String(decoding:units[start..<end],as:UTF16.self),range:NSRange(location:start,length:end-start)))
    }
    // These are indivisible SQL Server operators. Unary +/- remain individual
    // tokens so `a * -1` and `a*- 1` compare equally.
    let pairs:Set<String>=["<=",">=","<>","!=","!<","!>","+=","-=","*=","/=","%=","&=","^=","|=","::","||"]
    while index<units.count {
      let start=index,c=units[index]
      if [9,10,11,12,13,32].contains(c) {index+=1;continue}
      if c==45,index+1<units.count,units[index+1]==45 {
        index+=2
        while index<units.count,![10,13].contains(units[index]) {index+=1}
        var trimmed=index
        while trimmed>start,[9,32].contains(units[trimmed-1]) {trimmed-=1}
        append(start,index,String(decoding:units[start..<trimmed],as:UTF16.self))
        let terminator=index
        if index<units.count {
          index+=1
          if units[terminator]==13,index<units.count,units[index]==10 {index+=1}
        }
        // EOF is a valid terminator too. A final newline after -- text carries
        // no code difference, while later SQL remains outside the comment.
        append(terminator,index,"\n")
      } else if c==47,index+1<units.count,units[index+1]==42 {
        index+=2;var depth=1
        while index<units.count,depth>0 {
          if index+1<units.count,units[index]==47,units[index+1]==42 {depth+=1;index+=2}
          else if index+1<units.count,units[index]==42,units[index+1]==47 {depth-=1;index+=2}
          else {index+=1}
        }
        let comment=String(decoding:units[start..<index],as:UTF16.self)
        append(start,index,comment.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n"))
      } else if [39,91,34].contains(c) || ([78,110].contains(c) && index+1<units.count && units[index+1]==39) {
        if [78,110].contains(c) {index+=1}
        let closing:UInt16=units[index]==91 ? 93:units[index]
        index+=1
        while index<units.count {
          if units[index]==closing {
            index+=1
            if index<units.count,units[index]==closing {index+=1} else {break}
          } else {index+=1}
        }
        append(start,index)
      } else if digit(c) || (c==46 && index+1<units.count && digit(units[index+1])) {
        if c==48,index+1<units.count,[88,120].contains(units[index+1]) {
          index+=2
          while index<units.count,hex(units[index]) {index+=1}
        } else {
          while index<units.count,digit(units[index]) {index+=1}
          if index<units.count,units[index]==46 {
            index+=1
            while index<units.count,digit(units[index]) {index+=1}
          }
          if index<units.count,[69,101].contains(units[index]) {
            var exponent=index+1
            if exponent<units.count,[43,45].contains(units[exponent]) {exponent+=1}
            let digits=exponent
            while exponent<units.count,digit(units[exponent]) {exponent+=1}
            if exponent>digits {index=exponent}
          }
        }
        // Preserve ambiguous adjacency instead of guessing whether an invalid
        // numeric suffix is an implicit alias or part of a literal.
        while index<units.count,word(units[index]) {index+=1}
        append(start,index)
      } else if word(c) {
        index+=1
        while index<units.count,word(units[index]) {index+=1}
        append(start,index)
      } else {
        index+=1
        if index<units.count {
          let pair=String(decoding:units[start...index],as:UTF16.self)
          if pairs.contains(pair) {
            index+=1
            if pair=="||",index<units.count,units[index]==61 {index+=1}
          }
        }
        append(start,index)
      }
    }
    return result
  }
}
