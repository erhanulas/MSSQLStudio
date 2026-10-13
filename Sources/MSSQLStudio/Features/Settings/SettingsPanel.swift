import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor private final class ShortcutCaptureButton: NSButton {
  var shortcutAction = GridShortcuts.Action.headers
  var report: ((String) -> Void)?
  private var monitor: Any?
  var recording = false
  override var acceptsFirstResponder: Bool { true }
  override func mouseDown(with event: NSEvent) {
    stop(); recording = true; title = "Tuşlara basın… (Esc: iptal)"
    window?.makeFirstResponder(self)
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let handled = MainActor.assumeIsolated {
        guard let self, self.recording else { return false }
        if event.keyCode == 53 { self.stop(); return true }
        if let message = GridShortcuts.save(event,action: self.shortcutAction) { self.report?(message) }
        else { self.report?("Kısayol kaydedildi."); self.stop() }
        return true
      }
      return handled ? nil : event
    }
  }
  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil; recording = false
    title = GridShortcuts.binding(shortcutAction).label + " · Değiştir…"
  }
  override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { stop() } }
}
private struct ShortcutCapture: NSViewRepresentable {
  let action: GridShortcuts.Action
  var report: (String) -> Void
  func makeNSView(context: Context) -> ShortcutCaptureButton {
    let button = ShortcutCaptureButton(); button.bezelStyle = .rounded; button.shortcutAction = action; button.report = report; button.stop()
    button.setAccessibilityLabel(GridShortcuts.title(action)+" kısayolunu değiştir")
    button.toolTip = GridShortcuts.title(action)+" kısayolunu değiştir"
    return button
  }
  func updateNSView(_ button: ShortcutCaptureButton, context: Context) {
    button.report = report
    if !button.recording { button.title = GridShortcuts.binding(action).label + " · Değiştir…" }
  }
}
enum SettingsSection: String, CaseIterable {
  case appearance, editor, shortcuts, workspace, updates, security
  var title: String {
    switch self {
    case .appearance: "Görünüm"
    case .editor: "SQL Editörü"
    case .shortcuts: "Kısayollar"
    case .workspace: "Çalışma Alanı"
    case .updates: "Güncellemeler"
    case .security: "Güvenlik"
    }
  }
  var icon: String {
    switch self {
    case .appearance: "paintpalette"
    case .editor: "chevron.left.forwardslash.chevron.right"
    case .shortcuts: "command"
    case .workspace: "square.stack"
    case .updates: "arrow.down.circle"
    case .security: "lock.shield"
    }
  }
}

struct SettingsPanel: View {
  let state: StudioState
  @State private var theme = UserDefaults.standard.string(forKey: "ssmsTheme") ?? "light"
  @State private var completion = UserDefaults.standard.object(forKey:"sqlAutomaticCompletion") as? Bool ?? true
  @State private var completionDelay = Double(SQLEditorPreferences.completionDelay())
  @State private var completionSchema = SQLEditorPreferences.includeSchema()
  @State private var completionBrackets = SQLEditorPreferences.quoteIdentifiers()
  @State private var validation = UserDefaults.standard.object(forKey:"sqlValidateReferences") as? Bool ?? true
  @State private var aliases = UserDefaults.standard.object(forKey:"sqlAutomaticAliases") as? Bool ?? true
  @State private var noLock = UserDefaults.standard.bool(forKey:"sqlAutomaticNoLock")
  @State private var shortcutRevision = 0
  @State private var history = false
  @State private var historyDays = QueryHistoryPolicy.defaultDays
  @State private var recovery = false
  @State private var updateRepository = UserDefaults.standard.string(forKey:"githubUpdateRepository") ?? ""
  @State private var keychainMessage = ""
  @State private var renewingKeychain = false
  @State private var message = ""
  @State private var selectedTab: SettingsSection
  @State private var search=""
  @State private var searchTarget:SettingsSearchEntry?
  @FocusState private var searchFocused:Bool
  init(state: StudioState, initialTab: SettingsSection = .appearance) {
    self.state = state
    _selectedTab = State(initialValue: initialTab)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Image(systemName: "slider.horizontal.3").font(.system(size: 19, weight: .medium))
          .foregroundStyle(Color(nsColor: StudioTheme.accent))
          .frame(width: 40, height: 40)
          .background(Color(nsColor: StudioTheme.selection), in: RoundedRectangle(cornerRadius: 10))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text("Ayarlar").font(.system(size: 21, weight: .semibold))
          Text("MSSQL Studio’yu çalışma biçiminize göre düzenleyin.").font(.callout).foregroundStyle(.secondary)
        }
        Spacer()
      }
      HStack(spacing:8) {
        Image(systemName:"magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
        TextField("Tüm ayarlarda ara…",text:$search).textFieldStyle(.roundedBorder)
          .focused($searchFocused).accessibilityLabel("Tüm ayarlarda ara").accessibilityIdentifier("settingsSearch")
          .onSubmit {if let result=SettingsSearch.results(search).first {openSearchResult(result)}}
        if !search.isEmpty {
          Button {search=""} label: {Image(systemName:"xmark.circle.fill")}
            .buttonStyle(.plain).help("Aramayı temizle").accessibilityLabel("Aramayı temizle")
        }
      }
      TabView(selection: $selectedTab) {
        settingsPage(.appearance, subtitle: "Sakin yüzeyler, net ayrımlar ve tema uyumlu SQL renkleri.") {
          settingsCard("Renk teması", icon: "circle.lefthalf.filled") {
            StudioFormField("Çalışma ortamı") {
              Picker("Renk teması", selection: $theme) {
                Text("Sistem").tag("system")
                Text("Studio Açık").tag("light")
                Text("Studio Koyu").tag("dark")
              }.labelsHidden().pickerStyle(.segmented).accessibilityIdentifier("settingsTheme").id("theme")
            }
            if theme == "system" {
              HStack(spacing: 14) {
                Image(systemName: "desktopcomputer").font(.system(size: 29, weight: .light))
                  .foregroundStyle(Color(nsColor: StudioTheme.accent)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                  Text("macOS görünümünü izle").font(.callout.weight(.medium))
                  Text("Sistem açık veya koyu görünüme geçtiğinde arayüz ve SQL renkleri birlikte uyum sağlar.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 25))
                  .foregroundStyle(Color(nsColor: StudioTheme.muted)).accessibilityHidden(true)
              }.padding(16).frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                .background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: StudioTheme.border)))
                .accessibilityElement(children: .combine).accessibilityIdentifier("settingsSystemThemePreview")
            } else { SettingsThemePreview(dark: theme == "dark") }
            settingsNote("Tema, Uygula’ya bastığınızda tüm pencerelere uygulanır.", icon: "paintbrush.pointed")
          }
          settingsCard("Yazı ve okunabilirlik", icon: "textformat") {
            HStack(spacing: 24) {
              fontDetail("SQL editörü", value: "\(StudioTheme.codeFont.familyName ?? "Monospace") · 13 pt", icon: "curlybraces")
              fontDetail("Arayüz", value: "Sistem · 12 pt", icon: "textformat.size")
            }
            settingsNote("Açık ve koyu temalarda SSMS sözdizimi renk kategorileri korunur.", icon: "checkmark.circle")
          }
        }.tabItem { Label(SettingsSection.appearance.title, systemImage: SettingsSection.appearance.icon) }.tag(SettingsSection.appearance)
        settingsPage(.editor, subtitle: "Tamamlama, doğrulama ve yazım yardımcıları.") {
          settingsCard("Otomatik tamamlama", icon: "text.badge.plus") {
            settingsToggle("Yazarken önerileri göster", detail: "Aktif veritabanındaki nesne ve kolonları önerir; kolon adlarının içinde de arar.", value: $completion)
              .accessibilityIdentifier("settingsCompletion")
            Divider()
            StudioFormField("Öneri gecikmesi") {
              HStack(spacing: 10) {
                Slider(value: $completionDelay, in: 50...1000, step: 10).accessibilityLabel("Otomatik tamamlama gecikmesi")
                Text("\(Int(completionDelay)) ms").monospacedDigit().frame(width: 58, alignment: .trailing)
                StudioActionButton("Varsayılan", icon: "arrow.counterclockwise", tint: .accentColor) { completionDelay = Double(SQLEditorPreferences.defaultCompletionDelay) }.controlSize(.small)
              }
            }.id("delay")
            settingsNote("Kısa süre daha hızlı öneri gösterir. ⌃Space, beklemeden açar; Tab / Enter kabul eder, Escape kapatır.", icon: "keyboard")
            Divider()
            settingsToggle("Tamamlamada şema adını ekle", detail: "Kapalıyken SQL Server’ın varsayılan şema çözümü kullanılır. Aynı adlı nesnelerde ve gerekli fonksiyonlarda şema korunur.", value: $completionSchema)
              .accessibilityIdentifier("settingsCompletionSchema")
            Divider()
            settingsToggle("Tamamlamada köşeli parantez kullan", detail: "Kapalıyken sade adlar kullanılır; boşluk, ayrılmış sözcük ve özel karakter içeren adlar SQL’in geçerli kalması için korunur.", value: $completionBrackets)
              .accessibilityIdentifier("settingsCompletionBrackets")
          }
          settingsCard("Kod yardımcıları", icon: "checkmark.seal") {
            settingsNote("Tanımlanmamış @parametreler kırmızı görünür. DECLARE, prosedür/fonksiyon parametreleri ve GO batch sınırları dikkate alınır.",icon:"at")
            settingsNote("Seçili satırları yorum yap / kaldır: \(GridShortcuts.binding(.comment).label). Yalnız yorumu kaldır: \(GridShortcuts.binding(.uncomment).label). İşlemler seçim yanındaki düğmeden de açılır.",icon:"text.bubble")
            settingsToggle("Eksik tablo ve kolonları vurgula", detail: "Güncel, doğrulanmış veritabanı indeksiyle kırmızı işaretler.", value: $validation)
            Divider()
            settingsToggle("Otomatik alias ekle", detail: "FROM / JOIN içinde tablo veya view önerisi kabul edildiğinde eklenir.", value: $aliases)
            Divider()
            settingsToggle("Alias sonrasında WITH(NOLOCK) ekle", detail: "Varsayılan kapalıdır. Henüz commit edilmemiş verileri okuyabilir.", value: $noLock).disabled(!aliases)
          }
        }.tabItem { Label(SettingsSection.editor.title, systemImage: SettingsSection.editor.icon) }.tag(SettingsSection.editor)
        settingsPage(.shortcuts, subtitle: "Sık kullandığınız işlemlere tek bir tuş birleşimiyle ulaşın.") {
          settingsCard("Klavye kısayolları", icon: "keyboard") {
            ForEach(Array(GridShortcuts.Action.allCases.enumerated()), id: \.element.rawValue) { index, action in
              if index > 0 { Divider() }
              HStack(spacing: 12) {
                Text(GridShortcuts.title(action)).frame(maxWidth: .infinity, alignment: .leading)
                ShortcutCapture(action: action) { message = $0; shortcutRevision += 1 }.frame(width: 220, height: 28)
                StudioActionButton("Sıfırla", icon: "arrow.counterclockwise", tint: .accentColor) { GridShortcuts.reset(action); shortcutRevision += 1 }.controlSize(.small)
              }.id(shortcutRevision).id("shortcut."+action.rawValue)
            }
          }
          settingsNote("Değiştir’e basıp ⌘ veya ⌃ ile bir harf / rakam veya / kullanın. Çakışan ve ayrılmış kısayollar reddedilir; Escape iptal eder. Değişiklikler hemen kaydedilir.", icon: "bolt.circle")
          settingsNote("Editörde ⌘Z / ⌘⇧Z ve ⌃Z / ⌃Y / ⌃⇧Z geri al / ileri al için kullanılabilir.", icon: "arrow.uturn.backward")
          settingsNote("SQL editöründe ⌥← / ⌥→ değişken, kelime ve operatör sınırlarında ilerler. @ / @@ önekleri değişkenle birlikte kalır.", icon: "arrow.left.and.right")
          settingsNote("⌘← / ⌘→ önce kodun başına / sonuna, ikinci basışta girinti / sondaki boşluk sınırına gider. ⇧ ekleyerek aynı hareketlerle seçim yapabilirsiniz.", icon: "selection.pin.in.out")
        }.tabItem { Label(SettingsSection.shortcuts.title, systemImage: SettingsSection.shortcuts.icon) }.tag(SettingsSection.shortcuts)
        settingsPage(.workspace, subtitle: "Bu Mac’te tutulan sorgu geçmişini ve oturum kurtarmayı yönetin.") {
          settingsCard("Geçmiş ve kurtarma", icon: "clock.arrow.circlepath") {
            settingsToggle("Sorgu geçmişini sakla", detail: "Çalıştırılan sorgular Timeline üzerinden yeniden açılabilir.", value: $history)
            StudioFormField("Saklama süresi") {
              Stepper(value: $historyDays, in: 1...3650) { Text("\(historyDays) gün").monospacedDigit() }
            }.disabled(!history).id("retention")
            settingsNote("Varsayılan 30 gün. Süresi dolan kayıtlar açılışta, yeni sorguda ve Uygula ile temizlenir. Üst sınır 16 MB / 20.000 kayıttır.", icon: "calendar")
            Divider()
            settingsToggle("Sorgu sekmelerini kurtar", detail: "Açık sekmeleri sonraki uygulama açılışında geri getirir.", value: $recovery)
          }
          settingsCard("Yerel kayıtlar", icon: "internaldrive") {
            Text("Sorgu metinleri değerler içerebilir. Kayıtlar yalnızca bu Mac’te tutulur; bağlantı parolaları bu dosyalara yazılmaz.")
              .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
              settingsNote("Geçmiş ve kurtarma kayıtlarını temizler.", icon: "doc")
              Spacer(minLength: 8)
              StudioActionButton("Yerel Kayıtları Sil", icon: "trash", tint: Color(nsColor: StudioTheme.danger), action: removeLocalRecords).id("removeRecords")
            }
          }
        }.tabItem { Label(SettingsSection.workspace.title, systemImage: SettingsSection.workspace.icon) }.tag(SettingsSection.workspace)
        settingsPage(.updates, subtitle: "Uygulamanın yeni sürümler için kontrol edeceği yayın kaynağı.") {
          settingsCard("GitHub yayınları", icon: "shippingbox") {
            StudioFormField("Yayın deposu") {
              TextField("kullanıcı/depo veya GitHub depo adresi", text: $updateRepository)
                .accessibilityIdentifier("githubUpdateRepository").id("repository")
            }
            settingsNote("Boş bırakırsanız MSSQL Studio’nun varsayılan yayın adresi kullanılır.", icon: "link")
          }
          settingsCard("Güncelleme kontrolü", icon: "arrow.down.circle") {
            Label("MSSQL Studio → Güncellemeleri Kontrol Et", systemImage: "menubar.arrow.up.rectangle").font(.callout.weight(.medium))
            Text("Depoyu değiştirdiyseniz önce Uygula’ya basın. Güncelleme kontrolü ve kurulum adımları uygulama menüsünden açılır.")
              .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            settingsNote("Herkese açık Releases kullanılır. Bağlantı parolaları ve sorgular GitHub’a gönderilmez.", icon: "lock.shield")
          }
        }.tabItem { Label(SettingsSection.updates.title, systemImage: SettingsSection.updates.icon) }.tag(SettingsSection.updates)
        settingsPage(.security, subtitle: "Bağlantı parolalarınız macOS Anahtar Zinciri’nde korunur.") {
          settingsCard("Parola erişimi", icon: "lock.shield", tint: Color(nsColor: StudioTheme.success)) {
            Text("Parolalara sürümler arasında aynı kalan imzalı MSSQL Studio parola bileşeni erişir.")
              .font(.callout).fixedSize(horizontal: false, vertical: true)
            settingsNote("Eski kayıtların ilk geçişinde macOS onay isterse Her Zaman İzin Ver’i seçin. Anahtar zinciri kilitliyse macOS ayrıca parola isteyebilir.", icon: "key")
          }
          settingsCard("Erişim sorunlarını gider", icon: "key.horizontal") {
            Text("Parola erişimi sorunu sürerse uygulama izinlerini yenileyebilirsiniz. Kayıtlı bağlantılarınız silinmez.")
              .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
              if renewingKeychain { ProgressView().controlSize(.small) }
              StudioActionButton(renewingKeychain ? "İzinler yenileniyor…" : "Keychain izinlerini yenile", icon: "arrow.triangle.2.circlepath", tint: .accentColor, action: renewKeychainAccess)
                .disabled(renewingKeychain).accessibilityIdentifier("renewKeychainAccess").id("renew")
              Spacer()
            }
            if !keychainMessage.isEmpty { Text(keychainMessage).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
          }
        }.tabItem { Label(SettingsSection.security.title, systemImage: SettingsSection.security.icon) }.tag(SettingsSection.security)
      }.accessibilityIdentifier("settingsTabs")
        .allowsHitTesting(search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        .opacity(search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? 1:0)
        .accessibilityHidden(!search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        .overlay {
          if !search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {searchResults}
        }
      HStack(spacing: 12) {
        Image(systemName: message == "Ayarlar kaydedildi." ? "checkmark.circle.fill" : "info.circle")
          .foregroundStyle(Color(nsColor: message == "Ayarlar kaydedildi." ? StudioTheme.success : StudioTheme.muted))
          .accessibilityHidden(true)
        Text(message.isEmpty ? (selectedTab == .shortcuts ? "Kısayol değişiklikleri hemen kaydedilir." : "Tercihlerinizi kaydetmek için Uygula’ya basın.") : message)
          .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true).lineLimit(3)
          .accessibilityIdentifier("settingsMessage")
        Spacer(minLength: 12)
        StudioActionButton("Uygula", icon: "checkmark", action: applySettings).buttonStyle(StudioPrimaryButton())
          .accessibilityIdentifier("settingsApply")
      }.padding(14)
        .background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: StudioTheme.border)))
    }.padding(18).studioPanel().onAppear {
      history = state.historyEnabled
      historyDays = state.historyRetentionDays
      recovery = state.recoveryEnabled
    }
  }
  private func settingsPage<Content: View>(_ section: SettingsSection, subtitle: String, @ViewBuilder content: @escaping () -> Content) -> some View {
    ScrollViewReader {proxy in
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(section.title).font(.system(size: 17, weight: .semibold))
          Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        content()
      }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
    }.background(Color(nsColor: StudioTheme.panel))
      .onChange(of:searchTarget) {_,target in if let target,target.section == section {proxy.scrollTo(target.scrollID,anchor:.center)}}
      .onChange(of:selectedTab) {_,selected in if selected == section,let target=searchTarget,target.section == section {proxy.scrollTo(target.scrollID,anchor:.center)}}
      .onAppear {if let target=searchTarget,target.section == section {proxy.scrollTo(target.scrollID,anchor:.center)}}
    }
  }
  private var searchResults:some View {
    let results=SettingsSearch.results(search)
    return VStack(alignment:.leading,spacing:12) {
      Text("\(results.count) ayar bulundu").font(.callout).foregroundStyle(.secondary)
        .accessibilityIdentifier("settingsSearchCount")
      if results.isEmpty {
        StudioEmptyState(title:"Eşleşen ayar yok",icon:"magnifyingglass",detail:"Tema, tamamlama, geçmiş, yorum veya parola gibi bir sözcük deneyin.")
        Spacer()
      } else {
        ScrollView {
          LazyVStack(spacing:8) {
            ForEach(results) {result in
              Button {openSearchResult(result)} label: {
                HStack(spacing:12) {
                  Image(systemName:result.section.icon).foregroundStyle(Color(nsColor:StudioTheme.accent)).frame(width:24)
                  VStack(alignment:.leading,spacing:4) {
                    Text(result.title).foregroundStyle(Color(nsColor:StudioTheme.text))
                    Text(result.section.title+" › "+result.card).font(.caption).foregroundStyle(.secondary)
                  }
                  Spacer(minLength:8)
                  Image(systemName:"chevron.right").foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                  .background(Color(nsColor:StudioTheme.canvas),in:RoundedRectangle(cornerRadius:8)).contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityIdentifier("settingsSearchResult_"+result.id)
            }
          }
        }
      }
    }.padding(18).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
      .background(Color(nsColor:StudioTheme.panel)).accessibilityIdentifier("settingsSearchResults")
  }
  private func openSearchResult(_ result:SettingsSearchEntry) {
    searchFocused=false;selectedTab=result.section;searchTarget=result;search=""
  }
  private func settingsCard<Content: View>(_ title: String, icon: String, tint: Color = Color(nsColor: StudioTheme.accent), @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label { Text(title).font(.system(size: 12, weight: .semibold)) } icon: {
        Image(systemName: icon).foregroundStyle(tint).frame(width: 18)
      }
      content()
    }.frame(maxWidth: .infinity, alignment: .leading).studioCard().id(title)
      .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(searchTarget?.card == title ? Color(nsColor:StudioTheme.accent):.clear,lineWidth:2))
  }
  private func settingsToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
    Toggle(isOn: value) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
        Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.toggleStyle(.switch).controlSize(.small).frame(maxWidth: .infinity).accessibilityLabel(title)
      .id(SettingsSearch.entries.first {$0.title==title}?.id ?? title)
  }
  private func settingsNote(_ text: String, icon: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: icon).frame(width: 16).accessibilityHidden(true)
      Text(text).fixedSize(horizontal: false, vertical: true)
    }.font(.caption).foregroundStyle(.secondary)
  }
  private func fontDetail(_ title: String, value: String, icon: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: icon).foregroundStyle(Color(nsColor: StudioTheme.accent)).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.callout.weight(.medium))
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private func removeLocalRecords() {
    do {
      for name in ["history.json", "tabs.json"] {
        let url = state.folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
          try FileManager.default.removeItem(at: url)
        }
      }
      state.history = []
      NotificationCenter.default.post(name: .init("queryHistoryChanged"), object: state)
      message = "Yerel kayıtlar silindi."
    } catch { message = error.localizedDescription }
  }
  private func renewKeychainAccess() {
    renewingKeychain = true; keychainMessage = ""
    Task {
      defer { renewingKeychain = false }
      do {
        let count = try await Task.detached { try ServerVault().renewApplicationAccess() }.value
        keychainMessage = count == 0 ? "Kayıtlı bağlantı bulunamadı." : "\(count) bağlantının parola bileşeni erişimi yenilendi. macOS ilk erişimde veya kilitli anahtar zincirinde ayrıca onay isteyebilir."
      } catch { keychainMessage = "İzinler tamamen yenilenemedi: " + error.localizedDescription }
    }
  }
  private func applySettings() {
          let source=updateRepository.trimmingCharacters(in:.whitespacesAndNewlines)
          if !source.isEmpty {
            do {updateRepository=try GitHubUpdateSource.repository(source)}catch {message=error.localizedDescription;return}
          }
          if source.isEmpty {UserDefaults.standard.removeObject(forKey:"githubUpdateRepository")}
          else {UserDefaults.standard.set(updateRepository,forKey:"githubUpdateRepository")}
          StudioTheme.apply(theme)
          UserDefaults.standard.set(completion,forKey:"sqlAutomaticCompletion")
          UserDefaults.standard.set(Int(completionDelay),forKey:SQLEditorPreferences.completionDelayKey)
          UserDefaults.standard.set(completionSchema,forKey:SQLEditorPreferences.completionSchemaKey)
          UserDefaults.standard.set(completionBrackets,forKey:SQLEditorPreferences.completionBracketsKey)
          UserDefaults.standard.set(validation,forKey:"sqlValidateReferences")
          UserDefaults.standard.set(aliases,forKey:"sqlAutomaticAliases")
          UserDefaults.standard.set(noLock,forKey:"sqlAutomaticNoLock")
          NotificationCenter.default.post(name:Notification.Name("sqlEditorPreferencesChanged"),object:nil)
          state.historyEnabled = history
          state.historyRetentionDays = historyDays
          UserDefaults.standard.set(historyDays, forKey: "historyRetentionDays")
          state.saveHistory()
          state.recoveryEnabled = recovery
          UserDefaults.standard.set(history, forKey: "historyEnabled")
          UserDefaults.standard.set(recovery, forKey: "recoveryEnabled")
          state.scheduleSnapshot()
          message = "Ayarlar kaydedildi."
  }
}

/// A local preview responds to an unsaved theme choice without changing the application appearance.
private struct SettingsThemePreview: View {
  let dark: Bool
  private var canvas: Color { Color(nsColor: dark ? NSColor(srgbRed: 30/255, green: 30/255, blue: 30/255, alpha: 1) : .white) }
  private var panel: Color { Color(nsColor: dark ? NSColor(srgbRed: 34/255, green: 40/255, blue: 51/255, alpha: 1) : NSColor(srgbRed: 244/255, green: 246/255, blue: 250/255, alpha: 1)) }
  private var ink: Color { dark ? Color(white: 0.84) : .black }
  private var keyword: Color { Color(nsColor: dark ? NSColor(srgbRed: 108/255, green: 160/255, blue: 1, alpha: 1) : NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)) }
  private var literal: Color { Color(nsColor: NSColor(srgbRed: 1, green: dark ? 128/255 : 0, blue: dark ? 128/255 : 0, alpha: 1)) }
  private var comment: Color { Color(nsColor: dark ? NSColor(srgbRed: 106/255, green: 153/255, blue: 85/255, alpha: 1) : NSColor(srgbRed: 0, green: 128/255, blue: 0, alpha: 1)) }
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 9) {
        Label("Explorer", systemImage: "sidebar.left").font(.system(size: 10, weight: .semibold))
        Label("Veritabanları", systemImage: "externaldrive").font(.system(size: 10))
        Label("Tablolar", systemImage: "tablecells").font(.system(size: 10)).padding(.leading, 10)
        Spacer(minLength: 0)
      }.foregroundStyle(dark ? Color(white: 0.78) : Color(white: 0.35)).padding(12).frame(width: 150).background(panel)
      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Label("Sorgu", systemImage: "doc.text").font(.system(size: 10, weight: .semibold))
          Spacer()
          Text("SQL").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }.foregroundStyle(ink)
        Text("\(Text("SELECT ").foregroundColor(keyword))\(Text("N'MSSQL Studio'").foregroundColor(literal))\(Text(";").foregroundColor(ink))")
          .font(.system(size: 11, design: .monospaced)).lineLimit(1)
        Text("-- SSMS renkleri, her iki temada da").font(.system(size: 10, design: .monospaced))
          .foregroundStyle(comment)
      }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(canvas)
    }.frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: StudioTheme.border)))
      .accessibilityElement(children: .ignore).accessibilityLabel(dark ? "Studio Koyu tema önizlemesi" : "Studio Açık tema önizlemesi")
  }
}

