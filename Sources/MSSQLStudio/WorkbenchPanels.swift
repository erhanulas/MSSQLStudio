import AppKit
import CoreText
import SQLServerKit
import SwiftUI

extension WorkbenchController {
  func showSettingsWindow() {
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "studio.settings" && $0.isVisible }) {
      window.makeKeyAndOrderFront(nil); return
    }
    let window = present(SettingsPanel(state: state), title: "MSSQL Studio Ayarları", width: 920, height: 700, minWidth: 780, minHeight: 600, identity: "studio.settings")
    window.minSize = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 780, height: 600)).size
  }
  func showHistoryWindow() {
    state.loadHistory()
    present(
      HistoryPanel(
        state: state,
        open: { [weak self] record in
          guard let self, let server = state.historyServer(record) else { return }
          state.newQuery(
            server: server, database: record.database, text: record.text,
            title: "Timeline · \(record.time.formatted())")
        }), title: "Timeline — Sorgu Geçmişi", width: 1120, height: 760, minWidth: 1000, minHeight: 650, identity: "studio.timeline")
  }
  func showAIWindow() {
    present(
      AssistantPanel(
        sql: state.active?.sql ?? "",
        open: { [weak self] sql in
          guard let self, let server = selectedServer else { return }
          state.newQuery(server: server, database: selectedDatabase, text: sql, title: "AI Önerisi")
        }), title: "SQL Assistant", width: 820, height: 720)
  }
  func showExtensionsWindow() {
    present(
      TemplatesPanel(open: { [weak self] template in
        guard let self, let server = selectedServer else { return }
        state.newQuery(
          server: server, database: selectedDatabase, text: template.sql, title: template.name)
      }), title: "SQL Şablon Eklentileri", width: 740, height: 580)
  }
  func showIndexWindow(node: TreeNode?) {
    guard let node, let item = node.item else { return }
    present(
      IndexPanel(
        table: item.qualified,
        load: {
          Catalog.rows(
            try await node.server.catalog(
              Catalog.children(.columns, object: item.id), database: node.database))
        },
        open: { [weak self] sql in
          self?.state.newQuery(
            server: node.server, database: node.database, text: sql,
            title: "Create Index · \(item.name)")
        }), title: "Index Designer — \(item.qualified)", width: 760, height: 620)
  }
  func showJobWindow(node: TreeNode?) {
    guard let node else { return }
    present(
      JobPanel(
        databases: node.server.databases.map(\.name),
        open: { [weak self] sql in
          self?.state.newQuery(
            server: node.server, database: "msdb", text: sql, title: "New SQL Agent Job")
        }), title: "SQL Server Agent — New Job", width: 760, height: 620)
  }
}
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
      TabView(selection: $selectedTab) {
        settingsPage(.appearance, subtitle: "Sakin yüzeyler, net ayrımlar ve tema uyumlu SQL renkleri.") {
          settingsCard("Renk teması", icon: "circle.lefthalf.filled") {
            StudioFormField("Çalışma ortamı") {
              Picker("Renk teması", selection: $theme) {
                Text("Studio Açık").tag("light")
                Text("Studio Koyu").tag("dark")
              }.labelsHidden().pickerStyle(.segmented).accessibilityIdentifier("settingsTheme")
            }
            SettingsThemePreview(dark: theme == "dark")
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
            settingsToggle("Yazarken önerileri göster", detail: "Aktif veritabanının DDL indeksindeki nesne ve kolonları önerir.", value: $completion)
              .accessibilityIdentifier("settingsCompletion")
            Divider()
            StudioFormField("Öneri gecikmesi") {
              HStack(spacing: 10) {
                Slider(value: $completionDelay, in: 50...1000, step: 10).accessibilityLabel("Otomatik tamamlama gecikmesi")
                Text("\(Int(completionDelay)) ms").monospacedDigit().frame(width: 58, alignment: .trailing)
                StudioActionButton("Varsayılan", icon: "arrow.counterclockwise", tint: .accentColor) { completionDelay = Double(SQLEditorPreferences.defaultCompletionDelay) }.controlSize(.small)
              }
            }
            settingsNote("Kısa süre daha hızlı öneri gösterir. ⌃Space, beklemeden açar; Tab / Enter kabul eder, Escape kapatır.", icon: "keyboard")
          }
          settingsCard("Kod yardımcıları", icon: "checkmark.seal") {
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
              }.id(shortcutRevision)
            }
          }
          settingsNote("Değiştir’e basıp ⌘ veya ⌃ ile bir harf / rakam kullanın. Çakışan ve ayrılmış kısayollar reddedilir; Escape iptal eder. Değişiklikler hemen kaydedilir.", icon: "bolt.circle")
          settingsNote("Editörde ⌘Z / ⌘⇧Z ve ⌃Z / ⌃Y / ⌃⇧Z geri al / ileri al için kullanılabilir.", icon: "arrow.uturn.backward")
          settingsNote("SQL editöründe ⌥← / ⌥→ değişken, kelime ve operatör sınırlarında ilerler. @ / @@ önekleri değişkenle birlikte kalır.", icon: "arrow.left.and.right")
          settingsNote("⌘← / ⌘→ önce kodun başına / sonuna, ikinci basışta girinti / sondaki boşluk sınırına gider. ⇧ ekleyerek aynı hareketlerle seçim yapabilirsiniz.", icon: "selection.pin.in.out")
        }.tabItem { Label(SettingsSection.shortcuts.title, systemImage: SettingsSection.shortcuts.icon) }.tag(SettingsSection.shortcuts)
        settingsPage(.workspace, subtitle: "Bu Mac’te tutulan sorgu geçmişini ve oturum kurtarmayı yönetin.") {
          settingsCard("Geçmiş ve kurtarma", icon: "clock.arrow.circlepath") {
            settingsToggle("Sorgu geçmişini sakla", detail: "Çalıştırılan sorgular Timeline üzerinden yeniden açılabilir.", value: $history)
            StudioFormField("Saklama süresi") {
              Stepper(value: $historyDays, in: 1...3650) { Text("\(historyDays) gün").monospacedDigit() }
            }.disabled(!history)
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
              StudioActionButton("Yerel Kayıtları Sil", icon: "trash", tint: Color(nsColor: StudioTheme.danger), action: removeLocalRecords)
            }
          }
        }.tabItem { Label(SettingsSection.workspace.title, systemImage: SettingsSection.workspace.icon) }.tag(SettingsSection.workspace)
        settingsPage(.updates, subtitle: "Uygulamanın yeni sürümler için kontrol edeceği yayın kaynağı.") {
          settingsCard("GitHub yayınları", icon: "shippingbox") {
            StudioFormField("Yayın deposu") {
              TextField("kullanıcı/depo veya GitHub depo adresi", text: $updateRepository)
                .accessibilityIdentifier("githubUpdateRepository")
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
                .disabled(renewingKeychain).accessibilityIdentifier("renewKeychainAccess")
              Spacer()
            }
            if !keychainMessage.isEmpty { Text(keychainMessage).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
          }
        }.tabItem { Label(SettingsSection.security.title, systemImage: SettingsSection.security.icon) }.tag(SettingsSection.security)
      }.accessibilityIdentifier("settingsTabs")
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
  private func settingsPage<Content: View>(_ section: SettingsSection, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(section.title).font(.system(size: 17, weight: .semibold))
          Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        content()
      }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
    }.background(Color(nsColor: StudioTheme.panel))
  }
  private func settingsCard<Content: View>(_ title: String, icon: String, tint: Color = Color(nsColor: StudioTheme.accent), @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label { Text(title).font(.system(size: 12, weight: .semibold)) } icon: {
        Image(systemName: icon).foregroundStyle(tint).frame(width: 18)
      }
      content()
    }.frame(maxWidth: .infinity, alignment: .leading).studioCard()
  }
  private func settingsToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
    Toggle(isOn: value) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
        Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.toggleStyle(.switch).controlSize(.small).frame(maxWidth: .infinity).accessibilityLabel(title)
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

struct HistoryPanel: View {
  let state: StudioState
  var open: (QueryRecord) -> Void
  @State private var records: [QueryRecord] = []
  @State private var search = ""
  @State private var selected: UUID?
  @State private var server = ""
  @State private var database = ""
  @State private var status = ""
  @State private var period = 0
  @State private var slowest = false
  var filtered: [QueryRecord] {
    records.filter {
      (search.isEmpty || ($0.text + $0.database + $0.server).localizedCaseInsensitiveContains(search)) &&
      (server.isEmpty || $0.server == server) && (database.isEmpty || $0.database == database) &&
      (status.isEmpty || $0.status == status) && (period == 0 || $0.time >= Date().addingTimeInterval(-Double(period)*86400))
    }.sorted { slowest ? $0.seconds > $1.seconds : $0.time > $1.time }
  }
  var record: QueryRecord? { filtered.first { $0.id == selected } }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: "Timeline", icon: "clock.arrow.circlepath", subtitle: "Sorgularını bul, sürelerini karşılaştır ve yeniden aç")
      HStack {
        Label("\(records.count) sorgu", systemImage: "text.badge.checkmark")
        Spacer()
        Text("Saklama: \(state.historyRetentionDays) gün").foregroundStyle(.secondary)
      }.font(.callout)
      if !state.historyEnabled { Text("Geçmiş kaydı kapalı. Ayarlar → Çalışma Alanı'ndan açabilirsiniz.").foregroundStyle(.secondary) }
      TextField("SQL, sunucu veya veritabanında ara", text: $search)
      HStack {
        Picker("Sunucu", selection: $server) { Text("Tümü").tag(""); ForEach(Array(Set(records.map(\.server))).sorted(), id: \.self) { Text($0).tag($0) } }
        Picker("Veritabanı", selection: $database) { Text("Tümü").tag(""); ForEach(Array(Set(records.map(\.database))).sorted(), id: \.self) { Text($0).tag($0) } }
        Picker("Durum", selection: $status) { Text("Tümü").tag(""); ForEach(["Başarılı", "Hata", "Kısmi"], id: \.self) { Text($0).tag($0) } }
        Picker("Tarih", selection: $period) { Text("Tümü").tag(0); Text("24 saat").tag(1); Text("7 gün").tag(7); Text("30 gün").tag(30) }
        Toggle("En yavaş önce", isOn: $slowest)
      }.controlSize(.small)
      Text("\(filtered.count) eşleşme · Toplam \(String(format: "%.2f", filtered.reduce(0) { $0 + $1.seconds })) sn").font(.caption).foregroundStyle(.secondary)
      Table(filtered, selection: $selected) {
        TableColumn("Zaman") { Text($0.time.formatted(date: .abbreviated, time: .standard)) }.width(min: 150, ideal: 175)
        TableColumn("Sunucu", value: \.server)
        TableColumn("Veritabanı", value: \.database)
        TableColumn("Sorgu") { Text($0.text.replacingOccurrences(of: "\n", with: " ")).lineLimit(1) }.width(min: 180, ideal: 300)
        TableColumn("Durum") { Label($0.status, systemImage: $0.status == "Hata" ? "xmark.circle" : $0.status == "Kısmi" ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle($0.status == "Hata" ? Color.red : Color.secondary) }
        TableColumn("Süre") { Text(String(format: "%.3f sn", $0.seconds)).monospacedDigit() }.width(85)
      }.frame(minHeight: 180)
      if let record {
        HStack {
          Text(record.server + " / " + record.database).font(.headline)
          Spacer()
          StudioActionButton("Kopyala", icon: "doc.on.doc", tint: .accentColor) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.text, forType: .string) }
          StudioActionButton("Yeni Sekmede Aç", icon: "plus.square", tint: .accentColor) { open(record) }
            .disabled(state.historyServer(record) == nil)
        }
        if let message = record.errorMessage { Text(message).foregroundStyle(.red).font(.caption).lineLimit(3).textSelection(.enabled) }
        if let count = record.rowCount { Text("\(count) yüklenen satır").font(.caption).foregroundStyle(.secondary) }
        SQLReadOnlyPreview(sql: record.text).frame(minHeight: 150, idealHeight: 240)
        if state.historyServer(record) == nil { Text("Bu sunucuyu Explorer'a ekleyerek sorguyu kendi bağlantısında açabilirsiniz.").font(.caption).foregroundStyle(.secondary) }
      } else {
        StudioEmptyState(title: filtered.isEmpty ? "Eşleşen sorgu yok" : "Sorguyu seçin", icon: "clock", detail: "SQL önizlemesi ve yeniden açma işlemleri burada görünür.").frame(height: 170)
      }
    }.padding(20).studioPanel()
      .onAppear { records = state.history; selected = records.first?.id }
      .onReceive(NotificationCenter.default.publisher(for: .init("queryHistoryChanged"))) { _ in records = state.history }
  }
}

@MainActor private final class SQLPreviewRuler: NSRulerView {
  var lines = 1
  override func drawHashMarksAndLabels(in rect: NSRect) {
    StudioTheme.editorCanvas.setFill(); bounds.fill()
    guard let clip=scrollView?.contentView else { return }
    let top=clip.bounds.minY
    let first=max(0,Int((top-10)/20)), last=min(lines-1,Int((top+clip.bounds.height)/20)+1)
    guard first <= last else { return }
    for line in first...last {
      let label=String(line+1) as NSString
      let attributes:[NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.regular),.foregroundColor:StudioTheme.lineNumber]
      let width=label.size(withAttributes:attributes).width
      label.draw(at:NSPoint(x:ruleThickness-width-10,y:10+CGFloat(line)*20-top+3),withAttributes:attributes)
    }
    StudioTheme.border.setFill(); NSRect(x:bounds.maxX-1,y:bounds.minY,width:1,height:bounds.height).fill()
  }
}
@MainActor final class SQLPreviewScrollView: NSScrollView {
  private let preview = NSTextView(usingTextLayoutManager:true)
  private var lastSQL: String?
  private var lastDark: Bool?
  override init(frame frameRect: NSRect) {
    super.init(frame:frameRect)
    clipsToBounds=true
    preview.identifier=NSUserInterfaceItemIdentifier("sqlSourcePreview")
    preview.isEditable=false; preview.isSelectable=true
    preview.isHorizontallyResizable=true; preview.isVerticallyResizable=true
    preview.textContainer?.widthTracksTextView=false
    preview.textContainerInset=NSSize(width:14,height:10)
    preview.setAccessibilityLabel("SQL önizleme editörü")
    documentView=preview; hasVerticalScroller=true; hasHorizontalScroller=true
    borderType = .noBorder
    let ruler=SQLPreviewRuler(scrollView:self,orientation:.verticalRuler); ruler.ruleThickness=48;ruler.clipsToBounds=true
    verticalRulerView=ruler; hasVerticalRuler=true; rulersVisible=true
    NotificationCenter.default.addObserver(self,selector:#selector(themeChanged),name:StudioTheme.changed,object:nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func themeChanged() { if let lastSQL { display(lastSQL) } }
  func display(_ sql: String) {
    guard lastSQL != sql || lastDark != StudioTheme.dark else { return }
    let sameSource=lastSQL == sql, selection=preview.selectedRanges, origin=contentView.bounds.origin
    lastSQL=sql; lastDark=StudioTheme.dark
    preview.backgroundColor=StudioTheme.editorCanvas; backgroundColor=StudioTheme.editorCanvas
    let attributed=NSMutableAttributedString(attributedString:SQLSourceHighlighting.attributed(sql))
    let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=20; paragraph.maximumLineHeight=20
    attributed.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:attributed.length))
    preview.textContentStorage?.textStorage?.setAttributedString(attributed)
    let lines=sql.components(separatedBy:"\n")
    let width=min(100000,max(600,(lines.map { ($0 as NSString).size(withAttributes:[.font:StudioTheme.codeFont]).width }.max() ?? 0)+40))
    preview.textContainer?.containerSize=NSSize(width:width,height:10000000)
    preview.setFrameSize(NSSize(width:width,height:max(200,CGFloat(lines.count)*20+32)))
    (verticalRulerView as? SQLPreviewRuler)?.lines=lines.count
    verticalRulerView?.needsDisplay=true
    if sameSource { preview.selectedRanges=selection; contentView.scroll(to:origin); reflectScrolledClipView(contentView) }
  }
}
struct SQLReadOnlyPreview: NSViewRepresentable {
  let sql: String
  func makeNSView(context: Context) -> SQLPreviewScrollView { SQLPreviewScrollView(frame:.zero) }
  func updateNSView(_ scroll: SQLPreviewScrollView, context: Context) { scroll.display(sql) }
}
private struct IndexPanel: View {
  var table: String
  var load: () async throws -> [CatalogItem]
  var open: (String) -> Void
  @State private var columns: [CatalogItem] = []
  @State private var keys: Set<String> = []
  @State private var includes: Set<String> = []
  @State private var name = "IX_NewIndex"
  @State private var unique = false
  @State private var filter = ""
  @State private var preview = ""
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: "Index Designer", icon: "list.number", subtitle: table)
      StudioFormField("İndeks adı") {TextField("İndeks adı", text: $name)}
      Toggle("UNIQUE", isOn: $unique)
      ScrollView {
        VStack {
          ForEach(columns, id: \.id) { column in
            HStack {
              Text(column.name).frame(maxWidth: .infinity, alignment: .leading)
              Toggle("Key", isOn: binding(column.name, set: $keys))
              Toggle("Include", isOn: binding(column.name, set: $includes))
            }
          }
        }
      }.frame(height: 160)
      StudioFormField("Filtre") {TextField("Filtre (isteğe bağlı WHERE koşulu)", text: $filter)}
      HStack {
        StudioActionButton("SQL Oluştur", icon:"doc.badge.gearshape", tint:.accentColor) {
          do {
            preview = try Scripts.index(
              table: table, name: name, keys: columns.filter { keys.contains($0.name) }.map(\.name),
              included: columns.filter { includes.contains($0.name) }.map(\.name), unique: unique,
              filter: filter)
            error = ""
          } catch let failure { error = failure.localizedDescription }
        }
        StudioActionButton("Sorgu Sekmesine Aktar", icon:"arrow.up.forward.square", tint:.accentColor) { open(preview) }.disabled(preview.isEmpty)
      }
      Text("SQL'i inceleyip sorgu sekmesinden çalıştırın.").foregroundStyle(.secondary).font(
        .caption)
      TextEditor(text: $preview).font(.custom(StudioTheme.codeFont.fontName, size: 13)).studioEditor()
      Text(error).font(.caption).foregroundStyle(.red)
    }.padding(20).studioPanel().task {
      do { columns = try await load() } catch let failure {
        self.error = failure.localizedDescription
      }
    }
  }
  func binding(_ name: String, set: Binding<Set<String>>) -> Binding<Bool> {
    Binding(
      get: { set.wrappedValue.contains(name) },
      set: { if $0 { set.wrappedValue.insert(name) } else { set.wrappedValue.remove(name) } })
  }
}
private struct JobPanel: View {
  var databases: [String]
  var open: (String) -> Void
  @State private var name = ""
  @State private var database = "master"
  @State private var command = "SELECT SYSDATETIME();"
  @State private var daily = false
  @State private var time = "090000"
  @State private var preview = ""
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: "SQL Server Agent", icon: "clock.badge.checkmark", subtitle: "Yeni iş ve zamanlama SQL’i hazırla")
      StudioFormField("Job adı") {TextField("Job adı", text: $name)}
      StudioFormField("Veritabanı") {Picker("Veritabanı", selection: $database) {
        ForEach(databases, id: \.self) { Text($0).tag($0) }
      }.labelsHidden()}
      Text("T-SQL Step").font(.headline)
      TextEditor(text: $command).font(.custom(StudioTheme.codeFont.fontName, size: 13)).studioEditor().frame(
        height: 120)
      HStack {
        Toggle("Her gün çalıştır", isOn: $daily)
        TextField("HHMMSS", text: $time).frame(width: 120).disabled(!daily)
      }
      HStack {
        StudioActionButton("SQL Oluştur", icon:"doc.badge.gearshape", tint:.accentColor) {
          do {
            if daily && Int(time) == nil { throw SQLFailure("Saat HHMMSS olmalı.") }
            preview = try Scripts.job(
              name: name, database: database, command: command, dailyTime: daily ? Int(time) : nil)
            error = ""
          } catch let failure { error = failure.localizedDescription }
        }
        StudioActionButton("Sorgu Sekmesine Aktar", icon:"arrow.up.forward.square", tint:.accentColor) { open(preview) }.disabled(preview.isEmpty)
      }
      Text(
        "Job oluşturma SQL'i ayrı sekmede incelenip çalıştırılır. Zamanlama için SQL Server Agent çalışıyor olmalı."
      ).font(.caption).foregroundStyle(.secondary)
      TextEditor(text: $preview).font(.custom(StudioTheme.codeFont.fontName, size: 13)).studioEditor()
      Text(error).font(.caption).foregroundStyle(.red)
    }.padding(20).studioPanel()
  }
}
private struct TemplatesPanel: View {
  var open: (SQLTemplate) -> Void
  @State private var templates: [SQLTemplate] = []
  @State private var selected: String?
  @State private var error = ""
  var item: SQLTemplate? { templates.first { $0.id == selected } }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: "SQL Şablonları", icon: "square.stack.3d.up", subtitle: "Tekrar kullanılabilir sorguları tek yerde tut")
      Text("JSON şablonları içe aktarın. Şablonlar SQL sekmesi açar; otomatik çalıştırılmaz.")
        .foregroundStyle(.secondary)
      HStack {
        StudioActionButton("JSON İçe Aktar…", icon:"square.and.arrow.down", tint:.accentColor) {
          let panel = NSOpenPanel()
          panel.allowedContentTypes = [.json]
          guard panel.runModal() == .OK, let url = panel.url else { return }
          do {
            let item = try SQLTemplate.read(url)
            templates.removeAll { $0.id == item.id }
            templates.append(item)
            selected = item.id
          } catch let failure { error = failure.localizedDescription }
        }
        StudioActionButton("Örnek JSON Kaydet…", icon:"square.and.arrow.up", tint:.accentColor) {
          let panel = NSSavePanel()
          panel.nameFieldStringValue = "template.json"
          guard panel.runModal() == .OK, let url = panel.url else { return }
          do {
            let item = SQLTemplate(
              id: "server-info", name: "Server Info", description: "Sunucu sürümü ve aktif oturum",
              sql: "SELECT @@VERSION AS version, @@SPID AS session_id;")
            try JSONEncoder().encode(item).write(to: url)
          } catch let failure { error = failure.localizedDescription }
        }
      }
      if templates.isEmpty {
        StudioEmptyState(title: "Şablon koleksiyonunu oluştur", icon: "square.stack.3d.up", detail: "Bir JSON şablonu içe aktarın veya örnek dosyayla başlayın.").frame(height: 150)
      } else {
        List(templates, selection: $selected) { Text($0.name).tag($0.id) }.frame(height: 150)
      }
      if let item {
        Text(item.description)
        ScrollView {
          Text(item.sql).font(.custom(StudioTheme.codeFont.fontName, size: 13)).textSelection(
            .enabled
          ).frame(
            maxWidth: .infinity, alignment: .leading)
        }
        StudioActionButton("Sorgu Sekmesinde Aç", icon:"arrow.up.forward.square", tint:.accentColor) { open(item) }
      }
      Text(error).font(.caption).foregroundStyle(.red)
    }.padding(20).studioPanel()
  }
}
private struct AssistantPanel: View {
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

extension ServerAppearance {
  @MainActor var color: NSColor {
    let value = UInt32(effectiveColorHex, radix: 16) ?? 0x7C3AED
    return NSColor(
      srgbRed: CGFloat((value >> 16) & 255) / 255,
      green: CGFloat((value >> 8) & 255) / 255,
      blue: CGFloat(value & 255) / 255, alpha: 1)
  }
}

@MainActor final class ConnectionTreeRow: StudioRowView {
  var color = NSColor.systemIndigo
  var isServer = false
  override func drawBackground(in dirtyRect: NSRect) {
    super.drawBackground(in: dirtyRect)
    if isServer {
      color.withAlphaComponent(0.1).setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
    stripe(in: dirtyRect)
  }
  override func drawSelection(in dirtyRect: NSRect) {
    super.drawSelection(in: dirtyRect)
    stripe(in: dirtyRect)
  }
  private func stripe(in dirtyRect: NSRect) {
    color.setFill()
    NSBezierPath(
      rect: NSRect(x: bounds.minX, y: bounds.minY, width: 3, height: bounds.height).intersection(
        dirtyRect)
    ).fill()
  }
}

struct ConnectionAppearanceFields: View {
  @Binding var appearance: ServerAppearance
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Picker(
          "Ortam",
          selection: Binding(
            get: { appearance.environment },
            set: { value in
              appearance.environment = value
              appearance.colorHex = nil
            })
        ) {
          ForEach(ServerEnvironment.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Button("İşareti Kaldır") { appearance = ServerAppearance() }
          .disabled(!appearance.isMarked)
      }
      HStack {
        ColorPicker(
          "Renk",
          selection: Binding(
            get: { Color(nsColor: appearance.color) },
            set: { color in
              guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
              let hex = String(
                format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
              if hex != appearance.effectiveColorHex { appearance.colorHex = hex }
            }), supportsOpacity: false
        ).fixedSize()
        TextField(
          "RRGGBB",
          text: Binding(
            get: { appearance.colorHex ?? appearance.effectiveColorHex },
            set: { value in
              if value != (appearance.colorHex ?? appearance.effectiveColorHex) {
                appearance.colorHex = value
              }
            })
        )
        .frame(width: 80).help("Altı haneli RGB renk kodu; örneğin D92D20.")
        StudioActionButton("Varsayılan", icon:"arrow.counterclockwise", tint:.accentColor) { appearance.colorHex = nil }
      }
      if appearance.environment == .custom {
        TextField("Özel ortam etiketi", text: $appearance.customLabel)
      }
      HStack(spacing: 8) {
        Image(
          systemName: appearance.environment == .live || appearance.environment == .attention
            ? "exclamationmark.triangle.fill" : "circle.fill"
        )
        .foregroundStyle(Color(nsColor: appearance.color))
        Text(appearance.isMarked ? appearance.badge : "Ortam işareti yok").fontWeight(.semibold)
        Text("Bağlantı ve sorgu alanında görünür").foregroundStyle(.secondary)
      }.font(.caption).padding(7).frame(maxWidth: .infinity, alignment: .leading)
        .background(
          Color(nsColor: appearance.color).opacity(appearance.isMarked ? 0.12 : 0.04),
          in: RoundedRectangle(cornerRadius: 5))
    }
  }
}
// Shared native design tokens. Explicit surfaces preserve semantic typography and colors.
@MainActor class StudioRowView: NSTableRowView {
  override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
  override func drawSelection(in dirtyRect: NSRect) {
    guard selectionHighlightStyle != .none else { return }
    StudioTheme.selection.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 5, yRadius: 5).fill()
    StudioTheme.accent.withAlphaComponent(0.45).setFill()
    NSBezierPath(roundedRect: NSRect(x: 3, y: 4, width: 2, height: max(0, bounds.height - 8)), xRadius: 1, yRadius: 1).fill()
  }
}

/// One label column for form controls; long labels wrap instead of shifting fields.
struct StudioFormField<Content: View>: View {
  let title: String
  let labelWidth: CGFloat
  @ViewBuilder let content: () -> Content
  init(_ title: String, labelWidth: CGFloat = 150, @ViewBuilder content: @escaping () -> Content) {
    self.title = title; self.labelWidth = labelWidth; self.content = content
  }
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title).foregroundStyle(.secondary).frame(width: labelWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      content().frame(maxWidth: .infinity, alignment: .leading)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
/// Compact native actions share semantic colors, hit areas and theme handling.
// Shared, non-interactive hover names avoid the system tooltip's long initial delay.
@MainActor final class StudioHoverHelp {
  static let shared = StudioHoverHelp()
  private var pending: Task<Void, Never>?
  private var panel: NSPanel?
  private weak var source: NSView?
  private(set) var visibleTitle: String?
  private(set) var visibleDetail: String?
  func schedule(for view: NSView, sqlSource: SQLResultSource? = nil) {
    hide(); source = view
    pending = Task { [weak self, weak view] in
      do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
      guard let self, let view, let window = view.window, window.isVisible,
        !view.isHiddenOrHasHiddenAncestor, let name = view.accessibilityLabel(), !name.isEmpty else { return }
      let label = NSTextField(labelWithString: name)
      label.font = .systemFont(ofSize: 11, weight: .medium)
      label.textColor = StudioTheme.text
      label.alignment = .center
      label.sizeToFit()
      var size = NSSize(width: label.frame.width + 16, height: 26)
      var content: NSView = label
      let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
      let screen = window.screen?.visibleFrame ?? anchor
      if let sqlSource {
        let width = min(560, max(240, screen.width-24))
        let code = NSTextField(wrappingLabelWithString: sqlSource.preview)
        code.attributedStringValue = SQLSourceHighlighting.attributed(sqlSource.preview)
        code.maximumNumberOfLines = 16
        code.lineBreakMode = .byTruncatingTail
        let measured = code.attributedStringValue.boundingRect(with: NSSize(width: width-24, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        let height = min(280, max(24, ceil(measured)+4))
        size = NSSize(width: width, height: height+50)
        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true; box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1; box.layer?.borderColor = StudioTheme.border.cgColor
        box.layer?.backgroundColor = StudioTheme.editorCanvas.cgColor
        let heading = NSTextField(labelWithString: sqlSource.heading)
        heading.font = .systemFont(ofSize: 11, weight: .semibold); heading.textColor = StudioTheme.muted
        heading.frame = NSRect(x: 12, y: size.height-30, width: width-24, height: 18)
        code.frame = NSRect(x: 12, y: 12, width: width-24, height: height)
        box.addSubview(heading); box.addSubview(code); content = box
      }
      let below = anchor.minY-size.height-5
      let y = below >= screen.minY ? below : min(screen.maxY-size.height, anchor.maxY+5)
      let rect = NSRect(x: min(max(screen.minX, anchor.midX-size.width/2), screen.maxX-size.width),
        y: max(screen.minY, y), width: size.width, height: size.height)
      let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.isReleasedWhenClosed = false; panel.level = .popUpMenu
      panel.ignoresMouseEvents = true; panel.hasShadow = true
      panel.backgroundColor = StudioTheme.panel
      panel.contentView = content
      window.addChildWindow(panel, ordered: .above)
      panel.orderFront(nil); self.panel = panel
      visibleTitle = name; visibleDetail = sqlSource?.preview
    }
  }
  func hide(for view: NSView? = nil) {
    if let view, source !== view { return }
    pending?.cancel(); pending = nil
    if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
    panel = nil; source = nil; visibleTitle = nil; visibleDetail = nil
  }
}

@MainActor final class StudioToolbarPopUpButton: NSPopUpButton {
  private var hoverArea: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area); hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) { StudioHoverHelp.shared.schedule(for: self) }
  override func mouseExited(with event: NSEvent) { StudioHoverHelp.shared.hide(for: self) }
  override func mouseDown(with event: NSEvent) { StudioHoverHelp.shared.hide(); super.mouseDown(with: event) }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    StudioHoverHelp.shared.hide(for: self); super.viewWillMove(toWindow: newWindow)
  }
}

/// Native tabs retain keyboard, target/action and accessibility behavior.
@MainActor final class StudioResultTabButton: NSButton {
  private var hoverArea: NSTrackingArea?
  var source: SQLResultSource? {
    didSet {
      guard source != oldValue else { return }
      StudioHoverHelp.shared.hide(for: self)
      toolTip = source?.help
      setAccessibilityHelp(source?.help)
    }
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area); hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) {
    if let source { StudioHoverHelp.shared.schedule(for: self, sqlSource: source) }
  }
  override func mouseExited(with event: NSEvent) { StudioHoverHelp.shared.hide(for: self) }
  override func mouseDown(with event: NSEvent) { StudioHoverHelp.shared.hide(); super.mouseDown(with: event) }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    StudioHoverHelp.shared.hide(for: self); super.viewWillMove(toWindow: newWindow)
  }
  override var state: NSControl.StateValue { didSet { refreshStyle() } }
  override var intrinsicContentSize: NSSize {
    let size = super.intrinsicContentSize
    return NSSize(width: size.width + 18, height: 26)
  }
  func refreshStyle() {
    wantsLayer = true; layer?.cornerRadius = 5
    layer?.backgroundColor = (state == .on ? StudioTheme.selection : .clear).cgColor
    contentTintColor = state == .on ? StudioTheme.accent : StudioTheme.muted
    font = .systemFont(ofSize: 11, weight: state == .on ? .semibold : .regular)
  }
}

@MainActor final class StudioToolbarButtonCell: NSButtonCell {
  func contentFrame(_ bounds:NSRect) -> NSRect {
    bounds.insetBy(dx:title.isEmpty ? 4:10,dy:3)
  }
  override func drawInterior(withFrame cellFrame:NSRect,in controlView:NSView) {
    super.drawInterior(withFrame:contentFrame(cellFrame),in:controlView)
  }
}

@MainActor final class StudioToolbarButton: NSButton {
  enum Tone { case neutral, accent, success, warning, danger }
  var tone: Tone { didSet { refreshStyle() } }
  var prominent: Bool { didSet { refreshStyle() } }
  var tracksActiveState = false
  private var hovered = false
  private var pressed = false
  private var hoverArea: NSTrackingArea?
  override var isEnabled: Bool { didSet { refreshStyle() } }
  override var state: NSControl.StateValue { didSet { refreshStyle() } }

  init(symbol: String, label: String, tone: Tone = .accent, title: String = "", width: CGFloat = 28, prominent: Bool = false) {
    self.tone = tone; self.prominent = prominent
    super.init(frame: .zero)
    cell = StudioToolbarButtonCell()
    setButtonType(.momentaryPushIn)
    focusRingType = .none
    self.title = title
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    bezelStyle = .rounded; isBordered = false; controlSize = .small
    font = .systemFont(ofSize: 11, weight: .semibold)
    setAccessibilityLabel(label); toolTip = label
    wantsLayer = true; layer?.cornerRadius = 7; layer?.borderWidth = 1
    widthAnchor.constraint(equalToConstant: width).isActive = true
    heightAnchor.constraint(equalToConstant: 26).isActive = true
    setContentCompressionResistancePriority(.required, for: .horizontal)
    refreshStyle()
  }
  required init?(coder: NSCoder) { fatalError() }
  func refreshStyle() {
    let color: NSColor
    switch tone {
    case .neutral: color = StudioTheme.muted
    case .accent: color = StudioTheme.accent
    case .success: color = StudioTheme.success
    case .warning: color = StudioTheme.warning
    case .danger: color = StudioTheme.danger
    }
    let active = prominent || tracksActiveState && state == .on
    contentTintColor = isEnabled ? prominent ? (StudioTheme.dark ? StudioTheme.canvas : .white) : color : StudioTheme.muted.withAlphaComponent(0.4)
    layer?.backgroundColor = (isEnabled
      ? color.withAlphaComponent(prominent ? pressed ? 0.80 : hovered ? 0.92 : 1 : pressed ? 0.20 : hovered ? 0.12 : active ? 0.12 : 0.035)
      : StudioTheme.muted.withAlphaComponent(0.015)).cgColor
    layer?.borderColor = (isEnabled ? color.withAlphaComponent(active || hovered ? 0.28 : 0) : NSColor.clear).cgColor
  }
  override func sendAction(_ action:Selector?, to target:Any?) -> Bool {
    // Native momentary cells may leave their last state behind. Only controls
    // representing a model mode (editing, favorites, refresh) retain that state.
    if !tracksActiveState {state = .off}
    defer {if !tracksActiveState {state = .off}}
    return super.sendAction(action,to:target)
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area); hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; refreshStyle(); StudioHoverHelp.shared.schedule(for: self) }
  override func mouseExited(with event: NSEvent) { hovered = false; refreshStyle(); StudioHoverHelp.shared.hide(for: self) }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    StudioHoverHelp.shared.hide(for: self); super.viewWillMove(toWindow: newWindow)
  }
  override func mouseDown(with event: NSEvent) {
    StudioHoverHelp.shared.hide()
    pressed = true; refreshStyle()
    defer { pressed = false; refreshStyle() }
    super.mouseDown(with: event)
  }
}

struct StudioActionButton: View {
  let title: String
  let icon: String
  let tint: Color?
  let action: () -> Void
  @Environment(\.isEnabled) private var enabled
  @Environment(\.studioPrimaryAction) private var primary
  init(_ title: String, icon: String, tint: Color? = nil, action: @escaping () -> Void) {
    self.title = title; self.icon = icon; self.tint = tint; self.action = action
  }
  var body: some View {
    Button(action: action) {
      Label {
        Text(title)
      } icon: {
        if let tint, !primary { Image(systemName: icon).foregroundStyle(enabled ? tint : Color.secondary) }
        else { Image(systemName: icon) }
      }.contentShape(Rectangle())
    }.accessibilityLabel(title).help(title)
  }
}
private struct StudioPrimaryActionKey: EnvironmentKey {
  static let defaultValue = false
}
private extension EnvironmentValues {
  var studioPrimaryAction: Bool {
    get { self[StudioPrimaryActionKey.self] }
    set { self[StudioPrimaryActionKey.self] = newValue }
  }
}
struct StudioPrimaryButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    StudioButtonSurface(configuration: configuration, primary: true)
  }
}
struct StudioSecondaryButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    StudioButtonSurface(configuration: configuration, primary: false)
  }
}
private struct StudioButtonSurface: View {
  let configuration: ButtonStyleConfiguration
  let primary: Bool
  @Environment(\.isEnabled) private var enabled
  @Environment(\.controlSize) private var size
  @State private var hovered = false
  private var compact: Bool { size == .small || size == .mini }
  private var ink: Color {
    enabled ? (primary ? Color(nsColor: StudioTheme.dark ? StudioTheme.canvas : .white) : Color(nsColor: StudioTheme.text)) : Color.secondary
  }
  var body: some View {
    configuration.label
      .font(.system(size: compact ? 11 : 12, weight: .medium))
      .symbolRenderingMode(.hierarchical)
      .padding(.horizontal, primary ? 14 : compact ? 8 : 10)
      .padding(.vertical, compact ? 4 : 6)
      .foregroundStyle(ink)
      .frame(minHeight: compact ? 24 : 30)
      .background {
        RoundedRectangle(cornerRadius: 7).fill(
          LinearGradient(colors: primary && enabled
            ? [Color(nsColor: StudioTheme.accent), Color(nsColor: StudioTheme.accent).opacity(0.88)]
            : [Color(nsColor: StudioTheme.controlSurface), Color(nsColor: StudioTheme.controlSurface)],
            startPoint: .top, endPoint: .bottom))
          .overlay(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: StudioTheme.accent).opacity(enabled && (hovered || configuration.isPressed) ? configuration.isPressed ? 0.14 : 0.06 : 0)))
      }
      .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(
        primary && enabled ? Color.white.opacity(0.16) : Color(nsColor: hovered && enabled ? StudioTheme.accent : StudioTheme.controlBorder).opacity(enabled ? 0.8 : 0.4)))
      .shadow(color: Color.black.opacity(enabled ? primary ? 0.10 : 0.035 : 0), radius: primary ? 3 : 1, y: 1)
      .opacity(enabled ? 1 : 0.5)
      .contentShape(RoundedRectangle(cornerRadius: 7))
      .environment(\.studioPrimaryAction, primary)
      .onHover { hovered = $0 }
      .animation(.easeOut(duration: 0.10), value: hovered)
  }
}
struct StudioGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(nsColor: StudioTheme.text))
      configuration.content.frame(maxWidth: .infinity, alignment: .leading)
    }.studioCard()
  }
}
struct StudioNavigationItem: View {
  let title: String
  let icon: String
  let selected: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 20)
          .foregroundStyle(Color(nsColor: selected ? StudioTheme.accent : StudioTheme.muted))
        Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
        Spacer(minLength: 0)
      }.padding(.horizontal, 10).padding(.vertical, 9)
        .foregroundStyle(Color(nsColor: StudioTheme.text))
        .background(selected ? Color(nsColor: StudioTheme.selection) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) {
          if selected { Capsule().fill(Color(nsColor: StudioTheme.accent)).frame(width: 3, height: 16) }
        }.contentShape(Rectangle())
    }.buttonStyle(.plain).help(title).accessibilityLabel(title)
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
struct StudioEmptyState: View {
  let title: String
  let icon: String
  let detail: String
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(.tint)
      Text(title).font(.system(size: 13, weight: .medium))
      Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: StudioTheme.border)))
  }
}
struct StudioPanelHeading: View {
  let title: String
  let icon: String
  let subtitle: String
  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: icon).font(.system(size: 20, weight: .medium))
        .foregroundStyle(Color(nsColor: StudioTheme.accent))
        .frame(width: 42, height: 42)
        .background(LinearGradient(colors: [Color(nsColor: StudioTheme.accent).opacity(0.16), Color(nsColor: StudioTheme.accent).opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: StudioTheme.accent).opacity(0.12)))
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 19, weight: .semibold))
        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }.padding(.bottom, 4)
  }
}
struct StudioPanelStyle: ViewModifier {
  @State private var revision = 0
  func body(content: Content) -> some View {
    content
      .textFieldStyle(.roundedBorder)
      .buttonStyle(StudioSecondaryButton())
      .groupBoxStyle(StudioGroupBoxStyle())
      .font(.system(size: 12))
      .tint(Color(nsColor: StudioTheme.accent))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(LinearGradient(colors: [Color(nsColor: StudioTheme.panel), Color(nsColor: StudioTheme.chrome)], startPoint: .top, endPoint: .bottom))
      .onReceive(NotificationCenter.default.publisher(for: StudioTheme.changed)) { _ in revision += 1 }
      .environment(\.colorScheme, revision >= 0 && StudioTheme.dark ? .dark : .light)
      .overlay(alignment: .top) { Rectangle().fill(Color(nsColor: StudioTheme.border)).frame(height: 1).allowsHitTesting(false) }
  }
}
extension View {
  func studioPanel() -> some View { modifier(StudioPanelStyle()) }
  func studioCard(padding: CGFloat = 16) -> some View {
    self.padding(padding).background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: StudioTheme.border)))
  }
  func studioEditor() -> some View {
    padding(8).background(Color(nsColor: StudioTheme.editorCanvas), in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: StudioTheme.border)))
  }
}

@MainActor enum SQLSourceHighlighting {
  static func foreground(_ token:Lexeme,unused:Bool) -> NSColor {
    unused ? StudioTheme.unusedVariable : StudioTheme.syntax(TSQL.syntaxStyle(token))
  }
  static func attributed(_ source:String) -> NSAttributedString {
    let result=NSMutableAttributedString(string:source,attributes:[.font:StudioTheme.codeFont,.foregroundColor:StudioTheme.editorText])
    guard source.utf16.count <= 1_000_000 else {return result}
    let unused=Set(TSQL.unusedDeclaredVariables(source).map(\.location))
    for token in TSQL.lex(source) {
      result.addAttribute(.foregroundColor,value:foreground(token,unused:unused.contains(token.range.location)),range:token.range)
    }
    return result
  }
}

@MainActor enum StudioTheme {
  static let changed = Notification.Name("MSSQLStudio.themeChanged")
  static var dark: Bool { UserDefaults.standard.string(forKey: "ssmsTheme") == "dark" }
  static func color(_ light: UInt32, _ darkValue: UInt32) -> NSColor {
    let hex = dark ? darkValue : light
    return NSColor(
      srgbRed: CGFloat((hex >> 16) & 255) / 255,
      green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
  }
  static var canvas: NSColor { color(0xFFFFFF, 0x191D25) }
  static var chrome: NSColor { color(0xEBEFF5, 0x141820) }
  static var controlSurface: NSColor { color(0xFFFFFF, 0x2B3341) }
  static var controlBorder: NSColor { color(0xCAD3E0, 0x48576D) }
  static var success: NSColor { color(0x21814E, 0x7BC69C) }
  static var warning: NSColor { color(0xA86412, 0xF0B866) }
  static var danger: NSColor { color(0xC23B48, 0xEE8792) }
  static var panel: NSColor { color(0xF4F6FA, 0x222833) }
  static var text: NSColor { color(0x263247, 0xE1E7F0) }
  static var border: NSColor { color(0xE1E6EF, 0x333C4A) }
  static var selection: NSColor { color(0xE8EFFF, 0x2C4062) }
  static var lineNumber: NSColor { color(0x008080, 0x4EC9B0) }
  static var editorCanvas: NSColor { color(0xFFFFFF,0x1E1E1E) }
  static var unusedVariable: NSColor { color(0x929292,0x808080) }
  static var editorText: NSColor { color(0x000000,0xD4D4D4) }
  static var codeFont: NSFont {
    NSFont(name: "Consolas", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
  }
  static var uiFont: NSFont { .systemFont(ofSize: 12) }
  static var accent: NSColor { color(0x3869D6, 0x8EAEFF) }
  static var muted: NSColor { color(0x5E6D82, 0x9DAAC0) }
  static var stripe: NSColor { color(0xFAFBFD, 0x1C212B) }
  static func surface(_ view: NSView, card: Bool = false, chrome: Bool = false, sidebar: Bool = false) {
    view.identifier = .init(sidebar ? "studio.sidebar" : card ? "studio.card" : chrome ? "studio.frame" : "studio.chrome")
    view.wantsLayer = true
    paintSurface(view)
  }
  private static func paintSurface(_ view: NSView) {
    view.layer?.backgroundColor = (view.identifier?.rawValue == "studio.card" ? canvas : view.identifier?.rawValue == "studio.frame" ? chrome : panel).cgColor
    if ["studio.card", "studio.sidebar"].contains(view.identifier?.rawValue ?? "") {
      view.layer?.cornerRadius = 10
      view.layer?.borderWidth = 1
      view.layer?.borderColor = border.cgColor
      view.layer?.masksToBounds = true
    }
  }
  static func syntax(_ style: TSQL.SyntaxStyle) -> NSColor {
    switch style {
    case .keyword: return color(0x0000FF, 0x6CA0FF)
    case .string: return color(0xFF0000, 0xFF8080)
    case .comment: return color(0x008000, 0x6A9955)
    case .function: return color(0xFF00FF, 0xE88BFF)
    case .systemObject: return color(0x008000, 0x72C77B)
    case .procedure: return color(0x800000, 0xD88585)
    case .operatorSymbol: return color(0x808080, 0xB4B4B4)
    case .plain: return editorText
    }
  }
  static func start() {
    if NSFont(name: "Consolas", size: 13) == nil {
      let path = "/Applications/Microsoft Word.app/Contents/Resources/DFonts/Consola.ttf"
      if FileManager.default.fileExists(atPath: path) {
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, nil)
      }
    }
    apply(UserDefaults.standard.string(forKey: "ssmsTheme") ?? "light")
  }
  static func apply(_ value: String) {
    UserDefaults.standard.set(value == "dark" ? "dark" : "light", forKey: "ssmsTheme")
    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    for window in NSApp.windows {
      window.backgroundColor = chrome
      if let view = window.contentView { decorate(view) }
    }
    NotificationCenter.default.post(name: changed, object: nil)
  }
  static func decorate(_ view: NSView) {
    if let button = view as? StudioToolbarButton { button.refreshStyle() }
    if let button = view as? StudioResultTabButton { button.refreshStyle() }
    if let label = view as? NSTextField, label.identifier?.rawValue == "studio.mutedLabel" { label.textColor = muted }
    // AppKit owns private text/layout views inside controls and the shared field editor.
    // Preserve their native typography and appearance when updating the SQL workspace.
    if view is NSTextField || view is NSPopUpButton || view is NSSegmentedControl { return }
    if let table = view as? NSTableView {
      table.backgroundColor = table is NSOutlineView ? panel : canvas
      table.gridColor = border
      table.headerView?.needsDisplay = true
      table.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
    } else if let scroll = view as? NSScrollView {
      scroll.backgroundColor = scroll.identifier?.rawValue == "studio.chrome" ? panel : canvas
    } else if let textView = view as? NSTextView, !textView.isFieldEditor, !(textView is SQLTextView), !["sqlSourcePreview","agentCommandEditor"].contains(textView.identifier?.rawValue ?? "") {
      textView.backgroundColor = canvas
      textView.textColor = text
      textView.font = codeFont
    }
    if view.identifier?.rawValue.hasPrefix("studio.") == true { paintSurface(view) }
    for child in view.subviews { decorate(child) }
  }
}

/// Fenced SQL is selectable, themed text. Markdown never executes code or loads images.
private struct SSMSMarkdown: View {
  let text: String
  @State private var revision = 0
  var body: some View {
    let blocks = text.components(separatedBy: "```")
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
        if index.isMultiple(of: 2) {
          Text(LocalizedStringKey(block))
            .font(.custom(StudioTheme.uiFont.fontName, size: 12))
            .foregroundStyle(Color(nsColor: StudioTheme.text))
        } else {
          let sql = block.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
          Text(styled(sql))
            .font(.custom(StudioTheme.codeFont.fontName, size: 13))
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: StudioTheme.border)))
        }
      }
    }.textSelection(.enabled)
      .id(revision)
      .onReceive(NotificationCenter.default.publisher(for: StudioTheme.changed)) { _ in
        revision += 1
      }
  }
  private func styled(_ sql: String) -> AttributedString {
    var output = AttributedString()
    for token in TSQL.lex(sql) {
      var part = AttributedString(token.text)
      part.foregroundColor = Color(nsColor: StudioTheme.syntax(TSQL.syntaxStyle(token)))
      output.append(part)
    }
    return output
  }
}

/// A single visible surface survives the complete asynchronous update preparation.
@MainActor final class UpdateProgressController:NSWindowController {
  let status=NSTextField(wrappingLabelWithString: "Güncellemeler kontrol ediliyor…")
  let spinner=NSProgressIndicator()
  let done=NSButton(title:"Kapat",target:nil,action:nil)
  init() {
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:170),styleMask:[.titled],backing:.buffered,defer:false)
    window.title="MSSQL Studio Güncellemesi";window.isReleasedWhenClosed=false
    super.init(window:window)
    spinner.style = .spinning;spinner.startAnimation(nil)
    status.alignment = .center;status.setAccessibilityIdentifier("updateCheckStatus")
    done.target=self;done.action=#selector(closeProgress);done.isEnabled=false
    let stack=NSStackView(views:[spinner,status,done]);stack.orientation = .vertical;stack.spacing=16
    stack.translatesAutoresizingMaskIntoConstraints=false;window.contentView?.addSubview(stack)
    NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:window.contentView!.centerXAnchor),stack.centerYAnchor.constraint(equalTo:window.contentView!.centerYAnchor),stack.widthAnchor.constraint(equalToConstant:392)])
    window.center()
  }
  required init?(coder:NSCoder) {fatalError()}
  func phase(_ text:String) {status.stringValue=text}
  func finish(_ text:String) {phase(text);spinner.stopAnimation(nil);spinner.isHidden=true;done.isEnabled=true;done.keyEquivalent="\r"}
  @objc private func closeProgress() {close()}
}

extension WorkbenchController {
  @objc func installUpdate() {
    guard !updateInProgress else {updateProgress?.showWindow(nil);return}
    let feed:URL
    do {
      if let source=UserDefaults.standard.string(forKey:"githubUpdateRepository"),!source.isEmpty {
        feed=try GitHubUpdateSource.feed(source)
      } else if let address=Bundle.main.object(forInfoDictionaryKey:"MSSQLUpdateFeedURL") as? String,
        let url=URL(string:address),url.scheme == "https" {feed=url}
      else {throw SQLFailure("GitHub yayın deposu henüz tanımlanmadı. Ayarlar → GitHub güncellemeleri alanına kullanıcı/depo adresini girin.")}
    }catch {state.showError(error.localizedDescription);return}
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    updateProgress?.close()
    let progress=UpdateProgressController();updateProgress=progress
    updateInProgress=true;progress.showWindow(nil)
    Task {
      defer {updateInProgress=false}
      let updater = ApplicationUpdate()
      do {
        guard let release = try await updater.check(feed:feed,currentVersion:version) else {
          progress.finish("MSSQL Studio güncel. Yeni bir sürüm bulunamadı.");return
        }
        progress.phase("MSSQL Studio \(release.version) indiriliyor…")
        let package = try await updater.downloadInstaller(release)
        defer {try? FileManager.default.removeItem(at:package)}
        progress.phase("Güncelleme paketi doğrulanıyor…")
        let prepared = try await updater.prepareInstaller(package:package,expectedVersion:release.version,currentVersion:version)
        var installerOpened=false
        defer {if !installerOpened {try? FileManager.default.removeItem(at:prepared.directory)}}
        progress.close()
        let alert=NSAlert();alert.messageText="MSSQL Studio \(prepared.version) kuruluma hazır"
        alert.informativeText="macOS Kurulum penceresinde kurulumu tamamlayın. Yeniden açmayı seçerseniz yeni sürüm doğrulandıktan sonra uygulama otomatik açılır; kurulum iptal edilirse açılmaz. Kayıtlı bağlantılarınız korunur."
        alert.addButton(withTitle:"Güncelle ve Yeniden Aç")
        alert.addButton(withTitle:"Güncelle ve Kapat")
        alert.addButton(withTitle:"Vazgeç")
        let response=alert.runModal()
        guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn,state.canQuit() else {return}
        _ = try await NSWorkspace.shared.open([prepared.package],withApplicationAt:URL(fileURLWithPath:"/System/Library/CoreServices/Installer.app"),configuration:NSWorkspace.OpenConfiguration())
        installerOpened=true
        UserDefaults.standard.set(prepared.version,forKey:"pendingInstallerVersion")
        if response == .alertFirstButtonReturn {
          guard let executable=Bundle.main.executableURL else {throw SQLFailure("Yeniden açma bileşeni bulunamadı.")}
          let watcher=Process();watcher.executableURL=executable
          watcher.arguments=["--reopen-after-update",prepared.version,String(ProcessInfo.processInfo.processIdentifier)]
          watcher.standardInput=FileHandle.nullDevice;watcher.standardOutput=FileHandle.nullDevice;watcher.standardError=FileHandle.nullDevice
          try watcher.run()
        }
        Application.updateTerminationApproved=true
        NSApp.terminate(nil)
      } catch {progress.showWindow(nil);progress.finish("Güncelleme kontrolü tamamlanamadı.\n"+error.localizedDescription)}
    }
  }
}

/// Stable native popovers share one viewport and use an anchor in window coordinates.
@MainActor enum StudioPopover {
  static func placement(anchor:NSRect,viewport:NSRect,preferred:NSSize,flipped:Bool) -> (size:NSSize,edge:NSRectEdge) {
    let above=flipped ? anchor.minY-viewport.minY:viewport.maxY-anchor.maxY
    let below=flipped ? viewport.maxY-anchor.maxY:anchor.minY-viewport.minY
    let down=below>=preferred.height+24 || (above<preferred.height+24 && below>above)
    let height=min(preferred.height,max(220,(down ? below:above)-24))
    return (NSSize(width:min(preferred.width,max(240,viewport.width-32)),height:height),down ? (flipped ? .maxY:.minY):(flipped ? .minY:.maxY))
  }
  static func show<Content:View>(_ popup:NSPopover,content:Content,from anchor:NSView,rect:NSRect?=nil,size:NSSize) {
    guard let host=anchor.window?.contentView else {return}
    let visible=(rect ?? anchor.bounds).intersection(anchor.visibleRect)
    guard !visible.isNull,!visible.isEmpty else {return}
    let converted=host.convert(visible,from:anchor)
    let point=NSRect(x:converted.midX-4,y:converted.minY,width:8,height:converted.height)
    let placement=placement(anchor:point,viewport:host.bounds,preferred:size,flipped:host.isFlipped)
    let controller=NSHostingController(rootView:content.frame(width:placement.size.width,height:placement.size.height))
    controller.sizingOptions=[]
    controller.view.frame=NSRect(origin:.zero,size:placement.size)
    popup.animates=false;popup.behavior = .transient
    popup.contentViewController=controller;popup.contentSize=placement.size
    popup.show(relativeTo:point,of:host,preferredEdge:placement.edge)
  }
}
