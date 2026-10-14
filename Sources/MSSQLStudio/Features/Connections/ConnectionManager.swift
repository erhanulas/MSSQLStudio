import SQLServerKit
import SwiftUI

/// New and existing profiles share one form. Selection never reads the vault or
/// opens a connection; save/connect retain their existing StudioState owners.
struct ConnectionManager: View {
  let servers: [ConnectedServer]
  let connect: (ServerProfile, String, Bool) async throws -> Void
  let save: (ConnectedServer, ServerProfile, String, Bool) async throws -> Void
  let loadingChanged: (Bool) -> Void
  let cancel: () -> Void
  @State private var selected: UUID?
  @State private var pending: UUID?
  @State private var switching = false
  @State private var dirty = false
  @State private var busy = false
  init(servers: [ConnectedServer], initial: ConnectedServer?,
       connect: @escaping (ServerProfile, String, Bool) async throws -> Void,
       save: @escaping (ConnectedServer, ServerProfile, String, Bool) async throws -> Void,
       loadingChanged: @escaping (Bool) -> Void, cancel: @escaping () -> Void) {
    self.servers = servers; self.connect = connect; self.save = save
    self.loadingChanged = loadingChanged; self.cancel = cancel
    _selected = State(initialValue: initial?.id)
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Picker("Bağlantılar", selection: Binding(get: { selected }, set: choose)) {
          Text("Yeni bağlantı").tag(Optional<UUID>.none)
          ForEach(servers) { server in
            Text(server.profile.name + (server.online ? " · bağlı" : " · çevrimdışı")).tag(Optional(server.id))
          }
        }.accessibilityIdentifier("connectionManagerSelection")
        Spacer()
      }.padding(.horizontal, 22).padding(.top, 16).disabled(busy)
      let initial = servers.first { $0.id == selected }
      ConnectionForm(initial: initial, connect: connect,
        saveProfile: initial.map { server in { profile, password, remember in try await save(server, profile, password, remember) } },
        loadingChanged: { busy = $0; loadingChanged($0) }, cancel: cancel, draftChanged: { dirty = true })
        .id(selected)
    }.studioPanel()
      .alert("Kaydedilmemiş bağlantı değişiklikleri", isPresented: $switching) {
        Button("Vazgeç", role: .cancel) { }
        Button("Değişiklikleri Bırak", role: .destructive) { selected = pending; dirty = false }
      } message: { Text("Başka bir bağlantıya geçerseniz bu formdaki değişiklikler bırakılacak.") }
  }
  private func choose(_ id: UUID?) {
    guard !busy, id != selected else { return }
    if dirty { pending = id; switching = true }
    else { selected = id }
  }
}

@MainActor final class ConnectionPanelWindow: StudioPanelWindow {
  override func performClose(_ sender:Any?) {cancelAction?()}
}
