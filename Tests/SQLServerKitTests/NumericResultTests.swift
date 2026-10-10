import Foundation
import Testing
@testable import SQLServerKit

struct NumericResultTests {
  @Test func leadingZeroUsesODBCBaseTypeAndPreservesEveryDigit() {
    let fields = [
      Field("N", type: 2, size: 28, scale: 8, declaredType: "TDBFLOAT"),
      Field("N", type: 3, size: 28, scale: 8, declaredType: "[dbo].[AnotherAlias]"),
      Field("N", type: 2, size: 38, scale: 38, declaredType: "numeric"),
      Field("N", type: 3, size: 38, scale: 8, declaredType: "decimal"),
      Field("N", type: 3, size: 19, scale: 4, declaredType: "money"),
      Field("N", type: 3, size: 10, scale: 4, declaredType: "smallmoney"),
      Field("N", type: 6, declaredType: "float"),
      Field("N", type: 7, declaredType: "real"),
      Field("N", type: 8, declaredType: "float"),
    ]
    let samples = [
      (".00000000", "0.00000000"), ("-.25000000", "-0.25000000"),
      ("+.25", "+0.25"), ("-.0000", "-0.0000"), (".0001", "0.0001"),
      (".12345678901234567890123456789012345678", "0.12345678901234567890123456789012345678"),
      ("-.12345678901234567E-100", "-0.12345678901234567E-100"),
      ("+.25e+12", "+0.25e+12"), ("964.80000000", "964.80000000"),
      ("99999999999999999999.12345678", "99999999999999999999.12345678"),
      ("-999999999999999999999999999999.12345678", "-999999999999999999999999999999.12345678"),
      ("9007199254740993", "9007199254740993"), ("0.00000000", "0.00000000"),
      ("1.2345678901234567E+308", "1.2345678901234567E+308"),
      ("4.9406564584124654e-324", "4.9406564584124654e-324"), ("0", "0"),
    ]
    for field in fields {
      for (raw, expected) in samples {
        let value = field.normalizedResultValue(raw)
        #expect(value == expected)
        #expect(field.normalizedResultValue(value) == expected)
      }
      #expect(field.normalizedResultValue(nil) == nil)
      for raw in ["", "NULL", ".", "-.", ".5x", ".5\n", ".5 ", " .5", ".5E", ".5E+", ".5.6", ".٥"] {
        #expect(field.normalizedResultValue(raw) == raw)
      }
    }
    #expect(fields[0].dataType == "TDBFLOAT(28,8)")
    #expect(fields[0].size == 28 && fields[0].scale == 8)
  }

  @Test func textBinaryUnknownTypesAndByteAliasesAreUnchanged() {
    for type: Int16 in [-9, 12, -3, -151, -150, 93, -7, -6, -5, 4, 5] {
      // Even an alias named TDBFLOAT must not override the actual ODBC type.
      let field = Field("Value", type: type, declaredType: "TDBFLOAT")
      for raw in [".00000000", "-.25", "0x00", "", "NULL", "255"] {
        #expect(field.normalizedResultValue(raw) == raw)
      }
      #expect(field.normalizedResultValue(nil) == nil)
    }
    let byte = Field("Kind", type: -6, size: 3, declaredType: "TDBBYTE")
    #expect(byte.numeric && byte.dataType == "TDBBYTE")
    for raw in ["0", "10", "255"] { #expect(byte.normalizedResultValue(raw) == raw) }
  }

  @Test func spoolExportAndAliasSQLKeepPrecisionScaleAndNull() throws {
    let field = Field("Amount", type: 3, size: 28, scale: 8, declaredType: "TDBFLOAT")
    let raw: [String?] = [".00000000", "-.25000000", "99999999999999999999.12345678", nil]
    let values = raw.map { [field.normalizedResultValue($0)] }
    let spool = try ResultSpool()
    var rows = Rows(fields: [field])
    rows.values = try spool.append(values)
    #expect(rows.values[0] == ["0.00000000"])
    #expect(rows.values[1] == ["-0.25000000"])
    #expect(rows.values[2] == [raw[2]])
    #expect(rows.values[3] == [nil])
    #expect(try ResultFiltering.projection(rows, search: "", rules: [:], sortColumn: 0, ascending: true) == [3, 1, 0, 2])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try ResultFileExport.write(rows, indices: nil, json: true, to: url)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let exported = try #require(object["rows"] as? [[Any]])
    for index in 0..<3 { #expect(exported[index][0] as? String == values[index][0]) }
    #expect(exported[3][0] is NSNull)
    try ResultFileExport.write(rows, indices: nil, json: false, to: url)
    let csv = try String(contentsOf: url, encoding: .utf8)
    for value in values.compactMap({ $0[0] }) { #expect(csv.contains(value)) }
    #expect(csv.contains("\\N"))

    let column = TableColumn(id: 2, name: "Amount", type: "[dbo].[TDBFLOAT]", baseType: "decimal(28,8)")
    for value in values.compactMap({ $0[0] }) {
      #expect(try DataEditScripts.value(value, column: column) == "CONVERT(decimal(28,8), N'\(value)')")
    }
    #expect(try DataEditScripts.value(nil, column: column) == "NULL")
    let byte = TableColumn(id: 3, name: "Kind", type: "[dbo].[TDBBYTE]", baseType: "tinyint")
    #expect(try DataEditScripts.value("255", column: byte) == "CONVERT(tinyint, N'255')")
  }
}

@Suite(.serialized) struct NumericResultLiveTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"] != nil))
  func numericAliasesRoundTripThroughODBCMemoryAndSpool() async throws {
    let password = try #require(ProcessInfo.processInfo.environment["MSSQL_TEST_PASSWORD"])
    let connection = ODBCConnection()
    try await connection.connect(ServerProfile(host: "localhost", port: 1433, database: "master", login: "sa", trustCertificate: true), password: password)
    let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let amountType = "[dbo]." + SQL.identifier("TDBFLOAT_" + suffix)
    let byteType = "[dbo]." + SQL.identifier("TDBBYTE_" + suffix)
    let table = "[dbo]." + SQL.identifier("StudioNumeric_" + suffix)
    do {
      _ = try await connection.execute("BEGIN TRANSACTION;")
      _ = try await connection.execute("CREATE TYPE \(amountType) FROM decimal(28,8) NULL;")
      _ = try await connection.execute("CREATE TYPE \(byteType) FROM tinyint NULL;")
      _ = try await connection.execute("""
        CREATE TABLE \(table) (Id int PRIMARY KEY, Amount \(amountType), Kind \(byteType),
          Exact numeric(38,8), Cash money, SmallCash smallmoney, F float, R real);
        INSERT INTO \(table) VALUES
          (1,0,0,0,0,0,0,0), (2,-.25,255,-.25,-.25,-.25,-.25,-.25),
          (3,99999999999999999999.12345678,10,999999999999999999999999999999.12345678,.25,.25,.25,.25),
          (4,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
        """)
      let query = "SELECT * FROM \(table) ORDER BY Id;"
      for disk in [false, true] {
        var limits = Limits(); limits.diskResults = disk
        let execution = try await connection.execute(query, limits: limits)
        #expect(!execution.partial)
        let rows = try #require(execution.results.first)
        #expect(rows.values.diskBacked == disk)
        #expect(rows.fields[1].numeric && rows.fields[1].size == 28 && rows.fields[1].scale == 8)
        #expect(rows.fields[2].type == -6)
        #expect(rows.values[0][1] == "0.00000000")
        #expect(rows.values[1][1] == "-0.25000000")
        #expect(rows.values[1][2] == "255")
        #expect(rows.values[2][1] == "99999999999999999999.12345678")
        #expect(rows.values[2][3] == "999999999999999999999999999999.12345678")
        #expect(rows.values[3].dropFirst().allSatisfy { $0 == nil })
        for index in 4...7 {
          #expect(rows.values[0][index]?.hasPrefix("0") == true)
          #expect(rows.values[1][index]?.hasPrefix("-0.25") == true)
          #expect(rows.values[2][index]?.hasPrefix("0.25") == true)
        }
      }
      let id = try #require(try await connection.execute("SELECT OBJECT_ID(\(SQL.literal(table)));").results.first?.values.first?.first.flatMap { $0 }.flatMap(Int.init))
      let definition = try ObjectMetadata.decode(try await connection.execute(ObjectMetadata.table(id)), schema: "dbo", name: "StudioNumeric_" + suffix)
      #expect(definition.columns[1].baseType == "decimal(28,8)")
      #expect(definition.columns[2].baseType == "tinyint")
      let amount = definition.columns[1], byte = definition.columns[2]
      // Exercise value and original-value conversions inside the fixture's rollback.
      // The production changes() wrapper deliberately refuses an open transaction.
      let update = try """
        UPDATE \(table) SET Amount = \(DataEditScripts.value("-0.00000001", column: amount)),
          Kind = \(DataEditScripts.value("255", column: byte))
        WHERE Id = 1 AND Amount = \(DataEditScripts.value("0.00000000", column: amount));
        IF @@ROWCOUNT <> 1 THROW 51001, N'Numeric round trip failed', 1;
        """
      let edited = try await connection.execute(update)
      #expect(!edited.partial)
      let updated = try #require(try await connection.execute(query).results.first)
      #expect(updated.values[0][1] == "-0.00000001" && updated.values[0][2] == "255")
      _ = try await connection.execute("ROLLBACK;")
      await connection.disconnect()
    } catch {
      _ = try? await connection.execute("IF @@TRANCOUNT > 0 ROLLBACK;")
      await connection.disconnect()
      throw error
    }
  }
}
