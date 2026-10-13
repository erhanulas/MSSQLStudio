import AppKit
import CoreText
import SQLServerKit
import SwiftUI

struct IndexPanel: View {
  var table: String
  var load: () async throws -> [CatalogItem]
  var open: (String) -> Void
  @State private var columns: [CatalogItem] = []
  @State private var keys: Set<String> = []
  @State private var includes: Set<String> = []
  @State private var name = "IX_NewIndex"
  @State private var unique = false
  @State private var filter = ""
  @State private var preview = ""
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: "Index Designer", icon: "list.number", subtitle: table)
      StudioFormField("İndeks adı") {TextField("İndeks adı", text: $name)}
      Toggle("UNIQUE", isOn: $unique)
      ScrollView {
        VStack {
          ForEach(columns, id: \.id) { column in
            HStack {
              Text(column.name).frame(maxWidth: .infinity, alignment: .leading)
              Toggle("Key", isOn: binding(column.name, set: $keys))
              Toggle("Include", isOn: binding(column.name, set: $includes))
            }
          }
        }
      }.frame(height: 160)
      StudioFormField("Filtre") {TextField("Filtre (isteğe bağlı WHERE koşulu)", text: $filter)}
      HStack {
        StudioActionButton("SQL Oluştur", icon:"doc.badge.gearshape", tint:.accentColor) {
          do {
            preview = try Scripts.index(
              table: table, name: name, keys: columns.filter { keys.contains($0.name) }.map(\.name),
              included: columns.filter { includes.contains($0.name) }.map(\.name), unique: unique,
              filter: filter)
            error = ""
          } catch let failure { error = failure.localizedDescription }
        }
        StudioActionButton("Sorgu Sekmesine Aktar", icon:"arrow.up.forward.square", tint:.accentColor) { open(preview) }.disabled(preview.isEmpty)
      }
      Text("SQL'i inceleyip sorgu sekmesinden çalıştırın.").foregroundStyle(.secondary).font(
        .caption)
      TextEditor(text: $preview).font(.custom(StudioTheme.codeFont.fontName, size: 13)).studioEditor()
      Text(error).font(.caption).foregroundStyle(.red)
    }.padding(20).studioPanel().task {
      do { columns = try await load() } catch let failure {
        self.error = failure.localizedDescription
      }
    }
  }
  func binding(_ name: String, set: Binding<Set<String>>) -> Binding<Bool> {
    Binding(
      get: { set.wrappedValue.contains(name) },
      set: { if $0 { set.wrappedValue.insert(name) } else { set.wrappedValue.remove(name) } })
  }
}
