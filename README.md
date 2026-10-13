# MSSQL Studio

SQL Server için native macOS çalışma alanı. Solda Object Explorer, ortada SQL editörü ve bağımsız sorgu sekmeleri, altta sonuçlar/mesajlar/plan ağacı bulunur. macOS 27+, Apple Silicon, Swift 6, AppKit/SwiftUI ve TextKit 2 kullanır.

## Kurulum ve başlangıç

[Son GitHub yayınından](https://github.com/erhanulas/MSSQLStudio/releases/latest) PKG'yi indirip uygulama kapalıyken kurun. Hedef `/Applications/MSSQLStudio.app` konumudur. Güncel yayın için GitHub Releases sayfasını ve uygulamanın Hakkında ekranını kullanın.

Microsoft ODBC Driver 18, unixODBC ve OpenSSL 3 ayrı kurulur; sürücüler app paketinde dağıtılmaz. [Microsoft macOS kurulum yönergesi](https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/install-microsoft-odbc-driver-sql-server-macos) kullanılabilir. Apple Silicon bağımlılık yolları `/opt/homebrew` altındadır. Bağlantı ekranı Driver 18 durumunu ve sürümünü otomatik denetler; eksikse **Kur…** ile lisans/kaynak onayından sonra Homebrew kurulumunu başlatabilirsiniz. Homebrew yoksa resmî kurulum yönergesi açılır; yönetici yetkisi otomatik alınmaz.

1. Sunucu bilgilerini girip **Test Et ve Yükle** ile erişilebilir veritabanlarını alın.
2. Görünecek veritabanlarını seçin, yıldızla varsayılanı belirleyip **Bağlan** kullanın. Görünürlük seçimi sunucu yetkilerini değiştirmez.
3. Sorguyu F5 / ⌘Return ile çalıştırın; seçim varsa yalnız seçim gönderilir. ⌘. iptal eder; iptal transaction rollback değildir.
4. Ctrl+Space önerileri açar; Tab/Enter kabul eder. Ctrl+F / ⌘F seçili metinle bulmayı, ⌘⇧F seçili SQL’i veya seçim yoksa tüm editörü biçimlendirmeyi açar. Girinti, harf biçimi, virgül, satır kırma ve satır genişliği tercihleri Ayarlar → SQL Editörü içindedir.
5. Nesne/Agent tasarım ekranları değişiklikleri önce SQL olarak incelemeye açar. Nesne önizlemesindeki **Veritabanına Gönder** ve Agent komut penceresinin açık onayı ayrıca yürütme yapar.

Bağlantılar ekranındaki seçiciden yeni veya mevcut Explorer profilini açabilirsiniz. Genel/Gelişmiş seçenekleri korunur; test/liste yükleme tek eylemdir, mevcut profil çevrimdışı kaydedilebilir. Explorer’da **Nesneleri Yenile** sunucudaki yüklenmiş nesne listelerini yeniden okur; **Yerel İndeksi Yenile** arama/tamamlama önbelleğini yeniler. İndeks ayrıntıları veritabanı adının yanındaki düğmeden açılır.

Ayarlar (⌘,) altı sekmede tema, editör, kısayollar, yerel kayıt, güncelleme kaynağı ve Keychain erişimini yönetir. v0.2.52 ile yeni güncelleme akışı, uygulama menüsündeki **Güncellemeleri Kontrol Et** ile PKG indirip içindeki uygulamanın sabit imzasını doğrular ve macOS Kurulum ekranını açar. Kurulumu tamamlayıp uygulamayı Uygulamalar’dan yeniden açın; önceki sürüm yedeği oluşturulmaz. **Hakkında** ekranındaki sürüm notları çevrimdışı okunabilir.

## Kapsam ve sınırlar

Editörde tanımlanmamış `@parametreler` kırmızı görünür. Seçili satırlarda `⌘/` yorum yapar/kaldırır; `⌥⌘/` yalnız yorumu kaldırır. Tam satır veya çok satırlı seçimin yanındaki küçük simge aynı işlemi sunar; kelime/boşluk seçiminde açılmaz; kısayollar Ayarlar’dan değiştirilebilir. Ayarlar’ın üstündeki arama tüm sekmelerdeki seçenekleri bulup ilgili ayara götürür.

Açık kolon listeli `INSERT ... VALUES` içinde kolona veya değere bir kez tıklamak karşılığını vurgular; küçük önizleme kolon adını ve sırasını gösterir. Kolon tıklaması çoklu VALUES satırlarını da eşler. Escape önizlemeyi kapatır; SQL metni değiştirilmez.

Türkçe Q klavyede `/` için `⇧7` kullanıldığından yorum aç/kapat `⌘⇧7`, yalnız yorum kaldırma `⌥⌘⇧7` ile de çalışır.

DDL tamamlama `SELECT dbo.fonksiyon(...)`, `SELECT ... FROM tablo/view/tablo_döndüren_fonksiyon(...)` ve `EXEC prosedür` bağlamlarını ayırır. Fonksiyon kabulünde eksik çağrı parantezleri eklenir ve imleç argüman alanına gelir; mevcut parantezler korunur.

- DDL indeksli T-SQL editörü, blok katlama, ortak SQL renkleri, kullanılmayan DECLARE vurgusu; disk destekli salt okunur sonuç grid'i, filtre/sıralama/sayfalama ve CSV/JSON dışa aktarma.
- Tablo/view/index/constraint/trigger/routine/synonym ve izin scriptleri, sınırlı ayrı veri editörü; SQL Agent özellikleri, T-SQL adımları, zamanlamalar, geçmiş ve Activity Monitor.
- Linked Server sağlayıcısının sunduğu katalog/table rowset nesneleri ve kolonları; uzak tasarım/rutin yönetimi yoktur.
- İsteğe bağlı yerel geçmiş/oturum kurtarma, JSON SQL şablonları ve AI paneli. AI yanıtı otomatik çalıştırılmaz; anahtar yalnız panel belleğinde tutulur.

Tam SSMS/DataGrip eşdeğerliği, eksiksiz T-SQL parser, grafik plan/JOIN diyagramı, serbest docking veya otomatik tablo rebuild yoktur. Filtreler yalnız yüklenen sonuçlara uygulanır. Varsayılan okuma bütçesi 50.000 satır/64 MB/60 sn; büyük modlar da sınırlıdır ve partial sonucu açıkça bildirir.

Yayınlar sabit **kişisel self-signed sertifika** kullanır; Apple Developer ID/notarization değildir. PKG kapsayıcısında Developer ID Installer imzası yoktur. v0.2.69’dan itibaren parolalara güncellemelerde değişmeyen imzalı bir bileşen erişir. Eski kayıtların ilk geçişinde macOS onay isterse **Her Zaman İzin Ver**’i seçin. Keychain sürekliliği, Gatekeeper onayı ve kilitli Keychain davranışı ayrı konulardır; tüm parola istemlerinin kesin ortadan kalktığı iddia edilmez. Ayrıntılar [geliştirme rehberindedir](AGENTS.md#keychain-kalıcı-imza-ve-güncelleme).

## Derleme ve test

Xcode projesi `MSSQLStudio.xcodeproj`; uygulama hedefi `MSSQLStudio`, veritabanı/core hedefi `SQLServerKit`, bağımsız SQL metin hedefi `SQLTextCore`'dur. Kaynaklar özellik klasörlerine ayrılmıştır; sorumluluk ve sahiplik haritası [geliştirme rehberindedir](AGENTS.md#platform-ve-kaynak-haritası).

```sh
python3 scripts/check-architecture.py
./scripts/test.sh
xcodebuild -project MSSQLStudio.xcodeproj -scheme MSSQLStudio -configuration Release -derivedDataPath /tmp/MSSQLStudio-check CODE_SIGNING_ALLOWED=NO build
```

Bu yerel build imzasızdır; kurulu uygulamanın yerine koymayın. İmzalı paket için `./scripts/build-app.sh /tmp/MSSQLStudio-release` sabit sertifikanın kullanılabilir olmasını gerektirir; yoksa hata verir. GitHub Actions aynı sertifikayı secrets üzerinden kullanır. [Yayın adımları](AGENTS.md#geliştirme-doğrulama-ve-yayın-akışı) rehberde yer alır.

## Proje belgeleri

- [AGENTS.md](AGENTS.md): mimari, kaynak haritası, güncel geliştirme durumu, görünüm/etkileşim ve güvenli yayın kuralları.
- [TEST-REPORT.md](TEST-REPORT.md): tarihli test/yayın kanıtları ve doğrulanmamış koşullar. Son hizalama turunun kapsamlı görsel kontrolü arayüz test aracı bağlantısı nedeniyle tamamlanmadı.
- [ReleaseNotes.json](Sources/SQLServerKit/Resources/ReleaseNotes.json): uygulama ve GitHub için ortak sürüm notları.

Eski mimari/tasarım/imzalama belgeleri AGENTS.md içinde birleştirildi; önceki içerikler Git geçmişinde korunur.

Bağlantı ayarlarının **Gelişmiş** bölümündeki **CREATE / ALTER tanımlarını indeksle** seçeneği, seçili veritabanlarının nesne kodlarını bu Mac’te saklar (varsayılan kapalı). Bağlıyken tanım daima sunucudan okunur ve indeks güncellenir. Explorer bağlantısı kapalıyken nesneye çift tıklayarak son indekslenmiş tanımı tarih bilgisiyle salt okunur görebilirsiniz. Seçeneği kapatmak tanım indeksini; Explorer’dan kaldırmak bağlantının yerel indekslerini temizler. Kod içinde kelime araması sonraki aşamadır.

Tanım indeksi kotası varsayılan **1 GB**’tır. **Ayarlar → Çalışma Alanı → Nesne tanım indeksi** altında 128 MB–64 GB arasında değiştirip Uygula ile kaydedebilirsiniz. Ayarlar başlığı kullanılan alanı ve doluluk yüzdesini gösterir. Kota tüm bağlantılar için ortaktır; dolduğunda en eski tanımlar temizlenir. Ölçüm tanım verisidir, SQLite dosya/WAL ve diğer katalog alanlarını kapsamaz.
