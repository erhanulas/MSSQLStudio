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
      switch folder {case .tables:return "U";case .views:return "V";case .procedures:return "P";case .functions:return "FN";case .synonyms:return "SN";default:return databaseTrigger ? "TRD":"TR"}
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
      var i=0
      while i<tokens.count {
        defer {i+=1}
        let verb=tokens[i].text.uppercased()
        guard tokens[i].kind == .keyword else {continue}
        if verb == "USE" {var j=i+1;let p=parts(&j);if p.count==1 {database=p[0]};i=max(i,j-1);continue}
        guard ["CREATE","ALTER","DROP"].contains(verb) else {continue}
        var j=i+1
        if j+1<tokens.count,tokens[j].text.uppercased()=="OR",tokens[j+1].text.uppercased()=="ALTER" {j+=2}
        if j<tokens.count,["UNIQUE","CLUSTERED","NONCLUSTERED"].contains(tokens[j].text.uppercased()) {
          while j<tokens.count,["UNIQUE","CLUSTERED","NONCLUSTERED"].contains(tokens[j].text.uppercased()) {j+=1}
        }
        guard j<tokens.count else {continue}
        let kind=tokens[j].text.uppercased(),folder:Folder
        switch kind {
        case "TABLE","INDEX":folder = .tables
        case "VIEW":folder = .views
        case "PROC","PROCEDURE":folder = .procedures
        case "FUNCTION":folder = .functions
        case "TRIGGER":folder = .triggers
        case "SYNONYM":folder = .synonyms
        default:continue
        }
        j+=1
        if j+1<tokens.count,tokens[j].text.uppercased()=="IF",tokens[j+1].text.uppercased()=="EXISTS" {j+=2}
        if kind == "INDEX" {
          guard let on=(j..<tokens.count).first(where:{tokens[$0].text.uppercased()=="ON"}) else {continue}
          j=on+1
        }
        repeat {
          let p=parts(&j)
          guard (1...3).contains(p.count),let object=p.last,!object.isEmpty,!object.hasPrefix("#"),!object.hasPrefix("@"),p.allSatisfy({$0.utf16.count<=128 && !$0.contains("\0")}) else {break}
          let dbTrigger=kind == "TRIGGER" && j+1<tokens.count && tokens[j].text.uppercased()=="ON" && tokens[j+1].text.uppercased()=="DATABASE"
          let schema=p.count>=2 && !p[p.count-2].isEmpty ? p[p.count-2]:nil
          let change=Change(database:p.count==3 ? p[0]:database,schema:dbTrigger ? "":schema,name:object,folder:folder,databaseTrigger:dbTrigger)
          if !result.contains(change),result.count<128 {result.append(change)}
          if verb == "DROP",kind != "INDEX",j<tokens.count,tokens[j].text=="," {j+=1} else {break}
        } while j<tokens.count
        if verb != "DROP",["VIEW","PROC","PROCEDURE","FUNCTION","TRIGGER"].contains(kind) {break}
        i=max(i,j-1)
      }
    }
    return result
  }
}
