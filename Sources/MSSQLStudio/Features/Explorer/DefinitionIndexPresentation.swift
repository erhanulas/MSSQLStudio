import Foundation
import SQLServerKit
import SwiftUI

struct DefinitionIndexActivity {
  enum Phase { case waiting, building, paused, failed }
  var phase: Phase
  var processed = 0
  var total: Int?
  var error: String?
  var stage: String?
}
struct DefinitionIndexPresentation {
  let enabled: Bool
  let online: Bool
  let stored: DefinitionIndexStatus?
  let activity: DefinitionIndexActivity?
  var building: Bool { enabled && activity?.phase == .building }
  var warning:Bool {failed || (enabled && stored?.synchronizedAt != nil && stored?.incomplete == true)}
  var failed: Bool { enabled && activity?.phase == .failed }
  var title: String {
    guard enabled else { return "Kapalı" }
    if let activity {
      switch activity.phase {
      case .waiting: return "Sırada"
      case .building: return "Eşitleniyor"
      case .paused: return "Duraklatıldı"
      case .failed: return "Hata"
      }
    }
    guard let stored else { return "Henüz hazırlanmadı" }
    if stored.synchronizedAt == nil {
      return stored.count > 0 ? "Kısmi indeks" : "Henüz hazırlanmadı"
    }
    return stored.incomplete ? "Kısmi indeks" : "Hazır"
  }
  var detail: String {
    guard enabled else { return "Bu veritabanı için Nesne içeriklerini indeksle seçeneğini açın." }
    var lines = [title + " · \(stored?.count ?? 0) kayıtlı tanım"]
    if building, let activity {
      if let stage = activity.stage { lines.append(stage) }
      lines.append(
        activity.total.map { "\(activity.processed) / \($0) nesne kontrol edildi" }
          ?? "Nesne listesi okunuyor…")
    }
    if let date = stored?.synchronizedAt {
      lines.append("Son eşitleme: " + date.formatted(date: .numeric, time: .shortened))
    }
    if let date = stored?.lastFetched {
      lines.append("Son içerik okuma: " + date.formatted(date: .numeric, time: .shortened))
    }
    if let stored, stored.unavailable > 0 { lines.append("\(stored.unavailable) nesne okunamadı") }
    if let stored, let expected = stored.expected, stored.count < expected - stored.unavailable {
      lines.append("Bazı tanımlar kotadan dolayı temizlenmiş veya henüz alınmamış olabilir.")
    }
    if let error = activity?.error { lines.append(error) }
    if !online { lines.append("Çevrimdışı · Son disk indeksi") }
    return lines.joined(separator: "\n")
  }
}
struct DefinitionIndexMetric: View {
  let value: DefinitionIndexPresentation
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label("Nesne içerikleri", systemImage: "doc.text.magnifyingglass").font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        Text(value.title).font(.headline)
        if value.building { ProgressView().controlSize(.small) }
      }
      Text(value.detail).font(.caption2).foregroundStyle(value.failed ? .orange : .secondary)
        .textSelection(.enabled)
    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).explorerInfoCard()
  }
}
