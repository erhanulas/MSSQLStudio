# MSSQL Studio — proje ve geliştirme rehberi

Bu dosya mimari, geliştirme durumu ve görünüm kurallarının ana kaynağıdır. Kullanıcıyla Türkçe iletişim kurun. Kullanıcı kod yazmak yerine istediği davranışı tarif ederek geliştirmeyi yönlendirir. Bu proje önceki NativeSQL'den bağımsızdır; eski projeyi değiştirmeyin veya kodunu kopyalamayın. Üst proje aynasının `sources/` dosyaları salt okunur referanstır.

## Belgelerin sorumluluğu

- `AGENTS.md`: güncel mimari, değişmez kurallar, ürün kapsamı, tasarım ve geliştirme/yayın iş akışı. Mimari veya davranış değiştiğinde ilgili bölümü güncelleyin; her sürüm için aynı bilgiyi yeniden eklemeyin.
- `README.md`: kullanıcı için kısa başlangıç, kurulum ve derleme bilgisi. Teknik rehberi burada tekrar etmeyin.
- `TEST-REPORT.md`: tarihli test/yayın kanıtları ve doğrulanmamış koşullar. Eski bölümler tarihsel kayıttır; güncel özellik veya güncel test sonucu gibi yorumlanmamalıdır.
- `Sources/SQLServerKit/Resources/ReleaseNotes.json`: uygulamadaki ve GitHub yayınındaki sürüm notlarının tek kaynağı. Yeni mimari/tasarım Markdown dosyaları açmak yerine önce mevcut belgeleri güncelleyin.
- Eski `ARCHITECTURE.md`, `DESIGN.md` ve `docs/PERSONAL-SIGNING.md` içerikleri bu rehberde birleştirilmiştir. Ayrı, çelişen kopyalar üretmeyin. Ayrıntılı eski uygulama/yayın geçmişi Git geçmişinde ve test raporundadır.

## Güncel durum — 10 Ekim 2026

Son doğrulanmış yayın **v0.2.55, build 56**; kaynak `8b501d882a9a03689f253a09185a3f8afd5fe8d1`. Depo: https://github.com/erhanulas/MSSQLStudio. Actions `38051856183` başarılı; indirilen ZIP/PKG SHA-256 ve sabit uygulama imzası doğrulandı.

- Native SQL Server çalışma alanı: bağlantı/Explorer, bağımsız sorgu sekmeleri, TextKit 2 SQL editörü, disk destekli sonuç grid'i, mesajlar, XML plan ağacı, ayrılabilir sorgu pencereleri.
- Editör: T-SQL renklendirme/biçimlendirme, GO batch'leri, seçim çalıştırma, DDL indeksli tamamlama/doğrulama, alias ve isteğe bağlı NOLOCK, blok katlama, kelime eşleşmeleri, tanıma geçiş, lexical kullanılmayan DECLARE vurgusu.
- Nesne yönetimi: tablo/view tasarımı, scriptler, index/key/FK/check/trigger, procedure/function çağrı SQL'i, synonym, izinler, yeniden adlandırma ve ayrı sınırlı veri editörü. Genel sonuç grid'i doğrulanmış tek tablo SELECT sonuçlarında önizlemeli INSERT/UPDATE/DELETE destekler.
- SQL Agent: job özellikleri/adımlar/zamanlamalar/bildirimler, geçmiş ve Activity Monitor, açık onayla iş komutları. T-SQL adımında veritabanı seçimi ve ana editörle ortak komut renkleri vardır.
- Ayarlar altı native sekme kullanır: Görünüm, SQL Editörü, Kısayollar, Çalışma Alanı, Güncellemeler, Güvenlik. Uygula/geri bildirim sabittir; sekme geçişleri kaydedilmemiş girdileri korur. Kısayollar hemen kaydedilir.
- v0.2.47: genel form hizalaması, Gelişmiş adım grupları ve işlem ikon/renkleri yayımlandı. Son yerel doğrulama: 67 uygulama + 99 core = 166 test; 144 geçti, 22 dış koşullu test atlandı. Yayın işi `38040358461` başarılı; indirilen ZIP'in SHA-256 ve sabit imzası doğrulandı.
- Son hizalama turunda CUA `Sky Computer Use native pipe closed before response` hatası verdi. Tüm formların son görsel kontrolü tamamlanmadı; build/test başarısı bu kontrolün yerine geçmez. Yeni arayüz işinde bu kontrolü yeniden deneyin.

Explorer/bağlantı revizyonu v0.2.49 içinde yayımlandı: 168 testten 146 geçti, 22 dış koşullu test atlandı; Release derlemesi başarılı. İzole bağlantı formu ve DB indeks düğmesi görsel kontrolden geçti; canlı DB davranışı doğrulanmış değildir. Ayrıntılar TEST-REPORT.md içindedir.

## Platform ve kaynak haritası

macOS 27+, Apple Silicon, Swift 6; AppKit + SwiftUI + TextKit 2. SQL Server erişimi Microsoft ODBC Driver 18 / unixODBC / OpenSSL 3 ile; katalog önbelleği SQLite. `Package.swift` app, core ve iki test hedefini tanımlar; Xcode projesi core'u local Swift package üzerinden kullanır.

| Kaynak | Sorumluluk |
|---|---|
| `Sources/MSSQLStudio/Application.swift` | Başlatma, menüler, güvenli UI fixture başlangıcı |
| `StudioState.swift` | ConnectedServer, QueryDocument, oturum/yürütme durumu, kayıt/kurtarma |
| `WorkbenchController.swift` | Explorer, arama, toolbar, sekmeler, bağlantı formları ve pencereler |
| `EditorView.swift` | SQLTextView/EditorController, TextKit 2, katlama, tamamlama, seçim/odak |
| `ResultsView.swift` | QueryController, native sonuç grid'i, filtre/sayfa/export, plan görünümü |
| `WorkspaceWindows.swift` | Aynı sorgu controller'ını taşıyan detached pencere |
| `ManagementReview.swift` | Fark önizleme/gönderme ve Agent yönetimi, adım/zamanlama editörleri |
| `ObjectManagementPanels.swift` | Nesne tasarım/script/izin/veri düzenleme panelleri ve fixture |
| `WorkbenchPanels.swift` | Ayarlar, yardımcı paneller, StudioTheme ve ortak görünüm bileşenleri |
| `AboutPanel.swift` | Kurulu sürüm, çevrimdışı sürüm geçmişi |
| `Sources/SQLServerKit/ODBCConnection.swift` | Worker queue, ODBC handle yaşam döngüsü, iptal ve streaming |
| `TSQL.swift`, `CompletionSymbols.swift` | Lexer/batch/format/folding ve sınırlı SQL intelligence |
| `Catalog.swift`, `CatalogDiskIndex.swift` | Metadata SQL'i, SQLite indeks ve atomik snapshot'lar |
| `ResultStorage.swift`, `ResultFiltering.swift` | Disk spool, snapshot/projection, filtre/sıralama |
| `ObjectManagement.swift`, `SQLAgent.swift` | UI'dan bağımsız modeller, metadata ve doğrulanmış SQL üretimi |
| `Persistence.swift` | ServerVault/Keychain, yerel kayıt ve yardımcı servisler |
| `ApplicationUpdate.swift`, `PersonalSigningIdentity.swift` | Güncelleme hazırlama/doğrulama ve sabit kimlik |
| `SQLTextDiff.swift`, `ReleaseHistory.swift`, `Resources/` | Fark hesaplama, sürüm geçmişi, açık imza kimliği |
| `Tests/SQLServerKitTests`, `Tests/StudioStateTests` | Core ve MainActor/native uygulama testleri |

Tablodaki kısa dosya adları, ayrıca yol belirtilmedikçe aynı satır grubunun kaynak klasöründedir. Yeni iş mantığını core'a, native pencere/controller davranışını app'e koyun; gereksiz mimari değişiklik yapmayın.

## Mimari ve veri bütünlüğü

- Swift 6 concurrency kontrolünü koruyun. AppKit/SwiftUI MainActor'da; blocking ODBC, SQLite, büyük analiz/filtre/export işleri arka planda kalır. UI'nın sekme değiştirmesini ağ işi bitene kadar engellemeyin; yükleme/iptal/hata durumunu görünür tutun.
- Her QueryDocument kendi ODBC bağlantısı, veritabanı, SQL/sonuç/tanı ve transaction durumunu taşır. Metadata ayrı bağlantılar kullanır; sorgunun transaction veya database context'ine dokunmaz. Detached pencere aynı controller/document/session'ı taşır; klonlamaz.
- ODBC handle'ları tek worker queue'da yönetilir. İptal ayrı queue + generation/lock korumasıyla SQLCancelHandle kullanır. UTF-16 ve parça parça hücre okumaları korunur; exact numeric değerleri Double'a dönüştürmeyin. Execution ID/generation eski cevapların yeni durumu ezmesini engeller.
- GO yalnızca bağımsız satırda, string/bracket/nested comment dışında bölünür. Batch'ler aynı oturumda sıralıdır; bütçe ortaktır. İptal veya kısmi sonuç sonraki batch'leri durdurur. **İptal transaction rollback değildir.** Çalışan sorgu/açık transaction kapanış güvenliğini koruyun.
- SQL identifier/literal escaping merkezi `SQL` helper'larından geçer; job kimlikleri doğrulanmış UUID'dir. Kaynak, fixture, log veya sohbete parola/API anahtarı/gerçek kullanıcı sonuçları koymayın.
- Tasarım/şablon/AI SQL'i önce inceleme editörüne aktarılır, otomatik çalıştırılmaz. Açık Agent komut onayı ve nesne önizlemesindeki Veritabanına Gönder ayrı yürütme yollarıdır; bu farkı koruyun.
- Nesne kimliği serverID/database/objectID'dir. `moduleOriginal` ham sunucu tanımıdır; hazırlanmış SET/GO/ALTER editör metnini conflict baseline olarak kullanmayın. Dosya dirty ile uygulanmamış nesne değişikliği ayrıdır. Gönderimden önce güncel tanımı tekrar okuyun; başarılı gönderimde yalnız gönderilen snapshot baseline olur. Eşzamanlı yeni editler bekleyen değişiklik kalır. Atomik şema kilidi/üç yönlü merge güvencesi yoktur.
- Tablo designer eksik/kısmi metadata'dan CREATE üretmez; mevcut tabloyu otomatik rebuild etmez. Desteklenmeyen seçenekleri açıkça bildirin. Ayrı veri editörü PK/original değerler ve rowversion ile optimistic kontrol yapar; @@ROWCOUNT != 1 hata/rollback üretir, generated/anahtar alanlarını korur. Başlangıç en fazla 200, değişiklik en fazla 400 satırdır.
- Explorer bağlantısını kesmek açık sorgu oturumlarını kapatmaz. Offline ağaç/profil ve arama kapsamı korunur; yeniden bağlantı otomatik SQL çalıştırmaz. Görünür DB tercihi yetkilendirme değildir. Credential/endpoint değişiminde aday bağlantı doğrulanır; çalışan sorgu/transaction denetimi öncesinde ve async beklemeden sonra tekrarlanır.
- Katalog indeksi SQLite worker'ında, staging + atomik yayınla hazırlanır; başarısız yenileme önceki snapshot'ı korur. Scope server/database'tir. Single-flight, cancellation, request/generation ve retry/freshness korumalarını kaldırmayın. Arama yüklenmiş yerel indeksleri kullanır; sınırlı/kısmi durum görünürdür.

## Editör, sonuçlar ve performans

- TextKit 2'yi koruyun; `layoutManager` erişimiyle TextKit 1'e geçmeyin. Native find/scroll/selection/undo/completion davranışını koruyun. Renklendirmede metni yeniden atamayın; yalnız değişen attribute aralıklarını güncelleyin. IME marked text sırasında biçimlendirmeyi erteleyin.
- Ana editör, fark önizleme ve Agent komut alanı `SQLSourceHighlighting`/StudioTheme renklerini paylaşır. Genel tema dekorasyonu `sqlSourcePreview` veya `agentCommandEditor` syntax renklerini sıfırlamamalıdır. Undo/redo restored text ile SwiftUI binding'i senkron tutun; renklendirmeyi undo kaydına eklemeyin.
- Katlama özgün SQL source'u koruyan projection'dır. Katlama/açmada başlık, caret ve viewport farkındalığı korunmalı; gereksiz animasyon, scroll veya metin sıfırlama yapılmamalıdır. Kapalı blok göstergesi açık halde kaybolur; +/− görünümü durumu anlaşılır kılar.
- Çift tıklama kelime seçimi/eşleşme vurgusudur; metin kaybolup geri gelmemeli, dirty/undo değişmemelidir. Native mouse tracking bitene kadar boyamayı erteleyin. @/@@/# önekleri ve composed Unicode karakterlerini koruyun. Tanıma gitme ayrı command-click/⌘B eylemidir.
- Kullanılmayan DECLARE adı aynı GO batch'inde lexical başka kullanım yoksa soluk görünür. Yorum/string/bracket kullanımı sayılmaz. Bu tam T-SQL scope/dataflow analizi değildir; dinamik SQL ve tüm grameri çözdüğünü iddia etmeyin.
- Tamamlama detached analiz, kaynak/caret/catalog generation doğrulaması ve iptal kullanır. Varsayılan gecikme 260 ms (50–1000 ms); Ctrl+Space beklemez. Alias yalnız kabulde eklenir. NOLOCK varsayılan kapalıdır ve dirty read riski açıklanır.
- Sonuç düzenleme Düzenle düğmesiyle veya hücreye çift tıklama/Enter ile kaynak doğrulanarak başlar. `sys.dm_exec_describe_first_result_set(...,1)` kaynak kolonlarını ordinal olarak doğrular; SQL metninden tablo adı tahmin edilmez. Tek yerel kullanıcı tablosu, bütün kolonlar ve PK zorunludur. Alias/kolon sırası desteklenir; JOIN/toplama/çoklu sonuç, temp/remote, eksik PK/projection ve kısmi sonuçlar salt okunur. Özel tablo metadata kısıtları korunur.
- Hücre düzenlemeleri kaynak satır indeksine göre ayrı yerel sözlükte tutulur (en çok 400 değişmiş satır); spool değiştirilmez. Normal PK alanları düzenlenebilir; UPDATE satırı orijinal anahtarla bulur. IDENTITY/computed/rowversion ve desteklenmeyen türler kilit ikonu + kolon tooltip/hücre açıklamasıyla salt okunurdur. NULL açık eylemdir, orijinale dönüş bekleyen değişikliği kaldırır. Yeni satır ve çoğaltma sayfanın sonunda ayrı negatif kimlikle görünür; filtre/sort onları gizlemez, spool/export dışında kalır. Yeni satırda dokunulmayan alan DEFAULT, açık NULL touched olur. Çoğaltma PK/generated/özel türleri taşımaz; nonidentity anahtar yeniden girilir. Silme mevcut satırı işaretler; yeni satırı yerelden kaldırır; seçili değişiklikler geri alınabilir. Satırlar menüsü ve sağ tık aynı işlemleri sunar. Sıralama/filtre/kolon taşıma kaynak satır kimliğini değiştirmez. Kopyalama yerel değerleri içerir; filtre/sıralama ve export yürütülmüş snapshot üzerindedir.
- Native field editor yazı değişikliğinde hücreden çıkmadan önizleme düğmesini etkinleştirir; taslak spool/yerel satır sözlüğünü commit öncesi değiştirmez. Escape taslağı iptal eder; önizlemeye basınca native editor commit edilir. SQL Önizle ve Gönder düğmesi sabit yerleşimde ve değişiklik yoksa pasiftir. Önizleme salt okunur SQL + sunucu/DB hedefi gösterir. Yalnız Onayla ve Veritabanına Gönder yazar; aynı SQL/sonuç generation/DB/sunucu generation yeniden denetlenir. Metadata tekrar doğrulanır, OBJECT_ID + PK/orijinal/isteğe bağlı rowversion + @@ROWCOUNT kontrolleri transaction içindedir. Rowversion zorunlu değildir: yoksa karşılaştırılabilen kolonlar + XML/text/ntext/image açık dönüşümleri denetlenir. Desteklenmeyen spatial/UDT/sql_variant alanlar salt okunurdur ve conflict predicate dışında kalır; bunlarda eşzamanlı değişiklik denetimi iddia edilmez. Yazma ayrı ODBC bağlantısındadır; query session transaction'ı etkilenmez. Başarılı gönderim düzenlemeleri temizleyip son SELECT'i yeniler. Ağ hatasında commit sonucu belirsiz olabilir; otomatik tekrar yoktur.
- Düzenleme modunda otomatik refresh kapalıdır. Bekleyen değişikliği silecek sorgu yürütme/yenileme/sekme kapatmada açık uyarı gerekir; gönderim sırasında sorgu yürütme/kapatma engellenir. Önizleme değiştikten sonra eski onay gönderilemez.
- GridDataCell.copy(with:) ayrı checkbox sahibi hücre üretir; inherited ObjC copy ile Swift-owned NSCell alanlarını sığ kopyalamayın. Sonuç table/scroll/cell focusRingType none kullanır; seçim/klavye odağı korunur. Field editor hücre kopyalar; native düzenleme/commit/deallocation regresyonunu koruyun.
- Başlık genişliği native 11 pt medium font ölçümü + ikon/kenar payı içerir; veri örneklemesi başlıktan daha dar yapmaz. Filtre hit alanı dış 12 pt resize kenarından ayrıdır ve sürüklemede açılmaz. False bit checkbox yalnız boş kontur, true native işaretli kutudur.
- Genel sonuç grid'i native cell-based NSTableView'dır; görünen hücreleri reuse eder. Hücre başına SwiftUI/Auto Layout veya tüm veriyi ölçme eklemeyin. Disk ResultSpool snapshot'ları, sınırlı cache ve ordinal kolon kimlikleri korunur. Filtre/sıralama sadece yüklenmiş satırlardadır; server-side filtre gibi sunulmaz.
- Filtre/sıralama/background export iptal edilebilir ve revision korumalıdır. Export sibling temp dosyasından atomik değişim yapar; hata/iptalde hedefi korur. Clipboard 10.000 satır/16 MB sınırını koruyun. O(n) indeks/anahtar belleği vardır; sınırsız/sabit bellek iddiası yapmayın.
- Varsayılan bütçe 50.000 satır, 100 result set, yaklaşık 2 MB/hücre, 64 MB ve 60 sn; 1m/5m modlarında toplam 2 GB/600 sn. Partial mesajını saklamayın. Büyük SQL'de syntax/analiz sınırlarını koruyun; UI kullanılır kalmalıdır.
- Theme değişiminde grid kolonları, genişlik/gizlilik, seçim ve scroll korunur. İlerleme bildiriminde recursive tema taraması/reloadData yapmayın; UI güncellemelerini birleştirin.

## Görünüm ve etkileşim kuralları

Kullanıcının önceliği düzenli, hizalı, sakin ve premium native bir görünüm; SSMS iş akışı ile DataGrip'in okunabilirlik yaklaşımıdır. Marka varlığı kopyalamayın, SF Symbols kullanın. Yalnız tek bildirilen ekranı düzeltip aynı kusuru diğer formlarda bırakmayın; benzer yerleşimleri de inceleyin.

- Ana düzen solda Object Explorer, ortada sorgu sekmeleri/editör, altta sonuç/mesaj/plan. Explorer daraltılınca kendiliğinden kapanmaz; gizleme açık eylemdir. Native pencere, menü ve dosya panellerini koruyun.
- Formlarda `StudioFormField`: 150 pt etiket sütunu + 12 pt aralık; Job Gelişmiş'te uzun etiketler için 180 pt. Etiketler satır sarar; alan başlangıcı etiket uzunluğuyla kaymaz. Grid kullanan bağlantı formu da 150 pt sütun kullanır. Birim ve numeric stepper'lar ortak hizadadır.
- Placeholder görünür etiketin yerine geçmez. Çok sayıda şema/ad/kaynak alanını tek dar HStack'e sıkıştırmayın; etiketli satırlara ayırın. İlişkili alanları başlıklı kart/GroupBox gruplarında toplayın. Kontrol/işlem çubuğunu kaydırılan uzun içerikten ayırın; küçük pencere ve uzun metinde taşmayı inceleyin.
- İşlem düğmeleri metin + anlamlı ikon kullanır (`StudioActionButton`). Birincil eylem `StudioPrimaryButton`; ikincil eylemlerde accent ikon, başlatmada yeşil, durdurma/ayırmada turuncu, silmede kırmızı. Renk tek başına anlam taşımaz; metin, ikon, tooltip ve erişilebilir ad kalır. Disabled durumu soluk ve tutarlıdır.
- Satır/sekme/düğmenin **tüm görünen alanı** tıklanır; yalnız harfler veya ikonun çizgileri değil. Expanded frame/padding sonrasında uygun `contentShape` kullanın. İkon-only düğmelere yeterli hit alanı ve erişilebilir ad verin. Seçili sayfayı zemin/kalın yazı ve `.isSelected` ile belirtin.
- Ayarlar'da native sekmeler, kalıcı Uygula/mesaj alanı ve pencere yeniden kullanımı korunur. Tema/sekme değişimi form kimliğini yeniden yaratıp kullanıcının girdisini sıfırlamamalıdır. Hakkında sürüm satırlarının boş alanı da tıklanır.
- Job/trigger satır adlarına `(Enabled)` benzeri durum metinlerini yığmayın; ikon, tooltip ve erişilebilirlik açıklamasını kullanın. Loading göstergesi görünür olsun; başka sekmeye geçişi engellemesin.
- Ortak bileşenleri kullanın: StudioTheme, StudioPanelHeading, StudioEmptyState, StudioPanelStyle/studioPanel, studioEditor, StudioFormField, StudioActionButton, StudioPrimaryButton. Rastgele font/renk/ölçü veya ağır gölge eklemeyin.

| Token / ölçü | Açık | Koyu |
|---|---|---|
| Canvas | `FFFFFF` | `202229` |
| Panel | `F3F4F8` | `292C35` |
| Metin | `272B38` | `DCE0EB` |
| Accent | `4C6FE8` | `8CA7FF` |
| Seçim | `E1EBFF` | `334766` |
| Kenarlık (1 pt) | `E1E4ED` | `3B3F4C` |

Sistem UI fontu 12 pt; yardımcı metin 10–11 pt; SQL varsa Consolas 13 pt, yoksa native monospace. Grid/ağaç satırı 24/25 pt, sorgu sekmesi/sonuç araç satırı 34 pt. Panel köşesi yaklaşık 8 pt, kontrol 5–6 pt; Ayarlar kartları 12 pt kullanabilir. Renk/ölçü kaynağı kodda StudioTheme ve ortak bileşenlerdir.

## Bağlantı formu ve Explorer yenileme düzeni

- Yeni bağlantı formu kayıtlı bağlantı seçmez/otomatik doldurmaz; yeni profil ve boş parola ile açılır, ServerVault listesi okumaz. Düzenleme yalnız seçili bağlantının mevcut bilgilerini kullanır.
- Bağlantıyı kaldır eylemi onay ister; yalnız Explorer bağlantısını, ağacını ve arama kapsamını kaldırır. Keychain kaydı/parola ve açık sorgu oturumu/transaction korunur. Otomatik restore seçimi kaldırılır.
- Veritabanı bilgileri ayrı salt okunur pencerede metadata bağlantısıyla yüklenir; SQL sekmesi açılmaz. Genel alanlar ve dosyalar hizalı kartlarda gösterilir. İndeks popup'ı DB başına kart ve nesne/kolon metrikleri, eşitleme zamanları, yükleme/hata durumları gösterir; katalog bildiriminde yenilenir.

- Bağlantı Genel/Gelişmiş seçenekleri ve ayrı görünür veritabanı paneli kullanır. Tek alt ana işlem önce Veritabanlarını Yükle, başarılı liste/seçim sonrası Bağlan/Uygula'dır. Liste yenilemesi yalnız liste hazırken görünür; loading/hata/başarı tek alt alandadır. Sekme geçişleri girdileri korur. Mevcut bağlantıyı düzenlerken tüm ServerVault kayıtları yeniden okunmaz; UI smoke yeni bağlantısı Keychain listesi okumaz.
- Nesneleri Yenile seçili Explorer dalının katalog listesini yeniler; açık sorguyu veya onun SQL intelligence indeksini zorla yenilemez. DB yenilemesinde yüklenmiş klasör listeleri yeniden okunur, klasör nesneleri korunur; açılmamış klasörler lazy kalır. Yerel İndeksi Yenile ayrı ve açık kapsamlı metadata önbelleği işlemidir.
- Üstte uzun DDL indeks metni yoktur. Header'da kompakt indeks düğmesi ve DB adının hemen yanında 24 pt durum düğmesi vardır; geniş tablonun sağ kenarına bağlayıp dar Explorer'da görünmez bırakmayın. Ayrıntı popup'ı nesne/kolon zamanı, hata/hazırlık ve açık yenileme eylemi sunar. Offline durumda yenileme kapalıdır. Her metadata status yenilemesinde tüm ağacı yeniden kurmayın.
- DB sağ tık menüsü Yeni Sorgu, Nesneleri Yenile, Yeni Nesne alt menüsü, yerel indeks ve Veritabanı bilgileri penceresini ayırır. SSMS'te var diye desteklenmeyen Backup/Restore/Tasks sihirbazlarını sahte menü olarak eklemeyin. Kaynak: [Microsoft Explorer yönetimi](https://learn.microsoft.com/en-us/ssms/object/manage-objects-by-using-object-explorer).

## Agent, Linked Server ve ürün sınırları

- Job History varsayılan **son 7 gün**; ilk açılışta en yeni 500 çalışma özeti, adım/retry ayrıntıları istekle yüklenir. Durum filtresi iş sonucuna uygulanır; alt adımlar kendi durumuyla korunur. Devam eden işler Activity Monitor'den izlenir. Aynı işin açık properties/history penceresini yeniden kullanın.
- Explorer Agent dalı açık, Jobs yüklenmiş ve pencere görünürken 15 sn auto-refresh; kapalı/minimized/offline durumda yeni otomatik okuma yoktur. Kullanıcı kapatabilir. Seçim, node kimliği ve scroll korunur. Activity Monitor 15/30/60 sn seçeneklidir.
- T-SQL adımının DB'si ayrı metadata bağlantısıyla erişilebilir DB listesinden seçilir; Explorer görünürlük filtresiyle daraltılmaz. Mevcut DB listede yok/hata/partial ise değer korunur, başka DB otomatik seçilmez. T-SQL dışı adımlar salt okunur ve DB liste sorgusu yapmaz.
- Tasarım SQL'i önce sorgu sekmesine gider; çalıştırma sonrası Yenile. Job/schedule version/tarih conflict kontrolleri ve stored procedure return-code/hata rollback davranışları korunur. Start/Stop Job ile işletim sistemi Agent servisi yönetimini karıştırmayın.
- Linked Server, mevcut SQL Server üzerinden sp_catalogs/sp_tables_ex/sp_columns_ex ile sağlayıcının katalog/table rowset'lerini ve kolonlarını gösterir. Dolu tablo/view/system/synonym/temp/other grupları, dört parçalı SELECT ve salt okunur properties vardır. Uzak parola/oturum, remote designer/DDL ve routine klasörleri eklenmiş gibi sunulmaz. Metadata 5.000 satır/8 MB/30 sn sınırlıdır; boş sonuç yokluk kanıtı değildir.
- Tam SSMS/DataGrip eşdeğerliği, eksiksiz T-SQL parser/IntelliSense, grafik plan/JOIN diyagramı, serbest docking, otomatik table rebuild, backup/restore sihirbazı veya binary plugin SDK yoktur. Agent step reorder, proxy/non-TSQL düzenleme, alert oluşturma, multiserver/servis yönetimi tamamlanmış değildir. Kerberos, gerçek AI sağlayıcısı, Linked Server sağlayıcıları ve sunucuya bağlı Agent koşulları test kanıtı olmadan doğrulanmış sayılmaz.
- AI ephemeral URLSession, HTTPS/loopback HTTP, redirects kapalı; API anahtarı yalnız açık panel belleğindedir. Şablon eklentileri boyutu sınırlı Codable JSON'dur; bilinmeyen/binary kod yüklenmez. Sahte düğme veya başarı mesajı eklemeyin.

## Keychain, kalıcı imza ve güncelleme

- Bundle ID `local.mssqlstudio.app`, Keychain service `local.mssqlstudio.servers`; sürüm numarası eklemeyin. Açık kimlik `Sources/SQLServerKit/Resources/SigningIdentity.json`; sertifika SHA-1 `adce16b1a3567d8c5fe2ed261e89493611cb7b9d`.
- Sabit designated requirement: `identifier "local.mssqlstudio.app" and certificate leaf = H"adce16b1a3567d8c5fe2ed261e89493611cb7b9d"`. CDHash derlemeler arasında değişebilir; süreklilik sabit DR'ye dayanır. Eski ad-hoc ACL kendiliğinden taşınmaz. Debug/ad-hoc uygulamayı yayın kimliğinin yerine kullanmayın.
- `scripts/build-app.sh` derleme sonrası `scripts/signing.py` ile sabit sertifikayı kullanır; bulunamazsa hata verir, ad-hoc fallback yoktur. PKG kapsayıcısında Developer ID Installer imzası yoktur; içindeki app kişisel sertifikalıdır. ZIP çıkarıldıktan sonra da imzayı doğrulayın.
- Özel anahtar/P12/parola Git'e, artifact'e, app'e veya log'a girmez. Actions secrets `MSSQL_SIGNING_P12`/`MSSQL_SIGNING_PASSWORD`; `scripts/ci-signing.py` 0600 geçici dosya ve geçici CI Keychain kullanıp temizler. Her sürümde sertifika üretmeyin. Güvenli şifreli çevrimdışı yedeği koruyun; mevcut secrets'ı dışarı çıkarmayın. Yerel incelemede kullanılabilir yayın özel anahtarı bulunmadı; yerelde var olduğunu varsaymayın.
- Mevcut sertifikanın geçerliliği 9 Ekim 2026–6 Ekim 2036 UTC. Anahtar kaybı/sertifika değişimi kontrollü migration gerektirir; eski updater yeni kimliği kendiliğinden kabul etmez. Workflow yazma yetkisini de anahtar güvenliği gibi koruyun.
- Ayarlar → Güvenlik → Keychain izinlerini yenile yalnız doğrulanmış yayın imzasıyla çalışır. Parolaları okumadan/export/silme yapmadan aynı service/account erişimini yeniler; eski izin girdilerini otomatik sıfırlamaz. macOS sahiplik onayı/parola isteyebilir. Normal kayıt güncellemesi ACL'yi yeniden yazmaz.
- Keychain sıfırlamayın, tüm uygulamalara erişim açmayın, kullanıcı kayıtlarına genel partition-list uygulamayın veya Gatekeeper kapatmayın. CI partition-list yalnız geçici imza özel anahtarına aittir. Kilitli Keychain ve sistem politikaları yine parola isteyebilir; “bir daha kesinlikle istemez” demeyin.
- `signing-audit.yml` iki farklı imzalı derleme/dosya yolunu sentetik kayıtla geçici test Keychain'inde sınar; ad-hoc okuma/yenileme yetkisi alamaz. Başsız ACL onayı veya gerçek kullanıcı yükseltmesi test edilmiş gibi raporlanmaz.
- Yerel sertifika Apple Developer ID/notarization eşdeğeri değildir. codesign ile Gatekeeper ayrı doğrulamalardır; v0.2.43 incelemesinde spctl reddetti. Güvenliği azaltarak aşmayın. [Apple kod gereksinimleri](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [imza teknik notu](https://developer.apple.com/library/archive/technotes/tn2206/).
- Güncelleme public GitHub latest update.json üzerinden HTTPS kullanır. ZIP alanları eski sürümler için manifestte kalır; yeni UI installerURL/installerSHA256 ile PKG indirir. SHA-256, açılmış payload'da sabit sertifika/DR, bundle ID ve tam sürüm doğrulanır. Betikli component paketleri reddedilir. Özel shell helper, .previous, rollback ve uygulamayı kendiliğinden değiştirme kaldırıldı. macOS Installer /Applications/MSSQLStudio.app hedefinde yerinde upgrade yapar; kullanıcı kurulum ekranını tamamlar ve uygulamayı Uygulamalar'dan açar. pendingInstallerVersion sonraki açılışta çalışan sürüm/konumla karşılaştırılır; eksik kurulum başarı gibi bildirilmez. Keychain/Preferences/Application Support korunur. Otomatik yetki yükseltme, Gatekeeper bypass veya yedek silme yoktur. Eski updater bu akışı kullanamaz; ilk geçiş PKG ile yapılmalıdır.

- Timeline metin/sunucu/DB/durum/tarih filtreleri, en yavaş sıralama, SQL renkli önizleme, hata/satır sayısı, kopyalama ve kendi sunucusunda açma sağlar. Yeni kayıtlarda server UUID bulunur; eski isim tabanlı kayıt yalnız tek eşleşmede açılır. Geçmiş paneli kayıt değişikliklerini izler. Ayarlar → Çalışma Alanı historyRetentionDays 1–3650 gün, varsayılan 30; açılış/yeni kayıt/Uygula'da süre temizliği yapılır. Ek 16 MB JSON / 20.000 kayıt bütçesi vardır, eski 300 kayıt sınırı kaldırılmıştır. Eski Codable kayıtlar korunur. UI smoke başlangıcı yerel history okumadan döner.
- Yerel history/recovery opt-in'dir; Application Support/MSSQLStudio klasörü 0700, dosyalar 0600 ve atomik yazılır. SQL değer içerebilir; snapshot parola içermez. Mevcut kullanıcı kayıtlarını test için silmeyin.

## Geliştirme, doğrulama ve yayın akışı

1. Başlangıçta Git durumunu ve ilgili kaynakları okuyun; kullanıcının mevcut değişikliklerini koruyun. Kullanıcı uygulamasını test derlemesiyle değiştirmeyin veya açık gerçek SQL oturumunu yeniden başlatmayın.
2. Build/test çıktılarını `/tmp` altında üretin. Core/native testler: `./scripts/test.sh`. Yerel Release doğrulaması: `xcodebuild -project MSSQLStudio.xcodeproj -scheme MSSQLStudio -configuration Release -derivedDataPath /tmp/MSSQLStudio-check CODE_SIGNING_ALLOWED=NO build`. Bu imzasız build yayın paketi değildir.
3. İlgili davranışa uygun test ve native UI smoke çalıştırın. İzole `local.mssqlstudio.uitest` veya `--ui-smoke` başlangıcı gerçek Keychain/restore/network öncesi döner. `scripts/prepare-ui-test.sh <release.zip>` ayrı test app'i hazırlar; fixture çevrimdışıdır. Canlı test yalnız adı belirtilen localhost ortamında benzersiz nesne/#temp ve rollback/cleanup ile; mevcut kullanıcı DB'sine yazmayın.
4. İlgili kontroller geçince sebepsiz tekrar/genişletme yapmayın. `git diff --check` çalıştırın. Geçen, atlanan, başarısız ve yapılamayan kontrolleri ayrı yazın; test aracı arızasını ürün başarısı gibi sunmayın. Kullanıcı istediğinde yayın yapın; yayımlanmış diye bildirmek için yalnız Git push yeterli değildir.
5. Yayında Xcode Debug/Release MARKETING_VERSION ve CURRENT_PROJECT_VERSION'ı yükseltin; ReleaseNotes.json en üst kaydını aynı version/date/title/changes ile ekleyin. Kullanılmamış yeni tag kullanın; mevcut tag'i force taşımayın, başarısız sürümü yeniden yazmayın.
6. Kaynağı main'e, `v<sürüm>` tag'ini origin'e gönderin. `.github/workflows/release.yml` xcode-27 runner'ında sabit imza, ZIP/PKG, manifest ve paket testlerini tamamlar; tüm asset'ler taslağa yüklendikten sonra latest yayını açar. Özel anahtarı yerel olarak çıkarmaya çalışmayın.
7. CI başarı + public release/latest + ZIP/PKG/update.json varlığını doğrulayın. ZIP'i `/tmp` altına indirip SHA-256 manifest/digest eşleşmesini ve çıkarılmış app için `codesign --verify --deep --strict` / sabit DR'yi kontrol edin. Gerçek kullanıcı app'ini değiştirmeden raporu güncelleyip yayın linkini verin.
