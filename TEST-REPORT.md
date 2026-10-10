# MSSQL Studio 0.2.39 — yayın doğrulaması

10 Ekim 2026. `b20f901` commit’i `v0.2.39` etiketiyle yayımlandı ve latest olarak doğrulandı. https://github.com/erhanulas/MSSQLStudio/actions/runs/38011208918 başarılı: kalıcı imza, uygulama/PKG derlemesi, manifest ve yayın paketiyle tüm testler geçti. 149 raporlanan test: 127 geçti, 22 koşullu test atlandı. ZIP, PKG ve update.json yayımlandı; latest/download/update.json sürümü 0.2.39 olarak doğrulandı. Kurulu uygulama ve veritabanı bu yayın görevinde değiştirilmedi.

0.2.38 CI: ekran boyutu testi geçti; eski occurrencePainting testinin 140ms temizleme beklemesi yük altında yetersiz kaldı. Test 2 saniye üst sınırla koşul gerçekleşene kadar bekleyecek biçimde düzeltildi; sıfır eşleşme koşulu korundu. Yeniden yayın 0.2.39 / build 40.

0.2.37 yayın denemesinde derleme/imzalama başarılı, testte sabit >1080 pencere genişliği beklentisi CI küçük ekranında başarısız oldu (gerçek genişlik 963). Ekrana uyarlama davranışı doğruydu. Test görünür ekran alanı ve minimum genişliğe göre beklenen boyutu hesaplayacak şekilde düzeltildi. Yeniden yayın 0.2.38 / build 39; 0.2.37 Release oluşturulmadı.

# Fark önizlemesi ve nesne gönderme — yerel geliştirme doğrulaması

10 Ekim 2026. DataGrip resmi kaynak güncelleme akışı incelendi: https://www.jetbrains.com/help/datagrip/update-source-code-of-database-objects.html . Karşılıklı ok diff ikonu ve tray.and.arrow.up gönderme ikonu; ikisinden açılan önizlemede koşullar uygunsa Veritabanına Gönder. `QueryDocument.canSubmitModule` bağlantı, hazır/busy durumu, açık transaction, nesne ID'si, hedef DB ve bekleyen değişiklik koşullarını birleştirir. Mevcut ham sunucu tanımı çakışma kontrolü ve gönderilen snapshot baseline ilerletmesi korunur; kontrol sürerken tekrar gönderme engellenir. Kısmi büyük önizlemede gönderme kapalı kalır.

SQLSourceHighlighting ana editör ve önizlemeye aynı syntax/unused renklerini sağlar. Diff satırları tam SQL kaynağının renklendirilmiş aralıklarından alınır; satır numaraları lexere karışmaz ve multiline yorum/string renkleri korunur. Genel pencere dekorasyonu sqlSourcePreview metninin foreground renklerini sıfırlamaz. Panel 1400×840 hedef, ekran görünür alanıyla sınırlı ve minimum 960×600. Satır genişliği gerçek font ölçüsüyle; ilk fark gösterilirken yatay başlangıç x=0 korunur.

Son Release derlemesi başarılı. Tam testler 58 uygulama + 91 core = 149 raporlanan test: 127 geçti, 22 koşullu test atlandı. İki yeni test gönderme uygunluğunu ve gerçek NSPanel'de üç SQL görünümünün renklerini, multiline kaynak eşlemesini, genel tema dekorasyonu sonrası renklerin korunmasını, TextKit 2/read-only yapısını, x=0 başlangıcını ve yalnız düğmeye basınca callback çağrılmasını doğrular. Mevcut baseline, katlama, seçim ve SQL testleri geçti. Paket/imza veya canlı DB yazma testi bu görevde yapılmadı. Mevcut gutter accessibility/main actor uyarısı sürüyor.

Native smoke ayrı local.mssqlstudio.uitest kimlikli çevrimdışı ObjectManagementUIFixture üzerinden yapıldı: Modify ALTER ile SalesByCity açıldı; her iki header ikonu erişilebilirlik ağacında görüldü, offline gönderme pasifti. Büyük panelde renkli yan yana diff, çok satırlı yorum, string ve unused isimler doğrulandı. Son derlemede Çalıştırılacak SQL sekmesinde renklerin kalıcı olduğu da görüldü. Yatay scrollbar başlangıcı 0 idi. Fixture düzenlemeleri undo ile geri alınıp test uygulaması kapatıldı. Gerçek kullanıcı sunucularına SQL gönderilmedi, kurulu uygulama değiştirilmedi. GitHub yayını henüz yapılmadı.

Kanıtlar: `/tmp/mssql-review-build-final.log`, `/tmp/mssql-review-tests-final3.log`.

# Katlama düğmesi görünümü — yerel doğrulama

10 Ekim 2026. Son değiştirilen blokta kalan mavi yan çizgi ve buna ait durum takibi kaldırıldı. Kapalı blokta + düğmesi StudioTheme.accent dolgu ve kontrastlı simgeyle belirgin; açık blokta − düğmesi normal arka plan/gri çizgiye döner. Vurgu doğrudan mevcut katlama durumundan hesaplanır.

Release derlemesi ve tam testler başarılı: 147 raporlanan test, 125 geçti, 22 koşullu test atlandı. Yalıtılmış çevrimdışı native uygulamada IF fareyle kapatıldı/açıldı: kapalı düğme mavi, açık düğme normal; yan çizgi yok, kaynak satırlar geri geldi. Test metni temizlenip uygulama kapatıldı. Yeni yayın yapılmadı. Kanıtlar: `/tmp/mssql-fold-button-build.log`, `/tmp/mssql-fold-button-tests.log`.

# Kullanılmayan DECLARE değişkenleri — yerel geliştirme doğrulaması

10 Ekim 2026, 0.2.36 üzerine. `TSQL.unusedDeclaredVariables` lexer ile batch içinde DECLARE adlarını ve diğer referanslarını karşılaştırır; yalnızca tanımda geçen adın foreground rengi soluklaştırılır. Yorum/string/quoted identifier kullanımları dışlanır. Harf büyüklüğü göz ardı edilir; farklı adlar tam eşleşir. GO yalnız bağımsız satırda ayırıcıdır; çoklu DECLARE, AS türü, decimal/fonksiyon argümanlarının virgülleri ve tablo değişkenleri desteklenir. Yarım kalan ad/tür beklenir. Atama da kullanım kabul edilir; veri akışı/dead-store analizi ve rutin başlık parametreleri kapsam dışıdır. 250.000 UTF-16 sınırı korunur. Katlama kaynak metin üzerinden hesaplanır; gizlenen referanslar korunur. Kaynak değişmedikçe sonuç önbellekte tutulur, seçim değişikliği yeniden boyama oluşturmaz.

Release derlemesi başarılı. Tam test çalışması: 56 uygulama + 91 çekirdek = 147 test; 125 geçti, 22 koşullu test atlandı. Dört yeni test çoklu/Unicode DECLARE, yorum/string/benzer isimler, GO, procedure/fonksiyon gövdeleri, eksik tanım, değişen kullanım rengi ve katlamayı kapsar. Önceki seçim/viewport, TextKit 2, undo/redo, find ve completion testleri geçti. Mevcut gutter accessibility/main-actor uyarısı sürüyor.

Native smoke ayrı `local.mssqlstudio.uitest` kimlikli ad-hoc kopyada ve çevrimdışı yapıldı. `@Unused` açık gri, `@Used` normal görünüyordu; IF katlanınca gizlenen @Used referansı korundu; SELECT @Unused eklenince tanım normal rengine döndü. Test metni temizlenip test uygulaması kapatıldı. Kurulu uygulama ve sunucu verileri değiştirilmedi. Koyu tema rengi tanımlı; bu çalışmada koyu temanın görsel kontrolü yapılmadı. Yeni GitHub yayını yapılmadı.

Yerel kanıtlar: `/tmp/mssql-unused-tests-final.log`, `/tmp/mssql-unused-build-final.log`. Geçici derleme: `/tmp/MSSQLStudio-unused-build`.

# MSSQL Studio 0.2.36 — yayın doğrulaması

10 Ekim 2026. `dd0e99e` commit’i `v0.2.36` etiketiyle GitHub’da yayımlandı ve latest olarak doğrulandı. Actions çalışması https://github.com/erhanulas/MSSQLStudio/actions/runs/38008676383 başarıyla tamamlandı: kalıcı imza kontrolü, uygulama/PKG derlemesi, manifest doğrulaması ve yayın paketiyle testler geçti. 143 test raporlandı: 121 geçti, 22 koşullu test atlandı. Yayın varlıkları: `MSSQLStudio-0.2.36.pkg`, `MSSQLStudio-0.2.36.zip`, `update.json`. Kurulu uygulamaya bu görevde güncelleme uygulanmadı.

0.2.35 etiketi için CI derleme/imzalama başarılı oldu; yayın, vurgu testinin paralel tema değişimlerini de sayması nedeniyle durdu. Vurgu işleminin storage gözlemi eşzamanlı bölüme alındı; tema değişikliğiyle karışmadan sıfır düzenleme koşulu korunuyor. 0.2.35 yayını oluşturulmadı; yeniden yayın 0.2.36 olarak hazırlanıyor.

# MSSQL Studio 0.2.36 — editörde katlama ve kelime vurgusu

10 Ekim 2026. `v0.2.34` üzerine hazırlanan 0.2.36 / derleme 37. Aşağıdaki sonuçlar yerel geliştirme doğrulamasıdır; kişisel imzalı yayın paketinin derleme ve testleri GitHub Actions tarafından ayrıca yürütülür.

Katlama artık bütün `NSTextView.string` değerini yeniden atamak yerine değişen UTF-16 aralığını güncelliyor. Gizlenen kod, kaynak SQL'de korunuyor. Tam yerleşim hesabı katlamanın desteklendiği 250.000 UTF-16 sınırı içindeki metinlerde tamamlanıyor; başlığın gerçek ekran konumu geri yükleniyor. TextKit'in tahmini kullanım yüksekliğinin sonradan kaydırmayı değiştirmemesi için editör boyutu açıkça yönetiliyor. Satırların gerçek yüksekliği font leading nedeniyle 18 punto paragraf ayarından farklı olabildiğinden konum hesabında satır sayısı çarpımı kullanılmıyor. Dosya sonunda bir görünüm yüksekliği kadar kaydırma payı bulunuyor. Yatay kaydırma, iç içe katlama ve tümünü açarken görünür kaynak satırı korunuyor. Gizlenen alanın içindeki imleç blok başlığına taşınıyor; son değiştirilen başlık gutter'da ince renkli çizgiyle işaretleniyor.

Kelime eşleşmeleri `NSTextStorage` biçim özelliklerine yazılmıyor. Fareyi engellemeyen `OccurrenceHighlights` görünümü mevcut TextKit 2 geometrisi üzerinde sarı işaretleri çiziyor; seçili kelime native seçim rengini koruyor. Kaydırmada görünür eşleşmeler yeniden çiziliyor; metin düzenlendiğinde eski işaretler temizleniyor. Değişmeyen metin/tanı sonuçlarında syntax biçimleri tekrar uygulanmıyor.

**Son doğrulama:** Release derlemesi başarılı. Tüm test çalışması **55 uygulama + 88 çekirdek = 143 test / 27 suite** raporladı: **121 geçti, 22 koşullu test atlandı**. Üç yeni regresyon; (1) seçim/vurgu değişimlerinde sıfır text-storage edit bildirimi, değişmeyen biçim/metin/viewport ve çizilebilir eşleşme geometrisi, (2) 1.200 ön satırdan sonraki büyük IF bloğunun dört aç/kapa döngüsünde gecikmiş layout sonrası gerçek başlık konumunun 1 punto altında farkla korunması, (3) yatay kaydırma ve tümünü açmada görünür kaynak satırının korunması. Mevcut Unicode, iç içe katlama, SQL kaynak eşleme, undo/redo, Bul ve completion testleri de geçti. Önceki aralıklı UI test çökmesi bu çalışmada tekrarlanmadı. Mevcut gutter accessibility/main-actor uyarısı sürüyor.

**Native UI:** Son Release'in ayrı `local.mssqlstudio.uitest` bundle kimlikli/ad-hoc imzalı kopyası kullanıldı. Gerçek çift tıklama `Customer_Name` kelimesini seçti; diğer üç kullanım sarı görünürken bütün SQL okunabilir kaldı. Seçim açıkken IF kapatılıp açıldı; başlık aynı konumda, kaynak satır numaraları doğru, seçim aynı kelimede kaldı. Son değiştirilen başlığın çizgisi ve katlanmış marker görüldü. Test sorgusu temizlenip uygulama kapatıldı. Kare bazında yüksek hızlı video/FPS ölçümü yapılmadı.

`releases/MSSQLStudio-editor-onizleme.zip`, bu yalıtılmış ve çevrimdışı oturumla başlayan UI önizlemesini içerir; ZIP yeniden çıkarıldıktan sonra strict/deep ad-hoc imza doğrulaması geçti. Kişisel sertifikalı dağıtım paketi, PKG veya otomatik güncelleme değildir. Kurulu uygulama değiştirilmedi. Canlı SQL/Agent, gerçek AI/Kerberos ve Keychain testleri yürütülmedi. Güncelleyici testleri önceki yayımlanmış kişisel imzalı 0.2.34 ZIP'ini doğruladı; önizleme ZIP'inin yayın imzasını temsil etmez.

Kanıtlar: `Validation/editor-stability-build.log`, `Validation/editor-stability-full-tests.log`, `Validation/editor-stability-tests.log`, `Validation/editor-stability-ui.txt`. Önceki başlangıç doğrulaması aşağıdadır.

# MSSQL Studio 0.2.34 — geliştirme başlangıcı doğrulaması

10 Ekim 2026, Europe/Istanbul. GitHub `releases/latest` yanıtı `erhanulas/MSSQLStudio` deposunda `v0.2.34` sürümünü gösterdi (yayın: 02:16:03). Etiket commit'i `822c36f4c7922ff780400f7e72b0808f22dddd44` yeni yerel kopyaya alındı; çalışma dalı `codex/continue-v0.2.34`. Kontrol anında `origin/main` üzerindeki `3fd4b1b3172a73dd8cdd6de80ef3df6460f90c24` yalnızca yayın sonucu belgesini değiştiriyordu. Başlangıç kodu yayın etiketinde tutuldu.

- Ortam: Apple Silicon, macOS 27.2, Xcode 27.0 (27A266a), Swift 6.4, unixODBC 2.3.14. Microsoft ODBC Driver 18 kaydı ve OpenSSL 3 kütüphanesi mevcut.
- Kaynaktan Release derlemesi `CODE_SIGNING_ALLOWED=NO` ile başarılı. Derleme çıktısı `/tmp/MSSQLStudio-baseline.wKRJyj/DerivedData` altında; bu geliştirme doğrulaması yeni bir kişisel imzalı yayın değildir.
- Yayımlanan ZIP indirildi. SHA-256 `44b481b72ad103131a93907f79cc811b98f80fbb50f58c87a03bd2935962f77b`, GitHub varlık özetiyle eşleşti. ZIP açıldıktan sonra `scripts/signing.py verify` sabit kişisel sertifika ve designated requirement denetiminden geçti.
- `MSSQL_UPDATE_ZIP` bu gerçek ZIP'e yönlendirilerek `scripts/test.sh` bir kez çalıştırıldı: **52 uygulama + 88 çekirdek = 140 test / 27 suite raporlandı; 22 koşullu test atlandı, 118 test geçti.** Gerçek imzalı güncelleme hazırlama ve farklı imzalı paketi reddetme testleri yürütüldü; güncelleme kurulmadı. Ortam gerektiren performans testlerindeki erken dönüşler benchmark doğrulaması sayılmaz.
- Yerel Release çıktısının farklı bundle ID (`local.mssqlstudio.uitest`) ve ad-hoc imzalı kopyasında native arayüz kontrolü yapıldı. Geçmiş/kurtarma kapalıydı, sentetik çevrimdışı oturum kullanıldı. SQL yazma ve undo/redo sonrasında metin korundu; seçili `BaselineCheck` ile ⌘F iki eşleşme gösterdi. Hakkında penceresi **0.2.34 / derleme 35** ve doğru sürüm notlarını gösterdi. Test metni temizlendi ve test uygulaması kapatıldı. SQL yürütülmedi.

Mevcut `EditorView.swift:225` uyarısı sürüyor: `GutterAction.perform` main actor özelliğine nonisolated erişilebilirlik callback'inden erişiliyor. Derlemeyi engellemedi; bu başlangıç çalışmasında düzeltilmedi. AppIntents bağımlılığı bulunmadığı için metadata çıkarımı atlandı. Önceden kaydedilen `NSTextFinderIndicatorManager` / signal 11 arayüz testi çökmesi bu koşuda tekrarlanmadı; kök nedenin giderildiği iddia edilmez.

Canlı SQL Server/Agent, gerçek AI sağlayıcısı, Kerberos, Keychain yaşam döngüsü, Installer ve performans benchmark'ları bu çalışmada doğrulanmadı. Uygulama kaynakları değiştirilmedi; yalnızca geliştirme ve test belgeleri güncellendi. Yeni sürüm yayımlanmadı.

Kanıtlar: `Validation/baseline-build.log`, `Validation/baseline-tests.log`, `Validation/baseline-context.json`, `Validation/baseline-ui.txt`. `Validation/` yerel ve Git dışında tutulur; `/tmp` çıktıları geçicidir. Aşağıdaki bölümler önceki çalışmaların tarihsel kayıtlarıdır.

# MSSQL Studio 0.2.33 — Editör araç çubuğu — 10 Ekim 2026

Farkları Gör düğmesi erişilebilirlik adı ve tooltip taşıyan bir karşılaştırma ikonuna çevrildi; editör başlığındaki DB’ye Uygula düğmesi kaldırıldı. Mevcut nesne sekmesi görünürlük ve sorgu çalışırken pasif olma davranışı korunur.

Değişiklik sonrası imzalama kapalı Release derlemesi başarılı. ManagementWorkspaceTests, PremiumLayoutTests ve CompactLayoutTests kapsamındaki 10 test / 3 suite geçti. Yeni dağıtım paketi üretilmedi, kurulu uygulama güncellenmedi, canlı SQL Server testi yapılmadı.

Başlangıç kontrolünde çekirdek test hedefi başarılıydı; tüm test komutu ise StudioStateTests sürecinin signal 11 ile çökmesi nedeniyle başarısız oldu. macOS çökme kaydı NSTextFinderIndicatorManager._delayedUpdate / objc_msgSend zincirini gösteriyor; kök neden bu küçük arayüz değişikliği kapsamında çözülmedi. Odaklı 10 testin geçmesi bütün test paketinin geçtiği anlamına gelmez. Önceden var olan EditorView.swift:225 main actor uyarısı da başlangıç derlemesinde görüldü.

Bu kontrolün kayıtları: /tmp/MSSQLStudio-audit-tests.beFMfa/tests.log, /tmp/MSSQLStudio-audit-tests.beFMfa/editor-toolbar-tests.log ve /tmp/MSSQLStudio-audit-build.oIw2HC/editor-toolbar-build.log. Aşağıdaki bölümler önceki sürümlerin tarihsel doğrulamalarıdır.

## 0.2.34 yayın hazırlığı

Vurgulama çizimi değişikliği için kişisel imzalı ZIP/PKG üretildi. prepare-release ZIP ve PKG imza kimliğini, metadata/binary eşleşmesini, release notes ve update manifestini doğruladı. Gerçek ZIP ile tüm testler başarılı: 52 uygulama + 88 çekirdek testi; 22 koşullu test atlandı, 118 test geçti. Canlı SQL, Keychain erişimi ve kurulum denenmedi. Kanıtlar Validation/release-0.2.34-build.txt, release-0.2.34-manifest.json ve release-0.2.34-tests.txt.

## 0.2.34 yayın sonucu

[GitHub Actions](https://github.com/erhanulas/MSSQLStudio/actions/runs/38003350209) başarılı; sabit imza denetimi, Release build, ZIP/PKG doğrulaması ve gerçek paketle tüm testler geçti. [v0.2.34](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.34) ZIP / PKG / update.json ile yayımlandı. Herkese açık Latest manifesti 0.2.34 sürümünü gösteriyor; ZIP indirildi, SHA-256 ve kişisel imza doğrulandı. Kurulum yapılmadı.

## 0.2.33 yayın hazırlığı

0.2.33 / build 34 kişisel imzalı Release ZIP ve PKG üretildi. prepare-release doğrulaması sertifika kimliğini, ZIP/PKG metadata ve binary eşleşmesini, sürüm notlarını ve SHA-256 manifestini doğruladı. Gerçek ZIP ile tam test çalışması başarılı: 52 uygulama + 88 çekirdek testi raporlandı; 22 koşullu test atlandı, 118 test geçti. Önceki aralıklı arayüz çökmesi bu koşuda tekrarlanmadı; kök neden için düzeltme yapılmadı. Canlı SQL, Keychain erişimi ve gerçek kurulum bu tur denenmedi. Kanıtlar Validation/release-0.2.33-build.txt, release-0.2.33-manifest.json ve release-0.2.33-tests.txt.

## 0.2.33 yayın sonucu

[GitHub Actions](https://github.com/erhanulas/MSSQLStudio/actions/runs/38002272188) ilk denemede StudioStateTests signal 11 nedeniyle yayını engelledi; aynı kaynakla ikinci deneme tüm kontrolleri geçti. [v0.2.33](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.33) ZIP, PKG ve update.json ile yayımlandı. Herkese açık Latest manifesti 0.2.33 gösteriyor; uzak ZIP indirildi, SHA-256 ve sabit kişisel imza doğrulandı. Kurulum yapılmadı. Kanıtlar: Validation/release-0.2.33-ci-failure.txt, release-0.2.33-github.json, release-0.2.33-public-check.json.

# MSSQL Studio 0.2.32 — Doğrulama raporu

Tarih: 9 Ekim 2026. Önceki NativeSQL projesi değiştirilmedi; bu uygulamanın kaynakları, arayüzü ve SQL katmanı yeniden yazıldı.

## 0.2.32 — kalıcı kişisel sertifika

10 Ekim 2026. 3072-bit RSA / SHA-256 self-signed code-signing sertifikası üretildi (3650 gün); özel anahtar login Keychain'e aktarıldı. Şifreli yedekler depo dışında 0700/0600 izinleriyle, yedek parolası Keychain'de saklandı. GitHub Actions Secrets şifreli P12 ve parolasını taşır; CI geçici keychain kullanır. Kaynakta yalnızca açık sertifika parmak izi bulunur. Build / ZIP / PKG doğrulaması hem sertifika leaf parmak izini hem kalıcı designated requirement'ı kontrol eder. Uygulama güncelleyicisi de 0.2.32'den sonra bu imzayı zorunlu tutar.

52 uygulama + 88 çekirdek, 27 suite / 140 test raporlandı; 22 koşullu atlandı, **118 farklı test geçti**. Yeni regresyon Security framework ile gereksinimin derlenmesini ve geçerli ad-hoc imzayla yeniden imzalanmış gerçek uygulama ZIP'inin reddini doğruladı. Gerçek kişisel imzalı ZIP hazırlama pozitif testi geçti. Sonraki değişiklik yalnızca release notlarındaki Keychain sınırının netleştirilmesidir; son paket ayrıca hazırlanıp doğrulandı ve uzak CI aynı son kaynak üzerinde çalıştırılır.

İki farklı binary aynı sertifika ve aynı designated requirement ile imzalandı; ad-hoc replacement reddedildi. Ayrı geçici test keychain'inde aynı konumda birinci/ikinci binary arasında UI kapalıyken test kaydı okundu; ad-hoc binary okuyamadı, test kaydı/keychain silindi. Bu test gerçek kullanıcı login keychain onayını temsil etmez.

**Login keychain bulgusu:** Sadece rastgele servis adındaki sahte kayıtlarla yapılan login keychain testi ikinci binary için -25293 yetkilendirme hatası verdi; ilk denemede sistem istemi görüldü ve test süreci durduruldu. Test kayıtları temizlendi. Kullanıcı ek izin/erişim-kuralı testini istemedi ve yalnızca imzalamayı tamamlamamızı seçti; ServerVault erişim kuralları ve gerçek bağlantı kayıtları değiştirilmedi. Bu sürümün her güncellemede Keychain istemini tamamen giderdiği doğrulanmış değildir.

Native smoke yalıtılmış bundle ID ile yapıldı; editör yazma ve Hakkında 0.2.32 / build 33 ile kişisel imza notları görüldü, test sorgusu kaydedilmeden test uygulaması kapatıldı. UI test kopyası izolasyon nedeniyle ad-hoc yeniden imzalanmıştır; gerçek yayın imzası ayrı ZIP / PKG policy kontrolleriyle doğrulanır. Kurulu kullanıcı uygulaması güncellenmedi, canlı SQL testi yapılmadı. Developer ID / notarization / PKG Installer imzası ve gerçek Installer çalıştırması yoktur. GitHub yayın sonucu ayrıca kaydedilir.

0.2.32 ilk uzak çalışmasında imzalama / paket doğrulaması ve 88 çekirdek test geçti; StudioStateTests süreci signal 11 ile kapandığı için yayın otomatik engellendi. Aynı kaynakla ikinci çalıştırma başarılı oldu; bu ilk hata başarılı test olarak sayılmadı.

### 0.2.32 yayın sonucu

[GitHub Actions](https://github.com/erhanulas/MSSQLStudio/actions/runs/38000684011) ikinci denemede başarılı; aynı kaynak üzerinde 118 farklı test ve geçici Keychain imza sürekliliği testi geçti. Geçici CI imza keychain'i kaldırıldı. [v0.2.32](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.32) ZIP / PKG / update.json ile yayımlandı; yayın açıklaması paket notlarıyla eşleşti. Gerçek ApplicationUpdate katmanı GitHub'dan 0.2.32'yi indirdi, SHA-256 / sabit sertifika / designated requirement / bundle-sürüm doğrulamasından geçirdi ve /tmp altında hazırladı. Aynı sürümde yeni güncelleme önermedi. Kurulum yapılmadı. Yerel ve uzak paketler ayrı derlemelerdir; byte/hash eşitliği iddia edilmez. Kanıt: Validation/signing.txt, github-ci.txt, github-public-check.txt, github.json, pkg.json, packages.json, build.txt, tests.txt.

## 0.2.31 — Hakkında ve ortak sürüm notları

10 Ekim 2026. Menüye MSSQL Studio Hakkında eklendi. Pencere bundle metadata'sından sürüm/build okur; ReleaseNotes.json Swift Package resource olarak imzalı uygulamaya dahil edilir. Beş sürümün notları çevrimdışı seçilebilir. GitHub yayın bağlantısı ve mevcut güncelleme kontrolü sunulur. Açık pencere tekrar kullanılır. Yayın hazırlığı notes/tag eşleşmesini, JSON varlığını ve ZIP/PKG notlarının byte eşitliğini kontrol eder; GitHub açıklamasını aynı JSON'dan üretir.

0.2.31 / build 32 Release derlemesi başarılı. Gerçek ZIP ile **52 uygulama + 87 çekirdek**, 26 suite / 139 test raporlandı; 22 koşullu test atlandı, **117 farklı test geçti**. Yeni regresyonlar: bundle notları, nümerik sürüm sırası ve metin eşleşmesi, yinelenen sürüm / bozuk tarih / geçersiz version / boş notların reddi, gerçek bundle kimliği ile not sürümünün ayrımı ve aynı About penceresinin sorgu oluşturmadan yeniden kullanılması. Gerçek ZIP hazırlama testi /tmp altında imza/sürüm denetimini geçti. SQL veya Keychain canlı testi gerekmedi ve yapılmadı.

Native smoke yalıtılmış bundle ID ile yapıldı: uygulama menüsünden Hakkında açıldı; Sürüm 0.2.31 · Derleme 32, mevcut notlar ve kurulu sürüm etiketi görüldü. 0.2.30 seçildiğinde başlık ve üç değişiklik değişti; üstteki kurulu sürüm 0.2.31 olarak kaldı. Pencerenin görünümü kontrol edildi. Güncellemeleri Kontrol Et düğmesi gerçek GitHub kaynağına ulaşıp daha eski 0.2.30 yayınından sonra yeni sürüm olmadığını gösterdi. Test uygulaması kapatıldı; kurulu kullanıcı uygulaması ve bağlantıları değiştirilmedi. ZIP ve PKG strict/deep imzası ve release notes eşleşmesi doğrulandı. Gerçek PKG kurulumu yapılmadı; Developer ID / notarization yoktur. Uzak CI ve yayın sonucu dağıtım kaydında ayrıca belirtilir.

### 0.2.31 yayın sonucu

[GitHub Actions](https://github.com/erhanulas/MSSQLStudio/actions/runs/37998408657) başarılı; aynı 117 test uzak runner üzerinde de geçti. [v0.2.31](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.31) ZIP / PKG / update.json ile yayımlandı. Yayın açıklaması, paket içindeki JSON'dan üretilen release-notes.md ile birebir eşleşti. Gerçek ApplicationUpdate katmanı sabit GitHub adresinden 0.2.30 için 0.2.31 buldu, ZIP indirme / SHA-256 / strict imza / bundle ve sürüm hazırlığını /tmp altında geçti; aynı sürüm için yeni güncelleme önermedi. Kurulum / yeniden başlatma yapılmadı. Kullanıcının kurulu sürümü 0.2.30; mevcut menüden güncelleyebilir.

Sonraki sürümlerde testlerin sabit sürüm metni gerektirmemesi için bundled history regresyonu nümerik sıra / benzersizlik / kullanılabilir notlara çevrildi; dört odaklı test yeniden geçti. Uygulama kaynakları ve yayımlanan paket bu test düzenlemesinden etkilenmez. Not/tag uyumsuzluğu içeren bozulmuş örnek ZIP'in yayın öncesi reddi de doğrulandı. Kanıt: Validation/history-focused.txt, github-ci.txt, github-public-check.txt, github.json, pkg.json, build.txt, tests.txt. Aşağıdakiler tarihsel kayıttır.

## 0.2.30 — GitHub güncelleme kaynağı

10 Ekim 2026. Varsayılan imzalı feed erhanulas/MSSQLStudio Releases adresine bağlandı. Ayarlar depo alanı HTTPS GitHub URL / owner/repo biçimlerini kabul eder; credentials, traversal, yabancı host, HTTP, query ve nesne alt yolları reddedilir. İlk yayın olmayan veya hatalı HTTP yanıtı güncel sürüm olarak gösterilmez. Etiket tabanlı CI derleme/test/taslak yayını hazırlayan workflow eklendi.

Release 0.2.30 / build 31 derlendi. Son ZIP ile **51 uygulama + 83 çekirdek**, 24 suite / 134 test raporlandı; 22 koşullu test atlandı, **112 farklı test geçti**. Gerçek ZIP /tmp altında hazırlanıp strict/deep imza ve sürüm doğrulandı; kullanıcı uygulamasına kurulmadı. Manifest üreticisi ZIP ve PKG payload imzalarını, metadata/binary eşleşmesini, version/tag ve gömülü depo adresini doğruladı; SHA-256 üretildi. Kaynakta kullanıcı parolası ve GitHub anahtarı taraması temiz.

Native smoke: yalıtılmış bundle ID ile GitHub ayar alanı açıldı, HTTPS .git adresi girilip Uygula seçildi; normalize edilmiş erhanulas/MSSQLStudio ve "Ayarlar kaydedildi" mesajı görüldü. Gerçek /Applications uygulaması ve Keychain'e dokunulmadı. Canlı SQL testleri bu sürümde çalıştırılmadı. GitHub yayın/push/CI sonucu aşağıdaki dağıtım durumunda ayrıca belirtilir; yerel doğrulama uzak CI başarısı sayılmaz. Developer ID / notarization ve gerçek PKG kurulumu doğrulanmadı.

### 0.2.30 dağıtım sonucu

Kaynaklar main dalına, 162ec652cb8eaa1bb53c957bcbc8427f308e977b commit'i v0.2.30 etiketine gönderildi. [GitHub Actions çalışması](https://github.com/erhanulas/MSSQLStudio/actions/runs/37997352668) başarıyla tamamlandı: macOS 27 runner üzerinde gerçek derleme, ZIP/PKG doğrulama ve 112 farklı test geçti; aynı 22 koşullu test atlandı. Bu tekrarlar yerel testlerle toplanarak farklı test sayısı artırılmadı. [v0.2.30 yayını](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.30), ZIP, PKG ve update.json varlıklarıyla herkese açık yayımlandı.

Ayrı /tmp Swift test aracı gerçek uygulama ApplicationUpdate katmanını kullandı: sabit latest/download/update.json adresinden 0.2.29 için yeni sürüm bulundu; yayımlanmış ZIP indirildi, SHA-256 ve strict/deep imza denetlendi, bundle/sürüm doğrulanıp /tmp hedefine hazırlandı. Aynı 0.2.30 için tekrar kontrol nil döndü. Kullanıcı uygulaması değiştirilmedi. Native ayar testinde yabancı host girildiğinde doğrulama hatası da görüldü. Mevcut /Applications sürümü 0.2.29 ve feed içermiyor; ilk 0.2.30 geçişi PKG kurulumu gerektirir. Yerel ve CI paketleri ayrı derlemelerdir; binary byte/hash eşitliği iddia edilmez. Gerçek güncelleme değiştirme/yeniden açma adımı bu sürümde çalıştırılmadı. Kanıt: Validation/github-ci.txt, github-public-check.txt, github.json, pkg.json, build.txt, tests.txt.

## 0.2.29 tarihsel doğrulama — daraltma ve gizleme

Sidebar canCollapse ve canCollapseFromWindowResize kapatıldı; isCollapsed ile mevcut düğme kontrollü gizleme devam eder. MinimumThickness 140 puntoya indirildi. Header ikon aralığı, arama seçicilerinin compression resistance / truncation davranışı, arama seçenekleri ve açıklama satırının parent genişlik constraint'leri düzeltildi. Panelin içeriği yaklaşık 251 punto fiilî minimumu artık dayatmıyor.

Yeni native layout regresyonu 1060×680 pencerede paneli 140 puntoya konumlandırdı, genişliğinin 139–145 aralığında kaldığını, otomatik collapse izninin olmadığını ve gizleme düğmesinin iki yönde çalıştığını doğruladı. Odaklı 3 PremiumLayout testi geçti. Son 0.2.29 / build 30 Release ZIP ile genel çalışmada **51 uygulama + 82 çekirdek**, 24 suite / 133 test raporlandı; 22 koşullu test atlandı, **111 farklı test geçti**. Odaklı tekrarlar ayrıca sayılmadı. SQL/Keychain davranışı değişmedi, yeni canlı test yapılmadı.

Son Release'den çıkarılmış yalıtılmış bundle ID / offline metadata ile gerçek native fare testi: divider 251 puntodan sola, minimumun da ötesine sürüklendi; erişilebilirlik değeri **139,5** olarak kaldı ve Explorer görünmeye devam etti. Kapsam/operatör/tür kontrolleri dar alana sığdı; nesne ağacı yatay kaydırması görünürdü. Gizleme düğmesiyle panel kapandı, editördeki düğmeyle açıldığında 139,5 korundu. Test uygulaması kapatılıp yeniden açıldığında yine 139,5 görüldü. Test uygulaması kapatıldı; çalışan gerçek kullanıcı uygulaması ve sorguları değiştirilmedi.

Derleme, Release/source ZIP bütünlüğü, credential taraması, PKG payload strict/deep imzası, 0.2.29/build 30 sürümü, /Applications sistem hedefi ve relocation kapalı ayarı doğrulandı. PKG gerçek Installer ile kurulmadı; Developer ID Installer imzası yoktur. Büyük nesne adlarının dar panelde kısalması beklenen davranıştır; yatay kaydırma ile okunabilir. Önceki gutter accessibility actor uyarısı sürüyor; build başarılıdır. Kanıt: Validation/build.txt, tests.txt, explorer-focused.txt, pkg.json, packages.json. Aşağıdaki testler tarihsel kayıttır.

## 0.2.28 tarihsel doğrulama — Uygulamalar konumu

Sorun doğrulandı: mevcut uygulama ~/Applications/MSSQLStudio.app altında, ana /Applications konumunda yoktu. PKG Distribution alanları enable_currentUserHome=false / enable_localSystem=true yapıldı. Payload Applications/MSSQLStudio.app, install-location / ve relocation=false korunarak sistem diski hedeflendi. Installer karşılama/bitiş metinleri düzeltildi; geçici kopyadan başlatılan uygulama için gelecekteki güncelleme varsayılanı da /Applications oldu. Yerleşik uygulama mevcut kurulu konumunda güncellenmeye devam eder.

Bu Mac'te çalışan MSSQL Studio süreci bulunmadığı ve hedef boş olduğu doğrulandı. Mevcut signed bundle atomik rename ile /Applications/MSSQLStudio.app konumuna taşındı; öncesinde/sonrasında strict/deep imza geçti. Launch Services kaydı yenilendi. Native Finder → Uygulamalar listesinde URL file:///Applications/MSSQLStudio.app/, tür Uygulama ve seçili MSSQLStudio satırı görüldü. Bağlantı, Keychain, Preferences ve Application Support dosyalarına yazılmadı. Kullanıcının uygulaması açılmadı, SQL çalıştırılmadı.

Release 0.2.28 / build 29 derlemesi ve ZIP/PKG payload imzası geçti. Son ZIP ile 50 uygulama + 82 çekirdek testi / 24 suite raporlandı; 22 koşullu atlandı, 110 test geçti. Yeni canlı SQL/Keychain testi gerekmedi ve çalıştırılmadı. PKG açılarak bundle sürümü, sistem alanı, relocation ve install-location denetlendi; installer -dominfo sistem hedefini doğruladı. Gerçek Installer çalıştırılarak root kurulumu yapılmadı; mevcut kurulum yukarıda anlatılan taşıma ile düzeltildi. PKG Developer ID Installer imzalı değildir. Önceki 0.2.27 canlı testleri tarihsel kayıttır, bu sürümün 110 sonucuna eklenmedi. Kanıtlar Validation/build.txt, tests.txt, pkg.json, packages.json içindedir.

## 0.2.27 tarihsel doğrulama

Release **0.2.27 / build 28** derlendi. Önceden var olan gutter accessibility callback actor uyarısı ve AppIntents metadata notu derlemeyi engellemedi. Genel çalışmada **50 uygulama + 82 çekirdek testi**, 24 suite raporlandı; 22 koşullu test atlandı, **110 farklı test çalıştı ve geçti**. Ayrı localhost çalışmasında iki koşullu canlı test de geçti; toplam **112 farklı test yürütüldü**. Odaklı ve canlı çalışmadaki örtüşen testler tekrar sayılmadı. Son Release ZIP güncelleme testiyle de açılıp imza/sürüm hazırlığı doğrulandı; kullanıcının kurulu uygulamasına güncelleme yapılmadı.

Eski kurtarma kayıtlarında gerçek başlangıç metni tutulmamışsa kaydedilmiş metin kıyası ihtiyatlı biçimde korunur; geçmişteki kullanıcı düzenlemelerini otomatik olarak temiz saymayız. Yeni oluşturulan/açılan sekmeler yeni baseline takibini kullanır.

Yeni regresyonlar: üretilmiş SQL'in temiz başlangıcı/gerçek düzenleme/geri dönüş; dosya kaydı ve DB baseline'ının ayrı tutulması, yürütme sırasında sonraki düzenlemelerin korunması; aynı object ID için mevcut sekmenin korunması ve bağlantı/DB ayrımı; ham sunucu tanımı ile SET/GO/ALTER editör başlangıcının ayrımı; pinned dahil Close All; Agent komutlarının dış NSMenu otomatik validation sonrasında da çalışma durumuna uyması; ayrık satır farklarının ve büyük lineer fallback'in SQL'i sırasıyla eksiksiz geri oluşturması; UUID doğrulama, Unicode/SQL literal escaping, UTF-16 ad sınırları, T-SQL olmayan adımların reddi, kısmi metadata ve geçmiş filtreleri.

Canlı localhost:1433 testleri yalnızca UUID isimli geçici nesnelerde yapıldı. msdb'de disabled job + T-SQL step oluşturuldu; Properties okundu, Enable/Disable tekrar okunarak doğrulandı, step komutu değiştirildi, History ve servis DMV sorguları okundu; transaction rollback sonrası job'ın yokluğu doğrulandı. Ayrı geçici procedure testinde SET/GO ile hazırlanmış ALTER, uygulamanın TSQL.run batch katmanından yürütüldü; ham definition'ın wrapper'dan farklı kaldığı, SELECT 2 değişikliği ve rollback sonrası nesnenin yokluğu doğrulandı. Kullanıcının mevcut tablolarına/işlerine yazılmadı. İlk canlı test çağrılarında Swift başlatıcısının OpenSSL arama ortamını düşürmesi nedeniyle bağlantı kurulamadı; Xcode toolchain'in doğrudan başlatılmasıyla düzeldi. İlk yeni DDL testinin düşük seviye execute API'sine GO göndermesi düzeltildi; son test uygulamanın batch katmanıyla geçti.

Native UI, son Release'den çıkarılmış farklı bundle ID/sentetik offline metadata ile test edildi; gerçek Keychain ve sorgular açılmadı. Divider 251 pt'den 394,5 pt'ye sürüklendi, gizle/göster son genişliği korudu. Aynı procedure'ü ikinci kez Modify açmak sekme sayısını artırmadı ve @Count=2 düzenlemesini korudu. Yan yana diff −1/+1 satır, kırmızı/yeşil ve değişen 1/2 karakter vurgusu gösterdi; ilk değişikliğe yatay kaydırdı. Çalıştırılacak SQL sekmesi ve kapatma kaynak metni korudu. Close All temiz başlangıç sekmesini uyarısız kapattı, yalnızca düzenlenmiş ALTER'da uyarı çıktı; Vazgeç metni korudu; metni başlangıca döndürünce işaret kalktı ve kalan sekmeler uyarısız kapandı.

Agent UI: disabled iş pause ikonu ve tek durum etiketiyle göründü; Stop Job pasifti. History/başarısız kaydın mesajı, General/Steps/Schedules sekmeleri, step seçimi, GUID içeren Enable önizlemesi, SQL'e aktarma ve ana pencerenin öne gelmesi, Job Activity/servis durumu, schedule Enabled toggle'ından sp_update_schedule SQL'i üretimi görüldü. Sentetik UI'da Uygula/İşi Sil çalıştırılmadı. Gerçek Agent işini başlatma/durdurma, çalışan iş, gerçek silme/shared schedule değişimi ve Agent servis yönetimi canlı doğrulanmadı. Yeni işlerin gerçek zamanlama tetiklemesi bu sürüm testine dahil değildir.

PKG uygulama payload'ının strict/deep ad-hoc imzası, sürüm/build, kullanıcı alanı kurulumu ve relocation kapalı ayarı doğrulandı. Release/source ZIP bütünlük ve credential taraması geçti. Developer ID Installer imzası ve gerçek Installer kurulum testi yoktur. Önizleme check→execute atomik değildir, üç yönlü merge yoktur; büyük DDL kısmi preview'da Apply engellenir. Agent'ın Alerts/Operators/Proxies ve ayrıntılı calendar yönetimi uygulanmadı. Kanıtlar: Validation/build.txt, tests.txt, management-focused.txt, management-live.txt, final-update.txt, pkg.json, packages.json. Aşağıdaki sonuçlar tarihsel sürüm kayıtlarıdır.

## 0.2.26 tarihsel doğrulama

Release derlemesi başarılı. Son kaynak ve gerçek 0.2.26 Release ZIP ile genel çalışmada **44 uygulama + 75 çekirdek testi**, 22 suite raporlandı. 20 koşullu test atlandı; **99 farklı test çalıştı ve geçti**. Canlı SQL/Keychain testi bu tur çalıştırılmadı. Güncelleme doğrulama testi son ZIP'i açtı ve sürüm/imza hazırlığını doğruladı; kurulu uygulamayı güncellemedi. Odaklı editör/çalışma alanı çalışması 29 test / 2 suite raporladı (1 koşullu atlandı); genel testlerle örtüştüğü için toplama ayrıca eklenmedi.

Dört yeni regresyon testi: native fare takibinin son seçimini @STOK_KODU / @@ROWCOUNT / #Temp / @şehir için tamamlama ve çok kelimeli seçimi koruma; gerçek native Bul barı için Ctrl+F, seçimi search field'a aktarma, tekrar seçimle aramayı yenileme, SQL ve undo koruması; ayrı UserDefaults alanında gecikme varsayılanı/kalıcılığı ve 50–1.000 ms sınırları; Workbench'te iki yeni sorgunun doğru editöre odaklanması ve sıradan workspace yenilenmesinin arama alanından odağı almaması. Kısayol çakışma testi Ctrl+F'nin Yeni sorgu için reddedildiğini de doğruladı.

Yalıtılmış Release arayüzünde gerçek fareyle STOK_KODU gövdesine çift tıklandı; erişilebilirlik seçimi **@STOK_KODU** oldu. Ctrl+F barında aynı metin ve iki eşleşme görüldü. ⌘N sonrasında editöre ayrıca tıklamadan yazılan SELECT 26 AS NewTabFocus yeni dokümana girdi. Ayarlardaki gecikme 720 ms yapılıp Uygula ile kaydedildi; pencere kapatılıp yeniden açılınca 720 ms görüldü. Varsayılan düğmesi 260 ms'ye döndürdü. Son paket yeniden açıldığında ⌘F ile @STOK_KODU bar değerine taşındı, ⌘N sonrası SELECT 27 AS FocusCheck doğrudan yeni editöre yazıldı ve gecikme 260 ms olarak korundu. Test uygulaması farklı bundle ID ve sentetik/offline metadata kullandı; kullanıcının gerçek uygulaması, sorguları ve Keychain'i değiştirilmedi. Test SQL'i çalıştırılmadı.

PKG içindeki **0.2.26 / build 27** uygulamasının strict/deep ad-hoc imzası, kullanıcı alanı hedefi ve relocation kapalı ayarı doğrulandı. Release/source ZIP bütünlük ve parola taraması geçti. PKG Developer ID imzalı değildir; gerçek Installer kurulumu bu tur yapılmadı. Kanıt: Validation/build.txt, tests.txt, editor-focused.txt, pkg.json, packages.json. Gecikme ayarı doğrulama/katlama ile ortak iptal edilebilir analiz döngüsünü etkiler; seçili metin eşleşmeleri bağımsız 90 ms akışını korur. Gecikme için gerçek sistemler arası zaman/FPS benchmark'ı yapılmadı. Aşağıdaki eski sürüm sonuçları tarihsel kayıttır.

## 0.2.25 güncel doğrulama

Release derlemesi başarılı. Son kaynak ve gerçek 0.2.25 Release ZIP ile genel test çalışması 40 uygulama + 75 çekirdek testi / 22 suite raporladı. 20 koşullu test atlandı; **95 farklı test çalıştı ve geçti**. Bu tur canlı SQL / Keychain testi çalıştırılmadı; önceki 0.2.24 canlı yönetim kanıtı tarihsel olarak korunur. Güncelleme ZIP hazırlama/doğrulama testi gerçek son paketi açtı, kurulu uygulamaya uygulamadı.

Dört yeni app regresyon testi: tek kelime seçiminin diğer statement'lara taşmaması (Türkçe/alt çizgi/@/emoji dahil); async sözdizimi analizi sonrasında sarı eşleşme attributes'unun, seçimin, SQL'in ve undo geçmişinin korunması/temizlenmesi; IF/ELSE başlığı, gölgeli placeholder/tooltip, değişmeyen host sync'inde katlama durumunun korunması ve ellipsis açılınca bütün bloğun seçilmemesi; iç içe katlama ve viewport konumu. Eski folding kaynak eşleme, görünümden sonra düzenleme, undo/redo, gutter satır seçimi, tamamlama, tanıma geçiş ve TextKit 2 testleri de geçti. Odaklı editör çalışmasında 17 test geçti; genel çalışmadaki tekrarları toplam sayıya ayrıca eklenmedi.

Yalıtılmış Release UI testi yalnızca sentetik offline metadata ile yapıldı. Örnek IF/BEGIN/END/ELSE metninde dört Customer_Name kullanımı vardı. Gerçek fare çift tıklaması yalnızca Customer_Name kelimesini seçti, yeni nesne sekmesi açmadı; diğer üç kullanım sarı göründü. IF katlandığında IF 1 = 1 …, + kutusu, özgün satır numaraları ve ayrı açık ELSE dalı görüldü. Ellipsis üzerine gerçek çift tıklama özgün kodu geri açtı, büyük metin seçimi oluşmadı. Son mouse-up koruması eklenen Release paketi ayrıca yeniden açıldı; üç kullanımlı kısa metinde gerçek çift tıklama yalnız Customer_Name seçti ve diğer iki kullanım sarı kaldı.

Table Designer'da açılır kolon seçicisi olmadığı, bit alanına tıklayınca Active satırının seçildiği ve satırın mavi/ok ile işaretlendiği görüldü. Name satır seçicisiyle Name seçildi, kaldırma taslağı 4→3 kolona indirdi. 18 yeni kolon eklendi; benzersiz NewColumn…NewColumn18 adları, otomatik aşağı kaydırma ve sabit toolbar gözlendi; seçili son kolon kaldırılınca 21→20 kolon oldu. Son küçük odak düzeltmesinden sonra Release paketi yeniden açıldı: Active tip alanından Name satır seçicisine tıklanınca hem seçili etiket hem metin odağı Name oldu. UI testinde SQL çalıştırılmadı, gerçek kayıtlı bağlantılar, Keychain ve kullanıcının açık sorguları değiştirilmedi.

Sınırlar: Katlama BEGIN tabanlıdır; tüm SSMS batch/statement parser davranışı yoktur. Düzenleme/undo önce katlanmış alanları açar. Eşleşme vurgusu semantik usages analizi değildir; 250.000 UTF-16 / 256 karakter seçim / 500 eşleşme sınırları korunur. Büyük dosyada gerçek FPS ölçümü ve dar pencere yatay sürükleme bu tur yapılmadı. Önceki sürümlerin SQL/AI/Kerberos sonuçları bu sürüm için yeniden çalıştırılmış sayılmaz.

PKG içindeki 0.2.25/build 26 uygulamasının strict/deep ad-hoc imzası, kullanıcı alanı hedefi ve relocation kapalı ayarı doğrulandı. Release/source ZIP bütünlük ve parola taraması geçti. PKG Developer ID imzalı değildir; gerçek Installer kurulumu bu tur denenmedi. Kanıtlar: Validation/build.txt, tests.txt, editor-focused.txt, pkg.json, packages.json. Aşağıdaki eski sürüm bölümleri tarihsel kayıttır.

## 0.2.24 güncel doğrulama

Release derlemesi başarılı. Genel çalışma 36 uygulama + 75 çekirdek testi / 22 suite raporladı; 20 koşullu test atlandı, 91 test çalıştı. ObjectManagementTests ve ExplorerManagementTests birlikte localhost üzerinde 11 test / 2 suite geçti; bunun 3'ü canlı SQL testidir. Birim test tekrarları çıkarılınca toplam **94 farklı test çalıştırıldı**. Gerçek 0.2.24 ZIP güncelleme doğrulama/hazırlama testi geçti; kurulu uygulamaya uygulanmadı.

Yeni testler procedure typed input/OUTPUT/DEFAULT/return value, scalar ve table-valued function argüman sırası, Unicode/quote kaçışları, TVP/özel tür/enjeksiyon reddi, binary literal doğrulaması, DML/database DDL trigger hedefleri, enabled/disabled durumu, modül başlığının katalog adıyla düzeltilmesi ve synonym hedeflerini kapsar. App testi ayrı procedure/function/trigger SF Symbols, parent/owner bağlantıları ve offline trigger durum fixture'ını doğrular.

Üç canlı test yalnızca localhost:1433 / master üzerinde benzersiz adlar, #temp ve transaction rollback kullandı. Önceki standart rowstore CREATE roundtrip ve optimistic data edit testleri tekrar geçti. Yeni test procedure parametreleri/OUTPUT/default, scalar+TVF çağrıları, procedure ALTER, DML ve database-scoped DDL trigger enable/disable/drop, ALTER sonrası disabled durumunu koruma, synonym create/read/drop ve trigger çocuklarının schema/durum metadatasını doğruladı. Rollback sonrasında test tablosunun yokluğu ayrıca kontrol edildi; mevcut kullanıcı verisine yazılmadı.

Yalıtılmış offline Release arayüzünde procedure sağ tık script hedefleri, parametre formu ve İstanbul girdisinden named EXEC/OUTPUT SQL üretimi görüldü. Function Modify ile ANSI_NULLS/QUOTED_IDENTIFIER + ALTER ve fark/DB'ye uygulama araçları açıldı. Aktif ve disabled trigger farklı ikon/etiketlerle görüldü; disabled trigger menüsündeki Enable doğru parent tablo hedefli scripti yeni query'de açtı. Trigger Properties ekranı açıldı; sentetik durum verisindeki tutarsızlık fixture'da düzeltildi ve app regression testi eklendi. Son Release paketinden yeniden açılan DDL trigger Properties ekranında DDLGuard / Disabled / DATABASE bilgileri ayrıca görüldü. Table Designer'da 20 yeni kolon eklenerek 24 kolonla en alta kaydırıldı; sabit ekleme/seçim/kaldırma kontrolleri görünür kaldı ve kaldırma 23 kolona indirdi. Dar pencerede yatay sürükleme elle ölçülmedi; araçlar iki eksenli scroll alanının dışındadır. UI testinde SQL çalıştırılmadı, Keychain ve kayıtlı kullanıcı sunucularına erişilmedi.

Sınırlar: Server-scoped DDL trigger, TVP/özel tür/CLR invocation, okunamayan encrypted modül tanımı, bütün security nesneleri için tasarım ekranları ve tam SSMS/SMO eşdeğerliği yoktur. Trigger/index/constraint disk arama indeksi eklenmedi. Özel tabloların structure scriptleri standart rowstore sınırına tabidir. Her yeni menü/izin/type birleşimi native UI'da ayrı ayrı denenmedi; canlı testler SQL üretim/metadata katmanını kapsar. Elle transaction içinde çalıştırılan değişiklikler için COMMIT sonrası Explorer Yenile gerekir. Kerberos, AI, uzak sunucu ve gerçek grid FPS bu tur tekrar sınanmadı.

PKG içindeki 0.2.24/build 25 uygulaması strict/deep ad-hoc imza, kullanıcı alanına kurulum ve relocation kapalı seçenekleriyle doğrulandı. ZIP/source ZIP bütünlük ve parola taraması geçti. PKG Developer ID ile imzalı değildir; gerçek Installer kurulumu denenmedi. Kullanıcının kurulu uygulaması, kayıtlı bağlantıları ve açık sorguları değiştirilmedi. Kanıtlar: Validation/build.txt, tests.txt, object-management-live.txt, pkg.json, packages.json. Aşağıdaki eski sürüm kayıtları tarihsel kanıttır.

## 0.2.23 güncel doğrulama

Release derlemesi başarılı. Genel test çalışması 35 uygulama + 69 çekirdek testi (20 suite) raporladı; 19 koşullu test atlandı, 85 test çalıştırıldı. Ayrıca `ObjectManagementTests` canlı localhost çalışmasında 3 birim + 2 canlı test geçti. Tekrarlanan birim testleri saymadan bu tur toplam 87 farklı test çalıştırıldı. Gerçek 0.2.23 güncelleme ZIP hazırlama/doğrulama testi geçti; kurulu uygulamaya uygulanmadı.

Yeni birim testleri kolon ALTER/ADD/rename/default/PK scripti, identifier/literal escaping, veri tipi enjeksiyonunun reddi, generated kolon koruması, view CREATE/ALTER/CREATE OR ALTER dönüşümü, FK şablonu, PK zorunluluğu, NULL ve orijinal değerli UPDATE/DELETE koşulları, anahtar düzenleme reddi ve yalnızca dokunulan kolonları içeren INSERT'i kapsar.

Canlı SQL Server testleri yalnızca localhost:1433 üzerinde master veritabanında benzersiz test nesneleri ve connection-local #temp kullandı. Standart rowstore CREATE scripti tekrar oluşturularak identity, named default, collation, computed/PERSISTED, rowversion, PK, FK, check, filtered DESC/INCLUDE indeks ve trigger doğrulandı. Aynı transaction içinde view CREATE, ALTER, DROP, CREATE OR ALTER ve sp_rename çalıştı. Oluşturulan nesneler rollback ile kaldırıldı; tablo nesnesinin yokluğu ayrıca kontrol edildi. Veri editörünün UPDATE/DELETE/INSERT ve ALTER ADD planları rollback ile sınandı; eski rowversion ile eşzamanlı değişiklik tespit edildi ve kullanıcı verisi üzerine yazılmadı. Hata mesajı ODBC'nin THROW sonrası exception veya partial diagnostic yolunda yakalandı.

Yalıtılmış Release arayüzünde sentetik offline metadata kullanıldı: table/view sağ tık menüleri ve alt script hedefleri görüldü; tablo kolon tipi değişimi için doğru ALTER önizlemesi üretildi; keys/indexes/relationships formu açıldı. Edit Top 200 Rows ekranında hücre düzenlendi ve orijinal PK + rowversion kontrollü UPDATE yeni sorgu sekmesine aktarıldı. View tanımı ANSI_NULLS/QUOTED_IDENTIFIER ayarlarıyla ALTER olarak yüklendi, metin düzenlendi, fark önizlemesi gösterildi ve yeni sorgu öne geldi. Properties General/Permissions sekmeleri açıldı. Delete ekranında bağımlılık listesi ve tam ad yazılmadan pasif kalan script düğmesi doğrulandı; tam ad girilince DROP VIEW yalnızca editöre aktarıldı. UI üzerinden veri/DDL yazma yapılmadı. Keychain veya kayıtlı kullanıcı sunucularına erişilmedi.

Görsel testte bulunan asenkron view tanımının boş görünmesi, SQL aktarımında çalışma penceresinin arkada kalması ve Delete bağımlılık listesinin yerleşim sırasında uygulamayı kapatması düzeltildi; ilgili akışlar tekrar sınandı. Delete listesi SwiftUI List yerine ScrollView/LazyVStack kullanır.

Bu sürüm bütün SSMS tasarım araçlarına eşdeğer değildir: grafik JOIN/ilişki kanvası, view veri düzenleme, anahtarsız tablo veri düzenleme, otomatik tablo rebuild ve tam SMO schema export yoktur. CREATE standart rowstore kapsamındadır; özel tablo türleri açıkça reddedilir, permissions/extended properties/istatistikler taşınmaz. Rename sonrasında Explorer yenilenmelidir. Yeni yönetim formlarının her olası sunucu/type/izin bileşimi canlı olarak sınanmadı; AI/Kerberos/uzak sunucu/FPS testleri bu tur tekrarlanmadı.

PKG içindeki 0.2.23/build 24 uygulaması strict/deep ad-hoc imza, kullanıcı alanına kurulum ve relocation kapalı seçenekleriyle doğrulandı. ZIP/source ZIP bütünlük ve parola taraması geçti. PKG Developer ID ile imzalı değildir; gerçek Installer kurulumu bu tur denenmedi. Kullanıcının kurulu uygulaması, kayıtlı bağlantıları ve açık sorguları değiştirilmedi. Kanıtlar: `Validation/build.txt`, `tests.txt`, `object-management-live.txt`, `pkg.json`, `packages.json`. Aşağıdaki eski sürüm kayıtları tarihsel kanıttır.

## 0.2.22 güncel doğrulama

Release derlemesi ve testler başarılı. Test araçları 35 uygulama + 64 çekirdek testi (19 suite) raporladı; 17 koşullu test atlandı, 82 test çalıştırıldı. Gerçek 0.2.22 güncelleme ZIP hazırlama testi çalıştı; kurulu uygulamaya uygulanmadı.

Yeni testler seçili metin eşleşmelerini/temizlenmesini, qualified nesne ve token sonundaki caret için tanıma geçiş callback'ini, Writing Tools kapalı olmasını, tümünü seçmeyi ve tamamlanmış köşeli parantezli eksik nesnenin kırmızı doğrulamasını kapsar. Grid testinde predominant-axis ayarı doğrulandı. Yalıtılmış Release arayüzünde üç Customers eşleşmesi sarı gösterildi, DefinitelyMissing kırmızı/altı çizili görüldü, Ctrl+A bütün metni seçti; Writing Tools popup/gri örtü oluşmadı. DDL indeks durum alanının bağlantısız hali görüldü. Son küçük navigasyon/scope/refresh düzeltmeleri derleme ve testle doğrulandı.

Bu tur canlı SQL/TEST2026 erişimi, tablo CREATE preview SQL'inin canlı sunucuda çalıştırılması, gerçek metadata indeks tarihinin UI üzerinden kontrolü, fiziksel trackpad çapraz gesture testi ve gerçek FPS ölçümü yapılmadı. Tablo preview tam DDL değildir; constraint/index/trigger/tablo seçenekleri içermez. Tanıma geçiş unit testinde callback doğrulandı, canlı yeni ALTER sekmesi bu tur uçtan uca denenmedi. Önceki performans ölçümleri aşağıda sürüm numarasıyla korunmuştur.

PKG payload sürümü/imzası doğrulandı; gerçek Installer kurulumu denenmedi. Uygulama ad-hoc imzalıdır, PKG Developer ID ile imzalı değildir. Kullanıcının kurulu uygulaması ve açık sorguları değiştirilmedi.

## 0.2.21 güncel doğrulama

Release derlemesi başarılı. Test araçları 33 uygulama + 64 çekirdek testi, 19 suite raporladı; 17 koşullu test atlandı (80 test çalıştırıldı). Gerçek 0.2.21 güncelleme ZIP doğrulama/hazırlama testi çalıştı; kurulu uygulama değiştirilmedi. Bu tur canlı veritabanı testi yoktur; aşağıdaki eski sürüm bölümleri tarihsel kayıttır.

Alias testleri büyük harf, alias çakışması (C/C2), NOLOCK açık/kapalı ve INSERT kapsamını doğruladı. Grid testleri bit gösterimi, ham değer/başlık kopyalama, sayfalama ve view tabanlı delegate kullanılmadığını doğruladı. Yalıtılmış Release uygulamasında 2.000 satır / 64 kolon sentetik disk sonucu açıldı; bit kutuları, NULL, yalnızca seçili hücre vurgusu, dikey kaydırma ve NOLOCK ayarının kaydedilmesi görüldü. Önceki debug kontrolünde hücre kopyalama/editöre yapıştırma doğrulandı. Kullanıcının kurulu uygulaması ve sorguları değiştirilmedi.

Geniş grid ölçümü: 10.000 satır / 64 kolon, 80 dikey-yatay hareket. Eski çizici: toplam 13,173 sn, p95 189,8 ms. Yeni çizici: toplam 0,563 sn, p95 9,56 ms. Yeni test her harekette ayrıca `display()` çağırarak çizimi zorlar; eski testte bu ek çağrı yoktur. Bu nedenle birebir FPS karşılaştırması değildir; CPU/layout/draw maliyetini ölçer. Native bir milyon disk satırı ve yatay kaydırma testleri de geçti. Gerçek TEST2026/TBLSTSABIT sonucu bu tur çalıştırılmadı; gerçek cihaz frame pacing ölçülmedi.

Kanıtlar: Validation/build.txt, tests.txt, grid-wide-before.txt, grid-wide-after.txt, pkg.json. PKG payload imzası ve sürümü doğrulanır; gerçek Installer kurulumu bu tur denenmedi. Uygulama ad-hoc imzalı, PKG Developer ID ile imzalı değildir.

## Önceki sürümlerden ortam ve test kayıtları

## Ortam

| Bileşen | Yerelde gözlenen değer |
|---|---|
| Mac | Apple Silicon / arm64 |
| macOS | 27.2, 26B5101f |
| Xcode / Swift | 27.0, 27A266a / 6.4 |
| unixODBC | 2.3.14 |
| Microsoft ODBC Driver | 18.7.1.1, kayıtlı “ODBC Driver 18 for SQL Server” |
| SQL Server | localhost:1433, SQL Server 2022 Developer 16.0.4265.3, Linux x64 |
| SQL Authentication | Yerel test hesabı; parola kaynaklara veya rapora yazılmadı |

Sürücü OpenSSL 3 ile çalıştı. Homebrew varsayılan OpenSSL 4 kitaplığı bu sürücünün SSL yüklemesinde başarısız oldu; global symlink değiştirilmedi. Xcode scheme ve uygulamanın LSEnvironment alanı `/opt/homebrew/opt/openssl@3/lib` yolunu yalnızca uygulama sürecine sağlar. `localhost`, SQL Authentication için IPv4 loopback adresine çevrilerek bu Mac'te GUI sürecinde görülen DNS timeout giderildi; Kerberos'ta SPN hostname korunur.

## Otomatik testler

Teslim edilen `scripts/verify.py` ile temiz `/tmp` build dizininde **58 test / 14 suite geçti**. Swift test runner iki hedefi ayrı raporlar: core **39 / 5 suite**, uygulama **19 / 9 suite**; ikisi de başarılı. Toplam **12 test** canlı localhost SQL Server kullanır. Yeni testler hücre/Shift aralık/# satır seçimi, Türkçe/NULL TSV kopyalama, kolon sırası, metadata ipuçları, pin ve sağ/sol/diğer sekmeleri kapatma, muhafazakâr tekrar uygunluğu, gerçek SELECT seçim snapshot’ı ile yenileme, Messages/filtre/genişlik korunması ve hata sonrası durmayı kapsar. Canlı testler yalnızca özel test ortam değişkeni verildiğinde çalışır.

| Test alanı | Doğrulanan davranış |
|---|---|
| Connection / SQL quoting | Brace, identifier, literal escaping; port doğrulama; Kerberos string'inde parola olmaması |
| Veritabanı seçimi | Profil JSON roundtrip, eski profil uyumluluğu, boş/geçersiz seçim reddi, yalnızca seçili ve halen erişilebilir adların gösterilmesi |
| Bağlantı keşfi | Canlı bağlantı testi, ayrı bağlantıda katalog listeleme, olmayan login hatası/parolanın gizlenmesi, sonraki başarılı test |
| Ortam / renk | Önayarlar, özel RGB doğrulama/normalizasyon, etikette satır kırılımı, JSON roundtrip, eski profil uyumluluğu, Keychain'de görünüm kaydı |
| Bağlantı düzenleme | Ad/renk değişiminde SPID ve #temp korunması; hatalı login sonrası mevcut bağlantının kullanılması; çalışan sorgu/açık transaction varken değişiklik reddi; başarılı endpoint değişiminde yeni oturum, metin korunması ve otomatik SQL çalışmaması |
| Lexer / GO | UTF-16, Türkçe/emoji, kaçışlı string ve identifier, iç içe comment; GO tekrar sınırı ve batch başlangıç satırı |
| Formatter / completion | Literal ve qualified identifier korunması; alias, tablo değişkeni, basit CTE/derived table sütunları |
| Export | NULL / boş string ve aynı adlı sütunlar; JSON array düzeni; CSV formül işaretleme |
| Script tools | İndeks anahtar/include tekrarlarının engellenmesi; Agent job adı/komutu kaçışları ve saat sınırı |
| Plan parse | Operatör parent/depth, thread ActualRows toplamı ve uyarılar |
| Template | JSON şekli, örnek içe aktarma ve geçersiz dosyanın reddi |
| AI transport | Yerel sahte HTTP sağlayıcıya request/response; SQL block extraction; redirect'in reddi |
| Keychain | Rastgele test servisine ekleme, güncelleme, okuma, silme; yalnızca uydurma test parolası; veritabanı seçimlerinin kaydı ve güncellenmesi |
| SQL veri türleri | bigint maksimumu, decimal(38,18) exact değer; NULL/empty, 3.000 Türkçe+emoji tekrar, 6 KB binary hex |
| Çoklu batch / mesaj | GO 2, çoklu SELECT ve Türkçe PRINT |
| İptal | 15 saniyelik WAITFOR iptali, aynı bağlantıda sonraki SELECT başarısı |
| Oturum / transaction | Farklı SPID, bir oturumdaki #temp ve transaction'ın diğerine taşınmaması, rollback |
| Kısmi sonuç | 10 satır limiti; sonraki GO'nun durması; hata sonrası önceki sonucun korunması |
| Hücre limiti | 270. satırdaki aşırı hücrede önceki 269 satırın korunması ve oturumun yeniden kullanılabilmesi |
| Catalog / DMV | Veritabanları, nesneler, güvenlik, jobs/schedules; activity/sessions/locks/files/history sorguları |
| DDL rollback | İzole tablo, indeks, procedure/parameters ve Agent job+schedule oluşturma; transaction rollback |
| Sunucu planı | SHOWPLAN_XML tahmini plan, STATISTICS XML gerçek plan ve ActualRows |

Canlı testler mevcut kullanıcı tablolarına yazmadı. Test nesneleri benzersiz isimli ve transaction içindeydi; Agent job çalıştırılmadı, rollback ile kaldırıldı. Oturum testinde kullanılan #temp yalnızca kendi bağlantısındaydı. Keychain testi gerçek bağlantı parolasını kaydetmedi.

## 0.2.11 araç çubuğu, bit ve pano doğrulaması

- Tek gridToolbar içinde gezinme, yenileme, saatli otomatik yenileme, sorgu satır limiti, arama, başlıklarla kopyalama ve ikonlu dışa aktarma yer aldı. ResultController’ın ayrı çubuğu hosted modunda sıfır alan kullanır. Kolon filtresi seçicisinin olmadığı ve gerçek sonuç sekmesi değişince doğru grid’in araçlarının taşındığı native testte doğrulandı.
- 830 pt genişliğindeki sorgu alanında (1060 pt çalışma alanı eksi sidebar) tüm görünür araç kontrollerinin sınırlar içinde kaldığı test edildi. Mevcut 1060×680 / 1920×1080 yerleşim testleri geçti. Messages’a geçince yalnızca grid’e ait araçlar pasifleşti.
- bit 1/0 checkbox, NULL metin gösterimi native testle doğrulandı. Checkbox disabled, target/action yok ve hitTest grid’e geçer; veri düzenlemez. Checkbox’dan kaynak metne pano dönüşümü `Enabled / 1 / 0 / NULL` olarak doğrulandı.
- Hücre seçimi için yalnızca seçili kolon başlığı; # satır seçimi için tüm görünür kolon başlıkları; Türkçe değerler ve yeniden sıralanan kolonlar test edildi. Normal kopyalama başlıksız kaldı. İlk testte NSObject.copy ile isim çakışması yakalandı; yöntem copySelectionData olarak yeniden adlandırıldı ve son testler geçti.
- Kaydırma bounds-change gözlemcisi kaldırıldı. Native testte 10.000 satırlık grid 9000. satıra kaydırıldı; sayaç metni aynı kaldı. Son aralık oku ile 9501–10000 aralığı güncellendi. Sayaç son gezinme aralığıdır; görünür ilk satırı sürekli takip etmez.
- GridShortcuts ayar tercihiyle ⌥⌘C keyDown olayı başlıklı TSV üretti; test önceki kullanıcı tercihini geri yükledi. Varsayılan ⇧⌘C menü ve tooltip ile aynı kaynaktan gelir. Tam serbest tuş kaydı bu sürümün kapsamı değildir.
- ZIP’ten çıkarılmış uygulama önce arayüz aracında timeout verdi, sonraki okumada bağlantı formu erişilebilir oldu. Önceki sürümün Local SQL Server profili, maskelenmiş parola, TLS seçimi ve veritabanı seçimleri dolu geldi. Yeniden parola girilmeden test → bağlan tamamlandı. Kullanıcının kayıtlı veritabanı seçimleri değiştirilmedi.
- Canlı GUI’de yalnızca VALUES kullanan üç satırlık SELECT çalıştırıldı: bit 1, bit 0, NULL. Checkbox durumları ve NULL görüldü. Tek çubuk, kolon filtresi seçicisinin kaldırılması, saat ve kopyalama tooltip’leri, dört seçenekli CSV/JSON dışa aktarma menüsü gözlendi. Kullanıcı tablolarına yazılmadı. Son küçük erişilebilirlik düzeltmesi checkbox’ları disabled olarak belirledi; bu son satır native otomatik testte doğrulandı.
- Son Release ZIP’in bütünlüğü ve çıkarılmış .app’in strict/deep imzası doğrulandı. Parola kaynak/rapor/paket taramasında bulunmadı. macOS yeni sürümün Keychain erişimi için sistem onayı isteyebilir; bu bağlantı ayarlarının silinmesi değildir.

### 0.2.11 büyük sonuç ölçümü

Release benchmark: 2.000.000 satır / iki kısa kolon disk kaydı **2,757 sn**; 1.000.000 eşleşmeye filtre + sayısal ters sıralama **3,795 sn**. Test süreci maksimum RSS **204.128.256 bayt (~194,7 MiB)**. Native 1.000.000 satırda sona kaydırma/yerleşim **0,00992 sn**, **18** satır görünümü. Bu ölçümler kısa sentetik değerler içindir; checkbox’lı milyon satırlık canlı sonuç, LOB ve her sorgu biçimi için aynı hız iddiası yoktur.

## 0.2.9 grid ve bağlantı doğrulaması

- Release derlemesi başarılı; native tabloda hücre/aralık seçimi ve yeniden sıralanan kolonlarda kopyalama otomatik AppKit olaylarıyla doğrulandı. # sütunu bütün satırı seçer; boş seçim tüm sonucu panoya dökmez. Pano sınırları korunur.
- Native sonuç sekmeleri otomatik yerleşim testinde seçildi; dar (1060×680) ve geniş (1920×1080) çalışma alanında taşma kontrolü geçti. Bezel hizalama payının 2 pt taşması testte yakalanıp düzeltildi.
- Sağ tık sekme menüsünün gerçek eylemleri testte çalıştırıldı: pin, sağ/sol/diğer toplu kapatma ve tek sekmeyi kapatma. Pin’li sekmeler toplu işlemde kaldı. Mevcut kaydet/transaction/iptal kapatma yolu korunur; bu sürümde her modal kapatma kombinasyonu GUI üzerinden yeniden denenmedi.
- Gerçek SQL Server testinde seçili `SELECT 17 AS n;` çalıştırıldı. Editör daha sonra veri değiştiren metinle değiştirildi, fakat yenileme yalnızca önceki SELECT snapshot’ını çalıştırdı. Kullanıcı tablosuna yazılmadı. Messages sekmesi, kolon genişliği ve aktif kolon filtresi korundu. Olmayan tabloya SELECT hatasından sonra yenileme uygunluğu kapandı.
- Canlı ODBC metadata testi `decimal(18,2)`, `datetime2(3)` ve `nvarchar(50)` türlerini doğruladı. Tür adı SQLColAttributeW’den, boyut/scale SQLDescribeColW’den gelir; sürücünün açıklayamadığı türler ODBC koduyla belirtilir.
- GUI’de localhost bağlantısı → yalnızca master → SELECT sonucu, gerçek Results/Messages sekmeleri ve 5 saniyelik otomatik yenileme gözlendi. Sunucu saati yenilendi; test sonunda otomatik yenileme kapatıldı. Sonraki düzeltmelerde Messages/filtre korunması canlı otomatik testle doğrulandı.
- Kullanıcının kalıcılık isteği üzerine gerçek yerel profil/parola bu kez **Keychain’e kaydedildi**. Bağlantı formu tekrar açıldığında Local SQL Server seçili, localhost/port/login ve maskelenmiş parola dolu, önceki TLS seçimi korunmuştu. Parola kaynaklara/rapora/paketlere yazılmadı. Bundle ID ve Keychain servis adı sürümlerden bağımsız kaldı; yeni imzalı ikili için macOS erişim onayı isteyebilir. Eski sürümlerde kaydedilmemiş bağlantıları otomatik kurtarma iddiası yoktur.
- Son Release ZIP’inin bütünlüğü ve çıkarılmış .app’in strict/deep kod imzası doğrulandı. Yeni ikili açılışında macOS SecurityAgent / Keychain erişim onayı bekledi; bilgisayar kullanım aracı bu sistem uygulamasını güvenlik nedeniyle açmayı reddetti. Bu nedenle yeni ikiliyle son GUI bağlantısı kullanıcı sistem onayını bekler. Önceki GUI kontrolü ve son kaynakların 49 otomatik testi başarılıdır.
- İlk/önceki/sonraki/son gezinme yüklenen/filtrelenen sonuçlarda 500 satır adımıdır; SQL Server sayfalaması ve grid üzerinden veri düzenleme bu sürümün kapsamında değildir.

### Bu sürümün büyük sonuç ölçümü

Release benchmark: 2.000.000 satır / iki kısa kolon disk kaydı **3,468 sn**; eşitlik filtresiyle 1.000.000 satır + sayısal ters sıralama **4,743 sn**. Test süreci maksimum RSS **210.780.160 bayt (~201 MiB)**. Native 1.000.000 satırlık grid’de sona kaydırma/yerleşim **0,01348 sn**, **18** satır görünümü çizildi. Tüm hücreler için görünüm veya seçim nesnesi oluşturulmaz. Bunlar sentetik kısa satır ölçümleridir; çok geniş kolon, uzun LOB, her filtre türü ve 5 milyon canlı satır için aynı hız garantisi değildir. Önceki ölçümler aşağıda sürüm tarihçesi olarak kalır.

## 0.2.8 premium görünüm doğrulaması

- Release build başarılı, ZIP içinden çıkarılan uygulamanın ad-hoc imzası strict/deep doğrulandı. Notarization veya başka Mac'e sürücü dahil bağımsız kurulum iddiası yoktur.
- Yeni native testler: tema değişimi sorgu metni/TextKit 2, semibold başlık fontu, seçili grid satırı, kolon genişliği ve gizli kolonu korur. 1060 × 680 ve 1920 × 1080 çalışma alanında database/result/toggle kontrolleri pencere sınırları içinde, grid yüksekliği kullanılabilir kaldı.
- Geliştirme sırasında yakalanan tema değişiminde seçim kaybı giderildi. Sorgu ilerleme bildiriminde tüm UI ağacına tema uygulama ve gereksiz table reload kaldırıldı.
- Açık/koyu ana çalışma alanı, gerçek 100 satır/6 kolonluk üretilmiş salt okuma sonucu (Türkçe metin, int, decimal, date, NULL), sakin satır seçimi, tür/filtre ikonları ve SQL renkleri görsel olarak kontrol edildi. Yerel sunucunun GENERATE_SERIES desteklemeyen master uyumluluğunda gerçek hata gösterildi; fixture recursive CTE ile çalıştırıldı.
- Bağlantı formu test/listeleme/master seçimi, iki ayrı yüzey ve yeni düğmelerle açıldı. Gerçek parola Keychain'e kaydedilmedi. Ayarlar, Timeline, SQL Assistant ve plan başlıkları görsel kontrol edildi; teknik font iç adı kullanıcı metninden kaldırıldı, açıklama satırları kesilmeden sarıldı. Son paket açılarak yerel bağlantı ve tahmini plan (operatörsüz örnek) yeniden doğrulandı.
- Şablon, Index/Agent tasarım ekranları ortak panel ve başlık bileşenlerini kullanır; bu turda tüm yönetim akışlarının GUI uçtan uca tekrarı yapılmadı. Script/SQL/Agent rollback/AI mock testleri geçti. Gerçek AI sağlayıcısına veri gönderilmedi.
- Release büyük grid ölçümü tekrar çalıştırıldı: 2.000.000 satır / iki kısa kolon, diske yazma **2,601 sn**, çift kayıtları seçme + 1.000.000 eşleşmenin sayısal ters sıralaması **3,675 sn**; test süreci en yüksek RSS **213.909.504 byte = 204 MiB**. Native 850 × 480 pt pencerede 1.000.000 kısa satırda son satıra programatik geçiş/layout **0,00875 sn**, **18** mevcut row view. Bunlar ağ sorgusu/GUI erişilebilirlik gecikmesi veya tüm veri türleri için garanti değildir.
- 5 milyon satırın tamamı, uzun/binary/date ağırlıklı milyonluk matris, aynı anda çok sayıda büyük sekme, disk dolması ve uzun export/crash senaryoları doğrulanmadı. Filtre/sıralama O(n) indeks/anahtar belleği kullanır. Önceki sürümdeki gerçek GUI milyon satır kontrolü aşağıdaki tarihsel bölümde ayrı belirtilmiştir.

Aşağıdaki 0.2.2–0.2.7 bölümleri önceki sürümlerdeki doğrulamaların tarihsel kaydıdır; güncel görünüm ve ölçümler yukarıdadır.

## 0.2.2 sağ tık ve ortam arayüzü

- Debug arayüzünde aynı yerel sunucuya farklı profillerle iki bağlantı açıldı. Canlı, Dikkat ve Test etiketleri/renkleri; özel RGB kodu; bağımsız ağaç/sekme/sorgu başlığı görünümü gözlendi. Bunlar yerel test sunucusu üzerindeki görsel etiketlerdir; gerçek üretim sunucusunda işlem yapılmadı.
- Sağ tık menüsünden yeni bağlantı formu, doğrudan bağlantı testi başarı mesajı, mevcut bağlantı düzenleme ve renk/ortam paneli açıldı. Hatalı RGB kodu reddedildi; doğru özel renk uygulandı. Görünüm değişiminde mevcut sorgu sonucu ve oturumu korundu.
- Düzenlemede `localhost` → `127.0.0.1` geçişi test/listeleme sonrası uygulandı: sorgu metni korundu, önceki sonuçlar temizlendi, SQL otomatik çalışmadı. Diğer profil ve sorgu sekmesi korunmuş kaldı.
- Son 0.2.2 Release ZIP'i çıkarılıp imzası doğrulandı ve açıldı. Boş Object Explorer'a sağ tıktan Sunucuya Bağlan formu açıldı; yerel bağlantı testi ve master seçimi başarıyla tamamlandı. Test başarılıyken RGB rengi değişince test sonucu/liste korunmaya devam etti.
- Release sorgusu ayrı pencereye taşındı: aynı Test etiketi, sunucu adı/adresi, veritabanı ve renkli sorgu başlığı korundu. Sorgu çalıştırılıp ana çalışma alanına geri yerleştirildi; sonuç korundu.
- Release düzenleme formunda mevcut ortam/özel renk/veritabanı seçimi görüldü; yeniden test ve listeleme başarılı. Başlık, açıklama ve düğme yerleşimi görsel olarak kontrol edildi.
- GUI kontrollerinde gerçek parola Keychain'e kaydedilmedi; yalnızca önceden onaylanan yerel TLS sertifika güveni kullanıldı. Keychain görünüm kaydı rastgele servis/uydurma parola ile otomatik testte doğrulandı. GUI sorguları yalnızca DB_NAME, SPID ve saat döndürdü; kullanıcı tablolarına yazılmadı.

## 0.2.1 bağlantı ve seçim arayüzü

Teslim edilen 0.2.1 Release ZIP'i `/tmp` altına çıkarıldı; imzası yeniden doğrulandı ve uygulama açıldı.

- Test yapılmadan Listele/Bağlan kapalı; geçersiz portta hata mesajı görünür, liste açılmaz.
- Yerel sunucuda başarılı bağlantı testi sonrası listeleme açıldı; 7 veritabanı başlangıçta seçilmemiş halde gösterildi. Keychain hatırlama bu GUI kontrolünde kapalı tutuldu.
- Debug arayüz kontrolünde parola değiştirilince test sonucu ve liste sıfırlandı; tekrar başarılı test ve listeleme yapıldı.
- Release arayüzünde iki veritabanı seçildi; arama birini gösterirken diğer seçim korundu. Bağlandıktan sonra ağaç ve seçicide yalnızca bu iki veritabanı vardı.
- Sunucu sağ menüsüyle seçim tek veritabanına indirildi. Ağaç yenilemesi gizlenen adları geri getirmedi; boş System Databases grubu gösterilmedi.
- Açık sorgu önceki veritabanını, sonuçlarını ve oturumunu korudu. Yeni Sorgu düğmesi yeni seçili varsayılan veritabanında açıldı; `DB_NAME()` bunu canlı sunucuda doğruladı.
- Sunucu/veritabanı/tablo/view/güvenlik/yönetim/Agent ikonlarının renk ayrımı native görünümde gözlendi. Form ve liste görsel olarak kontrol edildi.
- Gerçek kullanıcı tablolarına yazılmadı; GUI sorguları yalnızca veritabanı adı/oturum/saat döndürdü.

## Temel native arayüz doğrulaması (0.2.0)

Aşağıdaki temel akışlar önceki sürümde doğrulandı; 0.2.1'de otomatik core/live testleri tekrar çalıştırıldı.

- Xcode Debug ve Release derlemeleri başarılı.
- Release uygulaması ad-hoc imzalı; `codesign --verify --deep --strict` hem build ürününde hem teslim ZIP'i çıkarıldıktan sonra başarılı.
- ZIP'ten çıkarılan uygulama açıldı ve bağlantı formundan localhost SQL Server'a bağlandı. Keychain hatırlama kapalı tutuldu; yalnızca önceden onaylanan yerel sertifika güveni kullanıldı. TLS açık kaldı.
- Gerçek sunucunun veritabanı ve tablo ağacı açıldı; kullanıcı verileri değiştirilmedi.
- TextKit 2 editöründen ⌘Return ile sorgu çalıştırıldı; native grid ve Messages gözlendi. SQL lexer renkleri, ruler ve satır konumu görünür.
- Satır numarası alanının metni örten çizim sorunu giderildi: ruler ve pane çizimleri kendi sınırlarıyla kısıtlandı. Editörün yatay kaydırması ve sorgu/result bölücüsü native.
- Tahmini ve gerçek plan sekmeleri açıldı; gerçek katalog sorgusunun operatör ağacı görüntülendi.
- WAITFOR arayüzden iptal edildi; HY008 mesajı gösterildi ve oturum Ready durumuna döndü.
- Sorgu ayrı pencereye taşındı; bu penceredeki SELECT aynı SPID'yi döndürdü. Geri yerleştirme metin/sonuç/oturumu korudu.
- Native sütun tamamlama listesi tablo aliasından açıldı; [Name] seçimi editöre eklendi.
- Son Release paketinde Workspace.sql native dosya seçiciyle açılıp çalıştırıldı: 3 veri sonucu, toplam 10 satır ve PRINT mesajı. Mock tablodaki iki satır GUI üzerinden JSON dışa aktarıldı; dosyadaki sütunlar, Türkçe metin ve decimal değerler doğrulandı (`Validation/Results.json`).

Tam test isimleri ve sonuçları `Validation/tests.txt` altında. Paket build özeti `Validation/build.txt` altında.

## Kalan işler ve doğrulanmayan koşullar

Bu rapor tam SSMS eşdeğerliği veya üretim olgunluğu iddia etmez.

- Kerberos string'i sınandı; gerçek Active Directory, SPN ve Kerberos biletiyle bağlantı denenmedi.
- AI'nin aktarım katmanı sahte sağlayıcıyla sınandı; gerçek model sunucusu/API anahtarı verilmedi, harici AI'ya veri gönderilmedi.
- Agent job oluşturma ve schedule SQL'i rollback içinde sınandı; Agent servisinin job çalıştırması veya zamanlaması denenmedi.
- İsteğe bağlı Timeline / recovery kodu mevcut; crash/force-quit ve izin/disk-dolu senaryolarıyla uzun süreli kurtarma testi yapılmadı. Yeni oturumda yeniden açıkça bağlanmak gerekir.
- Tam parser/binder ve query scope çözümlemesi yok; completion basit CTE/derived projections ve metadata için yardımcıdır. Complex APPLY, nested scope veya star projection tam çözülmez.
- Execution plan grafik bağlantı diyagramı yerine operatör ağacı ve XML sunar.
- Pencereye ayırma ve yeniden yerleştirme çalışır; genel amaçlı drag/drop docking motoru yoktur.
- Grid veri düzenleme, görsel schema/relationship tasarımı, backup/restore sihirbazları, tam role/permission editörleri ve binary plugin SDK tamamlanmadı.
- Eklentiler SQL şablonlarıdır, açık panelde tutulur. AI ve yönetim tasarımları SQL'i editöre aktarır; otomatik uygulamaz.
- Paket yerel Homebrew bağımlılıklarını kullanır; driver/runtime bundling, notarization ve App Store dağıtımı yapılmadı.
- SQL Server 2022 yerel ortamı dışında sürüm/edition ve düşük yetkili kullanıcı matrisi sınanmadı. DBA DMV/Agent özellikleri sunucu izinleri gerektirir.

Sonraki geliştirme, bu çalışan native çalışma alanını temel almalı; bu sınırlar arayüzde hazır özellikler gibi gösterilmemeli.


## 0.2.3 tema doğrulaması

- Release build ve ZIP'ten çıkarılan uygulamanın kod imzası doğrulandı.
- Native UI'da parola → bağlantı testi → liste → yalnızca master seçimi → bağlantı tamamlandı; Keychain kaydı kapalı tutuldu. Mevcut kullanıcı tablolarına yazılmadı.
- Türkçe string, int değişken, sayı, GETDATE, NULL ve comment içeren SELECT bir satır döndürdü. Açık temada mavi keyword, kırmızı string, yeşil comment, eflatun GETDATE, teal satır numarası, Consolas ve sarı NULL vurgusu görsel kontrol edildi.
- Ayarlardaki gerçek fontlar Consolas 13 pt / Tahoma 12 pt olarak gözlendi. Koyu temaya geçince açık sorgu metni/sonuçları korundu ve editör/grid/paneller koyu renge geçti.
- Otomatik native editör testi Unicode metni, seçimi, TextKit 2'yi, keyword/comment renklerini ve tema değişiminden sonra undo'yu doğrular. Undo bildiriminde editör metni ile çalıştırılan/kaydedilen model metninin eşit kalması için senkronizasyon eklendi.
- Markdown render kodu derlendi; gerçek AI sağlayıcısından Markdown yanıtı görsel olarak denenmedi. Tam SSMS font, ikon ve piksel eşleşmesi doğrulanmadı; native kontroller korunuyor. Koyu palet Visual Studio'dan uyarlamadır.

Son paket kontrolü: 0.2.3 ZIP tekrar `/tmp` altında çıkarıldı, strict kod imzası doğrulandı. Paketlenmiş uygulamada bağlantı testi ve master seçimi tamamlandı; DB_NAME / @@SPID / SYSDATETIME sorgusu bir satır döndürdü.


## 0.2.4 kompakt yerleşim

Başlık/tab/durum satırlarının sabit yüksekliği toplam 165 → 124 pt oldu. Sonuç seçimi ayrı native sekme şeridinden aynı araç satırına taşındı. Fontlar küçültülmeden editör satır aralığı, ağaç/grid satırları ve kenar boşlukları sıkılaştırıldı.

Native UI kontrolü: yerel bağlantı testi, listeleme ve yalnızca master seçimi tamamlandı. SELECT bir satır döndürdü. ⌘R ile sonuçlar gizlenince ayırıcı 609.5 → 1015 pt'ye gitti; geri açıldığında 609.5 pt'ye döndü ve sonuç korundu. ⌥⌘B ile nesne ağacı kapandı. Kompakt seçiciden Messages'a geçilip çalışma mesajı görüntülendi. Bu ölçümler kontrol edilen geniş pencereye aittir; tüm ekran boyutları için aynı kazanç yüzdesi iddia edilmez.

Otomatik yerleşim testi iki sonuç kümesi/Messages seçimini, sonuç gizleme ile editöre alan açılmasını, açılışta ayırıcı oranının geri gelmesini, SQL ve sonuçların korunmasını denetler. Derleme, tüm testler ve ZIP imza kontrolü tamamlandı. Mevcut kullanıcı tablolarına yazılmadı.

Son paket kontrolü: TextKit 2 gerçek fragment/baseline konumlarıyla satır numaraları, sondaki boş satır dahil 1–4 olarak görsel doğrulandı. Son Release ZIP strict imza kontrolünden geçti; yerel bağlantı ve iki SELECT çalıştı. Son editör değişikliğinden sonra ilgili 2 native test tekrar geçti.


## 0.2.5 bağlantı ve büyük veritabanı listesi

- Release derlemesi ve son ZIP'ten çıkarılan uygulamanın strict kod imzası başarılı. Son kaynaklarla 34 test / 7 suite, bunların içinde 11 canlı SQL Server testi geçti.
- Arama/seçim testinde 1.006 katalog öğesi kullanıldı: 1.000 kullanıcı adı, dört sistem veritabanı ve iki ek ad. Çok terimli arama, Türkçe Unicode, doğal sıralama, sistem/kullanıcı/selected-only filtreleri, filtre dışı seçimlerin korunması ve deterministik varsayılan sınandı. Bu, 1.006 gerçek veritabanıyla sunucu performans testi değildir; yerel sunucuda 7 veritabanı vardır.
- Native UI'da 940 × 620 pt form ve 760 × 580 pt Object Explorer seçim penceresi görsel kontrol edildi. Kimlik alanları, filtreler, liste ve işlem düğmeleri form kaydırılmadan görünür. Yalnızca liste kayar.
- Başarılı bağlantı testi otomatik olarak yedi veritabanını yükledi. `mas` araması tek master sonucunu verdi; Enter master'ı seçti ve form açık kaldı. Kullanıcı filtresinde üç görünür adı toplu seçmek, gizli master seçimini korudu. Seçilenler filtresinde dört ad gösterildi. Görünenleri kaldırınca boş seçim ve kapalı Bağlan düğmesi doğrulandı. Filtre sıfırlama ve yıldızla master varsayılanı çalıştı.
- Tekrar bağlantı testi ve liste yenileme seçimleri korudu. Son teslim ZIP'inde bu akış tekrar edildi, yalnızca master ile bağlantı ve bir satırlık DB_NAME / SPID / saat sorgusu başarılı oldu.
- Object Explorer sağ tık → Veritabanlarını Seç ekranında `temp` araması ve Enter ile seçim yapıldı. Uygulama sonrası ağaçta yalnızca master/tempdb göründü; açık sorgunun sonucu ve SPID'si korundu.
- İlk UI denemesinde SwiftUI List'in native NSTableView yerleşiminde exception gözlendi. Kontrol ScrollView/LazyVStack ile değiştirildi; filtreleme, toplu seçim, yeniden test, yenileme ve bağlantı akışları yeniden tamamlandı. Büyük listenin görünmeyen satırları gerektiğinde oluşturulur.
- Ortam panelini açmanın kendiliğinden özel renk işareti oluşturması engellendi; son pakette panel açılırken “Ortam işareti yok” korundu. Önceki ortam/renk özellikleri korunur. Yerel TLS güveni önceden verilen onayla kullanıldı; şifreleme açık, gerçek parola Keychain'e kaydedilmedi. GUI testleri mevcut kullanıcı tablolarına yazmadı.


## 0.2.6 birleştirilmiş bağlantı ayarları

- Release derlemesi, son kaynaklarla 34 test / 7 suite (11 canlı test), biçim denetimi ve ZIP çıkarıldıktan sonra strict kod imzası başarılı.
- Teslim edilen Release ZIP'i `/tmp` altına çıkarılıp açıldı. Yerel test sunucusuna master seçimiyle bağlanıldı; SELECT bir satır döndürdü. Gerçek parola Keychain'e kaydedilmedi.
- Sunucu sağ tık menüsü gözlendi: Bağlantı ayarları, Bağlantıyı Kes, Yeni Sorgu, Yenile, Adı Kopyala. Kullanıcının kaldırılmasını istediği dört öğe yoktur; yeni bağlantı üst araç çubuğu/sidebar başlığından açılır.
- Bağlantı ayarları tıklanınca hiçbir test/listeleme düğmesine basılmadan başarılı test ve yedi veritabanı yüklendi; önceki master seçili ve varsayılan kaldı. Form başlığı/menu adı aynı. Tekrar açılışta yükleme durumu ve sonrasında önceki iki seçim/Test ortamı gözlendi.
- 940 × 680 pt form görsel olarak doğrulandı: Ortam seçicisi, renk seçimi/RGB kodu, Varsayılan ve İşareti Kaldır doğrudan görünür. Ortam popover düğmesi yoktur. Normal ayar akışında tüm alanlar ve Uygula düğmesi form kaydırılmadan görünür.
- Aynı ekranda Test ortamı ve tempdb ek seçimi uygulandı. Ağaç/başlık ortamı güncellendi, açık sorgunun metni ve sonucu korundu. Tekrar SELECT aynı SPID'yi döndürdü. Ayarlar tekrar açılıp Vazgeç ile kapatıldı; aktif çalışma alanı korundu.
- Test hataları ve kimlik/endpoint değişiminde mevcut oturumun korunması otomatik bağlantı düzenleme testinde yeniden sınandı. Gerçek sunucu erişimi başarısızken otomatik açılış testi başarılı olarak işaretlenmez. Mevcut kullanıcı tablolarına yazılmadı.


## 0.2.7 grid / büyük sonuç doğrulaması

- Son kaynaklarla tam doğrulama: 38 core + 5 uygulama testi, 9 suite başarılı; bunların 11'i canlı localhost SQL Server kullanır. İki büyük benchmark normal çalıştırmada env guard ile atlanır; ayrıca `MSSQL_GRID_BENCHMARK=1 scripts/test.sh -c release --filter ResultGrid` ile gerçek büyük veri gövdeleri çalıştırıldı ve geçti (7 core + 2 UI testi). Benzersiz toplam 43 testtir; tekrar çalıştırmalar bu sayıya eklenmez.
- Core testler: sabit disk snapshot'ı/rastgele erişim/Unicode/NULL/boş metin ve kopya semantiği; Decimal sınırı 9007199254740993, sayısal/tarih sıralaması/eşit anahtarda kararlılık, birleşik koşullar/genel arama, geçersiz sayısal girdi/ters aralık; 500 farklı değer sınırı ve sınır dışındaki değeri arama; filtrelenmiş/sıralanmış JSON/CSV, aynı adlı sütunlar, NULL/boş ve CSV formül önlemi. İptal sonrası hedef dosyanın korunması sınandı.
- Native uygulama testi hızlı filtre değişiminde son isteğin kazanmasını, iki kolonun AND koşulunu, kaynak satırların korunmasını ve kimlik projeksiyonuna dönüşü doğrular. Diğer bağlantı, TextKit 2 tema ve kompakt layout testleri yeniden geçti.
- Release benchmark: **2.000.000 satır / iki kısa kolon** özel geçici dosyaya **3,42 sn**'de yazıldı. Çift satırları seçip 1.000.000 eşleşmeyi sayısal ters sıralama **4,91 sn** sürdü. Test sürecinde getrusage ile en yüksek RSS **204.521.472 byte (yaklaşık 195 MiB)** ölçüldü. Bu sayı uygulamanın bütün durumları için bellek garantisi değildir; küçük testlerin ve test runner'ın bellek kullanımı da aynı süreçte bulunur. Wrapper/compiler RSS'siyle karıştırılmadı.
- Native Release benchmark: 1.000.000 kısa satırlı, 850 × 480 pt gerçek NSWindow içinde son satıra programatik kaydırma/layout yaklaşık **0,013 sn**, mevcut native row view sayısı **19**. Yalnızca görünür satırların çizilmesi doğrulandı. Bu ölçüm ağ yükleme veya erişilebilirlik aracının yanıt süresi değildir.
- Canlı GUI: salt okuma `sys.all_objects` çapraz sorgusundan **1.000.001 satır / iki kısa kolon** yüklendi; uygulamanın sorgu süresi **3,203 sn**. Genel `Çift` araması 500.000 eşleşme gösterdi. En alt görünümde 999962…1000000 kaynak satırları görüldü. Büyük mod 5 milyon sınırı seçilmişti; **beş milyon satırın tamamı bu turda yüklenmedi**. Kullanıcı tablolarına yazılmadı.
- Native UI'da int, date, Türkçe metin, NULL ve boş metin içeren dört satırlı sonuç kontrol edildi. NULL + boş metin değer seçimi 2/4 satır gösterdi; kaldırılabilir kolon etiketi ve aktif başlık görüldü. Son Release ZIP'i çıkarılıp açıldı; sayılar 2,3,4,10 sıralandı. Kolon sağ menüsünde filtre, içeriğe sığdır, gizle/göster gözlendi; Şehir kolonu gizlendi. Tarih filtre paneli açıldı. Alternatif satır zemini, sağa hizalı sayılar ve NULL vurgusu görsel kontrol edildi.
- GUI dışa aktarma akışı arka plana taşındı; gerçek GUI dosya seçiciyle kaydetme bu turda tekrar edilmedi. Akış dosya yazıcısı, filtre/order ve mevcut hedefe güvenli replacement otomatik testte doğrulandı. Kopyalama 10.000 satır/16 MB ile sınırlıdır.
- Büyük date/long text/binary kolon matrisi, eşzamanlı birçok milyonluk sonuç, disk dolması ve çok uzun export/crash senaryoları yük testi yapılmadı. Sıralama indeksleri/anahtarları RAM'de büyür; sınırsız veri/sabit RAM veya tam disk üzerinde dış sıralama iddiası yoktur. Kısmi sonuçta filtre yalnızca yüklenen bölümü kapsar.
- Release build, biçim denetimi, ZIP bütünlük/parola taraması ve çıkarılan paketin strict imzası tamamlandı. Ortam/renk ve birleştirilmiş bağlantı ayarları korunur.

## 0.2.11 ek doğrulama ve sınırlar

58 test / 14 suite başarılı (uygulama 19/9, core 39/5); 12 canlı yerel SQL Server testi dahil. Yeni testler gerçek sayfa aralığı, sayfalı kopyalama/dışa aktarma, kalıcı özel varsayılan, sekme yeniden sıralama, Explorer veritabanı seçimi, gerçek kısayol kayıt/çakışma kontrolü, sınırlı otomatik genişlik ve satır önbelleği tahliyesini kapsar.

Yeni paket arayüzünde kayıtlı bağlantı ve 7 veritabanı seçimi geri geldi, yerel bağlantı başarılı oldu. Sentetik üç satırlı SELECT ile bit hücreleri, soldaki Results/Messages, sağdaki arama ve otomatik kolon genişliği görüldü. ⌘R ile gizlenen panelin önceki yüksekliğinde çizgi kalmadığı ekran görüntüsüyle kontrol edildi. ⌘N yeni query açtı. Native sürükleme girişimi bilgisayar kullanım aracında noWindowsAvailable hatası verdi; gerçek fare hareketi elle doğrulanamadı, yeniden sıralama eylemi otomatik testte doğrulandı.

Release ölçümü: 2 milyon kısa satır depolama 2,634 sn, filtre/sıralama 3,968 sn; test süreci tepe RSS 215.465.984 bayt. Bir milyon / iki kolon grid 18 görünür satır üretti. 10.000 satır / 64 kolon geniş grid’de 80 programatik dikey/yatay konum değişimi toplam 11,269 sn, p95 186 ms, 19 görünür satır. Bu ekran FPS ölçümü değildir; geniş tabloda halen gecikme vardır ve kusursuz akıcılık iddia edilmez. 500 satırlık varsayılan sayfalama ve sınırlı çözülmüş satır önbelleği maliyeti azaltır; All modunda çok geniş sonuçlar hâlâ pahalıdır.

## 0.2.12 doğrulaması

63 test / 15 suite: uygulama 20/9, core 43/6; 13 canlı localhost testi. Kısa → uzun → kısa editör metninde yatay genişlik testi, arama escaping/tür/sınır testleri, ALTER dönüşümü ve doğrusal fark testleri, DDL hedeflerinde string/comment ayrımı eklendi. Yeni canlı test izole, benzersiz bir procedure oluşturur, filtreyle bulur, tanımı ALTER eder, değişen tanımı okur ve transaction rollback ile temizler; mevcut kullanıcı nesnelerine yazmaz.

Önceki bölümdeki grid performans sayıları 0.2.11 ölçümüdür; bu sürümde tekrar FPS ölçümü yapılmadı. Katalog araması UI’da 500 sonuçla sınırlıdır; sunucu CHARINDEX araması büyük kataloglarda sunucuda tarama yapabilir. Ayrı disk indeksi veya harici DDL aboneliği eklenmedi. Tam SSMS menü/tasarım özellikleri iddia edilmez.

Native smoke: yeni uygulama kayıtlı localhost bağlantısıyla açıldı; 7 DB seçimi korundu. Explorer gizlendi ve orta alandaki düğmeyle geri açıldı; Messages içinde yerel çalıştırma tarihi/saat ve DB görüldü. Seçili sunucu kapsamındaki eşleşmeyen arama master veritabanında 0 sonuçla tamamlandı; temizlenince normal ağaç geri geldi. Arama tüm alt nesneleri açmadı. ALTER çalıştırma/rollback canlı core testinde doğrulandı; gerçek kullanıcı procedure’u değiştirilmedi.

## 0.2.13 disk indeksi doğrulaması

69 test / 16 suite geçti: uygulama 20/9, core 49/7; 14 canlı localhost testi dahil. Beş disk testi persistans, ikinci actor ile yeniden açma, kapsam ayrımı, atomik staging/eski snapshot koruma, boş indeks, Türkçe/Unicode operatörler, literal wildcard, tür filtresi, hedef değişikliği/drop, diğer kayıtların korunması, ağsız warm service ve iptali kapsar. Yeni canlı test salt okunur server kataloğundan ilk indeksi oluşturur, yeniden açar ve warm cache'in authentication gerektirmediğini doğrular.

50.000 kısa ad için test derlemesinde yerel build 0,6404 sn; contains ve eşitlik araması toplam 0,01032 sn. SQL Server indirme süresi dahil değildir; milyonlarca nesne/FPS ölçümü değildir. Contains/suffix yerel tarama yapabilir. Önceki grid ölçümleri 0.2.11 sürümündendir.

Native smoke: kayıtlı bağlantı ve 7 DB seçimi korundu. master ilk indeks/yerel sonuç/elle eşitleme doğrulandı. İkinci dolu veritabanında 71 nesne indekslendi ve yerel arama tamamlandı. Kullanıcı nesnelerine yazılmadı. Paket ZIP bütünlüğü, credential taraması ve çıkarılmış uygulama imzası doğrulandı.

## 0.2.14 doğrulaması

73 test / 17 suite geçti: uygulama 21/9, core 52/8; 14 canlı localhost testi dahil. Yeni testler eski kayıtların taşınmasını, açıkça bağlantısı kesilen Explorer'ların yeniden açılmamasını, eksik kayıtların elenmesini, kapsamın metin temizlenince korunmasını, update ZIP yolları/traversal ve sürüm kontrolünü kapsar. Gerçek imzalı 0.2.14 ZIP paketi core updater ile staging'e açılıp doğrulandı; hedef uygulama bu testte değiştirilmedi. Otomatik testler yalnızca localhost üzerinde SQL çalıştırdı.

Kalıcı ~/Applications/MSSQLStudio.app konumuna kuruldu ve çıkarılmış/kurulmuş imzalar doğrulandı. Native açılışta bağlantı formu yerine kayıtlı Explorer görüldü, çevrimdışı başlangıçtan bağlantılı çalışma alanına geçti ve kayıtlı veritabanı seçimleri göründü. Gerçek kullanıcı nesnelerine SQL yazılmadı. Bağlantı/DB ve tür kapsamı seçicileri native arayüzde görüldü. Güncellemenin paket doğrulama/staging yolu sınandı; gelecekteki bir sürüme gerçek quit/replace/relaunch döngüsü bu teslimde çalıştırılmadı. İndirme feed'i yoktur; güncelleme yerel ZIP seçimiyle başlar.

## 0.2.15 doğrulaması

77 test / 18 suite geçti: uygulama 23/9, core 54/9; 15 canlı localhost testi dahil. Yeni native kontrol testi iki ayrı veritabanının yerel indeksini hazırlar, Explorer kapsamındaki aramada ikisinin de doğru DB ile geldiğini ve kapsamın UUID|* olarak kaydedildiğini doğrular. Yeni canlı localhost testi yalnızca bağlantı kurar, arama/elle yenileme yapmadan master disk indeksinin hazırlanmasını bekler. Mevcut ZIP staging testi gerçek 0.2.15 paketini doğrular. Update testleri JSON sürüm bilgisi çözümlemesini ve HTTP feed'in ağ isteğinden önce reddedilmesini kapsar.

Release derlemesi, ZIP çıkarıldıktan sonra ve kalıcı kurulumdan sonra strict codesign doğrulaması geçti. Native smoke: kayıtlı Explorer ile açıldı, kapsam menüsünde Tüm seçili veritabanları ve tek DB seçenekleri görüldü. Güncellemeleri Kontrol Et dosya seçimi açmadan henüz yayın adresi olmadığını bildirdi. GitHub deposu kullanıcı tarafından daha sonra eklenecek; gerçek uzaktan sürüm kontrolü/indirme henüz doğrulanmadı. Test kopyası kapatıldı; kullanıcının açık sorguları bulunan eski oturumu kapatılmadı. Yeni sürüm ~/Applications/MSSQLStudio.app konumuna atomik değişimle kuruldu; bir sonraki normal açılışta çalışacak. Önceki uygulama sürümü yerel yedekte korundu. Otomatik canlı testler yalnızca localhost üzerinde çalıştı; native smoke bağlantı açılışı seçili kayıtlı sunucuda salt okunur metadata hazırladı, kullanıcı nesnelerine yazmadı.

## PKG kurulum paketi

0.2.15 uygulama kodu değişmedi; önceki 77 test sonucu geçerlidir, bu paketleme değişikliğinde yeniden çalıştırılmadı. pkgbuild/productbuild başarılı. pkgutil --expand-full ile paket açıldı; payload uygulaması codesign --verify --deep --strict denetimini geçti. Distribution sadece CurrentUserHomeDirectory alanını etkinleştiriyor; Installer -dominfo ile doğrulandı. Bundle yolu Applications/MSSQLStudio.app, relocation false, version 0.2.15 ve must-close bundle ID doğrulandı. Payload yalnızca uygulama içeriyor, AppleDouble yan dosyaları yok. Paket imzasızdır (bu Mac'te geçerli dağıtım sertifikası bulunmadı). Açık kullanıcı oturumu korunması için gerçek kurulum/reinstall ve Installer GUI akışı çalıştırılmadı. Sonuçlar Validation/pkg.json dosyasında.


## 0.2.16 — Explorer arama ve SQL editörü

- Nesneler/Arama sekmeleri: aramayı temizleme açık dalları, seçili nesneyi ve kaydırma konumunu geri getiriyor. Native arayüzde doğrulandı.
- SSMS açık tema kategorileri: anahtar sözcük mavi, metin kırmızı, sistem fonksiyonları magenta, yorum/sistem nesneleri yeşil, prosedür bordo. Native renk kontrolü geçti.
- TextKit 2 korunuyor. Yazarken tüm belgeye font/paragraf uygulanmıyor; yalnızca rengi değişen aralıklar güncelleniyor. Tab dört boşluk genişliğinde; seçili blok Tab/Shift+Tab ve satır başı girintisini koruyan Enter eklendi.
- Kısa satırlar için yatay hareket sınırlandırıldı, uzun satırlarda yatay kaydırma korunuyor. Son SQLClipView düzeltmesinin native görsel kontrolü tamamlanamadı: geçici uygulama kayıtlı bağlantıları okurken Anahtar Zinciri yanıtını bekledi. Bu nedenle baş kesilmesi/beyaz parlamanın tüm gerçek kullanım durumlarında giderildiği henüz doğrulanmış sayılmamalı.
- Release derlemesi başarılı. PKG içindeki uygulamanın katı imza doğrulaması geçti; paket 0.2.16 (17), yalnızca kullanıcı alanı, relocation kapalı. Paket imzasız; gerçek kurulum çalıştırılmadı. Açık kullanıcı sorguları korunmuştur.
- Tam SSMS dil hizmeti/akıllı girinti eşdeğerliği iddia edilmez; nesne DDL içeriği otomatik yeniden biçimlendirilmez.

Son test turu: 26 uygulama testi ve 54 çekirdek testi raporu başarılı; 15 localhost SQL Server testi etkin. İki isteğe bağlı test (assistantTransportAndRedirect, keychainLifecycle) atlandı.


## 0.2.17 — Editör girişi ve güvenli UI testleri

SQLTextView düzenlenebilir/seçilebilir olarak açıkça yapılandırılır; ilk tıklama editörü odaklar. Arama alanından boş editöre tıklayıp normal klavyeyle SELECT 1; yazılması native arayüzde doğrulandı. 26 uygulama + 54 çekirdek test raporu başarılı; bu tur canlı DB testleri etkinleştirilmedi.

Başlangıçta ServerVault.list ana UI iş parçacığında çalışmaz. Anahtar Zinciri izni beklenirken uygulamanın ana olay döngüsü açık kalır. Görsel test hazırlama scripti ayrı local.mssqlstudio.uitest kimliği kullanır; bu kimlikle başlatılan uygulama kayıtlı bağlantıları, parolaları ve kullanıcı sunucularını okumaz, bağlantısız bir sorgu açar. --ui-smoke argümanı da aynı davranışı sağlar. Test modu bağlantı kaydetme gibi işlemleri test etme yetkisi vermez.

Mevcut dağıtım ad-hoc imzalıdır; Developer ID imzalama kimliği bulunmadı. Kullanıcının daha önce verdiği Keychain izninin farklı derlemelerde otomatik korunacağı garanti edilmez. ACL'ler gevşetilmedi, parolalar düz metne taşınmadı. Kalıcı sürüm kimliği için aynı Developer ID ile imzalama gerekir.


## 0.2.18 — İlk açılan boş SQL belgesi

0.2.17 native kontrolü önceden metin içeren test belgesiyle yapıldığı için ilk açılışta tamamen boş editörün tıklama sorununu yakalayamadı. Kullanıcının 0.2.17 penceresinde hata tekrarlandı: ilk boş belge tıklama ile odaklanmadı; erişilebilirlik yoluyla geçici metin atanıp temizlenince tıklama/yazma çalıştı. Geçici kontrol metni geri alındı; kullanıcı sorgusu boş bırakıldı.

EditorController artık ilk metin atamasını belge boşken de yapar; sonraki eşit metin güncellemelerinde gereksiz atama yapmaz. UI test modu artık ilk açılışta tamamen boş bir belge açar. Anahtar Zinciri ve sunucu bağlantısı kullanılmaz.

0.2.18 kontrolünde yalnızca ilk boş string atamasının yeterli olmadığı görüldü. SQLEditorScrollView artık boş metnin hit bölgesi oluşmamış olsa da belge viewport içindeki tıklamayı SQLTextView'a yönlendirir; ruler ve scroller bölgelerini korur. Boş native hit bölgesini taklit eden regresyon testi eklendi.

Son native kontrol başarılı: yeni test uygulaması ilk açılışta tamamen boş sorguyla başladı; hiçbir ön metin ataması olmadan editöre tıklayıp SELECT 1; yazıldı. Undo ile boşaltılıp arama alanına geçildi; editöre tekrar tıklayıp yorum yazıldı. Odağın sqlEditor'da ve metnin sorguda olduğu AX ile doğrulandı. Test metni geri alındı ve test uygulaması kapatıldı. 27 uygulama + 54 çekirdek test raporu başarılı; canlı SQL Server testleri bu tur etkin değildi.


## 0.2.19 — Sabit satır alanı ve blok daraltma

SQL metni ile satır numaraları artık aynı native ruler/clip yerleşimini paylaşmaz. 68 punto genişliğinde ayrı bir alan Auto Layout ile metnin solunda kalır. Satır numarasına tıklamak satırın bütün metnini ve varsa satır sonunu seçer. En sağdaki −/+ düğmeleri çok satırlı BEGIN–END, BEGIN TRY–END TRY ve BEGIN CATCH–END CATCH bloklarını açıp kapatır; iç içe bloklar desteklenir. IF/ELSE dallarında bu BEGIN blokları kullanılır. CASE/END, BEGIN TRANSACTION, yorum ve string içindeki sözcükler yanlış kapanış sayılmaz. Eşleşmemiş bloklar daraltılmaz.

Daraltılmış görünümde özgün satır numaraları korunur, gizlenen alan … ile gösterilir. Düğme üzerine gelince kod önizlemesi görünür. Editör sağ tık menüsü ve ⌥⌘[ (imlecin bulunduğu en içteki bloğu daralt/aç), ⌥⌘] (tümünü aç) kullanılabilir. Bunlar macOS kısayollarıdır; SSMS'in Windows Ctrl+M akoru kopyalanmaz.

Daraltma dosyanın SQL metnini veya dirty durumunu değiştirmez. Kopyalama/seçili kod çalıştırma özgün kaynak aralıklarına eşlenir. Düzenleme ve undo/redo öncesi daraltılmış alanlar açılır; gizli kodun yanlışlıkla görünüm yer tutucusuyla değiştirilmesi önlenir. Formatlama/metin değiştirme blok durumunu sıfırlar. Oturumlar arasında daraltma durumu saklanmaz. Yapısal analiz 250.000 UTF-16 karaktere kadar yapılır; üstünde blok analizi devre dışıdır. Satır numarası için satır başlangıçları önbelleğe alınır, her görünen satırda belgenin başı tekrar taranmaz.

Kapsam: BEGIN tabanlı bloklar. SSMS'in tüm batch ve çok satırlı statement outline dil hizmeti eşdeğerliği iddia edilmez. Tek satırlı veya BEGIN kullanmayan IF/ELSE ifadeleri için ayrı daraltma bölgesi üretilmez. TextKit 2, native undo ve mevcut SQL çalıştırma katmanı korunur.

Microsoft kaynakları: https://learn.microsoft.com/en-us/ssms/scripting/code-outlining ve https://learn.microsoft.com/en-us/ssms/sql-server-management-studio-keyboard-shortcuts .

Native 0.2.19 doğrulaması: boş editöre normal klavyeyle yazıldı, satır numarası/kod ayrımı ekran görüntüsünde kontrol edildi. BEGIN bloğu eksiyle daraltılıp artıyla açıldı; görünür satır numaraları 2'den 5'e atlayarak özgün kaynak numaralarını korudu. 3. satır numarasına tıklandı; yazı yalnızca bu satırı değiştirdi. Undo özgün Unicode satırı satır sonuyla seçili geri getirdi. Bir blok daraltılmışken diğer dal düzenlendiğinde gizli İstanbul satırı korunarak bütün kod açıldı. Test kopyası temizlenip kapatıldı; gerçek kullanıcı bağlantıları/sorguları kullanılmadı.

Son test raporu: 31 uygulama testi + 54 çekirdek testi raporu başarılı. 15 canlı SQL Server testi ve iki isteğe bağlı entegrasyon testi bu tur devre dışı. Release imza/PKG doğrulaması ayrı raporlanır; Installer ile kurulum bu tur çalıştırılmaz.


## 0.2.20 — DDL kolon indeksi ve editör zekâsı

Son koşu: uygulama hedefi 33 test / 9 suite; çekirdek 63 test / 10 suite raporu başarılı. Bu raporlardaki 17 koşullu test devre dışı bırakıldı (Keychain/AI ve diğer canlı senaryolar); kaynakta atlanan testler başarıyla çalıştırılmış sayılmaz. Ayrıca yalnızca `liveReadOnlyCatalogSnapshotAndWarmDisk` etkinleştirilerek localhost SQL Server üzerinde **1 canlı salt okunur test geçti**. Bu test ayrı bağlantıda master metadata snapshot'ı üretir, SQLite dosyasını yeni servisle açar, kolon dizilerini karşılaştırır ve başka veritabanı kapsamına sızmadığını doğrular. Kullanıcı verisinde değişiklik yapılmadı.

İlk canlı deneme /usr/bin Swift yönlendiricisinin OpenSSL ortamını kaybetmesi nedeniyle SSL kitaplığı yükleme hatası verdi. Xcode toolchain'in gerçek Swift yolu ve OpenSSL 3 ortamıyla yeniden koşu 0,200 saniyede geçti. Sistem kitaplıkları değiştirilmedi. Gerçek 0.2.20 ZIP'iyle update hazırlama/imza/sürüm kontrolü çalıştı; kurulum yapmadı.

Yeni testler: eksik nesne ve aliaslı/yalın kolonlar; doğru JOIN başvuruları; imleç altında yazılan adın işaretlenmemesi; eski/doğrulanmamış katalog ve USE/cross-database/sys/temp bağlamlarında muhafazakâr davranış; tablo/view tamamlaması ve schema prefix; alias çakışması/mevcut alias/alias kapatma; EXEC procedure; statement kapsamı; basit CTE/temp kolonları; literal içinde öneri vermeme; disk kalıcılığı ve kapsam ayrımı; 25.000 nesne/125.000 kolon adından en fazla 100 öneri (bu Mac'te fixture oluşturma + analiz testi yaklaşık 0,05 saniye); debounced kırmızı attribute ve eski edit analizinin yayınlanmaması. Önceki gutter/folding/Unicode/undo/TextKit 2 regresyonları da geçti. Büyük indeks testi etkileşimli FPS garantisi değildir.

Native Release UI: ayrı bundle ID ile Keychain'siz, ağsız boş belge; sentetik Customers/Orders kolon indeksi. Normal klavyeyle `SELECT * FROM Cus` yazıldığında tablo popup'ı açıldı; Tab ile `[dbo].[Customers] AS c` eklendi. `c.` + ⌃Space yalnızca CustomerID/Name/City önerdi; ok+Enter ile Name seçildi. `Na` tamamlaması `[c].[Name]` ekledi, ⌘Z ile geri alındı. Eksik c.NotThere kırmızı ve altı çizili ekran görüntüsünde, eksik dbo.NotExisting AX üzerinde doğrulandı. Editör odağı korundu; test belgesi temizlenip yalnızca test uygulaması kapatıldı. Kullanıcının çalışan sürümü, açık sorguları ve Keychain erişimi kullanılmadı.

Release ARM64 build başarılı. Uygulama ad-hoc imzalı; ZIP ve PKG payload'ında strict imza kontrolü yapıldı. PKG kişisel Applications konumunu günceller, relocation kapalıdır. Installer paketi Developer ID ile imzalı/notarized değildir ve bu tur gerçek Installer kurulumu çalıştırılmadı. İki mevcut Swift uyarısı (gutter accessibility actor callback ve DDL panelindeki weak capture), ayrıca AppIntents kullanılmadığı için metadata extraction uyarısı vardır; build hatası yoktur. Tam parser/collation/schema eşdeğerliği, bütün canlı regresyonlar, Keychain erişim izinleri ve interaktif büyük-belge FPS testi bu tur doğrulanmış değildir.

Son görsel kontrolde firstRect tabanlı popup konumunun hatalı olduğu görüldü. Popup konumu TextKit 2 selection segment geometrisine ve pencere content-view koordinatlarına geçirildi; sıfır genişlikli caret rect en az 1 puntoya genişletildi; imleç için yerel rect doğrulayan regresyon testi eklendi. Son paketin görsel kontrolü bu düzeltmeyle tekrarlandı.
