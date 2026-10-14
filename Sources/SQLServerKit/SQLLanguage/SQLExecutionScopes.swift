import Foundation

/// Conservative lexical execution units. Ambiguous/control-flow batches stay whole;
/// this is a chooser aid, never a parser or an authorization boundary.
public struct SQLExecutionScopes: Sendable {
  public struct Statement: Sendable, Equatable {
    public let range: NSRange
    public let kind: String
    public let batch: NSRange
    public let line: Int
  }
  public let statements: [Statement]
  public init(_ source: String, protectControlFlow: Bool = true) {
    let ns=source as NSString
    guard ns.length <= 250_000,!source.split(whereSeparator: \.isNewline).contains(where:{$0.trimmingCharacters(in:.whitespaces).hasPrefix(":") || $0.trimmingCharacters(in:.whitespaces).hasPrefix("!!")}) else {statements=[];return}
    let tokens=TSQL.lex(source).filter {$0.kind != .space && $0.kind != .comment}
    guard tokens.count <= 30_000 else {statements=[];return}
    var batches:[(NSRange,[Lexeme])]=[],start=0,body:[Lexeme]=[]
    for token in tokens {
      if SQLRoutineDefinition.isBatchSeparator(token,source:ns) {
        let end=NSMaxRange(ns.lineRange(for:token.range))
        batches.append((NSRange(location:start,length:end-start),body));start=end;body=[]
      } else if token.range.location >= start {body.append(token)}
    }
    if start < ns.length {batches.append((NSRange(location:start,length:ns.length-start),body))}
    // Compute line starts once on the analysis worker; menu construction does
    // not rescan a large prefix for every statement. CRLF is one Character.
    var lineStarts=[0],offset=0
    for character in source {offset += character.utf16.count;if character.isNewline {lineStarts.append(offset)}}
    func line(at offset:Int)->Int {
      var low=0,high=lineStarts.count
      while low < high {let mid=(low+high)/2;if lineStarts[mid] <= offset {low=mid+1} else {high=mid}}
      return max(1,low)
    }
    var result:[Statement]=[]
    for (batch,items) in batches where !items.isEmpty {
      func word(_ i:Int)->String {
        guard items.indices.contains(i),items[i].kind == .keyword,
          (i == 0 || items[i-1].text != "."),(i+1 == items.count || items[i+1].text != ".") else {return ""}
        return items[i].text.uppercased()
      }
      let conservative=Set(["IF","WHILE","TRAN","TRANSACTION","COMMIT","ROLLBACK","GOTO","CREATE","ALTER","MERGE","CURSOR","TRY","CATCH"])
      if protectControlFlow && items.indices.contains(where:{conservative.contains(word($0))}) {
        result.append(.init(range:batch,kind:word(0),batch:batch,line:line(at:batch.location)));continue
      }
      var segmentStart=0,depth=0,cases=0,blocks=0,kind="",hasSelect=false
      var ranges:[Statement]=[]
      var starters=Set(["SELECT","DECLARE","SET","USE","PRINT","EXEC","EXECUTE","INSERT","UPDATE","DELETE","WITH","THROW","RAISERROR"])
      starters.insert("BEGIN")
      if !protectControlFlow {starters.formUnion(["BEGIN","END","IF","ELSE","WHILE","RETURN"])}
      let compounds=Set(["UNION","ALL","EXCEPT","INTERSECT"])
      func append(_ end:Int) {
        guard end >= segmentStart,items[segmentStart...end].contains(where:{$0.text != ";"}) else {return}
        let first=items[segmentStart],last=items[end]
        ranges.append(.init(range:NSRange(location:first.range.location,length:NSMaxRange(last.range)-first.range.location),kind:kind,batch:batch,line:line(at:first.range.location)))
      }
      for i in items.indices {
        let upper=word(i),text=items[i].text,previous=i > 0 ? word(i-1):""
        if protectControlFlow,upper == "END",cases == 0,blocks > 0 {blocks -= 1}
        if depth == 0,cases == 0,blocks == 0 {
          // INSERT ... SELECT and WITH ... SELECT are one statement. UNION branches
          // and parenthesized subqueries can never become independently executable.
          let cteContinuation=kind == "WITH" && ["SELECT","INSERT","UPDATE","DELETE","MERGE"].contains(upper)
          let selectStart=upper != "SELECT" || (hasSelect || !["INSERT","WITH"].contains(kind)) && !compounds.contains(previous)
          let hint=upper == "WITH" && i+1 < items.count && items[i+1].text == "("
          let updateClause=upper == "SET" && ["UPDATE","INSERT"].contains(kind)
          let insertExec=["EXEC","EXECUTE"].contains(upper) && kind == "INSERT"
          if i > segmentStart,starters.contains(upper),selectStart,!cteContinuation,!hint,!updateClause,!insertExec,previous != "AS" {
            append(i-1);segmentStart=i;kind="";hasSelect=false
          }
          if kind.isEmpty || cteContinuation {kind=upper}
          if upper == "SELECT" {hasSelect=true}
          if text == ";" {append(i);segmentStart=i+1;kind="";hasSelect=false;continue}
        }
        if protectControlFlow,upper == "BEGIN",cases == 0 {blocks += 1}
        if text == "(" {depth += 1}
        if text == ")" {depth -= 1}
        if upper == "CASE" {cases += 1}
        if upper == "END",cases > 0 {cases -= 1}
      }
      if segmentStart < items.count {append(items.count-1)}
      if depth != 0 || cases != 0 || blocks != 0 || protectControlFlow && ranges.count > 200 {
        result.append(.init(range:batch,kind:word(0),batch:batch,line:line(at:batch.location)))
      } else {result += ranges}
    }
    statements = !protectControlFlow || result.count <= 200 ? result:[]
  }
}
