import Foundation

/// Bounded, read-only type metadata. Scalar returns never masquerade as TABLE.
public enum SQLObjectHover {
  public struct Info:Sendable,Equatable {
    public let title:String
    public let detail:String
  }
  static func typeExpression(_ value:String,_ type:String)->String {
    "\(type).name + CASE WHEN \(type).name IN ('nvarchar','nchar') THEN '('+CASE WHEN \(value).max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),\(value).max_length/2) END+')' WHEN \(type).name IN ('varchar','char','varbinary','binary') THEN '('+CASE WHEN \(value).max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),\(value).max_length) END+')' WHEN \(type).name IN ('decimal','numeric') THEN '('+CONVERT(varchar(10),\(value).precision)+','+CONVERT(varchar(10),\(value).scale)+')' WHEN \(type).name IN ('time','datetime2','datetimeoffset') THEN '('+CONVERT(varchar(10),\(value).scale)+')' ELSE '' END"
  }
  public static func query(targets:[[String]],column:String?=nil)throws->String {
    guard !targets.isEmpty,targets.count<=8,targets.allSatisfy({(1...2).contains($0.count) && $0.allSatisfy {!$0.isEmpty && $0.count<=128}}),column.map({!$0.isEmpty && $0.count<=128}) ?? true else {throw SQLFailure("Nesne hover kapsamı geçersiz.")}
    let ids=targets.map {"OBJECT_ID("+SQL.literal($0.map(SQL.identifier).joined(separator:"."))+")"}.joined(separator:",")
    let filter=column.map {" AND c.name="+SQL.literal($0)} ?? ""
    return """
    SELECT TOP(17) o.object_id,SCHEMA_NAME(o.schema_id),o.name,o.type_desc,c.name,\(typeExpression("c","t"))+CASE WHEN c.is_nullable=1 THEN ' NULL' ELSE ' NOT NULL' END
    FROM sys.objects o JOIN sys.columns c ON c.object_id=o.object_id JOIN sys.types t ON t.user_type_id=c.user_type_id
    WHERE o.object_id IN (\(ids)) AND o.type IN ('U','V','IF','TF','FT')\(filter)
    UNION ALL
    SELECT o.object_id,SCHEMA_NAME(o.schema_id),o.name,o.type_desc,N'Return Value',\(typeExpression("p","t"))
    FROM sys.objects o JOIN sys.parameters p ON p.object_id=o.object_id AND p.parameter_id=0 JOIN sys.types t ON t.user_type_id=p.user_type_id
    WHERE o.object_id IN (\(ids)) AND o.type IN ('FN','FS')\(column == nil ? "":" AND 1=0")
    ORDER BY 1,5;
    """
  }
  public static func decode(_ execution:Execution,column:String?=nil)->Info? {
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
    let header=kind.contains("TABLE_VALUED_FUNCTION") ? "Table Function → TABLE":kind=="VIEW" ? "View":"Tablo"
    let lines=rows.prefix(8).map {($0[4] ?? "")+" · "+($0[5] ?? "")}
    return Info(title:qualified,detail:([header]+lines+(rows.count>8 ? ["…"]:[])).joined(separator:"\n"))
  }
}
