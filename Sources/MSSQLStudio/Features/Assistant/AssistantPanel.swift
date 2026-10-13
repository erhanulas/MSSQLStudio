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
      Text("İstek").font(.headline)
      TextEditor(text: $prompt).font(.custom(StudioTheme.codeFont.fontName, size: 13)).studioEditor().frame(
        height: 150)
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
      Text("Yanıt").font(.headline)
      if response.isEmpty {
        VStack(spacing: 9) {
          Image(systemName: "text.bubble").font(.system(size: 26, weight: .light)).foregroundStyle(.tint)
          Text("Öneriler burada görünecek").font(.system(size: 13, weight: .medium))
          Text("Bir istek yazıp gönderin. Gelen SQL’i çalıştırmadan önce inceleyebilirsiniz.")
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          SSMSMarkdown(text: response).frame(maxWidth: .infinity, alignment: .leading)
        }.studioEditor()
      }
      if let sql = AssistantClient.sql(from: response) {
        StudioActionButton("Önerilen SQL'i Yeni Sekmede İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) { open(sql) }
      }
      Text(error).font(.caption).foregroundStyle(.red)
    }.padding(20).studioPanel().onDisappear { task?.cancel() }
  }
}

