import Foundation

/// A cheap immutable row snapshot. GUI queries spill to a private, unlinked temporary file.
public struct RowCollection: RandomAccessCollection, ExpressibleByArrayLiteral, Sendable {
  public typealias Element = [String?]
  public typealias Index = Int
  private var memory: [[String?]]
  private let disk: ResultSpool?
  public private(set) var count: Int
  public var startIndex: Int { 0 }
  public var endIndex: Int { count }
  public var diskBacked: Bool { disk != nil }
  public var readFailure: String? { disk?.readFailure }
  public init(arrayLiteral elements: [String?]...) { self.init(elements) }
  public init(_ rows: [[String?]] = []) {
    memory = rows
    disk = nil
    count = rows.count
  }
  init(spool: ResultSpool, count: Int) {
    memory = []
    disk = spool
    self.count = count
  }
  public subscript(index: Int) -> Element {
    precondition(index >= 0 && index < count)
    return disk?.row(index) ?? memory[index]
  }
  /// A constant-space view of the first loaded rows. The full backing snapshot
  /// remains owned by its caller, so a later larger limit can reveal it again.
  public func prefixSnapshot(_ maximumCount:Int) -> Self {
    var snapshot=self
    snapshot.count=Swift.min(count,Swift.max(0,maximumCount))
    return snapshot
  }
  public func index(after i: Int) -> Int { i + 1 }
  public func index(before i: Int) -> Int { i - 1 }
  public mutating func append(_ row: Element) {
    if disk != nil {
      self = RowCollection(Array(self) + [row])
    } else {
      if count < memory.count {memory=Array(memory.prefix(count))}
      memory.append(row)
      count = memory.count
    }
  }
  public mutating func append(contentsOf rows: [[String?]]) {
    if disk != nil {
      self = RowCollection(Array(self) + rows)
    } else {
      if count < memory.count {memory=Array(memory.prefix(count))}
      memory.append(contentsOf: rows)
      count = memory.count
    }
  }
}

/// Serialized writer; snapshots and cached page reads may run on any queue.
/// The file is unlinked immediately, so normal close AND crashes leave no result file behind.
public final class ResultSpool: @unchecked Sendable {
  private struct Page {
    let start: Int
    let count: Int
    let offset: UInt64
    let bytes: Int
  }
  private let lock = NSLock()
  private let writerLock=NSLock()
  private let encode:@Sendable ([[String?]]) throws -> (data:Data,sizes:[Int])
  private let handle: FileHandle
  private var pages: [Page] = []
  private var count = 0
  private var offset: UInt64 = 0
  private struct Record {
    let offset: UInt64
    let bytes: Int
  }
  private var records: [Record] = []
  private var cachedPage: Page?
  private var cachedData = Data()
  private var lastIndex = -1
  private var lastRow: [String?] = []
  private var decoded: [Int: ([String?], Int)] = [:]
  private var decodedOrder: [Int] = []
  private var decodedCursor = 0
  private var decodedBytes = 0
  private var failure: String?
  public var readFailure: String? {
    lock.lock()
    defer { lock.unlock() }
    return failure
  }
  public convenience init() throws {try self.init(encode:Self.encodeRows)}
  init(encode:@escaping @Sendable ([[String?]]) throws -> (data:Data,sizes:[Int])) throws {
    self.encode=encode
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MSSQL-result-\(UUID()).tmp"
    ).path
    guard
      FileManager.default.createFile(
        atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
    else {
      throw SQLFailure("Geçici sonuç dosyası oluşturulamadı.")
    }
    do { handle = try FileHandle(forUpdating: URL(fileURLWithPath: path)) } catch {
      try? FileManager.default.removeItem(atPath: path)
      throw error
    }
    try FileManager.default.removeItem(atPath: path)
  }
  deinit { try? handle.close() }
  private static func encodeRows(_ rows:[[String?]]) throws -> (data:Data,sizes:[Int]) {
    var data=Data(),sizes:[Int]=[]
    let encoder=JSONEncoder()
    for row in rows {
      let item=try encoder.encode(row)
      sizes.append(item.count);data.append(item)
    }
    return (data,sizes)
  }
  public func append(_ rows: [[String?]]) throws -> RowCollection {
    // Keep append order serialized without making UI reads wait for JSON encoding.
    writerLock.lock()
    defer {writerLock.unlock()}
    let encoded=try encode(rows)
    lock.lock()
    defer { lock.unlock() }
    if !rows.isEmpty {
      let data=encoded.data
      var next:[Record]=[],relative=0
      for size in encoded.sizes {
        next.append(Record(offset:offset+UInt64(relative),bytes:size));relative+=size
      }
      try handle.seek(toOffset: offset)
      try handle.write(contentsOf: data)
      pages.append(Page(start: count, count: rows.count, offset: offset, bytes: data.count))
      records.append(contentsOf: next)
      count += rows.count
      offset += UInt64(data.count)
    }
    return RowCollection(spool: self, count: count)
  }
  fileprivate func row(_ index: Int) -> [String?] {
    lock.lock()
    defer { lock.unlock() }
    if index == lastIndex { return lastRow }
    if let cached = decoded[index] { return cached.0 }
    let record = records[index]
    do {
      let data: Data
      if let page = cachedPage,
        record.offset >= page.offset
          && record.offset + UInt64(record.bytes) <= page.offset + UInt64(page.bytes)
      {
        let start = Int(record.offset - page.offset)
        data = cachedData.subdata(in: start..<start + record.bytes)
      } else if index == lastIndex + 1 {
        var lo = 0
        var hi = pages.count
        while lo < hi {
          let mid = (lo + hi) / 2
          if pages[mid].start <= index { lo = mid + 1 } else { hi = mid }
        }
        let page = pages[lo - 1]
        try handle.seek(toOffset: page.offset)
        guard let bytes = try handle.read(upToCount: page.bytes), bytes.count == page.bytes else {
          throw SQLFailure("Geçici sonuç dosyası eksik okunabildi.")
        }
        cachedPage = page
        cachedData = bytes
        let start = Int(record.offset - page.offset)
        data = bytes.subdata(in: start..<start + record.bytes)
      } else {
        try handle.seek(toOffset: record.offset)
        guard let bytes = try handle.read(upToCount: record.bytes), bytes.count == record.bytes
        else { throw SQLFailure("Geçici sonuç dosyası eksik okunabildi.") }
        data = bytes
      }
      lastRow = try JSONDecoder().decode([String?].self, from: data)
      let cost = data.count * 4 + lastRow.count * 32
      if cost <= 8_388_608 {
        while !decoded.isEmpty && (decodedBytes + cost > 8_388_608 || decoded.count >= 256) {
          let key = decodedOrder[decodedCursor]
          if let value = decoded.removeValue(forKey: key) { decodedBytes -= value.1 }
          decodedCursor += 1
        }
        if decodedCursor > 512 { decodedOrder.removeFirst(decodedCursor); decodedCursor = 0 }
        decoded[index] = (lastRow,cost); decodedOrder.append(index); decodedBytes += cost
      }
      lastIndex = index
      return lastRow
    } catch {
      failure = error.localizedDescription
      return []
    }
  }
}
