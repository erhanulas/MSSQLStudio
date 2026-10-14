import Foundation

/// Bounded, read-only type metadata. Scalar returns never masquerade as TABLE.
public enum SQLObjectHover {
  public struct Info:Sendable,Equatable {
    public let title:String
    public let detail:String
    public var columns:[Column] = []
  }
  public struct Column:Sendable,Equatable {
    public let ordinal:Int
    public let name:String
    public let type:String
  }
  static func typeExpression(_ value:String,_ type:String,baseType:String?=nil)->String {
    let name=baseType.map {"COALESCE(\($0).name,\(type).name)"} ?? "\(type).name"
    let formatted="\(name) + CASE WHEN \(name) IN ('nvarchar','nchar') THEN '('+CASE WHEN \(value).max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),\(value).max_length/2) END+')' WHEN \(name) IN ('varchar','char','varbinary','binary') THEN '('+CASE WHEN \(value).max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),\(value).max_length) END+')' WHEN \(name) IN ('decimal','numeric') THEN '('+CONVERT(varchar(10),\(value).precision)+','+CONVERT(varchar(10),\(value).scale)+')' WHEN \(name) IN ('time','datetime2','datetimeoffset') THEN '('+CONVERT(varchar(10),\(value).scale)+')' ELSE '' END"
    guard let baseType else {return formatted}
    return "CASE WHEN \(type).user_type_id<>\(type).system_type_id AND \(baseType).name IS NOT NULL AND \(type).name<>\(baseType).name THEN \(type).name+' ('+(\(formatted))+')' ELSE \(formatted) END"
  }
  static func baseTypeJoin(_ value:String,_ base:String)->String {
    "LEFT JOIN sys.types \(base) ON \(base).user_type_id=\(value).system_type_id AND \(base).user_type_id=\(base).system_type_id"
  }
  public static func query(targets:[[String]],column:String?=nil)throws->String {
    guard !targets.isEmpty,targets.count<=8,targets.allSatisfy({(1...2).contains($0.count) && $0.allSatisfy {!$0.isEmpty && $0.count<=128}}),column.map({!$0.isEmpty && $0.count<=128}) ?? true else {throw SQLFailure("Nesne hover kapsamı geçersiz.")}
    let ids=targets.map {"OBJECT_ID("+SQL.literal($0.map(SQL.identifier).joined(separator:"."))+")"}.joined(separator:",")
    let filter=column.map {" AND c.name="+SQL.literal($0)} ?? ""
    return """
    SELECT o.object_id,SCHEMA_NAME(o.schema_id),o.name,o.type_desc,c.name,\(typeExpression("c","t",baseType:"b"))+CASE WHEN c.is_nullable=1 THEN ' NULL' ELSE ' NOT NULL' END,c.column_id
    FROM sys.objects o JOIN sys.columns c ON c.object_id=o.object_id JOIN sys.types t ON t.user_type_id=c.user_type_id \(baseTypeJoin("c","b"))
    WHERE o.object_id IN (\(ids)) AND o.type IN (\(column == nil ? "'IF','TF','FT'":"'U','V','IF','TF','FT'"))\(filter)
    UNION ALL
    SELECT o.object_id,SCHEMA_NAME(o.schema_id),o.name,o.type_desc,N'Return Value',\(typeExpression("p","t",baseType:"b")),0
    FROM sys.objects o JOIN sys.parameters p ON p.object_id=o.object_id AND p.parameter_id=0 JOIN sys.types t ON t.user_type_id=p.user_type_id \(baseTypeJoin("p","b"))
    WHERE o.object_id IN (\(ids)) AND o.type IN ('FN','FS')\(column == nil ? "":" AND 1=0")
    ORDER BY 1,7;
    """
  }
  public static func decode(_ execution:Execution,column:String?=nil)->Info? {
    guard !execution.partial, !execution.stoppedEarly, execution.results.first?.truncated != true else {return nil}
    let rows=(execution.results.first?.values ?? []).filter {$0.count>=6}
    guard !rows.isEmpty,Set(rows.compactMap {$0[0]}).count==1,
      let first=rows.first,let schema=first[1],let name=first[2],let kind=first[3] else {return nil}
    let qualified=schema+"."+name
    if kind.contains("SCALAR_FUNCTION") {
      guard column==nil,let type=first[5] else {return nil}
      return Info(title:qualified,detail:"Scalar Function → "+type)
    }
    if let column,let row=rows.first(where:{$0[4]?.caseInsensitiveCompare(column) == .orderedSame}),let type=row[5] {
      return Info(title:qualified+"."+(row[4] ?? column),detail:type)
    }
    guard kind.contains("TABLE_VALUED_FUNCTION") else {return nil}
    let header="Table Function → TABLE"
    let columns=rows.enumerated().map { index,row in
      Column(ordinal:row.count>6 ? Int(row[6] ?? "") ?? index+1 : index+1,
        name:row[4] ?? "",type:row[5] ?? "")
    }.sorted {$0.ordinal<$1.ordinal}
    let lines=columns.map {$0.name+" · "+$0.type}
    return Info(title:qualified,detail:([header]+lines).joined(separator:"\n"),columns:columns)
  }
}
