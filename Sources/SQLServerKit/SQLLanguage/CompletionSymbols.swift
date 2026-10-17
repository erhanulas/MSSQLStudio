import Foundation

/// Best-effort columns for CTEs and derived SELECTs. No query is executed for completion.
enum CompletionSymbols {
  static func collect(_ tokens: [Lexeme], catalog: [CatalogSymbol]) -> [String: [String]] {
    func raw(_ s: String) -> String {
      if s.hasPrefix("[") && s.hasSuffix("]") {
        return String(s.dropFirst().dropLast()).replacingOccurrences(of: "]]", with: "]")
      }
      if s.hasPrefix("\"") && s.hasSuffix("\"") {
        return String(s.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
      }
      return s
    }
    var closes: [Int: Int] = [:]
    var stack: [Int] = []
    for i in tokens.indices {
      if tokens[i].text == "(" { stack.append(i) }
      if tokens[i].text == ")", let open = stack.popLast() { closes[open] = i }
    }
    func projection(_ open: Int, _ close: Int) -> [String] {
      guard
        let start = (open + 1..<close).first(where: { tokens[$0].text.uppercased() == "SELECT" })
      else { return [] }
      var chunks: [[Lexeme]] = []
      var chunk: [Lexeme] = []
      var depth = 0
      for i in start + 1..<close {
        let token = tokens[i]
        if depth == 0 && token.text.uppercased() == "FROM" { break }
        if depth == 0 && token.text == "," {
          chunks.append(chunk)
          chunk = []
          continue
        }
        chunk.append(token)
        if token.text == "(" { depth += 1 }
        if token.text == ")" { depth -= 1 }
      }
      chunks.append(chunk)
      return chunks.compactMap { part in
        if let asIndex = part.lastIndex(where: { $0.text.uppercased() == "AS" }),
          asIndex + 1 < part.count
        {
          return SQL.identifier(raw(part[asIndex + 1].text))
        }
        if part.count > 2, part[1].text == "=" { return SQL.identifier(raw(part[0].text)) }
        guard let last = part.last, last.kind == .word else { return nil }
        return SQL.identifier(raw(last.text))
      }
    }
    var result: [String: [String]] = [:]
    for i in tokens.indices
    where tokens[i].text.uppercased() == "AS" && i > 0 && i + 1 < tokens.count
      && tokens[i + 1].text == "("
    {
      guard let close = closes[i + 1], tokens[i - 1].kind == .word else { continue }
      // CTE declaration: WITH name AS (...), or comma name AS (...).
      guard i >= 2, ["WITH", ","].contains(tokens[i - 2].text.uppercased()) else { continue }
      result[raw(tokens[i - 1].text).lowercased()] = projection(i + 1, close)
    }
    for i in tokens.indices where tokens[i].text == "(" {
      guard let close = closes[i], i + 1 < close, tokens[i + 1].text.uppercased() == "SELECT" else {
        continue
      }
      var alias = close + 1
      if alias < tokens.count && tokens[alias].text.uppercased() == "AS" { alias += 1 }
      if alias < tokens.count, tokens[alias].kind == .word {
        result[raw(tokens[alias].text).lowercased()] = projection(i, close)
      }
    }
    // CTE explicit column names: WITH cte (a,b) AS (...).
    for i in tokens.indices where tokens[i].text == "(" && i > 0 {
      guard let close = closes[i], close + 2 < tokens.count,
        tokens[close + 1].text.uppercased() == "AS", tokens[close + 2].text == "(",
        tokens[i - 1].kind == .word
      else { continue }
      result[raw(tokens[i - 1].text).lowercased()] = tokens[i + 1..<close].filter {
        $0.kind == .word
      }.map { SQL.identifier(raw($0.text)) }
    }
    return result
  }
}

public enum SQLIntelligence {
  public struct Diagnostic: Equatable, Sendable { public let range: NSRange; public let message: String }
  public struct Suggestion: Equatable, Sendable {
    public enum Kind: Sendable { case table, view, procedure, synonym, column, keyword, function, variable }
    public let text: String
    public let label: String
    public let kind: Kind
    public let detail: String
    public let caretOffset:Int?
    public init(text: String, label: String, kind: Kind = .keyword, detail: String = "",caretOffset:Int?=nil) {
      self.text = text; self.label = label; self.kind = kind; self.detail = detail;self.caretOffset=caretOffset
    }
  }
  public struct Analysis: Sendable {
    public let tokens: [Lexeme]
    public let diagnostics: [Diagnostic]
    public let suggestions: [Suggestion]
    public let replacement: NSRange
    public var referenceBindings:[String:[String]] = [:]
    public var procedureCompletion = false
    public var variableCompletion = false
    public var objectCompletion = false
  }
  public final class Catalog: Sendable {
    public let snapshot: SQLCatalogSnapshot
    private let qualified: [String:CatalogSymbol]
    private let names: [String:[CatalogSymbol]]
    private let sorted: [(String,CatalogSymbol)]
    private let routines: [(String,CatalogSymbol)]
    private let readRelations:[(String,CatalogSymbol)]
    private let writeRelations:[(String,CatalogSymbol)]
    private let scalarFunctions:[(String,CatalogSymbol)]
    public var fresh: Bool { Date().timeIntervalSince(snapshot.synchronizedAt) < 300 }
    public init(snapshot: SQLCatalogSnapshot) {
      self.snapshot = snapshot
      var qualified: [String:CatalogSymbol] = [:], names: [String:[CatalogSymbol]] = [:]
      for item in snapshot.symbols { qualified[Self.key(item.schema,item.name)] = item; names[item.name.lowercased(),default:[]].append(item) }
      self.qualified = qualified; self.names = names
      sorted = snapshot.symbols.map { ($0.name.lowercased(),$0) }.sorted { $0.0 == $1.0 ? $0.1.schema < $1.1.schema : $0.0 < $1.0 }
      scalarFunctions=sorted.filter {$0.1.kind.contains("SCALAR_FUNCTION")}
      routines = sorted.filter {$0.1.kind.contains("PROCEDURE") || $0.1.kind.contains("SCALAR_FUNCTION")}
      writeRelations=sorted.filter {["USER_TABLE","VIEW","SYNONYM"].contains($0.1.kind)}
      readRelations=sorted.filter {["USER_TABLE","VIEW","SYNONYM"].contains($0.1.kind) || $0.1.kind.contains("TABLE_VALUED_FUNCTION")}
    }
    private static func key(_ schema: String, _ name: String) -> String { schema.lowercased()+"\u{1f}"+name.lowercased() }
    public func resolve(_ parts: [String]) -> CatalogSymbol? {
      if parts.count == 2 { return qualified[Self.key(parts[0],parts[1])] }
      guard parts.count == 1, let name = parts.first else { return nil }
      if let dbo = qualified[Self.key("dbo",name)] { return dbo }
      let values = names[name.lowercased()] ?? []
      return values.count == 1 ? values[0] : nil
    }
    public func isAmbiguous(_ parts: [String]) -> Bool { parts.count == 1 && (names[parts[0].lowercased()]?.count ?? 0) > 1 && qualified[Self.key("dbo",parts[0])] == nil }
    fileprivate func needsSchema(_ item: CatalogSymbol) -> Bool {
      // User functions always retain their owning schema. Bare relation names
      // are permitted only when the catalog has no naming ambiguity.
      (names[item.name.lowercased()]?.count ?? 0) > 1 || item.kind.contains("FUNCTION")
    }
    public func matchingRoutines(_ text:String,schema:String?=nil,limit:Int=100) throws -> [CatalogSymbol] {
      try containing(text,schema:schema,limit:limit,in:routines)
    }
    fileprivate func matchingScalarFunctions(_ text:String,schema:String?,limit:Int=100)throws->[CatalogSymbol] {
      try containing(text,schema:schema,limit:limit,in:scalarFunctions)
    }
    private func containing(_ text:String,schema:String?,limit:Int,in entries:[(String,CatalogSymbol)]) throws -> [CatalogSymbol] {
      let needle=text.lowercased(), schema=schema?.lowercased(), limit=max(0,min(limit,100))
      var result:[CatalogSymbol]=[]
      // Prefer prefixes, then interior matches; unrelated relations cannot consume the limit.
      for prefixPass in [true,false] {
        for (index,pair) in entries.enumerated() {
          if index%256 == 0 {try Task.checkCancellation()}
          guard result.count<limit else {return result}
          let (name,item)=pair
          guard schema == nil || item.schema.lowercased() == schema else {continue}
          let prefix=name.hasPrefix(needle)
          if prefixPass ? prefix : !prefix && name.contains(needle) {result.append(item)}
        }
      }
      return result
    }
    public func matches(_ prefix: String, schema: String? = nil, limit: Int = 100) -> [CatalogSymbol] {
      matchingPrefix(prefix,schema:schema,limit:limit,in:sorted)
    }
    fileprivate func matchingRelations(_ prefix:String,schema:String?,read:Bool) throws ->[CatalogSymbol] {
      try containing(prefix,schema:schema,limit:100,in:read ? readRelations:writeRelations)
    }
    private func matchingPrefix(_ prefix:String,schema:String?,limit:Int,in entries:[(String,CatalogSymbol)])->[CatalogSymbol] {
      let prefix = prefix.lowercased()
      var low = 0, high = entries.count
      while low < high { let mid = (low+high)/2; if entries[mid].0 < prefix { low = mid+1 } else { high = mid } }
      var result: [CatalogSymbol] = []
      while low < entries.count, entries[low].0.hasPrefix(prefix), result.count < max(0,min(limit,100)) {
        let item = entries[low].1
        if schema == nil || item.schema.lowercased() == schema!.lowercased() { result.append(item) }
        low += 1
      }
      return result
    }
  }
  private struct Binding {
    let alias: String
    var explicitAlias = false
    let parts: [String]
    let columns: [String]?
    let scope: NSRange
  }
  private static func raw(_ value: String) -> String {
    if value.hasPrefix("[") {
      var inner = String(value.dropFirst())
      if inner.hasSuffix("]") { inner.removeLast() }
      return inner.replacingOccurrences(of:"]]",with:"]")
    }
    if value.hasPrefix("\"") {
      var inner = String(value.dropFirst())
      if inner.hasSuffix("\"") { inner.removeLast() }
      return inner.replacingOccurrences(of:"\"\"",with:"\"")
    }
    return value
  }
  // SQL Server's reserved identifier words are broader than the editor's syntax palette.
  // Keep this check local to completion: DDL/CRUD SQL.identifier remains always delimited.
  // https://learn.microsoft.com/sql/t-sql/language-elements/reserved-keywords-transact-sql
  private static let reservedIdentifiers = TSQL.keywords.union(
    "ADD EXTERNAL PUBLIC FILE FILLFACTOR READ ANY FOR READTEXT AUTHORIZATION FREETEXT FREETEXTTABLE REPLICATION BACKUP RESTORE RESTRICT BREAK GOTO REVERT BROWSE BULK CASCADE HOLDLOCK ROWCOUNT IDENTITY ROWGUIDCOL IDENTITY_INSERT RULE CHECKPOINT IDENTITYCOL SAVE CLOSE SCHEMA SECURITYAUDIT COALESCE COLLATE SEMANTICKEYPHRASETABLE COLUMN SEMANTICSIMILARITYDETAILSTABLE SEMANTICSIMILARITYTABLE COMPUTE SESSION_USER CONTAINS SETUSER CONTAINSTABLE SHUTDOWN CONTINUE KILL SOME CONVERT STATISTICS SYSTEM_USER LINENO CURRENT LOAD TABLESAMPLE CURRENT_DATE TEXTSIZE CURRENT_TIME NATIONAL NOCHECK TO CURRENT_TIMESTAMP CURRENT_USER CURSOR DATABASE DBCC NULLIF OF TRUNCATE OFF TRY_CONVERT OFFSETS TSEQUAL OPEN UNPIVOT DISK OPENDATASOURCE OPENQUERY OPENROWSET UPDATETEXT DISTRIBUTED OPENXML DOUBLE OPTION USER DUMP VARYING WAITFOR ERRLVL PERCENT ESCAPE PIVOT PLAN WHILE PRECISION WITHIN WRITETEXT EXIT PROC LABEL".split(separator:" ").map(String.init))
  private static func completionIdentifier(_ name: String, alwaysQuote: Bool) -> String {
    guard !alwaysQuote, let first = name.unicodeScalars.first,
      first.value <= 0xffff, CharacterSet.letters.contains(first) || first == "_",
      !reservedIdentifiers.contains(name.uppercased()),
      name.unicodeScalars.allSatisfy({ scalar in
        scalar.value <= 0xffff && (CharacterSet.letters.contains(scalar)
          || CharacterSet.decimalDigits.contains(scalar) || "_@$#".unicodeScalars.contains(scalar))
      })
    else { return SQL.identifier(name) }
    return name
  }
  public static func alias(for name: String, occupied: Set<String>) -> String {
    var initials = "", previous: Character?
    for character in name {
      if character.isLetter && (previous == nil || previous?.isLetter == false || character.isUppercase && previous?.isLowercase == true) { initials.append(contentsOf:character.lowercased()) }
      previous = character
    }
    if initials.isEmpty { initials = "t" }
    initials = String(initials.prefix(8))
    if TSQL.keywords.contains(initials.uppercased()) { initials += "t" }
    let occupied = Set(occupied.map { $0.lowercased() })
    var candidate = initials, suffix = 2
    while occupied.contains(candidate.lowercased()) { candidate = initials+String(suffix); suffix += 1 }
    return candidate.uppercased()
  }
  public static func analyze(source: String, caret: Int, catalog: Catalog?, verified: Bool, automaticAliases: Bool = true, automaticNoLock: Bool = false, includeSchema: Bool = true, quoteIdentifiers: Bool = true, currentDatabase:String? = nil) throws -> Analysis {
    try Task.checkCancellation()
    let original = source as NSString, caret = max(0,min(caret,original.length))
    guard original.length <= 250_000 else { return Analysis(tokens:[],diagnostics:[],suggestions:[],replacement:NSRange(location:caret,length:0)) }
    let all = TSQL.lex(source)
    guard original.length <= 100_000 else { return Analysis(tokens:all,diagnostics:[],suggestions:[],replacement:NSRange(location:caret,length:0)) }
    let active = all.first { [.word,.keyword,.variable].contains($0.kind) && caret >= $0.range.location && caret <= NSMaxRange($0.range) }
    let wildcard=all.first {$0.text == "*" && caret >= $0.range.location && caret <= NSMaxRange($0.range)}
    let replacement = wildcard?.range ?? active?.range ?? NSRange(location:caret,length:0)
    let prefix = raw(original.substring(with:NSRange(location:replacement.location,length:caret-replacement.location)))
    let inLiteral = all.contains { [.string,.comment].contains($0.kind) && caret > $0.range.location && (caret < NSMaxRange($0.range) || caret == NSMaxRange($0.range) && ($0.kind == .comment || !$0.text.hasSuffix("'"))) }
    let tokens = all.filter { ![.space,.comment,.string].contains($0.kind) }
    guard tokens.count <= 4_000 else { return Analysis(tokens:all,diagnostics:[],suggestions:[],replacement:replacement) }
    var closes: [Int:Int] = [:], stack: [Int] = [], parents: [Int:Int] = [:]
    for i in tokens.indices {
      if let parent = stack.last { parents[i] = parent }
      if tokens[i].text == "(" { stack.append(i) }
      if tokens[i].text == ")", let open = stack.popLast() { closes[open] = i }
    }
    // SQL Server also permits consecutive SELECT statements without semicolons.
    // Each SELECT arm owns its FROM bindings, including UNION and nested queries.
    // WHEN actions belong to their MERGE statement, not independent DML scopes.
    var mergeAt:[Int:Int]=[:],currentMerge:[Int:Int]=[:]
    for i in tokens.indices {
      let parent=parents[i] ?? -1,word=tokens[i].text.uppercased()
      if word=="MERGE" {currentMerge[parent]=i}
      if let merge=currentMerge[parent] {mergeAt[i]=merge}
      if tokens[i].text==";" || SQLRoutineDefinition.isBatchSeparator(tokens[i],source:original) {currentMerge[parent]=nil}
    }
    let selects=tokens.indices.filter {
      tokens[$0].kind == .keyword && ["SELECT","UPDATE","DELETE","INSERT","MERGE"].contains(tokens[$0].text.uppercased())
        && !(mergeAt[$0] != nil && ["UPDATE","DELETE","INSERT"].contains(tokens[$0].text.uppercased()))
    }
    var starts = [Int](repeating:0,count:tokens.count), ends = [Int](repeating:original.length,count:tokens.count), start = 0
    for i in tokens.indices {
      starts[i] = start
      if parents[i] == nil && [";","GO"].contains(tokens[i].text.uppercased()) { start = NSMaxRange(tokens[i].range) }
    }
    var end = original.length
    for i in tokens.indices.reversed() {
      if parents[i] == nil && [";","GO"].contains(tokens[i].text.uppercased()) { end = tokens[i].range.location }
      ends[i] = end
    }
    for i in tokens.indices {
      let peers=selects.filter {parents[$0] == parents[i] && $0 >= 0 && tokens[$0].range.location >= starts[i] && tokens[$0].range.location < ends[i]}
      if let previous=peers.last(where:{$0 <= i}) {starts[i]=tokens[previous].range.location}
      if let next=peers.first(where:{$0 > i}) {ends[i]=tokens[next].range.location}
    }
    func scope(_ i: Int) -> NSRange {
      if let open = parents[i], let close = closes[open] { return NSIntersectionRange(NSRange(location:NSMaxRange(tokens[open].range),length:max(0,tokens[close].range.location-NSMaxRange(tokens[open].range))),NSRange(location:starts[i],length:max(0,ends[i]-starts[i]))) }
      return NSRange(location:starts[i],length:max(0,ends[i]-starts[i]))
    }
    func contains(_ range: NSRange, _ location: Int) -> Bool { location >= range.location && location <= NSMaxRange(range) }
    var local = CompletionSymbols.collect(tokens,catalog:catalog?.snapshot.symbols ?? [])
    // Script-local tables are resolved before the database index, including #temp and @table.
    for i in tokens.indices where tokens[i].text.uppercased() == "TABLE" {
      var j = i+1, parts: [String] = []
      if i > 0 && tokens[i-1].kind == .variable { parts = [raw(tokens[i-1].text)] }
      else {
        while j < tokens.count, tokens[j].kind == .word {
          parts.append(raw(tokens[j].text)); j += 1
          if j < tokens.count, tokens[j].text == "." { j += 1 } else { break }
        }
      }
      guard !parts.isEmpty, j < tokens.count, tokens[j].text == "(", let close = closes[j] else { continue }
      var columns: [String] = [], first = true, depth = 0
      for k in j+1..<close {
        if tokens[k].text == "(" { depth += 1 }; if tokens[k].text == ")" { depth -= 1 }
        if depth == 0 && first && tokens[k].kind == .word { columns.append(raw(tokens[k].text)); first = false }
        if depth == 0 && tokens[k].text == "," { first = true }
      }
      local[parts.map { $0.lowercased() }.joined(separator:".")] = columns
      if let name = parts.last { local[name.lowercased()] = columns }
    }
    var triggerParts:[String]?
    var triggerHeaderEnd=0
    if let trigger=tokens.indices.last(where: {tokens[$0].text.uppercased() == "TRIGGER" && $0>0 && ["CREATE","ALTER"].contains(tokens[$0-1].text.uppercased()) && tokens[$0].range.location <= caret}),
      let on=((trigger+1)..<min(tokens.count,trigger+128)).first(where:{["ON","GO"].contains(tokens[$0].text.uppercased())}),tokens[on].text.uppercased() == "ON" {
      var j=on+1,parts:[String]=[]
      while j<tokens.count,[Lexeme.Kind.word,.keyword].contains(tokens[j].kind) {
        parts.append(raw(tokens[j].text));triggerHeaderEnd=NSMaxRange(tokens[j].range);j+=1
        if j<tokens.count,tokens[j].text == "." {j+=1} else {break}
      }
      // A database-qualified DML target can use this catalog only when its
      // database is explicitly the editor's database. Never infer remote columns.
      if parts.count==3,let currentDatabase,parts[0].utf8.elementsEqual(currentDatabase.utf8) {parts.removeFirst()}
      if (1...2).contains(parts.count),!parts.contains(where:{["DATABASE","ALL","SERVER"].contains($0.uppercased())}),
        !tokens.contains(where:{$0.text.uppercased() == "GO" && $0.range.location>triggerHeaderEnd && $0.range.location<caret}) {
        triggerParts=parts
        if let columns=catalog?.resolve(parts)?.columns {local["inserted"]=columns;local["deleted"]=columns}
      }
    }
    local = local.mapValues { $0.map(raw) }
    var bindings: [Binding] = [], ignored = Set<Int>(), diagnostics: [Diagnostic] = []
    var references: [(Int,[String],NSRange)] = []
    var targets:[(index:Int,verb:String)]=[]
    var insertLists: [(open: Int, binding: Int)] = []
    var mergeSources:[(binding:Int,body:NSRange?)]=[]
    for i in tokens.indices where ["FROM","JOIN","UPDATE","DELETE","INSERT","INTO","APPLY","EXEC","EXECUTE","MERGE","USING"].contains(tokens[i].text.uppercased()) {
      try Task.checkCancellation()
      var j = i+1, parts: [String] = [], indices: [Int] = []
      let verb=tokens[i].text.uppercased()
      if j < tokens.count,tokens[j].text.uppercased() == "TOP" {
        j+=1
        if j < tokens.count,tokens[j].text == "(",let close=closes[j] {j=close+1}
        else if j < tokens.count,tokens[j].kind == .number {j+=1}
        if j < tokens.count,tokens[j].text.uppercased() == "PERCENT" {j+=1}
      }
      if ["DELETE","INSERT","MERGE"].contains(verb),j < tokens.count,["FROM","INTO"].contains(tokens[j].text.uppercased()) {continue}
      if verb=="USING",mergeAt[i]==nil {continue}
      if j < tokens.count, tokens[j].text == "(", let close = closes[j] {
        let body=NSRange(location:NSMaxRange(tokens[j].range),length:max(0,tokens[close].range.location-NSMaxRange(tokens[j].range)))
        j = close+1; if j < tokens.count && tokens[j].text.uppercased() == "AS" { j += 1 }
        if j < tokens.count, tokens[j].kind == .word {
          let name = raw(tokens[j].text); ignored.insert(j)
          bindings.append(Binding(alias:name,explicitAlias:true,parts:[name],columns:local[name.lowercased()],scope:scope(i)))
          if verb=="USING" {mergeSources.append((bindings.count-1,body))}
        }
        continue
      }
      while j < tokens.count, [.word,.variable].contains(tokens[j].kind) {
        parts.append(raw(tokens[j].text)); indices.append(j); j += 1
        if j < tokens.count && tokens[j].text == "." { ignored.insert(j); j += 1 } else { break }
      }
      guard !parts.isEmpty else { continue }
      ignored.formUnion(indices)
      let name = parts.joined(separator:".").lowercased(), resolved = catalog?.resolve(parts)
      let head = selects.last { $0 <= i && parents[$0] == parents[i] && tokens[$0].range.location >= starts[i] }
      let insertTarget = verb == "INSERT" || verb == "INTO" && head.map { tokens[$0].text.uppercased() == "INSERT" } == true
      var columnStart = j
      if insertTarget, columnStart < tokens.count, tokens[columnStart].text.uppercased() == "WITH",
        columnStart + 1 < tokens.count, tokens[columnStart + 1].text == "(", let close = closes[columnStart + 1] { columnStart = close + 1 }
      let insertOpen = insertTarget && columnStart < tokens.count && tokens[columnStart].text == "(" ? columnStart : nil
      let mergeTarget=verb=="MERGE" || verb=="INTO" && head.map {tokens[$0].text.uppercased()=="MERGE"} == true
      if mergeTarget,j+1<tokens.count,tokens[j].text.uppercased()=="WITH",tokens[j+1].text=="(",let close=closes[j+1] {j=close+1}
      var alias = parts.last!, explicitAlias = false
      if j < tokens.count && tokens[j].text == "(", let close = closes[j] { j = close+1 }
      if j < tokens.count && tokens[j].text.uppercased() == "AS" { ignored.insert(j); j += 1 }
      if j < tokens.count && tokens[j].kind == .word { alias = raw(tokens[j].text); explicitAlias = true; ignored.insert(j) }
      let columns = local[name] ?? (resolved?.kind == "SYNONYM" ? nil : resolved?.columns)
      bindings.append(Binding(alias:alias,explicitAlias:explicitAlias,parts:parts,columns:columns,scope:scope(i)))
      if verb=="USING" {mergeSources.append((bindings.count-1,nil))}
      if let insertOpen { insertLists.append((insertOpen, bindings.count - 1)) }
      if ["UPDATE","DELETE","INSERT","INTO","MERGE"].contains(verb) {targets.append((bindings.count-1,mergeTarget ? "MERGE":verb))}
      if verb == "FROM",let head=tokens.indices.last(where:{$0<i && parents[$0]==parents[i] && tokens[$0].range.location>=starts[i] && ["SELECT","UPDATE","DELETE","INSERT"].contains(tokens[$0].text.uppercased())}),tokens[head].text.uppercased() == "DELETE",!targets.contains(where:{$0.verb == "DELETE" && bindings[$0.index].scope == scope(i)}) {targets.append((bindings.count-1,"DELETE"))}
      references.append((i,parts,NSRange(location:tokens[indices[0]].range.location,length:NSMaxRange(tokens[indices.last!].range)-tokens[indices[0]].range.location)))
    }
    for i in tokens.indices where tokens[i].text.uppercased()=="INSERT" && mergeAt[i] != nil {
      guard i+1<tokens.count,tokens[i+1].text=="(",
        let target=targets.first(where:{$0.verb=="MERGE" && bindings[$0.index].scope==scope(i)}) else {continue}
      insertLists.append((i+1,target.index))
    }
    // An UPDATE/DELETE target may name a FROM alias. Resolve that target from
    // the same statement before de-duplicating; an unresolved target must not
    // shadow the later concrete relation (UPDATE NWS ... FROM dbo.News NWS).
    for target in targets {
      let binding=bindings[target.index]
      if binding.columns == nil,binding.parts.count == 1,
        let concrete=bindings.first(where:{$0.scope == binding.scope && $0.alias.lowercased() == binding.alias.lowercased() && $0.columns != nil}) {
        bindings[target.index]=Binding(alias:binding.alias,explicitAlias:true,parts:concrete.parts,columns:concrete.columns,scope:binding.scope)
      }
    }
    if let triggerParts {
      for index in bindings.indices where bindings[index].parts.count == 1 && ["inserted","deleted"].contains(bindings[index].parts[0].lowercased()) {
        let binding=bindings[index]
        bindings[index]=Binding(alias:binding.alias,explicitAlias:binding.explicitAlias,parts:triggerParts,columns:binding.columns,scope:binding.scope)
      }
      let scope=NSRange(location:0,length:original.length)
      for name in ["inserted","deleted"] {bindings.append(Binding(alias:name,explicitAlias:true,parts:triggerParts,columns:catalog?.resolve(triggerParts)?.columns,scope:scope))}
    }
    let targetBindings=targets.map {($0.verb,bindings[$0.index])}
    for (verb,binding) in targetBindings {
      let names=["UPDATE","MERGE"].contains(verb) ? ["inserted","deleted"] : verb == "DELETE" ? ["deleted"] : ["inserted"]
      // OUTPUT pseudo-tables are offered only after an OUTPUT in this scope.
      if tokens.contains(where:{$0.text.uppercased() == "OUTPUT" && contains(binding.scope,$0.range.location) && $0.range.location < caret}) {
        for name in names {bindings.append(Binding(alias:name,explicitAlias:true,parts:binding.parts,columns:binding.columns,scope:binding.scope))}
      }
    }
    guard bindings.count <= 128 else { return Analysis(tokens:all,diagnostics:[],suggestions:[],replacement:replacement) }
    var mergeExclusions:[(range:NSRange,indices:Set<Int>)]=[]
    for source in mergeSources {
      let binding=bindings[source.binding]
      if let body=source.body {
        // USING derived SELECTs cannot reference their own alias or the target.
        mergeExclusions.append((body,Set(bindings.indices.filter {bindings[$0].scope==binding.scope})))
      }
      guard let target=targets.first(where:{$0.verb=="MERGE" && bindings[$0.index].scope==binding.scope}),
        let merge=tokens.indices.first(where:{tokens[$0].range.location==binding.scope.location && tokens[$0].text.uppercased()=="MERGE"}) else {continue}
      let peers=tokens.indices.filter {mergeAt[$0]==merge}
      let actions=peers.filter {tokens[$0].text.uppercased()=="WHEN"}
      for (offset,action) in actions.enumerated() {
        var end=offset+1<actions.count ? tokens[actions[offset+1]].range.location:NSMaxRange(binding.scope)
        let body=peers.filter {$0>=action && tokens[$0].range.location<end}
        if let output=body.first(where:{["OUTPUT","OPTION"].contains(tokens[$0].text.uppercased())}) {end=tokens[output].range.location}
        if body.contains(where:{$0>0 && tokens[$0].text.uppercased()=="SOURCE" && tokens[$0-1].text.uppercased()=="BY"}) {
          mergeExclusions.append((NSRange(location:tokens[action].range.location,length:max(0,end-tokens[action].range.location)),[source.binding]))
        }
        if body.contains(where:{tokens[$0].text.uppercased()=="INSERT"}),let values=body.first(where:{tokens[$0].text.uppercased()=="VALUES"}) {
          mergeExclusions.append((NSRange(location:tokens[values].range.location,length:max(0,end-tokens[values].range.location)),[target.index]))
        }
      }
    }
    func activeBindings(_ location: Int) -> [Binding] {
      var excluded=Set<Int>()
      for exclusion in mergeExclusions where contains(exclusion.range,location) {excluded.formUnion(exclusion.indices)}
      let visible=bindings.indices.filter { !excluded.contains($0) && contains(bindings[$0].scope,location) }.map {bindings[$0]}.sorted {$0.scope.length<$1.scope.length}
      var seen = Set<String>()
      return visible.filter { seen.insert($0.alias.lowercased()).inserted }
    }
    func isEditing(_ range: NSRange) -> Bool {
      if caret == NSMaxRange(range), range.length > 0, original.substring(with:NSRange(location:caret-1,length:1)) == "]" { return false }
      return contains(range,caret)
    }
    let suppressValidation = tokens.contains { ["USE","CREATE","ALTER","DROP","PIVOT","UNPIVOT"].contains($0.text.uppercased()) }
    if verified, catalog?.fresh == true, !suppressValidation {
      for (i,parts,range) in references {
        let key = parts.joined(separator:".").lowercased()
        let systemRoutine = ["EXEC","EXECUTE"].contains(tokens[i].text.uppercased()) && TSQL.isSystemProcedure(parts)
        let systemRelation = ["FROM","JOIN","APPLY"].contains(tokens[i].text.uppercased()) && parts.count == 1 && TSQL.tableFunctions.contains(parts[0].uppercased()) && tokens.first(where:{$0.range.location>=NSMaxRange(range)})?.text == "("
        let special = systemRoutine || systemRelation || parts.count > 2 || parts.first?.lowercased() == "sys" || parts.first?.lowercased() == "information_schema" || parts.last?.hasPrefix("#") == true || parts.last?.hasPrefix("@") == true
        let updateAlias = ["UPDATE","FROM","DELETE"].contains(tokens[i].text.uppercased()) && activeBindings(range.location).contains { $0.alias.lowercased() == key && $0.parts.map { $0.lowercased() }.joined(separator:".") != key }
        if !special && local[key] == nil && catalog?.resolve(parts) == nil && catalog?.isAmbiguous(parts) != true && !updateAlias && !isEditing(range) {
          diagnostics.append(Diagnostic(range:range,message:"Nesne güncel DDL indeksinde bulunamadı: \(parts.joined(separator:"."))"))
        }
      }
      var outputAliasTokens=Set<Int>()
      var outputAliases:[Int:Set<String>]=[:]
      func registerOutputAlias(_ i:Int,select:Int) {
        outputAliasTokens.insert(i)
        outputAliases[select,default:[]].insert(raw(tokens[i].text).lowercased())
      }
      // Only SELECT-list identifiers define output aliases. Assignment-style
      // aliases are expression heads, never WHERE comparisons or UPDATE targets.
      for select in selects where tokens[select].text.uppercased()=="SELECT" {
        var first=select+1
        if first<tokens.count && ["DISTINCT","ALL"].contains(tokens[first].text.uppercased()) {first+=1}
        if first<tokens.count && tokens[first].text.uppercased()=="TOP" {
          first+=1
          if let close=closes[first] {first=close+1} else {first+=1}
          if first<tokens.count && tokens[first].text.uppercased()=="PERCENT" {first+=1}
          if first+1<tokens.count && tokens[first].text.uppercased()=="WITH" && tokens[first+1].text.uppercased()=="TIES" {first+=2}
        }
        ignored.formUnion((select+1)..<min(first,tokens.count))
        let peers=tokens.indices.filter {$0>=first && parents[$0]==parents[select] && contains(scope(select),tokens[$0].range.location)}
        var head=true
        for i in peers {
          let upper=tokens[i].text.uppercased()
          if ["FROM","INTO","WHERE","UNION","EXCEPT","INTERSECT",";","GO"].contains(upper) {break}
          if tokens[i].text=="," {head=true;continue}
          if head && (tokens[i].kind == .number || tokens[i].kind == .variable || tokens[i].text=="(") {head=false;continue}
          if tokens[i].kind == .word {
            if head && i+1<tokens.count && tokens[i+1].text=="=" {registerOutputAlias(i,select:select)}
            if i>0 && tokens[i-1].text.uppercased()=="AS" {registerOutputAlias(i,select:select)}
          }
          head=false
        }
      }
      var clauses: [String?] = [], clausesByParent:[Int:String]=[:]
      for i in tokens.indices {
        let key=parents[i] ?? -1,upper=tokens[i].text.uppercased()
        if ["SELECT","FROM","JOIN","WHERE","ON","SET","HAVING","ORDER","GROUP"].contains(upper) {clausesByParent[key]=upper}
        var parent=key
        while clausesByParent[parent]==nil && parent != -1 {parent=parents[parent] ?? -1}
        clauses.append(clausesByParent[parent])
        if i>0,tokens[i-1].text.uppercased()=="AS",let open=parents[i],open>0,["CAST","TRY_CAST"].contains(tokens[open-1].text.uppercased()) {ignored.insert(i)}
      }
      var predecessors: [Int:Lexeme] = [:], preceding: Lexeme?
      for token in all where token.kind != .space && token.kind != .comment {
        if let preceding { predecessors[token.range.location] = preceding }; preceding = token
      }
      // A SELECT expression may name its output without AS. Do not diagnose that output name.
      for i in tokens.indices where i > 0 && tokens[i].kind == .word && clauses[i] == "SELECT" {
        let previous = predecessors[tokens[i].range.location] ?? tokens[i-1]
        if (previous.kind == .word || previous.kind == .string || previous.kind == .number || previous.text == ")") && (i+1 == tokens.count || [",","FROM"].contains(tokens[i+1].text.uppercased())) {
          if let select=selects.last(where:{$0<i && parents[$0]==parents[i] && contains(scope($0),tokens[i].range.location) && tokens[$0].text.uppercased()=="SELECT"}) {registerOutputAlias(i,select:select)}
        }
      }
      let commaSources = tokens.indices.contains { tokens[$0].text == "," && clauses[$0] == "FROM" }
      for i in tokens.indices where tokens[i].kind == .word && !ignored.contains(i) {
        try Task.checkCancellation()
        let token = tokens[i], name = raw(token.text).lowercased()
        if isEditing(token.range) || outputAliasTokens.contains(i) { continue }
        let visible = activeBindings(token.range.location)
        if i >= 2 && tokens[i-1].text == "." {
          let qualifier = raw(tokens[i-2].text).lowercased()
          if let binding = visible.first(where: { $0.alias.lowercased() == qualifier }), let columns = binding.columns, !columns.isEmpty,
            !columns.contains(where: { $0.lowercased() == name }) {
            diagnostics.append(Diagnostic(range:token.range,message:"\(binding.alias) için kolon DDL indeksinde bulunamadı: \(raw(token.text))"))
          }
          continue
        }
        if clauses[i]=="ORDER" && outputAliases.contains(where:{contains(scope($0.key),token.range.location) && parents[$0.key]==parents[i] && $0.value.contains(name)}) {continue}
        if i+1 < tokens.count && [".","("].contains(tokens[i+1].text) { continue }
        guard !commaSources, !visible.isEmpty, visible.allSatisfy({ $0.columns?.isEmpty == false }) else { continue }
        // Restrict bare-column inspection to ordinary SELECT/expression clauses, not declarations or aliases.
        let prior = clauses[i]
        guard ["SELECT","WHERE","ON","SET","HAVING","ORDER","GROUP","BY"].contains(prior ?? ""), !TSQL.functions.contains(token.text.uppercased()) else { continue }
        if !visible.contains(where: { $0.columns?.contains(where: { $0.lowercased() == name }) == true }) {
          diagnostics.append(Diagnostic(range:token.range,message:"Kolon bu sorgunun DDL kapsamındaki kaynaklarında bulunamadı: \(raw(token.text))"))
        }
      }
    }
    var suggestions: [Suggestion] = []
    let before = tokens.filter { NSMaxRange($0.range) <= replacement.location }
    let qualifier = before.last?.text == "." && before.count >= 2 ? raw(before[before.count-2].text) : nil
    let visible = activeBindings(caret)
    let insertList = insertLists.last { list in
      let open = tokens[list.open]
      let end = closes[list.open].map { tokens[$0].range.location } ?? original.length
      guard replacement.location >= NSMaxRange(open.range), caret <= end else { return false }
      let between = tokens[(list.open + 1)...].prefix { $0.range.location < replacement.location }
      guard !between.contains(where: { $0.text == ";" || SQLRoutineDefinition.isBatchSeparator($0, source: original) || $0.kind == .keyword && ["VALUES","SELECT","OUTPUT","INSERT","UPDATE","DELETE","MERGE"].contains($0.text.uppercased()) }) else { return false }
      return before.last?.text == "(" || before.last?.text == ","
    }
    let insertBinding = insertList.map { list -> Binding in
      let binding = bindings[list.binding]
      let end = closes[list.open] ?? tokens.count
      let used = Set(tokens.indices.filter { $0 > list.open && $0 < end && parents[$0] == list.open && tokens[$0].range != replacement && [.word,.keyword].contains(tokens[$0].kind) }.map { raw(tokens[$0].text).lowercased() })
      return Binding(alias: binding.alias, explicitAlias: false, parts: binding.parts,
        columns: binding.columns?.filter { !used.contains($0.lowercased()) }, scope: binding.scope)
    }
    func identifier(_ name: String) -> String { completionIdentifier(name, alwaysQuote: quoteIdentifiers) }
    let needle = prefix.lowercased()
    func appendColumns(from bindings: [Binding], alreadyQualified: Bool) throws {
      // Prefixes across every visible source precede interior matches. Do not let
      // an earlier, wide relation consume all 100 slots before a closer prefix.
      var seen = Set<String>()
      for prefixPass in [true, false] {
        for binding in bindings {
          for (index, column) in (binding.columns ?? []).enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            guard suggestions.count < 100 else { return }
            let name = column.lowercased(), isPrefix = name.hasPrefix(needle)
            guard prefixPass ? isPrefix : !isPrefix && name.contains(needle) else { continue }
            // Only an alias already written in this statement may qualify columns.
            let qualifier = alreadyQualified ? "" : binding.explicitAlias ? identifier(binding.alias)+"."
              : visible.count == 1 ? "" : binding.parts.map(identifier).joined(separator:".")+"."
            let text = qualifier+identifier(column)
            guard seen.insert(text).inserted else { continue }
            let label = alreadyQualified ? identifier(binding.alias)+"."+identifier(column) : text
            suggestions.append(Suggestion(text:text,label:label,kind:.column,detail:binding.parts.joined(separator:".")))
          }
        }
      }
    }
    var context = before
    if qualifier != nil { context = Array(context.dropLast(2)) }
    let remoteQualifier=qualifier != nil && context.last?.text == "."
    let inDefinitionHeader=SQLRoutineDefinition.headers(in:tokens,source:source).contains {header in
      let start=tokens[header.tokenRange.lowerBound].range.location
      let end=header.tokenRange.upperBound < tokens.count ? tokens[header.tokenRange.upperBound].range.location:original.length+1
      return replacement.location>=start && replacement.location<end
    }
    let returnAssignment=context.count>=3 && context.last?.text == "=" && context[context.count-2].kind == .variable && ["EXEC","EXECUTE"].contains(context[context.count-3].text.uppercased())
    let execution = !inDefinitionHeader && (["EXEC","EXECUTE"].contains(context.last?.text.uppercased() ?? "") || returnAssignment) && !prefix.hasPrefix("@")
    var clauses=[""]
    let clauseWords=Set(["SELECT","FROM","JOIN","APPLY","WHERE","ON","HAVING","SET","ORDER","GROUP","BY","OUTPUT","VALUES","RETURN","EXEC","EXECUTE","DECLARE","CREATE","ALTER","DROP","INSERT","UPDATE","DELETE","INTO","UNION"])
    for (index,token) in before.enumerated() {
      if token.text == "(" {
        var inherited=clauses.last ?? ""
        if index>0 {
          var j=index-1,parts=[raw(before[j].text)]
          while j>=2,before[j-1].text == "." {j-=2;parts.insert(raw(before[j].text),at:0)}
          if catalog?.resolve(parts)?.kind.contains("FUNCTION") == true || TSQL.functions.contains(before[index-1].text.uppercased()) {inherited="CALL"}
        }
        clauses.append(inherited)
      } else if token.text == ")" {if clauses.count>1 {clauses.removeLast()}}
      else if token.text == ";" || SQLRoutineDefinition.isBatchSeparator(token,source:original) {clauses=[""]}
      else if token.kind == .keyword,clauseWords.contains(token.text.uppercased()) {clauses[clauses.count-1]=token.text.uppercased()}
    }
    let clause=clauses.last ?? ""
    let readPosition=["FROM","JOIN","APPLY","USING"].contains(context.last?.text.uppercased() ?? "") || context.last?.text == "," && clause == "FROM"
    let objectPosition = execution || readPosition || ["UPDATE","DELETE","INSERT","INTO","MERGE"].contains(context.last?.text.uppercased() ?? "")
    let prior=qualifier == nil ? all.last {![.space,.comment].contains($0.kind) && NSMaxRange($0.range)<=replacement.location}:context.last
    let priorIsOperand=prior.map {[Lexeme.Kind.word,.variable,.number,.string].contains($0.kind) || $0.text == ")"} ?? false
    let topNumber=context.count>=2 && context[context.count-2].text.uppercased() == "TOP"
    let topParenthesis=prior?.text == ")" && closes.contains {open,close in open>0 && tokens[open-1].text.uppercased() == "TOP" && tokens[close].range == prior?.range}
    let scalarPosition = !remoteQualifier && !inDefinitionHeader && context.last?.text.uppercased() != "AS" && ["SELECT","WHERE","ON","HAVING","SET","ORDER","GROUP","BY","OUTPUT","VALUES","RETURN","CALL"].contains(clause) && (!priorIsOperand || topNumber || topParenthesis)
    let mergeTarget=targetBindings.first {$0.0=="MERGE" && contains($0.1.scope,caret)}?.1
    let mergeAssignment=mergeTarget != nil && clause=="SET" && context.last.map {token in
      guard token.text=="," || token.text.uppercased()=="SET",let index=tokens.firstIndex(where:{$0.range==token.range}),let merge=mergeAt[index] else {return false}
      return parents[index]==parents[merge]
    } == true
    let nextToken=tokens.first {$0.range.location>=NSMaxRange(replacement) && $0.range.location>replacement.location}
    func objectSuggestion(_ item:CatalogSymbol,call:Bool)->Suggestion {
      let schemaRequired=includeSchema || catalog?.needsSchema(item) == true
      var text=qualifier == nil && schemaRequired ? identifier(item.schema)+"."+identifier(item.name):identifier(item.name)
      var offset:Int?
      if call,nextToken?.text != "(" {text+="()";offset=text.utf16.count-1}
      let kind:Suggestion.Kind=item.kind.contains("PROCEDURE") ? .procedure:item.kind.contains("FUNCTION") ? .function:item.kind == "VIEW" ? .view:item.kind == "SYNONYM" ? .synonym:.table
      let label=schemaRequired ? identifier(item.schema)+"."+identifier(item.name):identifier(item.name)
      return Suggestion(text:text,label:label,kind:kind,detail:text,caretOffset:offset)
    }
    func appendScalarFunctions()throws {
      guard scalarPosition,!prefix.hasPrefix("@") else {return}
      let functions=try catalog?.matchingScalarFunctions(prefix,schema:qualifier,limit:qualifier == nil ? 25:100) ?? []
      // Retain one reachable function in a full column list, after the columns.
      // A function-heavy catalog must never evict 25 matching column slots.
      let budget = suggestions.count >= 100 ? min(1,functions.count) : min(100-suggestions.count,functions.count)
      suggestions = Array(suggestions.prefix(100-budget)) + functions.prefix(budget).map {objectSuggestion($0,call:true)}
    }
    if !inLiteral {
      if prefix.hasPrefix("@"),!prefix.hasPrefix("@@") {
        let separators=tokens.filter {SQLRoutineDefinition.isBatchSeparator($0,source:original)}
        let start=separators.last(where:{$0.range.location < caret}).map {NSMaxRange($0.range)} ?? 0
        let end=separators.first(where:{$0.range.location >= caret})?.range.location ?? original.length
        let batch=tokens.filter {$0.range.location>=start && $0.range.location<end}
        let declarations=TSQL.declaredVariables(in:batch,source:source).filter {NSMaxRange($0.range)<caret}
        let matching = declarations.filter { needle.count == 1 || $0.text.dropFirst().lowercased().contains(String(needle.dropFirst())) }
        suggestions=(matching.filter { $0.text.lowercased().hasPrefix(needle) } + matching.filter { !$0.text.lowercased().hasPrefix(needle) }).map {Suggestion(text:$0.text,label:$0.text,kind:.variable,detail:"Bu SQL grubunda tanımlı değişken")}
      } else if wildcard != nil {
        let sources=qualifier.map {name in visible.filter {$0.alias.caseInsensitiveCompare(name) == .orderedSame}} ?? visible
        if clause == "SELECT",["SELECT","DISTINCT","ALL"].contains(context.last?.text.uppercased() ?? "") || context.last?.text == "," || topNumber || topParenthesis,
          !sources.isEmpty,sources.allSatisfy({$0.columns?.isEmpty == false}) {
          let columns=sources.flatMap {binding in (binding.columns ?? []).map {column in
            let prefix=qualifier != nil ? "":binding.explicitAlias ? identifier(binding.alias)+".":sources.count>1 ? binding.parts.map(identifier).joined(separator:".")+".":""
            return prefix+identifier(column)
          }}
          let separator=qualifier == nil ? ",\n    ":", "+identifier(qualifier!)+"."
          suggestions=[Suggestion(text:columns.joined(separator:separator),label:"Tüm kolonları listele",kind:.column,detail:"\(columns.count) kolon · SELECT * yerine kolon adları")]
        }
      } else if let insertBinding {
        try appendColumns(from: [insertBinding], alreadyQualified: true)
      } else if objectPosition {
        let alreadyAliased = nextToken?.text.uppercased() == "AS" || nextToken?.kind == .word
        let occupied = Set(visible.map { $0.alias.lowercased() })
        let candidates = execution ? try catalog?.matchingRoutines(prefix,schema:qualifier) ?? [] : try catalog?.matchingRelations(prefix,schema:qualifier,read:readPosition) ?? []
        for item in candidates {
          let isRelation = ["USER_TABLE","VIEW"].contains(item.kind)
          let base=objectSuggestion(item,call:!execution && item.kind.contains("FUNCTION"))
          var text=base.text,label=base.label
          if automaticAliases && isRelation && !alreadyAliased && readPosition {
            let suffix=" AS "+alias(for:item.name,occupied:occupied)
            text += suffix;label += suffix
            if automaticNoLock && nextToken?.text.uppercased() != "WITH" { text += " WITH(NOLOCK)" }
          }
          suggestions.append(Suggestion(text:text,label:label,kind:base.kind,detail:text,caretOffset:base.caretOffset))
        }
        if readPosition,qualifier == nil {
          suggestions += TSQL.tableFunctions.sorted().filter {$0.lowercased().contains(needle)}.prefix(max(0,100-suggestions.count)).map {word in
            let call=nextToken?.text != "("
            let text=word+(call ? "()":"")
            return Suggestion(text:text,label:word,kind:.function,detail:"SQL Server tablo değerli fonksiyonu",caretOffset:call ? text.utf16.count-1:nil)
          }
        }
        if execution,qualifier == nil || ["sys","dbo"].contains(qualifier?.lowercased() ?? "") {
          let existing=Set(suggestions.map {$0.label.uppercased()})
          suggestions += TSQL.systemProcedures.sorted().filter {$0.lowercased().contains(needle) && !existing.contains($0)}.prefix(max(0,100-suggestions.count)).map {Suggestion(text:$0,label:$0,kind:.procedure,detail:"SQL Server sistem yordamı")}
        }
      } else if mergeAssignment,let mergeTarget {
        if qualifier==nil || qualifier?.lowercased()==mergeTarget.alias.lowercased() {
          try appendColumns(from:[mergeTarget],alreadyQualified:qualifier != nil)
        }
      } else if let qualifier {
        if let binding = visible.first(where: { $0.alias.lowercased() == qualifier.lowercased() }) {
          try appendColumns(from:[binding],alreadyQualified:true)
        } else {try appendScalarFunctions()}
      } else {
        if scalarPosition || ["INSERT","INTO"].contains(clause) && prior?.text == "(" {try appendColumns(from:visible,alreadyQualified:false)}
        try appendScalarFunctions()
        if suggestions.count < 100 {
          let preferred: [String]
          switch clause {
          case "FROM", "JOIN", "APPLY": preferred = ["WHERE", "JOIN", "LEFT", "INNER", "ON", "GROUP", "ORDER"]
          case "WHERE", "ON", "HAVING": preferred = ["AND", "OR", "IS", "IN", "EXISTS", "LIKE", "GROUP", "ORDER"]
          case "GROUP", "ORDER": preferred = ["BY"]
          case "UPDATE": preferred = ["SET"]
          case "DELETE": preferred = ["FROM"]
          case "SELECT": preferred = ["DISTINCT", "TOP", "FROM", "AS"]
          default: preferred = []
          }
          let words = preferred + Array(TSQL.keywords).sorted() + (scalarPosition || clause.isEmpty ? TSQL.functions.filter {!TSQL.tableFunctions.contains($0)} : [])
          var seenWords = Set<String>()
          let matching = words.filter {seenWords.insert($0).inserted && (needle.isEmpty || $0.lowercased().contains(needle))}
          suggestions += (matching.filter { $0.lowercased().hasPrefix(needle) } + matching.filter { !$0.lowercased().hasPrefix(needle) })
            .prefix(100-suggestions.count).map { word in
              let function=(scalarPosition || clause.isEmpty) && TSQL.functions.contains(word)
              let insertCall=function && !TSQL.bareFunctions.contains(word) && nextToken?.text != "("
              let text=word+(insertCall ? "()":"")
              return Suggestion(text:text,label:word,kind:function ? .function:.keyword,caretOffset:insertCall ? text.utf16.count-(TSQL.noArgumentFunctions.contains(word) ? 0:1):nil)
            }
        }
      }
    }
    try Task.checkCancellation()
    var seen = Set<String>()
    suggestions = suggestions.filter { seen.insert($0.text).inserted }.prefix(100).map { $0 }
    let referencesByAlias=Dictionary(uniqueKeysWithValues:activeBindings(caret).filter {
      local[$0.parts.joined(separator:".").lowercased()] == nil
    }.map {($0.alias.lowercased(),$0.parts)})
    return Analysis(tokens:all,diagnostics:Array(diagnostics.prefix(200)),suggestions:suggestions,replacement:replacement,referenceBindings:inLiteral ? [:]:referencesByAlias,procedureCompletion:execution && !inLiteral,variableCompletion:prefix.hasPrefix("@") && !inLiteral,objectCompletion:!inLiteral && (wildcard != nil && !suggestions.isEmpty || insertBinding != nil || objectPosition || scalarPosition && !prefix.isEmpty && suggestions.contains {$0.kind == .column || $0.kind == .function && !$0.detail.isEmpty}))
  }
}
