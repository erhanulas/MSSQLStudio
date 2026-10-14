import Foundation

/// A bounded page of source metadata; bodies never accumulate across the database.
public struct DefinitionIndexEntry: Sendable {
  public let object: SchemaObject
  public let parentID: Int?
  public let stamp: String
  public init(_ row: [String?]) throws {
    guard row.count == 6, let id = row[0].flatMap(Int.init), id > 0,
      let schema = row[1], let name = row[2], let type = row[3], let modified = row[4],
      ["U", "V", "P", "FN", "IF", "TF", "TR", "TRD", "SN"].contains(type)
    else { throw SQLFailure("Tanım envanteri doğrulanamadı.") }
    object = .init(key: .init(schema: schema, name: name, databaseTrigger: type == "TRD"),
                   objectID: id, type: type, digest: nil)
    parentID = row[5].flatMap(Int.init)
    stamp = IndexedObjectDefinition.stamp(schema: schema, name: name, type: type, modified: modified)
  }
  public var isModule: Bool { object.type != "U" && object.type != "SN" }
}

public enum DefinitionIndexBatch {
  public static func query(_ entries: [DefinitionIndexEntry]) throws -> String {
    guard !entries.isEmpty, entries.count <= (entries[0].isModule ? 200 : 64),
      Set(entries.map { $0.object.objectID }).count == entries.count,
      entries.allSatisfy({ $0.isModule == entries[0].isModule })
    else { throw SQLFailure("Geçersiz tanım okuma grubu.") }
    if entries[0].isModule {
      return """
        -- StudioDefinitionModuleBatch
        SELECT m.object_id,m.definition,m.uses_ansi_nulls,m.uses_quoted_identifier,ISNULL(t.is_disabled,0),CASE WHEN t.parent_class=0 THEN N'DATABASE' ELSE QUOTENAME(OBJECT_SCHEMA_NAME(t.parent_id))+N'.'+QUOTENAME(OBJECT_NAME(t.parent_id)) END,DATALENGTH(m.definition)
        FROM sys.sql_modules m LEFT JOIN sys.triggers t ON t.object_id=m.object_id
        WHERE m.object_id IN (\(entries.map { String($0.object.objectID) }.joined(separator: ",")));
        """
    }
    let tables = entries.filter { $0.object.type == "U" }.map { $0.object.objectID }
    let synonyms = entries.filter { $0.object.type == "SN" }.map { String($0.object.objectID) }
    let tableSQL = tables.isEmpty ? "" : try ObjectMetadata.tableBatch(tables)
    let synonymSQL = synonyms.isEmpty ? "" : "SELECT object_id,base_object_name FROM sys.synonyms WHERE object_id IN (" + synonyms.joined(separator: ",") + ");"
    return "-- StudioDefinitionStructureBatch\n" + tableSQL + "\n" + synonymSQL
  }
  public static func decode(_ output: Execution, entries: [DefinitionIndexEntry], fetched: Date) throws
    -> (values: [IndexedObjectDefinition], unavailable: [Int])
  {
    guard !output.partial, !output.stoppedEarly, !output.results.contains(where: \.truncated),
      !entries.isEmpty else { throw SQLFailure("Tanım grubu kısmi; önceki kayıtlar korundu.") }
    var inputs: [Int: Execution] = [:]
    if entries[0].isModule {
      guard output.results.count == 1 else { throw SQLFailure("Tanım grubu doğrulanamadı.") }
      let ids = Set(entries.map { $0.object.objectID })
      for row in output.results[0].values {
        guard row.count == 7, let id = row[0].flatMap(Int.init), ids.contains(id), inputs[id] == nil
        else { throw SQLFailure("Tanım grubu kimlikleri doğrulanamadı.") }
        if let body=row[1] {
          guard row[6].flatMap(Int.init)==body.utf16.count*2 else {throw SQLFailure("Nesne tanımı eksik okundu; önceki indeks korundu.")}
        }
        var result = Execution(); result.results = [Rows(values: [Array(row[1...5])])]
        inputs[id] = result
      }
    } else {
      let tables = entries.filter { $0.object.type == "U" }
      let synonyms = entries.filter { $0.object.type == "SN" }
      let expected = (tables.isEmpty ? 0 : 7) + (synonyms.isEmpty ? 0 : 1)
      guard output.results.count == expected else { throw SQLFailure("Tablo tanım grubu eksik.") }
      let tableIDs = Set(tables.map { $0.object.objectID })
      for entry in tables {
        var result = Execution(); result.results = Array(repeating: Rows(), count: 7)
        inputs[entry.object.objectID] = result
      }
      if !tables.isEmpty {
        for index in 0..<7 {
          var grouped: [Int: [[String?]]] = [:]
          for row in output.results[index].values {
            guard let id = row.first.flatMap({ $0 }).flatMap(Int.init), tableIDs.contains(id)
            else { throw SQLFailure("Tablo metadata kimliği doğrulanamadı.") }
            grouped[id, default: []].append(Array(row.dropFirst()))
          }
          for (id, values) in grouped { inputs[id]?.results[index] = Rows(values: values) }
        }
      }
      if !synonyms.isEmpty {
        let ids = Set(synonyms.map { $0.object.objectID })
        for row in output.results.last!.values {
          guard row.count == 2, let id = row[0].flatMap(Int.init), ids.contains(id), inputs[id] == nil
          else { throw SQLFailure("Synonym kimliği doğrulanamadı.") }
          var result = Execution(); result.results = [Rows(values: [Array(row.dropFirst())])]
          inputs[id] = result
        }
      }
    }
    var values: [IndexedObjectDefinition] = [], unavailable: [Int] = []
    for entry in entries {
      try Task.checkCancellation()
      let object = entry.object
      guard let result = inputs[object.objectID], let content = try? SchemaComparison.decodeContent(result, object: object)
      else { unavailable.append(object.objectID); continue }
      let value = IndexedObjectDefinition(id: object.objectID, schema: object.key.schema, name: object.key.name,
        type: object.type, sql: content.sql, original: content.definition, parentID: entry.parentID,
        modified: entry.stamp, fetchedAt: fetched)
      if try JSONEncoder().encode(value).count > 4_194_304 { unavailable.append(object.objectID) }
      else { values.append(value) }
    }
    return (values, unavailable)
  }
}
