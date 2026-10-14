# MSSQL Studio — geliştirme ve mimari sözleşmesi

Bu dosya projenin mimari, kod yapısı, görünüm, veri bütünlüğü, test ve yayın kurallarının tek ana kaynağıdır. Değişiklik yapmadan önce ilgili bölümü okuyun; davranış veya mimari değiştiğinde aynı bölümü güncelleyin. Kuralları yeni mimari/tasarım belgelerine dağıtmayın.

## Agent çalışma protokolü — önce okuyun

Bu bölüm çalışma yönteminin öncelikli özetidir; aşağıdaki teknik, güvenlik, UI, test ve yayın sözleşmelerini kaldırmaz veya gevşetmez. Hız hedefi zorunlu kontrolü atlama gerekçesi değildir.

1. **Bağımsız ilerleyin.** Kullanıcı istenen davranışı tarif eder; ilgili kodu ve testleri inceleyerek mevcut mimariye uygun en küçük, güvenli çözümü seçin, uygulayın ve doğrulayın. Rutin teknik tercihleri kullanıcıya seçtirmeyin; yalnız plan sunup bırakmayın.
2. **Soruları sınırlayın.** Önce bu dosyada, kaynakta ve testlerde araştırın. Ancak ürün davranışını belirleyen belirsizlik, erişilemeyen zorunlu bilgi veya mevcut yetkiyi aşan geri dönüşü zor işlem varsa sorun. Soruyu somut seçenek ve öneriyle birleştirin; yanıt beklerken bağımsız işleri tamamlayın. Daha önce verilmiş ve aynı kapsamda geçerli onayı tekrar istemeyin.
3. **Görev kadar okuyun.** İçindekiler ve kaynak haritasından ilgili bölümleri seçin; aynı oturumda değişmemiş içeriği tekrar tekrar okumayın. Otomatik yüklenen metnin tam olduğunu varsaymayın: ilgili bölüm eksik/kesilmişse depodaki bu AGENTS.md'den doğrudan okuyun. Ortak güvenlik kuralları her görevde geçerlidir; ayrıntılı okuma kapsamı aşağıdadır.
4. **Kök nedeni bulun.** Belirtiyi ilgili veri/olay akışı, durum sahibi ve test kanıtıyla ilişkilendirin; varsayımı gerçek gibi sunmayın. Aynı nedeni paylaşabilecek yakın çağrı noktalarını kontrol edin. Hata gizleme, kontrol kaldırma veya kanıtsız tekrar deneme ile başarı üretmeyin.
5. **Küçük, hedefli değiştirin.** İlgili özellik sahibinde çalışın; ilgisiz refactor, biçimlendirme, bağımlılık veya mimari katman eklemeyin. Kullanıcının değişikliklerini, çalışan özellikleri, veri biçimlerini ve performans bütçelerini koruyun. Gerekli ortak düzeltmeyi etkilenen yolların regresyonuyla doğrulayın.
6. **Aşamalı doğrulayın.** Önce ilgili test, ardından etkilenen ortak yollar, gerekli derleme/native kontrol ve görev gerektiriyorsa tam suite/paket doğrulaması. Ayrıntılar “Geliştirme, doğrulama ve yayın akışı”ndadır. Geçmiş başarılı sonucu ancak ilgili kaynak, bağımlılık ve koşullar değişmediyse yeniden kullanın; yeni hata/değişiklik/koşul yoksa aynı kontrolü tekrarlamayın.
7. **Güvenlik sınırını koruyun.** Geliştirme isteği gerçek kullanıcı DB'sine yazma, kullanıcı verisini silme, kurulu uygulamayı değiştirme veya test için yeniden başlatma yetkisi değildir. Üründeki SQL/DDL gönderim ve işlem onaylarını atlamayın. Secret, Keychain, dondurulmuş helper ve imza kuralları aynen geçerlidir; güvenlik bypass'ı çözüm değildir.
8. **Geliştirme, paket ve yayını ayırın.** Hata/özellik isteğinde geliştirme akışını tamamlayın; dosya/önizleme isteğinde yalnız yerel paket akışını, açık public yayın isteğinde yayın akışını uygulayın. Paket isteği release/tag/latest yetkisi değildir. Yayın isteği varsa aynı kapsam için tekrar onay aramayın; zorunlu doğrulamaları tamamlayın. Helper/kimlik değişimi ayrı açık migration kapsamı gerektirir.
9. **Çelişkiyi sessizce çözmeyin.** Kaynak, test, bu sözleşme ve son kullanıcı isteğini birlikte değerlendirin. Genel özerklik kuralıyla özel güvenlik/bütçe/onay sınırını aşmayın. Ürün kararını gerektiren çözülemeyen çelişkide yalnız etkilenen adımı durdurun; gerekçeyi ve gereken kararı bildirin. Doğrulanan değişikliği mevcut bölümde güncelleyin; yeni sözleşme belgesi açmayın.
10. **Kısa ve kanıtlı raporlayın.** Türkçe iletişim kurun. Anlamlı ilerleme veya engeli kısa bildirin; rutin adımları tek tek anlatmayın. Sonuçta ne değiştiğini, gerçekten çalıştırılan doğrulamayı ve varsa doğrulanmayan koşulu/kalan riski yazın. Atlanan test, sıfır test, araç hatası veya yalnız CI başarısını canlı SQL/native UI/Installer doğrulaması diye sunmayın.

## İçindekiler

- [Agent çalışma protokolü — önce okuyun](#agent-çalışma-protokolü--önce-okuyun)
- [Çalışma ilkeleri ve kapsam](#çalışma-ilkeleri-ve-kapsam)
- [Belgelerin sorumluluğu](#belgelerin-sorumluluğu)
- [Platform ve kaynak haritası](#platform-ve-kaynak-haritası)
- [Kod yapısı ve sahiplik kuralları](#kod-yapısı-ve-sahiplik-kuralları)
- [Görünüm standardı](#görünüm-standardı)
- [SQL oturumları, yürütme ve katalog güvenliği](#sql-oturumları-yürütme-ve-katalog-güvenliği)
- [SQL editörü sözleşmesi](#sql-editörü-sözleşmesi)
- [Sonuçlar, veri düzenleme ve performans](#sonuçlar-veri-düzenleme-ve-performans)
- [Nesne yönetimi ve DDL karşılaştırma](#nesne-yönetimi-ve-ddl-karşılaştırma)
- [Yardımcı özellik sözleşmeleri](#yardımcı-özellik-sözleşmeleri)
- [Keychain, kalıcı imza ve güncelleme](#keychain-kalıcı-imza-ve-güncelleme)
- [Geliştirme, doğrulama ve yayın akışı](#geliştirme-doğrulama-ve-yayın-akışı)
- [Rehberi güncel tutma](#rehberi-güncel-tutma)

## Çalışma ilkeleri ve kapsam

- Proje deposu: https://github.com/erhanulas/MSSQLStudio. Bu proje NativeSQL'den bağımsızdır; eski projeyi değiştirmeyin veya kodunu kopyalamayın. Üst proje aynasının `sources/` dosyaları salt okunur referanstır.
- Kullanıcının mevcut yerel değişikliklerini koruyun. İlgisiz dosyaları, tercihleri, SQL belgelerini, verileri veya geliştirme ortamını sıfırlamayın. Refactor sırasında önceki özellikleri ve kalıcı veri biçimlerini koruyun.
- İstenen davranışı mevcut özellik sahibinde geliştirin. Yeni teknoloji, paket, genel servis katmanı veya büyük yeniden yazım ancak somut ihtiyacı varsa eklenir. Mevcut AppKit/SwiftUI/TextKit 2 yaklaşımını koruyun.
- Eksik yeteneği çalışan düğme, başarı mesajı veya tamamlanmış özellik gibi göstermeyin. Kısmi veri, okunamayan metadata, çevrimdışı bağlantı ve belirsiz işlem sonucu görünür olmalıdır.
- Tasarım, şablon, AI ve favori SQL'i açmak otomatik yürütme değildir. Yazma, sorgu çalıştırma ve yeniden bağlantı yollarının kullanıcıya görünen anlamını koruyun.
- Kurulu `/Applications/MSSQLStudio.app` uygulamasını test derlemesiyle değiştirmeyin; gerçek kullanıcı uygulamasını veya açık SQL oturumlarını test için yeniden başlatmayın. Test/build/QA çıktıları `/tmp` altında tutulur.

### Göreve göre okuma

Her görevde üst protokolü, çalışma ilkelerini ve belgelerin sorumluluğunu esas alın. Kod değişiminde kaynak haritası, sahiplik/concurrency kuralları ve doğrulama akışı ortak temeldir. Aynı oturumda okunmuş ve değişmemiş bölümleri yeniden yüklemek gerekmez. Aşağıdaki tablo başlangıç kapsamıdır; değişiklik başka bir sınırı etkiliyorsa o bölümü de okuyun. Görev dışı ayrıntıyı okumamak o sözleşmeyi değiştirme yetkisi vermez.

| Görev | Bu dosyada ayrıca okunacak bölüm |
|---|---|
| SQL editörü, tamamlama, undo, folding | SQL editörü sözleşmesi; katalog/metadata etkileniyorsa SQL oturumları, yürütme ve katalog güvenliği |
| Bağlantı, Explorer, yürütme, katalog | SQL oturumları, yürütme ve katalog güvenliği; credential etkileniyorsa Keychain, kalıcı imza ve güncelleme |
| Grid, filtre, export, yenileme, veri editi | Sonuçlar, veri düzenleme ve performans; SQL oturumları, yürütme ve katalog güvenliği |
| Nesne tasarımı veya DDL karşılaştırma | Nesne yönetimi ve DDL karşılaştırma; SQL oturumları, yürütme ve katalog güvenliği |
| İzleme, favori/geçmiş, Agent, Linked Server, AI | Yardımcı özellik sözleşmeleri içindeki ilgili alt bölüm; etkilenen oturum/kalıcılık sınırları |
| Görsel veya etkileşim değişikliği | Görünüm standardı; ilgili özelliğin sözleşmesi; Test kanıtı ve UI izolasyonu |
| Credential, imza, updater, paket veya yayın | Keychain, kalıcı imza ve güncelleme; Geliştirme, doğrulama ve yayın akışı |
| Belge düzenleme | Belgelerin sorumluluğu; değiştirilen sözleşmenin tamamı; Rehberi güncel tutma |

### Ürün sınırı

Uygulama native SQL Server çalışma alanıdır: Explorer/bağlantılar, bağımsız sorgu sekmeleri, SQL editörü, disk destekli sonuçlar, mesajlar/XML plan, detached sorgular, sınırlı nesne/veri yönetimi, SQL Agent, DDL karşılaştırma, izleme ve yerel favoriler.

Tam SSMS/DataGrip eşdeğerliği, eksiksiz T-SQL parser/IntelliSense, grafik plan/JOIN diyagramı, serbest docking, otomatik tablo rebuild, backup/restore sihirbazı veya binary plugin SDK vaat edilmez. Agent step reorder, proxy/non-TSQL düzenleme, alert oluşturma ve multiserver/servis yönetimi tamamlanmış özellikler değildir. Kerberos, AI sağlayıcısı, Linked Server sağlayıcıları ve canlı Agent davranışları ancak kendi test kanıtlarıyla doğrulanır.

## Belgelerin sorumluluğu

| Dosya | İçeriği |
|---|---|
| `AGENTS.md` | Güncel geliştirme, mimari/sahiplik, görünüm, veri güvenliği, test ve yayın kuralları |
| `README.md` | Kullanıcıya kısa kurulum, başlangıç ve derleme bilgisi; bu rehberi tekrar etmez |
| `TEST-REPORT.md` | Tarihli test/yayın kanıtları, açık sorunlar ve doğrulanmamış koşullar |
| `Sources/SQLServerKit/Resources/ReleaseNotes.json` | Uygulama ve GitHub yayını için tek sürüm notu kaynağı |
| `Package.swift`, Xcode projesi, scripts/workflows | Gerçek hedef, kaynak kümesi ve derleme/yayın işlemleri |

Sürüm başına geçmiş, Actions numaraları, paket hash'leri ve uzun test günlükleri AGENTS.md'ye eklenmez. Bunlar test raporunda ve Git geçmişinde kalır. Eski tarihli test kayıtları güncel özellik veya güncel başarı kanıtı sayılmaz. Ayrı `ARCHITECTURE.md`, `DESIGN.md` veya imzalama rehberi kopyaları oluşturmayın.

## Platform ve kaynak haritası

macOS 27+, Apple Silicon, Swift 6. Native UI AppKit + SwiftUI, editör TextKit 2 kullanır. SQL Server erişimi Microsoft ODBC Driver 18 / unixODBC / OpenSSL 3; yerel katalog indeksi SQLite üzerindedir.

### Derleme sınırları

Bağımlılık yönü: `MSSQLStudio → SQLServerKit → SQLTextCore`.

- `MSSQLStudio`: uygulama ve native sunum. Özellik klasörleri aynı uygulama hedefi içindedir; her klasör ayrı Swift modülü değildir.
- `SQLServerKit`: UI'dan bağımsız bağlantı, yürütme, metadata, depolama, SQL intelligence ve yönetim mantığı. CODBC/CSQLite bu hedefin bağımlılıklarıdır; AppKit/SwiftUI/uygulama import edilmez.
- `SQLTextCore`: yalnız Foundation'a bağlı SQL yorum ve metin karşılaştırma işlemleri. ODBC, SQLite, UI veya SQLServerKit bağımlılığı alamaz.
- SQLServerKit içindeki public metin typealias'ları mevcut çağrıları korur. API değişimi ayrıca planlanmadan bu uyumluluk kaldırılmaz.
- Test hedefleri: `StudioStateTests`, `SQLServerKitTests`, `SQLTextCoreTests`. Xcode uygulaması yerel SQLServerKit paketini transitif SQLTextCore bağımlılığıyla kullanır.

### Uygulama kaynakları

Aşağıdaki yollar `Sources/MSSQLStudio/` altındadır.

| Alan | Sorumluluk |
|---|---|
| `App/` | Başlatma, menüler, uygulama kısayolları ve izole UI fixture'ları |
| `Workspace/` | Workbench yerleşimi/entegrasyonu, StudioState, QueryDocument, QueryController, sekmeler ve detached pencereler |
| `Features/Connections/` | ConnectedServer, merkezî ConnectionManager/form, DriverSetupModel ve profil görünümü |
| `Features/Explorer/` | TreeNode, ExplorerTreeModel, arama sahibi, katalog/outline/menü/klasör ve Linked Server adaptörleri |
| `Features/Editor/` | SQLTextView, EditorController, Completion, Parameters ve Presentation bileşenleri |
| `Features/Results/` | Grid, Filtering, Plans, Editing ve sonuç tercihleri |
| `Features/Settings/` | Ayarlar, genel ayar araması ve editör tercihleri |
| `Features/ObjectManagement/` | Tables, Modules, Data, Actions ve Review ekranları |
| `Features/SQLAgent/` | Properties, Steps, Schedules, History ve Activity ekranları |
| Diğer `Features/` klasörleri | ActivityMonitor, DatabaseFiles, Favorites, History, SchemaComparison, Updates, About, Templates, Assistant |
| `SharedUI/Theme/` | StudioTheme, semantik renk/font kaynakları |
| `SharedUI/Controls/` | Ortak native düğme, menü, hover ve satır bileşenleri |
| `SharedUI/Forms/` | Form, kart, panel ve native diyalog bileşenleri |
| `SharedUI/SQL/` | Ortak SQL renklendirme, salt okunur önizleme ve fark görünümü |

### Core kaynakları

Aşağıdaki yollar `Sources/SQLServerKit/` altındadır.

| Alan | Sorumluluk |
|---|---|
| `Connections/` | ODBC handle/worker yaşam döngüsü ve ortak modeller |
| `Execution/` | TSQL batch yürütme, okuma bütçesi, sonuç kaynağı ve execution plan |
| `SQLLanguage/` | Lexer, tamamlama, folding, caret/parametre bağlamı ve metin API uyumluluğu |
| `Catalog/` | Metadata, SQLite indeks ve Explorer organizasyon modelleri |
| `Results/` | Spool/snapshot, filtre/sıralama ve güvenli düzenleme hazırlığı |
| `Management/` | Nesne/Agent/DDL modelleri, doğrulanmış SQL üretimi ve karşılaştırma |
| `Monitoring/` | Sunucu/DB dosya ölçümleri ve sayaç hesapları |
| `Persistence/` | Profil, favori/geçmiş depoları ve credential istemcisi |
| `Security/`, `Updates/`, `Assistant/` | Sabit imza kimliği, updater/sürüm geçmişi ve AI servisi |
| `Resources/` | ReleaseNotes.json ve açık SigningIdentity.json; kaynak/paket konumları korunur |

`Sources/SQLTextCore/`: SQLComments, SQLTextDiff, SQLWhitespaceComparison. Dosya adı kısa verilmişse bu haritadaki ilgili alan içinde arayın.

## Kod yapısı ve sahiplik kuralları

### Sorumluluk ayrımı

- View/ViewController native çizim, yerleşim, odak ve olayları yönetir. SwiftUI `body` içinde ağ/disk işi, kayıt veya task yaşam döngüsü başlatmayın.
- Model/özellik sahibi seçim, yüklenme, hata, task, cache ve generation durumunu yönetir. Servis SQL/analiz/depolama işlemini yapar; UI kontrollerine erişmez.
- Bir durumun tek sahibi olur. Aynı Rows, QueryDocument, ODBC session veya undo geçmişi için ikinci gerçeklik kaynağı oluşturmayın. Görünüm için snapshot/projection üretmek sahipliği değiştirmez.
- Bağımlılıkları init/parametre veya dar callback üzerinden verin. Testlerde dış sınırları enjekte edin. Sırf her tipe arayüz eklemek için protocol/repository katmanı kurmayın; gereksiz global singleton ve servis arayıcısı eklemeyin.
- WorkbenchController entegrasyon, yerleşim, sekme/pencere ve komut yönlendirmesidir. Feature içindeki Workbench extension'ları native selector/adaptördür; yeni iş kuralı/task/cache ilgili özellik sahibine gider.

### Mevcut durum sahipleri

| Sahip | Korunacak sorumluluk |
|---|---|
| `StudioState` | Açık bağlantı/belge kümesi, aktif belge, kayıt/kurtarma ve kapatma koordinasyonu |
| `ConnectedServer` | Explorer metadata oturumu, sağlık/generation ve sıralı katalog görünürlüğü işleri |
| `QueryDocument` | Tek sorgunun ODBC oturumu, DB, SQL, yürütme/transaction ve sonuç durumu |
| `QueryController` | Aynı belgenin editör/sonuç alanı ve yürütme UI entegrasyonu |
| `ExplorerTreeModel` | Kararlı node kimlikleri, klasör/favori düzeni ve genişletme kaydı |
| `DefinitionIndexStorageModel` | Ayarlar kota taslağı, asenkron doluluk snapshot’ı, kayıt/temizlik ve görünür hata durumu |
| `ObjectDefinitionIndexController` | Bağlantı opt-in tanım indeksi, tek arka plan okuyucu, revizyon/lease ve çevrimdışı kaynak önizlemesi |
| `ExplorerSearchController` | Debounce, iptal/generation, tek uçuş ve en son bekleyen disk araması |
| `EditorController` | Tek SQLTextView/undo, source-fold projection ve syntax sunumu |
| `EditorInsertPresentation` | Source/generation kontrollü INSERT ordinal snapshot, caret/kolon eşleşmesi ve odağı almayan tıklama önizlemesi |
| `EditorCompletionController` | Analiz task/generation, öneri popup'ı ve key monitor yaşam döngüsü |
| `ResultController` | loadedResult/prefix, kolon/selection/sayfa/pin ve staged edit durumu |
| `ResultSelectionPresentation` | Grid seçim özeti, debounce/tek worker/iptal/revision ve ortak durum çubuğuna sunulan text/help; saf hesap ResultSelectionSummary core’dadır |
| `ResultProjectionController` | Değişmez Rows/rule/sort snapshot'ında arka plan filtre/sıralama işi |
| `ResultEditingCoordinator` | Sonuç/bağlantı/SQL/field bağlamında metadata hazırlığı, tek uçuş, bellekten reuse ve iptal |

### Dosya ve API düzeni

- Yeni dosyayı özelliğin/alanın klasörüne yerleştirin; MSSQLStudio ve SQLServerKit köklerinde dağınık Swift dosyası açmayın. `Utils`, `Helpers`, `Manager` gibi belirsiz yeni toplama alanları yerine sorumluluğu adlandırın.
- Dosya adı ana tip veya belirgin işlevle uyumlu olsun. Birlikte değişen küçük yardımcılar aynı dosyada kalabilir; her birkaç satır için dosya oluşturmayın.
- `scripts/check-architecture.py` dosya başına 1.100 satırı sınırlar. Bu üst sınır hedef boyut değildir. Sınırı rastgele extension'a bölerek aşmayın; önce durum ve işlem sahipliğini ayırın.
- Extension aynı tipin protokol uyumu veya dar native adaptörü için uygundur. Bağımsız bir özelliğin durumu başka dosyalardaki dev controller'a dağıtılmaz.
- `private` varsayılanını koruyun; feature adaptörleri arasındaki gerekli erişim `internal`, modül dışı gerçek API `public` olur. Dosya taşımak için bütün üyeleri public yapmayın.
- Swift adları ve API'ler İngilizce, kullanıcı metinleri mevcut Türkçe ürün diliyle tutarlı olur. Kısaltma, yoğun tek satır ve iç içe closure yerine niyetini anlatan adlar, okunur bloklar ve erken guard kullanın.
- Yorum kararın nedenini, sınırı veya veri bütünlüğü şartını açıklar. Kodun yaptığını tekrar eden yorum, ölü kod, geniş hatayı sessizce yutan catch ve ilgisiz biçimlendirme eklemeyin. İptal/stale sonuç catch'i açık gerekçeyle sessiz kalabilir.
- Mevcut Codable biçimleri, UserDefaults anahtarları, dosya izinleri, native erişilebilirlik kimlikleri ve semantik nesne anahtarları uyumluluk sözleşmesidir. Değişiklik migration ve regresyon kanıtı gerektirir.
- Yeni/taşınan uygulama Swift dosyasında `python3 scripts/sync-xcode-sources.py` çalıştırın. Xcode Sources ve SwiftPM recursive kaynakları eşit kalır; `--check` salt okunurdur.

### Concurrency ve yaşam döngüsü

- Swift 6 concurrency denetimini koruyun. AppKit/SwiftUI MainActor'dadır; blocking ODBC/SQLite ve büyük analiz, filtre, diff/export işleri worker queue/actor veya detached task'tadır.
- Her asenkron işin sahibi, iptal yolu ve güncellik anahtarı açık olur. Yayınlamadan önce gereken source/caret/document/DB/server generation/request revision kontrolünü yapın. `Task.cancel()` tek başına geç sonucu engellemez.
- Tek uçuş gereken işte iptal edilen iş fiziksel olarak bitmeden ikinci iş başlamaz. Explorer aramasında aradaki istekler elenir; yalnız en son bekleyen istek yürür.
- Observer/key monitor/task/cache/window yaşam döngüsünü özellik sahibi temizler. Callback'lerde uygun weak sahiplik kullanın; görünmeyen hosting controller/metin storage biriktirmeyin.
- UI sekme geçişi ağ sonucunu beklemez. Yükleme, hata, iptal ve tekrar deneme görünür kalır; kapanmış pencere/belgeye sonuç uygulanmaz.

## Görünüm standardı

Hedef sakin, hizalı, okunabilir native görünüm; SSMS iş akışı ve DataGrip okunabilirlik yaklaşımıdır. SF Symbols ve ortak bileşenleri kullanın; başka ürünün marka varlığını kopyalamayın. Aynı yerleşim kusuru bulunan benzer formları birlikte inceleyin.

### Tema ve tasarım kaynakları

Renk/font kaynağı `SharedUI/Theme/StudioTheme.swift`; ortak ölçü kaynağı `SharedUI/Theme/StudioMetrics.swift` ve ilgili SharedUI bileşenidir. Spacing ölçeği 4/8/12/16 pt; içerik panelleri esner, başlık ve form kontrolleri dikeyde esnemez. Feature içinde rastgele font/renk/ölçü veya ağır gölge eklemeyin. Ortak standardı değiştirirken bu rehber, kaynak ve ilgili testleri birlikte güncelleyin.

| Semantik token | Açık | Koyu |
|---|---|---|
| Canvas | `FFFFFF` | `191D25` |
| SQL editörü | `FFFFFF` | `1E1E1E` |
| Blok kılavuzu / aktif blok | `D8DEE8` / accent %75 | `414750` / accent %75 |
| Sonuç zemin / başlık / satır | `FFFFFF / FFFFFF / FBFCFE` | `1E1F22 / 252830 / 22252B` |
| Sonuç kenarlık / aktif filtre | `E9EDF3 / F0F6FF` | `343942 / 283952` |
| Panel | `F4F6FA` | `222833` |
| Explorer | `FFFFFF` | `1E1F22` |
| Pencere çerçevesi | `EBEFF5` | `141820` |
| Metin / yardımcı metin | `263247 / 5E6D82` | `E1E7F0 / 9DAAC0` |
| Accent / seçim | `3869D6 / E8EFFF` | `8EAEFF / 2C4062` |
| Kenarlık | `E1E6EF` | `333C4A` |
| Kontrol zemini / kenarlığı | `FFFFFF / CAD3E0` | `2B3341 / 48576D` |
| Başlat / uyarı / tehlike | `21814E / A86412 / C23B48` | `7BC69C / F0B866 / EE8792` |

- `ssmsTheme`: light/dark/system; varsayılan light. Sistem modunda NSApplication.appearance=nil ve public effectiveAppearance gözlemi kullanılır. Global AppleInterfaceStyle veya private bildirim yazılmaz.
- Tema değişimi SQL, caret, seçim, undo, fold, grid genişlik/gizlilik/pin ve scroll durumunu korur. Açık SwiftUI kart/düğme renkleri colorScheme değişiminde yeniden hesaplanır; eski açık yüzey üzerinde koyu tema metni kalmaz. İlerleme bildirimi sırasında recursive tema taraması veya gereksiz reloadData yapılmaz.
- Native text field/popup/segmented control'un private alt view'larını ve field editor'ını SQL editörü gibi biçimlendirmeyin. `sqlSourcePreview`/`agentCommandEditor` syntax renklerini genel dekorasyonla ezmeyin.
- NSTableView `gridColor` yalnız `gridStyleMask` doluyken yazılır. Çizgisiz SwiftUI List separator'ına müdahale row insertion assertion'ı ve tıklama sorunları oluşturabilir; bu regresyonu koruyun.

### Tipografi ve ölçüler

| Alan | Standart |
|---|---|
| UI / yardımcı yazı | Sistem 12 pt / 10–11 pt |
| Panel başlığı / ikon alanı | 16 pt / 32 pt |
| SQL | Consolas 13 pt; yoksa native monospace |
| Form etiket sütunu / aralık | 150 pt / 12 pt; Agent Gelişmiş uzun etiketlerinde 180 pt |
| Form kartı | 8 pt köşe, varsayılan 12 pt iç boşluk |
| İşlem düğmesi | 6 pt köşe; gölgesiz, hover/pressed/disabled durumları |
| Grid / Explorer satırı | 24 pt / Kompakt 24 pt, Rahat 28 pt |
| Sorgu / sonuç sekmesi | 36 pt / 32 pt |
| Sonuç araç satırı | 34 pt |
| Editör / sonuç numara alanı | En az 44 pt / 36 pt; basamak/işaret sayısına göre büyür |
| Sekme kapatma hit alanı | 24×24 pt |

Numara alanı genişliği kaynak/snapshot değişince hesaplanır; scroll çiziminde yeniden ölçülmez. Native popup/text field kendi biçimini korur. Sayı/birim/stepper başlangıçları hizalıdır; etiketler sarar, alan başlangıcı etiket uzunluğuna göre kaymaz.

### Çalışma alanı ve kontroller

- Ortak paneller düz panel yüzeyi, kompakt başlık ve gölgesiz düğme kullanır; dekoratif overlay hit-testing almaz. ConnectionManager native HSplitView ile 170–240 pt profil listesi ve esneyen form sunar. SQL şablonları ortak salt okunur SQL önizlemesi ve ayarlanabilir dikey ayırıcı kullanır.
- Yönetim/Agent/AI formlarında başlık ve işlem alanı sabit kalır; uzun liste, SQL ve yanıt gövdeleri esner/kaydırılır. Birbirinden bağımsız içerikler için native HSplitView/VSplitView kullanın. Agent adım/zamanlama ve favori düzenleme formlarını sabit bir frame’e kilitlemeyin. Yardımcı pencere minimumları `contentMinSize` ile kullanılabilir içerik alanını ifade eder; title bar yüksekliği form alanından düşülmez.
- Kısa işlem geri bildirimi `SharedUI/Forms/StudioFeedback.swift` kullanır: semantik ikon/renk, en fazla iki satır ve Ayrıntılar düğmesi. Uzun hata formu veya alt işlemleri aşağı itemez; tam metin native geçici popover’da seçilebilir/kopyalanabilir, Escape/dış tıklamayla kapanır. Ayrıntı kutusu kendi native responder’ına sahiptir; Escape yalnız kutuyu kapatır, sahibi formu kapatmaz. `StudioPanelWindow.activePopover` aynı korumayı panelden gelen iptal olayına da uygular; ortak seçici/popover sunumları sahip panele kaydolur. Native güncelleme penceresinde aynı ilke kaydırılabilir ayrıntı alanı ve erişilebilir Kapat düğmesiyle uygulanır.
- Düzenlenebilir yönetim SQL’i `SharedUI/SQL/SQLCodeEditor.swift`, salt okunur SQL `SQLReadOnlyPreview` kullanır. SQLCodeEditor mevcut Agent editöründen taşınmıştır; TextKit 2, native undo ve ortak SQL renklendirmesi korunur. `AgentCommandEditor` uyumluluk typealias’ı ve `agentCommandEditor` erişilebilirlik/dekorasyon kimliği korunur; aynı editörün feature içinde ikinci kopyasını oluşturmayın.
- Ana düzen solda Explorer, ortada sorgu sekmeleri/editör, altta sonuç/mesaj/plan alanıdır. Minimum ana pencere 1060×680 pt; Explorer başlangıç oranı %22, minimum genişliği 140 pt'dir. Daralınca kendiliğinden kapanmaz; gizleme açık eylemdir.
- Aktif sorgu sekmesi hafif zemin, 1 pt sakin accent kenarlığı ve medium başlıkla ayrılır; sekme şeridi 36 pt’dir. Alt/üst vurgu çizgisi, kalın çerçeve veya hareketli vurgu eklemeyin. Bağlantı rengi aktif seçimi ezmez; ikon rengi korunur.
- Bağlantı/klasör rengi küçük işaret ve sorgu sekmesine mirasla gösterilir. Ortam/renk adı satırı uzatmaz; tooltip'tedir. `customLabel` ortam unspecified olsa da korunur.
- DB seçimi/bağlantı etiketi ve sorgu araçları aynı 34 pt satırı paylaşır. QueryController'ın gerçek header view'ı host'a taşınır; kopyalanmaz. Sekme değişiminde eski slot'a, detach öncesinde 28 pt bağımsız header'a döner. Hedef/session değişmez.
- Formlarda StudioFormField, başlıklı kart/GroupBox ve sabit işlem alanı kullanın. Placeholder etiketin yerine geçmez. Çok alanı dar HStack'e sıkıştırmayın; küçük pencere/uzun metinde taşma ve hizalamayı kontrol edin.
- Ortak bileşenler: StudioTheme, StudioPanelHeading, StudioEmptyState, StudioPanelStyle/studioPanel, studioCard, StudioGroupBoxStyle, studioEditor, StudioFormField, StudioActionButton, StudioPrimaryButton, StudioSecondaryButton, StudioNavigationItem ve StudioToolbarButton.
- Birincil işlem belirgin, ikincil işlem sakin olur. İşlem düğmesi metin + anlamlı ikon taşır. Başlat yeşil, durdur/ayır turuncu, sil tehlike rengi; renk tek anlam taşıyıcısı değildir.
- Üst toolbar’da Bağlan ve sorgu yürütme araçları yoktur; Yeni Sorgu/Kaydet ve genel araçlar kalır. Editör satırında DB seçimi en soldadır; QueryEditorActions Çalıştır/İptal/Plan/Formatla ikonlarını hemen yanında sunar. Flat StudioToolbarButton normalde zeminsizdir; hover/pressed ve işlem rengi görünürdür. QueryEditorActions tek QueryDocument’a aittir, ana/detached header hostları aynı barı taşır; arkadaki/başka sorguyu hedeflemez.
- Sonuç toolbar’ında gezinme ve okuma/yenileme, kolon/kopyalama ve veri düzenleme grupları ince ayırıcılarla ayrılır. Native açılır okuma/export kontrolleri zeminsiz ve kompakt; borderless StudioToolbarPopUpButton alignment insets sıfırdır, hit yüzeyi toolbar ölçüsüyle eşleşir; düzenleme modu modelden vurgulanır, SQL gönderme yalnız bekleyen değişiklikte birincil olur.
- Toolbar normalde hafif, hover/pressed/aktif durumda belirgin olur. StudioToolbarButton momentaryPushIn'dır; yalnız gerçek model modu `tracksActiveState` ile opt-in yapar. Düğme state'i modelden gelir.
- QueryTabSurface başlık/ikon/padding hit testini DocumentButton’a yönlendirir; bırakma kabulü bütün surface sınırıdır. Close kendi 24×24 kontrolüdür. Borderless native kontroller StudioFullAreaButton/Cell kullanır; disabled ve dışarıda bırakma native davranışı korunur.
- Açılır/kapanır kart başlığı tek bir tam genişlikli kontroldür: ok, ikon, metin ve sağdaki boşluk aynı eylemi çalıştırır. Yalnız oka tıklanan varsayılan DisclosureGroup kullanmayın; StudioDisclosureHeader native tam alan hit test, hover/basılı vurgu, klavye odağı ve açık/kapalı erişilebilirlik durumunu sağlar. Kart gövdesine aç/kapat gesture eklemeyin; içindeki alan/düğme/seçim bağımsız kalır. Yeni kontrolü başlığın sol/metin/sağ boşluk noktaları ve taslak korumasıyla doğrulayın.
- Tüm görünen satır/sekme/düğme alanı tıklanabilir; uygun contentShape/hit alanı kullanın. Sekme X dışarıda mouse-up veya sürükleme sonrası eylem göndermez. Seçili gezinti zemini/işareti ve erişilebilir `.isSelected` durumuyla gösterilir.
- İkon-only kontrollerde erişilebilir ad ve tooltip zorunludur. Native StudioHoverHelp ve SwiftUI `.studioHelp` aynı 200 ms gecikmeli, yuvarlatılmış/kenarlıklı kompakt yüzeyi kullanır. StudioHelpAnchorView hitTest=nil / allowsHitTesting(false) ile tıklama, metin seçimi ve odağı host’ta bırakır; erişilebilir ipucu host’a yazılır. Çok satırlı yardım sınırlıdır; ekran içine yerleşir ve altta yer yoksa üste döner. Çıkış/tıklama/klavye/kaydırma/kapanışta iptal edilir; SQL kaynak/tür hover’ı aynı sahibi kullanır. Yeni SwiftUI yardımında `.help` yerine `.studioHelp` kullanın. Native araç düğmesi iç boşluğu metinli 10×3 pt, ikon-only yatay 4 pt'dir.
- Bitişik mükerrer eylemleri birleştirin; aç/kapat ve başlat/iptal aynı kontrolü paylaşabilir. Farklı veri kapsamındaki eylemleri ayırın. Export en sağdadır; çalışırken aynı konumda iptal gösterir.
- Job/trigger adına durum parantezleri yığmayın; ikon/tooltip/AX açıklaması kullanın. Loading göstergesi diğer sekmelere geçişi engellemez.

### Menü, popup ve yardımcı pencereler

- Sağ tık ve uygulama alt menüleri StudioMenu kullanır: 14 pt native metin, en az 280 pt menü genişliği, yalnız anlamlı ana eylemlerde sakin 16 pt simgeler (macOS 27’de preferredImageVisibility=.visible), gruplar/separatörler ve sistem seçim/klavye/erişilebilirlik davranışı korunur. Her öğeye fallback simge eklemeyin; ikincil eylemler metin ağırlıklı kalır. Template simgeler secondaryLabelColor kullanır; açıkça verilmiş renk işaretleri korunur. Explorer kök menüsünde sorgu/yenileme, favoriler, bağlantı ve organizasyon/kaldırma ayrı gruplardır. StudioTextView bütün uygulama sahipliğindeki native metin yüzeylerinde sistem menüsünü StudioMenu.adopting ile (alt menüler dahil) ortaklaştırır; target/action/tag/representedObject ve native validation korunur. Editörün native menü öğeleri de ortak menüye taşınır; özel NSMenuItem.view ile tracking/AX değiştirilmez. StudioCommandCatalog selector/eylem/varsayılan tuş bilgisinin ortak sahibidir; menü kısayolu ve toolbar yardım metni buradan gelir. Yeni atanabilir komutu GridShortcuts.Action/kataloğa kaydedin, uygun bağlamda gerçek menü öğesi üzerinden yönlendirin. Belirsiz/riskli komut varsayılan boş kalır; Ayarlar Değiştir/Kaldır/Sıfırla sunar. Çakışma ve ayrılmış native tuşlar reddedilir; bağlam menüsündeki enabled/validation, representedObject/tag ve tek eşleşme şartı yürütmede korunur. Kısayol başka sorgunun veya yardımcı pencerenin arkasındaki belgeyi hedefleyemez.
- Native NSMenu/StudioMenu seçim, klavye ve erişilebilirlik davranışlarını korur. Pasif menü öğeleri AppKit auto-enable ile yanlış etkinleşmez. İsim/silme pencereleri menü tracking bittikten sonra açılır.
- Kısa ayar/arama/filtre popup'ları animasyonsuz ve yapay ilk yükleme beklemesi olmadan açılır. Yazım debounce'u korunabilir.
- Aranabilir liste seçimleri StudioSearchablePopUpButton / SwiftUI StudioSearchablePicker kullanır. Seçici sade metin/chevron ve isteğe bağlı leadingSymbol kullanır. Popup önce arama alanı gizli bir liste olarak açılır; odak tablodadır. İlk yazılan karakter search alanını açıp kayıpsız aktarır, ardından native field editor devam eder. Yuvarlatılmış hafif seçim, 12 pt metin/24 pt satır ve overlay scroll ortaktır. Liste genişliği seçeneklerin metin ölçüsünden 160–360 pt aralığında hesaplanır; yükseklik görünür satırlarla büyür, en fazla 360 pt’de scroll kullanır. Seçenek NSTableView’i `.plain` stilinde ve sıfır otomatik inset ile satır geometrisini korur; kısa listedeki son satır kesilemez. Açılış seçili satırı, filtreleme ilk eşleşmeyi görünür kılar. Seçici kontrol 26 pt yüksekliktedir; SwiftUI representable sizeThatFits yüksekliği mutlaka sınırlar ve genişliği 100–280 pt’de tutar. Kontrol çevresindeki boşluğu tıklanabilir popup yüzeyine dönüştürmeyin; native geometri ve boş alan hit test regresyonunu koruyun. Arama native NSSearchField + NSTableView popup’ında yerel içerme filtresidir; yazarken seçim/DB/oturum değişmez. ↑↓/Enter/fare kabul eder, Escape/boş sonuç uygulamaz. updateChoices aynı kapsam/seçim/listeyle gelen durum yenilemesinde aramayı korur; kapsam, değer, seçim veya enabled durumu değişirse eski popup kapanır. Kabulde seçenek hâlâ mevcut olmalıdır; editör sekmesi contextID değişirse eski popup kapanır. Boş seçimin görünen başlığı raw boş değerinden ayrıdır. Editör DB, Explorer arama kapsamı, History/Favoriler, Database Files ve Agent DB alanları ortak kontrolü kullanır; sabit küçük enum seçimlerini gereksiz yere dönüştürmeyin.
- Genel popup'lar StudioPopover ile açık native boyut, pencere koordinatında görünür anchor, flipped koordinat ve ekran üst/alt alanı hesabını kullanır. İçerik kayarken alt işlem alanı görünür kalır; SwiftUI otomatik boyutlandırması popup'ı oynatmaz.
- SQL tamamlama caret/odak davranışı için kendi yolunu kullanır. Satır sayısı/boyut değişince popover kapatılır, content controller son boyutla yeniden bağlanır; eski yükseklikten başlık üstü boşluk bırakılmaz.
- StudioAssociatedWindow yardımcı pencerelerin sahibini zayıf associatedOwner referansıyla tutar; kalıcı addChildWindow sıralaması kullanılmaz. Normal seviyeli managed + participatesInCycle pencereler Mission Control/uygulama pencere seçimine ve Pencere menüsüne katılır; tam ekran auxiliary davranışı korunur. Arkadaki ana pencereye tıklamak yardımcı pencereyi kapatmaz veya erişilemez hale getirmez. Generic panel kapanınca owner/controller bir sonraki MainActor turunda temizlenir ve Pencere menüsü kaydı kaldırılır. Native sheet/alert ve geçici hover kendi native ilişkisini korur. ⌘W closeFocusedWindow ile öndeki pencerenin performClose/delegate yoluna gider; native dosya panelinde Cancel kullanır, arka sorgu sekmesini kapatmaz. Kaydet/Çalıştır/Formatla ve transaction komutları yardımcı penceredeyken arka sorguya yönlenmez; detached pencerede ilgili belge kullanılır. Gecikmiş editör odağı başka pencere öndeyken uygulanmaz.
- StudioPanelWindow Tab/Shift+Tab key loop ve Escape iptal sağlar; SQL metin alanının Tab girdisini çalmaz. İsim toplamak için StudioNameWindowController kullanın; NSAlert.runModal + accessory field kurmayın.
- İsim Save eylemi gerçek field-editor metnini alır; boş/çakışan değer ve hata formda kalır, tekrar denenebilir. Saving sırasında Escape/X kapatamaz. Genel hatalar bloklamayan native bildirim kartında gösterilir.
- Toplu kapatmada Kaydet / Tümünü Kaydetmeden Kapat / Vazgeç ortak karar kullanılır. Toplu at ayrı menü/toolbar maddesi değildir. Busy/transaction/grid yazması önce tüm kümede denetlenir; warnOnTabClose varsayılan açık olarak kaydedilmemiş SQL onayını yönetir. Kapalıyken SQL dosyaya kaydedilmeden kapanır; busy/transaction/pending write, sonuç taslağı ve uygulanmamış nesne değişikliği koruması sürer. Atılan taslak recovery'ye geri bırakılmaz.

### Ayarlar standardı

- Sol native kategori listesi altı bölüm sunar: Görünüm, SQL Editörü, Kısayollar, Çalışma Alanı, Güncellemeler, Güvenlik. Sağda StudioDisclosureHeader başlığının tamamından kartlar kompakt açılır/kapanır; seçili bölüm render edilir, taslakların sahibi SettingsPanel’dır. Sonuç tercihleri yalnız sonuç alanındadır.
- Pencere yeniden kullanılır; minimum içerik 820×620 pt, istenen başlangıç 960×720 pt (kullanılabilir ekrana native constrainFrameRect ile sığdırılır), gerçek frame `frameRect(forContentRect:)` ile hesaplanır. Kartlar hizalı, Uygula/geri bildirim sabittir. Uygula sabit 100×34 pt SwiftUI slotunda native SettingsApplyButton → StudioPrimaryActionButton’dır; zemin ve ink aynı draw içinde çizilir, sistem bezelColor/contentTintColor karışımına bırakılmaz; footer 16 pt iç boşluk bırakır. Pencere native ekran kısıtı ilk hosting layout’tan önce uygulanır; hosting layout ilk gösterim öncesinde/sonrasında tamamlanır; kullanıcının resize yapması beklenmez.
- Tema/depo ve diğer taslaklar sekme, arama ve görünüm değişiminde korunur. Uygula öncesi global tercih/tema değiştirilmez; kısayolların anlık kaydı ayrı mevcut davranıştır.
- Kısayollar ShortcutCatalog’ın eksiksiz switch ile sınıfladığı yedi kategoride gösterilir; yeni eylem kategorisiz bırakılamaz. ShortcutSettings yerel araması bütün kategorileri Türkçe harf/aksan toleransıyla tarar, kategoriye dönüş arama temizlenince olur. Atanmış/atanmamış filtresi güncel binding’i kullanır. Genel SettingsSearch sonucu ilgili kategoriyi açar, yerel filtreleri temizler ve hedef satırı görünür kılar. Değiştir/Kaldır/Sıfırla hemen kaydeder; kategori/arama/gezinme atamayı değiştirmez. Native ShortcutCapture klavye/AX ve pencereye bağlı monitor yaşam döngüsünü korur.
- SettingsSearch bütün sekmeleri Türkçe harf/aksan toleranslı, çok sözcüklü arar. Sonuç başlık/sekme/kart yolunu gösterir; tıklama/Enter ilgili grubu önce açar, doğru kontrol anchor'ına gider ve kartı vurgular.
- Arama/boş sonuç görünümü TabView kimliğini yeniden yaratmaz; ayar uygulamaz, ağ/Keychain işi başlatmaz. Yeni ayar arama kataloğuna ve anchor'a eklenir; kısayollar otomatik indekslenir.

## SQL oturumları, yürütme ve katalog güvenliği

### Oturum ve yürütme

- Her QueryDocument kendi ODBC bağlantısı, DB, SQL/sonuç/tanı ve transaction durumunu taşır. Metadata ayrı bağlantılardadır; sorgu DB context veya transaction'ına dokunmaz. Detached pencere aynı controller/document/session/undo'yu taşır.
- ODBC handle'ları tek worker queue'da yönetilir. SQLCancelHandle ayrı queue + generation/lock korumasıyla kullanılır. UTF-16 ve parçalı hücre okuma korunur. Execution ID/generation geç yanıtın yeni sonucu ezmesini önler.
- **İptal rollback değildir.** Çalışan SQL/açık transaction/pending grid yazması kapatma ve tekrar gönderimde korunur. Kopmuş sorgu ready'ye dönmez; sonuç sonrası session probe kopmayı da yakalar.
- GO yalnız bağımsız satırda ve string/bracket/nested comment dışında ayırır. Batch'ler aynı oturumda sıralıdır; byte/result-set bütçesi ortaktır, satır sınırı her sonuç kümesine ayrı uygulanır.
- Satır sınırında SQLMoreResults okunmamış satırları bırakıp sonraki rowset'e geçer; SQLCancelHandle ile kalan batch/sonuçları kesmeyin. `Rows.truncated`/`Execution.partial` sonraki başarıyla silinmez. Hata/iptal/ortak bütçe `Execution.stoppedEarly` ile sonrasını durdurabilir.
- SQL_ATTR_MAX_ROWS yalnız TSQL.canRepeatRead ile doğrulanmış salt okunur batch'te uygulanır; SQLGetStmtAttr kabul edilen değeri doğrular. DML/EXEC/karma batch'te SET ROWCOUNT etkisiyle yazma kapsamını daraltmayın. Sınırda N+1 fetch yapılmaz; tam N satırda daha fazlası bilinmediği için kısmi durum ihtiyatlıdır.
- SQL identifier/literal escaping merkezi SQL helper'ından geçer; job kimlikleri doğrulanmış UUID'dir. SQL string birleştirmede kullanıcı değerini doğrudan gömmeyin.
- Sayısal sonuçları Double/NumberFormatter'a dönüştürmeyin. Field.normalizedResultValue ODBC temel türüne göre eksik baştaki sıfırı streaming/spool öncesi tamamlar (`.00000000 → 0.00000000`, `-.25 → -0.25`). Precision/scale, kesir sıfırı, işaret, bilimsel gösterim ve NULL korunur; string/binary/integer/çözülemeyen UDT değişmez. Grid/kopyalama/export/conflict aynı metni kullanır.

### Explorer bağlantı sağlığı ve profil işleri

- Görünür ve örtülmemiş Explorer metadata oturumu 15 sn aralık/5 sn sınırla SELECT 1 kontrolü yapar; tek uçuşludur. Offline/reconnecting/fixture durumunda gerçek ağ işi yoktur.
- Yalnız SQLSTATE 08 sınıfı bağlantı kopması offline yapar; izin/syntax hatası offline sayılmaz. Kısa ömürlü katalog bağlantısının 08 hatası mevcut Explorer oturumunun koptuğunu tek başına kanıtlamaz; generation kontrollü kalıcı health probe gerekir. QueryDocument kaybı da ayrı Explorer probe ile doğrulanır.
- Online/offline bildirimi ikon/etiket/menüleri hemen günceller. Metadata kimliği/generation eski hatanın yeni bağlantıyı ezmesini önler. ODBC redaksiyonu ve batch başlangıç satırı yapılandırılmış diagnostics bilgisini korur.
- Offline heartbeat/yenileme kendiliğinden yeniden bağlanmaz. Yeni Sorgu mevcut profil/DB hedefiyle bağlantı beklemeden ayrı disconnected belge açar; query ODBC oturumu yalnız açık Çalıştır isteğinde tek uçuşla kurulur. İstek anındaki SQL/seçim snapshot’ı kullanılır; bağlantı iptali veya generation/DB değişiminde SQL gönderilmez. Login 10 sn sınırındadır; iptal, sürücü çağrısı döndüğünde oturumu kapatır. Hata alt durum çubuğunda ve mesajlarda kalır, yeniden deneme açık Çalıştır’dır; profil yoksa yeni form açılır. Metadata/IntelliSense query oturumunu açmadan ayrı katalog yoluyla yüklenir; offline yalnız cache okunur.
- Explorer bağlantısını kapatmak açık sorgu oturumlarını kapatmaz. Offline ağaç/profil/kapsam korunur. Yeniden bağlantı otomatik SQL çalıştırmaz.
- ConnectionManager Explorer’ı kilitlemeyen ilişkili native pencerede yeni ve mevcut profilleri aranabilir sol listede, formu sağda sunar (minimum içerik 1020×640 pt, istenen başlangıç 1080×700 pt); hosting sizingOptions boş, ekran sınırı ilk layout’tan önce uygulanır ve gösterim öncesi/sonrası layout tamamlanır; seçim kendiliğinden bağlanmaz veya vault listesi okumaz. Yeni bağlantı boş profil/parolayla açılır; kayıtlı profil otomatik seçilmez. Düzenleme yalnız seçilen profil verisini kullanır. Taslak varken profil değiştirme açık bırakma onayı ister. Değişmemiş profil reconnect sırasında Keychain'e tekrar yazılmaz.
- Bağlantı/test/kayıt işlemi alt durum çubuğunda görünür; işlem sırasında bağlantı penceresi kapanmaz, diğer sorgular kullanılabilir. Explorer DB keşfi 10 sn/50.001 satır/16 MB sınırındadır; partial/stoppedEarly/truncated liste kapsam olarak uygulanmaz. Genel/Gelişmiş girdileri korunur. Tek Test Et ve Yükle / Test Et-Yenile eylemi tek kısa ömürlü bağlantıda veritabanı listesini okuyarak testi de yapar; tekrar eden ön test/liste bağlantısı yoktur. Liste/seçim sonrası Bağlan etkinleşir. Mevcut profil çevrimdışı Kaydet ve ayrı isteğe bağlı Bağlan sunar; yerel ad/klasör/renk kaydı test/connect yapmaz.
- DriverSetupModel yeni/mevcut bağlantı formunda unixODBC SQLDriversW kaydını ve dylib yüklenebilirliğini arka planda denetler; Homebrew Cellar yolundan exact sürüm, yoksa major 18 gösterilir. Bu denetim SQL bağlantısı/Keychain veya kurulum başlatmaz.
- Sürücü eksikse kurulum yalnız lisans + Microsoft tap/gerekli trust/bağımlılık etkisini açıklayan açık UI onayıyla çalışır. Plan yalnız resmî Microsoft Homebrew tap ve msodbcsql18'dir; Homebrew >=6 için trust eklenir, tools/global update/sudo/otomatik Homebrew bootstrap yoktur. Homebrew yoksa resmî kurulum bağlantısı verilir. stdin kapalıdır; yönetici gereksinimi hata olarak gösterilir, yetki otomatik yükseltilmez. İşlemde Bağlan/Kaydet, profil seçimi ve kapatma kilitlenir; ilerleme, sınırlı çıktı ve hata görünürdür; başarı/hata sonrası sürücü yeniden denetlenir. Bu işlem sistem paket yöneticisidir, atomik rollback vaat edilmez.
- Endpoint/auth/credential değişiminde çalışan sorgu/transaction güvenliği async öncesi ve sonrası denetlenir. Doğrulama gereken bağlantı değişikliğinde aday bağlantı doğrulanır; vault işi MainActor dışında kalır. Oturumlar geçersizleştiğinde SQL belgeleri korunur; yeniden bağlantı açık kullanıcı eylemidir.
- Explorer'dan Kaldır ağaç/bağlantı/restore seçimini ve bağlantıya ait yerel nesne/kolon/tanım indekslerini kaldırır; profil/parola ve açık sorgular korunur. Kayıtlı Bağlantıyı Sil profil/parolayı da silen ayrı kapsamdır. İkisi açık ad/tooltip ve mevcut onaylarıyla sunulur. Görünür DB tercihi yetkilendirme değildir.

### Ağaç, organizasyon ve arama

- Explorer satır yoğunluğu `ExplorerDensity` ile Ayarlar → Görünüm → Yazı ve okunabilirlik içinde seçilir; Uygula’ya kadar taslaktır. Varsayılan Kompakt 24 pt, Rahat 28 pt; değişim node kimliklerini/seçimi/açık dalları koruyarak yalnız native satır geometrisini yeniler. Arama kutusu her zaman görünür; kapsam ve gelişmiş filtreler yalnız Arama modunda açılır. İndeks/hata durum satırı gizlenmez. Sütun/indeks ikonlarının hizası, lazy loading ve mevcut klavye/context menu yolları korunur.

- Explorer kök bağlantı etiketi yalnız profil adıdır. Özel ortam etiketi yalnız custom ortamında kullanılır; başka ortama geçiş veya validated() eski customLabel’ı temizler. Bağlı/kapalı/bağlanıyor/kaydediliyor durumu SF Symbol ve tint ile gösterilir; durum erişilebilirlik bilgisinde, bağlantı ayrıntıları ve hata tooltip’te korunur.

- State.servers sırası tek kaynaktır; roots aynı node kimlikleriyle izler. Native local move yalnız tek geçerli bağlantı payload'ını kabul eder; arama/nesne/DB/favori/harici kaynak/çoklu payload reddedilir. Sıra explorerServerOrder UUID'leriyle saklanır; bilinmeyen/tekrar kimlikler ayıklanır, yeni profil sona eklenir. Aktif restore/Keychain tercihi değişmez.
- Klasörler profil UUID'lerini düzenler; parola kopyalamaz. En çok 100 klasör/8 seviye, döngü ve aynı düzey isim çakışması denetlenir. Klasör silmek çocukları üst düzeye taşır; organizasyon nesne/DB genişletme anahtarlarını değiştirmez.
- explorerExpansionState semantik parent path + profil UUID/DB/nesne kimliği kullanır; bağlantı adı kimlik değildir. Üst collapse alt tercihi silmez; programmatik reload/restore kaydedilmez. Lazy yükleme sonrası açık atalar üzerinden restore edilir; offline restore ağ işi yapmaz.
- Kök DB kimlik listesi modelden izlenir. Her UI değişiminde yüklenmiş/kapalı ağacı yeniden kurmayın; başarısız reconnect seçim/node/genişletmeyi korur.
- Nesne araması yalnız seçili Explorer'ın tüm seçili DB'leri veya tek DB kapsamındadır. Bağlantı başına çalışma sırasındaki DB tercihi korunur; eski explorerSearchScope yalnız aynı UUID'de restore edilir. Temizleme/tema/ağaca dönüş kapsamı bozmaz; kaldırılan DB/bağlantıda geçerli kapsama düşülür.
- Sağ tık seçili node için tek kaynaktan kurulur. Mükerrer ALTER editörü eklemeyin: Modify editörü açar, Script As → ALTER Clipboard/File hedeflerini korur. View kolonunda Modify owning view'ı açar. Hata satırı üst dalı tekrar denetir; normal detay yalnız kopyalanır.
- Tek Yenile eylemi refreshExplorerScope üzerinden yürür. Klasör/nesne yalnız yüklenmiş ilgili dalı okur, lazy dallar korunur. DB ayrıca yerel nesne/kolon/tanım indeksini force eşitler; sunucu önce DB listesini okur, sonra indeks hazırlar. Opt-in/single-flight korunur; SQL çalıştırılmaz. Job History kendi native yenileme yolunu kullanır.
- Bağlantı adlandırması yalnız bağlantı ayarlarındadır; klasör ve SQL nesnesi adlandırması farklı kapsam olarak korunur. Ayrı indeks yenileme sağ tık eylemi yoktur. Header/DB ikonları durum/opt-in açar; panel Yenile aynı refreshExplorerScope yoludur ve offline pasiftir.

- ExplorerArchive v1 yalnız profillerin sırasını ve yerel klasör/renk organizasyonunu aktarır; parola, SQL, indeks veya credential archive içermez. JSON 2 MB/500 profil, mevcut klasör/derinlik sınırları ve alanlar yazmadan önce doğrulanır. Çakışan UUID yeniden eşlenir; mevcut profil/parola/sıra korunur, aynı ad/endpoint/default DB tekrar eklenmez. Yeni profiller boş parolayla Keychain’e kaydedilip çevrimdışı eklenir; aktarım SQL çalıştırmaz/bağlanmaz. Kısmi Keychain hatasında tamamlanan profiller korunup sayı/hata bildirilir; otomatik belirsiz tekrar yoktur. Dosya/Explorer bağlantı işlemleri menülerinden açılır.

### Nesne tanım indeksi ve çevrimdışı kaynak

- Nesne içeriği indeksi veritabanı bazındadır: ServerProfile.definitionIndexDatabases optional sözlüğü açık/kapalı tercihleri taşır. Yeni profilde eksik tercih kapalıdır. Legacy indexObjectDefinitions opt-in’i geriye uyumluluk için okunur; ilk DB tercihi değişikliği bilinen DB’lerin önceki tercihlerini sözlüğe taşır ve legacy alanı temizler, bundan sonra yeni DB kapalıdır. Bağlantı formundaki DB satırı İçerik seçeneği ve Explorer DB indeks panelindeki Nesne içeriklerini indeksle aynı profil kaydetme yolunu kullanır. Offline ayarlanabilir; credential/endpoint değişmediyse reconnect/query reset yapmaz. Yalnız görünür ve içerik için açık DB’ler alınır; bir DB’de kapatmak yalnız o owner/scope’un tanım kayıtları ve sync marker’ını siler, nesne/kolon tamamlamasını veya diğer DB’leri kapatmaz. Endpoint/auth değişimi eski tanım kapsamını temizler. Explorer’dan kaldırmak bütün kayıtlı owner scope’larını, geçerli/önceki DB nesne/kolon/tanım indekslerini temizler; profil/parola ve açık query session/transaction korunur.
- CatalogDiskIndex.source_definitions aynı SQLite actor'ında owner UUID + endpoint/login/DB scope + object ID ile saklanır. İçerik kaynak SQL/generated CREATE, ham modül tanımı, ad/şema/tür/parent ID, modify stamp, fetch zamanı ve SHA-256 taşır. SQL kodu hassas literal içerebilir; açık opt-in metni yerel saklamayı belirtir. Mevcut 0700 klasör/0600 SQLite izinleri korunur; şifreleme/secure erase vaat edilmez. catalog_owners eski endpoint scope'larının da kaldırılmasını sağlar.
- ObjectDefinitionIndexController tek uçuşludur. DB başına ayrı tek kısa ömürlü ODBC bağlantısında envanter (50k nesne/16 MB/30 sn) ve yalnız değişen nesneler sınırlı gruplarla okunur; query veya Explorer metadata oturumuna dokunmaz. Modüller 64 başlangıç/en çok 200 kimlikli set sorgusu, tablo/synonym 32 başlangıç/en çok 64 nesnelik set sorgusu kullanır. Tablo metadata’sı yedi ortak rowset + object ID prefix ile ayrılır; mevcut doğrulanmış decoder kullanılır, trigger gövdeleri ayrı envanterde alındığından tabloyla tekrar indirilmez. Grup bütçesi 8 MB/30 sn’dir; büyük/kısmi yanıt ikiye bölünür ve küçülen boyut sonraki gruplarda korunur. Tek nesne kısmi kalırsa eski kayıt korunur ve hata görünür. Boyut/süreye göre grup büyür/küçülür; sabit nesne başı bekleme yoktur. Inventory/decode/script utility worker’dadır, gruplar arasında cooperative yield vardır. SQLite savepoint/tek kota kontrolü ve grup başına tekrar kullanılan prepared statement atomik yayın yapar; disk hatası okunamayan nesne gibi yutulmaz. Küçük stamp/ağaç kimlikleri body JSON’ından ayrı covering indekslerden okunur. Normal yenileme 5 dk’ya kadar yeniden taramaz; force yenileme bu sınırı atlar. DB kapsamlı yenileme yalnız ilgili DB içeriğini okur; global yenileme açık DB’leri sıralar. İlerleme modül/tablo aşamasını belirtir. İlk tam taramanın sunucu/ağ maliyeti vardır; sabit hız veya sıfır maliyet iddia edilmez.
- Tablo, view, T-SQL procedure/function, DML/DB trigger ve synonym desteklenir; tablo mevcut doğrulanmış ObjectMetadata/CREATE üretimini kullanır. Şifreli/CLR/okunamayan veya desteklenmeyen nesneler başarı diye sunulmaz. Kısmi envanter/transport hatası eski kayıtları korur; kesin okunamayan içerik eski body'yi kaldırır. Yayın okuma grubu bazında atomiktir; bütün DB'nin aynı anda alınmış transaction snapshot'ı değildir. Tam tur sonunda artık bulunmayan kimlikler temizlenir. Payload başına 4 MB sınırı korunur. Tüm bağlantılar için ortak tanım kotası varsayılan 1 GB (1024 MB), Ayarlar → Çalışma Alanı içinde 128 MB–64 GB ayarlanır; Kota elle MB girilebilir; Uygula atomik kota/artış politikası kaydı ve temizlik yapar, küçültmede en eski kayıtlar atılır. İsteğe bağlı otomatik artış varsayılan kapalıdır; artış ve üst sınır elle 128 MB–64 GB girilir, açık politikada üst sınır mevcut kotadan küçük olamaz. Payload kotası dolarken belirlenen adımla üst sınıra kadar büyür; üst sınırda en eski kayıtları atar. Politika source_growth tablosundadır; gerçek disk doluluğu kota artışıyla giderilmez, yazma hatası görünür kalır. Ayarlar başlığında her sekmede kullanılan/kota/yüzde özeti; tanım kartında ilerleme, nesne sayısı ve Yenile bulunur. Ölçüm yalnız kaynak payload byte sayısıdır, SQLite dosya/WAL ve diğer katalog alanları dahil değildir. Kota SQLite source_settings içinde saklanır; RAM cache'i tekrar yazma yolunda SQL/DDL yapmaz. Doluluk SQLite actor'ından asenkron okunur; test/smoke depoları /tmp içinde izoledir; SQLite boyut sayacı trigger'larla sabit maliyetli tutulur.
- İçerik indeksi durumu DB bazındadır: source_sync son başarılı tur zamanı, beklenen/okunamayan nesne sayısını kalıcı tutar; kayıt sayısı ve son içerik okuma source_scope_fetched covering indeksinden alınır. Boş başarılı tur hazırlanmadı sayılmaz; beklenen okunabilir tanımlardan eksik kayıtlar Kısmi indeks'tir. Kesin okunamayan sayısı source_sync içinde tutulur, UI’da listelenmez ve tek başına uyarı üretmez; completeness count < max(0, expected-unavailable) ile hesaplanır. Gerçek ağ/disk hataları ve kota nedeniyle eksik okunabilir kayıtlar görünür kalır. Gizleme/kapatma/kaldırma sync metadata'sını da temizler. Runtime sırada/ilerleme/duraklama/hata her DB için bağımsızdır; başka DB başarısı hatayı gizlemez. DB düğmesi ve ortak indeks penceresi nesne/kolon/içerik bilgilerini sunar; yinelenen sağ tık Yerel İndeks Durumu maddesi yoktur. Nesne ve içerik ikonları 56 pt sabit ayrı native sütundadır; ExplorerScrollView tile sırasında plain tablonun ad sütununu viewport’a ölçer, native inset/yatay eski genişlik ikonları dışarı itemez. definitionsOnly bildirimleri completion yenileme/arama başlatmaz; en fazla saniyelik ilerleme yalnız ilgili DB satırı/kartını yeniler, tüm DB disk okuması yapmaz.
- **Online nesne tanımı her zaman sunucudan okunur; hata durumunda cache fallback yoktur.** View/module/table/synonym script/designer ve editör tanıma gitme yolları canlı okumadan sonra ilgili kaydı günceller. Ham moduleOriginal/conflict baseline disk indeksinden oluşturulmaz. Online tanım sekmesi de query bağlantısı açmaz; Veritabanına Gönder onayından sonra bağlantı gerekirse kurulur, ardından SQL/DB/original snapshot yeniden doğrulanarak canlı conflict okuması yapılır. Fetch başlangıç zamanı daha eski arka plan sonucunun yeni interaktif kaydı ezmesini önler; source tercih revizyonundan önce başlamış interaktif fetch’ler kapatma/yeniden açma sonrasında cache’e yazılamaz; owner lease + DB generation + app revision eski, kapatılmış/gizlenmiş/kaldırılmış kapsam yazmasını reddeder.
- Offline Explorer klasörleri küçük indeks kimliklerinden açılabilir. Nesne çift tık veya İndekslenmiş Tanımı Gör mevcut query sekmesinde tarihli native salt okunur önizlemedir. SQL’e Dön SQL/seçim/undo/sonuç/session/transaction’ı korur; önizleme edit SQL’i veya moduleOriginal olmaz, çalıştırma/yenileme/yapıştırma kapalıdır. Sekme yoksa bağlantısız boş belge oluşturulur. ⌘B cold katalogda da şema/adı küçük disk kimliklerinden çözer; belirsiz ad açık hata verir, farklı DB adı mevcut DB’ye eşlenmez. Önizleme içindeki ⌘B kaynak server/DB kapsamını kullanır. Geç yanıt request kimliğiyle geri dönme veya sonraki isteği ezemez. İndeks yoksa açık hata gösterir, nesne açmak yeniden bağlanmaz. Tablo/view trigger altları parent ID ile ayrılır. Nesne kodu içinde kelime arama UI'ı bu aşamanın kapsamında değildir; kayıt yapısı sonraki arama/navigasyona temeldir.

- Explorer DB satırında nesne listesi (`square.stack.3d.up`) ve içerik (`doc.text.magnifyingglass`) ikonları sabit iki trailing sütundadır; renk/tooltip durum verir. İlerleme yalnız ilgili DB satırını ve kartın runtime sunumunu günceller; reloadExplorer item/children:false tüm ağaç genişleme restorasyonu yapmaz, restorasyon yalnız yapısal reload’dadır; kart kimliği ve form taslağı korunur.
- İndeks paneli/tipleri durum için tam SQLIntelligence.Catalog yüklemez; timestamp ve DB kapsamlı mantıksal UTF-8 saklama boyutları CatalogDiskIndex worker’ında okunur. Boyut nesne/kolon/tanım/edit metadata ayrımıyla gösterilir; ortak SQLite sayfaları/indeks overhead/WAL/staging fiziksel DB boyutu diye sunulmaz. Boyut yalnız panel açılışı veya tamamlanma/ayar değişiminde okunur; progress bildiriminde okunmaz.
- QueryDocument.useDatabase yalnız kendi oturumundaki USE boyunca busy olur; başarıda task/ready katalog yenilemesinden önce yayınlanır. loadSymbols ayrı metadata servisinde güncellik korumasıyla yürür; taze cache iki kez yayınlanmaz. sqlCatalogChanged editör bildirimi Explorer indeks durumunu veya bütün DB satırlarını yenilemez.

### Katalog ve hedefli DDL yenilemesi

- SQLite worker'ında staging + atomik yayın kullanılır; başarısız yenileme önceki snapshot'ı korur. Scope server/DB'dir; tek uçuş, cancellation, request/generation, retry/freshness korunur. Arama yerel yüklenmiş indekstedir; kısmi/hazır değil durumu görünürdür.
- Gizlenen DB'nin nesne/staging/build/scope, tanım, completion ve editing metadata kayıtları yalnız o server/DB'den temizlenir. Devam eden tam/hedefli işler iptal edilir; yeni indeksleme başlatılmaz. Diğer DB ve açık gizli-DB sorgu/transaction'ı korunur; gerekli edit metadata önbelleğe yazılmadan okunabilir.
- ConnectedServer görünürlük işleri sıralıdır: önceki iki servis temizliği ve disk yan etkisi bitmeden sonraki seçim uygulanmaz. Tam erişilebilir/önceki DB adları kapsanır. Bütün disk yazmaları generation lease doğrular; geç yanıt gizlenmiş veya yeniden eklenmiş DB'ye yazamaz. Yalnız MainActor revision yeterli değildir.
- Statik CREATE/ALTER/DROP ve index owner değişimi tür/DB/şema/ad ile ayrılır. String/dinamik SQL ve modül gövdesi yürütülmüş DDL sayılmaz. USE/GO ve yürütme DB snapshot'ı korunur.
- Tek yol: scoped metadata → object disk target → completion target → açık Explorer dalı. Folder/full DB reload ve ikinci loadSymbols(force:true) eklemeyin. Diğer sembol/timestamp/cache'ler korunur.
- Açık transaction'da DDL yenilemesi bekler; COMMIT/ROLLBACK sonrası doğrulanmış session probe ile yapılır. Probe hatası bekleyen hedefleri silmez. Tablo edit cache'i ilgili base tabloda; view/synonym provenance bilinmiyorsa yalnız edit hazırlığı ihtiyatlı geçersizleşir.

## SQL editörü sözleşmesi

### Metin, undo, find ve folding

- Yürütmede yalnız gerçek sonuç field editor düzenlemesi commit edilir; SQL firstResponder koşulsuz boşaltılmaz. Manuel ana/detached Çalıştır editörü odaklar. İlk setText document.selectedRange alanını UTF-16 sınırında kurar; focusEditor caret görünürlüğü ve blink sağlar. Boş viewport tıklaması SQL/satır/undo yaratmaz.
- SQLPreviewView, LineNumbers bileşenini sabit sibling sütunda kullanır; SQLInlineDiffView ghost/source numaralarını kendi sabit sibling gutter’ında tutar. Native NSRulerView kaydırma/inset davranışına bağlı değildir. Yeni fark içeriğinin ilk değişikliğine geçiş, panel ölçüleri ve scroll tiling tamamlandıktan sonra yapılır; sıfır boyutlu panelde bekleyen hedef tüketilmez. TextKit 2, SSMS renkleri, viewport render, tema/seçim/kaydırma/kopya ve fark yönü korunur.
- Explorer’da Git tıklanan identifier snapshot’ını kullanır. En çok üç parçalı ad hedef DB’ye bağlanır; dört parçalı sunucu tahmin edilmez. Yüklenmiş ilgili DB dalları veya online sınırlı sys.objects metadata’sı nesne türünü belirler; legacy completion kind tahmin edilmez. SQLIntelligence aktif alias kapsamını gerçek nesneye bağlar. Hatalı/eksik ilgili dal yeniden yüklenir ve yükleme sonrası atalar tekrar açılır; offline yalnız yerel tanım indeksi okunur. Belge/SQL/seçim/server generation/request kimliği eski cevabın odak almasını engeller; tüm nesne ağacı taranmaz. SQL ve query oturumu değişmez.


- TextKit 2 korunur; `layoutManager` erişimiyle TextKit 1'e düşmeyin. Renklendirme metni yeniden atamaz; yalnız attribute aralıklarını günceller. IME marked text sırasında boyama/biçimlendirme ertelenir.
- Her editörün ayrı UndoManager'ı vardır; aynı controller detach/redock'ta taşınır. Ctrl+Z, Ctrl+Y/Ctrl+Shift+Z ve ⌘Z/⌘⇧Z aynı geçmişi kullanır. Standart undo:/redo:, validation, menü ve klavye aynı geçmişe bağlıdır; find/başka field editor odağında SQL geçmişi çalınmaz.
- Yazım grupları kelime + ardındaki yatay boşluk, 1 sn duraklama ve caret/yön/işlem değişiminde kesilir. Paste, silme, quote pair, completion, format/bulk replacement ayrı adımdır; IME grubu bölünmez. Syntax ve fold projection undo üretmez. Undo/redo sonrası QueryDocument.sql, binding ve renkler görünür metinle eşleşir.
- ⌘F/Ctrl+F aynı doğrudan native NSTextFinder yolunu açar; ilk açılış ve Düzen → Bul etkinliği önceki aramaya bağlı değildir. Native finder bar, EditorFindContainer içinde SQL viewport’un üstünde ayrı alan kullanır; ilk satırı örtmez, search field tıklamaları editöre aktarılmaz. Gutter SQL viewport ile hizalanır. Seçili metinle arama, next/previous, replace ve undo korunur; ⌘⇧F Formatla'dır.
- Find öncesi fold açılır; client string değişiminden önce noteClientStringWillChange çağrılır. incrementalSearchingShouldDimContentView=false; en çok 500 eşleşme viewport overlay'inde çizilir. Syntax foreground, private API ve TextKit 1 kullanılmaz.
- Folding özgün SQL'i koruyan source projection'dır. Başlık/caret/viewport anchor korunur; +/− gösterimi gerçek durumu izler. Gereksiz tam metin sıfırlama/animasyon/scroll yoktur; gizli hedefe gezinme projection'ı açar.
- Çift tık kelime seçimi/eşleşme vurgusudur; dirty/undo veya SQL değiştirmez. Boyama native mouse tracking sonrasına kalır; @/@@/# ve composed Unicode korunur. Tanıma geçiş command-click/⌘B ile ayrıdır.
- BEGIN/END, CASE/END ve parantez eşleri 250.000 UTF-16 lexer bütçesinde bulunur; CASE ve parantez ayrı stack kullanır, GO sınırdır. Transaction/dialog BEGIN ve END CONVERSATION blok sayılmaz; yorum/literal/quoted identifier dışlanır. Eşler viewport dekorasyonudur; gizli eş çizilmez. Ayarlanabilir Ctrl+Shift+M iki yönde gider.
- Çok satırlı BEGIN/END blokları soluk dikey kılavuzla gösterilir; tek caret'in içindeki en dar blok accent ile belirginleşir. SQLBlockStructure eşleştirme/gezinme ve kılavuzlar için ortak lexical snapshot'tır; EditorBlockGuides SQL değişene kadar bunu önbellekte tutar. Çizgi açılış satırının girintisine hizalanır, tab/space native dört boşluk aralığını izler; iki uç ekran dışındayken görünür alanda devam eder. Gizli uçlu/tek satırlı/eşleşmemiş bloklar çizilmez; görünür üst blok folded projection'a uyar. Çizim yalnız TextKit 2 viewport overlay'indedir; metin/foreground/undo/odak değişmez. CASE/parantez sözcük vurgusu ve eşe gitme korunur; bunlar BEGIN/END kılavuzu üretmez.
- ⌥←/→ SQLCaretNavigation değişken/temp/Unicode kelime/sayıları bütün, operatör/noktalama ayrı durak sayar. Quoted/yorum içinde kelime hareketi kalır. ⌘←/→ önce kod sınırına, sonra fiziksel satıra gider; CRLF bölünmez. Shift seçim yönü selectionAffinity ile korunur; sıradan/dikey oklar, IME/çoklu seçim native kalır. Hareket yalnız caret başını kaydırır ve yazım grubunu ayırır; kaynak/renk/undo üretmez. Çevre bütçesi yaklaşık 8.200 UTF-16; 4.096'yı aşan tek token ara durak alabilir.
- Tırnak eşleme yalnız fiziksel keyDown, editable/tek seçim/IME dışı girdide çalışır. 250k lexical bağlam yorum/string/bracket/quoted identifier'ı korur; metin ortasında gereksiz kapanış üretmez. Marker'lar affected-range ile kayar; aynı kapanışı skip, boş çifti Backspace ile silme ve kod seçimini sarma desteklenir. Paste/insertText eşlemez; tam SQL değişimi marker'ları geçersizleştirir.
- Formatla kaynak değişmiyorsa native metni yeniden atamaz; gerçek değişim/undo/redo renk cache'ini geçersizleştirir. Literal, source projection, undo ve SSMS renkleri korunur.

### SQL renkleri ve değişkenler

Ana editör, Agent, salt okunur SQL ve fark görünümü SQLSourceHighlighting/StudioTheme paletini paylaşır. Ana editör seçimi StudioTheme.editorSelection zeminini kullanır; selectedTextAttributes içinde foreground atamayın, SQL sözdizimi renklerini koruyun. Typing renkleri completion debounce'unu beklemez; caret literal içindeyse typingAttributes o rengi taşır.

| Kategori | Açık | Koyu |
|---|---|---|
| Keyword | `0000FF` | `6CA0FF` |
| String / tanımsız değişken | `FF0000` | `FF8080` |
| Yorum | `008000` | `6A9955` |
| Sistem fonksiyonu | `FF00FF` | `E88BFF` |
| Sistem nesnesi | `008000` | `72C77B` |
| Sistem procedure | `800000` | `D88585` |
| Operatör | `808080` | `B4B4B4` |
| Satır numarası | `008080` | `4EC9B0` |
| Düz SQL / kullanılmayan değişken | `000000 / 929292` | `D4D4D4 / 808080` |

Koyu palet uygulama uyarlamasıdır; Microsoft'un birebir koyu paleti diye sunulmaz. UI palet değişimi SQL kategorilerini değiştirmez.

- TSQL.variableAnalysis 250.000 UTF-16 bütçesinde DECLARE sırası, formal parametre, RETURNS @table ve GO kapsamını ortak çözer. Önceden tanımlanmamış @referans kırmızı/tooltip'li; lexical kullanılmayan DECLARE/SQL routine formal adı soluktur.
- @@, yorum/string/quoted identifier ve EXEC isimli argüman etiketi yerel hata sayılmaz. Etiketin sağındaki değer/return değişkeni gerçek referanstır; etiket aynı adlı yereli kullanılmış yapmaz. Atama kullanım sayılır; data-flow/dead-store veya dinamik SQL çözümü iddia edilmez.
- Çoklu DECLARE içindeki nested CASE/END, tür/fonksiyon virgülleri tanımı kesmez. Yarım/CLR/EXTERNAL NAME imzaları ve RETURNS @table soluklaştırılmaz. Gerçek referans katlanmış gövdede olsa da kullanımı korur; tema/kaynak/undo/fold rengi günceller, kaynak değiştirilmez.
- SQLComments seçilen fiziksel satırları girintiden sonra `-- ` ile yorumlar; tümü yorumluysa açar. ⌘/ toggle, ⌥⌘/ yalnız kaldırmadır; seçimsiz mevcut satır, sonraki satır başında biten seçim yalnız önceki satırlardır. Unicode/CRLF/boş satır/girinti/iç yorum korunur; tek replacement/undo ve gerçek source seçimi kullanılır.
- Düzen/sağ tık/seçim yanındaki native yorum düğmesi aynı yolu çağırır. IME/çoklu seçim/read-only durumda kapalıdır; 28×26 pt ikon düğmesi yalnız tam fiziksel satır veya çok satırlı seçimde, seçim dışında görünür; kelime/yalnız boşluk seçimi, sürükleme ve tamamlama/parametre popup’ı sırasında gizlenir. Düğme odağı/yerleşimi bozmaz. Türkçe Q `/` için Shift+7 gereksinimi kayıt/eşleştirmede normalize edilir. Kısayollar Ayarlar'dan değişir; standart undo alias'ları başka eyleme atanamaz.

- SQL yerleşik fonksiyon kataloğu TSQL.functions, parantezsiz ifadeler bareFunctions ve tablo değerli yerleşikler tableFunctions ile ayrılır. Tamamlamada gerekli `()` eklenir, caret içine gider; sonraki lexical token `(` ise yinelenmez. LEFT/RIGHT JOIN gibi keyword bağlamına parantez eklenmez. Bilinen sistem yordamları yalnız EXEC/EXECUTE içinde uygun unqualified/sys/dbo adlarında tanınır; bütün sp_ adlarını veya tablo kullanımlarını geçerli saymayın. Table-valued yerleşik çağrı FROM/JOIN/APPLY içinde önerilir; sistem nesnesi yeşili, scalar fonksiyon magenta, yordam maroon paleti korunur.

### ⌘Enter ifade seçimi

- ⌘Enter ve Sorgu → İfade / Blok Çalıştır native responder üzerinden odaktaki ana/detached editörü hedefler. Seçili source SQL doğrudan yürür; tek ayrıştırılmış ifade bütün metni yürütür; çoklu ifade native satır/SQL özeti menüsünde ↑↓/Enter/fare ile seçilir, Escape SQL göndermez. İmleçteki ifade işaretlidir; batch (GO tekrarı dahil) ve Tüm SQL seçenekleri vardır. F5/toolbar mevcut seçim/tüm belge yolunu korur; bağlantı yalnız onaylanan yürütmede denenir.
- SQLExecutionScopes core lexical aralıkları 250k UTF-16/30k token/200 yürütme seçeneği bütçesinde worker’da bulur. Literal/quoted/comment, parantez/CASE, CTE/UNION/INSERT SELECT ve dengeli BEGIN/END içi parçalanmaz. IF/WHILE, transaction, rutin DDL, TRY/CATCH/MERGE gibi belirsiz kapsamlar batch bütünü kalır; tam T-SQL parser veya otomatik değişken/USE bağımlılık çözümü iddia edilmez. Ayrıştırma bütçesi/SQLCMD durumunda yalnız açık tüm SQL seçimi kalır; kendiliğinden fallback yürütme yoktur. LF/CRLF/CR/Unicode satır başlangıçları analiz worker’ında bir kez hesaplanır; menü her ifade için kaynak önekini yeniden taramaz. Her seçimin ham source dilimi gönderilir; editör SQL/seçim/undo değişmez. Source/request/DB/server generation/busy/IME/readonly kontrolleri geç sonucu veya eski menü seçimini engeller.
- Referans: [DataGrip Run queries](https://www.jetbrains.com/help/datagrip/run-a-query.html).

### SQL biçimlendirme

- SQLFormatter lexer temelli boşluk/keyword-case düzenler; alias/identifier/literal/comment/operator/virgül/statement token’ı üretmez veya silmez. Keyword ile aynı yazılan bağlamsal identifier’lar (AS Go/Try/Catch, dbo.Go ve standalone olmayan GO) harf biçimini korur; tam belge eşlik denetimi bu adların değişmesini de reddeder. Palette keyword sayılan fakat SQL Server’da reserved olmayan belirsiz adlar ihtiyatlı korunur; tam parser olmadan OFFSET/ROWS/ONLY/OUTPUT/INCLUDE gibi sözcüklerin harf biçimi zorlanmaz. CTE/SELECT/JOIN/ON/CASE/nested query/INSERT/UPDATE/DELETE girinti ve liste kuralları aynı bounded yoldadır. INSERT kolon/VALUES çok satırlı listesi yalnız dış DML parantezine uygulanır; içteki GETDATE()/NEWID() ve argümanlı fonksiyonlar liste biçimini miras alıp parçalanmaz. SQLCMD direktifleri değişmeden korunur; tam parser/semantik düzeltme değildir.
- SQLFormattingOptions keyword upper/lower/preserve, 2/4/8 boşluk, leading/trailing virgül, çok satırlı liste/koşul kırma ve 60–240 karakter satır genişliği tercihlerini taşır (varsayılan 120). Eski kayıtların eksik optional lineWidth alanı 120 olarak uygulanır. blankLineAfterSelect ve blankLineAfterDeclare optional tercihlerinin eksik değeri açık sayılır; önceki girinti/harf/virgül ayarları korunur. Tamamlanan SELECT ve ardışık DECLARE grubundan sonra bir boş satır bırakılır; CTE/UNION/alt sorgu içi ayrılmaz. İki seçenek SQL Editörü biçimlendirme kartında ve genel aramada bulunur. Ortak GO lexical denetimi CRLF satır sonunu kırparak sayı/yorumlu ayırıcıları tanır; GO SQL token/tekrar sayısı korunur. IF/WHILE, BEGIN/END, TRY/CATCH ve RETURN/DECLARE ayrı satır sınırlarını kullanır; uzun üst düzey aritmetik/string birleştirmeleri devam girintisiyle kırılır, mevcut operatör devam satırları korunur; literal ve scientific notation parçalanmaz. Ayarlar taslağı Uygula’ya kadar saklanır; seçenekler genel aramada bulunur. TSQL.format API’si varsayılanlarla uyumludur.
- Formatla, GridShortcuts.format eylemidir; varsayılan ⌘⇧F, Ayarlar → Kısayollar’da anlık değiştirilir. Menü/sağ tık/toolbar tooltip güncel binding’i izler; native editör callback’i odaktaki sorguda çalışır, detached editör aynı controller yolunu kullanır. Standart Bul/undo ve diğer atanmış kısayollarla çakışma reddedilir. Seçim varsa yalnız source-projected aralık, yoksa tüm editör biçimlenir. Parça ve yerine yerleştirilmiş tam belge lexical token/yorum/literal/identifier ve GO separator satır eşliğini geçmelidir; literal/yorum/identifier içinden başlayan riskli seçim değiştirilmez. CRLF ve GO tekrarları korunur. Tam belge formatında caret lexical token ordinal’iyle yeni metne eşlenir; caret’in viewport içindeki konumu korunur, EOF’a taşınmaz. Seçim formatında biçimlenmiş parça seçili kalır. Tek undo, syntax/IME/read-only/fold sahipliği korunur; SQL otomatik yürütülmez.
- İş bütçesi 250.000 UTF-16 / 30.000 token’dır; büyük giriş özgün kalır. 50.000 üstü biçimlendirme detached worker’dadır; source/revision/selection değişmişse geç sonuç uygulanmaz. Diğer editör işlemleri bekletilmez.

### INSERT kolon/değer eşleştirmesi

- SQLInsertMapping açık kolon listeli INSERT ... VALUES ve INSERT ... SELECT projection ordinal'lerini source UTF-16 aralıklarıyla çözer. TOP/INTO/quoted target/hint/OUTPUT, çok satırlı VALUES, nested function/subquery/CASE ve literal/comment virgülleri ayrılır; GO ve diğer INSERT'ler kapsamı geçmez. Bütçe 250k UTF-16 /30k token, en çok 2.100 kolon/1.000 VALUES satırıdır. SELECT TOP/DISTINCT, nested expression/CASE/alt sorgu ve set-operation kolları ayrı listeler olarak çözülür. SELECT * / alias.* ve eşit olmayan projection sayısı reddedilir. Eksik/fazla kolon ve implicit fiziksel sıra metadata’dan tahmin edilmez; kapanmamış VALUES listesi tamamlanana kadar eşleştirme sunulmaz.
- Tek caret/değer içi veya tek ifade seçimi hedef kolon ve o satırın değerini accent viewport dekorasyonuyla eşler. Kolona tıklama bütün VALUES satırlarındaki aynı ordinal'i vurgular. Fold'da gizli aralıklar çizilmez. SQL/typing attributes/syntax/undo/dirty/odak ve gerçek yürütme değiştirilmez; highlight katmanı mouse-transparent'tır.
- 280×72 pt native önizleme yalnız fare seçimi tamamlanınca açılır; anchor görünür expression/caret’in clip koordinatına çevrilir, ayrı pencere köşesine bağlanmaz; hedef tablo, kolon, ordinal/satır ve değeri gösterir. Yazımda kendiliğinden açılmaz; Escape, scroll, kapsam dışı seçim, completion veya routine yardımında kapanır. Preview için SQL/metadata/Keychain/ağ okunmaz. Kaynak snapshot'ı önbellektedir; 50k üstü analiz detached worker'da, source/generation/iptal kontrollü yayınlanır; eski cevap yeni metne uygulanmaz.
- Referans: [DataGrip INSERT column hints](https://www.jetbrains.com/help/datagrip/inlay-hints.html). Bu uygulama source içine inlay metni enjekte etmez; caret eşleştirme ve tıklama önizlemesi ayrı native dekorasyondur.

- Kolon/fonksiyon hover bilgisi SQLObjectHover ile sys.columns ve scalar sys.parameters parameter_id=0 ayrımından gelir; user_type_id yanında system_type_id’den temel sys.types satırı çözülür. Alias adı + temel SQL tipi/uzunluk/precision/scale birlikte gösterilir; CLR/çözülemeyen türde temel tip uydurulmaz. Kolon verilmediyse yalnız fonksiyon türleri sorgulanır; tablo/view nesnesinin kolon-listesi popup’ı query ve decode sınırında kapalıdır. Bilinen tablo/view editörde metadata çağrısından önce elenir; kolon hover’ı ve scalar/TVF ayrımı sürer. scalar dönüş tipi ile table-valued TABLE/çıktı kolonları karıştırılmaz. EditorObjectHover aktif alias bağlamını kullanır, belirsiz çoklu nesne ve katlanmış source eşleşmezliğinde tahmin yapmaz. Explorer kolon/parametre detail alanını, fonksiyonda ayrı metadata yolunu kullanır. ConnectedServer başına SQLHoverMetadata tek fiziksel uçuş, 64 adet/5 dakika generation kapsamlı bellek cache’i, en çok 8 hedef/8.193 satır/8 MB/5 sn sınırı uygular; query oturumuna dokunmaz. Source/DB/generation/hover revision geç sonucu engeller. TVF çıktısı sys.columns.column_id sırasıyla eksiksiz çözülür; kısmi metadata tam liste diye sunulmaz. SharedUI/SQL/FunctionReturnPreview sıra/kolon/veri tipi kolonlarını native tabloyla hizalar; tüm satırlar korunur, uzun içerik yatay/dikey kaydırılır, üç noktayla kesilmez. StudioHoverHelp nonactivating paneli kullanır; yalnız TVF listesi içindeki kaydırma paneli açık tutar ve editör odağını almaz. Token ile panel arasında 180 ms geçiş toleransı vardır; çıkış/tıklama/klavye/editör kaydırması ve kapanış iptal eder. Diğer hover yüzeyleri ignoresMouseEvents kullanır; metadata hatası modal uyarı açmaz.

### Tamamlama ve parametre yardımı

- Tamamlama detached analiz ve iptal kullanır; source/caret/catalog/DB/generation güncelliği doğrulanır. Varsayılan 260 ms, aralık 50–1000 ms; Ctrl+Space beklemez. Öneri üst sınırı 100'dür.
- SELECT/ifade: SQL/CLR scalar fonksiyon. FROM/JOIN/APPLY/virgüllü FROM: tablo/view/synonym ve SQL inline/multi-statement/CLR TVF. DML hedefi: tablo/view/synonym. EXEC/EXECUTE/return assignment: procedure ve SQL Server'ın çalıştırabildiği scalar fonksiyon; TVF yoktur.
- Tablo/view/synonym, routine/scalar, kolon, keyword/builtin ve tanımlı değişken önerileri metni içeren eşleşmeleri sunar; tür/şema/kapsam filtreleri öneri sınırından önce uygulanır, başlangıç eşleşmesi diğer içeren eşleşmelerden önce gelir. Boş @ bütün geçerli batch tanımlarını korur; @ öneki interior değişken eşleşmesinin parçası değildir. Niteliksiz ifade/WHERE/ON/GROUP BY/ORDER BY/SET bağlamında kapsam kolonları fonksiyon ve keyword’lerden önce gelir. Liste doluysa yalnız bir scalar aday son sıraya ayrılır; fonksiyonlar 25 kolon slot’unu düşüremez. AS alias ve tamamlanmış operand sonrasında yanlış kolon/fonksiyon önerisi verilmez; keyword’ler clause’a göre önceliklenir. Alias qualifier gerçek kolonlarını tercih eder.
- INSERT [TOP] [INTO] hedefinin açık kolon listesi parantezi ve tablo hint’i ayrılır; her virgülde/tek harfte/boş kolonda yalnız hedefin henüz kullanılmamış kolonları unqualified önerilir. Düzenlenmekte olan kolon duplicate filtresinden muaftır; liste kapalı/açık olabilir, literal/comment/GO/sonraki statement bağlamına sızmaz. Otomatik popup için insert kolon konumu objectCompletion taşır. CTE/derived/temp/table-variable ve SELECT/UNION/nested sorgu kapsamı korunur. UPDATE/DELETE hedef alias'ı gerçek FROM/JOIN kaynağına bağlanır; sahte binding gölgelemez. OUTPUT inserted/deleted ilgili hedef bağlamındadır. Tek @ yalnız önceki lexical tanımları önerir; sonraki tanım/GO/@@ dışlanır.
- Kolon metnine yalnız sorguda var olan niteleyici eklenir; tek alias'sız kaynakta çıplak ad kullanılır. Otomatik alias yalnız tablo/view kabulündedir; NOLOCK varsayılan kapalıdır, dirty-read etkisi açıklanır. Fonksiyona alias/NOLOCK eklenmez.
- SELECT/FROM fonksiyon kabulünde eksik `()` eklenir, caretOffset imleci içine koyar; mevcut parantez/argüman çoğaltılmaz. FROM/EXEC boş/tek harfte, kapsam kolonu/kullanıcı scalar adı tek harfte mevcut debounce ile açılabilir. Kabul SQL çalıştırmaz ve tek undo'dur.
- Şema ve köşeli parantez tercihleri bağımsız, varsayılan true'dur. Yazılmış qualifier silinmez; aynı adlı çok şemalı nesnede ve bütün kullanıcı fonksiyonlarında (SQL/CLR scalar ve TVF, EXEC dahil) şema zorunlu korunur. Yerleşik sistem fonksiyonlarına katalog şeması eklenmez. Parantez kapalı olsa da reserved/boşluk/özel karakter/uygunsuz başlangıç/`]` güvenli SQL.identifier ile yazılır; genel DDL/CRUD escaping değişmez.
- Suggestion.Kind/detail, label ve insertion text ayrıdır. Öneri satırı 26 pt, en çok 16 tam satır/100 öneri; ikon/tür/eşleşme vurgusu/sayaç/ipucu/AX vardır. Ekran üst-alt boşluğuna sığar, reuse edilir, sıfır otomatik inset ve açık contentSize kullanır; tek satır da görünürdür.
- İlk öneri görünür/seçilidir; eşleşme bitince kapanır, aynı caret selection bildirimi kapatmaz. Popup key monitor yalnız kendi popup/aktif editöründedir; ↑↓, Page, Home/End, Shift-Tab, Tab/Enter/Escape işler, Command/Control/Option'ı çalmaz. Seçim görünür tutulur; monitor kapanış/deinit'te kaldırılır.
- SQLRoutineCall EXEC/fonksiyon çağrısını 100k UTF-16/4.000 token ile çözer; nested çağrı, string/comment virgülü, isimli/ordinal argüman, return assignment ve statement/batch sınırı korunur. Dinamik/cross-DB çağrı tahmin edilmez.
- Parametre yardımı 180 ms veya Ctrl+P, Escape kapanıştır; ID sırası, tür/OUTPUT/READONLY/aktif argüman gösterilir. Metadata ayrı bağlantıda 2.100 satır/1 MB/15 sn; cache server UUID/DB/generation/nesne anahtarlı 64 kayıt/5 dk'dır. Kaynak/caret/DB/generation/odak/IME/seçim/fold korumaları vardır; default/zorunluluk uydurulmaz.
- CREATE/ALTER/CREATE OR ALTER PROC/FUNCTION imzası çağrı değildir; başlıkta otomatik/Ctrl+P popup veya metadata işi yoktur. SQLRoutineDefinition formal/default/RETURNS/EXECUTE AS ile gövdeyi ayırır; gövdedeki gerçek çağrılar korunur. Yorum/string/output alias/uzak çok parçalı adlarda yanlış yerel öneri üretmeyin.
- Tanıma geçiş ağdan önce yükleme sekmesi açar; yüklerken düzenleme/yürütme kapalı, diğer sekmeler açıktır. Aynı server/DB/schema/name birleşir; objectID çözülünce mevcut objectEditorKey sekmesi korunur. Kapanmış/generation değişmiş hedefe geç yanıt yazılmaz. Ham moduleOriginal ile ALTER edit baseline ayrıdır; sorgu bağlantısı tanım hazırken açılır.

## Sonuçlar, veri düzenleme ve performans

- Editör viewport genişlemesinde TextKit fragment yerleşimi aynı resize transaction içinde hazırlanır; tam SQL genişlik/satır ölçümleri kaynak veya font değişimine kadar önbellektedir. INSERT önizlemesi gerçek clip origin değişiminde kapanır; syntax yeniden çizimi veya aynı-origin bounds bildirimi önizlemeyi kapatmaz.
- SQLReadOnlyPreview tam metni korur; CR/LF/CRLF/NEL/Unicode satır ayırıcıları ve çok geniş satırlar geometriden kırpılmaz. Nesne indeksinin modül rowset’i DATALENGTH(definition) taşır; decoder UTF-16 byte uzunluğunu doğrular ve eksik gövdede önceki snapshot korunur. Mevcut hücre/grup bütçeleri korunur; çevrimdışı eksik eski tanım sunucudan okunmadan yeniden oluşturulamaz.

Alt durum çubuğu ortak statusCanvas açık/koyu token’ını kullanır; ayrı ayraç son çalıştırma tarihini gösterir. QueryDocument.lastExecutionDate yalnız gerçek yürütme başlarken atanır; sekme/bağlantı değişimi diğer belgenin tarihini taşımaz.

### Bütçeler ve snapshot

| Kapsam | Korunacak sınır |
|---|---|
| Normal yürütme | Doğrulanmış SELECT sonucu başına 50.000 satır; toplam 100 gerçek rowset (row-count bildirimi hariç), yaklaşık 2 MB/hücre, 64 MB/60 sn |
| Büyük okuma | Satır sınırı en çok 5.000.000; 50.000 üstünde toplam 2 GB/600 sn |
| SELECT satır sınırı / otomatik yenileme | 1–5.000.000 satır / özel 1–3.600 sn |
| Clipboard | 10.000 satır / 16 MB |
| Ayrı veri editörü / değişiklik | İlk 200 satır / en çok 400 değişmiş satır |
| Edit hazırlığı cache | 1 MB/kayıt, 128/scope, toplam 4.096 kayıt/16 MB, 24 saat |

- Grid native cell-based NSTableView'dır; görünür hücreleri reuse eder. Hücre başına SwiftUI/Auto Layout veya tüm veriyi ölçme eklemeyin. Disk ResultSpool, sınırlı cache ve ordinal kolon kimliği korunur.
- loadedResult tam snapshot'tır. RowCollection.prefixSnapshot O(1) kaynak-sıralı ilk satır görünümüdür; sınır değiştirmek SQL çalıştırmaz, yükseltmek yalnız okunmuş veriyi geri gösterir. Filtre/sort prefix'ten sonra uygulanır.
- Grid/frozen pane/gutter/sayfa/kopyalama/export aynı capped snapshot'ı kullanır. Sınır değişimi sayfa/seçimi sıfırlar, pin/kolon/rule'ı korur; edit mode veya export varken kapalıdır. SINIRLI yerel prefix, KISMİ gerçek truncation'dır; history/doc.rowCount gerçek okunmuş toplamdır.
- Sonuç toolbar’ı tek Satır sınırı değeri sunar; ayrı sayfa boyutu alanı/menüsü yoktur. Düz menü 10/100/250/500/1.000/Tümü/Özel/Varsayılan Yap sunar; kayıtlı tercih yoksa 500 kullanılır. Tümü depoda 0, yürütmede Int.max olarak taşınır; 2 GB/600 sn güvenlik bütçesi korunur. Salt okuma ile DML çıktı tüketme politikası ayrı preserveExecution bayrağıyla belirlenir. Console grid’i pageSize=0 ile capped snapshot’ın tamamını gösterir; gereksiz sayfa okları gizlenir. Hazır/özel/default seçenekleri aynı değeri yönetir; yeni sorgu varsayılanı eski gridReadLimit değeridir, legacy gridDefaultPageSize console’da kullanılmaz. CSV/JSON görünen filtre/sıralama snapshot’ını dışa aktarır.
- QueryDocument yürütme Limits snapshot’ında readOnlyRowLimit=true kullanır. TSQL.usesResultRowLimit bütün GO batch’lerini salt okunur olarak doğrular; SELECT içeren INSERT/UPDATE/DELETE/EXEC veya karma batch salt okuma sayılmaz. DML/EXEC seçili satır sınırını driver’a/fetch’e/yerel prefix’e uygulamaz. Metadata çağrılarının mevcut ayrı satır bütçeleri korunur.
- ODBC SQLRowCount bildirimleri gerçek rowset kotasına dahil değildir; ardışık sayısal bildirimler toplamı korunarak birleştirilir. DML/EXEC için rowset/byte görüntüleme bütçesi dolarsa çıktı kısmi işaretlenir ve kalan çıktılar SQLMoreResults ile saklanmadan tüketilir; görüntüleme nedeniyle SQLCancelHandle çağrılmaz ve sonraki GO batch’i bütçe yüzünden atlanmaz. Gerçek hata, timeout veya açık iptal davranışı korunur; SQL iptali rollback değildir. Canlı yazma sonucunu hata/iptal sonrası otomatik yeniden denemeyin.
- Yeni normal execution generation'ında eski grid/plan child controller'ları debounce dışında temizlenir; akışın güncel rowset'leri eklenir. Yenilemede eski snapshot/seçim/genişlik korunabilir, finalde artık olmayan sekmeler kaldırılır. Rowset yoksa Messages gösterilir.
- Filtre/sort/export iptal ve revision korumalıdır; geç worker sonucu yayınlanmaz. Export sibling temp'ten atomik değişir, hata/iptalde hedef korunur. O(n) indeks/anahtar belleği vardır; sınırsız/sabit bellek iddiası yoktur.
- Rows.source/SQLResultSource yalnız bellektedir; sonuç SQL'i yürütme snapshot'ından gelir, güncel editörden tahmin edilmez. Düz SELECT/CTE/UNION ordinal eşleşmesi doğrulanır; tek EXEC çıktıları çağrı metnini paylaşır. Belirsiz karma akışta statement uydurulmaz, SQL grubu gösterilir; GO/tekrar grup numarasını korur.
- Results/plan hover önizlemesi 200 ms, en çok 2.000 karakter/20 satır ve nonactivating'dir; çıkış/tıklama/kaynak/sekme değişiminde kapanır. Kaynak grid hücrelerine/export/diske eklenmez. SQLReadOnlyPreview ortak renk/font, native numara ve yatay scroll kullanır; tema seçim/viewport'u korur.

### Güvenli tekrar okuma

- Yenileme son başarılı SQL + gerçek DB snapshot'ını kullanır; editördeki sonraki metni çalıştırmaz. Yürütme sonrası SELECT @@TRANCOUNT, DB_NAME() probu değişmemiş execution/bağlantı/generation bağlamında snapshot'ı doğrular. DB adları case-sensitive korunur; geç probe snapshot'ı geçersizleştirir.
- Pasif Yenile somut nedeni tooltip/AX'de gösterir. Busy/offline/açık transaction/düzenleme/başarısız veya tekrar okunamayan SQL auto-refresh yapmaz. İlk başarılı tekrar okunabilir SELECT öncesi süre seçimi SQL çalıştırmaz.
- TSQL.canRepeatRead SELECT/WITH ve dengeli parantezleri sınırlı lexical olarak denetler. Başlangıç boş `;`, `;WITH`, çoklu SELECT/CTE desteklenir; yazma/EXEC/SELECT INTO/GO/sequence/kilit ipucu engelleri korunur.
- Yalnız başlangıçta literal/NULL initializer'lı yerleşik scalar DECLARE ve literal SET NOCOUNT ON/OFF kabul edilir; AS/virgül/precision/scale korunur. Diğer SET, gövde DECLARE/SET, expression/function/subquery initializer, TABLE/CURSOR/UDT reddedilir. DECLARE/SET sonuçları ayrıca satır editine açılmaz.
- Anonim `Tests/Fixtures/ParameterizedMonitoring.sql` özgün ve NOCOUNT önekli regresyon kaynağıdır; test bunu kendiliğinden canlı sunucuda yürütmez.

### Native grid ve kolon davranışı

- Sonuç açık temada beyaz zemin/başlık/araç alanı, çok hafif satır zemini ve sakin ayırıcılar kullanır; uygulama koyu temasına uyar. Başlık ad/tip için iki satır, genişlik native 11 pt semibold ad ve 9 pt tür ölçümünün büyüğü + ikon/kenar payıdır; auto-fit veya pin başlığı/türü daraltmaz. Filtre hit alanı 12 pt dış resize kenarından ayrıdır; sürüklemede açılmaz. Aktif filtre hafif zemin/alt accent ve ikonla, PK doğrulanmış edit metadata'sı sonrası anahtar ikonu ile gösterilir. SF Symbols tema/rol bazında sınırlı cache'tedir; hücre başına view/layout kurulmaz.
- Kolon filtresi doğrudan değer seçimi, arama, Tümü/Görünenleri seç/Seçimi kaldır, açılabilir Koşul ve Temizle/Uygula sunar. Filtre yalnız yüklenmiş capped snapshot'tadır; SQL çalıştırmaz. NULL/boş metin, nil (sınırsız) / boş seçim (hiçbiri), arama dışında kalan seçimler ve en fazla 500 değer bütçesi korunur.
- Seçim özeti grid içinde ayrı satır oluşturmaz; seçili sorgu/sonuç için Ready ve son çalıştırmanın bulunduğu ortak durum çubuğunda gösterilir. QueryController salt okunur text/help snapshot’ını ve dar selectionStatusChanged callback’ini sunar; hesap sonucu bütün çalışma alanını render etmez veya recovery kaydı başlatmaz. Ana/detached durum alanı kendi belgesini kullanır; Messages/Plan/çevrimdışı önizleme/gizli sonuçta özet gizlenir. Toplam yalnız tek görünür numeric kolondaki (bit hariç) dikey hücre seçiminde hesaplanır; iki yönde eşdeğerdir. Çok kolonlu/yatay seçimde Toplam —, Sayı tüm seçili görünür kolonların NULL olmayan hücre sayısıdır. Boş metin Sayı’ya dahildir, sayısal varchar dönüştürülmez. Tüm satır/#/⌘A seçiminde de yalnız tek görünür kolon varsa toplam yapılır. Frozen pane iki kez sayılmaz; canonical ordinal, filtre/sort/prefix/sayfa ve commit edilmiş draft snapshot’ı korunur; field-editor’ın commit edilmemiş metni hesaplanmaz. Kaynak Rows/SQL değişmez ve SQL çalıştırılmaz.
- ResultSelectionPresentation 120 ms debounce, iptal/revision ve fiziksel önceki işin bitmesini bekleyen tek worker kullanır; ResultSelectionSummary core işi utility detached worker’dadır. Seçim/snapshot/kolon görünürlüğü/draft değişince güncellenir, görünüm kapanınca iptal edilir; çizim/scroll olayında hesaplama yoktur. İndeksler MainActor’da satır dizisine açılmaz. En fazla 5.000.000 hücre / 128 MB sayısal metin / 10 sn; tek numeric metin 512 UTF-8 byte, exponent ±400/scale en fazla 400’dür. Bütçe, geçersiz numeric, stale mapping veya spool okuma hatasında kısmi sonuç gösterilmez; neden tooltip’tedir. Base-10 limb toplamı bigint/decimal(38,s), bilimsel yazım ve daha geniş toplamı Double/Decimal yuvarlaması olmadan korur. Bu yerel gösterilen sayısal metin toplamıdır; SQL Server’ın float hesaplama sırası veya sunucudaki bütün satırlar için SUM garantisi değildir.
- Bit false boş kontur, true StudioTheme.success dolgulu işarettir; NULL metindir. Ham 1/0/NULL ve clipboard/edit değeri değişmez. GridDataCell.copy(with:) bağımsız native hücre üretir; inherited ObjC shallow copy Swift-owned alanları paylaşmaz. Table/scroll/cell focus ring none, native seçim/klavye korunur.
- Sonuç grid/frozen scroll alanları noBorder/drawsBackground=false ve overlay scroller kullanır; kalıcı legacy şerit/kenar alanı ayırmaz. Mouse wheel/trackpad/klavye/native scrollbar erişimi ve iki pane dikey eşliği korunur.
- ResultRowGutter yatay clip dışında tek sabit yüzeydir; görünür satırları çizer. Sentetik row kolonu gizlidir; ordinal/pozisyon korunur. Numara kaynak satır indeksidir; filter/sort/page/edit işaretleri ve tık/Shift/sürükle/sağ tık korunur. Clipboard/export/SQL'e girmez; görünür numaralar AX çocuklarıdır. # başlığının tamamı native/AX düğmesidir; selectAllCells geçerli tablonun/sayfanın tüm görünür hücrelerini seçer ve ⌘A ile ortaktır. Geçersiz field-editor taslağı odağı bırakamıyorsa seçimi değiştirmez.
- Kolon arama varsayılan ⌘⇧J'dir; yazım, ↑↓, Enter/Escape ve sayaç desteklenir. Gizli/taşınmış kolon ordinal ile bulunur; başlık vurgusu yeni generation'da temizlenir, hücre değer/seçimi değişmez.
- Pin/unpin/tümünü kaldır header menüsündedir. Kolonlar pin sırasıyla numaranın sağına gelir; native taşıma/resize korunur, kaldırınca asıl pozisyona döner. Gizlemek önce unpin eder; field signature değişince pin temizlenir, aynı snapshot refresh'te kalır. Tercih yalnız ResultController'dadır.
- Frozen CopyTable ikinci sunumdur; Rows/spool/projection/pendingEdits tek sahibinde paylaşılır. selectionOwner/canonicalPosition ve clipboard sırası görünür pin+kayan kolonları izler; satır seçimi/dikey scroll iki yönde eşit, yatay bağımsızdır. Kayan alan için en az 160 pt ayrılır.
- Pin/unpin önce field editor'ı commit eder; draft her iki tabloda denetlenir. Header clone/rebuild sort descriptor callback'ini geçici bastırarak mevcut sıralamayı korur. Export özgün kolonları bir kez içerir; pin metadata SQL/değere girmez. Testler `resultsGrid`/`resultsFrozenGrid` kimliğini kullanır; ilk CopyTable varsayılmaz.

### Veri yazma güvenliği

- Sonuç edit eligibility SQL metninden tablo tahminiyle kurulmaz. Canlı sys.dm_exec_describe_first_result_set(...,1) ordinal kaynağı doğrular: tek yerel kullanıcı tablosu ve tüm kolonlar zorunludur; varsa PK sonuçta bulunur. Alias/sıra ve anahtarsız tam satır desteklenir; JOIN/toplama/çoklu sonuç/temp/remote/eksik projection/kısmi sonuç salt okunurdur.
- Edit hazırlığı cache'i endpoint/login/server UUID/DB + tam sorgu ve ordinal field name/type/size/scale/declaredType SHA-256 anahtarlıdır. İlk/eksik/bozuk/eski kayıtta DMF ve yalnız objectID/kolon/PK/özel tablo flag metadata'sı iki okuma isteğiyle alınır; indeks/trigger DDL üretimi yapılmaz. Cache hit de eligibility'yi korur; anahtarsız snapshot tekrar kullanılabilir. SQL, sonuç değerleri, default/computed SQL diske yazılmaz; kolon nitelikleri ve canonical hash saklanır.
- ResultEditingCoordinator yalnız tamamlanmış güvenli sonucun metadata'sını önceden hazırlar; edit modu açılmaz/SQL yazılmaz. Düzenleme isteği aynı uçuşu veya hazır bellek sonucunu kullanır; context server/profil scope/generation, result generation, DB, yürütülen SQL ve fields'tır. Eski iş fiziksel olarak bitmeden yeni okuma başlamaz; iptali dikkate almayan eski yanıt yeni bağlama yayınlanmaz. Hazırlık hatası kendiliğinden döngüde tekrarlanmaz; açık düzenleme isteği tekrar deneyebilir. Kapanış/değişen bağlam işi iptal eder; UI bloke edilmez.
- Gönderimde cache'e güvenilmez: canlı DMF ordinal kaynak, objectID ve canonical metadata hash; PK/type/baseType/nullability/generated/default/computed yeniden doğrulanır. Çözümleme veya metadata değişmişse reddedilir. İlgili katalog değişimi/başarısız canlı doğrulama edit cache'ini geçersizleştirir.
- Staged edit kaynak satır indeksine bağlı ayrı sözlüktür; spool değişmez. Normal PK düzenlenebilir, UPDATE özgün anahtarla bulur. IDENTITY/computed/rowversion/desteklenmeyen tür kilit ve açıklamayla korunur. NULL ayrı açık eylemdir; orijinale dönüş değişikliği kaldırır.
- Yeni/çoğaltılan satır negatif yerel kimlikle sayfa sonunda görünür; filter/sort gizlemez, spool/export'a girmez. Dokunulmayan alan DEFAULT, açık NULL touched'dır. Çoğaltma PK/generated/özel tür taşımaz; nonidentity anahtar tekrar girilir. Mevcut silme staged, yeni satır silme yereldir. Kopyalama staged değeri, filter/sort/export yürütülmüş snapshot'ı kullanır.
- Field editor taslağı commit öncesinde sözlük/spool'u değiştirmez; Escape iptal eder ve pending draft kapanış denetimine dahildir. ResultCellFormatter kolon başına, ResultFieldEditor tablo başına yalnız edit sırasında oluşturulur. Sayısal metin yazım sırasında, tür/aralık/precision/scale/NULL/uzunluk/binary/UUID/ISO tarih commit ve SQL üretiminde doğrulanır; alias baseType kullanılır, integer/decimal metni Double'a çevrilmez. Geçersiz taslak native odak değişiminde hücrede kalır; görünür hata ve pasif SQL önizlemesi vardır. Önizleme native editor'ı commit eder, salt okunur SQL ve hedef sunucu/DB gösterir. Düğme sabit yerleşimlidir.
- Yalnız Onayla ve Veritabanına Gönder yazar. SQL/sonuç generation/DB/server generation ve metadata yeniden denetlenir. Sonuç grid'inin DataEditScripts.primaryKeyOrOriginalValues politikası kullanıcının isteğiyle PK varsa WHERE'de yalnız özgün anahtar(lar)ı kullanır; PK değişimi SET'te yeni, WHERE'de eski değerdir. Diğer kolon/rowversion eşzamanlı değişimi bu modda denetlenmez; önizleme bunu açıklar. OBJECT_ID ve @@ROWCOUNT=1 transaction koruması kalır, query transaction etkilenmez.
- PK yoksa karşılaştırılabilir özgün kolonlar (varsa rowversion) ve XML/text/ntext/image açık dönüşümleri kullanılır. Aynı transaction'da UPDLOCK/HOLDLOCK + COUNT_BIG=1 ön denetimi ve DML sonrası @@ROWCOUNT=1 zorunludur; sıfır/çoklu eşleşme rollback verir, keyfi TOP 1 kullanılmaz. SQL alias type özgün DDL adı ile baseType/length/precision/scale olarak ayrılır; CONVERT temel tiptedir, anahtarsız string karşılaştırması byte eşliğini korur. CLR/table/çözülemeyen alias/spatial/sql_variant salt okunur ve eşleştirme dışında olabilir; tam eşzamanlılık güvencesi iddia edilmez. Ayrı nesne veri editörü DataEditScripts'in varsayılan optimistic PK/original/rowversion politikasını korur.
- Edit mode'da auto-refresh yoktur. Pending taslağı silecek execution/refresh/close uyarır; gönderimde execution/close engellenir. Başarı değişiklikleri temizleyip son SELECT'i yeniler; ağ hatasında commit belirsiz olabilir, otomatik yazma tekrarı yoktur. Önizleme değişince eski onay geçersizdir.

## Nesne yönetimi ve DDL karşılaştırma

### Tek nesne düzenleme

- Nesne kimliği serverID/database/objectID'dir. Ham moduleOriginal sunucu tanımıdır; SET/GO/ALTER hazırlanmış edit metni conflict baseline yapılmaz. Dosya dirty ve uygulanmamış nesne değişikliği ayrıdır.
- Gönderimden önce canlı tanımı tekrar okuyun; başarıda yalnız gönderilen snapshot baseline olur, eşzamanlı yeni edit bekleyen değişiklik olarak kalır. Atomik şema kilidi/üç yönlü merge güvencesi yoktur.
- Designer eksik/kısmi metadata'dan CREATE üretmez; mevcut tabloyu otomatik rebuild etmez. Desteklenmeyen nitelikler açıkça gösterilir. Tasarım/şablon SQL'i önce inceleme editöründedir; Veritabanına Gönder ayrı yazma yoludur.

### Karşılaştırma kapsamı ve sunum

- Explorer en çok iki DB node seçer; karışık root/nesne seçimi tek kalır. Pencere yalnız kaynağı doldurur; hedef açık kullanıcı seçimine kadar boştur. Aynı host/port/DB hedef listesinde ve yazmada reddedilir; kaynak çakışması hedefi temizler, yön değişimi atomiktir.
- Üst liste yalnız doğrulanmış farktır: tablo yalnız kolon özeti, view yalnız canonical SQL kodu; diğer destekli modüller kod farkıdır. İndeks/FK/check/depolama veya default constraint adı tek başına tablo satırı üretmez. View kodu aynıysa çıktı kolon/indeks farkı liste satırı üretmez; raw/structural hash güvenlik için korunur.
- Tek tarafta nesne/tür uyuşmazlığı farktır. Kısmi/şifreli/okunamayan metadata eşit sayılmaz; ayrı sayaç/durumdur, üst fark listesine sessizce başarı olarak konmaz. Aynı view kodunun structural farkı staging ile çözülmüş sayılmaz.
- Tek kompakt araç satırı ve alt sayaç kullanılır. Checkbox/toplu seçim yoktur; odaktaki tek uygun nesnenin lazy detay/taşıma önizlemesi vardır. Kod Farkı/Kolonlar tercihi nesne/recompare/geç yanıtta korunur; ilk tercih Kolonlar, desteklemeyen nesnede geçici Kod Farkı'dır.
- DDL kod/kolon ve taşıma görünümünde kaynak solda, hedef sağdadır. original/edited veri sözleşmesi değişmez; kaynak eklemesi yeşil, hedef kaldırması kırmızıdır. Diğer yönetim önizlemesi original-solda kalır. Dikey scroll eşzamanlı, yatay bağımsızdır; gutter/boş hizalama satırı kopyaya girmez.
- Inline SQL farkı 20 pt gerçek satır yüksekliği/usesFontLeading=false ve native fragment baseline kullanır; Consolas leading ile çizim yüksekliğini ayırmayın. Pane/ruler kendi sınırında kırpılır; ilk/10./son satır geometry korunur.

### Metadata, hash ve fark algoritması

- Sürüm kontrolü SERVERPROPERTY ProductMajorVersion için NULL güvenli normal CONVERT kullanır; eski DB uyumluluk düzeyinde TRY_CONVERT gerektirmez ve DB uyumluluk ayarını değiştirmez.
- SQL Server 2017+ katalogları ve iki DB'de VIEW DEFINITION gerekir. Bütçe 50.000 nesne/64 MB/4 MB cell/90 sn; aynı nesnede gereksiz body fetch yoktur, yalnız raw hash'i farklı modüller 64'lü sayfalarda okunur.
- Eşleme tam schema/name ve database-trigger scope ile case-sensitive'dir. CREATE/ALTER ve sp_rename'den kalan declaration adı normalize edilir; gerçek nesne/Unicode farkı birleşmez.
- Boş typed FOR XML PATH koleksiyonları ortak xmlText/ISNULL(...,N'') ile NULL güvenlidir. m.definition NULL boş tanım yapılmaz. Raw digest NULL ve issue boşsa decode açık hatadır; okunabilir nesneyi sessiz unavailable yapmayın.
- SQL code comparison türleri V/P/FN/IF/TF/TR/TRD'dir. Liste hash'i ve görünüm aynı SQLWhitespaceComparison sözleşmesini kullanır. Dış boşluk/girinti/boş satır/satır sonu önemsiz; token sırası/harfi/literal/quoted ad/yorum içeriği ve token bitişikliği korunur. Satır yorumu sonu boşluk ve yorum line ending normalize edilebilir; literal içi CR/LF gerçek farktır. Eşitlik/render cache UTF-8 byte düzeyindedir.
- SQL modülü diff global token hizasıyla yalnız gerçek değişimi boyar; aynı SQL'in reflow/girintisi bütün satırları değişmiş yapmaz. Unique-token/patience anchor ve bounded Myers ortak 2.000.000 iş/256 edit-distance bütçelidir; yalnız çözülemeyen parça sadeleşir. Pure insertion/deletion yerelleştirmesi kalan token akışı byte-exact eşitse kabul edilir. Satır hizası ortak monoton token ankrajlarından gelir; ayrı LCS tie seçimi sahte fark üretmez.
- Özgün metin/satır numarası/source range ile display CR/LF/CRLF ayrımı korunur. Uzun tekrar, uzak küçük değişiklik, nested comment, literal, çok karakterli operatör ve özgün kopya regresyonlarını koruyun. Tablo/synonym ve diğer genel farklar varsayılan exact diff kullanır; SQL canonical anahtarı yürütülecek kaynak yerine geçmez.
- Seçili nesne detayında canlı raw hash tekrar doğrulanır. Kod/kolon cache'leri ayrı 24 giriş/~2 MB'dır; SQL disk cache'ine yazılmaz. I/O ayrı metadata oturumunda, diff/hash/parsing worker'dadır; iki uç generation/request revision ve iptal korunur.
- Kolon karşılaştırması bağımsız sys.columns/sys.types okumasıdır: objectID/tür/izin header doğrulaması, en çok 30.000 kolon. Alias/base type, Unicode byte→karakter/MAX, precision/scale, NULL/sıra/collation/identity/computed/persisted/default/özel nitelikler karşılaştırılır. Okunabilirlik ve taşıma desteği ayrı durumdur; özel nesne incelenebilir ama eksik CREATE üretilmez.

### Taşıma güvenliği

- UI yalnız tek nesneli planı kabul eder; core yeniden kullanılabilir plan sınırı 100 nesne/900.000 karakterdir. Eksik bağımlılık ayrı açık işlemle taşınır. Önizleme kaynak/hedef tanımlarını ve ayrı Çalıştırılacak SQL'i gösterir; yalnız Veritabanına Gönder yazar.
- Preflight yalnız seçili owner ve güncel doğrudan bağımlılık inventory(keys:) kapsamını okur. Canlı kaynak/hedef raw hash/objectID/tür ve connection generation doğrulanır. SET ANSI_NULLS/QUOTED_IDENTIFIER ve trigger enable/disable korunur.
- Ayrı hedef oturumunda XACT_ABORT/TRY/CATCH transaction; modül batch'leri sp_executesql, SET ayarları dış oturumdadır. Yazma sırasında pencere/app kapatma engellenir. Preflight-yazma arasında atomik şema kilidi yoktur; ağ kopmasında commit belirsiz olabilir, otomatik tekrar yoktur.
- Her plan UUID'lidir; yalnız en son plan gönderilir. Denenmiş/yerini yenisine bırakmış plan, refresh/recompare/baseline tekrar eşit olsa da yeniden gönderilemez.
- Başarı yalnız ilgili anahtarı iki uçta yeniden okur/refine eder; eşit satır çıkar, diğer liste/snapshot/cache/filtre/Kod-Kolon tercihi korunur. Hata/belirsiz commit/commit sonrası doğrulama başarısızlığı eski satır/odağı korur ve yalnız o nesneyi tekrar taşımaya kapatır. Seçili Nesneyi Yenile sadece o anahtarı okur, yazmaz; okunamayan yeni tanım eşit sayılmaz.
- Yeni standart tablo tam CREATE alır. Mevcut tablo yalnız desteklenen ADD/ALTER COLUMN/type/NULL/default farkını uygular; hedef PK/UQ/index/FK/check/depolama korunur. Default adı tek başına DDL üretmez, mevcut ad korunur/yeni adı SQL Server üretir. Korunan PK kolonunu NULL yapma önizleme öncesi reddedilir.
- Table/column drop, reorder, rename, otomatik rebuild veya bağımlılığı gizlice drop etme yoktur. Özel storage/temporal/ledger/graph/memory/column-set/encryption/CLR/bound-default/RLS, indeksli view, imzalı modül ve özel trigger sırası otomatik taşınmaz. İzin/owner/extended property/veri ve cross-DB/server adları taşınmaz/yeniden yazılmaz. Gerekli schema/filegroup/alias-type önkoşulları hedefte bulunmalıdır.

## Yardımcı özellik sözleşmeleri

### Activity Monitor ve Database Files

- Sunucu Activity Monitor ve SQL Agent Job Activity Monitor ayrıdır. DMV okuması metadata oturumunda salt okunurdur; KILL/DBCC/sayaç sıfırlama/yazma yoktur.
- Sunucu kartları aktif kullanıcı isteği, pozitif oturumlu bloklanan istek, devam eden backup ve açık transaction'ı gösterir. Aktif sayıda kendi sampler/backup/arka plan beklemeleri hariçtir; last_wait_type aktif işi gizlemez. Transaction oturum bazlıdır, sleeping ayrı dahil edilir; benzersiz dağıtık transaction sayısı değildir.
- Sunucu izleme 5/10/30/60 sn, duraklatma/elle yenileme; kapalı/minimized/tam örtülü/offline durumda otomatik okuma yoktur. Yeniden görünürlük yeni hız baseline'ıdır; generation/iptal geç yanıtı engeller. Bellekte en çok 181 örnek/15 dakika; 5/15 dakika görünümü vardır.
- I/O/batch/CPU monoton sayaç farkı / sunucu UTC farkıdır. CPU process_user_time_ms + process_kernel_time_ms ve mantıksal işlemci kapasitesidir; ring-buffer XML veya macOS CPU değildir. İlk örnek/restart/azalan sayaç/eksik kimlik/sıfır-negatif zaman/>180 sn aralıkta hız `—` olur. Stall-ms / işlem farkı gecikmedir; işlem yoksa sıfır uydurulmaz. İzin/eksik/eski veri ayrı gösterilir, grafikte boşluklar birleştirilmez.
- DBA ayrıntısı yalnız açıkken okunur: grup başına 30 istek, SQL 2.000 karakter; zincir 8 seviye/60 oturum/oturum başına 4 istek. Ortak bütçe 400 satır/5 sonuç/4 MB/10 sn'dir; plan-cache/XML/kilit/parçalanma taraması yoktur. Döngü/eksik/özel negatif kimlik/MARS/sınır görünürdür; son batch kilidi tutan ifade veya DMV örneği deadlock kanıtı sayılmaz. Estimated completion kesin bitiş değildir.
- Sorguda Tablo Olarak İzle mevcut aktif-istek sorgusunu açar; ilk başarılı SELECT sonrası 10 sn güvenli refresh yolunu kullanır.
- Database Files ayrı, yeniden kullanılan salt okunur penceredir; yerel DB/ad/yol filtreleri kullanır. sys.master_files en çok 5.000 dosya; seçili DB sınırlı sys.database_files/FILEPROPERTY, en çok 8 DB cache'dir. tempdb/FILESTREAM boyutu bilinmiyor kalır; kullanım/boş alan yalnız doğrulanmış normal ROWS'ta hesaplanır. MiB/GiB mantıksal tahsistir, fiziksel disk boşluğu değildir. Sorguda Aç açık eylemdir; çevrimdışı otomatik bağlanmaz.

### Favoriler ve geçmiş

- History başlık/arama/filtreleri dikeyde sabittir. Sunucu/DB aranabilir, durum/tarih kısa native Picker kalır; filtre grubu dar pencerede iki satıra geçer. Liste/SQL önizleme native VSplitView ile ayarlanır; minimum 820×560 pt içerikte kontroller boşluğu kaplayamaz. Metadata kolonları kompakt, SQL kolonu esnektir; süre sağa hizalıdır. Önizleme aynı kayıt seçimini kullanır; yalnız filtreleme/yazma SQL yürütmez veya yeni oturum açmaz.

- Favoriler actor/atomik favorites.json ile yereldir: 500 kayıt/16 MB, SQL başına 1 MB; klasör 0700/dosya 0600. Bozuk depo sessizce boşaltılmaz veya üzerine yazılmaz. Kapsam genel, profil UUID veya profil UUID + tam DB adıdır.
- ⌘⇧P seçici aktif ana/detached sorgunun server UUID + tam DB bağlamını yakalar; yalnız genel/o bağlantı/o DB listelenir. DB/bağlantı/genel sırası, arama/↑↓/Enter/çift tık/SQL önizleme/Yönet vardır. Başlık hedefi açıklar; arama kapsamı genişletmez, açılış SQL/yeniden bağlantı yapmaz.
- Yeni/Düzenle bağımsız Workbench editör penceresini weak presenter ile açar; modal SwiftUI sheet kullanılmaz. Kayıt tek uçuşlu, ilerleme/hata/retry görünürdür; atomik yazımdan dönen bellek sonucu için gereksiz read/decode yoktur.
- Close sonrası MainActor turunda auxiliaryWindows/contentViewController/subscription sahipliği temizlenir; aynı notification içinde erken serbest bırakılmaz. Async kayıt yalnız başladığı gerçek NSWindow'u weak kapatır; aynı UUID ile yeni açılmış taslağı kapatmaz. Native hit testing ve gerçek fare akışı regresyonu korunur.
- Explorer Favori Sorgular dalı çevrimdışı yerel açılır; node/seçim/genişletme korunur. Boş SQL yıldızı pasiftir. SQL eşleşmesi yalnız dış whitespace kırpar; harf/string içi değişmez. Açılan UUID sonra DB/bağlantı/genel önceliğiyle kaldırılır; başka DB/sunucu kaydı etkilenmez.
- Favori DB elle yazılmaz; bağımsız Catalog.databases okuması 5.000 satır/8 MB/15 sn'dir, Explorer görünürlük filtresiyle daralmaz. Offline/partial/hata mevcut DB'yi korur; profil değişiminde yeni profil varsayılanı kullanılır. Açık Sorguda Aç eylemi baseline'lı yeni sekmedir, SQL yürütmez; kayıtlı UUID yoksa kullanıcıya bildirilir. DB favorisi kayıtlı DB'yi; bağlantı favorisi aynı sunucu bağlamında seçilen DB'yi, başka bağlamda profil varsayılanını; genel favori açıkça gösterilen hedefi kullanır.
- History server UUID kullanır; eski ad bazlı kaydı yalnız tek eşleşmede açar. Filtre/sort/önizleme/kopya/kendi sunucusunda açma korunur. historyRetentionDays 1–3650, varsayılan 30; Ayarlar’da elle gün girilir, geçersiz taslak hiçbir ayar kaydedilmeden reddedilir; açılış/yeni kayıt/Uygula'da temizlenir. Bütçe 20.000 kayıt/16 MB; mevcut Codable kayıtları korunur.
- History/Favoriler Explorer/yerel yönetim listesi ve native seçici çift tıklaması, pencere açılışında yakalanan mevcut ana/detached editöre standart seçim değiştirme/imlece ekleme yapar; tek undo adımıdır, SQL yürütmez, hedef session/DB/baseline/favoriteID değiştirmez. Önizleme/IME/kapalı hedefte görünür hata verir. Yeni Sekmede Aç ayrı eylemdir.
- Kapatılan sekme History optional tabTitle/caret/selectionLength/reopenedAt alanlarıyla eski QueryRecord decode’unu korur. Açma yeni disconnected query oluşturur; SQL yürütmez, eski dosya yolu/ALTER conflict baseline bağlamaz. Command+Shift+T son kullanılmamış kaydı, Option+Command+H History’yi açar; GridShortcuts ile ayarlanır. History içinde Sorgular ve Kapatılan Sekmeler ayrı sekmelerdir. closedTabLimit, Ayarlar → Çalışma Alanı’nda elle 1–1000 (varsayılan 100) girilir. Her server UUID/veritabanında en yeni dolu sekmeler bu sayıyla korunur; boş/whitespace sekme kaydedilmez. Sorgu günü retention’ı kapatılan sekmeleri silmez; ortak 16 MB/20.000 disk bütçesi korunur. Geri açma kısayolu aktif server/DB kapsamındaki son kullanılmamış kaydı seçer; sekme sağ tık menüsü tıklanan belgenin server/DB kapsamını kullanır. History kapalıyken yalnız RAM’de aynı DB sayısı ve toplam 16 MB ham SQL sınırı vardır. Çalışan sorgu/transaction/pending write koruması kapanıştan önce geçer.
- QueryHistoryStore actor retention/JSON/atomik 0700/0600 yazımı yapar. StudioState fiziksel önceki yazıyı bekler ve ara snapshot’ları birleştirir; geç sonuç yeni belleği ezmez. Pending yazıda History eski disk verisini yüklemez. Normal çıkış flushHistory bekler; gerçek hata yalnız açık kaydetmeden çık seçimiyle atlanır. Bozuk/büyük dosya otomatik üzerine yazılmaz.
- History/recovery opt-in’dir, atomik 0700/0600 kullanır; SQL değer içerebilir, parola içermez. Test için kullanıcı geçmişi/favorisi silinmez veya okunmaz.

### SQL Agent, Linked Server, AI ve şablonlar

- Job History varsayılan son 7 gün/en yeni 500 özet; adım/retry istekle yüklenir. Durum filtresi iş sonucuna, alt adım kendi durumuna bağlıdır. Aynı properties/history penceresi yeniden kullanılır.
- Explorer Agent Jobs açık/yüklenmiş ve pencere görünürken 15 sn yenilenir; minimized/offline/kapalı dalda yeni otomatik iş yoktur. Kullanıcı kapatabilir; node/seçim/scroll korunur. Agent Activity Monitor 15/30/60 sn'dir.
- T-SQL adımı DB listesi metadata bağlantısından gelir; görünürlük filtresi uygulanmaz, eksik/partial/hata mevcut DB'yi değiştirmez. Non-TSQL adım salt okunur ve DB listesi okumaz.
- Tasarım SQL'i sekmede incelenir; Agent doğrudan komutu açık ayrı onay yoludur. Job/schedule version/tarih conflict, stored procedure return-code/hata rollback korunur. Start/Stop Job, OS Agent servisi yönetimi değildir.
- Linked Server mevcut SQL Server üzerinden sp_catalogs/sp_tables_ex/sp_columns_ex ile sağlayıcının rowset/kolonlarını okur; dört parçalı SELECT ve salt okunur properties sunar. Bütçe 5.000 satır/8 MB/30 sn; boşluk yokluk kanıtı değildir. Uzak parola/session/designer/DDL/routine yönetimi uydurulmaz.
- AI ephemeral URLSession, HTTPS veya loopback HTTP, redirects kapalıdır. API anahtarı yalnız açık panel belleğinde kalır. Yanıt inceleme editörüne gider, çalıştırılmaz. Şablonlar boyutu sınırlı Codable JSON'dur; bilinmeyen/binary kod yüklenmez.

## Keychain, kalıcı imza ve güncelleme

### Kimlik ve dondurulmuş parola bileşeni

- Bundle ID `local.mssqlstudio.app`, Keychain service `local.mssqlstudio.servers`; sürüm eklenmez. Açık kimlik `Sources/SQLServerKit/Resources/SigningIdentity.json`, sertifika SHA-1 `adce16b1a3567d8c5fe2ed261e89493611cb7b9d`.
- Sabit designated requirement: `identifier "local.mssqlstudio.app" and certificate leaf = H"adce16b1a3567d8c5fe2ed261e89493611cb7b9d"`. CDHash build'ler arasında değişir; kişisel sertifikada sabit DR tek başına file Keychain XARA/partition sürekliliği sağlamaz.
- ServerVault üretimde bütün credential create/read/update/delete/renew işlemlerini `Contents/Helpers/MSSQLStudioCredentials` üzerinden yapar; ana uygulamadan doğrudan fallback yoktur. Helper aynı sabit kimlikle, aynı executable/hash ile korunur. İlk eski-item onayı ve kilitli Keychain/sistem politikaları ayrı koşullardır; bir daha kesinlikle onay istenmez demeyin.
- **`Tools/CredentialAgent/main.m` protocol v1 dondurulmuştur; yeniden derlenmez veya yeniden imzalanmaz.** `installer/CredentialAgent-v1.json` source/archive/binary SHA-256 ve origin'i pinler. `scripts/credential-agent.py` ilk public `MSSQLStudio-CredentialAgent-v1.zip` archive'ını hash/imza doğrulayarak byte-for-byte kullanır. Helper v2 veya kimlik değişimi açık migration gerektirir.
- Helper private stdin/stdout pipe, parent PID dynamic SecCode/pinned DR ve istemcinin app/helper strict imza doğrulamasını kullanır. Bütçe 16 MB ileti/1 MB kayıtdır. Parola argüman/env/disk/log'a yazılmaz; socket/daemon/yetki toplama alanı yoktur.
- Normal kayıt yalnız data değiştirir; uygulama ACL/partition-list yazmaz. Exact service/account item silme yolu public SecKeychainItemDelete davranışını korur. Güvenlik yenilemesi yalnız bu service/account izinleridir; macOS onay isteyebilir, kayıt silmez/taşımaz.
- Keychain sıfırlamayın, genel partition-list/tüm uygulamalara erişim uygulamayın, Gatekeeper kapatmayın. Debug/ad-hoc kimliği yayın kimliğinin yerine koymayın.
- Özel anahtar/P12/parola Git, artifact, uygulama ve log'a girmez. Mevcut anahtarın yerelde var olduğunu varsaymayın veya secrets'ı çıkarmayın. CI yalnız MSSQL_SIGNING_P12/MSSQL_SIGNING_PASSWORD ile geçici 0600 dosya/Keychain kullanır; her sürümde yeni sertifika üretilmez. Anahtar kaybı/sertifika rotasyonu kontrollü migration'dır.
- `.github/workflows/signing-audit.yml` disposable runner'da `~/Library/Keychains/MSSQLStudio-signing-test-<UUID>.keychain` ve zorunlu partition ACL kullanır; `/tmp` eski keychain formatı kontrolü atlamamalıdır. Aynı helper farklı app build/path'inde CRUD yapar; doğrudan değişen app/ad-hoc/bağımsız launcher reddedilir. Bu sentetik ilk onay, gerçek login Keychain GUI/kilit politikası testi değildir; fixture her sonuçta temizlenir.
- scripts/build-app.sh sabit sertifika yoksa hata verir; ad-hoc fallback yoktur. Yerel kişisel sertifika Apple Developer ID/notarization değildir; PKG kapsayıcısında Developer ID Installer imzası yoktur. codesign ve Gatekeeper ayrı doğrulamalardır; reddi güvenliği azaltarak aşmayın.

### Updater ve kurulum

- Public latest update.json HTTPS'ten okunur. GitHub `/releases/latest/download/update.json` asset yoludur; Accept application/json kullanılmaz. octet-stream/no-cache/User-Agent/fresh redirect korunur. Transient HTTP/ağ için en çok 3 deneme/10 sn timeout/250–500 ms geri çekilme; cancellation/TLS/protokol/kalıcı 401/403/404 tekrarlanmaz. Hata gerçek HTTP/ağ nedenini gösterir.
- Kontrol/indirme/doğrulama tek uçuşlu, ilk ağ işinden önce görünür pencerededir; tekrar kontrol/kapatma işlemde pasif, diğer sorgular kullanılabilirdir. Güncel/hata aynı yüzeyde, hazır paket mevcut kurulum kararındadır.
- Manifest HTTPS/64 KB/JSON/version/SHA doğrulamasını korur. PKG installerURL/installerSHA256, payload SHA-256, bundle ID/exact sürüm ve sabit sertifika/DR strict/deep imzası doğrulanır. Betikli component paketleri reddedilir; özel shell replacement/rollback/.previous mekanizması eklenmez.
- macOS Installer `/Applications/MSSQLStudio.app` yerinde upgrade yapar; kullanıcı kurulumu tamamlar. Keychain/Preferences/Application Support korunur; otomatik yetki yükseltme, güvenlik bypass veya yedek silme yoktur. pendingInstallerVersion yalnız gerçekten kurulu sürüm/konumla tüketilir; eksik kurulum başarı sayılmaz, tamamlanmış kurulum için başarı modalı açılmaz.
- Kapanış hazırlığı ApplicationTermination tarafından normal uygulama döngüsünde tek uçuşla yapılır. MainActor asenkron geçmiş kaydı için terminateLater modal döngüsüne girilmez: ilk istek terminateCancel döner, kayıt ve son busy/transaction/DDL/kapatma doğrulaması tamamlanınca bir kez yeni terminate isteğine terminateNow verilir. Geçmiş kayıt hatasında iptal/kaydetmeden çık kararı korunur; iptal edilen güncelleme kapanışında watcher durdurulur.
- Güncelle ve Yeniden Aç / Güncelle ve Kapat / Vazgeç seçimi korunur. Yeniden açma watcher'ı eski signed executable'dan UI/Keychain/restore olmadan başlar; en çok 30 dk parent çıkışı + canonical hedef exact version/strict sabit imza bekler. Yalnız doğrulanırsa NSWorkspace yeni application instance açar; iptal/yanlış imzada açılmaz. Watcher frozen credential helper değildir.
- Eski updater yeni akışı okuyamıyorsa bir defalık doğrudan PKG yolu verilir; eski tag/asset yeniden yazılmaz. Her public yayında signed app'in kendi `--check-update-feed <beklenen-sürüm>` Foundation/URLSession ve bundle feed yolu exact sürümle doğrulanır. Python/gh/asset varlığı bu kontrolün yerine geçmez.

## Geliştirme, doğrulama ve yayın akışı

### Her değişiklikte

1. Üst protokol ve görev bazlı okuma kapsamıyla başlayın; Git durumunu ve ilgili feature/core/test kaynaklarını okuyun. Mevcut değişiklikleri ayırın; ilgisiz revert, temizlik veya format yapmayın.
2. Beklenen davranışı, kök neden kanıtını, davranışın sahibini ve etkilenen sınırları belirleyin. Refactor'da veri/oturum/undo/kalıcılık sahipliğini değiştirmeden küçük doğrulanabilir adımlarla ilerleyin.
3. İlgili sorunu gerçekten sınayan testleri ve gerekli native kontrolü çalıştırın. Düşük etkili belge/biçim değişiminde gereksiz ürün testi eklemeyin. Hata/davranış değişiminde geç yanıt/iptal/sahiplik veya veri bütünlüğü regresyonunu sınayın; yalnız uygulamayı taklit eden test yazmayın.
4. Kaynak ekleme/taşımada Xcode senkronizasyonu, mimari denetimi ve gerekli Release derlemesini yapın. Kontroller geçince yeni hata/değişiklik yoksa sebepsiz tekrar etmeyin.
5. İlgili kuralları burada, kullanıcı başlangıcını README'de, tarihli kanıt/açık sınırı TEST-REPORT'ta güncelleyin. Kısa sonuç raporunda üst protokoldeki kanıt ayrımını kullanın.

### Aşamalı doğrulama ve tekrar sınırı

Bu sıra mevcut test/derleme/yayın şartlarını değiştirmez; kontrollerin ne zaman genişletileceğini belirler. Aşağıdaki komut listesi her görevde körlemesine çalıştırılacak bir liste değildir.

| Aşama | Ne zaman ve ne doğrulanır? |
|---|---|
| Belge/biçim | İçerik, bağlantı, sözleşme ve diff tutarlılığını kontrol edin; düşük etkili değişiklik için gereksiz ürün testi eklemeyin. |
| Hedefli regresyon | Hata/davranış değişiminde ilgili suite/test ile başlayın; gerçek hatayı ve etkilenen iptal/geç yanıt/sahiplik/veri bütünlüğü sınırını sınayın. |
| Etki alanını genişletme | Ortak model/servis, oturum, kalıcılık, SQL çözümleme veya UI bileşeni değiştiğinde onu kullanan etkilenen yolları doğrulayın. Etki sınırı güvenle daraltılamıyorsa tam suite çalıştırın. |
| Derleme ve native kontrol | Kaynak ekleme/taşımada Xcode senkronizasyonunu, mimari denetimini ve gerekli Release derlemesini tamamlayın; UI davranışında ilgili izole native/smoke kontrolünü uygulayın. |
| Paket ve public yayın | İstenen paket/yayın yolunun tüm zorunlu test, imza, hash, helper ve manifest/feed kontrollerini tamamlayın. Hedefli test public yayın öncesi tam suite ve paket doğrulamasının yerine geçmez. |

- Bir kontrol başarısızsa önce ürün regresyonu, ortam/araç koşulu ve mevcut başarısızlık ayrımını kanıtla yapın. Kaynak veya koşul değişmeden aynı komutu döngüde çalıştırmayın; belirsiz yazmayı otomatik tekrarlamayın.
- Aynı kaynak ve koşullarda tamamlanmış mimari denetimini test/build betiği zaten çalıştırdıysa sırf ayrı komut olarak listelendiği için tekrarlamayın. Betiğin gerçekten hangi denetimi tamamladığını doğrulayın; zorunlu veya başarısız kontrolü atlamayın.
- Testi geçirtmek için assertion, güvenlik denetimi veya ürün sınırını kaldırmayın. Ortam eksikse yapılabilen doğrulamayı tamamlayın; eksik kontrolü ve gerçek engeli raporlayın.

### Komutlar

```sh
# Uygulama Swift dosyası eklendi/taşındıysa
python3 scripts/sync-xcode-sources.py

# Import yönü, dosya boyutu/konumu ve Xcode/SwiftPM kaynak eşliği
python3 scripts/check-architecture.py

# Native ve core/text suite'leri seri yürütür; build/test çıktısı /tmp'dedir
./scripts/test.sh

# Yerel imzasız Release; kullanıcı uygulamasına kurulmaz
xcodebuild -project MSSQLStudio.xcodeproj -scheme MSSQLStudio \
  -configuration Release -derivedDataPath /tmp/MSSQLStudio-check \
  CODE_SIGNING_ALLOWED=NO build

git diff --check
```

scripts/test.sh ve scripts/build-app.sh mimari kontrolünü çalıştırır. Filtreli test için scripts/test.sh'ye `--filter <suite-veya-test>` verilebilir. Yeniden kullanılan scratch gerektiğinde yalnız `/tmp` altında tutulur; paket/native bağımlılıklar için test.sh'nin OpenSSL ortam ayarı korunur.

### Test kanıtı ve UI izolasyonu

- Native suite'ler `--no-parallel` çalışır; build paralel olabilir. Aynı masaüstünde iki native test süreci çalıştırmayın; AppKit tema/odak/hover/field editor paylaşılır.
- Çıkış kodu tek başına başarı değildir. Tam suite çalışmasında StudioStateTests, SQLServerKitTests ve SQLTextCoreTests'in tamamlanmış `Test run with` özetlerini ayrı doğrulayın. Filtreli çalışmada seçilen hedefte beklenen testin gerçekten çalıştığını ve tamamlanmış özetini doğrulayın; bunu tam suite sonucu diye bildirmeyin. Geçen/atlanan/başarısız sayısı ve koşul ayrıdır; dış ortam nedeniyle skip, doğrulanmış davranış değildir. İlgili hedefte test bulunmayan filtre için sıfır testi başarı kanıtı gibi sunmayın.
- Gerçek SQL Server testi yalnız adı belirtilmiş test/localhost ortamında benzersiz nesne/#temp, rollback/cleanup ile yapılır; mevcut kullanıcı DB'sine yazılmaz. Gerçek credential, API anahtarı ve kullanıcı sonucu source/fixture/log/sohbete konmaz.
- StudioState.folder test/smoke başlangıcında `/tmp/MSSQLStudio-UI-<PID>` kullanır; Ayarlar Uygula dahil geçmiş/kurtarma gerçek kullanıcı yoluna yazamaz. UI smoke ayrı `/tmp` uygulaması ve `local.mssqlstudio.uitest` veya `--ui-smoke` kullanır; gerçek Keychain/history/favori/restore/network okunmaz. scripts/prepare-ui-test.sh imzalı ZIP'ten ayrı fixture hazırlar. Test tercihi/deposu kullanıcı tercihini değiştirmez.
- Fixture bayrakları yalnız izole başlangıçta etkindir: StudioObjectSmoke, StudioHistorySmoke (yalnız sentetik bellek kayıtları), StudioDesignSmoke (StudioDesignFixture ekran/alt sayfa kataloğu), StudioSchemaComparisonSmoke, StudioExplorerOrderSmoke, StudioGridSmoke/Compact, StudioMultiResultSmoke, StudioAgentSmoke, StudioActivitySmoke, StudioDatabaseFilesSmoke, StudioSettingsSmoke, StudioRefreshSmokeSQL, StudioOfflinePreviewSmoke ve StudioConnectionSmoke. ProjectDesignTests bu kataloğu minimum/geniş boyutta ve açık/koyu temada dolaşır; kontrol taşması denetimi, native dialog/plan ve uzun güncelleme hatasıyla birlikte çalışır. Native bitmap ve gerçek CUA kapsamını ayrı raporlayın.
- Grid normal fixture 2.000×64, compact 6×24; multi-result ilk sonucu 10 satırla sınırlı üç çıktı verir. Refresh fixture sentetik yürütme + sıfır transaction/master session probe ile sayaç artırır; canlı SQL göndermez. Execution fixture tek başına gerçek post-probe testinin yerine geçmez. Schema fixture default writer gönderimi reddeder.
- Ayarlar smoke taslak/gezinmeyi Uygula/Keychain yenileme/geçmiş silme olmadan sınar. Gerçek kaydetme/düzenleme testi yalnız açıkça izole sentetik depodadır. Test uygulamasını normal Quit ile kapatın; gerekirse yalnız exact disposable path/PID'yi hedefleyin.
- Native geometry hedef viewport'u ekran dışında açık boyutla kurar; minimum içerik frameRect ile pencereye çevrilir. Ekran ölçeği için en çok bir fiziksel piksel tolerans kullanın; gerçek satır/kolon kayması, scroll eşliği, selection ve render-count da denetlenir.
- Bitmap doğru appearance/çizim tamamlanmasıyla anlamlıdır; boş görüntü başarı sayılmaz. Native offscreen TabView bitmap'i boş kalabilir; gerçek pencere CUA ile ayrıca incelenir. AX etiket/selection doğru çizim, gerçek fare kaydı veya başarılı işlem kanıtı değildir.
- Başka suite'in field editor odağını çalmayın; edit/iptal arasına yapay async bekleme koymayın. Gerçek asenkron işte bounded koşul bekleyin. Araç timeout/odak/screenshot sorunu ürün başarısı veya kesin ürün hatası diye sunulmaz; somut örnek/log ve sınır rapora yazılır.

### Yerel dosya ve public yayın ayrımı

Aşağıdaki main/tag/publish adımları yalnız public yayın isteğine aittir; geliştirme veya yerel dosya isteğinin kendiliğinden devamı değildir. Kullanıcının açık yayın isteği aynı kapsam için yeterlidir; kapsam değişmedikçe ikinci onay istemeyin.

- Yalnız dosya/önizleme istendiğinde public release/tag oluşturmayın. package-preview.yml `codex/local-package-*` dalında contents:read ve 3 günlük artifact ile signed ZIP/PKG, frozen helper ve paket testlerini üretir; latest'i değiştirmez. Dosyaları indirip hash/strict imza/helper eşliğini doğrulayın, yerel bağlantıları verin. Ad-hoc test uygulamasını kullanıcı yayın paketi diye vermeyin.
- Public yayın yalnız kullanıcı isteğiyle yapılır. Debug/Release MARKETING_VERSION/CURRENT_PROJECT_VERSION, bundle ve ReleaseNotes.json version/date/title/changes aynı olmalıdır. Sürüm notunun tek kaynağını koruyun; kullanılmamış tag seçin, eski tag/asset force değiştirmeyin.
- Helper archive/binary/source pinleri ve signing identity değişmez; v1 değişimi yayın engelidir. Sabit imza anahtarını dışarı çıkarmayın. Yerel imzalı paket `./scripts/build-app.sh /tmp/MSSQLStudio-release` ile; sertifika yoksa CI imzalama yoludur, fallback değildir.
- Kaynağı main'e ve yeni `v<sürüm>` tag'ini origin'e gönderin. release.yml xcode-27 üzerinde kimlik/audit, signed app/PKG, manifest, paket testleri ve asset'ler tamamlandıktan sonra public/latest açar.
- CI başarısı + public latest/tag + ZIP/PKG/update.json/frozen archive doğrulanır. İndirilen SHA-256, GitHub digest/manifest, exact version/binary/notlar, app/helper strict/deep imza ve frozen byte eşliği denetlenir. Ardından signed app'in exact Foundation feed kontrolü geçmelidir; yalnız push veya upload yayın tamamlandı değildir.
- Kullanıcı uygulamasını kurmadan/yeniden başlatmadan tarihli yayın kanıtını TEST-REPORT'a kaydedin ve yayın linkini verin. Gerçek Installer tamamlanması ayrıca test edilmediyse doğrulandı demeyin.

## Rehberi güncel tutma

- Yeni özellikte önce sahip/klasör/işlem sınırını belirleyin; ilgili sözleşmeyi güncelleyin. Yeni ayar arama kataloğuna, yeni kontrol SharedUI standardına, yeni kaynak Xcode/SwiftPM eşliğine dahil edilir.
- Davranış veya mimari değişiminde eski çelişen kuralı düzeltin; sürüm başlığı altında ikinci bir kural kopyası eklemeyin. Mevcut bütçe/kalıcılık/güvenlik sınırı değişimi açık gerekçe ve ilgili regresyon kanıtı ister.
- Kod ve rehber çelişirse kaynak/test/son kullanıcı isteğiyle doğrulayın; doğrulanmamış davranışı belgeye gerçekmiş gibi eklemeyin. Tasarım token'larında StudioTheme/ortak bileşen değeriyle eşliği koruyun.
- Açık doğrulama noktaları TEST-REPORT.md'de izlenir; rehber yenilemek bunları çözülmüş saymaz. Güncel yayın/build bilgisi kaynak sürümü ve ReleaseNotes'tan, test/yayın kanıtı TEST-REPORT'tan doğrulanır.

### Teknik referanslar

Bunlar ürün davranışını otomatik genişletmez; ilgili sözleşme ve mevcut regresyonlar korunur.

- [Apple NSTextFinder](https://developer.apple.com/documentation/appkit/nstextfinder), [appearance](https://developer.apple.com/documentation/appkit/nsapplication/appearance), [kod imzası gereksinimleri](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
- [SQL Server EXECUTE](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/execute-transact-sql), [UDF türleri](https://learn.microsoft.com/en-us/sql/relational-databases/user-defined-functions/create-user-defined-functions-database-engine), [SQLMoreResults](https://learn.microsoft.com/en-us/sql/odbc/reference/syntax/sqlmoreresults-function), [SSMS renk kategorileri](https://learn.microsoft.com/en-us/ssms/scripting/color-coding-in-query-editors).
- [Microsoft macOS ODBC kurulumu](https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/install-microsoft-odbc-driver-sql-server-macos), [DataGrip SQL code style](https://www.jetbrains.com/help/datagrip/configure-the-sql-code-style.html), [completion](https://www.jetbrains.com/help/datagrip/auto-completing-code.html), [Data Sources](https://www.jetbrains.com/help/datagrip/configuring-database-connections.html).
- [DataGrip menü/araç çubuğu](https://www.jetbrains.com/help/datagrip/customize-actions-menus-and-toolbars.html), [kısayol özelleştirme](https://www.jetbrains.com/help/datagrip/configuring-keyboard-and-mouse-shortcuts.html), [Microsoft SUM](https://learn.microsoft.com/en-us/sql/t-sql/functions/sum-transact-sql), [sp_help](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-help-transact-sql), [OPENJSON](https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql).
- [DataGrip Explorer](https://www.jetbrains.com/help/datagrip/database-explorer.html), [editör/ayırıcılar](https://www.jetbrains.com/help/datagrip/code-editing.html), [Smart Keys](https://www.jetbrains.com/help/datagrip/settings-smart-keys.html), [data editor/viewer](https://www.jetbrains.com/help/datagrip/data-editor-and-viewer.html).
