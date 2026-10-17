import CODBC
import Foundation

/// Serial ownership of ODBC handles, with cancellation on a separate queue.
public final class ODBCConnection: @unchecked Sendable {
  private let worker = DispatchQueue(label: "mssqlstudio.odbc", qos: .userInitiated)
  private let canceller = DispatchQueue(label: "mssqlstudio.odbc.cancel", qos: .userInitiated)
  private let lock = NSLock()
  private var environment: SQLHANDLE?
  private var connection: SQLHANDLE?
  private var statement: SQLHANDLE?
  private var cancelled = false
  private var generation: UInt64 = 0
  private var executing = false
  public init() {}
  deinit {
    if let connection {
      SQLDisconnect(connection)
      SQLFreeHandle(SQLSMALLINT(SQL_HANDLE_DBC), connection)
    }
    if let environment { SQLFreeHandle(SQLSMALLINT(SQL_HANDLE_ENV), environment) }
  }
  public func connect(_ profile: ServerProfile, password: String) async throws {
    let string = try profile.connectionString(password: password)
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      worker.async { [self] in
        do {
          closeHandles()
          try check(
            SQLAllocHandle(SQLSMALLINT(SQL_HANDLE_ENV), nil, &environment),
            kind: SQLSMALLINT(SQL_HANDLE_ENV), handle: environment)
          try check(
            SQLSetEnvAttr(
              environment, SQLINTEGER(SQL_ATTR_ODBC_VERSION),
              UnsafeMutableRawPointer(bitPattern: Int(SQL_OV_ODBC3)), 0),
            kind: SQLSMALLINT(SQL_HANDLE_ENV), handle: environment)
          try check(
            SQLAllocHandle(SQLSMALLINT(SQL_HANDLE_DBC), environment, &connection),
            kind: SQLSMALLINT(SQL_HANDLE_ENV), handle: environment)
          try check(
            SQLSetConnectAttr(
              connection, SQLINTEGER(SQL_ATTR_LOGIN_TIMEOUT),
              UnsafeMutableRawPointer(bitPattern: 10), 0), kind: SQLSMALLINT(SQL_HANDLE_DBC),
            handle: connection)
          // ODBC otherwise inherits the server's packet size, which can exceed
          // TLS's 16 KiB fragment limit. This limits packets, not SQL batch size.
          try check(
            SQLSetConnectAttr(
              connection, SQLINTEGER(SQL_ATTR_PACKET_SIZE),
              UnsafeMutableRawPointer(bitPattern: 4096), 0), kind: SQLSMALLINT(SQL_HANDLE_DBC),
            handle: connection)
          var utf16 = Array(string.utf16) + [0]
          let length = SQLSMALLINT(utf16.count - 1)
          let rc = utf16.withUnsafeMutableBufferPointer {
            SQLDriverConnectW(
              connection, nil, $0.baseAddress, length, nil, 0, nil,
              SQLUSMALLINT(SQL_DRIVER_NOPROMPT))
          }
          do {
            try check(rc, kind: SQLSMALLINT(SQL_HANDLE_DBC), handle: connection)
            var packetSize:SQLUINTEGER=0
            try check(SQLGetConnectAttr(connection,SQLINTEGER(SQL_ATTR_PACKET_SIZE),&packetSize,SQLINTEGER(MemoryLayout<SQLUINTEGER>.size),nil),kind:SQLSMALLINT(SQL_HANDLE_DBC),handle:connection)
            guard packetSize>0 && packetSize<=16368 else {
              throw SQLFailure("SQL Server şifreli bağlantı için güvenli ağ paket boyutunu kabul etmedi. Bağlantı kurulamadı.")
            }
          } catch {
            let safe = ((error as? SQLFailure)?.message ?? error.localizedDescription).replacingOccurrences(
              of: password.isEmpty ? "\0" : password, with: "••••")
            throw SQLFailure(safe, diagnostics: (error as? SQLFailure)?.diagnostics.map {
              Diagnostic(state:$0.state,code:$0.code,message:$0.message.replacingOccurrences(of:password.isEmpty ? "\0" : password,with:"••••"),line:$0.line,procedure:$0.procedure)
            } ?? [])
          }
          continuation.resume()
        } catch {
          closeHandles()
          continuation.resume(throwing: error)
        }
      }
    }
  }
  public func disconnect() async {
    await withCheckedContinuation { continuation in
      worker.async { [self] in
        closeHandles()
        continuation.resume()
      }
    }
  }
  public func execute(
    _ text: String, limits: Limits = Limits(), events: (@Sendable (QueryEvent) -> Void)? = nil
  ) async throws -> Execution {
    guard !text.isEmpty, !text.contains("\0"), text.utf16.count < Int(Int32.max) else {
      throw SQLFailure("SQL metni boş, geçersiz veya çok uzun.")
    }
    guard
      lock.withLock({
        if executing { return false }
        executing = true
        cancelled = false
        return true
      })
    else { throw SQLFailure("Bu oturumda başka bir sorgu çalışıyor.") }
    return try await withCheckedThrowingContinuation { continuation in
      worker.async { [self] in
        defer { lock.withLock { executing = false } }
        do {
          continuation.resume(returning: try executeSync(text, limits: limits, events: events))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
  public func cancel() {
    let token = lock.withLock {
      cancelled = true
      return generation
    }
    requestCancellation(token, attempt: 0)
  }
  private func requestCancellation(_ token: UInt64, attempt: Int) {
    canceller.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.03)) { [self] in
      let retry = lock.withLock { () -> Bool in
        guard generation == token, cancelled, let statement else { return false }
        _ = SQLCancelHandle(SQLSMALLINT(SQL_HANDLE_STMT), statement)
        return attempt < 100
      }
      if retry { requestCancellation(token, attempt: attempt + 1) }
    }
  }
  private func closeHandles() {
    if let connection {
      SQLDisconnect(connection)
      SQLFreeHandle(SQLSMALLINT(SQL_HANDLE_DBC), connection)
    }
    connection = nil
    if let environment { SQLFreeHandle(SQLSMALLINT(SQL_HANDLE_ENV), environment) }
    environment = nil
  }
  private func executeSync(
    _ text: String, limits: Limits, events: (@Sendable (QueryEvent) -> Void)?
  ) throws -> Execution {
    guard let connection else { throw SQLFailure("Oturum bağlı değil.", diagnostics:[Diagnostic(state:"08003",code:0,message:"ODBC oturumu kapalı.")]) }
    let start = Date()
    var output = Execution()
    var handle: SQLHANDLE?
    try check(
      SQLAllocHandle(SQLSMALLINT(SQL_HANDLE_STMT), connection, &handle),
      kind: SQLSMALLINT(SQL_HANDLE_DBC), handle: connection)
    guard let handle else { throw SQLFailure("Sorgu handle'ı oluşturulamadı.") }
    lock.withLock {
      generation &+= 1
      statement = handle
    }
    defer {
      lock.withLock {
        statement = nil
        generation &+= 1
        SQLFreeHandle(SQLSMALLINT(SQL_HANDLE_STMT), handle)
      }
    }
    try check(
      SQLSetStmtAttr(
        handle, SQLINTEGER(SQL_ATTR_QUERY_TIMEOUT),
        UnsafeMutableRawPointer(bitPattern: max(1, limits.timeout)), 0),
      kind: SQLSMALLINT(SQL_HANDLE_STMT), handle: handle)
    func cancelledCheck() throws {
      if lock.withLock({ cancelled }) { throw SQLFailure("Sorgu iptal edildi.") }
    }
    func messages(_ rc: SQLRETURN) {
      if rc == SQL_SUCCESS_WITH_INFO {
        for diagnostic in diagnostics(SQLSMALLINT(SQL_HANDLE_STMT), handle)
        where diagnostic.state != "01004" {
          output.messages.append(diagnostic.description)
          events?(.message(diagnostic.description))
        }
      }
    }
    let preserveExecution=limits.readOnlyRowLimit && (limits.preserveExecution || !TSQL.canRepeatRead(text))
    let fetchRows=preserveExecution ? Int.max:limits.rows
    let serverLimited=try ServerReadLimit.configure(sql:text,rows:fetchRows,write:{maximum in
      try check(SQLSetStmtAttr(handle,SQLINTEGER(SQL_ATTR_MAX_ROWS),UnsafeMutableRawPointer(bitPattern:maximum),0),kind:SQLSMALLINT(SQL_HANDLE_STMT),handle:handle)
    },read:{
      var actual:SQLULEN=0
      try check(SQLGetStmtAttr(handle,SQLINTEGER(SQL_ATTR_MAX_ROWS),&actual,SQLINTEGER(MemoryLayout<SQLULEN>.size),nil),kind:SQLSMALLINT(SQL_HANDLE_STMT),handle:handle)
      return Int(clamping:actual)
    })
    // The driver restores default MAX_ROWS on subsequent statement handles.
    // Also clear this handle's attribute before it is freed, including errors/cancel.
    defer {if serverLimited {_ = SQLSetStmtAttr(handle,SQLINTEGER(SQL_ATTR_MAX_ROWS),nil,0)}}
    try cancelledCheck()
    var utf16 = Array(text.utf16) + [0]
    let length = SQLINTEGER(utf16.count - 1)
    let rc = utf16.withUnsafeMutableBufferPointer { SQLExecDirectW(handle, $0.baseAddress, length) }
    try check(rc, kind: SQLSMALLINT(SQL_HANDLE_STMT), handle: handle)
    messages(rc)
    var totalBytes = 0
    do {
      while true {
        try cancelledCheck()
        var count: SQLSMALLINT = 0
        try check(
          SQLNumResultCols(handle, &count), kind: SQLSMALLINT(SQL_HANDLE_STMT), handle: handle)
        var affected: SQLLEN = -1
        _ = SQLRowCount(handle, &affected)
        var rows = Rows(affected: Int(affected))
        let rowsetCount=ResultStreamBudget.rowsetCount(output.results)
        let skipRowset=count>0 && (rowsetCount>=max(0,limits.resultSets) || preserveExecution && totalBytes>=max(0,limits.totalBytes))
        if skipRowset {
          output.partial=true
          if !preserveExecution {
            output.stoppedEarly=true
            output.messages.append("Sonuç kümesi sınırına ulaşıldı; kalan sonuçlar alınmadı.")
            _ = SQLCancelHandle(SQLSMALLINT(SQL_HANDLE_STMT),handle)
            break
          }
          if !output.messages.contains("Görüntüleme bütçesi doldu; kalan çıktılar saklanmadan komutun tamamlanması beklendi.") {
            output.messages.append("Görüntüleme bütçesi doldu; kalan çıktılar saklanmadan komutun tamamlanması beklendi.")
          }
        }
        if count > 0 && !skipRowset {
          for number in 1...Int(count) {
            var name = [SQLWCHAR](repeating: 0, count: 1024)
            var nameLength: SQLSMALLINT = 0
            var type: SQLSMALLINT = 0
            var size: SQLULEN = 0
            var digits: SQLSMALLINT = 0
            var nullable: SQLSMALLINT = 0
            let code = name.withUnsafeMutableBufferPointer {
              SQLDescribeColW(
                handle, SQLUSMALLINT(number), $0.baseAddress, SQLSMALLINT($0.count), &nameLength,
                &type, &size, &digits, &nullable)
            }
            try check(code, kind: SQLSMALLINT(SQL_HANDLE_STMT), handle: handle)
            var typeName = [SQLWCHAR](repeating: 0, count: 256)
            var typeNameBytes: SQLSMALLINT = 0
            let typeNameCode = typeName.withUnsafeMutableBufferPointer {
              SQLColAttributeW(handle, SQLUSMALLINT(number), SQLUSMALLINT(SQL_DESC_TYPE_NAME), $0.baseAddress, SQLSMALLINT($0.count * 2), &typeNameBytes, nil)
            }
            let declaredType = (typeNameCode == SQL_SUCCESS || typeNameCode == SQL_SUCCESS_WITH_INFO)
              ? String(decoding: typeName.prefix(min(max(0, Int(typeNameBytes) / 2), 255)), as: UTF16.self) : nil
            rows.fields.append(
              Field(
                String(decoding: name.prefix(min(Int(nameLength), 1023)), as: UTF16.self),
                type: type, size: UInt(size), scale: digits, declaredType: declaredType?.isEmpty == false ? declaredType : nil))
          }
          let resultIndex = output.results.count
          events?(.result(resultIndex, rows.fields))
          let spool = limits.diskResults ? try ResultSpool() : nil
          var pending: [[String?]] = []
          var pendingBytes = 0
          var budget=ResultFetchBudget(rows:fetchRows)
          var lastSnapshot = Date.distantPast
          func flush(force: Bool = false) throws {
            guard !pending.isEmpty else { return }
            if let spool {
              rows.values = try spool.append(pending)
              if force || Date().timeIntervalSince(lastSnapshot) >= 0.2 {
                events?(.snapshot(resultIndex, rows.values))
                lastSnapshot = Date()
              }
            } else {
              rows.values.append(contentsOf: pending)
              events?(.rows(resultIndex, pending))
            }
            pending.removeAll(keepingCapacity: true)
            pendingBytes = 0
          }
          do {
            fetchLoop: while try budget.next(fetch:{
              try cancelledCheck()
              let fetched=SQLFetch(handle)
              if fetched == SQL_NO_DATA {return false}
              try check(fetched,kind:SQLSMALLINT(SQL_HANDLE_STMT),handle:handle)
              messages(fetched)
              return true
            }) {
              var row: [String?] = []
              for (i, field) in rows.fields.enumerated() {
                let rawValue = try read(
                  handle, column: i + 1,
                  binary: [Int16(SQL_BINARY), Int16(SQL_VARBINARY), Int16(SQL_LONGVARBINARY)]
                    .contains(field.type), cap: max(1024, limits.cellBytes))
                // Normalize once, before streaming/spooling, so display, copy, export
                // and edit conflict predicates share the same lossless numeric text.
                let value = field.normalizedResultValue(rawValue)
                totalBytes += value?.utf8.count ?? 0
                if preserveExecution && totalBytes>max(0,limits.totalBytes) {
                  rows.truncated=true;output.partial=true
                  output.messages.append("Sonuç boyutu görüntüleme bütçesini aştı; kalan satırlar saklanmadan komutun tamamlanması beklendi.")
                  break fetchLoop
                }
                guard totalBytes <= max(1024, limits.totalBytes) else {
                  throw SQLFailure(
                    "Sonuç boyutu bütçesini aştı; sonuç kısmi. Daha küçük bir SELECT/TOP kullanın.")
                }
                row.append(value)
              }
              pending.append(row)
              pendingBytes += row.reduce(0) { $0 + ($1?.utf8.count ?? 0) + 16 }
              if pending.count >= 512 || pendingBytes >= 1_048_576 { try flush() }
            }
            if budget.reached {
              rows.truncated=true;output.partial=true
              let message="Sonuç \(resultIndex+1): \(budget.maximum) satır sınırına ulaşıldı; daha fazla satır olabilir. Sonraki sonuçlar ayrı okunur."
              output.messages.append(message);events?(.message(message))
            }
          } catch {
            rows.truncated = true
            try? flush(force: true)
            output.results.append(rows)
            throw error
          }
          try flush(force: true)
          if spool != nil { events?(.snapshot(resultIndex, rows.values)) }
        }
        if !skipRowset {ResultStreamBudget.append(rows,to:&output.results)}
        try cancelledCheck()
        let more = SQLMoreResults(handle)
        if more == SQL_NO_DATA { break }
        try check(more, kind: SQLSMALLINT(SQL_HANDLE_STMT), handle: handle)
        messages(more)

      }
    } catch {
      _ = SQLCancelHandle(SQLSMALLINT(SQL_HANDLE_STMT), handle)
      guard !output.results.isEmpty else { throw error }
      output.partial = true
      output.stoppedEarly = true
      output.messages.append(error.localizedDescription)
    }
    output.bytesRead = totalBytes
    output.elapsed = Date().timeIntervalSince(start)
    return output
  }
  private func read(_ handle: SQLHANDLE, column: Int, binary: Bool, cap: Int) throws -> String? {
    if binary {
      var bytes: [UInt8] = []
      var buffer = [UInt8](repeating: 0, count: 4096)
      while true {
        var length: SQLLEN = 0
        let rc = buffer.withUnsafeMutableBytes {
          SQLGetData(
            handle, SQLUSMALLINT(column), SQLSMALLINT(SQL_C_BINARY), $0.baseAddress,
            SQLLEN($0.count), &length)
        }
        if length == SQL_NULL_DATA { return nil }
        if rc == SQL_NO_DATA { break }
        try check(rc, kind: SQLSMALLINT(SQL_HANDLE_STMT), handle: handle)
        let size =
          rc == SQL_SUCCESS_WITH_INFO ? buffer.count : min(buffer.count, max(0, Int(length)))
        bytes.append(contentsOf: buffer.prefix(size))
        guard bytes.count <= cap else { throw SQLFailure("İkili hücre boyut sınırını aştı.") }
        if rc == SQL_SUCCESS { break }
      }
      return "0x" + bytes.map { String(format: "%02X", $0) }.joined()
    }
    var units: [UInt16] = []
    var buffer = [SQLWCHAR](repeating: 0, count: 2048)
    while true {
      var length: SQLLEN = 0
      let rc = buffer.withUnsafeMutableBytes {
        SQLGetData(
          handle, SQLUSMALLINT(column), SQLSMALLINT(SQL_C_WCHAR), $0.baseAddress, SQLLEN($0.count),
          &length)
      }
      if length == SQL_NULL_DATA { return nil }
      if rc == SQL_NO_DATA { break }
      try check(rc, kind: SQLSMALLINT(SQL_HANDLE_STMT), handle: handle)
      let size =
        rc == SQL_SUCCESS_WITH_INFO
        ? buffer.count - 1
        : (length == SQL_NO_TOTAL
          ? (buffer.firstIndex(of: 0) ?? buffer.count - 1)
          : min(buffer.count - 1, max(0, Int(length) / 2)))
      units.append(contentsOf: buffer.prefix(size))
      guard units.count * 2 <= cap else { throw SQLFailure("Metin hücresi boyut sınırını aştı.") }
      if rc == SQL_SUCCESS { break }
    }
    return String(decoding: units, as: UTF16.self)
  }
  private func check(_ rc: SQLRETURN, kind: SQLSMALLINT, handle: SQLHANDLE?) throws {
    guard rc == SQL_SUCCESS || rc == SQL_SUCCESS_WITH_INFO || rc == SQL_NO_DATA else {
      throw SQLFailure("SQL Server işlemi tamamlanamadı.", diagnostics: diagnostics(kind, handle))
    }
  }
  private func diagnostics(_ kind: SQLSMALLINT, _ handle: SQLHANDLE?) -> [Diagnostic] {
    guard let handle else { return [] }
    var result: [Diagnostic] = []
    for record in 1...30 {
      var state = [SQLWCHAR](repeating: 0, count: 6)
      var text = [SQLWCHAR](repeating: 0, count: 8192)
      var code: SQLINTEGER = 0
      var length: SQLSMALLINT = 0
      let rc = SQLGetDiagRecW(
        kind, handle, SQLSMALLINT(record), &state, &code, &text, SQLSMALLINT(text.count), &length)
      if rc == SQL_NO_DATA { break }
      if rc != SQL_SUCCESS && rc != SQL_SUCCESS_WITH_INFO { break }
      // Microsoft driver-specific SQL_DIAG_SS_LINE / PROCNAME (msodbcsql.h).
      var line:SQLINTEGER=0
      let lineRC=SQLGetDiagFieldW(kind,handle,SQLSMALLINT(record),-1154,&line,0,nil)
      var procedure=[SQLWCHAR](repeating:0,count:512)
      var procedureLength:SQLSMALLINT=0
      let procedureRC=SQLGetDiagFieldW(kind,handle,SQLSMALLINT(record),-1153,&procedure,SQLSMALLINT(procedure.count*2),&procedureLength)
      let procedureName=procedureRC == SQL_SUCCESS ? String(decoding:procedure.prefix(while:{$0 != 0}),as:UTF16.self):""
      result.append(
        Diagnostic(
          state: String(decoding: state.prefix(5), as: UTF16.self), code: Int(code),
          message: String(decoding: text.prefix(min(Int(length), 8191)), as: UTF16.self),
          line:lineRC == SQL_SUCCESS && line>0 ? Int(line):nil,procedure:procedureName.isEmpty ? nil:procedureName))
    }
    return result
  }
}
