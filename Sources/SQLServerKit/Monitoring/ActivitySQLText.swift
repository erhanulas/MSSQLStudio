import Foundation

/// Fetch one immutable SQL-cache entry selected from a bounded monitoring snapshot.
public enum ActivitySQLText {
  public static let maximumBytes=2*1024*1024
  public static func sql(handle:String) throws -> String {
    guard handle.hasPrefix("0x"),(4...130).contains(handle.utf8.count),handle.utf8.count.isMultiple(of:2),
      handle.dropFirst(2).allSatisfy({"0123456789abcdefABCDEF".contains($0)}) else {throw SQLFailure("SQL metni kimliği geçersiz; DBA listesini yenileyin.")}
    return """
    SET NOCOUNT ON;
    \(ActivityMonitoring.permissionSQL)
    IF @canMonitor=0 THROW 51000,@permissionMessage,1;
    DECLARE @sql nvarchar(max);
    SELECT @sql=text FROM sys.dm_exec_sql_text(CONVERT(varbinary(64),\(SQL.literal(handle)),1));
    IF @sql IS NULL THROW 51083,N'SQL metni önbellekten kaldırılmış, şifreli veya okunamıyor. DBA listesini yenileyin.',1;
    IF DATALENGTH(@sql)>\(maximumBytes) THROW 51084,N'SQL metni 2 MB önizleme sınırını aşıyor; kesilmiş metin tam SQL olarak gösterilmedi.',1;
    SELECT @sql AS sql_text,CONVERT(bigint,DATALENGTH(@sql)) AS sql_bytes;
    """
  }
  public static func decode(_ execution:Execution) throws -> String {
    if let failure=execution.failure {throw failure}
    guard !execution.partial,!execution.stoppedEarly,execution.results.count==1,
      let rows=execution.results.first,!rows.truncated,rows.values.count==1,
      (rows.fields.isEmpty || rows.fields.map(\.name)==["sql_text","sql_bytes"]),
      rows.values[0].count==2,let sql=rows.values[0][0],let bytes=rows.values[0][1].flatMap(Int.init),
      bytes>=0,bytes<=maximumBytes,sql.utf16.count*2==bytes,rows.values.readFailure==nil else {
      throw SQLFailure("Tam SQL metni eksik veya okuma sınırına ulaşıldı; kesilmiş metin tam SQL olarak gösterilmedi.")
    }
    return sql
  }
}
