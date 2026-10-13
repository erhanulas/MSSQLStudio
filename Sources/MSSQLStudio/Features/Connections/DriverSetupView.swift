import AppKit
import SQLServerKit
import SwiftUI

@MainActor final class DriverSetupModel: ObservableObject {
  @Published private(set) var status: ODBCDriverSetup.Status?
  @Published private(set) var busy = false
  @Published private(set) var phase = "Sürücü kontrol ediliyor…"
  @Published private(set) var log = ""
  @Published private(set) var error = ""
  var inspect: () async -> ODBCDriverSetup.Status = { await ODBCDriverSetup.inspect() }
  var execute: (String, [String], Bool, @escaping @Sendable (String) -> Void) async throws -> String = {
    try await ODBCDriverSetup.run($0, arguments: $1, acceptLicense: $2, output: $3)
  }
  func refresh() async {
    guard !busy else { return }
    busy = true; phase = "Sürücü kontrol ediliyor…"
    status = await inspect(); busy = false
  }
  func install(approved: Bool) async {
    guard approved, !busy, let brew = status?.brew, status?.available == false else { return }
    busy = true; log = ""; error = ""
    defer { busy = false }
    do {
      let version = try await execute(brew, ["--version"], false, { _ in })
      let major = Int(version.split(whereSeparator: { !$0.isNumber }).first ?? "0") ?? 0
      for command in ODBCDriverSetup.installationCommands(homebrewMajor: major) {
        phase = command.phase
        _ = try await execute(brew, command.arguments, true) { [weak self] text in
          Task { @MainActor in self?.append(text) }
        }
      }
      phase = "Kurulum doğrulanıyor…"; status = await inspect()
      if status?.available != true { throw SQLFailure("Kurulum tamamlandı ancak sürücü yüklenemiyor. Sürücü kaydını ve bağımlılıklarını kontrol edin.") }
      phase = "Sürücü kurulumu tamamlandı."
    } catch { self.error = error.localizedDescription; status = await inspect() }
  }
  private func append(_ text: String) { log = String((log + text).suffix(16000)) }
}

struct DriverSetupView: View {
  @ObservedObject var model: DriverSetupModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var confirmation = false
  @State private var showDetails = false
  var body: some View {
    let _ = colorScheme
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Microsoft ODBC Driver \(model.status?.version ?? "18")", systemImage: "shippingbox")
          .font(.callout.weight(.semibold))
        Spacer()
        if model.busy { ProgressView().controlSize(.small) }
        else {
          if model.status?.available == false, model.status?.brew != nil {
            Button("Kur…") { confirmation = true }.accessibilityIdentifier("installODBCDriver")
          }
          Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
            .help("Sürücüyü yeniden kontrol et").accessibilityLabel("Sürücüyü yeniden kontrol et")
        }
      }
      Text(model.busy ? model.phase : model.status?.detail ?? model.phase)
        .font(.caption).foregroundStyle(.secondary)
      if model.status?.available == false, model.status?.brew == nil {
        Link("Homebrew kurulumunu aç", destination: URL(string: "https://brew.sh")!)
        Text("Homebrew sistem kurulumu resmî yönergelerle, kendi onayınızla yapılır. Ardından sürücüyü yeniden kontrol edin.")
          .font(.caption).foregroundStyle(.secondary)
      }
      if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(.red).textSelection(.enabled).lineLimit(4) }
      if !model.log.isEmpty {
        DisclosureGroup("Kurulum çıktısı", isExpanded: $showDetails) {
          ScrollView { Text(model.log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 90)
        }.font(.caption)
      }
      Link("Microsoft kurulum yönergeleri", destination: URL(string: "https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/install-microsoft-odbc-driver-sql-server-macos")!).font(.caption)
    }.padding(12).background(Color(nsColor: StudioTheme.panel), in: RoundedRectangle(cornerRadius: 8))
      .task { await model.refresh() }
      .alert("ODBC Driver 18 kurulsun mu?", isPresented: $confirmation) {
        Button("Vazgeç", role: .cancel) { }
        Button("Lisansı Kabul Et ve Kur") { Task { await model.install(approved: true) } }
      } message: {
        Text("Homebrew, resmî Microsoft kaynağını ekleyip gerekiyorsa bu kaynağa güven izni verecek ve msodbcsql18 ile bağımlılıklarını kuracak. Microsoft lisansını kabul etmiş olursunuz. Yönetici yetkisi otomatik istenmez; gerekirse işlem hata gösterir.")
      }
  }
}
