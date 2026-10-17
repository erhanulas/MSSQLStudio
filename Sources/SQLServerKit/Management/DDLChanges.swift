import Foundation

extension ModuleEditing {
  public struct Change:Equatable,Sendable {
    public let database:String?
    public let schema:String?
    public let name:String
    public let folder:Folder
    public let databaseTrigger:Bool
    public func inDatabase(_ value:String)->Self {Self(database:database ?? value,schema:schema,name:name,folder:folder,databaseTrigger:databaseTrigger)}
    public var type:String {
      switch folder {case .tables:return "U";case .views:return "V";case .procedures:return "P";case .functions:return "FN";case .synonyms:return "SN";case .users:return "USER";case .logins:return "LOGIN";case .roles:return "SERVER_ROLE";default:return databaseTrigger ? "TRD":"TR"}
    }
  }
  /// Named static DDL only. Dynamic SQL is deliberately not guessed. Module
  /// bodies are stored code, so declarations inside a CREATE PROC aren't changes.
  public static func changes(_ sql:String)->[Change] {
    guard sql.utf16.count<=1_000_000,let batches=try? TSQL.batches(sql) else {return []}
    func name(_ text:String)->String {
      if text.hasPrefix("[") && text.hasSuffix("]") {return String(text.dropFirst().dropLast()).replacingOccurrences(of:"]]",with:"]")}
      if text.hasPrefix("\"") && text.hasSuffix("\"") {return String(text.dropFirst().dropLast()).replacingOccurrences(of:"\"\"",with:"\"")}
      return text
    }
    var result:[Change]=[],database:String?
    for batch in batches {
      let tokens=TSQL.lex(batch.text).filter {![.space,.comment,.string].contains($0.kind)}
      guard tokens.count<=40_000 else {continue}
      func parts(_ index:inout Int)->[String] {
        var values:[String]=[]
        while index<tokens.count,[.word,.keyword].contains(tokens[index].kind) {
          values.append(name(tokens[index].text));index+=1
          if index<tokens.count,tokens[index].text == "." {
            index+=1
            if index<tokens.count,tokens[index].text == "." {values.append("");index+=1}
          } else {break}
        }
        return values
      }
      func append(_ p:[String],folder:Folder,databaseTrigger:Bool=false) {
        guard (1...3).contains(p.count),let object=p.last,!object.isEmpty,!object.hasPrefix("#"),!object.hasPrefix("@"),p.allSatisfy({$0.utf16.count<=128 && !$0.contains("\0")}) else {return}
        let schema=p.count>=2 && !p[p.count-2].isEmpty ? p[p.count-2]:nil
        let change=Change(database:p.count==3 ? p[0]:database,schema:databaseTrigger || [.users,.logins,.roles].contains(folder) ? "":schema,name:object,folder:folder,databaseTrigger:databaseTrigger)
        if !result.contains(change),result.count<128 {result.append(change)}
      }
      // ON and list separators belong to this statement only. In particular,
      // a malformed/unsupported index must not borrow the next statement's ON.
      func boundary(_ start:Int)->Int {
        var depth=0
        for index in start..<tokens.count {
          let text=tokens[index].text.uppercased()
          if depth==0 && (text==";" || ["CREATE","ALTER","DROP","TRUNCATE","ENABLE","DISABLE"].contains(text) && [.word,.keyword].contains(tokens[index].kind)) {return index}
          if text=="(" {depth+=1} else if text==")" {depth=max(0,depth-1)}
        }
        return tokens.count
      }
      func separator(after start:Int,before end:Int)->Int? {
        var depth=0
        for index in start..<end {
          if tokens[index].text=="(" {depth+=1}
          else if tokens[index].text==")" {depth=max(0,depth-1)}
          else if depth==0 && tokens[index].text=="," {return index}
        }
        return nil
      }
      var i=0
      while i<tokens.count {
        defer {i+=1}
        let verb=tokens[i].text.uppercased()
        guard [.word,.keyword].contains(tokens[i].kind) else {continue}
        if verb == "USE" {var j=i+1;let p=parts(&j);if p.count==1 {database=p[0]};i=max(i,j-1);continue}
        guard ["CREATE","ALTER","DROP","TRUNCATE","ENABLE","DISABLE"].contains(verb) else {continue}
        var j=i+1
        if j+1<tokens.count,tokens[j].text.uppercased()=="OR",tokens[j+1].text.uppercased()=="ALTER" {j+=2}
        let indexModifiers=["UNIQUE","CLUSTERED","NONCLUSTERED","COLUMNSTORE","PRIMARY","SELECTIVE","XML","SPATIAL","VECTOR","FULLTEXT"]
        while j<tokens.count,indexModifiers.contains(tokens[j].text.uppercased()) {j+=1}
        guard j<tokens.count else {continue}
        var kind=tokens[j].text.uppercased()
        if kind=="SERVER",j+1<tokens.count,tokens[j+1].text.uppercased()=="ROLE" {kind="SERVER_ROLE";j+=1}
        let folder:Folder
        switch kind {
        case "TABLE","INDEX","STATISTICS":folder = .tables
        case "VIEW":folder = .views
        case "PROC","PROCEDURE":folder = .procedures
        case "FUNCTION":folder = .functions
        case "TRIGGER":folder = .triggers
        case "SYNONYM":folder = .synonyms
        case "USER":folder = .users
        case "LOGIN":folder = .logins
        case "SERVER_ROLE":folder = .roles
        default:continue
        }
        j+=1
        if j+1<tokens.count,tokens[j].text.uppercased()=="IF",tokens[j+1].text.uppercased()=="EXISTS" {j+=2}
        let end=boundary(j)
        if kind == "INDEX" || kind == "STATISTICS" {
          repeat {
            var objectIndex=j
            let indexName = tokens[j].text.uppercased()=="ON" ? []:parts(&objectIndex)
            let clauseEnd=separator(after:objectIndex,before:end) ?? end
            if let on=(objectIndex..<clauseEnd).first(where:{tokens[$0].kind == .keyword && tokens[$0].text.uppercased()=="ON"}) {
              var ownerIndex=on+1
              append(parts(&ownerIndex),folder:.tables)
            } else if kind=="INDEX",indexName.isEmpty,j<end,tokens[j].text.uppercased()=="ON" {
              // CREATE/ALTER/DROP FULLTEXT INDEX ON <table> has no index name.
              var ownerIndex=j+1;append(parts(&ownerIndex),folder:.tables)
            } else if verb=="DROP",indexName.count>=2 {
              // Legacy DROP INDEX table.index and DROP STATISTICS table.stats.
              append(Array(indexName.dropLast()),folder:.tables)
            }
            guard verb=="DROP",let comma=separator(after:objectIndex,before:end) else {break}
            j=comma+1
          } while j<end
          i=max(i,end-1)
          continue
        }
        let triggerOn=kind == "TRIGGER" ? (j..<end).first(where:{tokens[$0].text.uppercased()=="ON" && tokens[$0].kind == .keyword}):nil
        let dbTrigger=triggerOn.map {$0+1<end && tokens[$0+1].text.uppercased()=="DATABASE"} ?? false
        let serverTrigger=triggerOn.map {$0+2<end && tokens[$0+1].text.uppercased()=="ALL" && tokens[$0+2].text.uppercased()=="SERVER"} ?? false
        repeat {
          let p=parts(&j)
          guard !p.isEmpty else {break}
          if !serverTrigger,!(kind=="TRIGGER" && p==["ALL"]) {append(p,folder:folder,databaseTrigger:dbTrigger)}
          if ["DROP","ENABLE","DISABLE"].contains(verb),j<tokens.count,tokens[j].text=="," {j+=1} else {break}
        } while j<tokens.count
        if let on=triggerOn,verb != "DROP",!dbTrigger,!serverTrigger {
          var targetIndex=on+1;append(parts(&targetIndex),folder:.tables)
        }
        if ["CREATE","ALTER"].contains(verb),["VIEW","PROC","PROCEDURE","FUNCTION","TRIGGER"].contains(kind) {break}
        i=max(i,j-1)
      }
    }
    return result
  }
}
