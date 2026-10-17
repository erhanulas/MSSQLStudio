import Foundation

/// Edits only recognized metadata spans; clustering, storage, trust and disable SQL survive.
public struct TableStructureDraft:Equatable,Sendable {
  public var kind="INDEX"
  public var name="IX_NewIndex"
  public var keys:[String]=[]
  public var descending:Set<String>=[]
  public var included:[String]=[]
  public var unique=false
  public var expression=""
  public var targetSchema="dbo"
  public var targetTable=""
  public var targetColumns=""
  public var deleteAction="NO ACTION"
  public var updateAction="NO ACTION"
  private var template:Template?
  private enum Field:Hashable,Sendable {case name,keys,include,unique,expression,target,targetColumns,deleteAction,updateAction}
  private struct Template:Equatable,Sendable {
    let source:String
    var spans:[Field:NSRange]=[:]
    var references:[NSRange]=[]
  }
  public init(kind:String="INDEX") {
    self.kind=kind
    name=kind == "FK" ? "FK_NewRelationship":kind == "CHECK" ? "CK_NewConstraint":kind == "PK" ? "PK_NewKey":kind == "UQ" ? "UQ_NewKey":"IX_NewIndex"
  }
  public init(_ definition:ManagedDefinition) throws {
    self.init(kind:definition.kind)
    guard ["INDEX","PK","UQ","FK","CHECK"].contains(kind) else {throw SQLFailure("Bu nesne SQL editöründen düzenlenebilir.")}
    name=definition.name
    let source=definition.sql as NSString
    let tokens=TSQL.lex(definition.sql).filter {$0.kind != .space && $0.kind != .comment}
    func word(_ i:Int,_ value:String)->Bool {tokens.indices.contains(i) && tokens[i].text.uppercased()==value}
    func find(_ text:String,after:Int=0)->Int? {tokens.indices.first {$0>=after && word($0,text)}}
    func range(_ start:Int,_ end:Int)->NSRange {NSRange(location:tokens[start].range.location,length:NSMaxRange(tokens[end].range)-tokens[start].range.location)}
    func closing(_ open:Int) throws -> Int {
      var depth=0
      for i in open..<tokens.count {
        if word(i,"(") {depth+=1};if word(i,")") {depth-=1;if depth==0 {return i}}
      }
      throw SQLFailure("Nesne özellikleri çözümlenemedi; SQL editöründe inceleyin.")
    }
    func identifier(_ text:String)->String {
      if text.hasPrefix("[") && text.hasSuffix("]") {return String(text.dropFirst().dropLast()).replacingOccurrences(of:"]]",with:"]")}
      if text.hasPrefix("\"") && text.hasSuffix("\"") {return String(text.dropFirst().dropLast()).replacingOccurrences(of:"\"\"",with:"\"")}
      return text
    }
    func columnList(_ open:Int,_ close:Int) throws -> ([String],Set<String>) {
      var names:[String]=[],desc:Set<String>=[],i=open+1
      while i<close {
        let name=identifier(tokens[i].text)
        guard tokens[i].kind == .word || tokens[i].kind == .keyword else {throw SQLFailure("Kolon listesi çözümlenemedi.")}
        names.append(name);i+=1
        if word(i,"DESC") {desc.insert(name);i+=1} else if word(i,"ASC") {i+=1}
        if i<close {guard word(i,",") else {throw SQLFailure("Kolon listesi çözümlenemedi.")};i+=1}
      }
      return (names,desc)
    }
    var layout=Template(source:definition.sql)
    guard let nameKeyword=find(kind == "INDEX" ? "INDEX":"CONSTRAINT"),tokens.indices.contains(nameKeyword+1),identifier(tokens[nameKeyword+1].text)==name else {throw SQLFailure("Nesne adı çözümlenemedi.")}
    layout.spans[.name]=tokens[nameKeyword+1].range
    // Metadata can append ALTER INDEX / NOCHECK CONSTRAINT for disabled objects.
    for i in tokens.indices where i>nameKeyword+1 && (word(i,"INDEX") || word(i,"CONSTRAINT")) && tokens.indices.contains(i+1) && identifier(tokens[i+1].text)==name {
      layout.references.append(tokens[i+1].range)
    }
    if kind == "CHECK" {
      guard let check=find("CHECK",after:nameKeyword+2),let open=find("(",after:check) else {throw SQLFailure("CHECK koşulu çözümlenemedi.")}
      let close=try closing(open),span=NSRange(location:NSMaxRange(tokens[open].range),length:tokens[close].range.location-NSMaxRange(tokens[open].range))
      layout.spans[.expression]=span;expression=source.substring(with:span)
    } else {
      guard let open=find("(",after:nameKeyword+2) else {throw SQLFailure("Anahtar kolonları çözümlenemedi.")}
      let close=try closing(open)
      (keys,descending)=try columnList(open,close)
      layout.spans[.keys]=NSRange(location:NSMaxRange(tokens[open].range),length:tokens[close].range.location-NSMaxRange(tokens[open].range))
      if kind == "INDEX" {
        let uniqueIndex=tokens.indices.first {$0<nameKeyword && word($0,"UNIQUE")}
        unique=uniqueIndex != nil
        guard let create=find("CREATE") else {throw SQLFailure("CREATE INDEX tanımı çözümlenemedi.")}
        layout.spans[.unique]=uniqueIndex.map {tokens[$0].range} ?? NSRange(location:NSMaxRange(tokens[create].range),length:0)
        var end=close
        if let include=find("INCLUDE",after:close+1),word(include+1,"(") {
          let includeEnd=try closing(include+1)
          included=try columnList(include+1,includeEnd).0
          layout.spans[.include]=range(include,includeEnd);end=includeEnd
        } else {layout.spans[.include]=NSRange(location:NSMaxRange(tokens[close].range),length:0)}
        if let whereIndex=find("WHERE",after:end+1) {
          var depth=0,stop=whereIndex+1
          while stop<tokens.count {
            if depth==0 && (word(stop,";") || word(stop,"WITH") || word(stop,"ON")) {break}
            if word(stop,"(") {depth+=1};if word(stop,")") {depth-=1};stop+=1
          }
          guard stop>whereIndex+1 else {throw SQLFailure("İndeks filtresi çözümlenemedi.")}
          let span=range(whereIndex,stop-1)
          layout.spans[.expression]=span
          expression=source.substring(with:NSRange(location:NSMaxRange(tokens[whereIndex].range),length:NSMaxRange(span)-NSMaxRange(tokens[whereIndex].range))).trimmingCharacters(in:.whitespacesAndNewlines)
        } else {layout.spans[.expression]=NSRange(location:NSMaxRange(tokens[end].range),length:0)}
      } else if kind == "FK" {
        guard let reference=find("REFERENCES",after:close),let targetOpen=find("(",after:reference),targetOpen==reference+4,word(reference+2,".") else {throw SQLFailure("İlişki hedefi çözümlenemedi.")}
        targetSchema=identifier(tokens[reference+1].text);targetTable=identifier(tokens[reference+3].text)
        layout.spans[.target]=range(reference+1,reference+3)
        let targetClose=try closing(targetOpen)
        targetColumns=try columnList(targetOpen,targetClose).0.map(SQL.identifier).joined(separator:", ")
        layout.spans[.targetColumns]=NSRange(location:NSMaxRange(tokens[targetOpen].range),length:tokens[targetClose].range.location-NSMaxRange(tokens[targetOpen].range))
        for (label,field) in [("DELETE",Field.deleteAction),("UPDATE",Field.updateAction)] {
          guard let at=find(label,after:targetClose),word(at-1,"ON"),tokens.indices.contains(at+1) else {throw SQLFailure("İlişki eylemi çözümlenemedi.")}
          let count=word(at+1,"CASCADE") ? 1:2
          guard tokens.indices.contains(at+count) else {throw SQLFailure("İlişki eylemi çözümlenemedi.")}
          let span=range(at+1,at+count),value=source.substring(with:span)
          layout.spans[field]=span
          if field == .deleteAction {deleteAction=value} else {updateAction=value}
        }
      }
    }
    template=layout
  }
  public func dropSQL(table:String,original:ManagedDefinition)->String {
    original.kind == "INDEX" ? "DROP INDEX \(SQL.identifier(original.name)) ON \(table);":"ALTER TABLE \(table) DROP CONSTRAINT \(SQL.identifier(original.name));"
  }
  public func createSQL(table:String,columns:[String]) throws -> String {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=128 else {throw SQLFailure("Geçerli bir nesne adı girin.")}
    guard kind == "CHECK" || !keys.isEmpty,Set(keys).count==keys.count,keys.allSatisfy(columns.contains),included.allSatisfy(columns.contains),Set(keys).isDisjoint(with:included) else {throw SQLFailure("Geçerli, tekrarsız anahtar/include kolonları seçin.")}
    let keySQL=keys.map {SQL.identifier($0)+(kind == "FK" ? "":descending.contains($0) ? " DESC":" ASC")}.joined(separator:", ")
    if kind == "CHECK",expression.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {throw SQLFailure("CHECK koşulu gerekli.")}
    let references=try Self.parseColumns(targetColumns)
    if kind == "FK" {_ = try ObjectScripts.foreignKey(table:table,name:name,columns:keys,referencedSchema:targetSchema,referencedTable:targetTable,referencedColumns:references,onDelete:deleteAction,onUpdate:updateAction)}
    if let template {
      let values:[Field:String]=[.name:SQL.identifier(name),.keys:keySQL,.include:included.isEmpty ? "":" INCLUDE ("+included.map(SQL.identifier).joined(separator:", ")+") ",.unique:unique ? " UNIQUE ":" ",.expression:kind == "INDEX" ? (expression.isEmpty ? "":" WHERE "+expression+" "):expression,.target:SQL.identifier(targetSchema)+"."+SQL.identifier(targetTable),.targetColumns:references.map(SQL.identifier).joined(separator:", "),.deleteAction:deleteAction,.updateAction:updateAction]
      var edits=template.spans.map {($0.value,values[$0.key] ?? "")}
      edits+=template.references.map {($0,SQL.identifier(name))}
      // At the same insertion point INCLUDE must precede WHERE in final SQL.
      edits.sort {a,b in a.0.location != b.0.location ? a.0.location>b.0.location:a.1.hasPrefix(" WHERE")}
      let result=NSMutableString(string:template.source)
      for (range,text) in edits {result.replaceCharacters(in:range,with:text)}
      return result as String
    }
    switch kind {
    case "INDEX":return try Scripts.index(table:table,name:name,keys:keys,included:included,unique:unique,filter:expression).replacingOccurrences(of:"("+keys.map(SQL.identifier).joined(separator:", ")+")",with:"("+keySQL+")")
    case "PK","UQ":return "ALTER TABLE \(table) ADD CONSTRAINT \(SQL.identifier(name)) \(kind == "PK" ? "PRIMARY KEY":"UNIQUE") (\(keySQL));"
    case "FK":return try ObjectScripts.foreignKey(table:table,name:name,columns:keys,referencedSchema:targetSchema,referencedTable:targetTable,referencedColumns:references,onDelete:deleteAction,onUpdate:updateAction)
    default:return "ALTER TABLE \(table) WITH CHECK ADD CONSTRAINT \(SQL.identifier(name)) CHECK (\(expression));"
    }
  }
  private static func parseColumns(_ source:String) throws -> [String] {
    let tokens=TSQL.lex(source).filter {$0.kind != .space && $0.kind != .comment}
    guard !tokens.isEmpty else {return []}
    var result:[String]=[]
    for (i,token) in tokens.enumerated() {
      if i.isMultiple(of:2) {
        guard token.kind == .word || token.kind == .keyword else {throw SQLFailure("Hedef kolonları virgülle ayırın.")}
        result.append(token.text.hasPrefix("[") ? String(token.text.dropFirst().dropLast()).replacingOccurrences(of:"]]",with:"]"):token.text)
      } else if token.text != "," {throw SQLFailure("Hedef kolonları virgülle ayırın.")}
    }
    guard !tokens.count.isMultiple(of:2) else {throw SQLFailure("Hedef kolonları virgülle ayırın.")}
    return result
  }
}
