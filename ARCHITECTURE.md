# Mimari

`SQLServerKit`, AppKit arayüzünden bağımsız Swift paketidir. `ODBCConnection` bütün environment/connection/statement handle'larını tek worker queue üzerinde yönetir. İptal ayrı queue üzerinden SQLCancelHandle çağırır; generation token ve lock handle'ın serbest bırakıldıktan sonra kullanılmasını önler. Sorgular UTF-16 API'leriyle gönderilir; metin/binary hücreler parça parça okunur, exact numeric değerler string olarak saklanır. ODBC worker blocking API kullanır; UI main actor'ını bloklamaz.

`TSQL` UTF-16 lexer, GO batch ayırıcı, biçimlendirme ve sınırlı tamamlama çözümleyicisidir. GO yalnızca bağımsız satırda, string/bracket/nested comment dışında ayrılır. Batch'ler aynı oturumda sırayla çalışır. Bellek/row/result budget tüm batch'ler arasında paylaşılır; iptal veya kısmi sonuç sonraki batch'leri durdurur. Tam parser/binder olduğu iddia edilmez.

`Catalog` sistem katalogları ve DMV sorgularını üretir. Metadata çalışması sorgu sekmesinin session/transaction'ına müdahale etmemek için ayrı kısa ömürlü bağlantılar kullanır. SQL identifier ve literal kaçışları merkezi `SQL` helper'ındadır; katalog object ID'leri Int'tir. Scripts indeks ve Agent job SQL'ini oluşturur, çalıştırmaz.

`ConnectedServer` bağlantı profilini ve veritabanı listesini tutar. Her `QueryDocument` bağımsız ODBC oturumu, seçili veritabanı, editör metni, sonuçları, hata mesajları ve transaction sayısını taşır. QueryEvent'ler main actor'a aktarılır; execution ID eski sorgunun geç gelen satırlarının yeni sorguya karışmasını engeller. Son sonuç anlık streaming görünümünün yerine konur. Çalışan sorgu ve açık transaction kapanmayı engeller.

`WorkbenchController` NSOutlineView, NSToolbar ve NSSplitViewController ile SSMS düzenini kurar. `QueryController` editor/result splitter ve çoklu NSTabView sonuçlarını taşır. `EditorController` TextKit 2 NSTextView, native completion ve Find Bar'ı yönetir; klasik layoutManager API'si kullanılmaz. Ruler yalnızca kendi bounds'unu boyar. `ResultController` virtual NSTableView kullanır; büyük hücreler ayrı inceleme ekranında açılır. `PlanController` XML operatör ağacını sunar.

`DetachedQueryWindow`, aynı QueryController'ı başka pencereye taşır; session clone etmez. Geri yerleştirme de aynı controller/document ile yapılır. Serbest docking motoru yerine native resizable panes ve ayrılabilen sorgu pencereleri vardır.

`ServerVault` Security framework/Keychain generic-password kayıtlarını kullanır. `StudioState` opt-in Timeline ve kurtarma kayıtlarını kullanıcıya özel Application Support klasörüne atomik yazar (klasör 0700, dosyalar 0600). Snapshot parola içermez. SQL metinleri kullanıcı verisi olabilir; bu nedenle kalıcı kayıt varsayılan kapalıdır.

AI ulaşımı ephemeral URLSession ile yapılır. HTTPS ve loopback HTTP kabul edilir; redirects kapalıdır, bearer key başka origin'e gönderilmez. API anahtarı yalnızca açık panelin belleğinde tutulur. Eklenti formatı boyutu sınırlı, Codable JSON SQL şablonudur; binary kod yükleme veya otomatik yürütme yoktur.

Yeni modüller core'a server API / modeller, app'e ayrı controller/panel olarak eklenebilir. Executable target ile core bağımlılığı Xcode'da local Swift package üzerinden kuruludur. Kaynak proje ve runtime dependency yolları Apple Silicon yerel kullanımına göre ayarlanmıştır.

## Bağlantı keşfi ve görünür veritabanları (0.2.1)

`ServerDiscovery` test/listeleme için geçici ODBC bağlantılarını başarı ve hata yollarında kapatır. `ServerProfile.visibleDatabases` açık ad listesidir; nil eski kayıtların tümünü gösterme davranışını korur, boş dizi hiçbirini göstermez. Yeni form boş listeyle başlar. `selectDatabases` en az bir erişilebilir ad gerektirir ve varsayılan veritabanını seçimin içinde tutar. `ConnectedServer.databases` ve her ağaç yenilemesi profil filtresinden geçer; keşfedilen tüm katalog UI seçim ekranında kalır. Bu tercih yetkilendirme değildir; doğrudan SQL erişimini değiştirmez. Seçim düzenlenirken açık sorgu bağlantıları değiştirilmez. Kayıtlı profilde seçim güncellemesi Keychain'e yazılır; kaydedilmemiş bağlantı RAM'de tutulur.

## Ortam işaretleri ve bağlantı düzenleme (0.2.2)

`ServerProfile.appearance` isteğe bağlı Codable `ServerAppearance` içerir: ortam, özel etiket, isteğe bağlı RGB hex. Eski JSON profilleri nil ile çözülür. `hasSameConnectionSettings` ad/görünüm/varsayılan DB gibi UI alanlarını network oturum kimliğinden ayırır. Ortam işaretleri sadece görseldir; yürütme izni veya SQL filtresi değildir.

Aynı profil düzenlenirken aday metadata bağlantısı önce kurulur. Oturum kimliği değişiyorsa hem beklemeden önce hem aday hazır olduktan sonra tüm güncel sekmelerde running/transaction kontrol edilir. Değişim sırasında etkilenen sekmeler busy işaretlenir; metadata bağlantısı değiştirilir, sorgu bağlantıları kapatılıp yeni varsayılan DB'ye yeniden açılır. SQL/saved text/dosya korunur; eski sonuç/symbols temizlenir, runAfterConnect kapatılır. Hatalı aday eski profile dokunmaz. ConnectedServer generation token'ı geç biten eski katalog yüklemelerini ayıklar; ağaç kökü yeni generation'da yeniden üretilir. Görünüm değişiminde generation ve sorgu oturumları korunur.

`ConnectionForm` toolbar ve Object Explorer sağ tık girişlerinde ortak kullanılır. Hızlı görünüm paneli sorgu çalışırken de yalnızca UI profilini değiştirir. QueryController kendi bağlantı işaretini çizer; bu yüzden detached pencerede aktif ana sekmeden bağımsız doğru sunucuyu gösterir. Uygulama oturum testleri ayrı `StudioStateTests` hedefinde MainActor üzerinde çalışır; tarihçe/kurtarma bu testte kapatılır.


Kompakt yerleşim (0.2.4): QueryController native NSTabView içeriklerini noTabsNoBorder ile korur; ResultSelector aynı araç satırından seçer. Sonuç paneli görünürlüğü ve önceki ayırıcı oranı sorgu başına tutulur. LineNumbers TextKit 2 viewport fragment/glyph baseline konumlarını kullanır; TextKit 1 API erişimi yoktur. Editörün içerik yüksekliği gerçek TextKit usage bounds ve tahmini satır yüksekliğinin büyüğüyle hesaplanır.

## Bağlantı kullanım düzeni (0.2.5)

ConnectionForm sabit iki sütunlu bir Grid ve ayrı veritabanı paneli sunar. Test ve keşif sıralı async işlemlerdir; başarısız testte keşif yapılmaz, başarılı test otomatik keşfi başlatır. Değişmeyen aday yeniden test edilirse seçim/default korunur. Kimlik veya endpoint değişikliği testi ve listeyi geçersiz kılar. Kalıcı kaydetme yalnızca mevcut açık Keychain tercihiyle yapılır.

ConnectionForm ve DatabaseVisibilityForm aynı DatabaseChoices görünümünü paylaşır. ScrollView/LazyVStack yalnızca gerekli satırları oluşturur; dış form kaymaz. SQLServerKit.DatabaseSelection arama terimlerini, scope/selected-only filtrelerini, doğal sıralamayı, filtreye özel union/subtract işlemlerini ve deterministik default seçimini merkezi olarak uygular. Her filtre değişiminde gizli seçimler korunur. UI seçimi sunucu erişim yetkisi değildir.

## Birleştirilmiş bağlantı ayarları (0.2.6)

Object Explorer context menüsü tek editConnection eylemiyle ConnectionForm açar. Ayrı test/renk/veritabanı sheet controller ve formları kaldırılmıştır. Yeni bağlantı başlatma araç çubuğu/sidebar başlığı üzerinden korunur. ConnectionForm mevcut ConnectedServer alırsa `.task` ve instance başına didAutoTest guard'ı ile bir kez test + discover akışını başlatır. Test sonucu gerçek sunucu yanıtına bağlıdır; hatada manuel yeniden test mümkündür. İlgili alanların sonraki değişimi test ve listeyi sıfırlar. Görünüm/ad değişimi testi geçersiz kılmaz.

ConnectionAppearanceFields form içinde iki satırda gösterilir; ayrı popover yoktur. Uygula mevcut StudioState.connect doğrulama/oturum kurallarını kullanır. Görünüm ve veritabanı görünürlüğü değişiklikleri açık oturumları korur; credential/endpoint değişimi aday doğrulaması sonrası bağlantıyı değiştirir. Eski 0.2.5 bağımsız DatabaseVisibilityForm ve ConnectionAppearanceForm yolları artık kullanılmaz.


## Result grid ve disk sonuçları (0.2.7)

SQLServerKit.RowCollection, RandomAccessCollection ve Sendable bir snapshot'tır. Küçük/core çağrılarda değer semantiğine sahip RAM dizisini, GUI sorgularında kilitli ResultSpool'u kullanır. Snapshot satır sayısı sabittir; writer'ın sonraki parçaları eski snapshot'ı büyütmez. Spool her satırın ofset/uzunluğunu RAM'de tutar, ham JSON satırlarını özel geçici dosyaya yazar. Sıralı taramada bir ham parça cache'i; rastgele erişimde yalnızca ilgili satır okuması kullanılır. Bu seçim, sıralanmış grid'in her hücresinde tüm sayfayı JSON ayrıştırmasını önler. Son satır cache'i aynı satırın farklı hücrelerinde tekrar çözümlemeyi önler. Dosya hemen unlink edilir ve son referans deinit'inde descriptor kapanır; salt bir ResultSpool NSLock ile writer/UI/filter/export erişimini serileştirir.

Limits.diskResults açıkken ODBC 512 satır/1 MB tamponunu diske boşaltır; QueryEvent.snapshot en fazla yaklaşık 5 Hz ve sonuç sonlarında gönderilir. GUI aynı satırları ikinci bir RAM dizisine eklemez. Core sonuçlar RAM modunda kalabilir. Execution.bytesRead TSQL batch bütçesini satırları yeniden taramadan azaltır. Eski 64 MB/50.000 güvenli varsayılan korunur; GUI'den seçilen büyük modlarda 1m/5m, 2 GB ve 600 sn üst sınırları kullanılır. Bütçe aşımı kısmi sonuçtur.

ResultFiltering birden fazla ColumnRule + genel arama için kaynak indekslerini döndürür; filtresiz/sıralamasız görünüm nil kimlik projeksiyonudur. NULL/boş metin farklı CellChoice değerleridir. Distinct paneli en fazla 500 değer/4 MB tutar; değer araması tüm yüklenen snapshot'ı tarar, seçimler aramada korunur. Decimal karşılaştırması Double kullanmaz; tarih/offset girdileri ISO 8601 olarak ayrıştırılır. Sıralama anahtarları tek taramada cache'lenir, disk subscript'i comparator içinde çağrılmaz. İptal edilebilir stable merge sort eşit anahtarlarda kaynak sırasını korur. İndeksler/anahtarlar O(n) bellek kullanır; dış sıralama motoru yoktur.

ResultController yalnızca görünür hücreleri NSTableView reuse üzerinden çizer; otomatik satır ölçümü kapalı, sabit 24 pt'dir. Arka plan task'ı 220 ms debounce ve revision guard'ı ile eski sonuçların yeni filtreyi ezmesini engeller. View deinit işi iptal eder. Kolon kimliği ordinal indekstir; aynı adlı kolonlar ve başlık taşıma hücre incelemesinin yanlış kolon okumasına yol açmaz. Context menüsündeki fit örneklemesi 200 görünür satırla sınırlıdır. Genişlik/görünürlük düzeni yalnızca sonuç görünümüne aittir; SQL kolonlarını değiştirmez.

ResultFileExport snapshot + opsiyonel projeksiyonu arka planda 1 MB yazma tamponuyla serileştirir. Özel sibling temp dosyasını başarıda atomik olarak taşır/değiştirir. İptal/hata temp'i kaldırır; mevcut hedef korunur. CSV formül işaretlemesi, JSON sütun adı dizisi/NULL/duplicate-column semantiği korunur. Eski Export.csv/json string/Data helper'ları küçük/core kullanımlar için vardır; GUI büyük export bunları kullanmaz. Clipboard satır ve boyut sınırı vardır.


## Ortak native tasarım (0.2.8)

StudioTheme açık/koyu tasarım token'larını sağlar. Yalnızca studio.card / studio.chrome işaretli yüzeyler boyanır; genel NSTextField font/renk üzerine yazımı kaldırıldı. Decorate, tablo reloadData çağırmaz; ilerleme bildirimindeki recursive tema taraması kaldırıldı. QueryController tema bildiriminde görünür grid'i yenilerken seçimi geri yükler; kolon nesneleri yeniden oluşturulmaz. Editörün TextKit 2 tema/undo/selection davranışı bağımsız kalır.

StudioRowView seçimi sade, dikdörtgen yüzeyle çizer. FilterHeaderCell filtre etkinliği, sıralama yönü ve gerçek Field türüne göre SF Symbol çizer; boş uzatma alanında ikon göstermez. Grid render sırasında yeni SQL veya tam sonuç kopyası üretilmez. Filtre etiket alanının yüksekliği yalnızca aktif kolon koşulları varsa açılır. PlanController aynı header/row çizimini filtre kontrolleri olmadan kullanır.

StudioPanelStyle / StudioPanelHeading / StudioEmptyState / StudioPrimaryButton / studioEditor yardımcıları SwiftUI pencerelerinin font, vurgu, yüzey, başlık, boş durum ve SQL alanı sınırlarını paylaşır. Auxiliary hosting controller boyutlandırması pencere boyutunu korur; içeriğin başa hizalanması boş alanı başlık üstüne taşımaz. Tema değişikliği formun kimliğini yeniden yaratmaz; kullanıcı girdisi sıfırlanmaz.

## 0.2.9 grid etkileşimleri

CopyTable seçimi satır IndexSet’i ve görünür kolon IndexSet’i olarak tutar; milyonlarca hücre nesnesi üretmez. CellRowView yalnızca görünür hücre aralığını boyar. RowCollection/disk spool ve arka plan filtreleme korunur. # kolonu yerinden taşınamaz; kopyalama kolonların sabit ordinal kimliğini kullanır. ODBC SQLDescribeColW metadata’sına SQLColAttributeW / SQL_DESC_TYPE_NAME eklenmiştir.

QueryDocument son çalıştırılan SQL + veritabanı + başarılı yürütme bilgisini saklar. Her yürütme generation sayacını artırır; aynı satır sayılı yenilemeler de grid’e işlenir. QueryController kendi iptal edilebilir timer görevini yönetir; boş sonuç aşamasında eski grid controller’ını koruyup yeni snapshot ile günceller. Filtre ve kolon durumu korunur. Hatalı yenilemede eski veri güncelmiş gibi gösterilmez. TSQL.canRepeatRead muhafazakâr bir tekrar uygunluğu kontrolüdür, genel amaçlı SQL parser veya güvenlik sınırı değildir.

Query tab menüsü sağ tıklanan belgeyi hedefler. Toplu kapatma state.close yolunu kullanır, pin’li belgeleri atlar ve ilk iptalde durur. Pin alanı kurtarma JSON’unda optional olduğundan eski snapshot’lar okunur.

Keychain servis adı ve bundle ID sürüm içermez. UserDefaults lastSavedServer yalnızca profil UUID’sidir; parola Keychain’de kalır. ConnectionForm mevcut kayıtların son kullanılanını veya ilkini seçer. Kayıt başarılı bağlantıdan sonra yapılır.

## 0.2.10 ortak grid araç alanı

ResultController.toolbar gezinme/filtre temizleme kontrollerini üretir; QueryController.navigationHost yalnızca seçili grid’in araçlarını ana gridToolbar içine taşır. ResultController toolbarHosted modunda ikinci çubuk/boş yükseklik oluşturmaz; bağımsız native testte kendi çubuğunu korur. Her sonuç kendi filtre/kolon/sayfa durumunu tutar. Tab değişiminde eski araç alanı çıkarılır ve yeni grid’in alanı eklenir.

Clip view bounds-change gözlemcisi yoktur; kaydırma sayaç metni üretmez. pageStart yalnızca gezinme ve sonuç sayısı değişiminde sınırlandırılır; değişmeyen metin NSTextField’e tekrar atanmaz.

bit hücreleri ayrı bitCell reuse kimliği kullanır; salt okunur checkbox hitTest’i kullanıcı girişini grid’e bırakır, hedef/action almaz. NULL normal metin hücresidir. Panoya ve dışa aktarmaya dokunmadan kaynak değer kopyalanır. copySelectionData adı NSObject.copy çakışmasını önler.

GridShortcuts, AppStorage tercih anahtarı, kısayol eşlemesi ve değişim bildirimi ortak davranışıdır. Ayarlardaki sınırlı iki seçenek çakışmaları önler; serbest kaydedici/çakışma editörü gelecekte eklenebilir. Tooltip ve bağlam menüsü aynı tercih değerini okur.

## 0.2.11 çalışma alanı

Sonuç paneli gizlenirken split view’dan çıkarılır ve ayırıcı kalınlığı sıfırlanır. Soldaki özel tab strip içerik NSTabView seçimini yönetir. GridPaging kalıcı varsayılanı ve yerel sayfa aralığını yönetir; filtre indeksleri sayfalamadan önce uygulanır. Sayfalı kopyalama/dışa aktarma kaynak satır indekslerini korur. ResultSpool kilit altında 256 satır / 8 MiB sınırlı çözülmüş satır önbelleği kullanır. Otomatik genişlik örneklemesi en fazla 32 satır / 4096 hücredir; tüm veri taranmaz. QueryTabStrip native dragging source/destination ile UUID tabanlı yeniden sıralama yapar. GridShortcuts kayıtları ayarlarda gerçek tuş yakalama, çakışma kontrolü ve menü güncellemesini paylaşır.

## 0.2.12 Explorer / module editing

Recursive visible() filtresi kaldırıldı. Katalog sorgusu TOP501, 350ms debounce, tek uçuş ve UUID invalidation kullanır; 500 satır UI’ya aktarılır. Arama kapsamı ilk girişte seçili düğümden sabitlenir, boşaltılınca normal ağaç geri gelir. ALTER sekmesi özgün tanımı belgeyle tutar; preview lineer prefix/suffix, apply metadata bağlantısında iyimser karşılaştırma ve ardından bağımsız query oturumunda çalıştırma yapar. Başarılı committed basit DDL bildirimi yüklü ilgili tür klasörüne tek nesnelik katalog sonucu uygular; ağaç dolaşımı 200 düğümde Task.yield ile UI’ya zaman verir.

## 0.2.13 persistent catalog

CSQLite system module is linked through SQLServerKit. CatalogDiskIndex serializes SQLite access off the main actor. objects(scope,id) is WITHOUT ROWID, with name/qualified-name/kind indexes. Completed scopes carry count and synchronization time. CatalogIndexService builds keyset pages of 1000 into a UUID staging scope, then atomically publishes it; failures preserve the old scope. builds tracks staging age for cleanup after one day. WAL and bounded page cache keep database access independent of UI rendering.

Single-flight builds, 300-second freshness and 60-second retry backoff are per scope. DDL target updates wait for an in-flight build. Warm searches return immediately; stale refresh notifies the UI only if the published timestamp changed, avoiding feedback loops. SQLite progress handlers support cancellation. Contains/suffix scan the local scope. SQLite file integrity is shared across app processes, but server snapshot/DDL order has no cross-process coordinator.

## 0.2.14 lifecycle and local updates

Explorer active UUIDs are persisted separately from query recovery. Initial migration includes saved Keychain profiles; explicit empty selection remains empty. Startup creates offline placeholders before network connection, then restores visible database selections from the saved profile. Failure preserves the Explorer instead of reopening setup. Search scopes are explicit cloned database nodes, persisted by server UUID/database; clearing text and tree selection do not reset scope.

ApplicationUpdate validates ZIP root paths, rejects symlinks, checks code signature/bundle identity/newer version and extracts to a protected staging directory beside the destination. Helper waits for the current PID to exit, moves the app to a backup, swaps and verifies the replacement, then reopens. Failure attempts rollback. This local update foundation has no network feed or developer-publisher trust anchor. Prepared staging is tested without replacing user applications.

## 0.2.15 Explorer indeks hazırlığı
ConnectedServer bağlantı açılışında iptal edilebilir bir hazırlık göreviyle seçili DB'leri sırayla CatalogIndexService'e gönderir. Tek DB için aynı anda gelen yenilemeler service tarafından paylaşılır; SQLite atomik snapshot korunur. Arama ağ çağrısı yapmadan hazır disk indekslerini tarar, toplam 501 kayıtlık tamponla ilk 500 sonucu gösterir. Kapsam UUID|* ile Explorer, UUID|DB ile veritabanı olarak saklanır. Güncelleme kaynağı uygulama bundle'ındaki MSSQLUpdateFeedURL'dir; kaynak yokken güncel olduğu iddia edilmez.

## 0.2.16 Arama ağacı ve editör
Arama kapsamından bağımsız Nesneler/Arama görünüm durumu tutulur. Aramaya girişte yalnızca görünür/açık node referansları, seçim ve clip origin saklanır; ağacın tamamı dolaşılmaz veya server'dan yeniden yüklenmez. Ağacı geri yüklerken üstten alta açık node'lar açılır. Arka planda biten arama Nesneler görünümünü reload etmez.

EditorController TextKit 2'yi korur. Lexeme renkleri mevcut foregroundColor run'larıyla karşılaştırılır ve sadece değişen run'lar tek storage transaction'da boyanır. Font ve paragraph attributes yalnızca ilk metin/tema kurulumu sırasında ayarlanır; klavyede bütün metin biçimi sıfırlanmaz. NSScrollView tile sonrası viewport ölçülür. Text container gerçek ölçülmüş satır genişliğine göre sınırlandırılır; kısa metin için x offset sıfırlanır. Tab interval monospace boşluk genişliği x4; kaynak TAB/boşluk dizisi korunur.


## DDL editör analizi (0.2.20)

SQLCatalogService ayrı metadata bağlantısıyla sayfalı nesne/kolon listesi üretir. CatalogDiskIndex completion_snapshots tablosu yalnızca tam snapshot yayınlar. Immutable SQLIntelligence.Catalog qualified/name/prefix indeksleri ortak actor önbelleğinde tutulur. QueryDocument aktif database + server generation + request kimliğiyle eski cevapları reddeder. EditorController 260 ms debounce ardından detached analiz çalıştırır, iptali iletir; kaynak/imleç/generation değişmişse sonuç yayınlamaz. TextKit 2 storage yalnızca renk/underline/tooltip değişikliği alır. Tamamlama NSPopover/NSTableView ile editör odağını korur; kabul tek native insertText/undo işlemidir. Katlanmış projeksiyonda anlamsal analiz durur; açılınca kaynak üzerinde sürer. Sınırlar ve desteklenmeyen gramer README'de belirtilir.


## 0.2.21 sonuç çizimi ve alias tercihi

ResultsView cell-based NSTableView kullanır. Kolon başına yeniden kullanılan GridDataCell, metin/NULL veya salt okunur bit kutusunu çizer; hücre başına NSView/Auto Layout oluşturulmaz. Seçim görünür satır/kolon dikdörtgenlerinde çizilir. ResultSpool disk depolaması ve sınırlı decoded-row cache (8 MiB / 256 satır) korunur. Geniş sonuçta görünmeyen tüm kolonların view oluşturma maliyeti kaldırılmıştır.

SQLIntelligence otomatik aliası büyük harfle üretir ve çakışmaları harf duyarsız denetler. sqlAutomaticNoLock boolean tercihi varsayılan false; sadece otomatik FROM/JOIN relation aliası üretilen completion item metnine uygulanır. Background analiz mevcut debounce/cancellation/stale-result korumalarını kullanır.


## 0.2.22 editör ve indeks durumu

Grid NSScrollView.usesPredominantAxisScrolling kullanır. Metin eşleşmesi yalnız seçim değişince bounded NSTextStorage backgroundColor aralıklarıyla boyanır; ODBC çalıştırmaz. TextKit2 korunur, Writing Tools kapalıdır. Navigasyon tokenı güncel belge scope'undaki Catalog üzerinden çözülür; metadata bağlantısında object_id/tanım alınır, yeni QueryDocument hazırlanır. Tablo scripti açıkça kolon-only preview'dir; modüllerde moduleOriginal karşılaştırma tabanı saklanır. Hiçbiri otomatik execute edilmez.

QueryDocument eski catalog için arka plan refresh'ini rate-limit eder. Explorer ayrı indeks durum alanını SQLite/SQLCatalogService üzerinden asenkron okur; scope değişiminde stale-task cancel edilir. Metadata hatası/son tarih ve nesne/kolon index ayrımı görünürdür.

## Nesne yönetimi (0.2.23)

`ObjectManagement.swift` UI'dan bağımsız `TableDefinition`, `ObjectMetadata`, `ObjectScripts` ve `DataEditScripts` içerir. Metadata yedi sonuç kümesinde kolonlar, PK, key/index, FK, check, trigger ve desteklenmeyen tablo seçeneklerini getirir. Farklı katalog / veritabanı collation'ları `DATABASE_DEFAULT` ile normalize edilir. Kısmi/eksik metadata'dan CREATE oluşturulmaz. Standart rowstore dışındaki özellikler açık hata üretir; permissions/extended properties/istatistikler taşınmaz.

`ObjectManagementPanels.swift` sağ tık işlemlerini native SwiftUI pencerelerine bağlar. Table designer kolon farklarını ALTER/ADD/DROP/sp_rename ve default/PK değişikliklerine çevirir; mevcut tabloyu kendiliğinden yeniden oluşturmaz. Index/FK/check formları ve permissions alanı gözden geçirilebilir SQL üretir. View designer TextKit 2 `EditorController` kullanır; asenkron yüklemede değer snapshot'ı SwiftUI representable güncellemesini tetikler. SQL'e aktarım ana çalışma penceresini öne getirir. Tüm işlemler seçilen bağlantı ve veritabanı bağlamında yeni bağımsız sorgu oturumu açar; otomatik çalıştırılmaz.

Veri editörü en fazla 200 başlangıç satırını PK sırasıyla ayrı metadata bağlantısından okur. Hücre tabanlı NSTableView yalnızca görünen hücreleri çizer; genel sonuç grid'inin disk spool/paging davranışı değişmez. Mevcut anahtar/generated alanlar düzenlenmez. Üretilen UPDATE/DELETE orijinal PK ve rowversion (yoksa tüm karşılaştırılabilir orijinal değerler) içerir; @@ROWCOUNT tam 1 değilse THROW ve transaction rollback uygulanır. Karşılaştırılamayan türler rowversion olmadan reddedilir; string karşılaştırması byte eşitliğini de denetler. INSERT yalnızca dokunulan kolonları içerir; kalan alanları SQL Server default'ları belirler. En fazla 400 değişiklik satırı kabul edilir. SQL çalıştırma sonucu hata/partial durumları mevcut QueryDocument tanılarıyla görünür kalır.

`ObjectManagementUIFixture` yalnızca `local.mssqlstudio.uitest` / UI smoke başlangıç dalında atanır. Sentetik bağlantı offline kalır; Keychain veya kullanıcı sunucularına erişmez. Canlı çekirdek testleri yalnızca localhost'ta benzersiz nesneler ve connection-local #temp kullanır, rollback/disconnect ile temizler.

## Genelleştirilmiş Explorer yönetimi (0.2.24)

TreeNode parent weak'tir; children ataması parent'ı kurar. objectFolder ve ownerObject alt nesneyi doğru tablo/view/modüle bağlar. DML trigger metadata sys.triggers parent_class=1, database DDL trigger parent_class=0 üzerinden gelir. İkon/durum katalog is_disabled bilgisine dayanır. Metadata worker bağlantısında okunur, AppKit değişiklikleri MainActor'dadır.

RoutineScripts tipli parametre metadata'sını UI'dan bağımsız doğrular ve inceleme SQL'i üretir. TriggerDefinition scope/parent/state/drop semantiğini tek yerde tutar. ExplorerScripts modül başlığını lexer ile değiştirir; gövde/comment/string korunur. Synonym hedefleri 1–4 qualified identifier parçası olarak yeniden escape edilir. Değerler literal quoting ve CONVERT, identifier'lar merkezi SQL.identifier üzerinden geçer. TVP ve desteklenmeyen türler açık hata verir.

ObjectManagementPanels modül, invocation, trigger, synonym ve alt structure menülerini ortak SQL-review akışına bağlar. QueryDocument managedObjectApplied callback'i başarılı/nonpartial, estimated olmayan ve transactionCount=0 sonucunda çağırır; SQL tokenları hedef yönetim komutlarını içeriyorsa ilgili Explorer dalı yenilenir. Transaction içinde yapılan değişiklikte manuel COMMIT sonrası refresh gerekir. TableDesigner kontrol çubuğu ScrollView dışında; minimum pencere 800×600, içerik iki eksenli ve lazy kolon satırları kullanır. Genel sonuç grid çizicisi ve disk spool davranışı değişmez.

## Editör seçim ve katlama sunumu (0.2.25)

SQLTextView word granularity aralığını SQL identifier karakterlerine göre sınırlar; noktalama için composed character range kullanır. Double-click yalnız seçim / folded ellipsis açma yapar; definition navigation command click veya command B ile ayrıdır. Selection notification boyamayı 90 ms geciktirir, önceki task'ı iptal eder, kaynak/seçim snapshot'ını doğrular. Native mouseDown tracking sırasında occurrence boyaması engellenir; mouse-up callback'i son seçimi boyar. Bounded occurrence boyaması selectedRanges'i saklar ve geri yükler; karakter, dirty veya undo mutasyonu yapmaz.

SQLFolding.Projection özgün source'u saklar. EditorController.setText değişmeyen source için no-op'tur; SwiftUI update katlamayı sıfırlamaz. IF/ELSE + hemen sonraki BEGIN başlığı satır gruplu token lookup ile bağlanır. Fold işlemi TextKit 2 caret segment geometrisiyle başlık/viewport konumunu korur. Collapsed marker display range'leri background/tooltip ile ayrı dekore edilir; source range eşleme ve SQL çalıştırma kaynağı özgün metindir. Bir ellipsis seçimini açmak gizli bloğu bütünüyle seçmez. Mevcut edit/undo öncesi expand koruması devam eder.

TableDesigner kolon seçiminde SwiftUI FocusState kolon ID + alan ID ile bağımsızdır. Satır seçicisi ad alanına odaklanır; ad/tip/default odağı seçili satırı günceller. ScrollViewReader sadece yeni kolon eklenince son seçilen satırı görünür kılar; sıradan alan seçimi scroll komutu üretmez. Kontrol çubuğu scroll dışında kalır. Yeni kolon adı mevcut adlara harf duyarsız bakılarak benzersiz oluşturulur.

## Editör find, gecikme ve odak (0.2.26)

SQLTextView, native mouseDown seçim döngüsü bittikten sonra yalnız identifier karakterlerinden oluşan seçimi normalizeSQLWordSelection ile genişletir; @/@@/# gibi SQL önekleri native word sınırlamasıyla düşmez. Ellipsis açma önce değerlendirilir; çok kelime, punctuation ve emoji seçimleri bu son normalizasyonda genişletilmez. Native selectionRange composed-character desteği sürer.

Ctrl+F hem key equivalent hem keyDown yolunda yerel showSelectionFind'a gider. performFindPanelAction(showFindInterface), seçim boş değilse önce native setSearchString gönderir; ⌘F menüsü de aynı override'ı kullanır. Popup kapatılır; ayrı search implementation, SQL mutasyonu veya TextKit 1 geçişi yoktur.

SQLEditorPreferences completionDelayMilliseconds alanını UserDefaults'ta tutar; yoksa 260 ms, mevcut değer 50–1.000 ms aralığına sınırlandırılır. SettingsPanel 10 ms adımlı slider, varsayılana dönme ve Uygula sağlar. EditorController, istek başında ayarı snapshot alır; manuel tamamlama beklemez. Mevcut cancellation/source/caret generation korumaları aynıdır.

Workbench.renderActive yalnız yeni QueryController oluşturulunca, view embed edildikten sonraki main queue adımında focusEditor çağırır. Aktif doküman ID'si, doğru host view, detached durumu ve sheet yokluğu tekrar kontrol edilir; eski async odak isteği yeni sekmeyi veya modal ekranı bozmaz. Mevcut controller'ı güncellemek odak isteği üretmez. İzole UI test bundle'ında offline yeni query oluşturulmasına izin verilir; offline QueryDocument.connect hiçbir ağ erişimi yapmaz.

## 0.2.27 nesne kimliği, değişiklik ve Agent katmanı

`ObjectEditorKey(serverID,database,objectID)` kaynak nesne sekmesinin kimliğidir. Normal dosya kirliği `sql != savedText`; nesnenin uygulanmamış değişikliği `sql != moduleInitialSQL` ile bağımsız izlenir. `moduleOriginal` sunucunun ham tanımıdır; SET/GO/ALTER ile hazırlanmış editör metni sunucu conflict kıyasına sokulmaz. Başarılı gönderim yalnızca gönderilen anlık görüntüyü baseline yapar; yürütme sırasında yeni yazılanlar bekleyen değişiklik olarak kalır. Snapshot alanları geriye uyumlu optional kaydedilir, bağlantı yeniden bağlanınca server kimliği yeniden eşlenir.

`ModuleReviewController` TextKit 2 salt okunur iki kaynak görünümü ve gerçek yürütülecek SQL sekmesi sunar. `SQLTextDiff` ortak önek/son eki ayırır, sınırlı orta blok için satır farkı hesaplar; büyük değişimde lineer replacement kullanır. UI text layout boyutu ve satır sayısı sınırlandırılır, kısmi incelemeden Apply kapatılır. Compare işi arka planda; yayın ve native görünüm ana actor'dadır. Onayda güncel tanım yeniden okunur ve editör/DB snapshot'ı doğrulanır; atomik şema kilidi veya üç yönlü merge yoktur.

`SQLAgent` msdb sorguları, UUID doğrulamalı komutlar, iş/adım/zamanlama/geçmiş modellerini içerir. Geçmiş TOP 500, iş listesi TOP 1.000; history filtreleri sunucuda uygulanır. Komutlar keyfi job adını işlem kimliği olarak kullanmaz, panel açılınca gerçek job UUID'si okunur. Properties ve schedule tasarım SQL'i sorgu sekmesine aktarılır; açık command paneli kullanıcı Uygula'sıyla ayrı metadata bağlantısında yürütür. Başarı bildirimi yalnızca ilgili sunucunun yüklenmiş Agent klasörlerini yeniler. İş Start/Stop ile işletim sistemi Agent servisini Start/Stop farklıdır; servis salt okunur izlenir.
