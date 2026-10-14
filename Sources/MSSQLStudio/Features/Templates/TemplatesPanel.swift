import AppKit
import CoreText
import SQLServerKit
import SwiftUI

struct TemplatesPanel: View {
  var open: (SQLTemplate) -> Void
  @State private var templates: [SQLTemplate] = []
  @State private var selected: String?
  @State private var error = ""
  init(templates: [SQLTemplate] = [], open: @escaping (SQLTemplate) -> Void) {
    self.open = open
    _templates = State(initialValue: templates)
    _selected = State(initialValue: templates.first?.id)
  }
  var item: SQLTemplate? { templates.first { $0.id == selected } }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: "SQL Şablonları", icon: "square.stack.3d.up", subtitle: "Tekrar kullanılabilir sorguları tek yerde tut")
      Text("JSON şablonları içe aktarın. Şablonlar SQL sekmesi açar; otomatik çalıştırılmaz.")
        .foregroundStyle(.secondary)
      HStack {
        StudioActionButton("JSON İçe Aktar…", icon:"square.and.arrow.down", tint:.accentColor) {
          let panel = NSOpenPanel()
          panel.allowedContentTypes = [.json]
          guard panel.runModal() == .OK, let url = panel.url else { return }
          do {
            let item = try SQLTemplate.read(url)
            templates.removeAll { $0.id == item.id }
            templates.append(item)
            selected = item.id
          } catch let failure { error = failure.localizedDescription }
        }
        StudioActionButton("Örnek JSON Kaydet…", icon:"square.and.arrow.up", tint:.accentColor) {
          let panel = NSSavePanel()
          panel.nameFieldStringValue = "template.json"
          guard panel.runModal() == .OK, let url = panel.url else { return }
          do {
            let item = SQLTemplate(
              id: "server-info", name: "Server Info", description: "Sunucu sürümü ve aktif oturum",
              sql: "SELECT @@VERSION AS version, @@SPID AS session_id;")
            try JSONEncoder().encode(item).write(to: url)
          } catch let failure { error = failure.localizedDescription }
        }
      }
      VSplitView {
        Group {
          if templates.isEmpty {
            StudioEmptyState(title: "Şablon koleksiyonunu oluştur", icon: "square.stack.3d.up", detail: "Bir JSON şablonu içe aktarın veya örnek dosyayla başlayın.")
          } else {
            List(templates, selection: $selected) { Text($0.name).tag($0.id) }
          }
        }.frame(minHeight:100,idealHeight:160)
        if let item {
          VStack(alignment:.leading,spacing:8) {
            Text(item.description).foregroundStyle(.secondary)
            SQLReadOnlyPreview(sql:item.sql).frame(minHeight:120)
            StudioActionButton("Sorgu Sekmesinde Aç", icon:"arrow.up.forward.square", tint:.accentColor) { open(item) }
          }.padding(.top,8).frame(minHeight:180)
        }
      }
      StudioFeedback(message: error)
    }.padding(StudioMetrics.gap).studioPanel()
  }
}
