import Foundation

public enum ActivityRequestTermination {
  public enum Target:Sendable {
    case request(ActivityMonitoring.Request)
    case applicationLock(ActivityApplicationLocks.Lock)
    public var sessionID:Int64 {
      switch self {case .request(let value):value.sessionID;case .applicationLock(let value):value.sessionID}
    }
  }
  public static func sql(for target:Target) throws -> String {
    switch target {case .request(let value):try sql(for:value);case .applicationLock(let value):try applicationLockSQL(value)}
  }
  private static func applicationLockSQL(_ lock:ActivityApplicationLocks.Lock) throws -> String {
    guard (51...32767).contains(lock.sessionID),let login=lock.sessionLoginTime,validTimestamp(login),
      let database=lock.databaseID,(1...32767).contains(database),
      ["SESSION","TRANSACTION"].contains(lock.ownerType),let owner=Int64(lock.ownerID),owner>=0,
      let address=lock.id.first,!lock.resource.isEmpty,lock.resource.utf16.count<=256,!lock.resource.contains("\0") else {
      throw SQLFailure("Sonlandırma için güncel application lock ve kullanıcı oturumu kimliği gerekli. Listeyi yenileyin.")
    }
    let parts=address.split(separator:":",omittingEmptySubsequences:false)
    guard parts.count==2,parts[0].hasPrefix("0x"),parts[0].count>2,parts[0].count<=18,
      parts[0].dropFirst(2).allSatisfy({"0123456789abcdefABCDEF".contains($0)}),
      let partition=Int32(parts[1]),partition>=0 else {throw SQLFailure("Uygulama kilidi adresi geçersiz.")}
    return """
    SET NOCOUNT ON;
    IF @@TRANCOUNT <> 0 THROW 51080,N'Sonlandırma ayrı, transaction olmayan bir bağlantı gerektirir.',1;
    IF @@SPID = \(lock.sessionID) THROW 51080,N'İzleme bağlantısı sonlandırılamaz.',1;
    IF NOT EXISTS (
      SELECT 1 FROM sys.dm_exec_sessions s JOIN sys.dm_tran_locks l ON l.request_session_id=s.session_id
      WHERE s.session_id=\(lock.sessionID) AND s.is_user_process=1
        AND s.login_time=CONVERT(datetime,\(SQL.literal(login)),121)
        AND l.resource_type=N'APPLICATION' AND l.resource_database_id=\(database)
        AND CONVERT(varchar(34),l.lock_owner_address,1)=\(SQL.literal(String(parts[0]))) AND l.resource_lock_partition=\(partition)
        AND l.resource_description=\(SQL.literal(lock.resource))
        AND l.request_owner_type=\(SQL.literal(lock.ownerType)) AND l.request_owner_id=\(owner)
    ) THROW 51081,N'Seçili application lock veya oturum değişmiş ya da kilit bırakılmış. Listeyi yenileyin.',1;
    IF EXISTS (SELECT 1 FROM sys.dm_exec_requests WHERE session_id=\(lock.sessionID) AND (command LIKE N'BACKUP%' OR command LIKE N'%ROLLBACK%'))
      THROW 51082,N'Yedekleme veya geri alma yapan oturum bu işlemle sonlandırılamaz.',1;
    KILL \(lock.sessionID);
    """
  }
  public static func sql(for request:ActivityMonitoring.Request) throws -> String {
    guard (51...32767).contains(request.sessionID),(0...Int64(Int32.max)).contains(request.requestID),
      !request.command.uppercased().hasPrefix("BACKUP"),
      !request.command.uppercased().contains("ROLLBACK"),
      let login=request.sessionLoginTime,let start=request.requestStartTime,
      validTimestamp(login),validTimestamp(start) else {
      throw SQLFailure("Sonlandırma için güncel kullanıcı oturumu ve istek kimliği gerekli. DBA listesini yenileyin.")
    }
    return """
    SET NOCOUNT ON;
    IF @@TRANCOUNT <> 0 THROW 51080,N'Sonlandırma ayrı, transaction olmayan bir bağlantı gerektirir.',1;
    IF @@SPID = \(request.sessionID) THROW 51080,N'İzleme bağlantısı sonlandırılamaz.',1;
    IF NOT EXISTS (
      SELECT 1 FROM sys.dm_exec_sessions s JOIN sys.dm_exec_requests r ON r.session_id=s.session_id
      WHERE s.session_id=\(request.sessionID) AND r.request_id=\(request.requestID) AND s.is_user_process=1
        AND s.login_time=CONVERT(datetime,\(SQL.literal(login)),121)
        AND r.start_time=CONVERT(datetime,\(SQL.literal(start)),121)
        AND r.command NOT LIKE N'BACKUP%' AND r.command NOT LIKE N'%ROLLBACK%'
    ) THROW 51081,N'Seçili oturum veya sorgu değişmiş ya da tamamlanmış. DBA listesini yenileyin.',1;
    KILL \(request.sessionID);
    """
  }
  private static func validTimestamp(_ text:String)->Bool {
    guard text.utf8.count==23 else {return false}
    let formatter=DateFormatter()
    formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(secondsFromGMT:0)
    formatter.dateFormat="yyyy-MM-dd HH:mm:ss.SSS";formatter.isLenient=false
    guard let date=formatter.date(from:text) else {return false}
    return formatter.string(from:date)==text
  }
}
