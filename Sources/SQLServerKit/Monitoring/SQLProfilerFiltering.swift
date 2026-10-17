import Foundation

public enum SQLProfilerFiltering {
  public enum Column:String,CaseIterable,Identifiable,Sendable,Codable {
    case message,messageLevel,errorNumber,severity,clientPID,session,sql,host,application,login,database,kind,duration,cpu,reads,writes,timestamp
    public var id:String {rawValue}
    public var title:String {
      switch self {
      case .message:"Mesaj"
      case .messageLevel:"Bildirim"
      case .errorNumber:"Hata no"
      case .severity:"Önem derecesi"
      case .timestamp:"Zaman (UTC)"
      case .clientPID:"ClientProcessID"
      case .session:"SPID"
      case .sql:"SQL metni"
      case .host:"Host"
      case .application:"Uygulama"
      case .login:"Login"
      case .database:"Veritabanı"
      case .kind:"Olay"
      case .duration:"Süre (ms)"
      case .cpu:"CPU (ham)"
      case .reads:"Okuma"
      case .writes:"Yazma"
      }
    }
    public var numeric:Bool {[.errorNumber,.severity,.clientPID,.session,.duration,.cpu,.reads,.writes].contains(self)}
    public var operators:[Comparison] {numeric ? [.equals,.notEquals,.atLeast,.atMost]:[.contains,.notContains,.equals,.notEquals]}
    public func value(_ event:SQLProfiler.Event)->String {
      switch self {
      case .message:event.message
      case .messageLevel:event.messageLevel?.title ?? ""
      case .errorNumber:event.errorNumber.map(String.init) ?? ""
      case .severity:event.severity.map(String.init) ?? ""
      case .timestamp:event.timestamp
      case .clientPID:event.clientPID
      case .session:event.session
      case .sql:event.sql
      case .host:event.host
      case .application:event.application
      case .login:event.login
      case .database:event.database
      case .kind:event.kind
      case .duration:event.durationMS.map {String($0)} ?? ""
      case .cpu:event.cpu
      case .reads:event.reads
      case .writes:event.writes
      }
    }
  }
  public enum Comparison:String,CaseIterable,Identifiable,Sendable,Codable {
    case contains,notContains,equals,notEquals,atLeast,atMost
    public var id:String {rawValue}
    public var title:String {
      switch self {case .contains:"İçerir";case .notContains:"İçermez";case .equals:"Eşittir";case .notEquals:"Eşit değil";case .atLeast:"En az (≥)";case .atMost:"En çok (≤)"}
    }
  }
  public struct Rule:Identifiable,Sendable,Equatable,Codable {
    public let id:UUID
    public var column:Column
    public var comparison:Comparison
    public var value:String
    public init(column:Column = .clientPID,comparison:Comparison = .equals,value:String="") {id=UUID();self.column=column;self.comparison=comparison;self.value=value}
  }
  public struct Filter:Sendable,Equatable,Codable {
    public var hideInformational=true
    public var sqlSearch=""
    public var rules:[Rule]=[]
    public var columnRules:[Column:ColumnRule]=[:]
    public init() {}
  }
  public struct Client:Identifiable,Sendable {
    public struct Key:Hashable,Sendable {public let host:String;public let pid:String}
    public let id:Key
    public let count:Int
    public let durationMS:Double?
    public let applications:String
  }
  public struct Projection:Sendable {
    public let relations:[UInt64:SQLProfilerCorrelation.Relation]
    public let events:[SQLProfiler.Event]
    public let clients:[Client]
    public let unknownClientEvents:Int
  }
  private static func number(_ text:String)->Decimal? {
    var dots=0,digits=0
    for byte in text.utf8 {
      if byte==46 {dots+=1;if dots>1 {return nil}}
      else if (48...57).contains(byte) {digits+=1}
      else {return nil}
    }
    guard digits>0,!text.hasPrefix("."),!text.hasSuffix("."),let value=Decimal(string:text,locale:Locale(identifier:"en_US_POSIX")),!value.isNaN else {return nil}
    return value
  }
  public static func rows(_ events:[SQLProfiler.Event],columns:[Column])throws->Rows {
    let fields=columns.map {Field($0.title,type:$0 == .timestamp ? -155:$0.numeric ? 3:-9)}
    var values:[[String?]]=[];values.reserveCapacity(events.count)
    for (index,event) in events.enumerated() {
      if index%64==0 {try Task.checkCancellation()}
      values.append(columns.map {$0.value(event)})
    }
    return Rows(fields:fields,values:values)
  }
  public static func project(_ events:[SQLProfiler.Event],filter:Filter) throws -> Projection {
    guard filter.rules.count+filter.columnRules.count<=20,filter.sqlSearch.utf16.count<=2048 else {throw SQLFailure("En fazla 20 kolon filtresi ve 2.048 karakter arama kullanılabilir.")}
    let rules=try filter.rules.filter {!$0.value.isEmpty}.map {rule -> (Rule,Decimal?) in
      guard rule.value.utf16.count<=1024,rule.column.operators.contains(rule.comparison) else {throw SQLFailure("\(rule.column.title) filtresinin işlemi veya değeri geçersiz.")}
      let numeric=rule.column.numeric ? number(rule.value):nil
      guard !rule.column.numeric || numeric != nil else {throw SQLFailure("\(rule.column.title) için geçerli, negatif olmayan sayı girin.")}
      if [.clientPID,.session].contains(rule.column),rule.value.contains(".") {throw SQLFailure("\(rule.column.title) tam sayı olmalıdır.")}
      return (rule,numeric)
    }
    func matches(_ event:SQLProfiler.Event)->Bool {
      if event.isCallStart {return false}
      if filter.hideInformational,event.messageLevel == .info {return false}
      if !filter.sqlSearch.isEmpty,event.sql.range(of:filter.sqlSearch,options:[.caseInsensitive,.literal])==nil {return false}
      return rules.allSatisfy {rule,numeric in
        let value=rule.column.value(event)
        if let numeric {
          guard let actual=number(value) else {return false}
          switch rule.comparison {case .equals:return actual==numeric;case .notEquals:return actual != numeric;case .atLeast:return actual>=numeric;case .atMost:return actual<=numeric;default:return false}
        }
        let equal=value.compare(rule.value,options:[.caseInsensitive,.literal]) == .orderedSame
        let contains=value.range(of:rule.value,options:[.caseInsensitive,.literal]) != nil
        switch rule.comparison {case .contains:return contains;case .notContains:return !contains;case .equals:return equal;case .notEquals:return !equal;default:return false}
      }
    }
    let columns=Column.allCases.filter {filter.columnRules[$0]?.active==true}
    var visible:Set<Int>?
    if !columns.isEmpty {
      for column in columns {
        let rule=filter.columnRules[column]!
        guard rule.first.utf16.count<=1024,rule.second.utf16.count<=1024,(rule.choices?.count ?? 0)<=5000 else {throw SQLFailure("Kolon filtresi boyut sınırını aşıyor.")}
      }
      let rows=try rows(events,columns:columns)
      let mapped=Dictionary(uniqueKeysWithValues:columns.enumerated().map {($0.offset,filter.columnRules[$0.element]!)})
      if let indices=try ResultFiltering.projection(rows,search:"",rules:mapped,sortColumn:nil,ascending:true) {visible=Set(indices)}
    }
    var filtered:[SQLProfiler.Event]=[]
    var groups:[Client.Key:(count:Int,duration:Double,measured:Int,apps:Set<String>)]=[:]
    var unknown=0
    for (index,event) in events.enumerated() {
      if index%64==0 {try Task.checkCancellation()}
      guard visible?.contains(index) ?? true,matches(event) else {continue}
      filtered.append(event)
      guard !event.clientPID.isEmpty,!event.host.isEmpty else {unknown+=1;continue}
      let key=Client.Key(host:event.host,pid:event.clientPID)
      var value=groups[key] ?? (0,0,0,[])
      value.count+=1
      if let duration=event.durationMS {value.duration+=duration;value.measured+=1}
      if !event.application.isEmpty {value.apps.insert(event.application)}
      groups[key]=value
    }
    let clients=groups.map {key,value in Client(id:key,count:value.count,durationMS:value.measured>0 ? value.duration:nil,applications:value.apps.sorted().joined(separator:", "))}.sorted {
      if $0.count != $1.count {return $0.count>$1.count}
      if $0.durationMS != $1.durationMS {return ($0.durationMS ?? -1)>($1.durationMS ?? -1)}
      if $0.id.host != $1.id.host {return $0.id.host<$1.id.host}
      return $0.id.pid<$1.id.pid
    }
    return Projection(relations:SQLProfilerCorrelation.relations(events),events:filtered,clients:clients,unknownClientEvents:unknown)
  }
}
