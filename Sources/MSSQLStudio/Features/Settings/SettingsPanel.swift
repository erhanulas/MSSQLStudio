import AppKit
import CoreText
import SQLServerKit
import SwiftUI

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
  @StateObject private var definitionStorage:DefinitionIndexStorageModel
  @State private var theme = UserDefaults.standard.string(forKey: "ssmsTheme") ?? "light"
  @State private var explorerDensity = ExplorerDensity.current()
  @State private var completion = UserDefaults.standard.object(forKey:"sqlAutomaticCompletion") as? Bool ?? true
  @State private var completionDelay = Double(SQLEditorPreferences.completionDelay())
  @State private var completionSchema = SQLEditorPreferences.includeSchema()
  @State private var completionBrackets = SQLEditorPreferences.quoteIdentifiers()
  @State private var formatting = SQLEditorPreferences.formatting()
  @State private var validation = UserDefaults.standard.object(forKey:"sqlValidateReferences") as? Bool ?? true
  @State private var aliases = UserDefaults.standard.object(forKey:"sqlAutomaticAliases") as? Bool ?? true
  @State private var noLock = UserDefaults.standard.bool(forKey:"sqlAutomaticNoLock")
  @State private var queryTimeout = QueryExecutionPreferences.timeoutSeconds
  @State private var history = false
  @State private var closedTabLimit = QueryHistoryPolicy.defaultClosedTabLimit
  @State private var historyDays = QueryHistoryPolicy.defaultDays
  @State private var recovery = false
  @State private var warnOnTabClose = true
  @State private var warnOnObjectClose = true
  @State private var updateRepository = UserDefaults.standard.string(forKey:"githubUpdateRepository") ?? ""
  @State private var keychainMessage = ""
  @State private var renewingKeychain = false
  @State private var message = ""
  @State private var selectedTab: SettingsSection
  @State private var expandedCards:Set<String>=["Renk teması","Otomatik tamamlama","Klavye kısayolları","Sekmeler ve pencereler","GitHub yayınları","Parola erişimi"]
  @State private var search=""
  @State private var searchTarget:SettingsSearchEntry?
  @State private var searchFocused=false
  init(state: StudioState, initialTab: SettingsSection = .appearance, definitionStorage:DefinitionIndexStorageModel = DefinitionIndexStorageModel()) {
    self.state = state
    _definitionStorage=StateObject(wrappedValue:definitionStorage)
    _selectedTab = State(initialValue: initialTab)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        StudioPanelHeading(title:"Ayarlar",icon:"slider.horizontal.3",subtitle:"Çalışma ortamı ve uygulama tercihleri")
        Spacer()
        Button {selectedTab = .workspace;expandedCards.insert("Nesne tanım indeksi")} label: {
          VStack(alignment:.trailing,spacing:3) {
            Label("Tanım indeksi",systemImage:"internaldrive").font(.caption)
            Text(definitionStorage.usageText).font(.caption2).monospacedDigit()
          }.padding(4).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier("definitionIndexUsageSummary")
      }
      StudioSearchInput(placeholder:"Tüm ayarlarda ara…",text:$search,focused:Binding(get:{searchFocused},set:{searchFocused=$0}),accessibilityLabel:"Tüm ayarlarda ara",accessibilityID:"settingsSearch",submit:{if let result=SettingsSearch.results(search).first {openSearchResult(result)}})
        .frame(height:28)

      HStack(alignment:.top,spacing:0) {
        SettingsCategoryPicker(selected:selectedTab) {section in selectedTab=section;searchTarget=nil}
          .padding(8).frame(width:164)
        Divider()
        ZStack(alignment:.topLeading) {
        settingsPage(.appearance, subtitle: "Sakin yüzeyler, net ayrımlar ve tema uyumlu SQL renkleri.") {
          settingsCard("Renk teması", icon: "circle.lefthalf.filled") {
            StudioFormField("Çalışma ortamı") {
              StudioChoiceTabs(choices:[("system","Sistem","circle.lefthalf.filled"),("light","Studio Açık","sun.max"),("dark","Studio Koyu","moon")],selection:$theme).accessibilityIdentifier("settingsTheme").id("theme")
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
            StudioFormField("Explorer satırları") {
              StudioChoiceTabs(choices:ExplorerDensity.allCases.map {($0,$0.title,"list.bullet")},selection:$explorerDensity).frame(maxWidth:260).id("explorerDensity")
                .accessibilityIdentifier("settingsExplorerDensity")
            }
            settingsNote("Satır yoğunluğu Uygula ile değişir; ağaç seçimi ve açık dallar korunur.", icon: "list.bullet")
          }
        }
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
            settingsToggle("Tamamlamada şema adını ekle", detail: "Kapalıyken SQL Server’ın varsayılan şema çözümü kullanılır. Aynı adlı nesnelerde ve tüm kullanıcı fonksiyonlarında şema her zaman korunur.", value: $completionSchema)
              .accessibilityIdentifier("settingsCompletionSchema")
            Divider()
            settingsToggle("Tamamlamada köşeli parantez kullan", detail: "Kapalıyken sade adlar kullanılır; boşluk, ayrılmış sözcük ve özel karakter içeren adlar SQL’in geçerli kalması için korunur.", value: $completionBrackets)
              .accessibilityIdentifier("settingsCompletionBrackets")
          }
          settingsCard("SQL biçimlendirme", icon: "text.alignleft") {
            StudioFormField("Anahtar kelimeler") {
              StudioChoiceTabs(choices:[(.upper,"BÜYÜK","textformat"),(.lower,"küçük","textformat"),(.preserve,"Koru","textformat")],selection:$formatting.keywordCase)
            }.id("formatCase")
            StudioFormField("Girinti") {
              Picker("Girinti boşluk sayısı", selection: $formatting.indentWidth) {
                Text("2 boşluk").tag(2); Text("4 boşluk").tag(4); Text("8 boşluk").tag(8)
              }.labelsHidden()
            }.id("formatIndent")
            StudioFormField("Satır genişliği") {
              Stepper(value:Binding(get:{formatting.lineWidth ?? 120},set:{formatting.lineWidth=$0}),in:60...240,step:10) {
                Text("\(formatting.lineWidth ?? 120) karakter").monospacedDigit()
              }
            }.id("formatWidth")
            StudioFormField("Virgül") {
              StudioChoiceTabs(choices:[(.trailing,"Satır sonunda","text.alignright"),(.leading,"Satır başında","text.alignleft")],selection:$formatting.commaStyle)
            }.id("formatComma")
            settingsToggle("Kolon listelerini satırlara ayır", detail: "SELECT, SET, INSERT ve CTE listelerinde okunabilir satır kırma.", value: $formatting.multilineLists)
            settingsToggle("Koşulları satırlara ayır", detail: "WHERE / ON / HAVING içinde AND / OR ifadelerini hizalar.", value: $formatting.breakConditions)
            settingsToggle("SELECT sonrasında boş satır", detail:"Tamamlanan SELECT ifadesini sonraki SQL’den ayırır; alt sorgu ve UNION parçalanmaz.", value:Binding(get:{formatting.blankLineAfterSelect ?? true},set:{formatting.blankLineAfterSelect=$0})).id("formatSelectGap")
            settingsToggle("DECLARE grubu sonrasında boş satır", detail:"Ardışık DECLARE ifadelerini birlikte tutar ve sonraki SQL’den ayırır.", value:Binding(get:{formatting.blankLineAfterDeclare ?? true},set:{formatting.blankLineAfterDeclare=$0})).id("formatDeclareGap")
            settingsNote("Formatla seçili SQL’i, seçim yoksa tüm editörü biçimlendirir. Identifier, alias, literal ve yorum metni korunur; işlem tek adımda geri alınır.", icon: "arrow.uturn.backward")
          }
          settingsCard("Kod yardımcıları", icon: "checkmark.seal") {
            settingsNote("Tanımlanmamış @parametreler kırmızı görünür. DECLARE, prosedür/fonksiyon parametreleri ve GO batch sınırları dikkate alınır.",icon:"at")
            settingsNote("Seçili satırları yorum yap / kaldır: \(GridShortcuts.binding(.comment).label). Yalnız yorumu kaldır: \(GridShortcuts.binding(.uncomment).label). Tam satır veya çok satırlı seçimde küçük yorum simgesi görünür; kelime seçimlerinde açılmaz.",icon:"text.bubble")
            settingsToggle("Eksik tablo ve kolonları vurgula", detail: "Güncel, doğrulanmış veritabanı indeksiyle kırmızı işaretler.", value: $validation)
            Divider()
            settingsToggle("Otomatik alias ekle", detail: "FROM / JOIN içinde tablo veya view önerisi kabul edildiğinde eklenir.", value: $aliases)
            Divider()
            settingsToggle("Alias sonrasında WITH(NOLOCK) ekle", detail: "Varsayılan kapalıdır. Henüz commit edilmemiş verileri okuyabilir.", value: $noLock).disabled(!aliases)
          }
        }
        settingsPage(.shortcuts, subtitle: "Sık kullandığınız işlemlere tek bir tuş birleşimiyle ulaşın.") {
          ShortcutSettings(target: searchTarget?.id,navigate:{action in
            searchTarget=SettingsSearch.entries.first {$0.id == "shortcut."+action.rawValue}
          }) { message = $0 }
        }
        settingsPage(.workspace, subtitle: "Bu Mac’te tutulan sorgu geçmişini ve oturum kurtarmayı yönetin.") {
          settingsCard("Sorgu çalıştırma",icon:"play.circle") {
            StudioFormField("Sorgu zaman aşımı") {
              HStack {
                SettingsIntegerInput("Saniye",value:$queryTimeout).accessibilityIdentifier("queryExecutionTimeout")
                Text("sn").foregroundStyle(.secondary)
              }
            }.id("queryTimeout")
            settingsNote("0 = sınırsız (varsayılan). Manuel sorgular tamamlanana veya İptal’e basılana kadar bekler. 1–86.400 saniye sınır belirleyebilirsiniz. Satır sınırından bağımsızdır; sonraki çalıştırmalarda uygulanır. Explorer, izleme ve otomatik yenileme süre sınırları değişmez.",icon:"info.circle")
          }
          settingsCard("Nesne tanım indeksi",icon:"externaldrive") {
            StudioFormField("Toplam disk kotası") {
              HStack {
                SettingsIntegerInput("MB", value: $definitionStorage.quotaMB)
                Text("MB").foregroundStyle(.secondary)
                Stepper("Kota", value: $definitionStorage.quotaMB, in: 128...65_536, step: 128).labelsHidden()
              }
                .accessibilityIdentifier("definitionIndexQuota")
            }.id("definitionQuota")
            settingsToggle("Kota dolunca otomatik artır", detail: "Yalnız belirlediğiniz üst sınıra kadar büyür.", value: $definitionStorage.automaticGrowth)
            StudioFormField("Artış miktarı") {
              HStack { SettingsIntegerInput("MB", value: $definitionStorage.incrementMB); Text("MB") }
            }.disabled(!definitionStorage.automaticGrowth)
            StudioFormField("Otomatik üst sınır") {
              HStack { SettingsIntegerInput("MB", value: $definitionStorage.maximumMB); Text("MB") }
            }.disabled(!definitionStorage.automaticGrowth)
            ProgressView(value:definitionStorage.usage?.fraction ?? 0).accessibilityLabel("Tanım indeksi doluluk oranı")
            HStack {
              Text(definitionStorage.usageText).monospacedDigit()
              Spacer()
              StudioActionButton("Yenile",icon:"arrow.clockwise") {Task {await definitionStorage.refresh()}}
                .disabled(definitionStorage.busy)
            }.font(.caption)
            if let usage=definitionStorage.usage {Text("\(usage.count) nesne tanımı · Tüm bağlantıların ortak kotası").font(.caption).foregroundStyle(.secondary)}
            if !definitionStorage.error.isEmpty {Label(definitionStorage.error,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)}
            settingsNote("Varsayılan 1 GB (1024 MB). Kota ve otomatik artış Uygula ile kaydedilir. Üst sınır dolunca veya kota küçültülürse en eski tanımlar temizlenir. Otomatik artış fiziksel diskte boş alan oluşturmaz. Doluluk tanım verisini ölçer; SQLite dosya/WAL ve diğer katalog alanları dahil değildir. İndeksleme bağlantı ayarlarından açılır.",icon:"info.circle")
          }
          settingsCard("Sekmeler ve pencereler",icon:"macwindow") {
            settingsToggle("Sekme kapatırken kaydetme uyarısı",detail:"Kaydedilmemiş SQL için sorar. Kapalıysa SQL kaydedilmeden kapanır. Nesne değişiklikleri için aşağıdaki ayrı ayar kullanılır.",value:$warnOnTabClose)
            settingsToggle("Uygulanmamış nesne değişikliklerinde uyar",detail:"Tablo, procedure, view veya fonksiyon tanımındaki uygulanmamış değişikliklerde sorar. Kapalıysa değişiklikler veritabanına gönderilmeden kapanır. Çalışan sorgu, açık transaction ve gönderilmemiş sonuç düzenlemeleri korumaları sürer.",value:$warnOnObjectClose)
          }
          settingsCard("Geçmiş ve kurtarma", icon: "clock.arrow.circlepath") {
            settingsToggle("Sorgu geçmişini sakla", detail: "Çalıştırılan sorgular History üzerinden yeniden açılabilir.", value: $history)
            StudioFormField("Saklama süresi") {
              HStack {
                SettingsIntegerInput("Gün", value: $historyDays).accessibilityIdentifier("historyRetentionDays")
                Text("gün").foregroundStyle(.secondary)
                Stepper("Saklama süresi", value: $historyDays, in: 1...3650).labelsHidden()
              }
            }.disabled(!history).id("retention")
            settingsNote("Varsayılan 30 gün. Süresi dolan kayıtlar açılışta, yeni sorguda ve Uygula ile temizlenir. Üst sınır 16 MB / 20.000 kayıttır.", icon: "calendar")
            StudioFormField("Kapatılan sekmeler / DB") {
              SettingsIntegerInput("Sekme",value:$closedTabLimit).accessibilityIdentifier("closedTabLimit")
            }.id("closedTabs")
            settingsNote("Her bağlantı ve veritabanında en yeni 1–1000 dolu sekme saklanır. Varsayılan 100; boş sekmeler kaydedilmez. Kalıcı kayıt için sorgu geçmişi açık olmalı.",icon:"rectangle.stack")
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
        }
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
        }
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
        }
        }
      }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .accessibilityIdentifier("settingsNavigation")
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
        SettingsApplyButton(apply:applySettings).frame(width:100,height:34)
          .accessibilityIdentifier("settingsApply").disabled(definitionStorage.busy)
          .fixedSize(horizontal:true,vertical:true).layoutPriority(1)
      }.frame(minHeight:38).padding(16)
        .background(Color(nsColor: StudioTheme.canvas), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: StudioTheme.border)))
    }.padding(12).studioPanel().onAppear {
      history = state.historyEnabled
      historyDays = state.historyRetentionDays
      closedTabLimit = state.closedTabLimit
      recovery = state.recoveryEnabled
      warnOnTabClose=state.warnOnTabClose
      warnOnObjectClose=state.warnOnObjectClose
    }.task {await definitionStorage.refresh()}
  }
  private func settingsPage<Content: View>(_ section: SettingsSection, subtitle: String, @ViewBuilder content: @escaping () -> Content) -> some View {
    Group {if selectedTab==section {ScrollViewReader {proxy in
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text(section.title).font(.system(size: 17, weight: .semibold))
          Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        content()
      }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }.background(Color(nsColor: StudioTheme.panel))
      .task(id:searchTarget) {if let target=searchTarget,target.section == section {await Task.yield();proxy.scrollTo(target.scrollID,anchor:.center)}}
      .onChange(of:selectedTab) {_,selected in if selected == section,let target=searchTarget,target.section == section {proxy.scrollTo(target.scrollID,anchor:.center)}}
      .onAppear {if let target=searchTarget,target.section == section {proxy.scrollTo(target.scrollID,anchor:.center)}}
    }} }
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
    searchFocused=false;expandedCards.insert(result.card);selectedTab=result.section;searchTarget=result;search=""
  }
  private func settingsCard<Content: View>(_ title: String, icon: String, tint: Color = Color(nsColor: StudioTheme.accent), @ViewBuilder content: @escaping () -> Content) -> some View {
    VStack(alignment:.leading,spacing:0) {
      StudioDisclosureHeader(title:title,icon:icon,tint:NSColor(tint),expanded:expandedCards.contains(title)) {
        if expandedCards.contains(title) {expandedCards.remove(title)} else {expandedCards.insert(title)}
      }.frame(height:32)
      if expandedCards.contains(title) {VStack(alignment:.leading,spacing:10) {content()}.padding(.top,8)}
    }.frame(maxWidth:.infinity,alignment:.leading).studioCard().id(title)
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
    Task {
          guard QueryExecutionPreferences.timeoutRange.contains(queryTimeout) else {message="Sorgu zaman aşımı 0–86.400 saniye arasında olmalı (0 = sınırsız).";return}
          guard (1...3650).contains(historyDays) else { message = "Saklama süresi 1–3650 gün arasında olmalı."; return }
          guard (1...1000).contains(closedTabLimit) else {message="Kapatılan sekme sayısı 1–1000 arasında olmalı.";return}
          let source=updateRepository.trimmingCharacters(in:.whitespacesAndNewlines)
          if !source.isEmpty {
            do {updateRepository=try GitHubUpdateSource.repository(source)}catch {message=error.localizedDescription;return}
          }
          guard await definitionStorage.apply() else {message=definitionStorage.error;return}
          if source.isEmpty {UserDefaults.standard.removeObject(forKey:"githubUpdateRepository")}
          else {UserDefaults.standard.set(updateRepository,forKey:"githubUpdateRepository")}
          UserDefaults.standard.set(explorerDensity.rawValue,forKey:ExplorerDensity.key)
          NotificationCenter.default.post(name:ExplorerDensity.changed,object:nil)
          QueryExecutionPreferences.save(timeout:queryTimeout)
          StudioTheme.apply(theme)
          UserDefaults.standard.set(completion,forKey:"sqlAutomaticCompletion")
          UserDefaults.standard.set(Int(completionDelay),forKey:SQLEditorPreferences.completionDelayKey)
          UserDefaults.standard.set(completionSchema,forKey:SQLEditorPreferences.completionSchemaKey)
          UserDefaults.standard.set(completionBrackets,forKey:SQLEditorPreferences.completionBracketsKey)
          SQLEditorPreferences.saveFormatting(formatting)
          UserDefaults.standard.set(validation,forKey:"sqlValidateReferences")
          UserDefaults.standard.set(aliases,forKey:"sqlAutomaticAliases")
          UserDefaults.standard.set(noLock,forKey:"sqlAutomaticNoLock")
          NotificationCenter.default.post(name:Notification.Name("sqlEditorPreferencesChanged"),object:nil)
          state.warnOnObjectClose=warnOnObjectClose
          UserDefaults.standard.set(warnOnObjectClose,forKey:"warnOnObjectClose")
          state.warnOnTabClose=warnOnTabClose
          UserDefaults.standard.set(warnOnTabClose,forKey:"warnOnTabClose")
          state.historyEnabled = history
          state.historyRetentionDays = historyDays
          UserDefaults.standard.set(historyDays, forKey: "historyRetentionDays")
          state.closedTabLimit=closedTabLimit
          UserDefaults.standard.set(closedTabLimit,forKey:"closedTabLimit")
          state.closedTabs=QueryHistoryPolicy.closedTabs(state.closedTabs,limit:closedTabLimit)
          state.saveHistory()
          state.recoveryEnabled = recovery
          UserDefaults.standard.set(history, forKey: "historyEnabled")
          UserDefaults.standard.set(recovery, forKey: "recoveryEnabled")
          state.scheduleSnapshot()
          message = "Ayarlar kaydedildi."
    }
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
