import AppKit
import CoreText
import SQLServerKit
import SwiftUI

struct AssistantPanel: View {
  let sql: String
  var open: (String) -> Void
  @State private var endpoint = "http://localhost:11434/v1/chat/completions"
  @State private var model = ""
  @State private var key = ""
  @State private var prompt = ""
  @State private var response = ""
  @State private var error = ""
  @State private var task: Task<Void, Never>?
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: "SQL Assistant", icon: "sparkles", subtitle: "Önerileri incele, ardından sorgu sekmesine taşı")
      StudioFormField("API adresi") {TextField("Chat/completions adresi", text: $endpoint)}
      StudioFormField("Model") {TextField("Model", text: $model)}
      StudioFormField("API anahtarı") {SecureField("Yalnızca bu pencere", text: $key)}
      Text(
        "Aşağıdaki metin belirttiğiniz adrese gönderilir. Sonuçlar, şema ve bağlantı bilgileri eklenmez."
      ).font(.caption).foregroundStyle(.secondary)
      VSplitView {
        VStack(alignment:.leading,spacing:8) {
          Text("İstek").font(.system(size:12,weight:.semibold))
          TextEditor(text: $prompt).font(.custom(StudioTheme.codeFont.fontName, size: 13)).studioEditor().frame(
            minHeight: 90, idealHeight: 150)
          HStack {
            StudioActionButton("Editördeki SQL'i İsteğe Ekle", icon:"text.badge.plus", tint:.accentColor) { prompt += "\n\n```sql\n\(sql)\n```" }.disabled(
              task != nil)
            StudioActionButton("Gönder", icon:"paperplane.fill", tint:.accentColor) {
              error = ""
              let address = endpoint
              let token = key
              let chosenModel = model
              let text = prompt
              task = Task {
                do {
                  response = try await AssistantClient.request(
                    endpoint: address, key: token, model: chosenModel, prompt: text)
                } catch let failure { self.error = failure.localizedDescription }
                task = nil
              }
            }.disabled(task != nil || prompt.isEmpty || model.isEmpty)
            StudioActionButton("Durdur", icon:"stop.fill", tint:.orange) { task?.cancel() }.disabled(task == nil)
          }
        }.frame(minHeight:170,idealHeight:230)
        VStack(alignment:.leading,spacing:8) {
          Text("Yanıt").font(.system(size:12,weight:.semibold))
          if response.isEmpty {
            StudioEmptyState(title:"Öneriler burada görünecek",icon:"text.bubble",detail:"Bir istek yazıp gönderin. Gelen SQL’i çalıştırmadan önce inceleyebilirsiniz.")
          } else {
            ScrollView {
              SSMSMarkdown(text: response).frame(maxWidth: .infinity, alignment: .leading)
            }.studioEditor()
          }
          if let sql = AssistantClient.sql(from: response) {
            StudioActionButton("Önerilen SQL'i Yeni Sekmede İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) { open(sql) }
          }
        }.frame(minHeight:140,idealHeight:220)
      }
      StudioFeedback(message:error)
    }.padding(StudioMetrics.gap).studioPanel().onDisappear { task?.cancel() }
  }
}
