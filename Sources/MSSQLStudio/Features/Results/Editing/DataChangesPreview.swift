import AppKit
import SQLServerKit
import SwiftUI

struct DataChangesPreview: View {
  let sql: String
  let target: String
  let submit: () async throws -> Void
  @State private var sending = false
  @State private var completed = false
  @State private var message = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      StudioPanelHeading(title: "Değişiklikleri İncele", icon: "doc.text.magnifyingglass", subtitle: target)
      Text("SQL onayınızla tek transaction içinde gönderilir. Primary key varsa satır yalnız özgün anahtarıyla bulunur; diğer kolonların eşzamanlı değişimleri denetlenmez. Primary key yoksa özgün değerlerle tek bir satır eşleşmesi gerekir; bulunamazsa veya birden fazla satır eşleşirse işlem geri alınır.").foregroundStyle(.secondary)
      HStack(spacing:16) {
        Label("SQL önizlemesi",systemImage:"chevron.left.forwardslash.chevron.right").font(.callout.weight(.semibold))
        Spacer()
        Label("Salt okunur",systemImage:"lock").font(.caption).foregroundStyle(.secondary)
        Label("Transaction koruması",systemImage:"shield.checkered").font(.caption).foregroundStyle(.secondary)
      }.padding(.horizontal,4)
      SQLReadOnlyPreview(sql: sql)
        .clipShape(RoundedRectangle(cornerRadius:8))
        .overlay(RoundedRectangle(cornerRadius:8).stroke(Color(nsColor:StudioTheme.border),lineWidth:1).allowsHitTesting(false))
      StudioFeedback(message:message,tone:completed ? .success:.error)
      HStack {
        if sending { ProgressView().controlSize(.small) }
        Spacer()
        StudioActionButton(completed ? "Gönderildi" : "Onayla ve Veritabanına Gönder", icon: completed ? "checkmark.circle.fill" : "paperplane.fill", tint: .green) {
          sending = true
          Task {
            defer { sending = false }
            do { try await submit(); completed = true; message = "Değişiklikler gönderildi. Sonuç yeniden yükleniyor." }
            catch { message = error.localizedDescription + " Bağlantı hatasında işlem tamamlanmış olabilir; yeniden göndermeden önce sonucu kontrol edin." }
          }
        }.buttonStyle(StudioPrimaryButton()).disabled(sending || completed || !message.isEmpty)
      }
    }.padding(StudioMetrics.gap).studioPanel()
  }
}

@MainActor final class DataReviewWindowController: NSWindowController, NSWindowDelegate {
  var canClose: (() -> Bool)?
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard canClose?() != false else { NSSound.beep(); return false }
    return true
  }
}
