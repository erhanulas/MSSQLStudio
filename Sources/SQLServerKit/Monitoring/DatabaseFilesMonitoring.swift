import Foundation

/// Read-only file inventory. Usage is read only in the file's own database context.
public enum DatabaseFilesMonitoring {
  public struct File: Identifiable, Sendable, Equatable {
    public var id:String {"\(databaseID):\(fileID)"}
    public let databaseID:Int64
    public let fileID:Int64
    public let database:String?
    public let name:String
    public let type:String
    public let path:String?
    public let sizePages:Int64?
    public let maxPages:Int64?
    public let growth:Int64?
    public let percentGrowth:Bool?
    public let state:String?
    public let readOnly:Bool?
    public let sparse:Bool?
    public let usedPages:Int64?
    public var freePages:Int64? {
      guard type == "ROWS",sparse == false,let sizePages,let usedPages,usedPages<=sizePages else {return nil}
      return sizePages-usedPages
    }
    public var usedFraction:Double? {
      guard let usedPages,let sizePages,sizePages>0,freePages != nil else {return nil}
      return Double(usedPages)/Double(sizePages)
    }
  }
  public struct Inventory:Sendable {
    public let files:[File]
    public let issues:[String]
    public let limited:Bool
  }
  public static let columns=["database_id","file_id","database_name","name","type_desc","physical_name","size_pages","max_size_pages","growth","is_percent_growth","state_desc","is_read_only","is_sparse"]
  public static let inventorySQL="""
  SELECT TOP (5001) f.database_id,f.file_id,DB_NAME(f.database_id) AS database_name,f.name,f.type_desc,f.physical_name,
    CASE WHEN f.database_id=2 OR f.type=2 THEN NULL ELSE CONVERT(bigint,f.size) END AS size_pages,
    CONVERT(bigint,f.max_size) AS max_size_pages,CONVERT(bigint,f.growth) AS growth,f.is_percent_growth,f.state_desc,f.is_read_only,f.is_sparse
  FROM sys.master_files AS f ORDER BY f.database_id,f.file_id;
  SELECT N'Dosya görünürlüğü sunucu yetkileriyle sınırlı olabilir; tüm dosyalar için CREATE DATABASE, ALTER ANY DATABASE veya VIEW ANY DEFINITION gerekir.' AS issue
  WHERE ISNULL(HAS_PERMS_BY_NAME(NULL,N'SERVER',N'VIEW ANY DEFINITION'),0)<>1
    AND ISNULL(HAS_PERMS_BY_NAME(NULL,N'SERVER',N'ALTER ANY DATABASE'),0)<>1
    AND ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'CREATE DATABASE'),0)<>1;
  """
  public static let detailSQL="""
  SELECT TOP (5001) DB_ID() AS database_id,f.file_id,DB_NAME() AS database_name,f.name,f.type_desc,f.physical_name,
    CONVERT(bigint,f.size) AS size_pages,CONVERT(bigint,f.max_size) AS max_size_pages,CONVERT(bigint,f.growth) AS growth,
    f.is_percent_growth,f.state_desc,f.is_read_only,f.is_sparse,
    CASE WHEN f.type=0 AND f.is_sparse=0 THEN CONVERT(bigint,FILEPROPERTY(f.name,N'SpaceUsed')) ELSE NULL END AS used_pages
  FROM sys.database_files AS f ORDER BY f.file_id;
  """
  public static func detailSQL(database:String) -> String {
    detailSQL.replacingOccurrences(of:"ORDER BY f.file_id;",with:"WHERE DB_NAME()=\(SQL.literal(database)) ORDER BY f.file_id;")
  }
  public static func decodeInventory(_ execution:Execution) throws -> Inventory {
    try validate(execution,resultSets:2)
    let files=try decodeRows(execution.results[0],detail:false)
    let issueRows=execution.results[1]
    guard issueRows.fields.map(\.name) == ["issue"],issueRows.values.allSatisfy({$0.count == 1 && $0[0] != nil}),issueRows.values.count<=1 else {throw SQLFailure("Dosya görünürlük bilgisi okunamadı.")}
    let issues=issueRows.values.compactMap {$0[0]}.filter {!$0.isEmpty}
    return Inventory(files:Array(files.prefix(5000)),issues:issues,limited:files.count>5000)
  }
  public static func decodeDetails(_ execution:Execution,database:String) throws -> Inventory {
    try validate(execution,resultSets:1)
    let files=try decodeRows(execution.results[0],detail:true)
    guard files.allSatisfy({$0.database == database}),Set(files.map(\.databaseID)).count<=1 else {throw SQLFailure("Dosya ayrıntısı seçili veritabanına ait değil.")}
    return Inventory(files:Array(files.prefix(5000)),issues:[],limited:files.count>5000)
  }
  private static func validate(_ execution:Execution,resultSets:Int) throws {
    guard !execution.partial,!execution.stoppedEarly,execution.results.count == resultSets,
      execution.results.allSatisfy({!$0.truncated}) else {throw SQLFailure("Dosya bilgileri eksik geldi; son doğrulanmış liste korunuyor.")}
  }
  private static func decodeRows(_ rows:Rows,detail:Bool) throws -> [File] {
    let expected=columns+(detail ? ["used_pages"]:[])
    guard rows.fields.map(\.name) == expected,rows.values.count<=5001 else {throw SQLFailure("Dosya bilgisi biçimi tanınamadı.")}
    var ids=Set<String>()
    return try rows.values.map {row in
      guard row.count == expected.count,let databaseID=row[0].flatMap(Int64.init),databaseID>0,
        let fileID=row[1].flatMap(Int64.init),fileID>0,let name=row[3],!name.isEmpty,
        let type=row[4],!type.isEmpty,ids.insert("\(databaseID):\(fileID)").inserted else {throw SQLFailure("Dosya kimliği veya satır bilgisi geçersiz.")}
      func pages(_ value:String?) -> Int64? {guard let number=value.flatMap(Int64.init),number>=0,number<=Int64.max/8192 else {return nil};return number}
      func bit(_ value:String?) -> Bool? {value == "1" ? true:value == "0" ? false:nil}
      let size=pages(row[6]),sparse=bit(row[12])
      let maxValue=row[7].flatMap(Int64.init)
      let maxPages=maxValue == -1 ? maxValue:pages(row[7])
      var used=detail && type == "ROWS" && sparse == false ? pages(row[13]):nil
      if let value=used,let size,value>size {used=nil}
      return File(databaseID:databaseID,fileID:fileID,database:row[2].flatMap {$0.isEmpty ? nil:$0},name:name,type:type,path:row[5],sizePages:size,maxPages:maxPages,growth:pages(row[8]),percentGrowth:bit(row[9]),state:row[10],readOnly:bit(row[11]),sparse:sparse,usedPages:used)
    }
  }
}
