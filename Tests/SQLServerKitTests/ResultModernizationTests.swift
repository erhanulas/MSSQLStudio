import Foundation
import Testing
@testable import SQLServerKit

struct ResultModernizationTests {
  @Test func keylessMetadataCacheIsReusableAndFieldShapeChangesInvalidateItsKey() async throws {
    let folder = URL(fileURLWithPath: "/tmp/MSSQLStudio-keyless-cache-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let index = CatalogDiskIndex(url: folder.appendingPathComponent("index.sqlite")), profile = ServerProfile()
    let fields = [Field("Label", type: -9, size: 10)], sql = "SELECT * FROM dbo.Heap;"
    let snapshot = ResultEditingSnapshot(objectID: 42, table: .init(schema: "dbo", name: "Heap", columns: [.init(id: 1, name: "Label", type: "nvarchar(10)")]))
    let key = CatalogDiskIndex.editingFingerprint(sql: sql, fields: fields)
    try await index.saveEditingMetadata(snapshot, scope: CatalogDiskIndex.scope(profile: profile, database: "D"), fingerprint: key)
    let result = try await ResultEditingPreparation.load(sql: sql, fields: fields, profile: profile, database: "D", index: index) { _ in throw SQLFailure("Keyless cache must avoid network") }
    #expect(result.cached && result.snapshot.primaryKey.isEmpty)
    #expect(key != CatalogDiskIndex.editingFingerprint(sql: sql, fields: [Field("Label", type: -9, size: 20)]))
  }
  @Test func integerRangesAndAliasesRejectTextWithoutChangingValues() throws {
    for (type, good, bad) in [("tinyint", "255", "256"), ("smallint", "-32768", "32768"), ("int", "2147483647", "2147483648"), ("bigint", "-9223372036854775808", "9223372036854775808")] {
      let column = TableColumn(id: 1, name: "Count", type: "[dbo].[Counter]", nullable: false, baseType: type)
      try ResultValueValidation.validate(good, column: column)
      for value in [bad, "text", "1.5", "1e2", ""] { #expect(throws: SQLFailure.self) { try ResultValueValidation.validate(value, column: column) } }
      #expect(throws: SQLFailure.self) { try ResultValueValidation.validate(nil, column: column) }
      #expect(try DataEditScripts.value(good, column: column) == "CONVERT(\(type), N'\(good)')")
    }
  }
  @Test func exactDecimalsLengthsBinaryAndDatesValidateBeforeSQL() throws {
    let decimal = TableColumn(id: 1, name: "Amount", type: "decimal(38,8)")
    let exact = "123456789012345678901234567890.12345678"
    #expect(try DataEditScripts.value(exact, column: decimal).contains(exact))
    for value in ["1234567890123456789012345678901.0", "0.123456789", "1,2", "NaN"] { #expect(throws: SQLFailure.self) { try ResultValueValidation.validate(value, column: decimal) } }
    try ResultValueValidation.validate("0.12345678000", column: decimal)
    for (type, good, bad) in [("bit", "1", "2"), ("nvarchar(2)", "😀", "😀x"), ("binary(2)", "0x0011", "0x001122"), ("date", "2024-02-29", "2025-02-29"), ("time(7)", "23:59:59.1234567", "24:00:00"), ("datetime", "1753-01-01 12:00:00", "1752-12-31"), ("money", "922337203685477.5807", "922337203685477.5808")] {
      let column = TableColumn(id: 1, name: "Value", type: type)
      try ResultValueValidation.validate(good, column: column)
      #expect(throws: SQLFailure.self) { try ResultValueValidation.validate(bad, column: column) }
    }
    #expect(throws: SQLFailure.self) { try DataEditScripts.changes(table: .init(schema: "dbo", name: "T", columns: [.init(id: 1, name: "Id", type: "int")], primaryKey: ["Id"]), rows: [.init(original: nil, values: ["invalid"], touched: [0])]) }
  }
  @Test func resultUpdatesUseOnlyOriginalCompositeKeyIncludingKeyEdits() throws {
    let table = TableDefinition(schema: "dbo", name: "T", columns: [.init(id: 1, name: "Tenant", type: "int"), .init(id: 2, name: "Code", type: "nvarchar(10)"), .init(id: 3, name: "Name", type: "nvarchar(20)"), .init(id: 4, name: "Version", type: "rowversion")], primaryKey: ["Tenant", "Code"])
    let row = DataEditRow(original: ["7", "OLD", "Before", "0x0011"], values: ["7", "NEW", "After", "0x0011"])
    let sql = try DataEditScripts.changes(table: table, rows: [row], expectedObjectID: 42, rowMatching: .primaryKeyOrOriginalValues)
    let statement = try #require(sql.components(separatedBy: "\n").first { $0.hasPrefix("UPDATE ") })
    #expect(statement.hasSuffix("WHERE [Tenant] = 7 AND [Code] = N'OLD';"))
    #expect(!statement.contains("Before") && !statement.contains("[Version]") && statement.contains("[Code] = N'NEW'"))
    #expect(sql.contains("@@ROWCOUNT <> 1") && sql.contains("ROLLBACK TRANSACTION") && sql.contains("<> 42"))
    var deleted = row; deleted.deleted = true
    #expect(try DataEditScripts.changes(table: table, rows: [deleted], rowMatching: .primaryKeyOrOriginalValues).contains("DELETE FROM [dbo].[T] WHERE [Tenant]"))
    try sql.write(toFile: "/tmp/MSSQLStudio-result-key-update.sql", atomically: true, encoding: .utf8)
  }
  @Test func keylessOriginalRowsRequireOneLockedMatchAndKeepNullAndStringIdentity() throws {
    let table = TableDefinition(schema: "dbo", name: "Heap", columns: [.init(id: 1, name: "Number", type: "int"), .init(id: 2, name: "Label", type: "nvarchar(30)"), .init(id: 3, name: "Other", type: "int")])
    let row = DataEditRow(original: ["1", "Original ", nil], values: ["1", "Changed", nil])
    let sql = try DataEditScripts.changes(table: table, rows: [row], rowMatching: .primaryKeyOrOriginalValues)
    #expect(sql.contains("COUNT_BIG(*) FROM [dbo].[Heap] WITH (UPDLOCK, HOLDLOCK)"))
    #expect(sql.contains("CONVERT(varbinary(max),[Label])") && sql.contains("[Other] IS NULL") && sql.contains("<> 1 THROW 51003"))
    #expect(!sql.contains("TOP (1)") && sql.contains("@@ROWCOUNT <> 1"))
    #expect(throws: SQLFailure.self) { try DataEditScripts.changes(table: table, rows: [row]) } // Separate designer keeps its optimistic PK policy.
    let unsupported = TableDefinition(schema: "dbo", name: "Spatial", columns: [.init(id: 1, name: "Shape", type: "geometry")])
    #expect(throws: SQLFailure.self) { try DataEditScripts.changes(table: unsupported, rows: [.init(original: ["x"], values: ["x"], deleted: true)], rowMatching: .primaryKeyOrOriginalValues) }
    try sql.write(toFile: "/tmp/MSSQLStudio-result-keyless-update.sql", atomically: true, encoding: .utf8)
  }
  @Test func editingMetadataOmitsDDLButKeepsFullProjectionAndSpecialTableGuards() throws {
    let query = ObjectMetadata.editingTable(schema: "dbo", name: "Odd]'Name")
    #expect(query.contains("OBJECT_ID(N'[dbo].[Odd]]''Name]', N'U')"))
    #expect(query.contains("c.encryption_type") && query.contains("t.temporal_type") && query.contains("k.type='PK'"))
    #expect(!query.contains("STRING_AGG") && !query.contains("sys.triggers") && !query.contains("CREATE "))
    var output = Execution()
    output.results = [Rows(values: [["42"]]), Rows(values: [["1", "Id", "int", "0", "0", nil, nil, nil, "0", nil, nil, nil, "0", "0", "0", "int"]]), Rows(), Rows(values: [["0", nil]])]
    let metadata = try ObjectMetadata.decodeEditing(output, schema: "dbo", name: "T")
    #expect(metadata.objectID == 42 && metadata.table.primaryKey.isEmpty && metadata.table.columns.count == 1)
    let source = try ResultEditSource.decode({ var e = Execution(); e.results = [Rows(values: [["Id", nil, "D", "dbo", "T", "Id", nil, nil, "1"]])]; return e }(), fields: [Field("Id", type: 4)], database: "D")
    #expect(try source.projected(metadata.table).columns.count == 1)
    output.results[3] = Rows(values: [["1", nil]])
    #expect(throws: SQLFailure.self) { try ObjectMetadata.decodeEditing(output, schema: "dbo", name: "T") }
    try query.write(toFile: "/tmp/MSSQLStudio-result-editing-metadata.sql", atomically: true, encoding: .utf8)
  }
}
