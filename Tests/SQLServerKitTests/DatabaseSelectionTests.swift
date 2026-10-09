import Foundation
import Testing

@testable import SQLServerKit

struct DatabaseSelectionTests {
  private var many: [CatalogItem] {
    [
      CatalogItem(id: 1, name: "master"), CatalogItem(id: 2, name: "model"),
      CatalogItem(id: 3, name: "msdb"), CatalogItem(id: 4, name: "tempdb"),
    ]
      + (1...1000).map { CatalogItem(id: $0 + 4, name: "Sales_2026_\($0)") }
      + [
        CatalogItem(id: 2000, name: "İstanbul_Satış_2025"),
        CatalogItem(id: 2001, name: "Sales_Archive_2024"),
      ]
  }
  @Test func findsAcrossLargeCatalogWithTermsNaturalOrderAndUnicode() {
    let result = DatabaseSelection.filtered(
      many, search: "sales,2026; 99", scope: .user, selectedOnly: false, chosen: [])
    #expect(
      result.map(\.name) == [
        "Sales_2026_99", "Sales_2026_199", "Sales_2026_299", "Sales_2026_399", "Sales_2026_499",
        "Sales_2026_599", "Sales_2026_699", "Sales_2026_799", "Sales_2026_899", "Sales_2026_990",
        "Sales_2026_991", "Sales_2026_992", "Sales_2026_993", "Sales_2026_994", "Sales_2026_995",
        "Sales_2026_996", "Sales_2026_997", "Sales_2026_998", "Sales_2026_999",
      ])
    let unicode = DatabaseSelection.filtered(
      many, search: "İstanbul satış", scope: .all, selectedOnly: false, chosen: [])
    #expect(unicode.map(\.name) == ["İstanbul_Satış_2025"])
    #expect(
      DatabaseSelection.filtered(
        many, search: "   \n", scope: .system, selectedOnly: false, chosen: []
      ).count == 4)
  }
  @Test func bulkActionsOnlyChangeVisibleMatchesAndKeepOtherSelections() {
    let selected: Set<String> = ["master", "Sales_Archive_2024"]
    let visible = DatabaseSelection.filtered(
      many, search: "2026", scope: .user, selectedOnly: false, chosen: selected)
    let expanded = DatabaseSelection.changingVisible(visible, chosen: selected, select: true)
    #expect(expanded.count == 1002)
    #expect(DatabaseSelection.changingVisible(visible, chosen: expanded, select: false) == selected)
    let selectedMatches = DatabaseSelection.filtered(
      many, search: "sales", scope: .all, selectedOnly: true, chosen: selected)
    #expect(selectedMatches.map(\.name) == ["Sales_Archive_2024"])
    #expect(DatabaseSelection.changingVisible([], chosen: selected, select: false) == selected)
    #expect(
      DatabaseSelection.filtered(
        many, search: "missing", scope: .all, selectedOnly: false, chosen: []
      ).isEmpty)
  }
  @Test func defaultStaysSelectedAndFallsBackDeterministically() {
    let selected: Set<String> = ["Sales_2026_10", "Sales_2026_2", "missing"]
    #expect(
      DatabaseSelection.defaultName("Sales_2026_10", items: many, chosen: selected)
        == "Sales_2026_10")
    #expect(
      DatabaseSelection.defaultName("master", items: many, chosen: selected) == "Sales_2026_2")
    #expect(DatabaseSelection.defaultName("missing", items: many, chosen: ["missing"]) == "")
    #expect(DatabaseSelection.defaultName("master", items: many, chosen: []) == "")
  }
}
