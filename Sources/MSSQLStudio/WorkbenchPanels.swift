import AppKit
import CoreText
import SQLServerKit
import SwiftUI

extension WorkbenchController {
  func showSettingsWindow() {
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "studio.settings" && $0.isVisible }) {
      window.makeKeyAndOrderFront(nil); return
    }
    present(SettingsPanel(state: state), title: "MSSQL Studio Ayarları", width: 920, height: 700, minWidth: 780, minHeight: 600, identity: "studio.settings")
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
    button.setAccessibilityLabel(action == .newQuery ? "Yeni sorgu kısayolunu değiştir" : "Başlıklarla kopyalama kısayolunu değiştir")
    return button
  }
  func updateNSView(_ button: ShortcutCaptureButton, context: Context) {
    button.report = report
    if !button.recording { button.title = GridShortcuts.binding(action).label + " · Değiştir…" }
  }
}
private struct SettingsPanel: View {
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
  @State private var selectedTab = "appearance"
  @State private var resultReadLimit = ResultReadPreferences.readLimit
  @State private var resultPageSize = GridPaging.defaultSize
  @State private var resultRefreshSeconds = ResultReadPreferences.refreshSeconds
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      StudioPanelHeading(title: "Ayarlar", icon: "slider.horizontal.3", subtitle: "Çalışma alanını kendine göre düzenle")
      TabView(selection: $selectedTab) {
        settingsPage(title: "Görünüm", subtitle: "Sana uygun çalışma ortamı", icon: "paintpalette") {
      StudioFormField("Renk teması") {Picker("Renk teması", selection: $theme) {
        Text("Studio Açık").tag("light")
        Text("Studio Koyu").tag("dark")
      }.labelsHidden()}.pickerStyle(.segmented)
      Text(
        "Editör: \(StudioTheme.codeFont.familyName ?? "Monospace") · 13 pt  |  Arayüz: Sistem · 12 pt"
      )
      .font(.caption).foregroundStyle(.secondary)
      Text(
        "Dengeli yüzeyler, ince ayrımlar ve ortak ikon dili. Açık ve koyu temalarda SQL renk kategorileri korunur."
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.tabItem { Label("Görünüm", systemImage: "paintpalette") }.tag("appearance")
        settingsPage(title: "SQL Editörü", subtitle: "Yazarken yardımcı olan araçlar", icon: "chevron.left.forwardslash.chevron.right") {
      Toggle("Yazarken DDL indeksinden önerileri göster", isOn:$completion)
      HStack {
        Text("Öneri gecikmesi")
        Slider(value:$completionDelay,in:50...1000,step:10).accessibilityLabel("Otomatik tamamlama gecikmesi")
        Text("\(Int(completionDelay)) ms").monospacedDigit().frame(width:65,alignment:.trailing)
        StudioActionButton("Varsayılan", icon:"arrow.counterclockwise", tint:.accentColor) {completionDelay=Double(SQLEditorPreferences.defaultCompletionDelay)}
      }
      Text("Kısa süre daha hızlı öneri gösterir; uzun süre yazmayı bitirmenizi bekler. Ctrl+Space her zaman beklemeden açar. Uygula ile kaydedilir.").font(.caption).foregroundStyle(.secondary)
      Toggle("Eksik tablo ve kolonları kırmızı vurgula", isOn:$validation)
      Toggle("Tablo / view tamamlamasında otomatik alias ekle", isOn:$aliases)
      Toggle("Otomatik alias sonrasında WITH(NOLOCK) ekle", isOn:$noLock).disabled(!aliases)
      Text("Yalnızca FROM/JOIN tablo veya view tamamlamalarında. Varsayılan kapalıdır; NOLOCK henüz commit edilmemiş verileri okuyabilir.").font(.caption).foregroundStyle(.secondary)
      Text("⌃Space: önerileri aç · Tab / Enter: kabul et · Escape: kapat. Alias yalnızca öneriyi kabul ettiğinizde eklenir. Doğrulama güncel, doğrulanmış aktif veritabanı indeksini kullanır.").font(.caption).foregroundStyle(.secondary)
        }.tabItem { Label("SQL Editörü", systemImage: "chevron.left.forwardslash.chevron.right") }.tag("editor")
        settingsPage(title:"Sonuçlar",subtitle:"Yeni sorgular için yükleme tercihleri",icon:"tablecells") {
          StudioFormField("Okuma sınırı") { TextField("Satır",value:$resultReadLimit,format:.number.grouping(.never)).textFieldStyle(.roundedBorder) }
          StudioFormField("Sayfa boyutu") { TextField("Satır",value:$resultPageSize,format:.number.grouping(.never)).textFieldStyle(.roundedBorder) }
          StudioFormField("Otomatik yenileme") { HStack { TextField("Saniye",value:$resultRefreshSeconds,format:.number.grouping(.never)).textFieldStyle(.roundedBorder); Text("sn").foregroundStyle(.secondary) } }
          Text("Okuma sınırı 1–5.000.000; sayfa boyutu 0–1.000.000. Sayfada 0 tüm yüklenen satırları gösterir. Yenileme 0–3.600 saniye; 0 kapalıdır.").font(.caption).foregroundStyle(.secondary)
          Label("Otomatik yenileme yalnız başarılı SELECT sonuçlarında çalışır; hücre düzenlerken durur.",systemImage:"arrow.clockwise.circle").font(.caption).foregroundStyle(.secondary)
          Text("Bu tercihler yeni sorgulara uygulanır. Açık sorgunun yükleme tercihlerini sonuç çubuğundaki ayar ikonundan değiştirebilirsiniz. Yüksek sınırlar daha fazla disk ve zaman kullanır; bellek/disk ve süre korumaları devam eder.").font(.caption).foregroundStyle(.secondary)
        }.tabItem { Label("Sonuçlar",systemImage:"tablecells") }.tag("results")
        settingsPage(title: "Kısayollar", subtitle: "Sık kullandığın işlemlere hızlı erişim", icon: "command") {
      ForEach(GridShortcuts.Action.allCases, id: \.rawValue) { action in
        HStack {
          Text(action == .headers ? "Grid · Başlıklarla kopyala" : action == .columns ? "Grid · Kolon başlığında ara" : "Yeni sorgu")
          Spacer()
          ShortcutCapture(action: action) { message = $0; shortcutRevision += 1 }.frame(width:220,height:28)
          StudioActionButton("Sıfırla", icon:"arrow.counterclockwise", tint:.accentColor) { GridShortcuts.reset(action); shortcutRevision += 1 }
        }
      }
      .id(shortcutRevision)
      Text("Değiştir’e basıp istediğiniz tuş birleşimine basın. ⌘ veya ⌃ ile harf/rakam kullanın. Ayrılmış ve çakışan kısayollar reddedilir; Escape iptal eder.")
        .font(.caption).foregroundStyle(.secondary)
      Text("Kısayol değişiklikleri hemen kaydedilir.").font(.caption).foregroundStyle(.secondary)
        }.tabItem { Label("Kısayollar", systemImage: "command") }.tag("shortcuts")
        settingsPage(title: "Çalışma Alanı", subtitle: "Geçmiş ve oturum kurtarma", icon: "square.stack") {
      Toggle("Sorgu geçmişini bu Mac'te sakla", isOn: $history)
      StudioFormField("Geçmiş saklama süresi") {
        Stepper(value: $historyDays, in: 1...3650) { Text("\(historyDays) gün").monospacedDigit() }
      }.disabled(!history)
      Text("Varsayılan 30 gün. Süresi dolan kayıtlar açılışta, yeni sorguda ve Uygula ile temizlenir. Çok büyük geçmişlerde ayrıca 16 MB / 20.000 kayıt bütçesi uygulanır.").font(.caption).foregroundStyle(.secondary)
      Toggle("Açık sorgu sekmelerini sonraki açılışta kurtar", isOn: $recovery)
      Text(
        "Sorgu metinleri değerler içerebilir. Kayıtlar yalnızca bu Mac'te Application Support/MSSQLStudio altında tutulur. Bağlantı parolaları bu dosyalara yazılmaz."
      ).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Divider()
        StudioActionButton("Yerel Kayıtları Sil", icon:"trash", tint:.red) {
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
        }.tabItem { Label("Çalışma Alanı", systemImage: "square.stack") }.tag("workspace")
        settingsPage(title: "Güncellemeler", subtitle: "Yeni sürümlerin kaynağı", icon: "arrow.down.circle") {
      StudioFormField("Yayın deposu") {TextField("kullanıcı/depo veya GitHub depo adresi",text:$updateRepository)}.accessibilityIdentifier("githubUpdateRepository")
      Text("Herkese açık Releases kullanılır. Depoyu girip Uygula’ya basın; ardından MSSQL Studio → Güncellemeleri Kontrol Et. Bağlantı parolaları ve sorgular GitHub’a gönderilmez. Boş bırakırsanız uygulamanın yayın adresi kullanılır.").font(.caption).foregroundStyle(.secondary)
        }.tabItem { Label("Güncellemeler", systemImage: "arrow.down.circle") }.tag("updates")
        settingsPage(title: "Güvenlik", subtitle: "Bağlantı parolaları ve uygulama erişimi", icon: "lock.shield") {
      Text("Güncellemelerden sonra tekrarlayan Keychain izni için eski kayıtların uygulama erişimini bir kez yenileyin. macOS bu işlemde parola isteyebilir. Kalıcı imzalı MSSQL Studio'nun erişimi yenilenir; parolalar silinmez veya dışarı aktarılmaz. Önceki izin girdileri otomatik temizlenmez.").font(.caption).foregroundStyle(.secondary)
      StudioActionButton(renewingKeychain ? "İzinler yenileniyor…" : "Keychain izinlerini yenile",icon:"key",tint:.accentColor) {
        renewingKeychain=true;keychainMessage=""
        Task {
          defer {renewingKeychain=false}
          do {
            let count=try await Task.detached {try ServerVault().renewApplicationAccess()}.value
            keychainMessage=count == 0 ? "Kayıtlı bağlantı bulunamadı." : "\(count) bağlantının erişim izni yenilendi. Aynı imzalı güncellemeler için erişim kuralı yenilendi; kilitli anahtar zinciri ayrıca macOS onayı isteyebilir."
          } catch {keychainMessage="İzinler tamamen yenilenemedi: "+error.localizedDescription}
        }
      }.disabled(renewingKeychain).accessibilityIdentifier("renewKeychainAccess")
      if !keychainMessage.isEmpty {Text(keychainMessage).font(.caption).textSelection(.enabled)}
        }.tabItem { Label("Güvenlik", systemImage: "lock.shield") }.tag("security")
      }.accessibilityIdentifier("settingsTabs")
      HStack(spacing: 16) {
        Text(message.isEmpty ? "Tercihlerini düzenledikten sonra Uygula’ya bas." : message)
          .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
          .accessibilityIdentifier("settingsMessage")
        Spacer(minLength: 12)
        StudioActionButton("Uygula", icon:"checkmark", action: applySettings).buttonStyle(StudioPrimaryButton())
          .accessibilityIdentifier("settingsApply")
      }
    }.padding(24).studioPanel().onAppear {
      history = state.historyEnabled
      historyDays = state.historyRetentionDays
      recovery = state.recoveryEnabled
    }
  }
  private func settingsPage<Content: View>(title: String, subtitle: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 12) {
          Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Color.accentColor)
            .frame(width: 44, height: 44).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
          VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
          }
        }
        VStack(alignment: .leading, spacing: 16, content: content)
          .frame(maxWidth: .infinity, alignment: .leading).padding(20)
          .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
      }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private func applySettings() {
          guard (1...5_000_000).contains(resultReadLimit), (0...1_000_000).contains(resultPageSize), (0...3600).contains(resultRefreshSeconds) else { message="Sonuç yükleme değerlerini belirtilen aralıklarda girin."; return }
          let source=updateRepository.trimmingCharacters(in:.whitespacesAndNewlines)
          if !source.isEmpty {
            do {updateRepository=try GitHubUpdateSource.repository(source)}catch {message=error.localizedDescription;return}
          }
          if source.isEmpty {UserDefaults.standard.removeObject(forKey:"githubUpdateRepository")}
          else {UserDefaults.standard.set(updateRepository,forKey:"githubUpdateRepository")}
          ResultReadPreferences.save(rows:resultReadLimit,page:resultPageSize,refresh:resultRefreshSeconds)
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
    preview.identifier=NSUserInterfaceItemIdentifier("sqlSourcePreview")
    preview.isEditable=false; preview.isSelectable=true
    preview.isHorizontallyResizable=true; preview.isVerticallyResizable=true
    preview.textContainer?.widthTracksTextView=false
    preview.textContainerInset=NSSize(width:14,height:10)
    preview.setAccessibilityLabel("SQL önizleme editörü")
    documentView=preview; hasVerticalScroller=true; hasHorizontalScroller=true
    borderType = .noBorder
    let ruler=SQLPreviewRuler(scrollView:self,orientation:.verticalRuler); ruler.ruleThickness=48
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
      NSBezierPath(rect: bounds.intersection(dirtyRect)).fill()
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
    NSBezierPath(rect: bounds.intersection(dirtyRect)).fill()
    StudioTheme.accent.withAlphaComponent(0.45).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: bounds.height)).fill()
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
  var visibleTitle: String? { panel?.isVisible == true ? (panel?.contentView as? NSTextField)?.stringValue : nil }
  func schedule(for view: NSView) {
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
      let size = NSSize(width: label.frame.width + 16, height: 26)
      let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
      let screen = window.screen?.visibleFrame ?? anchor
      let rect = NSRect(x: min(max(screen.minX, anchor.midX - size.width / 2), screen.maxX - size.width),
        y: max(screen.minY, anchor.minY - size.height - 5), width: size.width, height: size.height)
      let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.isReleasedWhenClosed = false; panel.level = .popUpMenu
      panel.ignoresMouseEvents = true; panel.hasShadow = true
      panel.backgroundColor = StudioTheme.panel
      panel.contentView = label
      window.addChildWindow(panel, ordered: .above)
      panel.orderFront(nil); self.panel = panel
    }
  }
  func hide(for view: NSView? = nil) {
    if let view, source !== view { return }
    pending?.cancel(); pending = nil
    if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
    panel = nil; source = nil
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

@MainActor final class StudioToolbarButton: NSButton {
  enum Tone { case neutral, accent, success, warning, danger }
  var tone: Tone { didSet { refreshStyle() } }
  var prominent: Bool { didSet { refreshStyle() } }
  private var hovered = false
  private var pressed = false
  private var hoverArea: NSTrackingArea?
  override var isEnabled: Bool { didSet { refreshStyle() } }
  override var state: NSControl.StateValue { didSet { refreshStyle() } }

  init(symbol: String, label: String, tone: Tone = .accent, title: String = "", width: CGFloat = 28, prominent: Bool = false) {
    self.tone = tone; self.prominent = prominent
    super.init(frame: .zero)
    self.title = title
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    bezelStyle = .rounded; isBordered = false; controlSize = .small
    font = .systemFont(ofSize: 11, weight: .semibold)
    setAccessibilityLabel(label); toolTip = label
    wantsLayer = true; layer?.cornerRadius = 6; layer?.borderWidth = 1
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
    case .success: color = .systemGreen
    case .warning: color = .systemOrange
    case .danger: color = .systemRed
    }
    let active = prominent || state == .on
    contentTintColor = isEnabled ? color : StudioTheme.muted.withAlphaComponent(0.4)
    layer?.backgroundColor = (isEnabled
      ? color.withAlphaComponent(pressed ? 0.24 : hovered ? 0.17 : active ? 0.13 : 0.06)
      : StudioTheme.muted.withAlphaComponent(0.035)).cgColor
    layer?.borderColor = (isEnabled ? color.withAlphaComponent(active || hovered ? 0.3 : 0.13) : StudioTheme.border.withAlphaComponent(0.45)).cgColor
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
  init(_ title: String, icon: String, tint: Color? = nil, action: @escaping () -> Void) {
    self.title = title; self.icon = icon; self.tint = tint; self.action = action
  }
  var body: some View {
    Button(action: action) {
      Label {
        Text(title)
      } icon: {
        if let tint { Image(systemName: icon).foregroundStyle(enabled ? tint : Color.secondary) }
        else { Image(systemName: icon) }
      }.contentShape(Rectangle())
    }.accessibilityLabel(title)
  }
}
struct StudioPrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 12, weight: .semibold))
      .padding(.horizontal, 14).padding(.vertical, 7)
      .foregroundStyle(enabled ? (StudioTheme.dark ? Color(nsColor: StudioTheme.canvas) : Color.white) : Color.secondary)
      .background(enabled ? Color(nsColor: StudioTheme.accent).opacity(configuration.isPressed ? 0.8 : 1) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
      .contentShape(RoundedRectangle(cornerRadius: 6))
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
      Image(systemName: icon).font(.system(size: 20, weight: .regular))
        .foregroundStyle(.tint)
        .frame(width: 38, height: 38)
        .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 18, weight: .semibold))
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
      .font(.system(size: 12))
      .tint(Color(nsColor: StudioTheme.accent))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color(nsColor: StudioTheme.panel))
      .onReceive(NotificationCenter.default.publisher(for: StudioTheme.changed)) { _ in revision += 1 }
      .environment(\.colorScheme, revision >= 0 && StudioTheme.dark ? .dark : .light)
      .overlay(alignment: .top) { Rectangle().fill(Color(nsColor: StudioTheme.border)).frame(height: 1).allowsHitTesting(false) }
  }
}
extension View {
  func studioPanel() -> some View { modifier(StudioPanelStyle()) }
  func studioEditor() -> some View {
    padding(8).background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: StudioTheme.border)))
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
  static var canvas: NSColor { color(0xFFFFFF, 0x202229) }
  static var panel: NSColor { color(0xF3F4F8, 0x292C35) }
  static var text: NSColor { color(0x272B38, 0xDCE0EB) }
  static var border: NSColor { color(0xE1E4ED, 0x3B3F4C) }
  static var selection: NSColor { color(0xE1EBFF, 0x334766) }
  static var lineNumber: NSColor { color(0x008080, 0x858585) }
  static var editorCanvas: NSColor { color(0xFFFFFF,0x1E1E1E) }
  static var unusedVariable: NSColor { color(0x929292,0x808080) }
  static var editorText: NSColor { color(0x000000,0xD4D4D4) }
  static var codeFont: NSFont {
    NSFont(name: "Consolas", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
  }
  static var uiFont: NSFont { .systemFont(ofSize: 12) }
  static var accent: NSColor { color(0x4C6FE8, 0x8CA7FF) }
  static var muted: NSColor { color(0x737D94, 0x9BA5BB) }
  static var stripe: NSColor { color(0xF8F9FC, 0x242730) }
  static func surface(_ view: NSView, card: Bool = false) {
    view.identifier = .init(card ? "studio.card" : "studio.chrome")
    view.wantsLayer = true
    paintSurface(view)
  }
  private static func paintSurface(_ view: NSView) {
    view.layer?.backgroundColor = (view.identifier?.rawValue == "studio.card" ? canvas : panel).cgColor
    if view.identifier?.rawValue == "studio.card" {
      view.layer?.cornerRadius = 8
      view.layer?.borderWidth = 1
      view.layer?.borderColor = border.cgColor
      view.layer?.masksToBounds = true
    }
  }
  static func syntax(_ style: TSQL.SyntaxStyle) -> NSColor {
    switch style {
    case .keyword: return color(0x0000FF, 0x569CD6)
    case .string: return color(0xFF0000, 0xCE9178)
    case .comment: return color(0x008000, 0x6A9955)
    case .function: return color(0xFF00FF, 0xDCDCAA)
    case .systemObject: return color(0x008000, 0x4EC9B0)
    case .procedure: return color(0x800000, 0xC586C0)
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
      window.backgroundColor = panel
      if let view = window.contentView { decorate(view) }
    }
    NotificationCenter.default.post(name: changed, object: nil)
  }
  static func decorate(_ view: NSView) {
    if let button = view as? StudioToolbarButton { button.refreshStyle() }
    if let table = view as? NSTableView {
      table.backgroundColor = canvas
      table.gridColor = border
      table.headerView?.needsDisplay = true
      table.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
    } else if let scroll = view as? NSScrollView {
      scroll.backgroundColor = canvas
    } else if let textView = view as? NSTextView, !(textView is SQLTextView), !["sqlSourcePreview","agentCommandEditor"].contains(textView.identifier?.rawValue ?? "") {
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

extension WorkbenchController {
  @objc func installUpdate() {
    guard !updateInProgress else {return}
    let feed:URL
    do {
      if let source=UserDefaults.standard.string(forKey:"githubUpdateRepository"),!source.isEmpty {
        feed=try GitHubUpdateSource.feed(source)
      } else if let address=Bundle.main.object(forInfoDictionaryKey:"MSSQLUpdateFeedURL") as? String,
        let url=URL(string:address),url.scheme == "https" {feed=url}
      else {throw SQLFailure("GitHub yayın deposu henüz tanımlanmadı. Ayarlar → GitHub güncellemeleri alanına kullanıcı/depo adresini girin.")}
    }catch {state.showError(error.localizedDescription);return}
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    updateInProgress=true
    Task {
      defer {updateInProgress=false}
      let updater = ApplicationUpdate()
      do {
        guard let release = try await updater.check(feed:feed,currentVersion:version) else {
          let alert = NSAlert(); alert.messageText = "MSSQL Studio güncel"; alert.runModal(); return
        }
        let package = try await updater.downloadInstaller(release)
        defer {try? FileManager.default.removeItem(at:package)}
        let prepared = try await updater.prepareInstaller(package:package,expectedVersion:release.version,currentVersion:version)
        var installerOpened=false
        defer {if !installerOpened {try? FileManager.default.removeItem(at:prepared.directory)}}
        let alert=NSAlert();alert.messageText="MSSQL Studio \(prepared.version) kuruluma hazır"
        alert.informativeText="macOS Kurulum penceresinde kurulumu tamamlayın, ardından MSSQL Studio’yu Uygulamalar’dan yeniden açın. Mevcut uygulama yerinde güncellenir; önceki sürüm saklanmaz. Kayıtlı bağlantılarınız korunur."
        alert.addButton(withTitle:"Kurulum’u Aç ve Kapat");alert.addButton(withTitle:"Vazgeç")
        guard alert.runModal() == .alertFirstButtonReturn, state.canQuit() else {return}
        _ = try await NSWorkspace.shared.open([prepared.package],withApplicationAt:URL(fileURLWithPath:"/System/Library/CoreServices/Installer.app"),configuration:NSWorkspace.OpenConfiguration())
        installerOpened=true
        UserDefaults.standard.set(prepared.version,forKey:"pendingInstallerVersion")
        Application.updateTerminationApproved=true
        NSApp.terminate(nil)
      } catch { state.showError(error.localizedDescription) }
    }
  }
}
