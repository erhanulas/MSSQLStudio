import AppKit
import SQLServerKit
import SwiftUI
import UniformTypeIdentifiers

private struct DatabaseChoices: View {
  let items: [CatalogItem]
  @Binding var chosen: Set<String>
  @Binding var defaultDatabase: String
  @Binding var profile: ServerProfile
  @State private var search = ""
  @State private var scope = DatabaseListScope.all
  @State private var selectedOnly = false
  @FocusState private var searchFocused: Bool
  private var filtered: [CatalogItem] {
    DatabaseSelection.filtered(
      items, search: search, scope: scope, selectedOnly: selectedOnly, chosen: chosen)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("\(chosen.count) seçili / \(items.count) veritabanı").fontWeight(.semibold)
        Spacer()
        Menu("Toplu seçim") {
          Button("Tüm veritabanlarını seç (\(items.count))") { chosen = Set(items.map(\.name)) }
          Button("Bütün seçimi temizle") { chosen = [] }
        }.fixedSize()
      }
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Veritabanı ara — ör. satış 2026", text: $search)
          .textFieldStyle(.roundedBorder).focused($searchFocused)
          .accessibilityIdentifier("databaseSearch")
          .onSubmit {
            if filtered.count == 1, let item = filtered.first { chosen.insert(item.name) }
          }
          .onExitCommand { search = "" }
        if !search.isEmpty {
          Button {
            search = ""
            searchFocused = true
          } label: {
            Image(systemName: "xmark.circle.fill").frame(width: 24, height: 24).contentShape(Rectangle())
          }
          .buttonStyle(.plain).help("Aramayı temizle").accessibilityLabel("Aramayı temizle")
        }
      }
      HStack {
        Picker("Veritabanı türü", selection: $scope) {
          Text("Tümü").tag(DatabaseListScope.all)
          Text("Kullanıcı").tag(DatabaseListScope.user)
          Text("Sistem").tag(DatabaseListScope.system)
        }.labelsHidden().pickerStyle(.segmented)
        Toggle("Yalnızca seçilenler", isOn: $selectedOnly).toggleStyle(.checkbox).fixedSize()
      }
      HStack(spacing: 10) {
        Text("\(filtered.count) eşleşme").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Görünenleri Seç") {
          chosen = DatabaseSelection.changingVisible(filtered, chosen: chosen, select: true)
        }.disabled(filtered.isEmpty)
        Button("Görünenleri Kaldır") {
          chosen = DatabaseSelection.changingVisible(filtered, chosen: chosen, select: false)
        }.disabled(!filtered.contains { chosen.contains($0.name) })
      }.controlSize(.small)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(filtered, id: \.name) { item in
            HStack(spacing: 8) {
              Toggle(
                isOn: Binding(
                  get: { chosen.contains(item.name) },
                  set: { value in
                    if value { chosen.insert(item.name) } else { chosen.remove(item.name) }
                  })
              ) {
                Text(item.name).lineLimit(1).truncationMode(.middle).help(item.name)
              }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
              Toggle("İçerik", isOn: Binding(get: { profile.indexesDefinitions(in: item.name) }, set: {
                profile.setDefinitionIndex($0, database: item.name, known: items.map(\.name))
              })).toggleStyle(.checkbox).disabled(!chosen.contains(item.name))
                .help("Nesne kodlarını bu Mac’te indeksle: " + item.name)
                .accessibilityLabel("Nesne içeriği indeksi: " + item.name)
              if (1...4).contains(item.id) {
                Text("Sistem").font(.caption).foregroundStyle(.secondary)
              }
              Button {
                chosen.insert(item.name)
                defaultDatabase = item.name
              } label: {
                Image(systemName: defaultDatabase == item.name ? "star.fill" : "star")
                  .foregroundStyle(defaultDatabase == item.name ? Color.orange : Color.secondary)
              }.buttonStyle(.borderless)
                .help("Yeni sorgular için varsayılan yap: \(item.name)")
                .accessibilityLabel("Varsayılan yap: \(item.name)")
            }.padding(.horizontal, 10).padding(.vertical, 7)
            Divider().padding(.leading, 30)
          }
        }.padding(.vertical, 4)
      }.background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15)))
        .overlay {
          if filtered.isEmpty {
            VStack(spacing: 6) {
              Image(systemName: "line.3.horizontal.decrease.circle").font(.title2)
              Text(selectedOnly && chosen.isEmpty ? "Henüz seçim yok" : "Eşleşen veritabanı yok")
              Text("Aramayı veya filtreleri değiştirin.").font(.caption)
              Button("Filtreleri Sıfırla") {
                search = ""
                scope = .all
                selectedOnly = false
              }
            }.foregroundStyle(.secondary)
          }
        }.frame(minHeight: 220, maxHeight: .infinity)
        .accessibilityIdentifier("databaseChoicesList")
      HStack(spacing: 6) {
        Image(systemName: "star.fill").foregroundStyle(.orange)
        Text(
          defaultDatabase.isEmpty
            ? "Varsayılan için bir satırdaki yıldıza basın." : "Yeni sorgular: \(defaultDatabase)"
        )
        .lineLimit(1).truncationMode(.middle).help(defaultDatabase)
        Spacer(minLength: 0)
      }.font(.caption)
      Text("Soldaki seçim Explorer görünümünü belirler. İçerik seçeneği nesne kodlarını bu Mac’te saklar; kapatınca o veritabanının tanım indeksi silinir. Sunucu izinleri değişmez.")
        .font(.caption).foregroundStyle(.secondary)
    }.onChange(of: chosen) { _, names in
      defaultDatabase = DatabaseSelection.defaultName(defaultDatabase, items: items, chosen: names)
    }.task { searchFocused = true }
  }
}

struct ConnectionForm: View {
  var connect: (ServerProfile, String, Bool) async throws -> Void
  var saveProfile:((ServerProfile,String,Bool) async throws->Void)?
  var loadingChanged:(Bool)->Void
  var cancel: () -> Void
  var draftChanged: () -> Void = {}
  @StateObject private var driver = DriverSetupModel()
  @State private var profile = ServerProfile(visibleDatabases: [])
  @State private var password = ""
  @State private var remember = false
  @State private var loading = false
  @State private var listed = false
  @State private var phase = ""
  @State private var status = ""
  @State private var error = ""
  @State private var items: [CatalogItem] = []
  @State private var chosen: Set<String> = []
  @State private var defaultDatabase = ""
  private let editing: Bool
  init(
    initial: ConnectedServer? = nil,
    connect: @escaping (ServerProfile, String, Bool) async throws -> Void,
    saveProfile:((ServerProfile,String,Bool) async throws->Void)?=nil,
    loadingChanged:@escaping (Bool)->Void={_ in},
    cancel: @escaping () -> Void,
    draftChanged: @escaping () -> Void = {}
  ) {
    self.connect = connect
    self.saveProfile=saveProfile
    self.loadingChanged=loadingChanged
    self.cancel = cancel
    self.draftChanged = draftChanged
    editing = initial != nil
    _profile = State(initialValue: initial?.profile ?? ServerProfile(visibleDatabases: []))
    _password = State(initialValue: initial?.password ?? "")
    _remember = State(initialValue: initial?.remembered ?? true)
    _items=State(initialValue:initial?.databases ?? [])
    _chosen=State(initialValue:Set(initial?.profile.visibleDatabases ?? initial?.databases.map(\.name) ?? []))
    _defaultDatabase=State(initialValue:initial?.profile.database ?? "")
    _listed=State(initialValue:initial?.databases.isEmpty == false)
  }
  private var appearance: Binding<ServerAppearance> {
    Binding(get: { profile.appearance ?? ServerAppearance() }, set: { profile.appearance = $0 })
  }
  @State private var connectionPage = "Genel"
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: editing ? "Bağlantı ayarları" : "Yeni bağlantı", icon: "server.rack", subtitle: editing ? "Bağlantı ve görünür veritabanlarını düzenle" : "Sunucuya bağlan, veritabanlarını seç")
      Divider()
      HStack(alignment: .top, spacing: 18) {
        VStack(alignment: .leading, spacing: 12) {
          Text("Sunucu bilgileri").font(.headline)
          Picker("Bağlantı seçenekleri",selection:$connectionPage) {Text("Genel").tag("Genel");Text("Gelişmiş").tag("Gelişmiş")}.pickerStyle(.segmented)
          ScrollView {
          VStack(alignment:.leading,spacing:14) {
          if connectionPage == "Genel" {
          Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
              Text("Görünen ad").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
              TextField("Bağlantı adı", text: $profile.name)
            }
            GridRow {
              Text("Sunucu / port").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
              HStack(spacing: 6) {
                TextField("Sunucu", text: $profile.host)
                TextField("Port", value: $profile.port, format: .number.grouping(.never)).frame(
                  width: 58)
              }
            }
            GridRow {
              Text("Kimlik").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
              Picker("Kimlik doğrulama", selection: $profile.kerberos) {
                Text("SQL Server Authentication").tag(false)
                Text("Windows / Kerberos").tag(true)
              }.labelsHidden()
            }
            if !profile.kerberos {
              GridRow {
                Text("Kullanıcı").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
                TextField("Login", text: $profile.login)
              }
              GridRow {
                Text("Parola").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
                SecureField("Password", text: $password)
              }
            }
            GridRow {
              Text("Test veritabanı").frame(width:150,alignment:.leading).foregroundStyle(.secondary)
              TextField("master", text: $profile.database)
                .help(
                  "Bağlantı testi ve listeleme için kullanılır. Yeni sorguların veritabanını sağdaki yıldızla seçin."
                )
            }
          }.textFieldStyle(.roundedBorder)
          DriverSetupView(model: driver)
          if profile.kerberos {
            Text("Geçerli Kerberos bileti ve sunucu SPN ayarı gerekir.").font(.caption)
              .foregroundStyle(.secondary)
          }
          Toggle("Bağlantıyı Keychain’de sakla", isOn: $remember).toggleStyle(.checkbox)
          } else {
          Text("Güvenlik").font(.headline)
          Label("Bağlantı şifrelemesi zorunlu",systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
          Toggle("Trust server certificate", isOn: $profile.trustCertificate).toggleStyle(.checkbox)
            .help("Şifreleme açık kalır; sunucu sertifikası doğrulanmaz.")
          if profile.trustCertificate {
            Text("Şifreleme açık; sertifika doğrulanmayacak.").font(.caption).foregroundStyle(
              .orange)
          }
          Divider()
          Text("Nesne tanım indeksi").font(.headline)
          Text("Sağdaki veritabanı listesindeki İçerik seçeneğiyle her veritabanını ayrı ayarlayın. Explorer’daki veritabanı indeks düğmesinden de değiştirilebilir. Nesne kodları bu Mac’te saklanır; kapatınca yalnız ilgili veritabanının tanım indeksi silinir.").font(.caption).foregroundStyle(.secondary)
          Divider()
          Text("Ortam ve renk").font(.headline)
          ConnectionAppearanceFields(appearance: appearance)
          }
          }.padding(2)
          }
                }.studioCard(padding: 16).frame(width: 420).disabled(loading)
        Divider()
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Object Explorer veritabanları").font(.headline)
            Spacer()
            StudioActionButton(listed ? "Test Et / Yenile" : "Test Et ve Yükle",icon:"arrow.clockwise",tint:.accentColor,action:test).disabled(loading || driver.busy)
          }
          if listed {
            DatabaseChoices(items: items, chosen: $chosen, defaultDatabase: $defaultDatabase, profile: $profile)
              .disabled(loading)
          } else {
            VStack(spacing: 12) {
              Image(systemName: "externaldrive.badge.magnifyingglass").font(.system(size: 32))
                .foregroundStyle(.secondary)
              Text("Görmek istediğin veritabanlarını seç").font(.headline)
              Text(
                "Bağlantı bilgilerini girip Test Et ve Yükle’ye basın. Ardından görünür veritabanlarını ve varsayılanı seçin."
              )
              .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)

            }.frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }.studioCard(padding: 16).frame(maxWidth: .infinity, maxHeight: .infinity)
      }.frame(maxHeight: .infinity)
      Divider()
      HStack {
        if loading {
          ProgressView().controlSize(.small)
          Text(phase).font(.caption)
        } else {
          if !error.isEmpty {Label(error,systemImage:"exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red).lineLimit(3).textSelection(.enabled)}
          else if !status.isEmpty {Label(status,systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.green)}
          else {Text("Bilgileri girip veritabanlarını yükleyin.").font(.caption).foregroundStyle(.secondary)}
        }
        Spacer()
        StudioActionButton("Vazgeç",icon:"xmark",action:cancel).disabled(loading || driver.busy)
        if editing,saveProfile != nil {
          StudioActionButton("Bağlan",icon:"bolt.horizontal",action:submit)
            .disabled(loading || driver.busy || !listed || chosen.isEmpty)
          StudioActionButton("Kaydet",icon:"checkmark",action:saveLocal).buttonStyle(StudioPrimaryButton()).disabled(loading || driver.busy).accessibilityIdentifier("saveConnectionProfile")
        } else if listed {
          StudioActionButton(editing ? "Uygula" : "Bağlan",icon:editing ? "checkmark":"bolt.horizontal",action:submit)
            .buttonStyle(StudioPrimaryButton()).disabled(loading || driver.busy || chosen.isEmpty)
        } else {
          StudioActionButton("Bağlan",icon:"bolt.horizontal",action:submit)
            .buttonStyle(StudioPrimaryButton()).disabled(true)
        }
      }
    }.padding(22).studioPanel().frame(width: 940, height: 620)
      .onChange(of: profile) { old, new in
        var previous = old
        previous.name = new.name
        previous.appearance = new.appearance
        previous.indexObjectDefinitions = new.indexObjectDefinitions
        previous.definitionIndexDatabases = new.definitionIndexDatabases
        draftChanged()
        if previous != new { invalidate() }
      }
      .onChange(of: password) { _, _ in draftChanged();invalidate() }
      .onChange(of: remember) { _, _ in draftChanged() }
      .onChange(of: chosen) { _, _ in draftChanged() }
      .onChange(of: defaultDatabase) { _, _ in draftChanged() }
      .onChange(of: driver.busy) { _, value in loadingChanged(loading || value) }
      .onChange(of: loading) {_,value in loadingChanged(value || driver.busy)}
  }
  private func saveLocal() {
    guard let saveProfile,!loading else {return}
    loading=true;phase="Kaydediliyor…";error=""
    var value=profile
    do {
      if listed,(chosen != Set(profile.visibleDatabases ?? items.map(\.name)) || defaultDatabase != profile.database) {
        try value.selectDatabases(chosen,available:items);value.database=defaultDatabase
      }
    } catch {self.error=error.localizedDescription;loading=false;return}
    let input=value,secret=password,remember=remember
    Task {@MainActor in
      defer {loading=false}
      do {try await saveProfile(input,secret,remember)} catch {self.error=error.localizedDescription}
    }
  }
  private func invalidate() {
    listed = false
    items = []
    chosen = []
    defaultDatabase = ""
    status = ""
    error = ""
  }
  private func test() {
    guard !loading, !driver.busy else { return }
    loading = true; phase = "Bağlantı test ediliyor ve veritabanları yükleniyor…"
    status = ""; error = ""
    Task { @MainActor in
      defer { loading = false }
      do {
        try await discover()
        status = "Bağlantı başarılı · \(items.count) veritabanı"
      } catch { self.error = error.localizedDescription }
    }
  }
  private func discover() async throws {
    phase = "Veritabanları yükleniyor…"
    let previous = listed ? chosen : Set(profile.visibleDatabases ?? [])
    let legacy = !listed && profile.visibleDatabases == nil
    let previousDefault = defaultDatabase.isEmpty ? profile.database : defaultDatabase
    let available = try await ServerDiscovery.databases(profile, password: password)
    items = available
    chosen = Set(items.map(\.name)).intersection(legacy ? Set(items.map(\.name)) : previous)
    defaultDatabase = DatabaseSelection.defaultName(previousDefault, items: items, chosen: chosen)
    listed = true
  }
  private func submit() {
    loading = true
    phase = "Bağlanıyor…"
    error = ""
    Task { @MainActor in
      defer { loading = false }
      do {
        var final = profile
        final.appearance = try profile.appearance?.validated()
        try final.selectDatabases(chosen, available: items)
        if chosen.contains(defaultDatabase) { final.database = defaultDatabase }
        try await connect(final, password, remember)
      } catch { self.error = error.localizedDescription }
    }
  }
}
