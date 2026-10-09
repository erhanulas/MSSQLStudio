import Darwin
import Foundation
import Testing

@testable import SQLServerKit

@Suite struct ResultGridTests {
  @Test func boundedDecodedRowsRemainCorrectAcrossEvictionAndAppend() throws {
    let spool = try ResultSpool()
    var snapshot = try spool.append((0..<600).map { row in (0..<64).map { column in "İ\(row):\(column)" } })
    for _ in 0..<2 {
      for row in 0..<600 { #expect(snapshot[row][63] == "İ\(row):63") }
    }
    #expect(snapshot[0][0] == "İ0:0")
    snapshot = try spool.append([["appended"]])
    #expect(snapshot[600] == ["appended"])
    #expect(snapshot[599][63] == "İ599:63")
  }
  let fields = [Field("N", type: 3), Field("Text"), Field("When", type: 93)]
  var sample: Rows {
    Rows(
      fields: fields,
      values: [
        ["10", "İstanbul", "2026-10-09 12:00:00"], ["2", "", "2026-10-08 12:00:00"],
        [nil, nil, nil], ["2", "Ankara", "2026-10-09 12:00:00"],
        ["9007199254740993", "Z", "2026-10-10 12:00:00"],
      ])
  }
  @Test func typesNullEmptyAndStableOrder() throws {
    #expect(
      try ResultFiltering.projection(sample, search: "", rules: [:], sortColumn: 0, ascending: true)
        == [2, 1, 3, 0, 4])
    #expect(
      try ResultFiltering.projection(
        sample, search: "", rules: [:], sortColumn: 2, ascending: false) == [4, 0, 3, 1, 2])
    var r = ColumnRule()
    r.choices = [.null]
    #expect(
      try ResultFiltering.projection(
        sample, search: "", rules: [1: r], sortColumn: nil, ascending: true) == [2])
    r.choices = [.text("")]
    #expect(
      try ResultFiltering.projection(
        sample, search: "", rules: [1: r], sortColumn: nil, ascending: true) == [1])
  }
  @Test func combinesRulesSearchAndExactDecimal() throws {
    var n = ColumnRule()
    n.operation = .between
    n.first = "2"
    n.second = "10"
    var s = ColumnRule()
    s.operation = .contains
    s.first = "Ankara"
    #expect(
      try ResultFiltering.projection(
        sample, search: "ank", rules: [0: n, 1: s], sortColumn: nil, ascending: true) == [3])
    n.operation = .greater
    n.first = "9007199254740992"
    #expect(
      try ResultFiltering.projection(
        sample, search: "", rules: [0: n], sortColumn: nil, ascending: true) == [4])
    n.first = "2oops"
    #expect(throws: SQLFailure.self) { try ResultFiltering.validate(n, field: fields[0]) }
    n.operation = .between
    n.first = "10"
    n.second = "2"
    #expect(throws: SQLFailure.self) { try ResultFiltering.validate(n, field: fields[0]) }
  }
  @Test func choicesAreBoundedAndSearchFindsBeyondFirstPage() throws {
    let rows = Rows(
      fields: [Field("Name")], values: (0..<1001).map { ["Name\($0)"] } + [[nil], [""]])
    let a = try ResultFiltering.choices(rows, column: 0, search: "")
    #expect(a.values.count == 500)
    #expect(a.truncated)
    let b = try ResultFiltering.choices(rows, column: 0, search: "1000")
    #expect(b.values == [.text("Name1000")])
    #expect(!b.truncated)
  }
  @Test func diskSnapshotsRandomAccessAndValueCopies() throws {
    let spool = try ResultSpool()
    let first = try spool.append([[nil, ""], ["İstanbul\n😀", "x"]])
    let last = try spool.append([["last"]])
    #expect(first.count == 2)
    #expect(last.count == 3)
    #expect(last[2] == ["last"])
    #expect(first[0] == [nil, ""])
    #expect(last[1] == ["İstanbul\n😀", "x"])
    var copy = last
    copy.append(["copy"])
    #expect(copy.count == 4)
    #expect(last.count == 3)
    #expect(first.readFailure == nil)
  }
  @Test func streamingExportRespectsProjectionNullAndDuplicateNames() throws {
    let spool = try ResultSpool()
    var rows = Rows(fields: [Field("X"), Field("X")])
    rows.values = try spool.append([["=SUM(1)", nil], ["", "😀"]])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try ResultFileExport.write(rows, indices: [1, 0], json: true, to: url)
    let object = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(object["columns"] as? [String] == ["X", "X"])
    let values = try #require(object["rows"] as? [[Any]])
    #expect(values.count == 2)
    #expect(values[1][1] is NSNull)
    try ResultFileExport.write(rows, indices: [0], json: false, to: url)
    let csv = try String(contentsOf: url, encoding: .utf8)
    #expect(csv.contains("'=SUM(1)"))
    #expect(csv.contains("\\N"))
    #expect(!csv.contains("😀"))
  }
  @Test func cancellationDoesNotReplaceDestination() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try "original".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    let job = Task {
      try await Task.sleep(for: .milliseconds(20))
      try ResultFileExport.write(sample, indices: nil, json: true, to: url)
    }
    job.cancel()
    await #expect(throws: CancellationError.self) { try await job.value }
    #expect(try String(contentsOf: url, encoding: .utf8) == "original")
    let filterJob = Task {
      try await Task.sleep(for: .milliseconds(20))
      return try ResultFiltering.projection(
        sample, search: "a", rules: [:], sortColumn: 0, ascending: true)
    }
    filterJob.cancel()
    await #expect(throws: CancellationError.self) { try await filterJob.value }
  }
  @Test func twoMillionRowsBenchmark() throws {
    guard ProcessInfo.processInfo.environment["MSSQL_GRID_BENCHMARK"] == "1" else { return }
    let start = Date()
    let spool = try ResultSpool()
    var values = RowCollection()
    for base in stride(from: 0, to: 2_000_000, by: 512) {
      values = try spool.append(
        (base..<min(base + 512, 2_000_000)).map { [String($0), $0 % 2 == 0 ? "even" : "odd"] })
    }
    let stored = Date()
    var rows = Rows(fields: [Field("N", type: 4), Field("Group")])
    rows.values = values
    var rule = ColumnRule()
    rule.choices = [.text("even")]
    let projection = try #require(
      try ResultFiltering.projection(
        rows, search: "", rules: [1: rule], sortColumn: 0, ascending: false))
    #expect(values.count == 2_000_000)
    #expect(projection.count == 1_000_000)
    #expect(projection.first == 1_999_998)
    #expect(projection.last == 0)
    #expect(values[1_234_567][0] == "1234567")
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    print("GRID_BENCHMARK testProcessMaxRSSBytes=\(usage.ru_maxrss)")
    print(
      "GRID_BENCHMARK rows=2000000 storedSeconds=\(stored.timeIntervalSince(start)) filterSortSeconds=\(Date().timeIntervalSince(stored))"
    )
  }
}
