# MSSQL Studio — native SQL Server çalışma alanı

Önceki NativeSQL uygulamasından bağımsız, sıfırdan yazılmış yeni proje. SSMS düzenini kullanır: solda Object Explorer, ortada bağımsız SQL oturumlarına sahip sorgu sekmeleri, altta Results / Messages / Execution Plan. macOS 27+, Apple Silicon, Swift 6, AppKit + SwiftUI ve TextKit 2; veritabanı katmanı Microsoft ODBC Driver 18.

## Başlatma

**0.2.39 — fark önizlemesi ve veritabanına gönderme:** Farkları Gör ikonu karşılıklı oklarla gösterilir; nesne sekmelerinde yanında Veritabanına Gönder ikonu bulunur. İkisi de yan yana farklar / çalıştırılacak SQL önizlemesini açar. Önizleme ana SQL editörünün syntax ve kullanılmayan DECLARE renklerini paylaşır; multiline yorumlar ve string'ler tam kaynak üzerinden renklendirilir. Pencere 1400×840 hedef boyutuyla, ekranın görünür alanına göre açılır ve yeniden boyutlandırılabilir. Uzun satırlar yatay kaydırılır; açılışta satır başı korunur. Bağlı ve hazır nesne sekmesinde bekleyen değişiklik varsa, açık transaction yoksa Veritabanına Gönder etkinleşir. Son düğmeye basıldığında sunucudaki tanım açılan ham tanımla yeniden karşılaştırılır; çakışmada gönderme durur. Kontrol esnasında yinelenen gönderme engellenir; uygulama başarılı olursa baseline ilerler. Bu bir GitHub publish işlemi değildir.

**0.2.39 — kullanılmayan DECLARE değişkenleri:** `DECLARE @ad` tanımında, aynı SQL Server batch'inde başka lexical kullanımı bulunmayan ad soluk gri gösterilir. Yorumlar, string'ler ve köşeli parantezli isimler kullanım sayılmaz; harf büyüklüğü göz ardı edilir. Çoklu DECLARE, tablo değişkenleri ve `GO` ayrımı desteklenir. Katlanmış kodun kaynak metni de hesaba katılır. Kullanım eklenince normal renk geri gelir. Bu özellik procedure/fonksiyon gövdesindeki yerel DECLARE değişkenleri içindir; rutin başlığındaki parametreleri veya yalnızca yazılan ama okunmayan değerleri denetlemez. Analiz 250.000 UTF-16 birimine kadar çalışır, bağlantı gerektirmez.

**SQL editörü (0.2.36):** IF/BEGIN bloklarını açıp kapatırken başlık ekrandaki yerini korur. Katlanmış blokta + düğmesi dolu vurgu rengiyle görünür; blok açılınca − düğmesi normal renge döner. Kalıcı yan çizgi gösterilmez. Katlanmış bloğun açıklaması gizlenen satır sayısını gösterir. Dosyanın sonunda kaydırma payı vardır; büyük bir blok kapatılınca görünüm yukarı sıçramaz. Tüm blokları açma görünür kaynak satırını, katlama yatay kaydırma konumunu korur. Kelime eşleşmeleri metin özelliklerini değiştirmeyen, fare olaylarını engellemeyen ayrı bir çizim katmanında gösterilir; seçili kelime native seçim rengini korur.

**SQL editörü (0.2.33–0.2.34):** Nesne düzenleme sekmesindeki **Farkları Gör** artık yan yana iki panel simgesidir; üzerine gelince adı görünür ve erişilebilirlik etiketi korunur. Editör araç çubuğundaki **DB’ye Uygula…** düğmesi kaldırıldı. Fark penceresi karşılaştırma amaçlıdır; SQL çalıştırmak için mevcut sorgu çalıştırma komutları kullanılır. Metin eşleşmesi vurguları yalnızca değişiklik olduğunda yeniden çizilir.

`releases/MSSQLStudio-0.2.39.pkg` kurulum paketini açın. Açık sorgularınızı kaydedip uygulamayı kapatın; paket ana `/Applications/MSSQLStudio.app` konumuna kurar/günceller. Bu Mac'te gereken unixODBC, Microsoft ODBC 18 ve OpenSSL 3 kurulu. Uygulama bu yerel kurulumları kullanır; sürücüyü paket içinde dağıtmaz. Başka bir Mac için [Microsoft'un macOS kurulum yönergesini](https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/install-microsoft-odbc-driver-sql-server-macos) izleyin ve `/opt/homebrew/opt/openssl@3/lib` yolunu sağlayın.

1. Sunucu ve parolayı girip **Bağlantıyı Test Et ve Listele** düğmesine basın; yerel test adresi `localhost`, port `1433`. Başarılı testten sonra erişebildiğiniz veritabanları otomatik yüklenir. Görmek istediklerinizi işaretleyip yeni sorguların varsayılanını satırdaki yıldızla belirleyin; ardından **Bağlan** düğmesine basın. Yeni bağlantıda hiçbiri otomatik seçilmez; en az bir seçim gerekir. Parola kaynak kodunda veya örneklerde yoktur.
2. Yerel kendinden imzalı sertifika için onaylanan **Trust server certificate** seçeneği kullanılabilir. Şifreleme her zaman açık; bu seçenek yeni bağlantılarda varsayılan olarak kapalı.
3. `Examples/Workspace.sql` dosyasını açın. F5 veya ⌘Return ile tüm metni, seçili metin varsa yalnızca seçimi çalıştırın. ⌘. sorguyu iptal eder. GO / GO n desteklenir.
4. Yazarken DDL önerileri açılır; Control+Space ile elle açın, Tab/Enter ile kabul edin, Escape ile kapatın. Ctrl+F / ⌘F seçili metinle bulma çubuğunu açar; ⌘⇧F SQL'i biçimlendirir.
5. Object Explorer ve üstteki seçici yalnızca seçtiğiniz veritabanlarını gösterir. Sunucu veya Databases üzerinde sağ tık → **Bağlantı ayarları** ile seçimi değiştirin. Açık sorgular kendi veritabanlarını korur; bu nedenle açık sekmenin mevcut veritabanı seçicide görünmeye devam edebilir. Veritabanını üstteki seçiciden değiştirin. Tablonun sağ menüsünden SELECT / INSERT / UPDATE / DELETE scriptleri, özellikler ve indeks tasarımını açın.
6. Görünüm menüsünden sorguyu ayrı pencereye taşıyın; aynı oturum, sorgu, sonuçlar ve transaction korunur. Pencere kapanınca sorgu ana çalışma alanına döner.

## Kalıcı kişisel imza (0.2.32)

Yayın uygulaması **MSSQL Studio Personal Signing** sertifikasıyla imzalanır. Bu kişisel, self-signed bir code-signing kimliğidir; Apple Developer ID, noter onayı veya Apple Gatekeeper dağıtım onayı değildir. PKG kapsayıcısının Developer ID Installer imzası yoktur; içindeki uygulama kişisel sertifikayla imzalıdır. Xcode'un geçici ara çıktısından sonra build-app.sh kalıcı imzayı uygular. Geçici/ad-hoc veya farklı sertifikalı yayın paketleri build-pkg / prepare-release tarafından reddedilir.

Tek açık kimlik kaydı `Sources/SQLServerKit/Resources/SigningIdentity.json`: bundle ID + sertifika parmak izi. Kalıcı designated requirement bu ikisine bağlıdır; binary hash'ine bağlı değildir. 0.2.32 ve sonrasındaki uygulama içi güncelleme de aynı sertifika ve gereksinimi denetler. Farklı bir yayın deposu seçmek bu imza kısıtlamasını kaldırmaz. Sertifika kaybedilirse veya değiştirilirse eski uygulama yeni kimliği otomatik kabul etmez; elle kurulum/geçiş gerekir.

Özel anahtar ve parolalar kaynakta bulunmaz. Yerel özel anahtar login Keychain'e aktarıldı; şifreli yerel P12/PEM yedekleri proje deposu dışında, yalnızca bu kullanıcıya açık dosya izinleriyle saklanır. Yedek parolası `local.mssqlstudio.signing-backup` Keychain kaydındadır, düz metin parola dosyası tutulmaz. GitHub deposundaki `MSSQL_SIGNING_P12` ve `MSSQL_SIGNING_PASSWORD` Actions Secrets yeni yayınlarda aynı kimliği sağlar. CI kimliği yalnızca geçici keychain'e aktarır ve iş sonunda siler. Özel anahtarı ya da bu Secrets değerlerini Git'e / issue'ya / sohbete koymayın. Depoya workflow yazabilen kişiler imzalama Secrets'ını kullanabileceğinden depo yazma erişimi güvenilen kişilerle sınırlı olmalıdır. Eksik Secrets durumunda ad-hoc yayına geri dönüş yoktur.

**Keychain sınırı:** Kullanıcı bu aşamada yalnızca imzalamayı istedi; mevcut bağlantı kayıtlarının erişim kuralları değiştirilmedi. Gerçek login keychain'deki yalıtılmış kayıt testi, sabit imzaya rağmen ek yetkilendirme isteyebildi. İzin istemlerinin her güncellemede tamamen kalktığı iddia edilmez. İleride yalnızca uygulama kayıtları için ayrı, kullanıcı onaylı erişim kuralı geçişi gerekebilir. Geçici boş test keychain'inde iki farklı derleme aynı kimlikle erişti; bu sonuç gerçek login keychain davranışıyla eş tutulmaz.

## Hakkında ve sürüm değişiklikleri (0.2.31)

**MSSQL Studio → MSSQL Studio Hakkında** menüsü kurulu bundle'ın gerçek sürümünü ve derleme numarasını gösterir. Sol listeden sürüm seçildiğinde o sürümün tarih, başlık ve değişiklikleri okunur; kurulu sürüm ayrıca işaretlidir. Son beş sürümün notları uygulamayla birlikte gelir ve internet gerekmez. GitHub Yayınları bağlantısı tüm uzak yayınları açar; Güncellemeleri Kontrol Et düğmesi mevcut güncelleme akışını kullanır. SQL oturumu veya Keychain erişimi gerekmez. Açık Hakkında penceresine tekrar menüden gidilirse aynı pencere öne gelir.

Notların tek kaynağı `Sources/SQLServerKit/Resources/ReleaseNotes.json` dosyasıdır. Yeni sürüm için en üste version/date/title/changes kaydı ekleyin ve Xcode sürümünü yükseltin. JSON uygulamaya paketlenir. Yayın hazırlığı en üst kaydın tag ile eşleşmesini ve ZIP/PKG notlarının aynı olmasını zorunlu tutar; aynı kayıttan GitHub yayın açıklaması üretilir. Uygulama notları ağdan çalıştırılabilir içerik olarak almaz. Bundle sürümü hiçbir zaman notların en yeni kaydından türetilmez. Geçmiş eksik/bozuksa sürüm görünmeye devam eder ve hata metni gösterilir.

## GitHub üzerinden güncellemeler (0.2.30)

Yayın deposu [erhanulas/MSSQLStudio](https://github.com/erhanulas/MSSQLStudio); [ilk GitHub sürümü 0.2.30](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.30) ZIP ve PKG ile yayımlandı. Otomatik yayın akışı ve herkese açık adresten gerçek indirme/doğrulama testi geçti. Uygulamanın varsayılan kaynağı bu deponun son yayımlanmış sürümündeki `update.json` dosyasıdır. Ayarlar → GitHub güncellemeleri alanı alternatif herkese açık bir depo için kullanılabilir; boş bırakmak yerleşik adresi kullanır. Uygulama GitHub oturumu veya erişim anahtarı istemez; bağlantılar, parolalar, sorgular ve sonuçlar yayımlanmaz.

**İlk geçiş:** 0.2.30 PKG'yi bir kez kurun; eski sürümler bu GitHub adresini içermez. Sonrasında MSSQL Studio → **Güncellemeleri Kontrol Et** komutunu kullanın. Yeni sürüm bulunduğunda ZIP indirilir; SHA-256, uygulama imzası, bundle kimliği ve sürüm doğrulanır. Kullanıcı onayı ve açık çalışma denetiminden sonra uygulama kapanıp aynı konumda yenisiyle değiştirilir. Önceki uygulama `.previous` olarak saklanır. Bağlantı kayıtları ve Keychain kimlikleri aynı kalır. Kurulum konumuna yazma izni yoksa hazırlama hata verir; yükseltilmiş yetki otomatik alınmaz. Geçici/ZIP konumundan çalıştırmayın, PKG ile /Applications'a kurun.

### Yeni sürüm yayımlama

1. Xcode projesindeki iki `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` değerini yükseltin. `ReleaseNotes.json` dosyasının en üstüne yeni sürümün değişikliklerini ekleyin; testleri çalıştırıp değişiklikleri `main` dalına gönderin.
2. Aynı sürümle etiket oluşturup gönderin, örneğin `git tag v0.2.32` ve `git push origin v0.2.32`.
3. `.github/workflows/release.yml`, macOS 27 / Apple Silicon runner'ında uygulamayı ve PKG'yi üretir. ZIP/PKG imzası, bundle, sürüm ve depo eşleşmesini denetler, testleri çalıştırır, SHA-256 içeren manifesti üretir. Üç varlık da taslak yayına yüklendikten sonra yayını Latest olarak açar. Tag ile Xcode sürümü uyuşmazsa yayın oluşturulmaz. Aynı sürüm yeniden yayımlanmaz.

İlk yayın henüz oluşturulmamışsa kontrol hata mesajı verir; bu durum "güncelsiniz" sayılmaz. GitHub Actions'ın depo için etkin olması gerekir. Workflow yalnızca yayın işi için `contents: write` ister; kullanıcı token'ı kaynakta veya uygulamada bulunmaz. Runner `xcode-27` public preview olduğundan kullanılabilirliği GitHub'a bağlıdır. 0.2.30/31 paketleri ad-hoc imzalıdır; 0.2.32 kalıcı kişisel sertifika kullanır. Developer ID / noter onayı yoktur. SHA-256 indirme bütünlüğünü denetler; Apple yayıncı kimliği güvencesi sağlamaz. ODBC 18 / unixODBC / OpenSSL bağımlılıkları ayrı kurulur.

## Dar Object Explorer (0.2.29)

Object Explorer ayırıcısını sola sürüklemek paneli gizlemez. Pencere daralırken de otomatik kapanmaz; gizlemek için paneldeki veya editör üzerindeki gizleme düğmesini kullanın. Panel yaklaşık **140 punto** genişliğe kadar daralır; önceki görünümün fiilî alt sınırı yaklaşık 251 puntoydu. Arama kapsamı/operatör/tür seçicileri ve açıklamalar genişliği zorlamak yerine kısalır. Uzun nesne adları için ağacın yatay kaydırması korunur. Son genişlik gizle/göster ve uygulamayı yeniden açma sonrasında korunur.

## Uygulamalar klasörü düzeltmesi (0.2.28)

Kurulum hedefi kişisel ~/Applications yerine Mac'in ana **/Applications** klasörüdür. Finder → Uygulamalar içinde MSSQLStudio görünür. Installer yalnızca sistem diskini hedefler; yönetici doğrulaması isteyebilir. Relocation kapalıdır, uygulama bundle kimliği değişmediği için bağlantılar/Keychain/tercihler korunur. Bu Mac'teki mevcut kişisel kurulum, çalışmıyorken imzası doğrulanıp ana klasöre taşındı ve macOS'e yeniden kaydedildi; ikinci uygulama kopyası bırakılmadı. Yeni PKG sonraki sürümleri aynı ana konuma kurar. Diğer Mac'lerde eski kişisel uygulama kopyaları otomatik silinmez.

## Çalışma alanı ve nesne değişiklikleri (0.2.27)

- Object Explorer ile editör arasındaki ayırıcıyı sürükleyerek genişliği değiştirin. Genişlik ve gizle/göster tercihi sonraki açılışta korunur.
- Sekme sağ menüsündeki **Close All Tabs** sabitlenenler dahil tüm sekmeleri kapatır. Uyarı, açılan/oluşturulan SQL'den gerçekten farklı metin veya veritabanına uygulanmamış nesne düzenlemesi varsa çıkar. İlk metne geri dönmek uyarıyı kaldırır. Dosyaya kaydetme ile veritabanına uygulama ayrı takip edilir; açık transaction ve çalışan sorgu korumaları devam eder. Toplu kapatmada Vazgeç kalan sekmeleri korur; daha önce kapanmış temiz sekmeleri geri açmaz.
- Aynı bağlantı, veritabanı ve object ID için Modify/ALTER/CREATE açmak mevcut nesne sekmesine döner; yazdığınız kodu yeniden yükleyip değiştirmez. Farklı bağlantı/veritabanları ayrı kalır. Clipboard/File hedefleri script üretmeye devam eder.
- **Farkları Gör** / **DB’ye Uygula…**: yan yana eski/yeni kaynak, hizalı satır numaraları, kırmızı/yeşil satır ve değişen metin vurgusu, birlikte dikey kaydırma ve ayrı çalıştırılacak SQL görünümü. Önizleme ilk farka gider. Uygula yalnızca incelenen SQL anlık görüntüsünü gönderir; editörde seçili parçayla sınırlanmaz. Sunucu tanımı açılıştan beri değişmişse gönderim engellenir. Kontrol ve DDL yürütmesi atomik değildir; üç yönlü birleştirme yoktur. Bu akış kaynak tanımı olan view/procedure/function/trigger nesneleri içindir; table designer SQL'i sorgu sekmesinde inceletir.
- Karşılaştırma arka planda yapılır; büyük değişiklikler sınırlı blok karşılaştırmasına döner. 1 milyon UTF-16 birimini veya 10.000 karşılaştırma satırını aşan tanımlar kısmi önizleme olarak açıkça işaretlenir; bu ekrandan uygulanamaz, tam SQL sorgu sekmesindedir.

## SQL Server Agent (0.2.27)

- **Jobs sağ menüsü:** View History, Start Job, Stop Job, Enable/Disable, Delete Job, Properties. Çalışmayan işte Stop pasiftir. Disabled işi başlatmak ile zamanlanmış çalışmayı etkinleştirmek ayrı işlemlerdir. İşlem penceresi hedef işi ve gönderilecek SQL'i gösterir; yalnızca açık Uygula/İşi Sil komutu yürütür. Alternatif olarak SQL sorgu sekmesine aktarılır. Delete paylaşılan/kullanılmayan schedule kayıtlarını otomatik silmez.
- **History:** son 500 kayıt; tarih aralığı, durum ve adım filtresi, Yenile, seçilen kaydın ayrıntılı mesajı. Saatler SQL Server'ın yerel saatidir. Geçmiş temizlenmez.
- **Properties:** ad/açıklama/Enabled, owner/durum/son değişiklik, mevcut T-SQL adımlarının ad/veritabanı/komut düzenlemesi ve bağlı zamanlamalar. Değişiklikler önce SQL sekmesine aktarılır. CmdExec/PowerShell gibi subsystem düzenlemesi yoktur.
- **Job Activity Monitor:** en çok 1.000 işin etkinlik durumu ve Agent servisinin salt okunur durumu; elle yenileme ve History. **Schedules → Properties / Enable / Disable** paylaşılan zamanlama için incelemeye hazır SQL üretir. Başarılı Agent komutlarından sonra yüklenmiş Explorer klasörleri yenilenir.
- Agent/msdb/DMV izin hataları görünürdür. Start isteğinin kabulü işin başarıyla tamamlandığı anlamına gelmez. Servis başlatma/durdurma, ayrıntılı takvim tasarımcısı, Alerts/Operators/Proxies yönetimi ve tam SSMS Agent eşdeğerliği bu sürümde yoktur.

Davranış araştırması: DataGrip'in [nesne kaynak kodu ve migration önizlemesi](https://www.jetbrains.com/help/datagrip/update-source-code-of-database-objects.html), [kaydetme davranışı](https://www.jetbrains.com/help/datagrip/saving-and-reverting-changes.html); SSMS'in [iş etkinleştirme/devre dışı bırakma](https://learn.microsoft.com/en-us/ssms/agent/disable-or-enable-a-job), [iş geçmişi](https://learn.microsoft.com/en-us/ssms/agent/view-the-job-history) ve [SQL Server Agent kapsamı](https://learn.microsoft.com/en-us/ssms/agent/sql-server-agent). Bu uygulama kendi dosya kaydetme uyarılarını korur; DataGrip'in otomatik kaydetmesini aynen uygulamaz.

## Değişken seçimi, bulma ve yeni sorgu odağı (0.2.26)

- SQL değişkenine çift tıklayınca `@STOK_KODU` bütünüyle seçilir. `@@ROWCOUNT`, `#Temp`, alt çizgi ve Türkçe harfler de korunur. AppKit'in fare takibi sonrasında bıraktığı tek kelimelik seçim SQL sınırlarına tamamlanır; boşluk veya noktalama içeren çok kelimeli seçim genişletilmez. SQL metni ve undo geçmişi değişmez.
- **Ctrl+F ve ⌘F**, seçili metin varsa yerel Bul çubuğunu o metinle açar; seçim yoksa önceki arama korunur. Ctrl+F başka bir özelleştirilebilir komuta atanamaz. AppKit'in [setSearchString](https://developer.apple.com/documentation/appkit/nstextfinder/action/setsearchstring) işlemi kullanılır.
- **Ayarlar → SQL editörü → Öneri gecikmesi**: 50–1.000 ms arası 10 ms adımlı ayar; varsayılan **260 ms**. Uygula ile kaydedilir, yeniden açılışta korunur. Varsayılan düğmesi 260 ms'ye döndürür. Ctrl+Space bu beklemeyi atlar. Mevcut iptal/güncellik denetimi ve arka planda analiz korunur; bu ayar sunucu/DDL indeksinin hazır olma süresi garantisi değildir.
- Yeni sorgu sekmesi açılınca odak editöre geçer. Bağlantı/sonuç güncellemeleri mevcut sekmede yazma veya arama odağını tekrar ele geçirmez; hızlı açılan sekmelerde eski sekmeye ait bekleyen odak işlemi uygulanmaz. Yeni sorgu kısayolu varsayılan ⌘N'dir ve mevcut ayarlar ekranından değiştirilebilir.

## Kolon seçimi ve editör etkileşimleri (0.2.25)

Table Designer'daki kolon açılır listesi kaldırıldı. Satırın sol seçicisi veya ad/tip/default alanına tıklayarak doğrudan kolon seçilir; seçili satır mavi zemin, kenar çizgisi ve ok ile belirtilir. Satır seçicisi yazma odağını o kolonun adına taşır. Üst çubuk seçilen adı gösterir; ekleme/kaldırma düğmeleri sabit kalır. Yeni kolon NewColumn, NewColumn2… şeklinde çakışmasız ad alır ve uzun listede otomatik görünür alana kayar. Kaldırma önce taslağı değiştirir; SQL'i inceleyip çalıştırmadan DB değişmez.

SQL editöründe **çift tık kelimeyi seçer**; nesneye gitme **⌘B / ⌘tık / sağ tık → Nesne Tanımına Git** ile yapılır. Alt çizgi, @/#/$ ve Türkçe karakterler kelime içinde kalır; noktalama başka statement'ları seçime katmaz. Emoji seçimi UTF-16 surrogate çiftini bölmez. Seçilen metnin diğer kullanımları sarı, gerçek seçim native seçim rengiyle görünür. Klavye/AX seçim boyaması 90 ms bekler, eski isteği iptal eder ve seçim/metin güncelliğini kontrol eder. Fareyle seçimde boyama mouse-up sonrasına bırakılır; fare seçim işlemi sırasında storage boyaması yapılmaz. SQL metni, seçim aralığı ve undo geçmişi korunur. Mevcut 250.000 UTF-16 / 256 karakter seçim / 500 eşleşme sınırları sürer.

Katlama alanında **− açık**, **+ kapalı** kutu anlamına gelir. Katlanmış metin gölgeli **…** ile görünür; üzerinde gizli kod önizlemesi vardır. … üzerine çift tık veya + düğmesi bloğu açar. BEGIN'den hemen önceki satır IF/ELSE ise koşul/dal başlık olarak görünür kalır; diğer BEGIN/TRY/CATCH blokları kendi başlıklarını korur. Tıklanan başlığın ekrandaki konumu korunur, placeholder açılınca bütün gizli blok yanlışlıkla seçilmez. İç içe blokların durumları korunur; aynı SQL'in host tarafından tekrar senkronize edilmesi açık/kapalı durumunu sıfırlamaz. ⌥⌘[ imlecin bloğunu açar/daraltır, ⌥⌘] tümünü açar.

Katlama halen BEGIN tabanlıdır; BEGIN'siz IF/ELSE, bütün batch/statement outline veya tam T-SQL parser eşdeğerliği yoktur. Düzenleme ve undo öncesinde gizli kodu korumak için katlanmış alanlar açılır; bu sürümde katlanmış görünümün içinde doğrudan metin düzenleme eklenmedi. Kullanım yaklaşımı Microsoft [SSMS outlining](https://learn.microsoft.com/en-us/ssms/scripting/code-outlining?view=sql-server-ver16), JetBrains [DataGrip folding/selection](https://www.jetbrains.com/help/datagrip/work-with-sql-code.html) ve [DDL navigation](https://www.jetbrains.com/help/datagrip/code-editor-navigation.html) belgeleriyle karşılaştırıldı; tüm ürün davranışlarının birebir eşdeğerliği iddia edilmez.

## Procedure, function, trigger ve diğer nesneler (0.2.24)

Procedure / function / trigger menülerinde **Modify → ALTER**, **Script As → CREATE / ALTER / CREATE OR ALTER / DROP / DROP And CREATE**, **View Dependencies**, **Delete**, **Properties** ve uygun nesnelerde **Rename** bulunur. Script hedefleri yeni query, pano ve dosyadır. Modify mevcut tanımı, ANSI_NULLS ve QUOTED_IDENTIFIER ayarlarıyla yükler; mevcut fark önizlemesi / DB'ye uygulama akışı kullanılır. Tanımın eski adı sp_rename sonrasında kalmışsa yalnızca modül başlığı güncel katalog adıyla düzeltilir; gövdeye dokunulmaz. DROP işlemi nesne adı yazılan inceleme ekranından SQL üretir; otomatik çalışmaz.

- **Execute Stored Procedure** parametre adı/türü, Value/NULL/DEFAULT ve OUTPUT alanlarını gösteren ayrı form açar. İncele düğmesi tipli DECLARE, named EXEC, return value ve OUTPUT SELECT scripti üretir. DEFAULT seçilen procedure argümanı gönderilmez; SQL Server'daki varsayılan kullanılır, yoksa sunucu hata verir. Function formu scalar için SELECT, table-valued için SELECT TOP (1000) üretir; konumsal argümanlar korunur. TVP, özel kullanıcı türleri ve CLR çağrıları formda desteklenmez; açık hata ile elle SQL'e yönlendirilir.
- Table/view altındaki **Triggers** DML trigger'larını; Programmability altındaki **Triggers** database-scoped DDL trigger'larını gösterir. Etkin trigger yeşil şimşek ve Enabled, devre dışı trigger sönük üstü çizili şimşek ve Disabled etiketi taşır. Sağ tık Enable/Disable doğru tablo/view veya ON DATABASE hedefiyle SQL açar. ALTER SQL Server'da trigger'ı etkinleştirdiği için üretilen modül scripti mevcut disabled durumunu tekrar uygular. Properties durum, kapsam, parent, INSTEAD OF, NOT FOR REPLICATION ve tarihleri sunucudan okur. Server-scoped DDL trigger yönetimi bu sürümde yoktur.
- Procedure terminal, function matematiksel fonksiyon, synonym bağlantı ikonuyla ayrılır. Kolon, parametre, key, indeks ve constraint alt nesneleri artık sağ tıklanabilir. Kolon/parametre Modify ilgili tablo designer/modül editörüne gider; index/key/constraint scriptleri ve indeks rebuild/reorganize/disable işlemleri SQL incelemeye açılır. FK/check enable-disable desteklenir; default constraint için anlamsız enable seçeneği gösterilmez.
- **Synonym** hedef düzenleme formu CREATE veya transaction içinde DROP+CREATE üretir; SQL Server'da ALTER SYNONYM olmadığından izinlerin yeniden atanması gerekebilir. Procedure/scalar function/inline TVF/trigger/synonym klasörlerinde New şablonları vardır. Bütün işlemler sağ tıklanan bağlantı/veritabanına aittir.
- Table Designer'da **Kolon Ekle**, **Seçili kolon** ve **Seçili Kolonu Kaldır** kaydırılan içeriğin dışında sabit araçlardır. Kolonlar iki yönde kayar; yapı yönetimindeki script düğmesi de listenin dışında kalır. Pencere minimum 800×600 pt'dir.

Başarıyla çalıştırılan, transaction dışında tamamlanan üretilmiş trigger/index/constraint/rename scripti ilgili Explorer dalını yeniler. Elle açılan transaction içinde değişiklik yaptıysanız COMMIT sonrasında Yenile kullanın. Disk DDL araması halen table/view/procedure/function/synonym ve kolon kapsamındadır; trigger/index/constraint için disk arama indeksi bu sürümde eklenmedi. Şifreli / CLR modüllerinin okunamayan tanımları açık hata verir. Tüm SSMS güvenlik ve özel nesne tasarım ekranları bu sürümün kapsamında değildir.

Davranış referansları: Microsoft [procedure parametre formu](https://learn.microsoft.com/en-us/sql/relational-databases/stored-procedures/execute-a-stored-procedure?view=sql-server-ver17), [function Modify](https://learn.microsoft.com/en-us/sql/relational-databases/user-defined-functions/modify-user-defined-functions?view=sql-server-ver17), [trigger enable/disable/delete](https://learn.microsoft.com/en-us/sql/relational-databases/triggers/delete-or-disable-dml-triggers?view=sql-server-ver17), [SSMS script hedefleri](https://learn.microsoft.com/en-us/ssms/tutorials/scripting-ssms).

## Tek grid araç çubuğu (0.2.11)

Grid araçları tek kompakt çubukta: **ilk/önceki/sonraki/son aralık, yenile, otomatik yenileme, satır limiti, sonuç araması, başlıklarla kopyala, dışa aktar ve filtreleri temizle**. Results/Messages gerçek sekmeleri korunur. Ayrı sağdaki Kolon filtresi seçicisi kaldırıldı; kolon başlığındaki filtre ikonu, sağ tık menüsü ve aktif filtre etiketleri çalışır. Kolon gizleme/gösterme başlık sağ menüsündedir. Messages veya plan açıkken yalnızca grid’e ait araçlar pasifleşir; otomatik sorgu yenileme ve sonraki sorgu limiti kullanılabilir.

- İkonlarda işlem açıklaması ve mevcutsa kısayol tooltip’te görünür. Otomatik yenileme saat simgesi, dışa aktarma paylaşım simgesi, başlıklı kopyalama belge simgesi kullanır. Uygulanmamış veri düzenleme/commit/DDL araçları eklenmez.
- **Başlıklarla Kopyala** sağ tıkta ve araç çubuğunda bulunur; hücre seçimi yalnızca seçilen kolonların başlıklarını, # üzerinden satır seçimi tüm görünür kolonların başlıklarını ekler. Görünür kolon sırası, TSV kaçışları, NULL ve 10.000 satır/16 MB sınırları korunur. Normal **⌘C** başlık eklemez.
- **Ayarlar → Klavye kısayolları → Grid · Başlıklarla kopyala**: **⇧⌘C** (varsayılan) veya **⌥⌘C**. Tercih bu Mac’te kalıcıdır ve menü/tooltip anında güncellenir. GridShortcuts ortak davranışı gelecekte diğer işlemler için genişletilebilir; tam serbest tuş atama bu sürümde yoktur. Kısayol grid odaktayken çalışır.
- SQL Server **bit** kolonlarındaki 1/0 salt okunur checkbox olarak çizilir. NULL açıkça NULL kalır. Checkbox veritabanına yazmaz; kopyalama/dışa aktarma özgün 0/1 değerlerini korur. Başlıkta bit tipi ve checkbox simgesi görünür.
- Kaydırma gözlemcisi kaldırıldı. Sayaç sonuç/filtre değişiminde ve gezinme oku kullanıldığında güncellenir; normal kaydırmada yeniden formatlama veya araç çubuğu yerleşimi tetiklemez. Gösterilen aralık son gezinme aralığıdır, viewport satır numarası değildir. Sayaç ipucu yüklenen/gösterilen sayısını açıklar. Gezinme SQL Server’dan sayfa istemez.

## Grid, yenileme ve sekmeler (0.2.9)

- Sonuç panelinde **Results / Messages / Execution Plan** gerçek sekmelerdir. Yenileme araçları ve filtre/dışa aktarma üst çubukta kalır.
- **Yenile**, son çalıştırılan SELECT metnini tekrar çalıştırır; editörde sonradan değişen SQL veya seçim kullanılmaz. Tüm sonuç kümeleri aynı sorgudan yeniden alınır. Aynı kolon yapısında filtreler, sıralama, kolon genişliği/gizleme ve açık sonuç/mesaj sekmesi korunur.
- **Otomatik yenileme**: kapalı, 5/10/30/60 saniye veya 5 dakika. Varsayılan kapalıdır, sürüm/oturum açılışında kendiliğinden başlamaz. Çalışan sorguyla çakışmaz; hata, bağlantı kopması, veritabanı değişimi veya açık transaction’da durur. Yalnızca muhafazakâr SELECT/CTE denetiminden geçen başarılı sorgular tekrar edilir; DML, DDL, EXEC, SELECT INTO, GO, sequence ve yazma kilitleri içeren SQL için normal Çalıştır kullanılır. Bu denetim bir SQL yetkilendirme sınırı değildir; özel sunucu fonksiyonlarının harici yan etkilerini analiz etmez.
- Grid’de hücreye tıklayın; Shift+tıklama veya sürüklemeyle dikdörtgen hücre aralığı seçin. Sol **#** sütunundan bütün satır seçilir. Sağ tık **Kopyala** ve **⌘C**, seçilen hücreleri görünür kolon sırasıyla TSV olarak kopyalar; NULL açıkça yazılır. Boş seçim kendiliğinden bütün sonucu kopyalamaz. Pano sınırı 10.000 satır / 16 MB; büyük çıktı için dışa aktarma kullanın.
- Kolon başlığının üzerinde bekleyince sürücünün bildirdiği veri tipi, uzunluk ve hassasiyet görünür; örneğin `nvarchar(50)`, `decimal(18,2)`, `datetime2(3)`.
- İlk/önceki/sonraki/son araçları **yüklenmiş ve filtrelenmiş satırlarda 500 satırlık adımlarla** gezinir. Bunlar sunucu sayfalaması değildir; gösterge yüklenen sayıyı, kısmi sonuçta `+` işaretini gösterir. Disk destekli grid yalnızca ekranda gereken satırları çizer.
- Sorgu sekmesine sağ tık: **Pin/Unpin Tab, Close Tab, Close Right Tabs, Close Left Tabs, Close Other Tabs**. Toplu kapatma sabitlenen sekmeleri korur. Açık transaction/çalışan sorgu/kaydedilmemiş metin için mevcut uyarılar geçerlidir; iptal toplu işlemi durdurur. Sabitleme, isteğe bağlı çalışma alanı kurtarmasına dahildir.
- Yeni bağlantılarda **Bağlantıyı Keychain’de sakla** artık açık gelir; istenirse kapatılabilir. Başarılı bağlantıdan sonra profil, parola, seçili veritabanları ve ortam/rengi aynı sürümden bağımsız Keychain servisinde saklanır. Son kaydedilen bağlantı sonraki açılışta doldurulur; SQL kendiliğinden çalışmaz. Önceden hiç kaydedilmemiş parolalar eski süreç kapandıktan sonra geri getirilemez. macOS yeni imzalı ikiliye Keychain erişimi için sistem onayı isteyebilir.

## Pratik bağlantı ve veritabanı seçimi (0.2.6)

Bağlantı ekranı 940 × 680 pt iki sütundan oluşur: sunucu bilgileri solda, veritabanları sağda. Formun tamamını kaydırmak gerekmez; yalnızca uzun veritabanı listesi kayar. Ortam ve renk ayarları sol sütunda doğrudan görünür; test ve bağlantı düğmeleri sabit kalır.

- Arama alanı liste açılınca odaklanır. Boşluk, virgül veya noktalı virgülle ayrılmış sözcüklerin hepsini içeren adlar bulunur; örneğin `satış 2026`. Tek eşleşme varsa Enter seçer. Escape aramayı temizler.
- **Tümü / Kullanıcı / Sistem** ve **Yalnızca seçilenler** filtreleri, uzun listeyi daraltır. Filtre dışında kalan seçimler korunur. Adlar doğal sıralanır; `DB2`, `DB10`'dan önce gelir.
- **Görünenleri Seç / Kaldır** yalnızca geçerli filtredeki eşleşmeleri değiştirir. **Toplu seçim** menüsünde tüm listeyi seçme ve bütün seçimi temizleme işlemleri ayrıca bulunur.
- Satırdaki yıldız, yeni sorguların varsayılan veritabanını belirler ve o veritabanını seçime ekler. Seçili/toplam sayısı ve varsayılan adı sürekli görünür. Boş seçimle bağlanılmaz.
- Bilgiler değişmeden tekrar test veya yenileme yapılınca seçimler korunur. Sunucu, kimlik bilgileri veya sertifika ayarı değişince önceki test ve liste geçersizleşir.
- Object Explorer sağ menüsündeki **Bağlantı ayarları**, mevcut bilgilerle otomatik test başlatır; başarıdan sonra veritabanları ve önceki seçimler yüklenir. Bu işlem sırasında yükleme durumu görünür. Hata olursa gerçek hata gösterilir; test başarılıymış gibi davranılmaz. Alanlar değişince yeniden test gerekir.

## Object Explorer bağlantı işlemleri ve ortam renkleri

Object Explorer sağ tık menüsündeki **Bağlantı ayarları** bağlantı testi, sunucu/kimlik bilgileri, veritabanı görünürlüğü, varsayılan veritabanı ve ortam/rengi tek ekranda yönetir. Ayrı **Bağlantıyı Test Et**, **Bağlantı Rengi ve Ortamı…**, **Veritabanlarını Seç…** ve **Sunucuya Bağlan…** öğeleri kaldırıldı. Yeni sunucu eklemek için üst araç çubuğundaki **Bağlan** veya Object Explorer başlığındaki bağlantı düğmesini kullanın. İşlemler sağ tıklanan sunucuyu hedefler; farklı bir aktif sorgu sekmesini hedef almaz. Sunucu menüsünden bağlantıyı kesebilirsiniz.

Ortam önayarları: Canlı (kırmızı), Test (yeşil), Dikkat (turuncu), Geliştirme (mavi), Özel. Renk seçici veya altı haneli RGB koduyla her profil için özel renk seçilebilir; özel ortam etiketleri en fazla 40 karakterdir. Varsayılan rengi geri yüklemek veya işareti kaldırmak mümkündür. İşaret ağaçta sunucu adı/zemini/kenar çizgisinde, sorgu sekmelerinde ve sorgu başlığında görünür; ayrı pencerelerde de korunur. Nesne türlerinin ikon renkleri korunur. **Bu bir görsel hatırlatmadır; SQL çalıştırmayı engelleyen bir güvenlik politikası değildir.** Keychain'e kaydedilen profiller ortam/rengi de saklar; kaydedilmemiş bağlantılar yalnızca RAM'dedir. Eski profiller işaretsiz açılır.

Ayarlar formu mevcut bilgileri doldurur; ilk açılışta test ve listeleme otomatik başlar. Ortam, renk kodu, varsayılan rengi geri yükleme ve işareti kaldırma doğrudan formdadır. Değişiklikler **Uygula** ile kaydedilir; **Vazgeç** mevcut ayarları korur. Ad, ortam, renk ve veritabanı görünürlüğü mevcut sorgu oturumlarını değiştirmez. Sunucu/port/login/parola/Kerberos/sertifika ayarı değişirse önce aday bağlantı doğrulanır. Başarısız aday mevcut oturumu bozmaz. Çalışan sorgu veya açık transaction varsa değişiklik uygulanmaz. Başarılı değişiklikte bu sunucunun açık sekmeleri metinlerini ve dosyalarını korur, önceki sonuçlar temizlenir, oturumlar yeni varsayılan veritabanına bağlanır; SQL otomatik çalıştırılmaz. Diğer sunucuların sekmeleri korunur.

## Çalışan kapsam

- Bağlantı testi → veritabanı listeleme → çoklu seçim akışı. Test ve listeleme kısa ömürlü ayrı bağlantılar kullanır; sorgu sekmesi açmaz ve Keychain'e yazmaz. Bağlantı alanları/parola değişirse test sonucu sıfırlanır. Yalnızca sunucunun erişim verdiği veritabanları listelenir; seçim erişim izni veya güvenlik sınırı değildir.
- Veritabanı seçimi isteğe bağlı Keychain profilinde saklanır ve güncellenir. Eski profiller uyumlu kalır; seçim alanı olmayan eski kayıtlar tüm erişilebilir veritabanlarını gösterir. Yeni bağlantılar boş seçimle başlar. Yenileme, sonradan eklenen veritabanlarını kendiliğinden seçmez.
- Object Explorer ikonlarında kategori renkleri: sunucu indigo, veritabanı teal, tablolar mavi, views cyan, procedures/functions mor, güvenlik ve anahtarlar turuncu, yönetim yeşil. İkonlar ve metinler ayrımı renkten bağımsız da belirtir.

- Sunucu/veritabanı/tablolar/views/procedures/functions/synonyms; sütun, parametre, anahtar, indeks, constraint ve trigger ayrıntıları. Logins/users/roles/linked servers ve Agent jobs/schedules ağacı.
- SQL Authentication; Keychain'e isteğe bağlı profil ve parola kaydı. Kerberos bağlantı modu mevcut; gerçek AD ortamında doğrulanmadı. Microsoft sürücüsünün bu modu [Kerberos bileti ve SPN yapılandırması gerektirir](https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/using-integrated-authentication).
- Bağımsız sorgu oturumları, çalıştırma/iptal, GO, PRINT ve hata tanıları, transaction komutları, açık transaction varken kapatmayı engelleme.
- TextKit 2 editörü: renkler, satır numaraları, undo/redo, bulma, native tamamlama; metadata, alias, tablo değişkeni/temp table ve basit CTE/derived SELECT önerileri.
- Disk destekli çoklu sonuçlar, kolon bazlı filtreler, türüne göre sıralama, yerel arama, çoklu satır kopyalama, hücre inceleme ve akış halinde CSV/JSON dışa aktarma. JSON NULL ve aynı adlı sütunları korur; CSV formül güvenliği için riskli hücreleri apostrofla işaretler.
- Tahmini/gerçek XML plan, operatör ağacı, tahmini/gerçek satır ve maliyet, uyarılar, .sqlplan kaydı.
- İndeks ve tek T-SQL adımlı Agent job + günlük schedule tasarımı; SQL önce sorgu sekmesine aktarılır. Job start/stop/enable/disable de script olarak açılır.
- Activity, sessions, locks/blocking ve database files sorguları. Sunucu izinleri yetersizse hata gösterilir.
- İsteğe bağlı yerel Timeline ve sekme kurtarma; varsayılan kapalı. Son 300 geçmiş kaydı; dosyalar Application Support/MSSQLStudio altında, parola içermez. Kurtarma yeniden açıkça bağlandıktan sonra yapılır; sorgular otomatik çalıştırılmaz.
- Kullanıcı tarafından yapılandırılan chat/completions sağlayıcısına AI paneli. Gönderilecek metin açıkça görünür; sonuç/şema/parola otomatik eklenmez. SQL önerisi ayrı sekmeye aktarılır, otomatik çalışmaz.
- JSON SQL şablon eklentisi içe aktarma. Örnek `Examples/diagnostics.template.json`; bu sürümde şablonlar açık panelde tutulur.

## Tablo / view sağ tık yönetimi (0.2.23)

SSMS'in [Script Object As](https://learn.microsoft.com/en-us/ssms/tutorials/scripting-ssms) ve [Table Designer](https://learn.microsoft.com/en-us/ssms/visual-db-tools/design-tables-visual-database-tools) akışları esas alındı. İşlem ekranlarında **SQL Editöründe İncele** yeni sorgu sekmesini açar; değişikliği uygulamak için SQL'i kontrol edip **Çalıştır** kullanılır. Script tasarım ekranları kendi başına veritabanına yazmaz. Agent işlem penceresindeki açık Uygula/İşi Sil ve nesne değişikliği önizlemesindeki Uygula komutları ayrıca yürütme yapar.

- **Table → Design…**: kolon ekle/kaldır/ad değiştir, veri tipi, NULL, default ve primary key. Yeni identity kolonları 1,1 kullanır. Mevcut identity/computed kolonun yeniden oluşturulması otomatik yapılmaz.
- **Keys / Indexes / Relationships**: mevcut PK/UQ, indeks, FK, check ve trigger scriptlerini görüntüleme; DROP / DROP + CREATE scriptleri; yeni indeks, unique key, FK ve check formu. Filtreli/INCLUDE indeks ve FK cascade seçenekleri bulunur.
- **View → Design… / Modify · ALTER…**: gerçek tanımı ALTER olarak düzenleme, farkları gösterme. New View ekranında tek kaynak ve kolon seçimiyle başlangıç SQL'i oluşturma; karmaşık JOIN/CTE SQL editöründe yazılır. ANSI_NULLS / QUOTED_IDENTIFIER ayarları korunur.
- **Script Table / View As**: CREATE, DROP, DROP And CREATE, SELECT, INSERT, UPDATE, DELETE; view için ALTER ve CREATE OR ALTER. Hedefler yeni sorgu, pano ve `.sql` dosyasıdır. UPDATE/DELETE şablonları başlangıçta `WHERE 1 = 0` içerir.
- **Edit Top 200 Rows**: primary key olan standart tabloda hücre düzenleme, satır ekleme/silme, NULL ve yenileme. Değişiklik SQL'i PK + rowversion ile, rowversion yoksa karşılaştırılabilir orijinal kolonlarla denetlenir. Eşzamanlı değişiklikte transaction geri alınır. Mevcut PK, identity ve computed alanlar salt okunur; view/anahtarsız tablo için veri editörü yoktur.
- **Delete… / Rename… / Properties…**: bağımlılık listesi ve tam nesne adı onayıyla DROP scripti; yeniden adlandırma; genel bilgiler ve GRANT/DENY/REVOKE izin scriptleri. Dinamik SQL bağımlılıkları sistem kataloğunda bulunmayabilir. Rename sonrasında Explorer'ı yenileyin; SQL metin başvuruları otomatik değiştirilmez.
- **Tables / Views klasörü → New Table… / New View…**: ayrı oluşturma ekranları.

Tablo CREATE çıktısı standart rowstore kolonlarını, named default, identity/computed, collation, PK/UQ, rowstore indeks, FK, check ve trigger tanımlarını içerir. Permissions, extended properties ve bağımsız istatistikler dahil değildir. Temporal, memory-optimized, graph, partition/compression, columnstore/XML indeks ve özel üretilen/şifreli/filestream kolonlar için eksik CREATE üretmek yerine hata gösterilir. Bu bir SMO eşdeğeri yedekleme aracı değildir.

## Derleme ve test

`MSSQLStudio.xcodeproj` → **MSSQLStudio** scheme → Run. Shared scheme OpenSSL 3 yolunu yalnızca uygulama sürecine ekler. `scripts/build-app.sh` Release derlemesi, kalıcı kişisel imza doğrulaması, ZIP ve PKG oluşturur; depoda tanımlanan imzalama kimliğinin yerel Keychain'de bulunması gerekir. Sistem OpenSSL bağlantıları değiştirilmez.

10 Ekim 2026 tarihinde geliştirme başlangıcı GitHub'daki son yayın `v0.2.34` / `822c36f4c7922ff780400f7e72b0808f22dddd44` olarak doğrulandı. Yerel çalışma dalı `codex/continue-v0.2.34`. Başlangıç ve sonraki değişikliklerin Release derlemesi, otomatik testleri ve yalıtılmış native arayüz kontrolü için [güncel doğrulama kaydına](TEST-REPORT.md) bakın.

İmzalama kimliği kullanmadan geliştirme derlemesini kontrol etmek için:

```sh
build_dir="$(mktemp -d /tmp/MSSQLStudio-dev.XXXXXX)"
xcodebuild -project MSSQLStudio.xcodeproj -scheme MSSQLStudio -configuration Release \
  -derivedDataPath "$build_dir" CODE_SIGNING_ALLOWED=NO build
./scripts/test.sh
```

Bu komut dağıtım paketi üretmez. Gerçek yayın ZIP'ini güncelleme/imza testlerine dahil etmek için `scripts/test.sh` çağrısına `MSSQL_UPDATE_ZIP` ortam değişkeniyle ZIP'in yolunu verin; verilmezse ilgili testler doğrulamayı çalıştırmadan döner.

`scripts/verify.py`, yerel geçici AI fixture ve Keychain testiyle tüm doğrulama paketini çalıştırır. `scripts/test.sh` bağımsız testleri çalıştırır. Canlı testler yalnızca `MSSQL_TEST_PASSWORD` ortam değişkeni sağlandığında çalışır; yerel localhost test sunucusunu kullanır. `MSSQL_KEYCHAIN_TEST=1` geçici ve rastgele bir test servisiyle Keychain yaşam döngüsünü sınar. `MSSQL_MOCK_URL` yerel AI HTTP test sunucusunu belirtir. Parolaları komut geçmişi veya dosyalara yazmadan ortamınıza sağlayın.

Test/build çıktıları `/tmp` altında tutulur: iCloud/File Provider'ın `.app` içine eklediği FinderInfo imzayı bozabilir. ZIP bu yüzden kaynak ağacındaki unpacked uygulama yerine dağıtım çıktısıdır.

## Sınırlar

Bu sürüm çalışan, geniş kapsamlı native bir örnektir; SSMS'in bütün özellikleriyle eşdeğer bitmiş ürün değildir. Tam T-SQL grammar/binder, kapsama göre eksiksiz IntelliSense, grafik plan diyagramı, sürükle-bırak docking, view üzerinden veri düzenleme, grafik JOIN/ilişki diyagramı, otomatik tablo rebuild, backup/restore sihirbazları ve ikili eklenti SDK'sı yoktur. Yönetim ekranlarının önemli kısmı gerçek sorgu veya gözden geçirilebilir script açar. AI gerçek sağlayıcı/model ile henüz sınanmadı; aktarım katmanı yerel sahte sağlayıcıyla doğrulandı. Notarization/App Store dağıtımı yoktur.

Varsayılan okuma sınırları: 50.000 satır, 100 sonuç kümesi, hücre başına yaklaşık 2 MB, toplam 64 MB veri ve 60 sn sorgu timeout. Sonuç araç satırından 1 milyon veya 5 milyon satır modu seçilebilir; bu modlarda toplam veri bütçesi 2 GB ve timeout 600 sn olur. Sınır sonraki sorguya uygulanır. GUI sonuçları RAM yerine özel geçici dosyada tutulur; indeksler ve filtre/sıralama anahtarları RAM kullanır. Bu, sınırsız satır veya sabit bellek kullanımı iddiası değildir. Sınıra ulaşınca kısmi sonuç ve mesaj gösterilir. Bunlar sunucuda daha önce gerçekleşmiş yazma işlemlerini geri almaz. Transaction kontrolü ayrı ve açık tutulur. Renklendirme 250.000 UTF-16 biriminin üzerindeki metinde kapatılır; editör kullanılabilir kalır.

Doğrulama ayrıntıları: [TEST-REPORT.md](TEST-REPORT.md). Mimari: [ARCHITECTURE.md](ARCHITECTURE.md).


## Studio görünümü (0.2.8)

Ayarlar (⌘,) → **Studio Açık / Studio Koyu** → Uygula. DataGrip referansındaki yüzey ayrımı, düzenli ikonlar ve sakin seçim renkleri kararlaştırılmış SSMS yerleşimine uygulandı. Ana paneller, sorgu sekmeleri, nesne ağacı, editör, grid, bağlantı formu, ayarlar, Timeline, AI, şablonlar ve script tasarımcıları ortak görsel dil kullanır. Ayrıntılar [DESIGN.md](DESIGN.md) içindedir. `Examples/Premium-Preview.sql`, mevcut tablolara dokunmadan Türkçe metin/sayı/tarih/NULL içeren 100 satırlık görünüm örneği üretir.

Arayüz sistem yazı tipini, SQL editörü varsa Consolas 13 pt, yoksa native monospace kullanır. Mavi keyword, sıcak string, yeşil comment ve mor fonksiyon kategorileri hem açık hem koyu temada dengelenmiştir. Satır numaraları sakin gri; grid’de NULL italik ikincil metinle gösterilir. Seçili sorgu sekmesi açık yüzey/ince kenarlık ve belge ikonu kullanır; sunucu ortam rengi korunur. Sayı/metin/tarih kolon ikonları, filtre ve sıralama işaretleri başlıktadır. Tema değişiminde seçim, kolon genişlikleri ve gizli kolonlar korunur. Filtresiz grid’de açıklama/boş etiket satırı alan kaplamaz.

macOS menüleri ve pencere kontrolleri native kalır. Bu görünüm DataGrip veya SSMS’in piksel düzeyinde kopyası değildir. Markdown/fenced SQL blokları aynı palet ve fontları kullanır; tam Markdown belge motoru yoktur. Bu bloklar otomatik çalıştırılmaz.


## 0.2.4 — Ekran alanı ve kompakt yerleşim

Sabit başlık yükseklikleri azaltıldı; font boyutları değişmedi. Ana pencere native kompakt araç çubuğu kullanır. Tekrarlanan pencere alt başlığı ve T-SQL etiketi kaldırıldı; aktif sunucu/veritabanı ve ortam işareti sorgu başlığında kalır.

| Alan | Önce | Şimdi |
|---|---:|---:|
| Sorgu sekmeleri | 39 pt | 28 pt |
| Veritabanı satırı | 36 pt | 26 pt |
| Sorgu bağlantı/konum başlığı | 30 pt | 24 pt |
| Sonuç araç satırı | 32 pt + native sekme şeridi | 26 pt; sonuç/mesaj seçimi aynı satırda |
| Alt durum satırı | 28 pt | 20 pt |
| Object Explorer minimum genişliği | 235 pt | 210 pt |
| Nesne ağacı satır yüksekliği | 25 pt | 20 pt |
| Sonuç satır yüksekliği | 23 pt | 20 pt |
| Editör satır yüksekliği | 20 pt | 18 pt |

Sabit satırlardan **41 pt** dikey yer geri kazanıldı; native sonuç sekme şeridinin kaldırılması ve kompakt pencere çubuğu ayrıca alan açar. Bu rakam ekran çözünürlüğünden bağımsız macOS yerleşim puntosudur; toplam ekran yüzdesi pencere boyutuna bağlıdır.

- **⌘R:** aktif sorgunun sonuç alanını gizle/göster. SQL metni, sonuçlar, seçili sonuç kümesi ve oturum korunur; geri açınca ayırıcı önceki oranına döner. Sorgu başlığındaki küçük düğme aynı işlemi yapar.
- **⌥⌘B:** Object Explorer'ı gizle/göster. İkisini gizleyerek editöre daha fazla alan ayırabilirsiniz.
- Sonuç panelinin gerçek sekmelerinden Results 1/2/…, Execution Plan veya Messages’a geçin; filtre ve dışa aktarma yanında kalır.
- İlk editör/sonuç oranı %60/%40'tır; ayırıcı sürüklenebilir. Ayrı sorgu penceresinin komut satırı 42 → 28 pt oldu.
- 0.2.4 sürümünde bağlantı formu yüksekliği azaltılmıştı. 0.2.5, bu formun yerine yukarıda açıklanan sabit iki sütunlu tasarımı kullanır.


## 0.2.7 — Kolon filtreleri ve büyük sonuç grid’i

- Kolon başlığının sağındaki **⌄** veya **Kolon filtresi…** seçicisi değer/koşul panelini açar. Metinde içerir/başlar/eşittir, sayıda karşılaştırma/aralık ve tarihte önce/sonra/aralık kullanılabilir. Aralık uçları dahildir. Tarih girdisi YYYY-MM-DD veya ISO 8601, ondalık ayırıcı noktadır.
- Değer listesinde **Değer seçimini kullan** ile çoklu seçim açılır. NULL ve boş metin ayrı seçeneklerdir. Arama seçimleri korur; Görünenleri seç/Kaldır yalnızca paneldeki değerleri değiştirir. Liste en fazla 500 farklı değer gösterir; diğer değerleri arayarak bulabilirsiniz. Liste ayrıca uzun metinlerin belleği doldurmasını önleyen bir boyut bütçesine sahiptir. Boş değer seçimi sıfır satır getirir; değer seçimini kapatmak bu sınırlamayı kaldırır.
- Farklı kolonların koşulları ve genel arama birlikte uygulanır. Filtre etiketindeki × o kolonun filtresini kaldırır; **Filtreleri Temizle** kolon filtrelerini ve genel aramayı temizler. Filtreler her sonuç kümesinde ayrı tutulur. Yeni sorgu yeni sonuç/filtre durumu oluşturur.
- Başlığın metnine tıklama artan/azalan sıralar. Decimal değerler Double'a çevrilmez. Tarihler tarihe göre sıralanır; NULL artan sıralamada önce, azalan sıralamada sonra gelir. Eşit değerlerin kaynak sırası korunur. Satır numarası orijinal sonuç satırını gösterir.
- Kolon başlığı sağ menüsü filtre, **İçeriğe Sığdır**, gizleme ve gösterme sunar. İçeriğe sığdırma ilk 200 görünür satırdan örnek alır ve genişliği sınırlar; milyon satırı ölçmez. Kolonlar sürüklenebilir ve kenarlarından genişletilebilir. Gizlenen kolonlar filtre, kopyalama ve dışa aktarma verisinden çıkarılmaz.
- Hafif dönüşümlü satır zemini, sağa hizalı sayılar, belirgin NULL ve çift tıkla uzun hücre inceleme korunur. Hücre önizlemesi sınırlıdır; veri saklama/dışa aktarma kırpılmaz.
- Durum satırı **yüklenen / gösterilen** sayısını ve kısmi sonuç uyarısını gösterir. Filtre/sıralama arka planda çalışır; yeni bir işlem önceki işi iptal eder. Yükleme devam ederken veya işlem sürerken ekrandaki eski görünüm geçici olabilir; “İşleniyor…” işareti görünür. İşlem bitmeden dışa aktarma başlatılmaz.
- **Dışa Aktar** menüsünde görünen satırlar veya tüm yüklenen satırlar için CSV/JSON seçilir. Görünenler mevcut filtre ve sıralamayı izler; tüm yüklenenler sorgu sırasındadır. Dosya arka planda parça parça yazılır, aktarım iptal edilebilir. İptal veya hata mevcut hedef dosyayı değiştirmez. Kopyalama en fazla 10.000 satır / 16 MB'dır; büyük sonuçlar için dışa aktarma kullanın.

### Milyonlarca satır için davranış

GUI ODBC sonuçları 512 satır veya yaklaşık 1 MB'lık parçalarla geçici dosyaya yazılır. Dosya özel izinlidir ve açılır açılmaz adı dosya sisteminden kaldırılır; oturum açıkken descriptor üzerinden okunur, sonuç bırakılınca kapanır. Normal kapanış veya süreç çökmesi sonrasında bu sonuç dosyası geride kalmaz. Bu geçici saklama, Timeline/kurtarma kaydı değildir.

Ekran yalnızca görünür hücreleri oluşturur. Filtreleme satırları çoğaltmaz; eşleşen satır indekslerini tutar. Sıralama anahtarlarını bir kez okur ve arka planda iptal edilebilir kararlı sıralama uygular. Satır indeksleri ve anahtarlar satır sayısıyla büyür; geniş/uzun kolonlar, tarih ayrıştırma, disk hızı ve eşzamanlı sorgular performansı etkiler. 5 milyon modu sunulur; bu sürümde 1.000.001 satır canlı sunucuda, 2 milyon kısa satır yerel benchmark'ta sınandı. Sonsuz/sınırsız veri veya tüm şekillerde aynı hız iddia edilmez.

Filtreler **yalnızca yüklenmiş bölümde** çalışır. Satır/veri bütçesi, iptal veya sunucu hatası nedeniyle kısmi sonuç varsa sunucuda kalan satırlar filtrelenmez. Otomatik yeniden SELECT veya OFFSET/FETCH yapılmaz; sorgunun sırası, yan etkileri ve transaction davranışı değiştirilmez. Büyük veri için mümkünse SQL WHERE/TOP ile sunucuda daraltın.

## Çalışma alanı güncellemesi — 0.2.11

Results/Messages sekmeleri soldadır; arama araç çubuğunun en sağındadır. Sonuç paneli gizlendiğinde panel ve ayırıcı birlikte kaldırılır. Query sekmeleri başlığından sürüklenerek sıralanabilir; pin ve aktif oturum korunur. Yeni query varsayılan ⌘N ile açılır; Explorer’da veritabanı seçiliyse o veritabanını, sunucu seçiliyse bağlantının varsayılan veritabanını kullanır. Ayarlar → Kısayollar alanında Yeni Query ve Başlıklarla Kopyala için Cmd/Ctrl içeren harf veya rakam kombinasyonları kaydedilebilir; çakışan/rezerve tuşlar reddedilir.

Page Size: 10, 100, 250, 500, 1.000, All, Custom… ve Set as Default. Varsayılan 500’dür; özel değer 1–1.000.000 olabilir. Sayfalama yüklenen sonuç üzerinde yapılır, SQL Server sayfalaması değildir. All yalnızca yüklenmiş satırlardır; sorgu okuma sınırı ayrı alt menüdedir. Geçerli sayfa dışa aktarma mevcut sayfayı, Tüm yüklenen seçeneği yüklenen sonucu aktarır.

Kolonlar ilk sonuçta en fazla 32 satır / 4.096 hücre örneklenerek 70–420 pt aralığında otomatik genişler; yenilemede kullanıcı genişlikleri korunur. Disk sonuçlarında 256 satır / 8 MiB sınırında çözülmüş satır önbelleği geniş kolonlarda tekrar okumayı azaltır. Alttaki yatay kaydırma çubuğu daima görünür; trackpad ile yatay kaydırma desteklenir. Sayfa sayacı kaydırma olaylarına bağlı değildir.

## Explorer ve ALTER düzenleme — 0.2.12

Explorer başlığındaki sola daraltma düğmesi paneli gizler; sorgu veritabanı çubuğundaki sidebar düğmesi geri açar. SQL editöründe kısa metin için yatay genişlik viewport’a eşitlenir; yalnızca uzun satırda yatay kaydırma gerekir. Messages her çalıştırmanın yerel tarih/saatini ve veritabanını içerir.

Nesne araması seçili Explorer düğümünün veritabanında yapılır. Tables/Views/Procedures/Functions/Synonyms seçiliyse türle sınırlanır; sunucu seçiliyse bağlantının varsayılan veritabanı kullanılır. İçerir, Eşittir, İle başlar, İle biter ve İçermez seçenekleri vardır. Arama 350 ms gecikmeli, tek sorgu uçuşlu, eskimiş yanıtları reddeden ve ilk 500 sonucu gösteren yapıdadır. SQL wildcard karakterleri düz metindir. Arama tüm ağacı açmaz veya indeks/kolonları yüklemez. Sunucunun sys.objects kataloğu kullanıldığı için ayrı bir yerel disk indeksi tutulmaz; offline arama ve indeks/kolon adı araması bu sürümde yoktur.

Table sağ menüsü Select Top 1000 Rows, Script As → SELECT/INSERT/UPDATE/DELETE, özellikler/indexler, Create Index ve View Dependencies içerir. Script komutları önce editöre gelir. Veri düzenleme grid’i / tam SSMS tablo tasarımcısı eklenmedi. View/procedure/function çift tıklama veya Modify komutu ALTER düzenleme sekmesi açar. Farkları Gör, açılan sunucu tanımı ile editördeki metni karşılaştırır; doğrusal değişen blok önizlemesi en fazla 1.000’er satırdır, minimal satır diff’i değildir. DB’ye Uygula önizlemeyi gösterir, güncel tanımla çakışma kontrolü yapar ve ancak Uygula seçilince SQL’i çalıştırır. Açık transaction varken bu akış durur. Çakışma kontrolü iyimserdir; kontrol ile ALTER arasında atomik sunucu kilidi sağlamaz. Şifreli veya VIEW DEFINITION izni olmayan modüller düzenlemeye açılamaz. Tablo şeması ALTER tasarımcısı bu akışa dahil değildir.

Uygulamada başarılı, transaction dışında çalıştırılan basit CREATE/ALTER/DROP TABLE/VIEW/PROC/FUNCTION komutları için yalnızca ilgili nesnenin metadata’sı ve açık ilgili arama yenilenir; diğer ağaç dalları yeniden yüklenmez. Yeni/silinen nesne yüklü tür klasörüne eklenir/çıkarılır. Başka uygulamalardan yapılan değişiklikler, dinamik SQL, transaction içinde sonradan commit edilen DDL ve çok parçalı veritabanı adları için elle Yenile kullanın. DDL takibi tam T-SQL parser’ı değildir.

## Kalıcı nesne disk indeksi — 0.2.13

Explorer araması artık yerel SQLite indeksini kullanır. İlk yükleme seçili veritabanından 1.000 nesnelik sayfalarla yapılır. Tamamlanan indeks atomik yayımlanır; hatada önceki indeks korunur. Sonraki aramalar SQL Server'a gitmeden yerel dosyada çalışır ve 500 sonuç gösterir. Ad, şema, tür ve nesne kimliği saklanır; parola, veri veya DDL gövdesi saklanmaz. Bağlantı/sunucu/port/kullanıcı/auth/veritabanı kapsamı SHA-256 anahtarıyla ayrılır.

Dosya: Application Support/MSSQLStudio/CatalogIndex/catalog-v1.sqlite. SQLite actor üzerinde UI dışında çalışır; WAL, 4 MiB sayfa önbelleği, disk geçici alanı ve iptal kontrolü kullanılır. Yarım kalan build kayıtları bir günden sonra açılışta temizlenir. Yeniden açılan uygulama tamamlanmış indeksi kullanır.

Desteklenen başarılı DDL yalnızca hedef kaydı ekler/günceller/siler. Tam build sürüyorsa hedef güncellemesi yayımlamayı bekler. Harici değişiklikler anında izlenmez: beş dakikadan eski indeks bir sonraki aramada arka planda eşitlenir, eski sonuç hemen kullanılabilir. Hata sonrası denemeler en az 60 sn arayla yapılır. Başlıktaki disk simgesi elle eşitleme yapar; son eşitleme ve nesne sayısı durum ipucundadır.

Türler: table/view/procedure/function/synonym. Kolon/index adları ve DDL kaynak metni bu sürümde indekslenmez. İçerir/İçermez/İle biter yerel tarama yapabilir; FTS değildir. Unicode/Türkçe harf ve aksan duyarsız arama yapılır; %, _ ve apostrof düz metindir. İlk indeks bağlantı gerektirir; ayrı offline sunucu açma akışı yoktur. İlk yükleme sırasında server kataloğu değişirse farklı anların metadata'sı görülebilir; sunucuda snapshot transaction alınmaz. İzin değişikliklerinde eski adlar tam eşitlemeye kadar önbellekte kalabilir; içerik/izin önbellekten verilmez. Önceki bölümdeki disk indeksi yok açıklaması 0.2.12 içindir.

## Kalıcı uygulama / açılış / arama kapsamı — 0.2.14

0.2.13 tarihsel konumu: ~/Applications/MSSQLStudio.app. 0.2.28 ile güncel kurulum hedefi /Applications/MSSQLStudio.app oldu. Artık her sürümde başka çıkarılmış .app dosyası açmak gerekmez. MSSQL Studio → Güncellemeyi Yükle… yerel ZIP paketini doğrular, daha yeni sürümü hazırlar, açık sorgu/transaction ve kaydetme akışını kontrol eder, çıkıştan sonra aynı konumda değiştirir ve yeniden açar. Önceki uygulama .previous yedeğinde kalır. Paket bundle ID, version, codesign ve ZIP yolları kontrol edilir; symlink paketleri reddedilir. Bu kişisel ad-hoc imza doğrulamasıdır, yayıncı kimliği/onaylanmış internet kaynağı doğrulaması değildir. Otomatik indirme sunucusu veya uzaktan güncelleme kontrolü henüz yoktur. Gerçek güncelleme için kullanıcı kendi sağlanan güncelleme ZIP'ini seçer.

Kayıtlı Explorer bağlantıları açılışta Keychain'den geri yüklenir; görünür veritabanı seçimleri, varsayılan DB ve renkler ServerProfile ile korunur. İlk geçişte eski kayıtlı bağlantılar taşınır. Bağlantıyı Kes ile kaldırılan Explorer sonraki açılışta otomatik açılmaz; Keychain kaydı silinmez. Ağ bağlantısı kurulamazsa Explorer çevrimdışı kalır, tekrar kurulum formu dayatılmaz. Kaydedilmemiş/parolası Keychain'de olmayan bağlantı otomatik geri getirilemez. Query sekmesi kurtarma mevcut ayrı Ayarlar tercihiyle yönetilir.

Arama için açık Bağlantı / Veritabanı seçicisi ve ayrı nesne türü seçicisi vardır. Ağaç seçimi arama kapsamını değiştirmez. Metni temizlemek veritabanını korur, normal ağacı geri açar. Son açık arama kapsamı kalıcı kaydedilir. Böylece her aramada yeniden Explorer seçmek gerekmez.

## Explorer kapsamı ve otomatik indeks — 0.2.15

Arama kapsamındaki **Tüm seçili veritabanları**, ilgili Explorer bağlantısının görünür veritabanlarını birlikte arar. Tek veritabanı seçimi de korunur. Sonuçlarda veritabanı adı gösterilir; nesne açma gerçek veritabanında çalışır. Yerel arama en fazla 500 sonuç gösterir; veritabanı sırasına göre sınırlandırılır. Diğer bağlantılar ve seçilmemiş veritabanları kapsama girmez.

Yeni bağlantıda, bağlantı ayarları/DB seçimi değiştiğinde, kayıtlı Explorer geri açıldığında ve sunucu listesi yenilendiğinde indeksler arka planda sırayla hazırlanır. Tamamlanmış indeks diskten yeniden kullanılır; 5 dakikadan eski kayıt yenilenir. İndeks hazırlanırken arama mevcut tamamlanmış veritabanlarını gösterir; eksik indeksleri belirtir. Yetki/ağ hatası olan veritabanı diğerlerini engellemez. Nesne adları/türleri indekslenir; DDL gövdesi veya tablo verileri depolanmaz.

**Güncellemeleri Kontrol Et** yerel dosya seçmez. GitHub deposu daha sonra ekleneceği için bu sürümde yayın adresi tanımlı değildir ve menü bunu açıkça bildirir. Yayın entegrasyonunda Configuration/Info.plist içine MSSQLUpdateFeedURL HTTPS adresi eklenir. JSON bilgisi version, downloadURL ve sha256 alanlarını içerir; paket SHA-256, imza, bundle ID ve gerçek sürüm eşleşmesiyle doğrulanır. İnternet üzerinden gerçek indirme/yayın henüz denenmedi. Önceki 0.2.14 yerel ZIP menüsü kaldırılmıştır.

## PKG dağıtımı

Dağıtım çıktısı artık MSSQLStudio-0.2.15.pkg. build-app.sh Release uygulamasını doğrular, dahili ZIP çıktısından build-pkg.sh ile PKG üretir. 0.2.15 paketi yalnızca mevcut kullanıcı alanını hedefliyordu; 0.2.28 paketi sistem genelinde /Applications konumunu hedefler. Bundle relocation kapalıdır; eski test kopyaları kurulum hedefi olamaz. Installer uygulamanın önce kapanmasını ister. Kurulum script'i yoktur; yalnızca uygulama bundle'ı taşınır, Keychain / Preferences / Application Support korunur. macOS 27+ ve arm64 koşulları pakete işlendi.

Paket şu anda Developer ID Installer sertifikasıyla imzalı veya notarize değildir. İçindeki uygulamanın ad-hoc imzası doğrulanır; bu Apple yayıncı doğrulaması yerine geçmez. Sürücü bağımlılıkları mevcut Mac kurulumundan kullanılır. Güncelleme feed'i hâlâ yapılandırılmamıştır; gelecekteki GitHub entegrasyonu ayrıca tamamlanacak. Dahili ZIP updater/staging doğrulaması için korunur.

## Arama ve SQL Editor — 0.2.16

Object Explorer artık Nesneler ve Arama sekmelerine sahiptir. Arama ayrı sonuç listesi kullanır; metin temizlenince Nesneler sekmesindeki genişletilmiş dallar, seçili nesne ve kaydırma konumu geri yüklenir. Arama sürerken Nesneler sekmesine geçilebilir; arka planda biten arama ağacı yeniden yüklemez. Kapsam, operatör ve tür seçimleri korunur. Sunucu bağlantısı/DB listesi gerçekten değiştiğinde eski nesne referansları geçersiz olabilir; bu bir oturumlar arası ağaç persistansı değildir.

SQL Editor açık tema paleti Microsoft SSMS varsayılan renk kategorilerine göre güncellendi: keyword mavi #0000FF, string kırmızı #FF0000, comment koyu yeşil #008000, system function magenta #FF00FF, system schema yeşil, stored procedure maroon, operator gri, düz metin siyah, satır numarası teal. Koyu tema aynı kategorileri okunabilir koyu paletle gösterir; Microsoft sayfası koyu temanın RGB değerlerini tanımlamaz. Consolas mevcutsa kullanılır, aksi durumda macOS monospace fontu kullanılır; Windows fontu pakete eklenmez.

Sekme genişliği dört boşluk ölçüsündedir; mevcut TAB/boşluklar açılışta değiştirilmez. Tab ve Shift+Tab seçili satırları girintiler/geri alır, yeni satır önceki girintiyi korur. Bu blok girintisidir; SSMS dil servisinin bütün smart-indent kuralları değildir. Yatay genişlik gerçek font ve sekme ölçüleriyle hesaplanır. Sözdizimi renklendirmesi yalnızca rengi değişen aralıklara foregroundColor uygular; her yazışta tüm belgenin font/paragraph attributes'u değişmez. 250.000 UTF-16 karakter üstünde renklendirme kapalı kalır. SQL metni açılışta yeniden formatlanmaz.

Kaynaklar: https://learn.microsoft.com/en-us/ssms/scripting/color-coding-in-query-editors ve https://learn.microsoft.com/en-us/ssms/scripting/manage-code-formatting .


## 0.2.17 — Editör girişi ve güvenli UI testleri

SQLTextView düzenlenebilir/seçilebilir olarak açıkça yapılandırılır; ilk tıklama editörü odaklar. Arama alanından boş editöre tıklayıp normal klavyeyle SELECT 1; yazılması native arayüzde doğrulandı. 26 uygulama + 54 çekirdek test raporu başarılı; bu tur canlı DB testleri etkinleştirilmedi.

Başlangıçta ServerVault.list ana UI iş parçacığında çalışmaz. Anahtar Zinciri izni beklenirken uygulamanın ana olay döngüsü açık kalır. Görsel test hazırlama scripti ayrı local.mssqlstudio.uitest kimliği kullanır; bu kimlikle başlatılan uygulama kayıtlı bağlantıları, parolaları ve kullanıcı sunucularını okumaz, bağlantısız bir sorgu açar. --ui-smoke argümanı da aynı davranışı sağlar. Test modu bağlantı kaydetme gibi işlemleri test etme yetkisi vermez.

Mevcut dağıtım ad-hoc imzalıdır; Developer ID imzalama kimliği bulunmadı. Kullanıcının daha önce verdiği Keychain izninin farklı derlemelerde otomatik korunacağı garanti edilmez. ACL'ler gevşetilmedi, parolalar düz metne taşınmadı. Kalıcı sürüm kimliği için aynı Developer ID ile imzalama gerekir.


## 0.2.18 — İlk açılan boş SQL belgesi

0.2.17 native kontrolü önceden metin içeren test belgesiyle yapıldığı için ilk açılışta tamamen boş editörün tıklama sorununu yakalayamadı. Kullanıcının 0.2.17 penceresinde hata tekrarlandı: ilk boş belge tıklama ile odaklanmadı; erişilebilirlik yoluyla geçici metin atanıp temizlenince tıklama/yazma çalıştı. Geçici kontrol metni geri alındı; kullanıcı sorgusu boş bırakıldı.

EditorController artık ilk metin atamasını belge boşken de yapar; sonraki eşit metin güncellemelerinde gereksiz atama yapmaz. UI test modu artık ilk açılışta tamamen boş bir belge açar. Anahtar Zinciri ve sunucu bağlantısı kullanılmaz.

Son native kontrol başarılı: yeni test uygulaması ilk açılışta tamamen boş sorguyla başladı; hiçbir ön metin ataması olmadan editöre tıklayıp SELECT 1; yazıldı. Undo ile boşaltılıp arama alanına geçildi; editöre tekrar tıklayıp yorum yazıldı. Odağın sqlEditor'da ve metnin sorguda olduğu AX ile doğrulandı. Test metni geri alındı ve test uygulaması kapatıldı. 27 uygulama + 54 çekirdek test raporu başarılı; canlı SQL Server testleri bu tur etkin değildi.


## 0.2.19 — Sabit satır alanı ve blok daraltma

SQL metni ile satır numaraları artık aynı native ruler/clip yerleşimini paylaşmaz. 68 punto genişliğinde ayrı bir alan Auto Layout ile metnin solunda kalır. Satır numarasına tıklamak satırın bütün metnini ve varsa satır sonunu seçer. En sağdaki −/+ düğmeleri çok satırlı BEGIN–END, BEGIN TRY–END TRY ve BEGIN CATCH–END CATCH bloklarını açıp kapatır; iç içe bloklar desteklenir. IF/ELSE dallarında bu BEGIN blokları kullanılır. CASE/END, BEGIN TRANSACTION, yorum ve string içindeki sözcükler yanlış kapanış sayılmaz. Eşleşmemiş bloklar daraltılmaz.

Daraltılmış görünümde özgün satır numaraları korunur, gizlenen alan … ile gösterilir. Düğme üzerine gelince kod önizlemesi görünür. Editör sağ tık menüsü ve ⌥⌘[ (imlecin bulunduğu en içteki bloğu daralt/aç), ⌥⌘] (tümünü aç) kullanılabilir. Bunlar macOS kısayollarıdır; SSMS'in Windows Ctrl+M akoru kopyalanmaz.

Daraltma dosyanın SQL metnini veya dirty durumunu değiştirmez. Kopyalama/seçili kod çalıştırma özgün kaynak aralıklarına eşlenir. Düzenleme ve undo/redo öncesi daraltılmış alanlar açılır; gizli kodun yanlışlıkla görünüm yer tutucusuyla değiştirilmesi önlenir. Formatlama/metin değiştirme blok durumunu sıfırlar. Oturumlar arasında daraltma durumu saklanmaz. Yapısal analiz 250.000 UTF-16 karaktere kadar yapılır; üstünde blok analizi devre dışıdır. Satır numarası için satır başlangıçları önbelleğe alınır, her görünen satırda belgenin başı tekrar taranmaz.

Kapsam: BEGIN tabanlı bloklar. SSMS'in tüm batch ve çok satırlı statement outline dil hizmeti eşdeğerliği iddia edilmez. Tek satırlı veya BEGIN kullanmayan IF/ELSE ifadeleri için ayrı daraltma bölgesi üretilmez. TextKit 2, native undo ve mevcut SQL çalıştırma katmanı korunur.

Microsoft kaynakları: https://learn.microsoft.com/en-us/ssms/scripting/code-outlining ve https://learn.microsoft.com/en-us/ssms/sql-server-management-studio-keyboard-shortcuts .


## 0.2.20 — DDL destekli SQL tamamlama ve doğrulama

Aktif sorgunun veritabanına ait tablo, view, synonym, procedure/function adları ve kolon adları disk indeksine kaydedilir. Tablo/view önerisini FROM/JOIN konumunda kabul etmek `[dbo].[Customers] AS c` gibi bir alias ekler. Mevcut alias korunur, aynı alias kullanılmışsa c2 gibi benzersiz ad seçilir. `c.` yalnızca ilgili kaynağın kolonlarını önerir; alias yazmadan kolon tamamlaması `[c].[Name]` olarak eklenir. EXEC bağlamında procedure önerileri vardır. INSERT/UPDATE konumunda alias otomatik eklenmez.

Güncel ve doğrulanmış indeksle çözülebilen eksik tablo/kolon başvuruları kırmızı, altı çizili ve açıklama ipucuyla gösterilir. Bu SQL derleyicisi veya çalıştırma engeli değildir. İmlecin üzerinde yazılan ad, eski/başarısız/kısmi indeks, başka veritabanına üç/dört parçalı başvuru, sys/INFORMATION_SCHEMA ve bilinmeyen geçici nesneler için yanlış hata üretmemeye çalışır. USE/CREATE/ALTER/DROP/PIVOT/UNPIVOT içeren belgelerde anlamsal doğrulama muhafazakâr biçimde kapalıdır; tamamlama devam eder. Basit CTE/derived SELECT ve belgede tanımlanan geçici/tablo değişkeni kolonları desteklenir. Karmaşık dinamik SQL, bütün T-SQL grameri, SELECT * CTE kolon yayılımı, comma-join ve varsayılan şema/case-sensitive collation çözümleme tam dil hizmeti düzeyinde değildir; bazı bağlamlar öneri/uyarı üretmeyebilir veya manuel kontrol gerektirebilir.

**Ayarlar → SQL editörü**: yazarken öneriler, eksik başvuru doğrulaması ve otomatik alias birbirinden bağımsızdır. Tamamlama SQL çalıştırmaz. Tab/Enter veya çift tıklama kabul eder; oklar öneriyi seçer. Boşluk ve nokta istemeden öneri kabul etmez. Alias yalnızca kabul edilen tablo/view önerisine eklenir. İşlem native undo ile geri alınır.

Metadata ayrı ODBC bağlantısında 2.000 satırlık keyset sayfalarıyla alınır; editörün sorgu/transaction oturumunu değiştirmez. Tam snapshot SQLite'a atomik kaydedilir; eksik yükleme eski snapshot'ı değiştirmez. Profil/login/veritabanı kapsamları ayrıdır. İlk bağlantıda seçili veritabanları arka planda hazırlanır, sorgu veritabanı değişince kapsam temizlenir. Başarılı DDL uygulaması veya manuel yenileme indeksi günceller. Dışarıda yapılan değişiklikler için Yenile kullanın; metadata önbelleğinin tazelik süresi 5 dakikadır. Kolon indeksine yalnızca adlar/tür kategorileri yazılır; kullanıcı sonuçları, parola veya DDL gövdeleri yazılmaz.

Performans sınırları: 260 ms yazma beklemesi, iptal edilebilir arka plan analizi, kaynak/imleç/sürüm doğrulaması; en fazla 100 öneri ve 200 uyarı. İndeks sınırı 50.000 nesne / 250.000 metadata satırı; aşımda eksik metadata ile kırmızı uyarı açılmaz. Ortak RAM önbelleği en fazla 8 veritabanı snapshot'ı tutar (açık sorgular kendi snapshot'ını korur). Anlamsal analiz en fazla 100.000 UTF-16 karakter / 4.000 anlamlı token / 128 kaynak bağlamında çalışır; daha büyük belgelerde SQL yazma/çalıştırma korunur, semantik öneri/uyarı kapatılır. Sözdizimi renklendirmesi ve blok analizi 250.000 UTF-16 karaktere kadar sürer. Tamamlama esnasında font, paragraf veya metin yeniden atanmaz.

Davranış kaynakları: [DataGrip code completion](https://www.jetbrains.com/help/datagrip/auto-completing-code.html), [SSMS T-SQL IntelliSense kapsamı](https://learn.microsoft.com/en-us/ssms/scripting/transact-sql-syntax-supported-by-intellisense). Bu sürüm bu ürünlerin tam parser eşdeğeri değildir.


## 0.2.21 — Alias ve geniş sonuç tabloları

Otomatik üretilen aliaslar artık büyük harflidir: `[dbo].[TBLSTSABIT] AS T`. Elle yazılan mevcut aliaslar değiştirilmez. Ayarlar → SQL editörü → **Otomatik alias sonrasında WITH(NOLOCK) ekle** seçeneği varsayılan kapalıdır. Açıldığında FROM/JOIN tablo veya view önerisi kabul edilince `AS T WITH(NOLOCK)` eklenir; mevcut WITH ipucu tekrarlanmaz. INSERT/UPDATE hedeflerine eklenmez. [NOLOCK commit edilmemiş verileri okuyabilir](https://learn.microsoft.com/en-us/sql/t-sql/queries/hints-transact-sql-table?view=azuresqldb-current); bu ayar sorgu davranışıdır, grid kaydırma optimizasyonu değildir.

Sonuç tablosu her hücrede ayrı view ve Auto Layout oluşturmak yerine native hücre çizimi kullanır. Disk destekli ResultSpool ve sınırlı RAM önbelleği korunur. Hücre/satır seçimi, kopyalama, bit kutuları, NULL, filtreleme ve yatay kaydırma korunur. 64 kolonlu sentetik kaydırma ölçümleri TEST-REPORT.md içindedir. Gerçek TEST2026/TBLSTSABIT sorgusu bu sürüm testinde çalıştırılmadı; gerçek ekran FPS garantisi verilmez.


## 0.2.22 — Kaydırma, seçim ve tanıma geçiş

Gridde native baskın eksen kaydırması açıldı: dikey trackpad hareketindeki küçük yatay sapmaları azaltır; yatay kaydırma ve scrollbar korunur. Fiziksel trackpad diyagonal hareket/FPS ölçümü bu tur yapılmadı.

SQL editöründe seçili metnin diğer kullanımları sarı arka planla görünür (harf duyarsız metin eşleşmesi, yorumlar dahil; semantik usages analizi değildir). Seçim temizlenince vurgu kalkar. Büyük metinde yazma kalitesini korumak için 250.000 UTF16 karakter / 256 karakter seçim / 500 eşleşme sınırı vardır. Ctrl+A ve ⌘A tüm metni seçer; SQL editöründe Apple Writing Tools kapalıdır.

İndekste bulunan tablo/view/proc/function adına ⌘tık, ⌘B veya sağ tık → Nesne Tanımına Git yeni sorgu açar. View/proc/function sunucudan alınan tanımı ALTER biçiminde ve karşılaştırma tabanıyla açar; otomatik çalıştırmaz. Tablo, kolon/identity/default/computed/type bilgilerinden CREATE **önizlemesi** açar; constraint/index/trigger/table seçenekleri dahil değildir ve üstte açıkça yazılıdır. Tam tablo export veya otomatik migration değildir. Çapraz veritabanı/alias üzerinden tanıma geçiş ve şifreli modüller desteklenmez; VIEW DEFINITION izni gerekir.

Kapanan köşeli parantezle tamamlanan eksik nesne adı için imleci taşımadan hata vurgusu yapılır. Güncel aktif veritabanı indeksi gerekir; eski indeks yazarken arka planda yeniden doğrulanır (hata halinde en fazla 30 saniyede bir deneme). Explorer başlığının altındaki DDL indeksi satırı nesne/kolon indeksinin tarihini ve hazır/eşitleniyor/hata durumunu gösterir; geniş ayrıntılar üzerine gelince görünür. Nesne ağacında seçilen bağlantı/DB, Arama sekmesinde açık arama kapsamı gösterilir. Yenileme düğmesi hem nesne hem kolon indeksini yeniler.

Davranış kaynakları: [DataGrip nesne navigasyonu](https://www.jetbrains.com/help/datagrip/code-editor-navigation.html), [Apple baskın eksen kaydırması](https://developer.apple.com/documentation/appkit/nsscrollview/usespredominantaxisscrolling), [Apple Writing Tools davranışı](https://developer.apple.com/documentation/appkit/customizing-writing-tools-behavior-for-system-views).

### 0.2.32 yayın doğrulaması

[GitHub v0.2.32](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.32) yayımlandı. Uzak CI ikinci denemede 118 farklı testi geçti; ilk arayüz test süreci signal 11 ile kapanmıştı. GitHub paketinin gerçek güncelleyiciyle indirme, SHA-256, sabit sertifika ve sürüm hazırlığı doğrulandı; kurulu uygulama değiştirilmedi. Keychain erişim kuralları değiştirilmediği için tekrar izin istemesinin tamamen kalktığı doğrulanmış değildir.
