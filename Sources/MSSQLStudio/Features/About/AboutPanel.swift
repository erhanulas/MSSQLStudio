import AppKit
import SQLServerKit
import SwiftUI

extension WorkbenchController {
  @objc func about() {
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "studio.about" && $0.isVisible }) {
      window.makeKeyAndOrderFront(nil)
      return
    }
    let window = present(
      AboutPanel(identity: ApplicationIdentity(info: Bundle.main.infoDictionary ?? [:]),
        checkUpdates: { [weak self] in self?.installUpdate() }),
      title: "MSSQL Studio Hakkında", width: 720, height: 580, minWidth: 620, minHeight: 460)
    window.identifier = NSUserInterfaceItemIdentifier("studio.about")
  }
}

struct AboutPanel: View {
  let identity: ApplicationIdentity
  let checkUpdates: () -> Void
  private let history: [ReleaseNote]
  private let loadError: String?
  @State private var selection: String

  init(identity: ApplicationIdentity, checkUpdates: @escaping () -> Void) {
    self.identity = identity
    self.checkUpdates = checkUpdates
    do { history = try ReleaseHistory.bundled(); loadError = nil }
    catch { history = []; loadError = error.localizedDescription }
    _selection = State(initialValue: identity.version)
  }
  private var repositoryURL: URL {
    // This destination is the product's release history, independent of an alternate update feed.
    URL(string: "https://github.com/erhanulas/MSSQLStudio/releases")!
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 16) {
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 68, height: 68)
        VStack(alignment: .leading, spacing: 5) {
          Text("MSSQL Studio").font(.system(size: 24, weight: .semibold))
          Text("SQL Server için native macOS çalışma alanı").foregroundStyle(.secondary)
          Text("Sürüm \(identity.version) · Derleme \(identity.build)")
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .textSelection(.enabled).accessibilityIdentifier("aboutVersion")
        }
        Spacer()
      }.padding(24)
      Divider()
      HStack(alignment: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 10) {
          Text("SÜRÜM GEÇMİŞİ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
          ScrollView {
            VStack(spacing: 4) {
              if !history.contains(where: { $0.version == identity.version }) {
                versionButton(identity.version, current: true)
              }
              ForEach(history) { note in versionButton(note.version, current: note.version == identity.version) }
            }
          }
        }.padding(16).frame(width: 158).background(Color(nsColor: StudioTheme.panel))
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if let note = history.first(where: { $0.version == selection }) {
              VStack(alignment: .leading, spacing: 6) {
                Text(note.title).font(.system(size: 19, weight: .semibold))
                Text("\(note.version) · \(note.date)").foregroundStyle(.secondary)
              }
              ForEach(Array(note.changes.enumerated()), id: \.offset) { _, change in
                HStack(alignment: .top, spacing: 10) {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).padding(.top, 2)
                  Text(change).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
              }
            } else {
              Text("Bu sürümün değişiklik notları bulunamadı.").font(.headline)
              Text(loadError ?? "Tam sürüm geçmişini GitHub yayınlarından inceleyebilirsiniz.").foregroundStyle(.secondary)
            }
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("aboutReleaseNotes")
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      HStack {
        Link("GitHub Yayınları ↗", destination: repositoryURL).studioHelp("Tüm yayımlanmış sürümleri GitHub'da aç")
        Spacer()
        StudioActionButton("Güncellemeleri Kontrol Et", icon:"arrow.down.circle", tint:.accentColor, action: checkUpdates)
      }.padding(.horizontal, 24).padding(.vertical, 16)
      Text("Değişiklik notları uygulamayla birlikte gelir; çevrimdışı okunabilir.")
        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 16)
    }.studioPanel()
  }
  private func versionButton(_ version: String, current: Bool) -> some View {
    Button { selection = version } label: {
      VStack(alignment: .leading, spacing: 3) {
        Text(version).font(.system(size: 13, weight: .semibold, design: .monospaced))
        if current { Text("Kurulu sürüm").font(.system(size: 10)) }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .foregroundStyle(selection == version ? Color.accentColor : Color.primary)
        .background(selection == version ? Color.accentColor.opacity(0.10) : Color.clear,
          in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selection == version ? Color(nsColor: StudioTheme.accent).opacity(0.25) : .clear))
      .contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityAddTraits(selection == version ? .isSelected : []).accessibilityLabel("\(version)\(current ? " Kurulu sürüm" : "")")
      .accessibilityIdentifier("aboutRelease-\(version)")
  }
}
