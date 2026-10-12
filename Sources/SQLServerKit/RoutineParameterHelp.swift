import Foundation

/// Bounded lexical call context; never evaluates SQL or changes the editor source.
public struct SQLRoutineCall:Sendable {
  public let symbol:CatalogSymbol
  public let ordinal:Int
  public let namedArgument:String?
  public let start:Int
  public var key:String {symbol.schema+"\u{1f}"+symbol.name}
  public func activeIndex(in parameters:[RoutineParameter])->Int? {
    if let namedArgument {return parameters.firstIndex {$0.name.caseInsensitiveCompare(namedArgument) == .orderedSame}}
    return parameters.indices.contains(ordinal) ? ordinal:nil
  }
  public static func context(source:String,caret:Int,catalog:SQLIntelligence.Catalog?)->SQLRoutineCall? {
    guard source.utf16.count <= 100_000,caret >= 0,caret <= source.utf16.count,let catalog else {return nil}
    let all=TSQL.lex(source)
    if all.contains(where: {$0.kind == .comment && $0.range.location <= caret && (caret < NSMaxRange($0.range) || caret == NSMaxRange($0.range) && !TSQL.allowsQuotePair(in:source,at:caret))}) {return nil}
    let tokens=all.filter {$0.kind != .space && $0.kind != .comment && $0.range.location < caret}
    guard tokens.count <= 4000 else {return nil}
    func raw(_ text:String)->String {
      if text.hasPrefix("[") {return String(text.dropFirst().dropLast()).replacingOccurrences(of:"]]",with:"]")}
      if text.hasPrefix("\"") {return String(text.dropFirst().dropLast()).replacingOccurrences(of:"\"\"",with:"\"")}
      return text
    }
    func resolve(_ end:Int)->CatalogSymbol? {
      guard end>=0,tokens[end].kind == .word else {return nil}
      var parts=[raw(tokens[end].text)],i=end
      while i>=2,tokens[i-1].text == ".",tokens[i-2].kind == .word {parts.insert(raw(tokens[i-2].text),at:0);i-=2}
      guard parts.count<=2,!(i>0 && tokens[i-1].text == "."),let symbol=catalog.resolve(parts),symbol.kind.contains("PROCEDURE") || symbol.kind.contains("FUNCTION") else {return nil}
      return symbol
    }
    func call(_ symbol:CatalogSymbol,start:Int,args:ArraySlice<Lexeme>)->SQLRoutineCall {
      var depth=0,ordinal=0,chunk:[Lexeme]=[]
      for token in args {
        if token.kind == .symbol && token.text == "(" {depth+=1}
        if token.kind == .symbol && token.text == ")" {depth-=1}
        if depth == 0 && token.kind == .symbol && token.text == "," {ordinal+=1;chunk=[]} else {chunk.append(token)}
      }
      let name=chunk.count>=2 && chunk[0].kind == .variable && chunk[1].text == "=" ? chunk[0].text:nil
      return SQLRoutineCall(symbol:symbol,ordinal:ordinal,namedArgument:name,start:start)
    }
    // Prefer the innermost open, known scalar/table function call.
    var opens:[Int]=[]
    for i in tokens.indices {
      if tokens[i].kind == .symbol && tokens[i].text == "(" {opens.append(i)}
      if tokens[i].kind == .symbol && tokens[i].text == ")" {_=opens.popLast()}
      if tokens[i].kind == .keyword && tokens[i].text.uppercased() == "GO" || tokens[i].text == ";" {opens=[]}
    }
    for i in opens.reversed() where i>0 {
      if let symbol=resolve(i-1),symbol.kind.contains("FUNCTION") {return call(symbol,start:tokens[i-1].range.location,args:tokens[(i+1)...])}
    }
    guard let exec=tokens.lastIndex(where: {$0.kind == .keyword && ["EXEC","EXECUTE"].contains($0.text.uppercased())}) else {return nil}
    var i=exec+1
    if i+2<tokens.count,tokens[i].kind == .variable,tokens[i+1].text == "=" {i+=2}
    guard i<tokens.count,tokens[i].kind == .word else {return nil}
    var end=i
    while end+2<tokens.count,tokens[end+1].text == ".",tokens[end+2].kind == .word {end+=2}
    guard let symbol=resolve(end),caret>=NSMaxRange(tokens[end].range) else {return nil}
    let args=tokens[(end+1)...]
    let boundaries=Set(["GO","SELECT","EXEC","EXECUTE","INSERT","UPDATE","DELETE","MERGE","DECLARE","SET","BEGIN","END","RETURN","CREATE","ALTER","DROP","USE","PRINT","IF","ELSE"])
    guard !args.contains(where: {$0.kind == .symbol && $0.text == ";" || $0.kind == .keyword && boundaries.contains($0.text.uppercased())}) else {return nil}
    return call(symbol,start:tokens[exec].range.location,args:args)
  }
}
