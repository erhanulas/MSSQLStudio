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
    public init(text: String, label: String, kind: Kind = .keyword, detail: String = "") {
      self.text = text; self.label = label; self.kind = kind; self.detail = detail
    }
  }
  public struct Analysis: Sendable {
    public let tokens: [Lexeme]
    public let diagnostics: [Diagnostic]
    public let suggestions: [Suggestion]
    public let replacement: NSRange
    public var procedureCompletion = false
    public var variableCompletion = false
  }
  public final class Catalog: Sendable {
    public let snapshot: SQLCatalogSnapshot
    private let qualified: [String:CatalogSymbol]
    private let names: [String:[CatalogSymbol]]
    private let sorted: [(String,CatalogSymbol)]
    private let routines: [(String,CatalogSymbol)]
    public var fresh: Bool { Date().timeIntervalSince(snapshot.synchronizedAt) < 300 }
    public init(snapshot: SQLCatalogSnapshot) {
      self.snapshot = snapshot
      var qualified: [String:CatalogSymbol] = [:], names: [String:[CatalogSymbol]] = [:]
      for item in snapshot.symbols { qualified[Self.key(item.schema,item.name)] = item; names[item.name.lowercased(),default:[]].append(item) }
      self.qualified = qualified; self.names = names
      sorted = snapshot.symbols.map { ($0.name.lowercased(),$0) }.sorted { $0.0 == $1.0 ? $0.1.schema < $1.1.schema : $0.0 < $1.0 }
      routines = sorted.filter {$0.1.kind.contains("PROCEDURE") || $0.1.kind.contains("FUNCTION")}
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
      // A bare name cannot identify a chosen entry when more than one schema owns it.
      (names[item.name.lowercased()]?.count ?? 0) > 1 || item.kind.contains("SCALAR_FUNCTION")
    }
    public func matchingRoutines(_ text:String,schema:String?=nil,limit:Int=100) throws -> [CatalogSymbol] {
      let needle=text.lowercased(), schema=schema?.lowercased(), limit=max(0,min(limit,100))
      var result:[CatalogSymbol]=[]
      // Prefer prefixes, then interior matches; unrelated relations cannot consume the limit.
      for prefixPass in [true,false] {
        for (index,pair) in routines.enumerated() {
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
      let prefix = prefix.lowercased()
      var low = 0, high = sorted.count
      while low < high { let mid = (low+high)/2; if sorted[mid].0 < prefix { low = mid+1 } else { high = mid } }
      var result: [CatalogSymbol] = []
      while low < sorted.count, sorted[low].0.hasPrefix(prefix), result.count < limit {
        let item = sorted[low].1
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
  public static func analyze(source: String, caret: Int, catalog: Catalog?, verified: Bool, automaticAliases: Bool = true, automaticNoLock: Bool = false, includeSchema: Bool = true, quoteIdentifiers: Bool = true) throws -> Analysis {
    try Task.checkCancellation()
    let original = source as NSString, caret = max(0,min(caret,original.length))
    guard original.length <= 250_000 else { return Analysis(tokens:[],diagnostics:[],suggestions:[],replacement:NSRange(location:caret,length:0)) }
    let all = TSQL.lex(source)
    guard original.length <= 100_000 else { return Analysis(tokens:all,diagnostics:[],suggestions:[],replacement:NSRange(location:caret,length:0)) }
    let active = all.first { [.word,.keyword,.variable].contains($0.kind) && caret >= $0.range.location && caret <= NSMaxRange($0.range) }
    let replacement = active?.range ?? NSRange(location:caret,length:0)
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
    let selects=tokens.indices.filter {tokens[$0].kind == .keyword && ["SELECT","UPDATE","DELETE","INSERT","MERGE"].contains(tokens[$0].text.uppercased())}
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
    local = local.mapValues { $0.map(raw) }
    var bindings: [Binding] = [], ignored = Set<Int>(), diagnostics: [Diagnostic] = []
    var references: [(Int,[String],NSRange)] = []
    var targets:[(index:Int,verb:String)]=[]
    for i in tokens.indices where ["FROM","JOIN","UPDATE","DELETE","INSERT","INTO","APPLY","EXEC","EXECUTE"].contains(tokens[i].text.uppercased()) {
      try Task.checkCancellation()
      var j = i+1, parts: [String] = [], indices: [Int] = []
      let verb=tokens[i].text.uppercased()
      if j < tokens.count,tokens[j].text.uppercased() == "TOP" {
        j+=1
        if j < tokens.count,tokens[j].text == "(",let close=closes[j] {j=close+1}
        else if j < tokens.count,tokens[j].kind == .number {j+=1}
        if j < tokens.count,tokens[j].text.uppercased() == "PERCENT" {j+=1}
      }
      if ["DELETE","INSERT"].contains(verb),j < tokens.count,["FROM","INTO"].contains(tokens[j].text.uppercased()) {continue}
      if j < tokens.count, tokens[j].text == "(", let close = closes[j] {
        j = close+1; if j < tokens.count && tokens[j].text.uppercased() == "AS" { j += 1 }
        if j < tokens.count, tokens[j].kind == .word {
          let name = raw(tokens[j].text); ignored.insert(j)
          bindings.append(Binding(alias:name,explicitAlias:true,parts:[name],columns:local[name.lowercased()],scope:scope(i)))
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
      var alias = parts.last!, explicitAlias = false
      if j < tokens.count && tokens[j].text == "(", let close = closes[j] { j = close+1 }
      if j < tokens.count && tokens[j].text.uppercased() == "AS" { ignored.insert(j); j += 1 }
      if j < tokens.count && tokens[j].kind == .word { alias = raw(tokens[j].text); explicitAlias = true; ignored.insert(j) }
      let columns = local[name] ?? (resolved?.kind == "SYNONYM" ? nil : resolved?.columns)
      bindings.append(Binding(alias:alias,explicitAlias:explicitAlias,parts:parts,columns:columns,scope:scope(i)))
      if ["UPDATE","DELETE","INSERT","INTO"].contains(verb) {targets.append((bindings.count-1,verb))}
      if verb == "FROM",let head=tokens.indices.last(where:{$0<i && parents[$0]==parents[i] && tokens[$0].range.location>=starts[i] && ["SELECT","UPDATE","DELETE","INSERT"].contains(tokens[$0].text.uppercased())}),tokens[head].text.uppercased() == "DELETE",!targets.contains(where:{$0.verb == "DELETE" && bindings[$0.index].scope == scope(i)}) {targets.append((bindings.count-1,"DELETE"))}
      references.append((i,parts,NSRange(location:tokens[indices[0]].range.location,length:NSMaxRange(tokens[indices.last!].range)-tokens[indices[0]].range.location)))
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
    let targetBindings=targets.map {($0.verb,bindings[$0.index])}
    for (verb,binding) in targetBindings {
      let names=verb == "UPDATE" ? ["inserted","deleted"] : verb == "DELETE" ? ["deleted"] : ["inserted"]
      // OUTPUT pseudo-tables are offered only after an OUTPUT in this scope.
      if tokens.contains(where:{$0.text.uppercased() == "OUTPUT" && contains(binding.scope,$0.range.location) && $0.range.location < caret}) {
        for name in names {bindings.append(Binding(alias:name,explicitAlias:true,parts:binding.parts,columns:binding.columns,scope:binding.scope))}
      }
    }
    guard bindings.count <= 128 else { return Analysis(tokens:all,diagnostics:[],suggestions:[],replacement:replacement) }
    func activeBindings(_ location: Int) -> [Binding] {
      let visible = bindings.filter { contains($0.scope,location) }.sorted { $0.scope.length < $1.scope.length }
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
        let special = parts.count > 2 || parts.first?.lowercased() == "sys" || parts.first?.lowercased() == "information_schema" || parts.last?.hasPrefix("#") == true || parts.last?.hasPrefix("@") == true
        let updateAlias = ["UPDATE","FROM","DELETE"].contains(tokens[i].text.uppercased()) && activeBindings(range.location).contains { $0.alias.lowercased() == key && $0.parts.map { $0.lowercased() }.joined(separator:".") != key }
        if !special && local[key] == nil && catalog?.resolve(parts) == nil && catalog?.isAmbiguous(parts) != true && !updateAlias && !isEditing(range) {
          diagnostics.append(Diagnostic(range:range,message:"Nesne güncel DDL indeksinde bulunamadı: \(parts.joined(separator:"."))"))
        }
      }
      var outputAliases = Set(tokens.indices.compactMap { i -> String? in
        guard i > 0, tokens[i-1].text.uppercased() == "AS", tokens[i].kind == .word else { return nil }; return raw(tokens[i].text).lowercased()
      })
      var clauses: [String?] = [], clause: String?
      for token in tokens {
        if ["SELECT","FROM","JOIN","WHERE","ON","SET","HAVING","ORDER","GROUP","BY"].contains(token.text.uppercased()) { clause = token.text.uppercased() }
        clauses.append(clause)
      }
      var predecessors: [Int:Lexeme] = [:], preceding: Lexeme?
      for token in all where token.kind != .space && token.kind != .comment {
        if let preceding { predecessors[token.range.location] = preceding }; preceding = token
      }
      // A SELECT expression may name its output without AS. Do not diagnose that output name.
      for i in tokens.indices where i > 0 && tokens[i].kind == .word && clauses[i] == "SELECT" {
        let previous = predecessors[tokens[i].range.location] ?? tokens[i-1]
        if (previous.kind == .word || previous.kind == .string || previous.kind == .number || previous.text == ")") && (i+1 == tokens.count || [",","FROM"].contains(tokens[i+1].text.uppercased())) {
          outputAliases.insert(raw(tokens[i].text).lowercased())
        }
      }
      let commaSources = tokens.indices.contains { tokens[$0].text == "," && clauses[$0] == "FROM" }
      for i in tokens.indices where tokens[i].kind == .word && !ignored.contains(i) {
        try Task.checkCancellation()
        let token = tokens[i], name = raw(token.text).lowercased()
        if isEditing(token.range) || outputAliases.contains(name) { continue }
        let visible = activeBindings(token.range.location)
        if i >= 2 && tokens[i-1].text == "." {
          let qualifier = raw(tokens[i-2].text).lowercased()
          if let binding = visible.first(where: { $0.alias.lowercased() == qualifier }), let columns = binding.columns, !columns.isEmpty,
            !columns.contains(where: { $0.lowercased() == name }) {
            diagnostics.append(Diagnostic(range:token.range,message:"\(binding.alias) için kolon DDL indeksinde bulunamadı: \(raw(token.text))"))
          }
          continue
        }
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
            let label = alreadyQualified ? binding.alias+"."+identifier(column) : text
            suggestions.append(Suggestion(text:text,label:label,kind:.column,detail:binding.parts.joined(separator:".")))
          }
        }
      }
    }
    var context = before
    if qualifier != nil { context = Array(context.dropLast(2)) }
    let returnAssignment=context.count>=3 && context.last?.text == "=" && context[context.count-2].kind == .variable && ["EXEC","EXECUTE"].contains(context[context.count-3].text.uppercased())
    let execution = (["EXEC","EXECUTE"].contains(context.last?.text.uppercased() ?? "") || returnAssignment) && !prefix.hasPrefix("@")
    let objectPosition = execution || ["FROM","JOIN","UPDATE","DELETE","INSERT","INTO","APPLY"].contains(context.last?.text.uppercased() ?? "")
    if !inLiteral {
      if prefix.hasPrefix("@"),!prefix.hasPrefix("@@") {
        let separators=tokens.filter {SQLRoutineDefinition.isBatchSeparator($0,source:original)}
        let start=separators.last(where:{$0.range.location < caret}).map {NSMaxRange($0.range)} ?? 0
        let end=separators.first(where:{$0.range.location >= caret})?.range.location ?? original.length
        let batch=tokens.filter {$0.range.location>=start && $0.range.location<end}
        let declarations=TSQL.declaredVariables(in:batch,source:source).filter {NSMaxRange($0.range)<caret}
        suggestions=declarations.filter {$0.text.lowercased().hasPrefix(needle)}.map {Suggestion(text:$0.text,label:$0.text,kind:.variable,detail:"Bu SQL grubunda tanımlı değişken")}
      } else if objectPosition {
        let nextToken = tokens.first { $0.range.location >= NSMaxRange(replacement) && $0.range.location > replacement.location }
        let alreadyAliased = nextToken?.text.uppercased() == "AS" || nextToken?.kind == .word
        let occupied = Set(visible.map { $0.alias.lowercased() })
        let candidates = execution ? try catalog?.matchingRoutines(prefix,schema:qualifier) ?? [] : catalog?.matches(prefix,schema:qualifier) ?? []
        for item in candidates {
          let isRelation = ["USER_TABLE","VIEW"].contains(item.kind)
          if !execution && !isRelation && item.kind != "SYNONYM" { continue }
          let schemaRequired = includeSchema || catalog?.needsSchema(item) == true
          var text = qualifier == nil && schemaRequired ? identifier(item.schema)+"."+identifier(item.name) : identifier(item.name)
          if automaticAliases && isRelation && !alreadyAliased && ["FROM","JOIN"].contains(context.last?.text.uppercased() ?? "") { text += " AS "+alias(for:item.name,occupied:occupied)
            if automaticNoLock && nextToken?.text.uppercased() != "WITH" { text += " WITH(NOLOCK)" }
          }
          let kind: Suggestion.Kind = item.kind.contains("PROCEDURE") ? .procedure : item.kind.contains("FUNCTION") ? .function : item.kind == "VIEW" ? .view : item.kind == "SYNONYM" ? .synonym : .table
          suggestions.append(Suggestion(text:text,label:SQL.identifier(item.schema)+"."+SQL.identifier(item.name),kind:kind,detail:text))
        }
      } else if let qualifier {
        if let binding = visible.first(where: { $0.alias.lowercased() == qualifier.lowercased() }) {
          try appendColumns(from:[binding],alreadyQualified:true)
        }
      } else {
        try appendColumns(from:visible,alreadyQualified:false)
        if suggestions.count < 100 {
          suggestions += (Array(TSQL.keywords)+TSQL.functions).sorted().filter { $0.lowercased().hasPrefix(prefix.lowercased()) }.prefix(100-suggestions.count).map { Suggestion(text:$0,label:$0,kind:TSQL.functions.contains($0) ? .function : .keyword) }
        }
      }
    }
    try Task.checkCancellation()
    var seen = Set<String>()
    suggestions = suggestions.filter { seen.insert($0.text).inserted }.prefix(100).map { $0 }
    return Analysis(tokens:all,diagnostics:Array(diagnostics.prefix(200)),suggestions:suggestions,replacement:replacement,procedureCompletion:execution && !inLiteral,variableCompletion:prefix.hasPrefix("@") && !inLiteral)
  }
}
