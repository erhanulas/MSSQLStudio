import Foundation

public struct PlanOperation: Sendable {
  public let id: Int
  public let depth: Int
  public let physical: String
  public let logical: String
  public let estimatedRows: String
  public let cost: String
  public var actualRows: Double?
  public var warnings: [String]
}
public struct ExecutionPlan: Sendable {
  public let xml: String
  public let operations: [PlanOperation]
  public static func parse(_ xml: String) throws -> Self {
    guard xml.utf8.count < 10_000_000, xml.contains("ShowPlanXML"),
      !xml.uppercased().contains("<!DOCTYPE"), !xml.uppercased().contains("<!ENTITY")
    else { throw SQLFailure("Geçerli SQL Server plan XML'i gerekli.") }
    let parser = XMLParser(data: Data(xml.utf8))
    let collector = Collector()
    parser.delegate = collector
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else {
      throw SQLFailure(
        "Plan XML'i okunamadı: \(parser.parserError?.localizedDescription ?? "XML hatası")")
    }
    return Self(xml: xml, operations: collector.operations)
  }
}
private final class Collector: NSObject, XMLParserDelegate {
  var operations: [PlanOperation] = []
  var parents: [Int] = []
  var warnings = false
  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if name == "RelOp" {
      operations.append(
        PlanOperation(
          id: operations.count, depth: parents.count, physical: attributes["PhysicalOp"] ?? "",
          logical: attributes["LogicalOp"] ?? "", estimatedRows: attributes["EstimateRows"] ?? "",
          cost: attributes["EstimatedTotalSubtreeCost"] ?? "", actualRows: nil, warnings: []))
      parents.append(operations.count - 1)
    } else if name == "RunTimeCountersPerThread", let current = parents.last,
      let rows = attributes["ActualRows"].flatMap(Double.init)
    {
      operations[current].actualRows = (operations[current].actualRows ?? 0) + rows
    } else if name == "Warnings", let current = parents.last {
      warnings = true
      operations[current].warnings += attributes.sorted { $0.key < $1.key }.map {
        "\($0.key)=\($0.value)"
      }
    } else if warnings, let current = parents.last {
      operations[current].warnings.append(name)
    }
  }
  func parser(
    _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
  ) {
    if name == "RelOp" { _ = parents.popLast() }
    if name == "Warnings" { warnings = false }
  }
}
