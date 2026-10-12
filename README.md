# MSSQL Studio

SQL Server için native macOS çalışma alanı. Solda Object Explorer, ortada SQL editörü ve bağımsız sorgu sekmeleri, altta sonuçlar/mesajlar/plan ağacı bulunur. macOS 27+, Apple Silicon, Swift 6, AppKit/SwiftUI ve TextKit 2 kullanır.

## Kurulum ve başlangıç

[Son GitHub yayınından](https://github.com/erhanulas/MSSQLStudio/releases/latest) PKG'yi indirip uygulama kapalıyken kurun. Hedef `/Applications/MSSQLStudio.app` konumudur. Son doğrulanmış sürüm **0.2.52 / build 53**.

Microsoft ODBC Driver 18, unixODBC ve OpenSSL 3 ayrı kurulur; sürücüler app paketinde dağıtılmaz. [Microsoft macOS kurulum yönergesi](https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/install-microsoft-odbc-driver-sql-server-macos) kullanılabilir. Apple Silicon bağımlılık yolları `/opt/homebrew` altındadır.

1. Sunucu bilgilerini girip **Bağlantıyı Test Et ve Listele** ile erişilebilir veritabanlarını alın.
2. Görünecek veritabanlarını seçin, yıldızla varsayılanı belirleyip **Bağlan** kullanın. Görünürlük seçimi sunucu yetkilerini değiştirmez.
3. Sorguyu F5 / ⌘Return ile çalıştırın; seçim varsa yalnız seçim gönderilir. ⌘. iptal eder; iptal transaction rollback değildir.
4. Ctrl+Space önerileri açar; Tab/Enter kabul eder. Ctrl+F / ⌘F seçili metinle bulmayı, ⌘⇧F biçimlendirmeyi açar.
5. Nesne/Agent tasarım ekranları değişiklikleri önce SQL olarak incelemeye açar. Nesne önizlemesindeki **Veritabanına Gönder** ve Agent komut penceresinin açık onayı ayrıca yürütme yapar.

Bağlantı ekranında Genel/Gelişmiş seçenekleri ve tek ana işlem kullanılır. Explorer’da **Nesneleri Yenile** sunucudaki yüklenmiş nesne listelerini yeniden okur; **Yerel İndeksi Yenile** arama/tamamlama önbelleğini yeniler. İndeks ayrıntıları veritabanı adının yanındaki düğmeden açılır.

Ayarlar (⌘,) altı sekmede tema, editör, kısayollar, yerel kayıt, güncelleme kaynağı ve Keychain erişimini yönetir. v0.2.52 ile yeni güncelleme akışı, uygulama menüsündeki **Güncellemeleri Kontrol Et** ile PKG indirip içindeki uygulamanın sabit imzasını doğrular ve macOS Kurulum ekranını açar. Kurulumu tamamlayıp uygulamayı Uygulamalar’dan yeniden açın; önceki sürüm yedeği oluşturulmaz. **Hakkında** ekranındaki sürüm notları çevrimdışı okunabilir.

## Kapsam ve sınırlar

- DDL indeksli T-SQL editörü, blok katlama, ortak SQL renkleri, kullanılmayan DECLARE vurgusu; disk destekli salt okunur sonuç grid'i, filtre/sıralama/sayfalama ve CSV/JSON dışa aktarma.
- Tablo/view/index/constraint/trigger/routine/synonym ve izin scriptleri, sınırlı ayrı veri editörü; SQL Agent özellikleri, T-SQL adımları, zamanlamalar, geçmiş ve Activity Monitor.
- Linked Server sağlayıcısının sunduğu katalog/table rowset nesneleri ve kolonları; uzak tasarım/rutin yönetimi yoktur.
- İsteğe bağlı yerel geçmiş/oturum kurtarma, JSON SQL şablonları ve AI paneli. AI yanıtı otomatik çalıştırılmaz; anahtar yalnız panel belleğinde tutulur.

Tam SSMS/DataGrip eşdeğerliği, eksiksiz T-SQL parser, grafik plan/JOIN diyagramı, serbest docking veya otomatik tablo rebuild yoktur. Filtreler yalnız yüklenen sonuçlara uygulanır. Varsayılan okuma bütçesi 50.000 satır/64 MB/60 sn; büyük modlar da sınırlıdır ve partial sonucu açıkça bildirir.

Yayınlar sabit **kişisel self-signed sertifika** kullanır; Apple Developer ID/notarization değildir. PKG kapsayıcısında Developer ID Installer imzası yoktur. v0.2.69’dan itibaren parolalara güncellemelerde değişmeyen imzalı bir bileşen erişir. Eski kayıtların ilk geçişinde macOS onay isterse **Her Zaman İzin Ver**’i seçin. Keychain sürekliliği, Gatekeeper onayı ve kilitli Keychain davranışı ayrı konulardır; tüm parola istemlerinin kesin ortadan kalktığı iddia edilmez. Ayrıntılar [geliştirme rehberindedir](AGENTS.md#keychain-kalıcı-imza-ve-güncelleme).

## Derleme ve test

Xcode projesi `MSSQLStudio.xcodeproj`; core paket `SQLServerKit` ve uygulama SwiftPM hedefi `MSSQLStudio`'dur.

```sh
./scripts/test.sh
xcodebuild -project MSSQLStudio.xcodeproj -scheme MSSQLStudio -configuration Release -derivedDataPath /tmp/MSSQLStudio-check CODE_SIGNING_ALLOWED=NO build
```

Bu yerel build imzasızdır; kurulu uygulamanın yerine koymayın. İmzalı paket için `./scripts/build-app.sh /tmp/MSSQLStudio-release` sabit sertifikanın kullanılabilir olmasını gerektirir; yoksa hata verir. GitHub Actions aynı sertifikayı secrets üzerinden kullanır. [Yayın adımları](AGENTS.md#geliştirme-doğrulama-ve-yayın-akışı) rehberde yer alır.

## Proje belgeleri

- [AGENTS.md](AGENTS.md): mimari, kaynak haritası, güncel geliştirme durumu, görünüm/etkileşim ve güvenli yayın kuralları.
- [TEST-REPORT.md](TEST-REPORT.md): tarihli test/yayın kanıtları ve doğrulanmamış koşullar. Son hizalama turunun kapsamlı görsel kontrolü arayüz test aracı bağlantısı nedeniyle tamamlanmadı.
- [ReleaseNotes.json](Sources/SQLServerKit/Resources/ReleaseNotes.json): uygulama ve GitHub için ortak sürüm notları.

Eski mimari/tasarım/imzalama belgeleri AGENTS.md içinde birleştirildi; önceki içerikler Git geçmişinde korunur.
