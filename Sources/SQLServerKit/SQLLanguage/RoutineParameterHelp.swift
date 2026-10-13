import Foundation

/// Shared, bounded lexical distinction between a routine signature and its SQL body.
/// The caller supplies tokens without whitespace/comments. Ranges refer to that array.
enum SQLRoutineDefinition {
  struct Header {
    let tokenRange:Range<Int>
    let parameters:[NSRange]
    let hasSQLBody:Bool
  }
  static func isBatchSeparator(_ token:Lexeme,source:NSString)->Bool {
    guard token.kind == .keyword,token.text.uppercased() == "GO" else {return false}
    let line=source.substring(with:source.lineRange(for:token.range))
    return line.range(of:#"^\s*GO(?:[ \t]+[0-9]+)?[ \t]*(?:--[^\r\n]*)?[\r\n]*$"#,
                      options:[.regularExpression,.caseInsensitive]) != nil
  }
  static func headers(in tokens:[Lexeme],source:String)->[Header] {
    let text=source as NSString
    var result:[Header]=[],i=0
    func word(_ index:Int,_ value:String)->Bool {
      index < tokens.count && [.word,.keyword].contains(tokens[index].kind) && tokens[index].text.uppercased() == value
    }
    func identifier(_ index:Int)->Bool {index < tokens.count && tokens[index].kind == .word}
    while i < tokens.count {
      guard tokens[i].kind == .keyword,word(i,"CREATE") || word(i,"ALTER") else {i+=1;continue}
      let start=i
      var kind=i+1
      if word(i,"CREATE"),word(kind,"OR"),word(kind+1,"ALTER") {kind+=2}
      let function=word(kind,"FUNCTION")
      guard function || word(kind,"PROC") || word(kind,"PROCEDURE"),identifier(kind+1) else {i+=1;continue}
      var nameEnd=kind+1
      while nameEnd+2 < tokens.count,tokens[nameEnd+1].text == ".",identifier(nameEnd+2) {nameEnd+=2}
      var j=nameEnd+1,depth=0,parameterDepth=0,expectParameter=true,acceptParameters=true
      var parameters:[NSRange]=[]
      // A function signature is parenthesized; procedures normally omit the parentheses.
      if j < tokens.count,tokens[j].text == "(" {parameterDepth=1}
      else if function {acceptParameters=false}
      var hasSQLBody=false,external=false
      while j < tokens.count {
        let token=tokens[j]
        if isBatchSeparator(token,source:text) {break}
        if depth == 0 {
          if word(j,"AS") {
            // Procedure @p AS int and WITH EXECUTE AS owner belong to the signature.
            let parameterType=j>0 && tokens[j-1].kind == .variable
            let executionContext=j>0 && word(j-1,"EXECUTE")
            if !parameterType && !executionContext {
              external=word(j+1,"EXTERNAL")
              hasSQLBody=j+1 < tokens.count && !external
              break
            }
          }
          if token.kind == .keyword,word(j,"BEGIN") || word(j,"RETURN") {hasSQLBody=true;break}
          if word(j,"RETURNS") || word(j,"WITH") || word(j,"FOR") {acceptParameters=false}
        }
        if acceptParameters,depth == parameterDepth,expectParameter,token.kind == .variable,!token.text.hasPrefix("@@") {
          var type=j+1
          if word(type,"AS") {type+=1}
          // Do not dim an unfinished parameter name or treat a default expression's
          // variable as another declaration. User-defined type names remain valid.
          if type < tokens.count,[.word,.keyword].contains(tokens[type].kind),
            !["AS","RETURNS","WITH","FOR","BEGIN","RETURN"].contains(tokens[type].text.uppercased()),
            !isBatchSeparator(tokens[type],source:text) {
            parameters.append(token.range)
          }
          expectParameter=false
        }
        if token.kind == .symbol {
          if token.text == "(" {depth+=1}
          if token.text == ")" {
            depth=max(0,depth-1)
            if parameterDepth == 1,depth == 0 {acceptParameters=false}
          }
          if token.text == ",",depth == parameterDepth {expectParameter=true}
        }
        j+=1
      }
      result.append(Header(tokenRange:start..<j,parameters:external ? []:parameters,hasSQLBody:hasSQLBody))
      i=max(j,start+1)
    }
    return result
  }
}

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
    let original=source as NSString
    let all=TSQL.lex(source)
    if all.contains(where: {$0.kind == .comment && $0.range.location <= caret && (caret < NSMaxRange($0.range) || caret == NSMaxRange($0.range) && !TSQL.allowsQuotePair(in:source,at:caret))}) {return nil}
    let tokens=all.filter {$0.kind != .space && $0.kind != .comment && $0.range.location < caret}
    guard tokens.count <= 4000 else {return nil}
    // An ALTER/CREATE FUNCTION's name + '(' declares parameters, it does not call
    // that function. End suppression at the body so nested real calls still help.
    guard !SQLRoutineDefinition.headers(in:tokens,source:source).contains(where: {$0.tokenRange.upperBound == tokens.count}) else {return nil}
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
      if SQLRoutineDefinition.isBatchSeparator(tokens[i],source:original) || tokens[i].text == ";" {opens=[]}
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
    guard !args.contains(where: {$0.kind == .symbol && $0.text == ";" || $0.kind == .keyword && boundaries.contains($0.text.uppercased()) && ($0.text.uppercased() != "GO" || SQLRoutineDefinition.isBatchSeparator($0,source:original))}) else {return nil}
    return call(symbol,start:tokens[exec].range.location,args:args)
  }
}
