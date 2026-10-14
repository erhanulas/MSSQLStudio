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
  @State private var search=""
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
    HStack(spacing:0) {
      VStack(alignment:.leading,spacing:10) {
        Label("Bağlantılar",systemImage:"server.rack").font(.headline)
        TextField("Bağlantı ara…",text:$search).textFieldStyle(.roundedBorder)
        Button {choose(nil)} label: {Label("Yeni bağlantı",systemImage:"plus.circle").frame(maxWidth:.infinity,alignment:.leading).padding(8).contentShape(Rectangle())}.buttonStyle(.plain)
        Divider()
        ScrollView {
          LazyVStack(alignment:.leading,spacing:4) {
            ForEach(servers.filter {search.isEmpty || ($0.profile.name+" "+$0.profile.host).localizedCaseInsensitiveContains(search)}) {server in
              Button {choose(server.id)} label: {
                HStack(alignment:.top,spacing:6) {
                  Image(systemName:server.online ? "network":"network.slash").foregroundStyle(server.online ? .green:.secondary)
                  VStack(alignment:.leading,spacing:3) {Text(server.profile.name).lineLimit(1);Text(server.profile.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)}
                  Spacer(minLength:0)
                }.padding(8).frame(maxWidth:.infinity,alignment:.leading)
                  .background(selected==server.id ? Color(nsColor:StudioTheme.selection):.clear,in:RoundedRectangle(cornerRadius:6)).contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityIdentifier("connectionProfile_"+server.id.uuidString)
            }
          }
        }.accessibilityIdentifier("connectionManagerSelection")
      }.padding(12).frame(width:190).disabled(busy)
      Divider()
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
