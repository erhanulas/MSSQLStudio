## 12 Ekim 2026 — v0.2.77 / build 78: SQL renkleri, Explorer durumu ve güncellemede yeniden açma

- Native yazımda renkler tamamlamanın gecikmesini beklemeden güncellenir; literal içindeki caret aynı SSMS typing rengini taşır. Yalnız attribute değişir; IME, Unicode, native undo/redo ve belge metni korunur. Açık/koyu temada her native edit sonrasında bütün string aralığı ve caret rengi sınandı.
- Noktalı virgülsüz SELECT ifadelerinin binding kapsamı ayrıldı; önceki/sonraki SELECT ve UNION kolunun alias’ı alias’sız tabloya sızmaz. TBLSTSABIT/STOK_KODU için boşluk/LF/CRLF/semicolon/GO/UNION/UNION ALL ve her iki caret yönü, mevcut geçerli alias/CTE/nested query testleriyle kontrol edildi. Mevcut SQL metni otomatik yeniden yazılmaz.
- Explorer, UUID ve semantik parent path ile açık/kapalı dalları hatırlar; root otomatik tekrar açılmaz. Lazy yükleme ve node rebuild sonrasında açık atalar üzerinden restore yapılır. AppKit üst dal collapse sırasında alt collapse bildirimleri ürettiğinden alt tercihlerin kaybolması regresyonda yakalandı; will/did collapse takibi ve programmatik reload guard ile ayrıldı. Aynı adlı iki profil, yeniden controller oluşturma, DB listesi/root rebuild, profil yeniden adlandırma, üst dalı kapatıp yeniden açma ve offline durumda reconnect olmaması sınandı.
- Güncellemede Güncelle ve Yeniden Aç / Güncelle ve Kapat / Vazgeç vardır. İlk seçim signed app executable’ını UI/Keychain/restore olmadan ayrı izleyici modunda çalıştırır. Eski PID çıkışı, beklenen exact sürüm, canonical hedef ve strict/deep sabit DR doğrulanınca Apple NSWorkspace yeni instance açar; Installer must-close korunur. İzleyici 30 dk ile sınırlıdır; frozen credential helper değişmez. [Apple API](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/createsnewapplicationinstance).
- İlk genel native koşu aynı masaüstünde paralel tema/hover testlerinin birbirini kapatması nedeniyle başarısız oldu. scripts/test.sh açık --no-parallel ile suite’leri sırayla çalıştırır; derleme paralelliği korunur. Son `/tmp/mssql-077-tests-final.log`: **133 app + 144 core = 277 test; 252 geçti / 25 dış koşullu atlandı**, iki hedefin tamamlanmış başarılı özeti var. Release `/tmp/mssql-077-release.log`: **BUILD SUCCEEDED**. İlk yeni testte explicit undo grouping eksikliği düzeltildi; başarısız koşular başarı olarak sayılmadı.
- Yeniden açma kontrolü eksik app, yanlış sürüm, unsigned app, canlı parent, geçersiz PID/timeout ve indirilen gerçek v0.2.76 signed fixture ile strict doğrulamayı kapsar; CI aynı testleri yeni yayın paketiyle çalıştıracaktır. İzole son Release executable’ında headless watcher canlı sentetik parent ile bekledi, geçersiz argümanlar UI açmadan çıktı; test-owned izleyici sonlandırıldı. Gerçek /Applications güncellemesi, Installer tamamlanması ve kullanıcı uygulamasını yeniden açma uçtan uca yapılmadı; kullanıcı oturumları/Keychain değiştirilmedi.
- İzole `/tmp/MSSQLStudio-077-ui/MSSQLStudio.app` CUA koyu temada `SELECT N'SELECT İstanbul FROM metin'` içini kırmızı gösterdi. Noktalı virgülsüz `Customers C` sorgusundan sonraki alias’sız sorguda popup `[Name]` sundu; Tab yalnız `[Name]` ekledi. DemoDB/Tables açıldı, DemoDB kapatılıp açılınca Tables açık kaldı. Yeniden başlangıç/state rebuild ayrıca native testte doğrulandı; UI fixture UUID’si her başlatmada değiştiği için CUA restart kalıcılığı iddia edilmez. Sentetik sorgu kaydedilmeden test app’i kapatıldı.
- Yayın/CI/public paket doğrulaması tamamlanınca bu kayda eklenecek. Helper v1 kaynak/pinler değişmedi.

## 12 Ekim 2026 — v0.2.76 / build 77: Kompakt editör ve akıllı tırnaklar

- Editör numara alanı 68 → 44 pt; sonuç numaraları 60 → 36 pt taban genişlikte. Basamak sayısı, katlama ve düzenleme/yeni satır işaretleri gerektiğinde alanı büyütür; sabit kolon bütçesi gerçek genişliği kullanır.
- Favori, Gerçek Plan, konum ve sonuç görünümü araçları mevcut controller’dan veritabanı/Explorer satırına taşınır. Sekme geçişi ve pencere ayırma/geri alma aynı belge/controller/odak ile çalışır; detached pencerede başlık kendi yerine döner.
- [DataGrip Smart Keys](https://www.jetbrains.com/help/datagrip/settings-smart-keys.html) eş tırnak davranışı araştırıldı. Klavyeden tek/çift tırnak eşlenir, caret içeride kalır; üretilen kapanış üzerinden geçilir, boş çift Backspace ile silinir, seçili kod sarılır. Native undo/redo, Unicode, SQL doubled apostrophe, yorum/literal bağlamı, salt okunur ve yapıştırılan SQL doğruluğu korunur. Senkron lexer 250.000 UTF-16 birimiyle sınırlıdır; daha büyük metinlerde sıradan yazım sürer.
- `/tmp/mssql-076-tests.log`: **131 app + 142 core = 273 test; 248 geçti / 25 dış koşullu atlandı**. İki hedefin tamamlanmış özetleri doğrulandı. Yeni regresyonlar tırnak bağlamı/girdi/caret/undo/paste, dinamik gutter ve 1060/1360 pt tek satır/sekme/detach/odak durumlarını kapsar. `/tmp/mssql-076-release.log`: **BUILD SUCCEEDED**.
- Son Release binary ile izole `/tmp/MSSQLStudio-076-ui/MSSQLStudio.app` CUA: koyu temada birleşmiş tek satır, kompakt editör ve altı sonuç numarası görüldü. `SELECT N` ardından tek tırnak çifti ve `İstanbul` yazımı, kapanış üzerinden geçme; çift tırnak çifti ve boş çiftin Backspace ile silinmesi gerçek native girdiyle doğrulandı. Test uygulaması kaydetmeden kapatıldı. Gerçek kullanıcı uygulaması/SQL/Keychain kullanılmadı; canlı dış koşullar doğrulanmış sayılmaz.
- [Public latest v0.2.76](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.76), kaynak/tag `3178a1d304ff11eb3b64c9b0b245e460b4493526`; [Actions 38245496512](https://github.com/erhanulas/MSSQLStudio/actions/runs/38245496512) bütün adımlarıyla başarılı. Gerçek yayın paketleriyle CI 131 app + 142 core = **273 test; 248 geçti / 25 dış koşullu atlandı**, iki tamamlanmış özet `/tmp/mssql-076-ci-tests.log` içinde doğrulandı.
- İndirilen ZIP/PKG/update.json/credential archive GitHub digest ve public manifest ile eşleşti. ZIP ve PKG app/helper strict imzaları, sabit DR/sertifika, build 77, executable/metadata/notlar eşitliği ve exact frozen helper doğrulandı (`/tmp/mssql-076-public-verification.log`, `/tmp/MSSQLStudio-0.2.76-verify`). ZIP SHA-256 `f6230074a74241109559307ffc4e13bb0a45c486b204a7adb5634055ff0986df`; PKG `9dea637047f221424960058d4f7a07ef31ca108e6e3d2cd038e8fe56e77720d4`; update.json `2f98f0cc7a946d57ed2308692f42ae75baa185853b341646d5b53d2f1c1e269b`. İlk indirmede geçici HTTP 504 alındı; yeni istekle bütün indirme/doğrulama tamamlandı.
- Frozen helper kaynak/pins değişmedi; archive SHA-256 `75bfb1d347f211607eda75ec2a511d3d3d38e3ffef786fec174cce932c6b5713` ve binary `5bdc54f130122075cb1d6204d49d2251f761e60cc4a8110652d1754af1a0f81b` v0.2.69 ile aynı. Tag taşınmadan yayın kanıtı main’de ayrı belge commit’iyle kaydedilir.

## 12 Ekim 2026 — v0.2.75 / build 76: SQL tamamlama boşluğu ve Explorer arama kapsamı

- Tamamlama: native kapsayıcı ilk büyük içerik yüksekliğini koruyup küçülen yüzeyi aşağıda bırakıyordu. Native regresyonda 30 → 1 geçişinde yüzey 78 pt iken kapsayıcı contentSize 468 pt ve fazladan 390 pt boşluk ölçüldü. Yalnız kapat/aç yeterli olmadı; değişen boyutta controller çıkarılıp son boyutuyla yeniden bağlanınca kontroller geçti. Aynı boyutta gereksiz kapat/aç yok; animasyon kapalı, yüzey kapsayıcıyla boyutlanır. [Apple contentSize](https://developer.apple.com/documentation/appkit/nspopover/contentsize) controller atanırken içerik view boyutunun kullanıldığını belirtir.
- Arama: tüm root’lardan scope üretimi yerine seçili Explorer sunucusu kullanılır. Bağlantı başına çalışma süresince DB tercihi, aynı Explorer içindeki açık kapsam ve eski UUID kapsam tercihi korunur. DB/bağlantı kaldırılınca geçerli kapsam seçilir; bağlantı yoksa kontrol pasiftir.
- Yeni native test: 1/3/30/2/1/18 öneride başlık/kapsayıcı yerleşimi; gerçek EditorController popup’ında 30/1/30/11/1 geçişleri, simetrik native insets ve odak. İki Explorer’da farklı ve aynı adlı DB seçenekleri, kayıtlı başka UUID, bağlantı değişimi, tercihe geri dönüş, metin temizleme/state refresh, DB/bağlantı kaldırma kontrol edildi.
- Yerel tam test `/tmp/mssql-075-tests.log`: 127 app + 141 core = **268 test; 243 geçti / 25 dış koşullu atlandı**, iki hedefin tamamlanmış özetleri doğrulandı. İlgili 15 native test: 14 geçti / 1 canlı koşullu atlandı. Release derlemesi başarılı (`/tmp/mssql-075-release.log`).
- İzole `/tmp/MSSQLStudio-075-ui/MSSQLStudio.app` CUA: ilk bağlantı menüsünde yalnız UI Test / tüm DB ve DemoDB; UI Test B’de yalnız kendi tüm DB seçeneği görüldü. İlk bağlantıya dönüşte DemoDB korundu. 100 öneri/16 görünür satırdan tek CustomerID önerisine geçişin ekran görüntüsünde başlık üstünde boşluk yoktu. Tab ile `[CustomerID]` eklendi, editör odağı korundu. Yalnız sentetik veri kullanıldı; gerçek Keychain/DB/açık uygulama değiştirilmedi.
- [v0.2.75](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.75) kaynak/tag `e52c997511653074d3633da0173ad72eaa467e87`, Actions `38243158527`: bütün adımlar başarılı. Gerçek paketlerle CI 127 app + 141 core = **268 test; 243 geçti / 25 dış koşullu atlandı**, iki tamamlanmış test özeti `/tmp/mssql-075-ci-tests.log` içinde doğrulandı.
- Public latest v0.2.75, ZIP/PKG/update.json/credential archive indirildi. GitHub asset digest + public manifest SHA-256, ZIP ve PKG’den açılmış app/helper strict imzaları, sabit DR, paketler arası executable/metadata/release notes eşitliği ve frozen helper binary/archive eşitliği doğrulandı (`/tmp/mssql-075-public-verification.log`, `/tmp/MSSQLStudio-0.2.75-verify`). ZIP `2372d7324e9f148fa5c7d0ab33dbc6fff788952eb85d8483fef305d2a4f38e8b`; PKG `d0addb2b5a97fea642c9bc565e129063ef5676c877e22880155f841c16cca39b`; update.json `74b1f82be2fbc8fea3a1b64e09f9d959b62933644f96ed3bea39431c26aef874`. Helper archive v0.2.69’dan değişmedi: `75bfb1d347f211607eda75ec2a511d3d3d38e3ffef786fec174cce932c6b5713`.
- Canlı SQL Server/gerçek kullanıcı Keychain/kurulu uygulamada güncelleme çalıştırılmadı; bu koşullar doğrulanmış sayılmaz. İzole UI uygulaması sentetik sorgu kaydedilmeden kapatıldı.

# v0.2.71 yayın doğrulaması — 12 Ekim 2026

- [Public latest v0.2.71](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.71), build 72, kaynak `befc15206686c0f638b830d6c6f902e94b934497`. [Actions 38233875621](https://github.com/erhanulas/MSSQLStudio/actions/runs/38233875621) sabit imza/sentetik Keychain fixture, signed ZIP/PKG, manifest, yayın paketi testleri, yayın ve geçici kimlik temizliği dahil **başarılıdır**.
- `/tmp/mssql-071-ci-tests.log`: **121 app + 140 core = 261 test; 236 geçti, 25 dış koşullu atlandı**. Her iki hedef tamamlanmış test özeti üretti; yerel son kaynakla aynı sayım. Sürüm/resource sonrası 18 ilgili kontrol ve Release ayrıca geçti. Kolon sabitleme, autocomplete boyut/klavye/alias, bağlantı durumu ve anlık butonlar aşağıdaki native/CUA/sentetik ODBC regresyonlarıyla sınandı. Gerçek SQL Server/ağ kesintisi koşulları doğrulanmış sayılmaz.
- İndirilen `/tmp/MSSQLStudio-0.2.71-verify` paketleri GitHub asset digest/public manifest ile eşleşti. ZIP SHA-256 `07180a615e676d72f99dcc3ea4dd1f98f4256b6e74d0b629c874b97f70262bed`; PKG `60b2c2a72a0f3c94f5fe9f3dcde7b05f209d151634dc9b1d2a7b3da8edfe0fa7`; public update.json `efbbe4dc6962ce18344628232e71277fafec247554bedd0f55f186465e190743`. İki paketin app/helper strict/deep kod imzaları, sabit DR/sertifika, 0.2.71/72 metadata, binary/notlar/helper bytes eşitliği doğrulandı. Kanıt `/tmp/mssql-071-public-verification.log`.
- Frozen helper archive SHA-256 `75bfb1d347f211607eda75ec2a511d3d3d38e3ffef786fec174cce932c6b5713`, executable `5bdc54f130122075cb1d6204d49d2251f761e60cc4a8110652d1754af1a0f81b`: v0.2.69 pins ile birebir aynı. Helper kaynak/pins değişmedi; yeniden derlenmedi/imzalanmadı. Gerçek kullanıcı uygulaması ve SQL oturumları değiştirilmedi/yeniden başlatılmadı; Keychain/geçmiş/favorilere erişilmedi. Yayın kanıtı main’de ayrı belge commit’iyle kaydedilir, v0.2.71 tag’i taşınmaz.

# v0.2.71 yayın hazırlığı — 12 Ekim 2026

- Kullanıcının yayın isteğiyle sabit kolonlar, autocomplete boyut/klavye/alias, Explorer bağlantı durumu ve anlık düğme düzeltmeleri 0.2.71 / build 72 olarak birleştirildi. Kullanılmamış etiket uzak depoda doğrulandı; her iki Xcode configuration ve tek kaynak ReleaseNotes.json güncellendi.
- İşlevsel son kaynakta 121 app + 140 core = 261 test; 236 geçti / 25 dış koşullu atlandı. Release ve izole native/CUA kontrolleri aşağıdaki tarihli geliştirme kayıtlarında yer alır. Sürüm/resource sonrasında /tmp/mssql-071-release-tests.log altında 2 native + 16 core = 18 ilgili kontrol geçti; /tmp/mssql-071-release-build.log Release BUILD SUCCEEDED.
- Frozen credential helper kaynak/pins değişmedi; kaynak SHA-256 pin ile eşleşti. CI ilk v0.2.69 public archive’ını kullanmalıdır. Bu hazırlık kaydı yayın başarısı değildir; CI/public paket kanıtı tamamlandığında ayrı kaydedilir.

# Tamamlama, bağlantı durumu ve anlık işlem düğmeleri — 12 Ekim 2026 / yerel geliştirme

- SQL tamamlama her açılışta native NSPopover.contentSize değerini açıkça günceller. Liste ekran boşluğuna göre en çok 10 tam satır gösterir; başlık/alt tuş ipucu sabit kalır. ↑/↓, Page Up/Down, Home/End, Shift-Tab, Tab/Enter/Escape seçim/kabul/kapatma desteklenir. Seçili öneri görünür konuma kayar; aynı caret için native selection bildirimi popup’ı kapatmaz. Açık popup/editör ile sınırlı key monitor kapanışta/deinit’te kaldırılır; diğer pencere ve Command/Control/Option kısayollarına dokunmaz.
- Kolon önerilerinde explicit alias ayrı izlenir. Tek alias’sız TBLSTSABIT kaynağına [STOK_KODU] eklenir; olmayan [T] üretilmez. Gerçek alias ve yazılı qualifier korunur; birden fazla kaynakta gerçek tablo/schema/alias ile belirsizlik önlenir. Alias ayarı yalnız tablo kabulüyle AS ekleyen yolu etkilemeye devam eder. Bracket, NOLOCK hint’i, JOIN ve ayrı statement kapsamları regresyonla sınandı.
- Explorer görünür ve örtülmemiş pencerede 15 saniyelik döngüyle mevcut metadata oturumunu SELECT 1 / 5 sn sınırıyla kontrol eder; offline/reconnecting/fixture durumunda ağ işi yoktur. SQLSTATE 08 kopması root ikon/etiket ve araç durumunu bildirir; izin/syntax hatası offline sayılmaz. Eski generation/metadata isteği yeni bağlantıyı kapatamaz. Katalog hata yolları aynı durum yoluna bağlandı. ODBC connect redaksiyonu ve batch hata sarmalayıcısı structured diagnostics’i kaybetmiyor. Kopmuş QueryDocument ready’ye dönmüyor; Explorer ayrı kendi oturumuyla doğrulanıyor. Sonuç sonrası session kontrolü kopmayı yakalıyor, bilinen kopmadan sonra tekrar gönderilmiyor. Kullanıcı sorgu oturumlarını Explorer durum değişimiyle kapatma yoktur.
- StudioToolbarButton anlık eylemlerde sendAction öncesi/sonrası state.off tutar; kopyalama, çoğaltma, ekleme ve geri alma kalıcı seçili görünüm bırakmaz. Yalnız Düzenle/Favori/Otomatik Yenile/Explorer modu tracksActiveState ile modelden aktif görünür; hover/pressed geri bildirimi korunur. Başlıklı kopyalama düğmesine gridCopyHeaders AX kimliği eklendi.
- Son kaynak: `/tmp/mssql-completion-fixes-final-all.log` **121 app + 140 core = 261 test; 236 geçti / 25 dış koşullu atlandı; iki hedefin de tamamlanmış test özeti var**. Son Release `/tmp/mssql-completion-fixes-final-release.log` **BUILD SUCCEEDED**; diff whitespace kontrolü temiz. İlgili önceki koşu `/tmp/mssql-completion-fixes-connection.log`: 21 native + 14 core; 34 geçti / 1 canlı koşullu atlandı. Yeni testler gerçek popup boyutu/klavyeyle son satır görünürlüğü/kabul/undo, alias’sız TBLSTSABIT ve doğru qualifier, anlık düğme dispatch’i/mod toggle, stale/permission/disconnect Explorer ve kapalı query handle + batch diagnostics davranışını kapsar. İlk native koşularda performClick kullanılan bazı koşular helper kapanıp app özeti üretmeden bitti; bunlar başarılı genel koşu sayılmadı. Test gerçek button.sendAction yoluna alınarak native event loop yan etkisi ayrıldı; gerçek tık ayrıca izole uygulamada denetlendi.
- İzole `/tmp/MSSQLStudio-completion-fixes-ui/MSSQLStudio.app` (`local.mssqlstudio.uitest`, compact grid fixture) CUA kontrolünde SELECT * FROM dbo.Customers WHERE bağlamında 100 önerilik popup 10 satırla açıldı. Page Down, End, Home ve Down seçimi/scroll görünürlüğü ekranda doğrulandı; Tab yalnız [Name] ekledi, alias üretmedi. Grid hücresi + başlıklarla kopyala gerçek tık yolu da kontrol edildi. Koyu popup iki satırlı metin/ikon/selection/footer görüntüsü incelendi. Bu CUA kontrolünden sonra yalnız bağlantı diagnostics/session kontrolü değişti; popup/button kaynakları aynı kaldı. Test app’i metni temizlenip menüden kapatıldı.
- Gerçek uygulama/SQL oturumları ve kullanıcı Keychain/geçmiş/favorileri değiştirilmedi. Ağ kesintisi/driver davranışı canlı SQL Server üzerinde denenmedi; bağlantı regresyonları sentetik SQLSTATE’ler ve gerçekten kapalı ODBC handle ile doğrulandı. Sonuç kolon sabitleme çalışması korunur. Sürüm/build/yayın notları ve frozen credential helper değiştirilmedi; bu talepte yayın yapılmadı.

# Sonuç kolonlarını sabitleme — 12 Ekim 2026 / yerel geliştirme

- Sağ tık menüsüne Kolonu Sabitle, Sabitlemeyi Kaldır ve Tüm Sabitlemeleri Kaldır eklendi. İstenen birden fazla kolon satır numarasının yanında solda kalır; grup içi resize/taşıma, pin simgesi, kolon filtresi ve Kolona Git desteklenir. Sabit kolon gizlenince sabitlemesi kaldırılır. Aynı kolon kümesiyle yenileme pinleri korur, farklı sonuç kolonları temizler. Dar görünümde kayan kolonlara 160 pt bırakılır; geniş sabit grup ayrı yatay kayabilir.
- İki cell-based native sunum tek result/spool/filter projection/staged edit kaynağını kullanır. Ordinal kimlik, görünür sırada hücre/aralık/başlıklı kopya, NULL/exact decimal, iki yönlü dikey scroll, ortak satır seçimi ve doğru pane'de native edit/Escape/commit/NULL/sol-sağ gezinme korunur. Pin/unpin SQL çalıştırmaz ve veri snapshot'ını değiştirmez. Başlangıç header genişliğine pin ikon boşluğu eklenerek isimlerin gereksiz kısalması giderildi.
- `/tmp/mssql-pinning-full.log`: **117 app + 138 core = 255 test; 230 geçti, 25 dış koşullu atlandı**. Üç yeni native regresyon testi keyfi/çoklu pin/menu/unpin/hide/show, görünür copy sırası ve NULL/28,8 metni, resize/group reorder, bidirectional scroll, filter/sort/page/refresh, tema/dar/all-pinned yerleşimi, native edit/draft/Escape/unpin commit/NULL/keyboard boundary ve özgün snapshot korunmasını sınadı. İlk genel koşu eski PremiumLayoutTests'in ilk CopyTable'ı ana grid sanması nedeniyle durdu; selector resultsGrid kimliğiyle düzeltildi. Native column rebuild'in sort descriptor'ı temizlemesi de bulundu; callback suppression ve koruma regresyonu eklendi.
- Son görünüm/performance düzeltmesi sonrası ilgili native kontroller `/tmp/mssql-pinning-final-focused.log`, son Release sonucu `/tmp/mssql-pinning-release-final.log` altında kayıtlıdır. Açık/koyu dar native görüntüler `/tmp/mssql-pinned-columns-light.png` / dark; mevcut sort/page kaynak satırı, ikon/etiket boşluğu ve exact decimal metni görsel olarak incelendi. Son kaynakla odaklı koşuda **31 ilgili native test geçti**, Release **BUILD SUCCEEDED**; `git diff --check` temiz.
- İzole `/tmp/MSSQLStudio-pinning-ui/MSSQLStudio.app` (`local.mssqlstudio.uitest`, StudioGridSmokeCompact 6/24) CUA kontrolünde Column0 ve Column3 gerçek başlık sağ tık menüsünden sabitlendi. Kayan pane Column15+ alanına ve aşağı kaydırılırken ikisi solda, kaynak satırlarla ve sabit numaralarla hizalı kaldı. Column3 başlığından Sabitlemeyi Kaldır seçilince yeniden kayan alana döndüğü ekranda doğrulandı. Bu kontrol son header genişliği iyileştirmesinden önceydi; final genişlik açık/koyu native test görüntüsüyle ayrıca kontrol edildi. Test app'i menüden kapatıldı.
- Gerçek uygulama/SQL oturumları, kullanıcı Keychain/geçmiş/favorileri değiştirilmedi. Canlı SQL Server testleri çalışmadı. Bu talep yerel geliştirmedir; sürüm/build/release notları, frozen credential helper ve yayın etiketi değiştirilmedi, yeni yayın yapılmadı.

# v0.2.70 yayın doğrulaması — 12 Ekim 2026

- [Public latest v0.2.70](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.70), build 71, kaynak `6da9f0dbf2c89df4dfc1728b8044978b9970a86d`. [Actions 38192030579](https://github.com/erhanulas/MSSQLStudio/actions/runs/38192030579) sabit imza/modern sentetik Keychain audit, signed ZIP/PKG, manifest, paket testleri, yayın ve geçici kimlik temizliği dahil **başarılıdır**.
- `/tmp/mssql-070-ci-tests.log`: **114 app + 138 core = 252 test; 227 geçti, 25 dış koşullu atlandı**. Yerel tam koşuyla aynı sayım; son odaklı koşu 17 testten 16 geçti / 1 canlı koşullu atlandı. Native açık/koyu tamamlamanın yerleşim, seçim, insertion/metadata ve odağı; grid’in yatay/dikey scroll, başlık sınırı, kopya/NULL/filtre/sort/page/staged row işaretleri doğrulandı. Güncel izole CUA görüntüsü `/tmp/mssql-070-ui-final.png`; gerçek SQL Server koşulları doğrulanmış sayılmaz.
- ZIP SHA-256 `7018fbb6c7f61264de6098ff1e2b340e330a191c065d680cc514951fc02d750a`; PKG `2081e04a35f6d394449a072ced40e0ad097a1a195b793677258fac8292425be1`; public update.json `7b6cb0273e3792d3f40ea59d2917d0d40ce3ae2897418a3262d2bd439a5a2b9b`. `/tmp/MSSQLStudio-0.2.70-verify` dosyaları GitHub asset digest/public manifest ile eşleşti; iki paketin app/helper strict/deep imzaları, sabit DR/sertifika, 0.2.70/71 metadata, aynı app binary/notlar ve exact helper bytes doğrulandı. Kanıt `/tmp/mssql-070-public-verification.log`.
- Frozen helper archive SHA-256 `75bfb1d347f211607eda75ec2a511d3d3d38e3ffef786fec174cce932c6b5713`, executable `5bdc54f130122075cb1d6204d49d2251f761e60cc4a8110652d1754af1a0f81b`: v0.2.69 pins ile birebir aynı. Kaynak/pin değiştirilmedi, helper yeniden derlenmedi veya imzalanmadı. Gerçek kullanıcı uygulaması/SQL oturumları yeniden başlatılmadı, Keychain/geçmiş/favorilere erişilmedi. Yayın kanıtı main’de ayrı belge commit’iyle kaydedilir; tag taşınmaz.

# SQL tamamlama ve sabit satır numaraları — 12 Ekim 2026 / v0.2.70 hazırlığı

- Tamamlama plain native listesi tür simgeleri, tema renkleri, iki satırlı etiket/detay, eşleşme vurgusu, öneri sayısı ve klavye ipuçlarıyla yenilendi. Typed tür/detay insertion text’i değiştirmez; alias/NOLOCK/prosedür/kolon semantiği aynı kalır. Tek öneride otomatik scroll inset kaynaklı kesilme giderildi; güncel listenin ilk satırı görünür ve eşleşme bitince popup kapanır.
- Sonuç numarası yatay kaydırmadan bağımsız tek painted gutter’dır; ikinci tablo/veri kopyası veya hücre başına view yoktur. Gizli sentetik row kolonu eski ordinal sözleşmesini korur. Numara, seçim ve staged satır işaretleri mevcut kaynak indeksinden okunur; header/scrollbar/bounds dışına çizim engellenir. Scroll yalnız gutter’ı yeniden çizer.
- `/tmp/mssql-070-full-final.log`: **114 app + 138 core = 252 test; 227 geçti, 25 dış koşullu atlandı**. Native test yatay/dikey kaydırma, header sınırı, tık/Shift satır seçimi, kolon taşıma, NULL içeren başlıklı kopya, export indeksleri, filtre/sort/sayfalama, update/delete/new/revert işaretlerini sınar. Öneri testi açık/koyu görünüm, uzun/kısa liste, ilk seçim ve klavye gezinmesi, tooltip/AX, callback’e exact SQL ve editör odağını sınar; core metadata sınıflandırmasını doğrular. Tek öneri scroll görünürlüğü son ilgili test koşusunda ayrıca denetlenir.
- `/tmp/mssql-070-release-final.log`: Release doğrulama kaydı; son kaynakla derleme/yayın sonucu aşağıdaki yayın kanıtıyla tamamlanacaktır. `/tmp/mssql-070-completion-light.png` / dark native liste görüntüleridir. İzole UI CUA görsel kontrolde başlık arkasına taşan numaralar ve tek öneri kesilmesi yakalandı, düzeltildi; son görsel doğrulama ayrıca kaydedilecektir.
- Son kaynakla `/tmp/mssql-070-final-focused.log`: **5 native + 12 core = 17 ilgili test; 16 geçti, 1 canlı koşullu atlandı**. Tek öneri ilk satırının bütünüyle görünmesi ve gutter header/bounds sınırı dahil geçti. `/tmp/mssql-070-release-final.log`: **BUILD SUCCEEDED**. `git diff --check` temiz.
- Güncel binary ile yeniden başlatılan `/tmp/MSSQLStudio-070-ui/MSSQLStudio.app` (`local.mssqlstudio.uitest`) CUA kontrolünde tek tablo önerisinin simge/iki satır/selection/footer’ı kesilmeden göründü; Tab exact `[dbo].[Customers] AS C` ekledi, editör odağı korundu. `EXEC details` prosedür simgeli usp_GetCustomerDetails önerisini açtı; Escape kapattı. Sentetik 6/24 grid yatay Column14+ alanında ve dikey aşağı kaydırıldığında numaralar solda hizalı kaldı, başlık üzerine taşmadı; görünür numara AX çocukları doğrulandı. Son ekran `/tmp/mssql-070-ui-final.png`. Test app’i menüden kapatıldı.
- Gerçek kullanıcı app’i, SQL oturumları, Keychain, geçmiş ve favoriler kullanılmaz/değiştirilmez. Canlı SQL Server testleri çalışmamıştır. Frozen helper kaynak/pin/binary akışı değiştirilmez. Bu hazırlık kaydı CI/public yayın başarısı değildir.

# v0.2.69 yayın ve frozen parola bileşeni doğrulaması — 12 Ekim 2026

- [Public latest v0.2.69](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.69), build 70, kaynak `41f7b47d73d2f5bbb27cb13459fd3a9955ad18b9`. [Actions 38190778855](https://github.com/erhanulas/MSSQLStudio/actions/runs/38190778855) modern XARA partition audit, signed ZIP/PKG/frozen helper archive, manifest, yayın paketi testleri, public latest ve geçici imza kimliği temizliği dahil **başarılıdır**.
- `/tmp/mssql-069-ci-tests.log`: **112 app + 137 core = 249 test; 224 geçti, 25 dış koşullu atlandı**. Yerel tam koşuyla aynı sayım; version/resource sonrası 16 ilgili test ve Release yeniden kontrolü de geçti. İlk GUI onayı, gerçek login keychain kilidi ve canlı SQL Server ortamı doğrulanmış sayılmaz.
- ZIP SHA-256 `955c944a9354dfa60ee3cffddf5751d135280dfbaedf1af25aa65476310b1519`; PKG `53a7b56646c7fda4e28156fcefe5c699e68e3959ce9e9e144e09caafc2c66158`; public update.json `13d8b5877f696a8673eeec97fb651599dce707eaf9663fc6885977a9bebd0802`. İndirilen dosyalar `/tmp/MSSQLStudio-0.2.69-verify` altında GitHub asset digest/public manifest ile eşleşti; app/helper strict/deep kod imzası, sabit DR/sertifika, 0.2.69/70 metadata, iki paketin aynı binary/notları/helper bytes doğrulandı. Kanıt `/tmp/mssql-069-public-verification.log`.
- İlk public `MSSQLStudio-CredentialAgent-v1.zip` SHA-256 `75bfb1d347f211607eda75ec2a511d3d3d38e3ffef786fec174cce932c6b5713`; içindeki executable SHA-256 `5bdc54f130122075cb1d6204d49d2251f761e60cc4a8110652d1754af1a0f81b`. Archive ve ZIP/PKG executable eşitliği doğrulandı; hash’ler `installer/CredentialAgent-v1.json` içinde main’e sabitlendi. Tag taşınmadı.
- `/tmp/mssql-069-reuse-proof.log`: yerel özel anahtar veya derleme olmadan ilk public helper arşivi yeniden indirildi, SHA-256 ve sabit imzası doğrulanıp exact executable üretildi. `/tmp/mssql-069-pinned-verification.log`: hash sabitlemesinden sonra her iki yayın paketinin denetimi yeniden geçti. Gelecek build helper’ı yeniden derlemez/imzalamaz; source/archive/binary uyuşmazlığı build’i durdurur.
- Gerçek kullanıcı uygulaması/SQL oturumları yeniden başlatılmadı veya değiştirilmedi; gerçek Keychain parolaları/profilleri okunmadı, izinler değiştirilmedi. Kök neden incelemesinde yalnız service’e sınırlı ACL metadata okundu. Modern CI audit’in ilk onayı yalnız disposable sentetik item üzerinde simüle edilir; üretim kodu partition-list yazmaz veya oturum parolasını toplamaz.

# Kişisel imza / XARA partition kök nedeni — 12 Ekim 2026 / v0.2.69 hazırlığı

- Kurulu uygulamanın strict/deep codesign ve sabit designated requirement kontrolü geçti. Kullanıcının yalnız `local.mssqlstudio.servers` service’ine ait ACL metadata’sı, UI ve password/data isteği olmadan okundu: iki item, eski derleme yollarına ait trusted-app birikimi ve `ACLAuthorizationPartitionID` içinde `cdhash:` görüldü. Parolalar/profiller/account alanları okunmadı, gerçek kayıtlar veya erişim kuralları değiştirilmedi.
- [Apple securityd clientid.cpp](https://github.com/apple-oss-distributions/Security/blob/main/securityd/src/clientid.cpp) kişisel imzaya değişen CDHash partition’ı verir; [Apple ACL kodu](https://github.com/apple-oss-distributions/Security/blob/main/securityd/src/acls.cpp) trusted-app ACL ve partition’ı ayrı denetler. [Apple DTS açıklaması](https://developer.apple.com/forums/thread/845980) iki koşulun da sağlanmasını doğrular. Önceki sabit DR çözümü ve `/tmp` fixture auditleri tek başına bu sorunu doğrulamıyordu; Apple Keychains.cpp yalnız home Library/Keychains yolundaki legacy keychain’i partition formatına yükselttiğinden eski audit yalancı güvence verebiliyordu.
- Kullanıcı kişisel imzayla devam etmeyi seçti. Üretim ServerVault erişimi (save/list/delete/renew) artık frozen `MSSQLStudioCredentials` üzerinden; helper ve parent pinned DR ile karşılıklı doğrulanır. Private pipe kullanılır; ayrı servis/daemon/elevation/socket yoktur. Kayıtlar aynı service/account/data biçiminde korunur; production partition list yazılmaz. İlk eski item erişiminde macOS onayı gerekebilir; kilitli zincir/sistem politikası veya helper v2 ayrı onay gerektirebilir.
- Eski kayıt silmede Apple SecItemDelete wrapper’ı imza yerine eski app path’i karşılaştırdığı için `errSecInvalidOwnerEdit` yeniden üretildi. Yalnız doğrulanmış parent’ın açık silme isteğinde exact service/account referansı için public SecKeychainItemDelete kullanılır; kalan kayıtlar/ACL/partition değiştirilmez.
- Helper ilk release’te bir kez imzalanır; sonraki release’ler exact signed archive/executable’ı SHA-256 ve imza doğrulayarak tekrar kullanır. Source v1 hash ile dondurulmuştur; yeniden derleme/imzalama yapılmaz. Bootstrap tag dışında pinsiz derleme reddedilir. PKG/ZIP helper bytes/imzası ayrıca denetlenir.
- `pendingInstallerVersion` yalnız canonical /Applications ve tamamlanmış sürüm koşulunda sessizce temizlenir. Başarı NSAlert’i kaldırıldı; eksik kurulum marker’ı korunur. Yeni test eski sürüm/yanlış konum/success/tekrar açılış koşullarını kapsar; imzasız helper isteği veri gönderilmeden reddedilir.
- `/tmp/mssql-069-full.log`: **112 app + 137 core = 249 test; 224 geçti, 25 dış koşullu atlandı**. `/tmp/mssql-069-release.log`: BUILD SUCCEEDED. 12 ilgili test de geçti; canlı SQL ve gerçek kullanıcı GUI Keychain geçişi doğrulanmış sayılmaz. Gerçek kullanıcı uygulaması/oturumları yeniden başlatılmadı veya değiştirilmedi.
- İlk modern auditler [38190468670](https://github.com/erhanulas/MSSQLStudio/actions/runs/38190468670) / [38190587342](https://github.com/erhanulas/MSSQLStudio/actions/runs/38190587342) partition kontrolü, farklı CDHash reddi, helper read/update ve yetkisiz istemci reddini geçti; eski kayıt silmede path-owner hatası nedeniyle başarısız oldular. Düzeltme sonrası [Actions 38190703445](https://github.com/erhanulas/MSSQLStudio/actions/runs/38190703445) **başarılıdır**: modern partition varlığı, kontrol amaçlı doğrudan farklı CDHash reddi, frozen helper ile eski/fresh item create/read/update/delete, farklı build/path ve yetkisiz launcher/ad-hoc istemci reddi doğrulandı. İlk user approval yalnız sentetik service/account partition girdisinde simüle edilir; gerçek GUI onayı değildir. CI/public yayın sonucu henüz bu hazırlık kaydının parçası değildir.
- Son version/resource sonrası `/tmp/mssql-069-metadata.log`: 16 ilgili test geçti; `/tmp/mssql-069-release-final.log`: BUILD SUCCEEDED. `git diff --check` temiz.

# v0.2.68 yayın doğrulaması — 12 Ekim 2026

- [Public latest v0.2.68](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.68), build 69, kaynak `ebaa6c5ce95b9ee643a1a4c4fec9b4d0d654fd90`. [Actions 38188169616](https://github.com/erhanulas/MSSQLStudio/actions/runs/38188169616) kalıcı imza/izole Keychain, signed ZIP/PKG, manifest, paket testleri, public yayın ve geçici kimlik temizliği dahil başarılıdır.
- `/tmp/mssql-068-ci-tests.log`: **112 uygulama + 135 core = 247 test; 222 geçti, 25 dış koşullu test atlandı**. Yeni 8 kaynak SQL/native hover testi gerçek yayın paketleriyle de geçti. Son tam yerel koşu aynı sayımla başarılıdır; son çoklu EXEC negatif denetimi ve Release yeniden kontrolü ayrıca geçti. Canlı SQL Server kaynak testi ortam bilgisi olmadığından atlandı; gerçek sunucu koşulları doğrulanmış sayılmaz.
- İndirilen ZIP SHA-256 `154a6084501a35cbd0cbc98531e61af61d428b220159c5faefb402e47066f535`; PKG SHA-256 `24c40afde5961259b3489afc04fce2e18a041683671b37a6024cabc57f3bbee5`. Dosyalar `/tmp/MSSQLStudio-0.2.68-verify` altında public update.json ve GitHub asset digest ile eşleştirildi. Manifest digest `d67ab6b2460ff021394a060abc5a9519b0f6b368223440a7083b659467c4d825` ayrıca doğrulandı.
- `scripts/prepare-release.py` indirilen her iki paketin uygulaması için strict/deep codesign, sabit sertifika/DR, bundle ID, 0.2.68/69 sürümü ve aynı binary/metadata/sürüm notlarını doğruladı; yeniden oluşturulan manifest public manifestle aynıdır. Kanıt: `/tmp/mssql-068-public-verification.log`. Kurulu kullanıcı uygulaması/SQL oturumları/Keychain/favoriler/geçmiş değiştirilmedi. Native görsel kanıtlar ve güvenli eşleştirme sınırları aşağıdaki hazırlık kaydındadır.

# Results sekmelerinde kaynak SQL — 12 Ekim 2026 / v0.2.68 hazırlığı

- Results ve plan sekmeleri `Rows.source` yürütme snapshot'ından kaynak SQL yardımını gösterir; editörde sonradan değişen metinle yeniden eşlenmez. TSQL.run streaming sırasında batch bağlamını, finalde sonuç sayısı eşleşen bilinen düz SELECT/CTE/UNION dizilerinde ayrı statement metnini taşır. GO tekrarlarının grup numarası ayrıdır; affected-row token'ları sıra eşleşmesini kaydırmaz. SQL yürütmesi bölünmez veya tekrar çalıştırılmaz; sayısal/NULL/spool/export değerlerine dokunulmaz.
- Tek EXEC/EXECUTE çağrısının çoklu sonuçları çağrı SQL'ini paylaşır. Koşul/döngü/DML/prosedür karışımı veya beklenmeyen rowset sayısında kesin statement iddiası yerine kaynak SQL grubu gösterilir. ODBC'nin bir prosedürden birden fazla rowset/rowcount döndürmesi nedeniyle salt ordinal tahmini yapılmaz; [Microsoft multiple results](https://learn.microsoft.com/en-us/sql/odbc/reference/develop-app/multiple-results?view=sql-server-ver17). Bu sınıflandırma tam T-SQL parser değildir; >250.000 UTF-16 kaynakta ek analiz yerine grup bağlamı kullanılır.
- Sekme hover'ı ortak 200 ms yordamla nonactivating, SSMS renkli SQL paneli açar. Ekran içinde yukarı/aşağı yerleşir; fare ayrılınca, tıklayınca, kaynak değişince veya sekme kaldırılınca kapanır. Native tooltip/AX yardımında aynı açıklama vardır. Önizleme 2.000 karakter/20 satırla sınırlıdır; orijinal SQL yalnız bellekte korunur. Messages sekmesine yanlış SQL atanmaz.
- `/tmp/mssql-result-source-focused.log`: 2 native + 6 core = 8 yeni test geçti. Literaller/yorumlar/nested SELECT, semicolonsuz SELECT, CTE/UNION, değişken ataması/TOP/SELECT INTO/NOCOUNT, prosedür/koşullu grup, beklenmeyen sayı, plan/affected token, GO tekrarları/streaming, uzun kaynak, editör değişiminde snapshot ve metadata güncellemesi doğrulandı. Native hover açık/koyu SSMS renklerini, ekran sınırını, giriş/çıkış ve kaynak değişiminde iptali doğruladı; `/tmp/mssql-result-source-hover-light.png` ve `...-dark.png` görsel olarak incelendi.
- `/tmp/mssql-068-full.log`: **112 uygulama + 135 core = 247 test; 222 geçti, 25 dış koşullu atlandı; hata yok**. Release derlemesi başarılıdır. Canlı GO testi kaynak SQL/grup kimliği beklentileriyle genişletildi; ortam bilgisi olmadığı için atlandı ve gerçek SQL Server kanıtı sayılmaz. Native UI testleri sentetik verilerle çalıştı; kurulu kullanıcı uygulaması/Keychain/history/favoriler/SQL oturumları kullanılmadı.
- Son çoklu EXEC belirsizlik kontrolü sonrası `/tmp/mssql-068-source-final.log`: 6 core test geçti; `/tmp/mssql-068-release-final.log`: BUILD SUCCEEDED. `git diff --check` temiz.
- Kullanılmamış v0.2.68 / build 69 sürümü ve 12 Ekim 2026 notları hazırlandı. AGENTS.md mimari/davranış kuralı güncellendi; public yayın doğrulaması tamamlandığında ayrıca kaydedilecektir.

# v0.2.67 yayın doğrulaması — 12 Ekim 2026

- [Public latest v0.2.67](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.67), build 68, kaynak `402231c43febb07d8189f26c323b0a0c68da9eb0`. [Actions 38183331282](https://github.com/erhanulas/MSSQLStudio/actions/runs/38183331282) kalıcı imza/izole Keychain, signed ZIP/PKG, manifest, paket testleri, public yayın ve geçici kimlik temizliği dahil başarılıdır.
- `/tmp/mssql-067-ci-tests.log`: **110 uygulama + 129 core = 239 test; 214 geçti, 25 dış koşullu test atlandı**. Son tam yerel koşuyla aynı sayım geçti. Sonuç başına okuma ve GO devamı, 6 → 2 sekme temizliği/plan/refresh/native kontrolleri ve önceki favori/Formatla/EXEC/popup geliştirmeleri bu sürümdedir. Canlı SQL Server testleri ortam bilgisi olmadığı için atlandı; doğrulanmış sayılmaz.
- İndirilen ZIP SHA-256 `852daf966184e915bd7bf043f99d5824a5453df51383a2b9a2407fe296c41c99`; PKG SHA-256 `8261f1c7d189e0b52134b2548cbab61230f32d89fdd94d2dfcd0add66500d627`. Dosyalar `/tmp/MSSQLStudio-0.2.67-verify` altında public update.json ve GitHub asset digest ile eşleştirildi. Manifest digest `38257d7d7838e839d528cb3910305744a100cb2ab8f53a0dbe14ed387640be8d` ayrıca doğrulandı.
- `scripts/prepare-release.py` indirilen her iki paketin uygulaması için strict/deep codesign, sabit sertifika/DR, bundle ID, 0.2.67/68 sürümü ve aynı binary/metadata/sürüm notlarını doğruladı; yeniden oluşturulan manifest public manifestle aynıdır. Kanıt: `/tmp/mssql-067-public-verification.log`. Kurulu kullanıcı uygulaması/SQL oturumları/Keychain/favoriler/geçmiş değiştirilmedi. Yerel/native/CUA kapsamı ve sınırları aşağıdaki tarihli kayıtlardadır.

# v0.2.67 yayın hazırlığı — 12 Ekim 2026

- Sürüm 0.2.67 / build 68 hazırlandı; origin/main ile başlangıç HEAD aynıydı ve v0.2.67 etiketi yerelde/uzakta kullanılmamıştı. Favori/popup/EXEC/Formatla geliştirmeleri, sonuç başına okuma sınırı ve eski sekme temizliği birlikte yayımlanacak.
- Sürüm/resource güncellemesi sonrası `/tmp/mssql-067-release-metadata-tests.log`: 6 ilgili test geçti; `/tmp/mssql-067-publish-release.log`: BUILD SUCCEEDED.
- Son tam yerel koşu: 239 test; 214 geçti, 25 dış koşullu atlandı. Release derlemesi ve ilgili native/CUA kontrolleri aşağıda kayıtlıdır. Bu hazırlık kaydı CI veya public yayın başarısı değildir.

# Yeni çalıştırmada eski sonuç sekmelerinin temizlenmesi — 12 Ekim 2026 (yerel geliştirme)

- Kullanıcının 6 sonuçtan sonra 2 sonuç çalıştırınca eski dört sekmenin kalması senaryosu native AppKit testinde yeniden üretildi. Kök neden temizliğin yalnız `document.results.isEmpty` ara durumuna bağlı olmasıydı; 50 ms streaming debounce bu ara durumu atlayabiliyor, normal yürütme sonunda eksik sekmeler de budanmıyordu. Eski plan önbelleği aynı ordinalde yeni grid'in açılmasını da engelleyebiliyordu.
- QueryController yeni resultGeneration sınırını debounce dışında hemen işler; normal Çalıştır önceki grid/plan sekmelerini, child controller'larını ve plan önbelleğini temizler. Doğrudan update yolunda da generation kontrolü vardır; boş ara durum çizilmeden yeni iki sonuç gelse bile yalnız güncel ikisi + Messages kalır. Sekme şeridi yatay kaydırması yeni çalıştırmada başa döner; ilk yeni sonuç seçilir.
- Yürütme tamamlandığında görünür sonuç ordinal kümesinin dışında kalan hem grid hem plan sekmeleri kaldırılır; affected-row/PRINT gibi rowset üretmeyen çıktı Messages gösterir. Yenileme sırasında önceki snapshot, mevcut grid kimliği/seçimi/kolon genişlikleri korunur; bitince artık olmayan sekmeler temizlenir. Aynı çalıştırmanın devam eden streaming güncellemeleri o çalıştırmanın grid'lerini yeniden oluşturmaz.
- `/tmp/mssql-result-replacement-before.log`: eski kodla iki yeni regresyon testi başarısız oldu (6 → 2 ve plan/affected-row geçişi); düzeltmeden sonra `/tmp/mssql-result-replacement-focused.log`: ilgili 23 native test geçti.
- Son kaynak/testlerle `/tmp/mssql-result-replacement-full.log`: **110 uygulama + 129 core = 239 test; 214 geçti, 25 dış koşullu atlandı; başarısız test yok**. Dört yeni native test hızlı 6 → 2, plan → grid → yalnız Messages, yenilemede eski grid/plan budama ve kolon genişliği/seçim korunması, debounce öncesi eşzamanlı temizleme + aynı yürütmede yeni sekme eklenmesini doğruladı. Bu testlerde ODBC handle bağlı değildir; gerçek kullanıcı sunucusu/verisi veya Keychain kullanılmadı. Canlı SQL Server testi doğrulanmış sayılmaz.
- `/tmp/mssql-result-replacement-release.log`: **BUILD SUCCEEDED**. `git diff --check` temiz. AGENTS.md sonuç yaşam döngüsü kuralı güncellendi. Önceki yerel değişiklikler korundu; yeni sürüm/tag/paket yayımlanmadı ve kurulu kullanıcı uygulaması değiştirilmedi.

# Çoklu SQL sonuçları ve okuma sınırı — 12 Ekim 2026 (yerel geliştirme)

- Kullanıcı ilk sonucun okuma sınırına ulaştığını doğruladı. Kök neden ODBC'de bütün rowset'ler için ortak `totalRows` sayacı ve sınırda SQLCancelHandle çağrısı; GO yürütmesinde de satır bütçesinin azaltılması ve her partial durumda durulmasıydı. İkinci SELECT'e ulaşılmadığından görünümde oluşturulacak ikinci sonuç yoktu.
- Satır okuma sınırı artık her rowset'e ayrı uygulanır. Sınırda okunmamış satırlar SQLMoreResults ile bırakılır ve sonraki sonuç açılır; GO batch'lerine aynı satır limiti taşınır. Byte/hücre/sonuç sayısı ve mevcut timeout korumaları korunur. Microsoft davranış referansı: [ODBC multiple results](https://learn.microsoft.com/en-us/sql/odbc/reference/develop-app/multiple-results?view=sql-server-ver17).
- `Rows.truncated` eksik sonucu, `Execution.stoppedEarly` hata/iptal/ortak bütçe nedeniyle kalan sonuçların durdurulduğunu ayırır. `Execution.partial` önceki sınırlanmış sonucu sonraki başarılı batch'te kaybetmez. Sınırlanan Results sekmesi KISMİ olur; tam ikinci/üçüncü grid kısmi etiketi veya satır sayısında + göstermez. Genel sorgu kısmi durumu ve düzenleme güvenlik denetimleri korunur. Okuma seçicisi/form/tooltip sonuç başına uygulandığını açıklar.
- `/tmp/mssql-multi-results-full.log`: **106 uygulama + 129 core = 235 test; 210 geçti, 25 dış koşullu atlandı; başarısız test yok**. GO/GO tekrarında bağımsız satır sınırı, ortak byte/result-set bütçesi, DML token'larıyla event indeksleri, partial birikimi, son batch tam bütçedeyken yanlış partial oluşmaması, hata/Task cancellation sonrası devam edilmemesi sınandı. Native test akan üç rowset (boş SELECT/NULL/exact numeric dahil), sekmelere tıklama ve çok sayıda sekmede yatay kaydırmayı doğruladı.
- Son grid kısmi göstergesi düzeltmesinden sonra `/tmp/mssql-multi-results-final.log`: **24 uygulama + 5 core = 29 ilgili test geçti**. `/tmp/mssql-multi-results-release-final.log`: **BUILD SUCCEEDED**. Canlı test ilk sınırdan sonra GO, aynı statement içinde çoklu SELECT/dinamik EXEC, boş sonuç, disk spool, byte hatası ve bağlantı yeniden kullanımını kapsayacak şekilde güncellendi/eklendi; MSSQL_TEST_PASSWORD olmadığı için çalışmadı ve canlı SQL Server doğrulaması sayılmaz.
- İzole `/tmp/MSSQLStudio-multi-results-ui/MSSQLStudio.app` (`local.mssqlstudio.uitest`, StudioMultiResultSmoke) CUA kontrolünde `Results 1 (10) · KISMİ`, `Results 2 (1)`, `Results 3 (1)` aynı sırada görünür. İkinci sekme NULL/Missing, üçüncü sekme 2/Last gösterdi. Son derlemede üçüncü grid `1–1 / 1` gösterdi ve Kısmi sonuç etiketi yoktu. Bu UI fixture sentetiktir; ağdan alınan sonuç kanıtı değildir. İzole test uygulaması kapatıldı; gerçek uygulama/oturum/Keychain/geçmiş/favoriler kullanılmadı.
- AGENTS.md davranış kuralı güncellendi. Yerel geliştirmedir; yeni sürüm/tag/paket yayımlanmadı, önceki yerel favori/popup/Formatla değişiklikleri korundu.

# Favoriler, SQL Formatla ve popup gezinmesi — 12 Ekim 2026 (yerel geliştirme)

- Favori Explorer sağ tık menüsü Aç / Düzenle / onaylı Sil sunar. Native eylem testi aynı UUID ile düzenleme formunu açtı; silmeyi iptal etmek kaydı korudu, onaylamak kaldırdı ve açık SQL değişmeden/çalıştırılmadan kaldı. Yıldız SQL + görünür kapsam eşleşmesinde dolu; tekrar tıklama yalnız o kaydı kaldırır. Diğer açık query controller yıldızları aynı bildirimle yenilenir. Başka DB/UUID ve farklı literal harfleri eşleşmez; dış whitespace aynı SQL sayılır.
- Favori düzenleyicisi/tarayıcı DB picker kullanır. Ayrı katalog listesi Explorer filtresinin gizlediği DB'leri de sunar; çevrimdışı/kısmi/hata ve mevcut-listede-yok seçimleri korunur. Native CUA listesinde DemoDB / master / Reporting doğrulandı; elle DB giriş alanı kaldırıldı. Seçim başka bağlantıya geçince açıkça profil varsayılanına döner.
- StudioPopover native ölçüyü sabitler, görünür anchor'ı pencere koordinatına çevirir ve uygun yukarı/aşağı alanı hesaplar. Kolon araması, filtre, yükleme/refresh ve indeks popup'ları ortak yolu kullanır; autocomplete caret yolu korunur. Kolon aramasında seçili satır, eşleşme sayısı, ↑/↓/Enter/Esc/Kapat ve kaydırma vardır. Hedef başlık kalın/renkli/alt çizgili ve AX yardımında adlandırılmıştır; yeni sonuçta temizlenir. Gizli/taşınmış kolon ordinali, kaynak değerleri ve satır seçimini koruyan test geçti.
- EXEC/EXECUTE prosedür tamamlama ad içinde eşleşir; prefix önce gelir, schema/return assignment desteklenir. Ayrı prosedür indeksi 500 benzer tabloyu geçerek doğru önerileri bulur; literal/comment/dinamik EXEC değişkeni/başka DB negatifleri ve 100 öneri sınırı korunur. CUA'da `EXEC customer` → `[dbo].[usp_GetCustomerDetails]` önerildi ve SQL çalıştırılmadı.
- Formatla tam native replacement sonrası foreground önbelleğini geçersizleştirip hemen renklendirir; aynı metni yeniden atamaz. İlk/repeat/undo/redo ve açık/koyu temada keyword/function/string/comment/system/plain/operator/procedure kategorileri doğrulandı. TextKit 2 ve SQL baseline/undo korunur. Toolbar/menü adı Formatla oldu.
- `/tmp/mssql-067-full.log`: **105 uygulama + 123 core = 228 test; 204 geçti, 24 dış koşullu test atlandı; hata yok**. Son seçili satır kontrast düzeltmesi sonrası `/tmp/mssql-067-popover-final.log`: ilgili 27 test geçti; native sağ tık edit/sil onay/iptal testi eklendikten sonra `/tmp/mssql-067-favorites-final.log`: 13 test geçti. Son kaynakla `/tmp/mssql-067-release.log`: **BUILD SUCCEEDED**. `git diff --check` temiz.
- İzole `/tmp/MSSQLStudio-polish-ui/MSSQLStudio.app`, `local.mssqlstudio.uitest`, PID 81895: kompakt 6×24 fixture ile koyu Kolona Git yukarı düzgün açıldı; Column2 aramasında Down/Enter ile Column21'e gidildi, başlık vurgusu ve AX `Gidilen kolon: Column21` doğrulandı. Yeniden açıp hemen yazmak ve Esc ile kapatmak geçti. Formatla sonrası çok renkli SQL görsel olarak korundu. Favori master kapsamına kaydedildi, yıldız doldu ve tekrar tıklamayla kayıt kaldırılıp yıldız boşaldı; sağ tık menü içeriği görüldü. CUA native menü komutlarına tıklamada odak/yeniden durum uyarısı verdiği için edit/sil eylemlerinin tamamlandığı CUA kanıtı sayılmadı; bu eylemler native selector + modal onay/iptal testiyle doğrulandı. CUA paste yordamı ilk popup girişinde ana editöre döndü; doğrudan yazma, odak ve klavye gezinmesi ayrıca geçti.
- Gerçek kullanıcı uygulaması/Keychain/favoriler/geçmiş veya SQL Server verisi kullanılmadı; UI süreci yalnız kendi PID'siyle kapatıldı. Canlı SQL Server yetkileri/gerçek katalog ve kullanıcı kurulum yükseltmesi doğrulanmış sayılmaz. Bu kayıt yerel geliştirmedir; yeni sürüm/tag/paket yayını yapılmadı. Son public yayın v0.2.66'dır.

# v0.2.66 yayın doğrulaması — 11 Ekim 2026

- [Public latest v0.2.66](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.66), build 67, kaynak `02a79c3abd8ec249d9992572eb9a4b55f866163c`. [Actions 38167209575](https://github.com/erhanulas/MSSQLStudio/actions/runs/38167209575) imza/izole Keychain, signed ZIP/PKG, manifest, paket testleri, public yayın ve geçici kimlik temizliği dahil başarılıdır.
- `/tmp/mssql-066-ci-tests.log`: **99 uygulama + 122 core = 221 test; 197 geçti, 24 dış koşullu test atlandı**. Yerel tam koşu da aynı sayımla başarılı. Yeni Explorer seçim/kimlik/no auto-run, editör yıldızı, ortak read/page menüsü ve refresh guard beklentileri korunarak geçti.
- Public ZIP SHA-256 `df2116a5889c79a16d1b6080697e91b91acf7a031e72165ffcedb301ddc30040`; PKG SHA-256 `10b83faa860bc99722846901676b9711cf47ba906ee35120d4f3848f5d3ba2be`. Her iki dosya `/tmp/MSSQLStudio-0.2.66-verify` altına indirilip update.json ve GitHub asset digest ile eşleştirildi. Manifest digest `3185d61e2f7bc7279b86b1051c9ba92a1f8379d30c592cf3468f41b31aa13260` ayrıca doğrulandı.
- `scripts/prepare-release.py` indirilen her iki paketin uygulaması için strict/deep codesign, sabit sertifika/DR, bundle ID, 0.2.66/67 sürümü ve aynı binary/metadata/sürüm notlarını doğruladı; yeniden oluşturulan manifest public manifestle aynıdır. Kanıt: `/tmp/mssql-066-public-verification.log`. Kullanıcının kurulu uygulaması/SQL oturumları/Keychain/favoriler/geçmiş dosyaları değiştirilmedi. Native CUA kanıtı ve test sınırları aşağıdadır.

# v0.2.66 geliştirme doğrulaması — 11 Ekim 2026

- Explorer yerel Favori Sorgular dalını Genel / Bu Bağlantı / tam DB adı gruplarıyla gösterir. Çift tıklama çevrimdışı da doğru hedefte yeni sorgu açar; otomatik SQL/yeniden bağlantı yapmaz. Kaydet/düzenle/sil node kimliği, seçim ve genişletmeyi korur. Editör yıldızı kendi belge SQL/ad/DB/UUID'sini favori formuna taşır; boş SQL'de pasiftir ve detached aynı controller'ı kullanır.
- Sayfa boyutu ve okuma sınırı tek native menüde hazır/özel seçimlerle birleştirildi. Sayfalama mevcut snapshot'ı, okuma sınırı sonraki yürütmeyi etkiler. Ayrı auto-refresh düğmesi hazır/özel süre ve kapatma sunar; ilk başarılı tekrar okunabilir SELECT'i bekler, düzenleme/busy/transaction güvenliği korunur. Popover'lar animasyonsuzdur; eski varsayılan anahtarları değişmedi.
- `/tmp/mssql-066-full.log`: **99 uygulama + 122 core = 221 test; 197 geçti, 24 dış koşullu test atlandı**; başarısız test yok. İlk ilgili koşuda favori güncellemesi seçim kaybını yakaladı; node kimliği korunurken native reload sonrası seçimi geri yükleme düzeltildi, tam koşuda geçti. Yeni kontroller scope/UUID/DB hedefi/no auto-run, yerel ağaç yenileme/selection/expansion, yıldızın belge kimliği/boş SQL, ortak menü preset/custom ve read/page bağımsızlığı, refresh pending/custom/kapalı/busy/editing guards'ını kapsar.
- `/tmp/mssql-066-release.log`: Release **BUILD SUCCEEDED**, v0.2.66/build 67. `git diff --check` temiz. Sonuç araçları düzenleme açıkken 830/1280 pt açık/koyu temada aynı sırada ve görünür; genel çalışma alanı/form yerleşimi testleri de geçti.
- İzole `/tmp/MSSQLStudio-favorites-ui/MSSQLStudio.app`, `local.mssqlstudio.uitest`, PID 46531 native CUA: boş editörde yıldız pasif; SQL yazınca aktif; yıldızdan adlandırılmış master kapsamlı favori kaydedildi. Explorer Favori Sorgular/master altında anında göründü; çift tıklama SQL'i yeni sekmede açtı ve Disconnected/0 rows/0.000 s kaldı. Okuma menüsünden 100.000 seçildi; refresh 10 sn ardından özel 17 sn seçildi ve başarılı SELECT'i beklediği tooltip/AX değerinde doğrulandı. Ortak özel formdan okuma 125.000 / sayfa 77 / refresh kapalı uygulandı; toolbar 77 · 125k ve Kapalı olarak güncellendi. Gerçek kurulu app, Keychain, mevcut favoriler/geçmiş ve SQL Server verisi kullanılmadı. Bu test süreci yalnız kendi PID'siyle kapatıldı.
- Public imzalı paket/CI doğrulaması üstte kaydedilmiştir. Canlı SQL Server/izin ve gerçek kullanıcı güncellemesi test edilmiş sayılmaz.

# v0.2.65 yayın doğrulaması — 11 Ekim 2026

- [Public latest v0.2.65](https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.65), build 66, kaynak `b53675694d533df71d485102b0132b3670679f86`. [Actions 38163928401](https://github.com/erhanulas/MSSQLStudio/actions/runs/38163928401) bütün adımlarıyla başarılı: sabit imza/izole Keychain, signed ZIP/PKG, manifest, paket testleri ve public yayın tamamlandı.
- `/tmp/mssql-065-ci-tests.log`: **96 uygulama + 122 core = 218 test; 194 geçti, 24 dış koşullu test atlandı**. v0.2.64 paket testinde bulunan altı viewport ve bir field editor beklentisi korunarak geçti. Yerelde `/tmp/mssql-065-full.log`: 195 geçti / 23 dış koşullu atlandı; Release `/tmp/mssql-065-release.log` başarılı. Yerel ve CI farklı koşullu test ortamları ayrı sayıldı.
- Public ZIP SHA-256 `691730fd811c0de984b47f479583c2336cdfa342c9a459306367f6cb886903ce`; PKG SHA-256 `6da8fac7fc732834256d02ac3e364592a7d0900c0d5acacf6d3b82df3b714a91`. Her ikisi indirilen update.json ve GitHub asset digest ile eşleşti. Manifest digest `c262831c35ad9818bfe5e0eb41b59f3aaf59792867889b9134c7bfbcf4a001b9` ayrıca doğrulandı.
- `/tmp/MSSQLStudio-0.2.65-verify` içindeki public paketler `scripts/prepare-release.py` ile strict/deep codesign, sabit sertifika/DR, bundle ID, 0.2.65/66 sürümü, aynı uygulama binary/metadata ve sürüm notları açısından doğrulandı. Yeniden üretilen manifest public manifestle aynı. Kanıt: `/tmp/mssql-065-public-verification.log`.
- Yeni işlevlerin native CUA kanıtı ve ölçüm/favori/veri bütünlüğü test kapsamı aşağıdadır. v0.2.64 açılmadı; etiketi taşınmadı. Kullanıcının kurulu uygulaması, açık SQL oturumları, Keychain, mevcut favori/geçmiş dosyaları ve DB değiştirilmedi. Canlı SQL Server/izin koşulları test ortamı tanımlı olmadığı için doğrulanmış sayılmaz.

# v0.2.64 paket testi engeli ve v0.2.65 hazırlığı — 11 Ekim 2026

- Kaynak `e55bfca4bcb98df532bb4bf04e12540af147d299`, Actions `38163380845`: imza/izole Keychain, signed app/PKG ve manifest geçti; paket testleri yedi beklentide başarısız oldu. Public yayın adımı atlandı; v0.2.64 yayımlanmadı ve etiketi taşınmadı.
- `/tmp/mssql-064-ci-tests.log`: 122 core testi başarılı; 96 uygulama testinde iki test başarısız. Altı boyut beklentisinde CI masaüstü tüm pencereleri 642 pt görünür yüksekliğe küçülttü (beklenen 700/660). Mantıksal viewport testleri artık ekran dışında istenen boyutta çizilir; gerçek AppKit kontrol sınırları ve iki tema beklentileri korunur. Bu pencereler başka suite’in native field editor odağını da çalamaz.
- Untouched grid editor testinin 50 ms beklemesinde başka UI suite pencere açarak odağı değiştirdi; firstResponder nil geldi. Native editColumn eşzamanlı olduğu için test key pencereyi açıkça seçer ve araya async bekleme koymadan içerik/iptal/undo davranışını kontrol eder. Ürün davranışı veya beklenti kaldırılmadı.
- v0.2.65 / build 66 yerel doğrulama: `/tmp/mssql-065-full.log` **96 uygulama + 122 core = 218 test; 195 geçti, 23 dış koşullu atlandı**; `/tmp/mssql-065-release.log` Release **BUILD SUCCEEDED**. Yedi beklentinin tamamı korundu ve geçti. `git diff --check` temiz. v0.2.64 geliştirme kayıtları aşağıda tarihsel kanıttır.

# v0.2.64 geliştirme doğrulaması — 11 Ekim 2026

- Çalıştır native hücresine 10 pt yatay / 3 pt dikey içerik boşluğu eklendi. Ana/detached ortak bileşen, ikon/metin, tooltip ve erişilebilir ad korunur.
- Sunucu Activity Monitor dört Swift Charts grafiği, örnek tablosu, 5/10/30/60 sn yenileme, duraklatma/elle yenileme ve normal sorguda aktif istek izleme sunar. İzleme ayrı metadata bağlantısında ve sınırlı bellekte kalır. Hızlar ardışık sayaç farkı / sunucu zamanı ile hesaplanır; izin/eksik veri/restart/geri giden zaman/kesinti sıfır gösterilmez. Pencere kapanması/minimize/tam örtülme otomatik örneklemeyi durdurur.
- Favori sorgular isim + SQL + genel/Explorer UUID/DB kapsamıyla atomik yerel depoda saklanır. Kapsam filtreleme, ad arama, düzenleme/silme ve doğru hedefte otomatik yürütmeden açma eklendi. Okuma sınırı tek görünür sonuç kontrolüne taşındı; Ayarlar Sonuçlar sekmesi ve sayfa menüsündeki yinelenen okuma sınırı kaldırıldı. Eski varsayılan anahtarları ve güvenli refresh koşulları korunur.
- `/tmp/mssql-feature-full-final.log`: **96 uygulama + 122 core = 218 test; 195 geçti, 23 dış koşullu test atlandı**. İlk tam koşuda tek hata eski sayfa menüsünün kaldırılan okuma sınırı alt menüsünü bekleyen testti; bu test tek görünür kontrolü ve sayfa/okuma ayrımını doğrulayacak şekilde güncellendi. Son tam koşu başarılı.
- Son favori açma pencere odağı düzeltmesinden sonra `/tmp/mssql-feature-focus-final.log`: **14 uygulama + 8 core = 22 ilgili test geçti**. Yeni testler scope/target/SQL baseline/no auto-run, bozuk depoyu koruma, atomik persist/update/remove, dosya izni, eksik/partial DMV decode, rate/reset, hata sonrası geçmiş/sequence, görünür okuma sınırı ve minimum form yerleşimlerini kapsar.
- Native yerleşim testleri: Activity 920×700, favoriler 900×660, editör 720×660 açık/koyu; grid toolbar 830/1280, çalışma alanı 1060/1920 ve 1100/1440 kontrolleri geçti. `/tmp/mssql-{activity,favorites,favorite-editor}-{light,dark}.png` rasterleri üretildi; Activity/favori editör açık rasterleri incelendi. Dar segmented etiket sarılması düzeltildi. Rasterler tek başına CUA yerine sayılmadı.
- Ayrı `/tmp/MSSQLStudio-activity-ui/MSSQLStudio.app` / `local.mssqlstudio.uitest` ile CUA: koyu dört grafik, duraklat/sürdür, örnek tablosu ve elle örnekleme doğrulandı; I/O ve batch oranları oluştu. Sonuç popover’ında 50.000 → 125.000 değişikliği başlıkta görüldü. İsimli DB favorisi kaydedildi, listede seçildi ve SQL/DB hedefi önizlemede doğrulandı. Sheet açılışı sırasında bir geçici AXError sonraki taze ağaç okumasıyla çözüldü. Gerçek Keychain/restore/history/favoriler/network öncesi fixture kullanıldı; canlı SQL Server izin/DMV koşulları doğrulanmış sayılmaz.
- Son görünür DB etiketi/liste genişliği düzenlemesinden sonra `/tmp/mssql-feature-ui-final.log` 5/5 native özellik testini geçti. Release `/tmp/mssql-feature-release-publish.log`: **BUILD SUCCEEDED**; mevcut EditorView actor izolasyonu uyarısı bu turda eklenmedi. Yayın ve indirilen imzalı paket doğrulaması tamamlanınca ayrı kayıt eklenir. Kullanıcının kurulu uygulaması ve SQL oturumları değiştirilmedi.

- Yayına gönderilen son kaynak `e55bfca4bcb98df532bb4bf04e12540af147d299` yeniden izole CUA uygulamasında açıldı. Görünür DB etiketi ve daraltılmış favori listesi doğrulandı. DB favorisi kaydedilip Sorguda Aç seçildiğinde ana pencere öne geldi; sekme adı, `SELECT 123;`, master hedefi ve Disconnected / 0 rows / 0.000 s durumu doğrulandı. Ayarlar native tab grubunda yalnız altı sekme bulundu; Sonuçlar yok. Bu tur sheet/pencere geçişlerinde CUA’nın geçici AXError yanıtları taze ağaç okumalarıyla çözüldü. İzole test uygulaması sonlandırıldı.

# v0.2.63 yayın doğrulaması — 11 Ekim 2026

- Public latest: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.63; build 64, kaynak `f8d56e06e170f5a1119852a3d36ca3347953390a`. Actions `38103401163` tüm adımlarıyla başarılı: kalıcı imza/izole Keychain, signed app/PKG, manifest, gerçek paketlerle test ve public yayın tamamlandı.
- `/tmp/mssql-063-ci-success-tests.log`: **91 uygulama + 114 core = 205 test; 181 geçti, 24 dış koşullu test atlandı**. Paket testinin önce bulduğu fark önizleme tema regresyonu genişletilerek geçti. Yerel test ve görsel kontrol kapsamı/sınırları aşağıdadır.
- İndirilen ZIP SHA-256 `38af059c6717d401501108ec46053c3b79b081ac009c071dfe5da047898c5be5`; PKG SHA-256 `4d79e464f6f0de11deffdeed5f4f3f6f8295dacf46d36b58ce007e255782ce06`. Her ikisi public GitHub digest ve update.json ile eşleşti; manifestin kendi digest'i de doğrulandı.
- prepare-release.py `/tmp/MSSQLStudio-0.2.63-verify` altındaki public ZIP/PKG için strict/deep codesign, sabit sertifika/DR, bundle ID, sürüm, aynı binary/metadata ve sürüm notlarını doğruladı. Uygulamanın 0.2.63/64 bilgisi ayrıca doğrulandı; üretilen manifest public manifestle aynı.
- İzole UI fixture sonlandırıldı. Kullanıcının kurulu uygulaması, açık SQL oturumları, Keychain ve veritabanı değiştirilmedi. Canlı SQL Server koşulları doğrulanmış sayılmaz; CUA servis kesintisi nedeniyle bütün yönetim formları yeniden gezilmedi.

# v0.2.62 CI hatası ve önizleme tema düzeltmesi — 11 Ekim 2026

- Kaynak `06ce5b70dbd38e8a651140ad2b2de5f8e495d614`, Actions `38103019195`: imza/izole Keychain, signed app/PKG üretimi ve manifest doğrulaması geçti; paket testleri ManagementWorkspaceTests içindeki dört renk beklentisinde başarısız oldu. Public latest v0.2.61 kaldı; v0.2.62 yayımlanmış sayılmaz ve etiketi taşınmadı.
- `/tmp/mssql-062-ci-failure-tests.log` mevcut GitHub kimliğiyle okundu. Fark panelleri hazırlandıktan sonra tema değişirken çalıştırılacak SQL paneli önceki paleti koruyordu. ModuleReviewController artık StudioTheme.changed bildiriminde hem hizalı diff satırlarını hem çalıştırılacak SQL'i yeniler. Diff zemini, metin, seçim, viewport ve açık gönderim onayı korunur; karşılaştırma yeniden hesaplanmaz.
- Regresyon testi açık–koyu–açık geçişinde üç gerçek TextKit 2 alanının syntax/unused renklerini, editör zeminini, aynı metin/seçim/viewport'u ve yalnız düğmeye tıklayınca gönderimi kontrol eder. `/tmp/mssql-063-review-regression.log`: **1/1 geçti**. Eski yapay 100×10 ms bekleme yerine en fazla 2 saniye hazır durum beklenir.
- `/tmp/mssql-063-final-tests.log`: **91 uygulama + 114 core = 205 test; 181 geçti, 24 dış koşullu test atlandı**. Sürüm geçmişi ve genişletilen preview regresyonu bu tam koşuya dahildir. `/tmp/mssql-063-release-build.log`: Release **BUILD SUCCEEDED**; `git diff --check` temiz.
- Düzeltme yeni v0.2.63/build 64 yayınına alınır. Önceki yerel tasarım kontrolü aşağıda tarihsel kanıttır.

# Premium form tasarımı ve SSMS renkleri — 11 Ekim 2026

- Ortak StudioPanelStyle bütün alt formlara secondary düğme ve GroupBox kart stilini taşır. Primary/secondary yüzeyler, 100 ms hover, pressed/disabled kontrastı, semantic toolbar renkleri, panel başlıkları ve 12 pt kartlar yenilendi. Bağlantı/Ayarlar kartları, Agent ikonlu gezinmesi, SQL gönderim düğmeleri ve Hakkında sürüm seçimi uyarlandı. İşlem yolları ve onaylar korunur; tasarım kuralları AGENTS.md'ye işlendi.
- SQL paleti genel UI paletinden ayrıldı. Açık temada SSMS kategori renkleri, koyuda aynı kategorilerin okunur uyarlamaları kullanılır; düz metin siyah/açık gri ve satır numarası teal olur. Microsoft'un birebir koyu RGB değerleri olduğu iddia edilmez. Kaynak: [SSMS renk kategorileri](https://learn.microsoft.com/en-us/ssms/scripting/color-coding-in-query-editors).
- `/tmp/mssql-premium-final-tests.log`: **91 uygulama + 114 core = 205 test; 181 geçti, 24 dış koşullu test atlandı**. Yeni renk regresyonu her iki temada ana editör ve SQL önizlemesinin sekiz kategorisini bağımsız RGB beklentisiyle, zemin/satır numarasını, metin/seçim ve TextKit 2 korunmasını kontrol eder. Mevcut Agent renk/undo, minimum/geniş pencere, detached, grid düzenleme/kopyalama ve precision regresyonları geçti.
- İlk tam koşu `/tmp/mssql-premium-all-tests.log` başarılı sayılmadı: bracketed missing object testi sabit 450 ms bekleme sonunda sonuç yetişmediği için hata verdi. Test aynı tanı beklentisini koruyarak en fazla 2 saniye completion bekler; ürünün debounce/analiz davranışı değiştirilmedi. Son tam koşu bu düzeltmeden sonradır.
- `/tmp/mssql-062-notes-tests.log`: sürüm artışı sonrası ReleaseHistoryTests **4/4 geçti**.
- `/tmp/mssql-premium-release-build-final.log`: Release **BUILD SUCCEEDED**. Mevcut EditorView actor izolasyonu uyarısı bu değişiklikte eklenmedi. `git diff --check` temiz.
- CUA ile ayrı `local.mssqlstudio.uitest` uygulamasında koyu Agent Genel formu, yeni ikonlu gezinme/selected durumu ve primary/secondary düğmeler görsel olarak incelendi; Adımlar ve T-SQL adım editörü erişilebilirlik ağacı doğrulandı. Gelişmiş sayfaya geçişte CUA servisi “native pipe closed before response” hatası verdi; yeniden bağlanma/reset de başarısız oldu. Bu nedenle Ayarlar, bağlantı, Hakkında ve bütün yönetim formları bu tur CUA ile yeniden gezilmiş sayılmaz.
- Son test koşusunun `/tmp/mssql-design-{light,dark}-{1100,1440}.png` rasterlerinden iki 1100 pt ana çalışma alanı görüntüsü incelendi. Native cacheDisplay bazı sistem kontrollerini eksik çizebildiğinden rasterler tam CUA smoke yerine geçmez. 1060/1920 pt yerleşim ve 1100/1440 pt tema/geçiş testleri geçti.
- İzole fixture gerçek Keychain/history/restore/network öncesinde döner. Kullanıcının kurulu uygulaması ve SQL oturumları değiştirilmedi. Canlı SQL Server entegrasyon testleri gerekli ortam tanımlı olmadığından atlandı.

# v0.2.61 yayın doğrulaması — 11 Ekim 2026

- Public latest: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.61; build 62, kaynak d9c038fe2d140390f34c1f9dbe299111fd12da72. Actions 38101901309 bütün adımlarıyla başarılı: sabit imza/izole Keychain, uygulama ve PKG üretimi, manifest ve gerçek yayın paketleriyle testler geçti.
- İndirilen ZIP SHA-256 1790432b6d828bbe22ba85321391d539832e00a5e34ce081ca996e378949efaf; PKG SHA-256 72bdb55b081d13c84b9d67da747bfca6a046d276221bf0dfda23040c13aee847. Her ikisi public GitHub asset digest ve update.json ile eşleşti.
- prepare-release.py indirilen ZIP/PKG için strict/deep imza, sabit sertifika/DR, local.mssqlstudio.app kimliği, sürüm, aynı binary/metadata ve sürüm notlarını doğruladı. Uygulamanın 0.2.61/62 bilgisi ayrıca doğrulandı. İndirme/doğrulama dosyaları /tmp/MSSQLStudio-0.2.61-verify altında.
- Yayın öncesi sürüm geçmişi testleri `/tmp/mssql-061-notes-tests.log`: 4/4 geçti. Tasarım geliştirmesinin tam test ve native görsel kanıtları aşağıdadır; aşağıdaki henüz yayımlanmadı başlığı o turun tarihsel durumudur.
- Kullanıcının kurulu uygulaması, açık sorguları, Keychain ve veritabanı değiştirilmedi.

# Genel çalışma alanı tasarımı — 10 Ekim 2026 (henüz yayımlanmadı)

- Açık/koyu palette pencere çerçevesi, Explorer/panel ve editör ayrı yüzeylere taşındı. Sorgu/sonuç sekmelerinin seçimi, satır seçimi, boşluklar ve tipografi yenilendi. Ana toolbar, Explorer ve ayrılmış sorgu penceresi ortak ikon/hover bileşenini kullanır. Sonuç satırları yalnız görünür aralıkta düz zebra zemine çizilir; native hücre, kopyalama/düzenleme ve spool davranışı korunur.
- `/tmp/mssql-design-all-tests-final.log`: **90 uygulama + 114 core = 204 test; 180 geçti, 24 dış koşullu test atlandı**. Önceki tam koşuda Explorer alt sınırının 240 pt yapılması eski 140 pt daraltma testini bozdu. 140 pt davranışı ve 1060 pt pencere alt sınırı geri korundu; başarılı tam koşu bundan sonradır.
- Son yardımcı metin tema düzeltmesinden sonra `/tmp/mssql-design-regression-final.log`: **21 ilgili testten 20 geçti, 1 dış koşullu test atlandı** (WorkbenchDesignTests, PremiumLayoutTests, GridToolbarTests, WorkspaceInteractionTests). Yeni native test 1100/1440 pt, açık/koyu tema, araçların pencereye sığması, SQL metni/seçimi, exact decimal metni ve arama fontu/yardımcı metin renklerinin korunmasını kapsar. Mevcut sekme, detached, daraltma, düzenleme, kopyalama ve hover regresyonları da geçti.
- `/tmp/mssql-design-release-complete.log`: Release **BUILD SUCCEEDED**. `git diff --check` temiz. Mevcut EditorView actor izolasyonu uyarısı devam eder; bu değişiklikte eklenmedi.
- CUA ile ayrı `local.mssqlstudio.uitest` uygulamasında açık/koyu ana çalışma alanı, koyu Ayarlar → Görünüm ve Sonuç Yükleme paneli görsel olarak incelendi. 2.000 satır / 64 kolon çevrimdışı fixture'da sayfalama 1–500 → 501–1000 ilerledi; arama alanları koyu temada okunur kaldı. Son iki yardımcı metin renk bağlaması ve eski minimum genişliği geri koruma, son native testlerle doğrulandı.
- Yerleşim rasterleri `/tmp/mssql-design-{light,dark}-{1100,1440}.png`. AppKit cacheDisplay bazı native alanların (arama zemini/köşe) görüntüsünü eksik yakalayabildiğinden bu rasterler tek görsel kanıt sayılmadı; çalışan uygulama CUA ekranlarında ayrıca incelendi. Bütün yönetim formları tek tek yeniden gezilmedi.
- İzole uygulama kapatıldı; kurulu kullanıcı uygulaması, açık SQL oturumları, Keychain ve veritabanı değiştirilmedi. Canlı sunucu/SQL yazma ve imzalı yayın paketi testleri bu görsel geliştirme turunda çalıştırılmadı. Sürüm artırılmadı, yayın yapılmadı.
- Tasarım referansı: [DataGrip arayüz yapısı](https://www.jetbrains.com/help/datagrip/guided-tour-around-the-user-interface.html), [tema yaklaşımı](https://www.jetbrains.com/help/datagrip/user-interface-themes.html). Marka varlıkları kopyalanmadı; AppKit/SF Symbols ve mevcut ürün işlevleri korundu.

# v0.2.60 yayın doğrulaması — 10 Ekim 2026

- Public latest: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.60; build 61, kaynak c2ebc5f495404fa63b73d2b1eaf7aa765cf6e69f. Actions 38082255408 başarılı; sabit imza/izole Keychain, paket üretimi, manifest ve gerçek paketlerle testler geçti.
- İndirilen ZIP SHA-256 0c0046a451950e9fe916e6ebeedfc7cf4cb56d9a7c119eaa031de6875476397a; PKG SHA-256 2a98dbcf54ee478d842279096e105d1a94ca7eb9fa0112874614c21795baabb3. Public GitHub digest ve update.json ile eşleşti.
- prepare-release.py indirilen ZIP ve PKG içindeki uygulamaların strict/deep imza, sabit sertifika/DR, bundle ID/sürüm ve aynı binary/metadata/sürüm notu kontrollerini geçti. Kullanıcının kurulu uygulaması değiştirilmedi.

# İkon açıklamaları, sadeleştirme ve hızlı paneller — 10 Ekim 2026

- Son tam doğrulama `/tmp/mssql-060-tests-verified.log`: 89 uygulama + 114 core = 203 test; **179 geçti, 24 dış koşullu test atlandı**. Önceki iki tur başarılı sayılmadı: ilkinde eski export konumu beklentisi ve sabit 900 ms arama beklemesi, ikincide paralel pencere testlerinin paylaştığı hover alanı etkilendi. Yerleşim beklentisi güncellendi, async arama sınırlı completion bekleyişi kullanır, hover testi ayrı helper örneğiyle izoledir.

- StudioHoverHelp sonuç ikonlarında 200 ms sonra işlev adını gösterir; fareyi/odağı yakalamaz, çıkış/tıklama sırasında kapanır. Sayfa boyutu ve export da aynı davranışı kullanır. Düzenle/Vazgeç aynı toggle'da birleştirildi; export en sağda arrow.down.document, işlem sürerken aynı yerde iptal görünür. İlgili kalıcı kurallar AGENTS.md'ye eklendi.
- Sonuç yükleme/kolon arama/kolon filtre ve Explorer indeks detay popover'larında animasyon kaldırıldı. Kolon filtresinin boş aramadaki ilk değer yüklemesinden 200 ms yapay bekleme kaldırıldı; yazılı aramada debounce ve detached veri okuma korunur. Ağ gecikmesinin kaldırıldığı iddia edilmez.
- `/tmp/mssql-060-focused-final.log`: GridToolbarTests 8/8 geçti; hover adının gösterilmesi/iptali, tek kapatma kontrolü, export'un sağda olması, native düzenlemeden değişikliksiz çıkış, bekleyen değişiklik onayları, doğrudan satır eylemleri ve 830/1280 light/dark yerleşimleri kapsandı. `/tmp/mssql-060-build.log`: Release BUILD SUCCEEDED. Mevcut EditorView actor izolasyonu derleyici uyarısı devam eder; bu kapsamda değiştirilmedi.
- İzole local.mssqlstudio.uitest uygulamasında CUA ile yükleme ayarları ve kolon arama açıldı; içerikleri ve export'un sağdaki yeni simgesi görsel olarak kontrol edildi. İzole uygulama kapatıldı. Gerçek uygulama/Keychain/SQL oturumları değiştirilmedi; canlı DB yazma testi yapılmadı.

# v0.2.59 yayın doğrulaması — 10 Ekim 2026

- Public latest: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.59; build 60, kaynak 77b7afbca6f96f8c29898d64d28bad611446b39c. Actions 38080851487 tüm adımlarıyla başarılı; sabit imza, izole Keychain, paket üretimi ve gerçek yayın paketleriyle testler geçti.
- İndirilen ZIP SHA-256 8167c0a759dc535ece34be10815a5837420f6f090156c7ecb46e1d68dac659be; PKG SHA-256 9e359d705bb1478d4d028c3b66d93b3e996ce69f92df515bfd513650685d19c0. update.json ve GitHub digest değerleriyle eşleşti.
- prepare-release.py indirilen her iki paketteki uygulama için strict/deep imza, sabit sertifika/DR, bundle ID, sürüm, aynı binary/metadata ve sürüm notlarını doğruladı. Gerçek kullanıcı uygulaması/Keychain/veritabanı değiştirilmedi.

# Sonuç araç çubuğu ve düzenleme modu — 10 Ekim 2026 (henüz yayımlanmadı)

- Düzenleme ve doğrudan ekle/çoğalt/sil/geri al/NULL/SQL önizleme/vazgeç düğmeleri ana araç çubuğuna taşındı. İkinci sıra ve Satırlar açılır menüsü kaldırıldı. Ortak StudioToolbarButton semantik ikon/renk, hafif kenarlık/zemin, hover ve disabled görünümü kullanır. Düzenleme toggle ve Vazgeç değişiklik olmadan modu kapatır; değişiklik varsa onay korunur.
- `/tmp/mssql-inline-toolbar-final-tests.log`: 88 uygulama + 114 core = 202 test; **178 geçti, 24 dış koşullu test atlandı**. Her iki hedefin tamamlanma özeti doğrulandı. Son kısa sayfa etiketi/arama placeholder düzeltmesinden sonra `/tmp/mssql-inline-toolbar-final-focused.log`: ilgili 7 testin tümü geçti. Yeni kontroller doğrudan satır eylemleri, nullable/generated kısıtları, gerçek native hücre editöründen değişikliksiz çıkış, vazgeç onayının kabul/red akışı ve grid konumunun korunmasını kapsar.
- Light/dark ve 830/1280 pt pencere genişliklerinde taşma/çakışma kontrolleri geçti. `/tmp/mssql-inline-toolbar-{light,dark}-{830,1280}.png` görüntüleri üretildi; dar koyu tema ve izole Release uygulaması görsel olarak incelendi. Sayfa boyutu 500 tam görünür; düzenleme eylemleri aynı sıradadır.
- `/tmp/mssql-inline-toolbar-build-final.log`: Release **BUILD SUCCEEDED**. İzole `local.mssqlstudio.uitest` uygulaması CUA ile açıldı; son sayfa düğmesi aralığı 1–500'den 1501–2000'e taşıdı, ileri düğmeleri devre dışı kaldı. Fixture sunucu doğrulaması içermediği için bu uygulamada edit düğmesi kapalıdır; düzenleme native uygulama testlerinde doğrulandı. Test uygulaması kapatıldı; gerçek uygulama/Keychain/SQL oturumları değiştirilmedi.
- İlk test denemeleri native hedefte tamamlanma özeti olmadan 0 çıkış verdi; başarılı sayılmadı. Yeni düğme testlerinde animasyonlu performClick yerine AppKit target/action gönderimi kullanıldı; tam suite sonradan tamamlandı. Canlı DB yazma testi yapılmadı. Sürüm/yayın değiştirilmedi.

# v0.2.54 yayın doğrulaması — 10 Ekim 2026

- Public latest https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.54; build 55, kaynak 7b673e7f5eeb5fe704713cefe8a0bfe9b02cab98. Actions 38050647736 başarılı; sabit imza/izole Keychain, paket üretimi, manifest ve gerçek ZIP/PKG ile testler geçti.
- Public ZIP SHA-256 f840a7bce067fbe095b0faa735bc7c687f0d116e81dd5ea6ba3e42e7bd897369; PKG SHA-256 ec938172845de80dc5348ff3b943f3b7254612555a41ce03c1ec3262d389caa5. Manifest ve GitHub digest değerleriyle eşleşti.
- Çıkarılan uygulama strict/deep codesign kontrolünü geçti; sürüm 0.2.54/55, sabit local.mssqlstudio.app / adce16b1a3567d8c5fe2ed261e89493611cb7b9d designated requirement doğrulandı.
- Gerçek kullanıcı app'i/Keychain/veritabanı değiştirilmedi. Canlı SQL Server yazma/çatışma senaryoları bu tur çalıştırılmadı; yerel test ayrıntıları aşağıdadır.

# Rowversion zorunluluğunun kaldırılması ve satır işlemleri — 10 Ekim 2026

- Rowversion artık zorunlu değil. Mevcutsa PK + rowversion kontrolü korunur; yoksa PK ve karşılaştırılabilen özgün değerler kullanılır. XML/text/ntext/image açık dönüşümlerle karşılaştırılır; legacy değer yazmaları varchar(max)/nvarchar(max)/varbinary(max) üzerinden üretilir. Spatial/UDT/sql_variant düzenlenmez ve predicate dışında kalır; bu özel alanların eşzamanlı değişikliğini yakalama güvencesi yoktur.
- Sonuç tablosunda Satırlar menüsü ve sağ tık Yeni Satır, Satırı Çoğalt, Satırı Sil / Silmeyi Geri Al, Seçili Düzenlemeleri Geri Al içerir. Değişiklikler yereldir; INSERT/UPDATE/DELETE aynı SQL önizleme/onay/transaction akışını kullanır. Mevcut PK/generated alanları korunur; yeni satırda nonidentity PK girilebilir. Çoğaltma PK/generated/desteklenmeyen özel alanları taşımaz. Dokunulmayan alan DEFAULT, açık NULL touched olarak kalır. DEFAULT bir placeholder'dır; gerçek veri metnine dönüşmez.
- Yeni satırlar ayrı negatif kimlikle mevcut sayfanın sonunda kalır; filtre/sıralama bunları gizlemez. Çoklu yeni satır silme kimlikleri önce snapshot alır; indeks kayması olmaz. Orijinal spool/export korunur. Düzenleme eylemleri ayrı 34 pt sırada; sonuç arama/sayfalama araçları korunur. Table/scroll/cell focusRingType none; native seçim/klavye odağı kalır.
- `/tmp/mssql-rows-final-verified-tests.log`: 76 uygulama + 106 core = 182 test; **159 geçti, 23 koşullu test atlandı**. Yeni testler rowversion olmayan XML/ntext/image metadata + SQL üretimi, özel alanın read-only/predicate dışında kalması, clone PK temizliği, editable yeni anahtar, DEFAULT/NULL, çoklu yeni satır silme, mevcut satır DELETE/geri alma, filtre altında yeni satır ve export ayrımı, 830 pt araç çubuğu kontrolünü kapsar. Native field editing ve hücre kopyası regresyonları da geçti.
- İlk yerleşim denemesinde test penceresinin controller sonrası içerik boyutu atanmaması sıfır genişlikli Search alanı üretti. Test penceresi gerçek 830x680 boyutuna ayarlanarak kontrol düzeltildi; başarısız denemeler başarılı sayılmadı. Eylemler ayrıca ayrı sıraya taşındı.
- `/tmp/mssql-rows-release-build.log`: Release **BUILD SUCCEEDED**; git diff --check temiz. Gerçek kullanıcı uygulaması/Keychain/veritabanı değiştirilmedi. Canlı INSERT/DELETE ve rowversion olmayan UPDATE/çakışma işlemleri bu ortamda doğrulanmadı.
- Araştırma: [DataGrip satır ekleme, çoğaltma ve silme](https://www.jetbrains.com/help/datagrip/rows.html?keymap=macos_system_shortcuts). Gönderim otomatik değildir; açık SQL önizleme onayı korunur.

# v0.2.53 yayın doğrulaması — 10 Ekim 2026

- Public latest https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.53; build 54, kaynak 4adb1294db157c931e3d2c938d136b4e3d0c338c. Actions 38049760449 başarılı; kalıcı imza, sentetik Keychain, paket üretimi ve gerçek ZIP/PKG ile testler geçti.
- Public ZIP SHA-256 41a715e699112de17c883ce97e85ea00127e1437e30296228c73b6ef6b17b358; PKG SHA-256 c11de0f25d332c4fde06282e30f24d2d8a126541442e4d3958ef3a8fef4543fb. Manifest ve GitHub digest değerleriyle eşleşti.
- Çıkarılan uygulama strict/deep codesign doğrulamasını geçti; bundle sürümü 0.2.53/54, sabit local.mssqlstudio.app / adce16b1a3567d8c5fe2ed261e89493611cb7b9d designated requirement doğrulandı.
- Kullanıcı uygulaması ve veritabanı değiştirilmedi. Canlı SQL Server UPDATE/çatışma testi bu tur çalıştırılmadı; yerel test ayrıntıları aşağıdadır. Aşağıdaki henüz yayımlanmadı başlığı geliştirme kontrolünün tarihsel durumudur.

# Timeline ve sonuçlarda önizlemeli UPDATE — 10 Ekim 2026 (henüz yayımlanmadı)

- Timeline: sunucu/DB/durum/tarih + metin filtreleri, süreye göre sıralama, sorgu özeti, renkli tam SQL önizlemesi, hata/satır sayısı ve kopyalama. Yeni sekme kendi server UUID'sinde açılır; eski kayıt yalnız tek isim eşleşmesinde açılır. Geçmiş değişiklikleri açık panele yansır.
- Ayarlar → Çalışma Alanı: saklama süresi 1–3650 gün, varsayılan 30. Açılış/yeni kayıt/Uygula ile süre temizliği; 16 MB JSON/20.000 kayıt ek bütçesi. Eski 300 kayıt sınırı kaldırıldı; eski Codable kayıtlar uyumludur. UI smoke gerçek history okumadan döner.
- Sonuç tablosunda Düzenle → yerel hücre değişiklikleri/NULL → renkli SQL Önizle → Onayla ve Veritabanına Gönder. PK/generated alanlar korunur; değişmiş hücreler ve satır sayısı işaretlenir. Başarılı gönderim son SELECT'i yeniler. Otomatik yenileme düzenleme modunda kapalı; gönderilmemiş düzenlemeleri silecek sorgu/yenileme/kapatma uyarılıdır. Gönderim sırasında sorgu yürütme/kapatma engellenir.
- Kaynak sys.dm_exec_describe_first_result_set ile doğrulanır; tek yerel tablo, bütün kolonlar ve PK gerekir. Alias/sütun sırası desteklenir; JOIN/toplama/çoklu sonuç, temp/remote, eksik projection/PK ve partial sonuçlar salt okunur kalır. En fazla 400 değişmiş satır; spool değişmez. Preview snapshot, sunucu generation, DB, sonuç generation ve tablo metadata yeniden kontrol edilir. Ayrı ODBC bağlantısında OBJECT_ID + PK/orijinal/rowversion + @@ROWCOUNT ve transaction rollback koruması kullanılır. Ağ hatasında commit belirsiz olabilir; otomatik tekrar yoktur.
- `/tmp/mssql-timeline-complete-tests.log`: 74 uygulama + 105 çekirdek = 179 test; **156 geçti, 23 koşullu test atlandı**, hata yok. Gün saklama sınırı/eskiden kayıt okuma/boyut bütçesi, remote/eksik kaynak reddi, ordinal alias eşlemesi, PK koruma, NULL, orijinale dönüş, filtre/taşınmış kolon altında doğru satır ve refresh invalidation sınandı. Native field editor 1.200 karakterlik tam hücreyi aldı; commit yerel değeri değiştirdi ve orijinal snapshot kaldı.
- Native testin ilk koşularında GridDataCell inherited ObjC copy ile Swift-owned checkbox sığ kopyası deallocation sırasında signal 11 üretti. `copy(with:)` ayrı checkbox sahibi hücre üretmek üzere düzeltildi. Düzeltme sonrası iki tam test koşusu geçti; önceki çöken koşular başarılı sayılmadı.
- Timeline ve gönderim önizlemesi native NSHostingController pencerelerinde render edildi; `/tmp/mssql-timeline-ui.png` ve `/tmp/mssql-data-preview-ui.png` görsel incelemesinde renkler/yerleşim/kaydırma kontrol edildi. Toolbar 830 pt sığma regresyonu geçti. `/tmp/mssql-timeline-complete-build.log`: Release **BUILD SUCCEEDED**. `git diff --check` temiz.
- Localhost için yeni provenance → gerçek UPDATE → stale rowversion durumunda çoklu satır rollback entegrasyon testi eklendi; MSSQL_TEST_PASSWORD tanımlı olmadığı için **çalıştırılmadı**. Gerçek SQL Server yazması, kullanıcı bağlantıları/Keychain/kurulu app değiştirilmedi. SQL yazma akışı canlı doğrulanmış veya yayınlanmış sayılmaz.
- Araştırma: [DataGrip sorgu geçmişi](https://www.jetbrains.com/help/datagrip/find-recent-queries-and-files.html), [yerel değişiklik/SQL önizlemesi/gönderim](https://www.jetbrains.com/help/datagrip/submitting-and-reverting-changes.html), [Microsoft sonuç kaynağı metadata](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-objects/sys-dm-exec-describe-first-result-set-transact-sql?view=sql-server-ver17).

# v0.2.52 yayın doğrulaması — 10 Ekim 2026

- Public latest https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.52; build 53, kaynak a0366b4432f224a143c1dd19a79cadf3e9f83e3f. Actions 38048473313 tüm adımları geçti; ZIP/PKG/update.json mevcut. Yeni manifest installerURL/installerSHA256 alanlarını içeriyor.
- İndirilen ZIP SHA256 534800503e3b51853c7e9ef3503932d97a9ef31a662d9d61538bbbc365b5408c; PKG e5103c97126ef2bea7d6b3b99df62ebe211938757369279e0afcaaa5c3336134. Her ikisi manifest ve GitHub digest ile eşleşti.
- Çıkarılan app codesign --verify --deep --strict kontrolünü geçti; local.mssqlstudio.app / adce16b1a3567d8c5fe2ed261e89493611cb7b9d sabit designated requirement korundu. CI testleri gerçek yayın ZIP ve PKG'siyle başarılı.
- Public indirilen PKG ile `/tmp/mssql-v52-public-pkg-test.log` odaklı doğrulama geçti: payload sabit imzası/sürümü kabul edildi, yanlış sürüm reddedildi; kurulum çalıştırılmadı.
- İlk geçiş doğrudan PKG kurulumu gerektirir; eski kurulu updater kendi kendini düzeltemez. Kullanıcı uygulaması/Keychain/veritabanı değiştirilmedi; macOS Installer içinde gerçek kullanıcı yükseltmesi yapılmadı. Aşağıdaki henüz yayımlanmadı ifadesi yerel kontrolün tarihsel durumudur.

# PKG tabanlı güncelleme — 10 Ekim 2026 (yerel, yayımlanmadı)

- Salt okunur yerel incelemede /Applications/MSSQLStudio.app sürümü 0.2.50; iki .MSSQLStudio-update-* klasöründe v0.2.51 uygulaması/helper.sh bulundu. Helper süreçleri çalışmıyordu; kurulum uygulanmamıştı. Bunlar değiştirilmedi/silinmedi. Yardımcının neden sona erdiği kesin olarak kanıtlanmadı; uygulama kapanışına bağlı özel taşıma yolu kaldırıldı.
- Güncelleme UI artık PKG indirir, SHA256 ve açılmış uygulama payload'ında sabit sertifika/DR, bundle ID ve tam sürümü doğrular. Component Scripts reddedilir. macOS Installer açılır, çalışma/transaction kapanış denetiminden sonra uygulama kapanır. Kullanıcı kurulumu tamamlar ve Uygulamalar'dan yeniden açar. Eski app yedeği/.previous/rollback helper yoktur.
- Yeni manifest installerURL/installerSHA256 içerir; ZIP alanları eski uygulamalar için korunur. Eski ZIP-only feed yeni UI tarafından açık PKG uyarısıyla reddedilir. Sonraki açılışta pendingInstallerVersion ve çalışan sürüm/konum karşılaştırılır; eski veya farklı konumdaki uygulama başarı olarak bildirilmez. Eşzamanlı update başlatma engeli eklendi.
- `/tmp/mssql-installer-final-tests.log`: 70 app + 102 core = 172 test; 150 geçti, 22 dış koşullu test atlandı. MSSQL_UPDATE_PKG=/tmp/MSSQLStudio-0.2.51.pkg ile gerçek imzalı PKG payload doğrulandı; yanlış sürüm reddedildi. Yeni completion testi eski sürümü ve yanlış konumu reddeder. Eski shell yedek/rollback testleri kaldırıldı.
- Gerçek PKG SHA256 c9f745a20d67e55a5551c86bf5296303b874562ae615082797537854ba95106c önceki doğrulanmış GitHub digest ile eşleşti. `/tmp/mssql-installer-manifest-test.log`: gerçek ZIP/PKG ile yeni manifest üretimi ve yayın kontrolleri geçti. `/tmp/mssql-installer-final-build.log`: Release BUILD SUCCEEDED. git diff --check temiz.
- Gerçek kullanıcı uygulaması/Keychain/veritabanı değiştirilmedi; macOS Installer içinde gerçek yerinde upgrade ve yeni akışın tüm görsel adımları bu turda çalıştırılmadı. İlk geçiş mevcut updater ile olmaz, yeni sürümün PKG'siyle yapılmalıdır. Kişisel sertifika Developer ID/notarization değildir; sistem güvenlik denetimleri atlanmaz. Son yayın hâlâ v0.2.51.

# v0.2.51 yayın doğrulaması — 10 Ekim 2026

- Public latest https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.51; build 52, kaynak 07a268c2fc6180d134b76c31563e1cbae94cc98f. Actions 38046699005 tüm adımları geçti; ZIP, PKG, update.json mevcut.
- İndirilen ZIP SHA256 89916829f01c33b61ca4dd3ce8b5c767dd5c0a1ca1d59444e1092ddfa1620877 manifest/GitHub digest ile eşleşti. PKG GitHub digest c9f745a20d67e55a5551c86bf5296303b874562ae615082797537854ba95106c.
- Çıkarılan uygulama codesign --verify --deep --strict kontrolünü geçti. local.mssqlstudio.app / adce16b1a3567d8c5fe2ed261e89493611cb7b9d sabit designated requirement korundu.
- CI imzalı derleme, izole Keychain kontrolü, manifest ve yayın paketi testleri başarılı. Kullanıcının uygulaması/Keychain/veritabanı değiştirilmedi. Önceki rapordaki canlı bilgi penceresi kontrol sınırı geçerlidir; henüz yayımlanmadı ifadesi o anki tarihsel durumu anlatır.

# Explorer bağlantı ve bilgi kartları — 10 Ekim 2026 (yerel, yayımlanmadı)

- Yeni bağlantıda kayıtlı bağlantı seçimi/otomatik doldurma ve ServerVault liste okuması kaldırıldı. Düzenleme seçili profil bilgilerini korur.
- Bağlantıyı kaldır, native onay sonrası yalnız Explorer sunucusunu ve restore seçimini kaldırır. Metadata kapanırken ağaç ve arama kapsamı temizlenir; kayıtlı parola/Keychain ve açık sorgu/transaction korunur. Yeni native test gerçek outline satırının kalkmasını da doğrular.
- Veritabanı bilgileri SQL sekmesi yerine yeniden kullanılabilen 760x620 salt okunur pencerede genel alan/dosya kartlarıyla gösterilir. Ayrı katalog bağlantısı, yükleme/hata, yenileme ve SQL escaping korunur.
- İndeks popup'ında DB kartı, nesne sayısı, kolon güncelliği, ayrı eşitleme tarihleri, offline/hata/hazırlık durumları ve yenileme eylemi vardır. Katalog bildirimleri görünümü günceller; metin özeti parse edilmez.
- `/tmp/mssql-explorer-cards-final-tests.log`: 70 uygulama + 100 core = 170 test; 148 geçti, 22 dış koşullu test atlandı. Son kaldırma sıralaması sonrası `/tmp/mssql-explorer-removal-final-test.log` odaklı regresyon geçti. `/tmp/mssql-explorer-cards-final-build.log`: Release BUILD SUCCEEDED; git diff --check temiz.
- İzole local.mssqlstudio.uitest uygulamasında kayıtlı seçim olmadan yeni form, indeks kartlarının son çerçeveli görünümü, offline yenilemenin kapalı olması, kaldırma onayı/Vazgeç ve son derlemede Kaldır sonrası ağacın boşalıp sorgu sekmesinin kalması doğrulandı. İlk görsel kontrolde eski ağaç kalma sorunu yakalanıp düzeltildi; test bu regresyonu kapsar.
- Gerçek kullanıcı uygulaması/Keychain/veritabanı değiştirilmedi. Canlı veritabanı bilgi okuması ve dolu bilgi penceresinin görsel kontrolü bu turda yapılmadı. Yayın sürümü hâlâ v0.2.50.

# v0.2.50 yayın doğrulaması — 10 Ekim 2026

- Public latest https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.50, build 51, kaynak bb0a6193daffcf1cd0995efc923346f0871b8fab. Actions 38044468276 tüm adımları geçti; ZIP/PKG/update.json mevcut.
- Yerel `/tmp/mssql-v50-tests.log`: 69 app + 100 core = 169 test; 147 geçti, 22 dış koşullu test atlandı. Yeni helper testi dört ayrı shell senaryosunu sınar. CI yayın paketi testleri de geçti.
- İndirilen ZIP SHA256 12e3aebee3d71c3dcc0ee42293aad5927a94ace035e96fb3e69c82156747aa9c manifest ve GitHub digest ile eşleşti. PKG GitHub digest c47fec788689d405e59b33e75ceb16b58aaafa8b7703a803c6dadcf8cad2ba2c.
- Çıkarılan app codesign --verify --deep --strict kontrolünü geçti; local.mssqlstudio.app / adce16b1a3567d8c5fe2ed261e89493611cb7b9d sabit kimliği korundu. Kullanıcının uygulaması değiştirilmedi; gerçek yerinde upgrade çalıştırılmadı.

# Güncelleme yedeği — 10 Ekim 2026

- Updater eski uygulamayı hedef.app.previous yerine gizli, özel staging/previous yoluna taşır. Taşıma/imza/open başarı zinciri sonunda yedek temizlenir; hata halinde eski uygulama geri getirilir. İmza/manifest kontrolleri korunur.
- `/tmp/mssql-update-backup-tests.log`: odaklı 8 test geçti; üretim shell akışı geçici sahte bundle'larla başarı, imza hatası, open hatası ve eksik paket durumlarında çalıştırıldı. Gerçek codesign/open yerine test stub'ları kullanıldı; gerçek kullanıcı uygulaması/Keychain değişmedi. open başarısı sonradan oluşan crash'i algılamaz.
- Eski updater'ın bu sürüme geçişte oluşturacağı veya geçmişten kalan .previous kopyalarına otomatik silme uygulanmaz. İlk geçişte bu davranışı önlemek için yayımlanan PKG kullanılabilir; yeni updater sonraki güncellemelerde geçerlidir.

# v0.2.49 yayın doğrulaması — 10 Ekim 2026

- Public latest: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.49; sürüm 0.2.49/build 50, kaynak 8f203c56e3b16e6b0c314b44364b3d850d83c9f6. ZIP, PKG ve update.json mevcut.
- Actions 38042594566 başarılı: sabit kimlik/izole Keychain, imzalı derleme, manifest, yayın paketi testleri ve yayın adımları geçti.
- İndirilen ZIP SHA256 3c26fa22ee1e85294bbb1e5cf69227c80f43a1b7d98a4977d69e350e8bebadf3; manifest ve GitHub digest eşleşti. PKG GitHub digest d521ec54dcbcbefc194ac3b7b24acd46fd4727701ce3d64763c46820e96dccc0.
- Çıkarılan app codesign --verify --deep --strict kontrolünü geçti; local.mssqlstudio.app ve sertifika adce16b1a3567d8c5fe2ed261e89493611cb7b9d designated requirement korundu. Gerçek kullanıcı uygulaması değiştirilmedi.
- v0.2.48 Actions 38042378822 mevcut katlama testinin sabit 400 ms analiz bekleme süresinde başarısız oldu; yayın açılmadı. Test artık sonucu sınırlı süre boyunca bekliyor; odaklı yerel test ve v0.2.49 CI geçti. Eski etiket değiştirilmedi. Aşağıdaki henüz yayımlanmadı ifadesi o anki yerel kontrolün tarihsel durumudur.

# Bağlantı formu ve Explorer — 10 Ekim 2026 (yerel, henüz yayımlanmadı)

- Yeni/düzenlenen bağlantı formu Genel/Gelişmiş sayfalarına ayrıldı; tekrar eden test/durum alanları kaldırıldı, tek alt ana işlem ve ayrı veritabanı paneli kullanıldı. Düzenleme sırasında gereksiz tüm Keychain kayıtlarını listeleme kaldırıldı; güvenlik seçenekleri korundu.
- DB yanına kompakt yerel indeks durum düğmesi eklendi; ayrıntı/yenileme kapsamı popup içinde. Dar satırda düğme görünürlüğü düzeltildi. DB sağ tık menüsü yeni nesne alt menüsü ve açık işlem adlarıyla düzenlendi.
- Nesneleri Yenile artık DB'nin yüklenmiş klasörlerini katalogdan yeniden okur; klasör kimliklerini korur, açılmamış dalları lazy bırakır. Açık SQL'i çalıştırmaz; yerel indeks yenilemesi ayrı işlemdir.
- `/tmp/mssql-explorer-final-build.log`: Release BUILD SUCCEEDED (CODE_SIGNING_ALLOWED=NO). `/tmp/mssql-explorer-final-tests.log`: 69 uygulama + 99 core = 168 test; 146 geçti, 22 dış koşullu test atlandı. İki yeni native regresyon: DB yenilemesinde katalog çağrıları/klasör kimliği/SQL'in çalışmaması ve 210 pt satırda indeks düğmesinin yerleşimi.
- İlk dar satır testinde test penceresinin kapanırken otomatik serbest bırakılması test sürecini düşürdü; test harness isReleasedWhenClosed=false ile düzeltildi. Odaklı test ve ardından tüm testler geçti.
- İzole `local.mssqlstudio.uitest` uygulamasında bağlantı formu görünümü, Genel/Gelişmiş geçişinde adın korunması, dar Explorer'da DB düğmesinin görünmesi ve DemoDB kapsamlı popup açılması görsel olarak doğrulandı. Çevrimdışı fixture kullanıldı; canlı bağlantı, gerçek sunucuda sağ tık işlemleri ve canlı indeks yeniden oluşturma test edilmedi. Kullanıcı uygulaması, gerçek Keychain kayıtları ve veritabanları değiştirilmedi.
- Önceki belge birleştirmesi korunur. Yayın sürümü hâlâ v0.2.47'dir; bu değişiklikler henüz GitHub'da yayımlanmadı.

# Belge düzeni notu — 10 Ekim 2026

Mimari, tasarım ve kişisel imza belgeleri AGENTS.md içinde birleştirildi; README kısa kullanıcı/derleme rehberine dönüştürüldü. Aşağıdaki kayıtlar tarihsel kanıttır. Önceki dosya yollarına atıflar ilgili tarihin durumunu anlatır; güncel rehber AGENTS.md'dir. Bu düzenleme uygulama kodunu veya yayımlanmış v0.2.47 paketlerini değiştirmez.

# v0.2.47 yayın doğrulaması — 10 Ekim 2026

- https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.47 en son yayın; draft değil. ZIP, PKG, update.json mevcut. Kaynak d877e41e542b2c0434b0abe884d45317c26a2958; sürüm 0.2.47/build 48.
- Actions 38040358461 tüm adımları başarıyla tamamladı: kalıcı imza/izole Keychain testi, uygulama ve installer derlemesi, manifest doğrulaması, yayın paketiyle testler ve yayın.
- Public ZIP indirildi: SHA256 c1123556bec86f9cfb4ca200daa5bf2a3777610f136d18cc0c078115208d389c manifest ve GitHub digest ile aynı. PKG GitHub digest 98357c2f265bcfc7cb5d4295f186359c6a404a892ce209dbc69beaabd3f82126.
- Çıkarılan uygulama codesign --verify --deep --strict kontrolünü geçti. Sabit designated requirement local.mssqlstudio.app / sertifika adce16b1a3567d8c5fe2ed261e89493611cb7b9d korundu. Gerçek kullanıcı uygulaması değiştirilmedi; kapsamlı görsel kontrolün CUA bağlantısı nedeniyle tamamlanamadığı sınırı aşağıda korunmaktadır.

# Genel form hizalaması — 10 Ekim 2026

- Ortak StudioFormField 150 pt etiket sütunu/12 pt aralık ve sarılabilen etiketler kullanır. Job genel/bildirim/adım alanları, zamanlama türü/göreli gün/gün içi tekrar/tarih/saat alanları; tablo/view/index/constraint/synonym tasarımları, yeniden adlandırma/izinler; indeks ve Job şablonları; SQL Assistant adres/model/anahtar; Ayarlar tema/yayın deposu bu düzene alındı. Job Gelişmiş sayfası uzun etiketler için 180 pt sütunu korur ve aynı bileşeni kullanır.
- View şema/ad/kaynak alanları tek sıkışık HStack yerine açık etiketli satırlara taşındı; tablo ve synonym adları da ayrı satırlarda gösterilir. Bağlantı Grid'i korunup etiket sütunu 150 pt ile sabitlendi. Tablo kolon gridleri ve sonuç tablolarının mevcut sütun düzenleri değiştirilmedi. Binding, SQL, seçim, disabled ve kimlik doğrulama davranışları korunur.
- `/tmp/mssql-form-final-tests.log`: 67 uygulama + 99 core = 166 test; 144 geçti, 22 dış koşullu test atlandı. `/tmp/mssql-form-build.log`: Release BUILD SUCCEEDED (CODE_SIGNING_ALLOWED=NO). git diff --check temiz. İlk geliştirme derlemesindeki closure/stepper biçimlendirmesi final derlemeden önce düzeltildi.
- CUA envanteri okunabildi; ancak izole `/tmp/MSSQLStudio-actions-ui/MSSQLStudio.app` penceresine bağlanma halen `Sky Computer Use native pipe closed before response` hatası veriyor. Yeni formların kapsamlı ekran görüntüsü/koordinat doğrulaması yapılamadı; otomatik testler bu görsel kontrolün yerine geçmiş sayılmıyor. Gerçek kullanıcı uygulaması, DB ve Keychain değiştirilmedi. Değişiklikler henüz yayımlanmadı.

# Form hizalaması ve işlem ikonları — 10 Ekim 2026

- AgentStepEditor Gelişmiş sayfasında sabit 180 pt etiket sütunu ve ortak 12 pt aralık kullanılır. Başarı/başarısızlık hedefleri, tekrar sayısı, dakika, çıktı dosyası ve veritabanı kullanıcısı aynı alan başlangıcına hizalanır; çıktı toggle'ları da bu sütuna oturur. Akış ve çıktı/çalışma bağlamı GroupBox gruplarına ayrıldı; taşan içerik scroll alanında kalır. SQL oluşturma, flags ve binding davranışı korunur.
- Ortak StudioActionButton native SwiftUI Button + Label kullanır. İkonlar görünür metinle birlikte sunulur; native klavye, disabled ve mevcut primary button style davranışları korunur. Job Properties, adım/zamanlama, activity/context menüleri, nesne tasarımları, Ayarlar, geçmiş/şablon/assistant ve Hakkında işlem düğmeleri güncellendi. Başlat yeşil, durdur/ayır turuncu, sil kırmızı; diğer ikincil işlemler accent ikon kullanır. ModuleReview AppKit gönder/vazgeç düğmelerine de ikon eklendi.
- `/tmp/mssql-actions-final-tests.log`: 67 uygulama + 99 core = 166 test; 144 geçti, 22 dış koşullu test atlandı. `/tmp/mssql-actions-build.log`: Release BUILD SUCCEEDED (CODE_SIGNING_ALLOWED=NO). git diff --check temiz.
- Ayrı `/tmp/MSSQLStudio-actions-ui/MSSQLStudio.app` çevrimdışı fixture ile açıldı. Job Properties → Adımlar → Düzenle geçişi, işlem düğmelerinin erişilebilir adları ve düzenleme penceresinin açılması doğrulandı. Gelişmiş sekmesine tıklarken CUA aracı `Sky Computer Use native pipe closed before response` hatası verdi; yeniden bağlanma ve araç reset'i de aynı hatayı verdi. Bu nedenle Gelişmiş sekmesinin son görsel yerleşimi ve ikon renkleri canlı ekran görüntüsüyle doğrulanmış sayılmıyor. Test kopyası araç bağlantısı nedeniyle kapatılamadı; gerçek kullanıcı uygulamasına müdahale edilmedi.
- Gerçek DB/Keychain işlemi yapılmadı; değişiklikler henüz yayımlanmadı.

# v0.2.46 yayın doğrulaması — 10 Ekim 2026

- https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.46 en son yayın; draft değil. ZIP, PKG ve update.json mevcut. Kaynak commit: 0af18584d6c700d435ad8fb7b5e04196de7213b5; sürüm 0.2.46, build 47.
- GitHub Actions 38039150656 başarıyla tamamlandı: sabit imza/izole Keychain testi, imzalı uygulama ve installer, manifest doğrulaması ve yayın paketiyle testler geçti.
- Herkese açık ZIP indirildi; SHA256 318ec088111307163a0415a96551c8a09b96e7f574544031a381599859be59c3 manifest ve GitHub digest ile aynı. PKG GitHub digest: ffb70536b21cb5310d181196436f78baf1d6176861c942a6ca756b0170f93ba1.
- Çıkarılan uygulama codesign --verify --deep --strict kontrolünü geçti; designated requirement bundle local.mssqlstudio.app ve sabit sertifika adce16b1a3567d8c5fe2ed261e89493611cb7b9d. Kullanıcının kurulu uygulaması değiştirilmedi; gerçek Keychain yükseltme testi bu yayında yapılmadı.

# Ayarlar ve tıklama alanları — 10 Ekim 2026

- Hakkında sürüm satırlarının genişletilmiş etiketi Rectangle contentShape ile tamamen tıklanabilir; seçili sürüm erişilebilirlik durumu eklendi. Kolon seçme ve veritabanı arama temizleme ikonlarının boş alanları da tıklamaya dahil edildi. Job Properties sayfa satırları mevcut tam satır tıklama alanını korur.
- Ayarlar altı native sekmeye ayrıldı: Görünüm, SQL Editörü, Kısayollar, Çalışma Alanı, Güncellemeler, Güvenlik. Kart yüzeyleri, bölüm ikonları, sabit Uygula/geri bildirim alanı ve daha büyük, yeniden kullanılan pencere eklendi. Mevcut ayarlar, repo doğrulaması, Keychain işlemi ve yerel kayıt silme davranışları korundu. Kısayolların hemen kaydedildiği belirtilir.
- `/tmp/mssql-settings-final-tests.log`: 67 uygulama + 99 core = 166 test; 144 geçti, 22 dış koşul testi atlandı. Yeni native pencere testi boyutları ve aynı pencerenin yeniden kullanımını doğrular. `/tmp/mssql-settings-build.log`: Release BUILD SUCCEEDED (CODE_SIGNING_ALLOWED=NO). git diff --check temiz.
- `/tmp/MSSQLStudio-settings-ui/MSSQLStudio.app` ayrı UI-test kimliğiyle çevrimdışı açıldı. Altı sekmenin erişilebilirlik ağacı ve SQL Editörü görünümü kontrol edildi; SQL Editörü → Güncellemeler → SQL Editörü geçişinde kaydedilmemiş alias seçimi korundu ve NOLOCK kontrolü devre dışı kaldı. Uygula çalıştırılmadı. Hakkında ekranında 1440×1224 ekran görüntüsünde (250,525) noktasındaki, 0.2.43 yazısının sağındaki boş alana tıklama seçimi ve sürüm notlarını değiştirdi. Test kopyası kapatıldı; kurulu kullanıcı uygulaması değiştirilmedi.
- Keychain izin yenileme ve kayıt silme çalıştırılmadı; gerçek DB değişikliği yapılmadı. Bu değişiklikler henüz yayımlanmadı.

# Job adımı Komut alanında SQL renklendirme — 10 Ekim 2026

- AgentCommandEditor, ana editörün SQLSourceHighlighting renkleri/fontu ve kullanılmayan DECLARE analizini kullanır. Renkler karakterleri değiştirmeden nitelik olarak uygulanır; kaynak/tema değişmedikçe yeniden uygulanmaz. IME marked text sırasında biçimlendirme ertelenir. Genel tema dekorasyonu bu editörün syntax renklerini sıfırlamaz; editör tema bildirimini kendisi işler.
- Native test ilk aşamada undo sonrası metin–binding uyumsuzluğunu ortaya çıkardı. Renklendirme undo kaydına eklenmez; aynı editörün UndoManager undo/redo bildiriminde geri yüklenen metin binding'e senkronize edilip renklendirilir. Başka editörün undo bildirimi işlenmez. Son regresyon undo ve redo'nun hem metni hem binding'i ve DECLARE rengini koruduğunu doğrular.
- `/tmp/mssql-agent-command-all-tests.log`: 66 uygulama + 99 core = 165 test; 143 geçti, 22 koşullu atlandı. Yeni native NSHosting/NSTextView testi keyword, çok satırlı yorum, Unicode string ve kullanılmayan DECLARE renklerini, açık/koyu tema geçişini, seçimi, viewport'u, TextKit 2'yi, yazma/binding ve undo/redo'yu doğruladı.
- `/tmp/mssql-agent-command-final-build.log`: BUILD SUCCEEDED; imzasız yerel Release doğrulaması. Tüm build/test çıktıları /tmp altında. git diff --check temiz.
- Gerçek SQL Server/job üzerinde değişiklik yapılmadı. Yeni renklendirme özelliği henüz yayımlanmadı; son yayın v0.2.45.

# v0.2.45 yayın doğrulaması — 10 Ekim 2026

- Yayın: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.45 — draft değil; ZIP, PKG ve update.json mevcut.
- Kaynak commit: `ab5e74a072d45876dbb53daba91301a2ce210e4b`; uygulama sürümü 0.2.45, build 46.
- CI https://github.com/erhanulas/MSSQLStudio/actions/runs/38038044424 ilk çalışmada başarıyla tamamlandı. Kalıcı imza/izole Keychain regresyonu, imzalı uygulama ve installer, metadata kontrolü ve yayın paketiyle tüm testler geçti.
- ZIP SHA256: `441b39b63c26c5ef19ae3a423b72460a0612a1c321c85d6ce451fc72b436a64a`.
- PKG SHA256: `f8ecc1b8268bf504d6c9335e97435247ef6af60ac051260610971ebc2a3ce1ce`.
- Public latest update.json sürüm/adres/hash değerleri doğrulandı. Gerçek public ZIP indirilip SHA256 karşılaştırıldı; çıkarılan uygulama scripts/signing.py verify ile aynı pinlenen sertifika ve DR politikasından geçti. Kurulu kullanıcı uygulaması değiştirilmedi.
- Job adımı veritabanı seçimi, sayfa satırı tıklama alanı ve Keychain açıklamaları yayımlandı. Aşağıdaki “henüz yayımlanmadı” ifadeleri tarihsel yerel aşamayı anlatır. Fiziksel boş-alan tıklama ve gerçek kullanıcı oturumunda tam Keychain güncellemesi için önceki doğrulama sınırları geçerlidir. v0.2.44 yalnız başarısız yayın adayı etiketi olarak kaldı; yeniden yazılmadı.

# Yayın testi zamanlama düzeltmesi — 10 Ekim 2026

- v0.2.44 etiketi için CI 38037609105 iki denemede farklı mevcut editör testlerinde başarısız oldu: typingShortScriptKeepsViewportAndMetrics renklendirmeyi, indexedDiagnosticsAreDebouncedAndStaleEditsDoNotPublish diagnostics sonucunu sabit 450 ms sonunda hazır varsayıyordu. Paketler/imza ve yeni Agent testi geçti ancak yayın açılmadı. Etiket yeniden yazılmadı.
- İki test artık beklenen sonucu 50 ms aralıkla en fazla 5 saniye bekler; gerçek sonuç beklentileri korunur. Uygulama kodu bu düzeltmede değişmedi. Yerel tam test `/tmp/mssql-v45-tests.log`: 65 uygulama + 99 core, 142 geçti, 22 koşullu atlandı.
- Yeni yayın adayı v0.2.45 / build 46; v0.2.44 yayınlanmış sürüm olarak sunulmaz.

# Job adımı veritabanı seçimi ve sayfa tıklama alanı — 10 Ekim 2026

- T-SQL adımında serbest metin yerine veritabanı Picker eklendi. Ayrı metadata bağlantısından Catalog.databases okunur; satır/byte/timeout sınırları 5000 / 8 MB / 15 sn. Mevcut seçim listede yoksa korunur. Boş/kısmi/hatalı sonuçlar görünür; yenileme sırasında önceki liste/seçim tutulur. Salt okunur diğer subsystem türleri metadata okumaz.
- Job Properties sayfa düğmesinin Text/frame/padding alanına Rectangle contentShape eklendi. Seçili sayfa semibold, zemin rengi ve accessibility isSelected ile belirtilir.
- `/tmp/mssql-agent-picker-verified.log`: ManagementWorkspaceTests 10/10 geçti. Yeni native test T-SQL adımının açılışta yalnız Catalog.databases okuduğunu ve CmdExec adımının ek sorgu göndermediğini doğruladı.
- `/tmp/mssql-agent-picker-all-tests.log`: 65 uygulama + 99 core = 164 test; 142 geçti, 22 koşullu atlandı. Son Release derlemesi `/tmp/mssql-agent-picker-build.log`: BUILD SUCCEEDED; imzasız yerel doğrulama.
- Gerçek kullanıcı uygulamasından ayrı, local.mssqlstudio.uitest kimliğiyle sentetik UI smoke çalıştırıldı. Veritabanı menüsünde DemoDB/master/Reporting görüldü; Reporting seçildi ve SQL önizlemesinde @database_name=N'Reporting' doğrulandı. Adımlar sayfasının seçili erişilebilirlik durumu doğrulandı. Sentetik uygulama kapatıldı; gerçek bağlantı ve job'lara işlem yapılmadı.
- Sayfa metni dışındaki alan için iki koordinatlı UI denemesi sayfa değiştirmedi; koordinat eşlemesi kesinleştirilmediği için bunlar başarılı tıklama testi sayılmadı. Geniş tıklama alanı kaynakta düzeltildi; bu alanın fiziksel fareyle uçtan uca doğrulaması sınırlı kaldı.
- İlk test denemeleri SwiftUI Picker'ı NSPopUpButton/yerel AX descendant olarak bulamadı; başarısız introspection doğrulaması başarı gibi raporlanmadı. Seçim ve SQL aktarımı harici UI erişilebilirlik kontrolüyle doğrulandı. Gerçek SQL Server üzerinde yeni canlı test yapılmadı. Henüz yeni release yayımlanmadı; sürüm 0.2.43.

# Keychain ve kalıcı imza incelemesi — 10 Ekim 2026

- Kurulu uygulama v0.2.43 ve GitHub'dan indirilen v0.2.42/v0.2.43 ZIP'leri aynı sertifika pinini ve aynı designated requirement'ı doğruladı: `identifier "local.mssqlstudio.app" and certificate leaf = H"adce16b1a3567d8c5fe2ed261e89493611cb7b9d"`. Bundle ID/service değiştirilmedi. Sertifika 9 Ekim 2026–6 Ekim 2036 UTC. Bu Mac'te kullanılabilir yayın özel anahtarı bulunmadı; CI'deki mevcut kimlik korundu.
- Tarihsel build script'i yalnızca Xcode ad-hoc imzasını doğruluyordu; 7442396 commit'i kalıcı sertifika ve açık DR politikasını eklemiş. İkili içerik hash'inin değişmesi normaldir. Güncel iki sürümde sertifika değişimi tespit edilmedi; eski ACL'lerin mevcut istemin tek nedeni olduğu kesinleştirilmedi.
- Gerçek service üzerinde yalnızca metadata/ACL okundu; parola, hesap adı, profil veya bağlantı verisi loglanmadı. İlk denetimde 1 kayıt, 1 decrypt ACL, 29 güvenilen uygulama girdisi ve 0 sınırsız decrypt girdisi bulundu. Önceki derlemelere ait izin birikimi olasıdır; herkese açık erişim saptanmadı.
- Kullanıcı sistem onayını tamamladıktan sonra kurulu uygulama “1 bağlantının erişim izni yenilendi” sonucunu verdi. Son metadata kontrolünde 1 kayıt korunuyor, 2 decrypt ACL / 30 güvenilen uygulama girdisi / 0 sınırsız decrypt girdisi vardı. İşlem eski ACL girdilerini sıfırlamaz; çağıran imzalı uygulamanın erişimini yeniler. Kayıt değerleri bu incelemede okunmadı, silinmedi veya dışarı aktarılmadı. Profil/parola değerlerinin karşılaştırmalı canlı testi yapılmadı.
- Yeni elle çalıştırılan `signing-audit.yml`: https://github.com/erhanulas/MSSQLStudio/actions/runs/38036998834 — başarı. Kaynak `6bd7db89b163e38cff033d765b002abd339a5465`. Mevcut Actions secrets ile aynı kimlik geçici Keychain'e aktarıldı; iş sonunda temizlendi. İki farklı imzalı derleme, gerçek ServerVault create/update/list koduyla geçici sentetik Keychain üzerinde test edildi. İkinci derleme ve taşınmış dosya yolu, kullanıcı etkileşimi kapalıyken aynı profil/parolayı okudu; kayıt güncellemesinden sonra ilk derleme de okuyabildi. Ad-hoc ikili hem okumada hem izin yenilemede reddedildi. Resmi v0.2.42/v0.2.43 ZIP'lerinin pinlenen kimliği CI'de de doğrulandı.
- İlk genişletilmiş audit https://github.com/erhanulas/MSSQLStudio/actions/runs/38036847253 başarısızdı: ACL yenilemeyi başsız ortamda onaysız başarıyla tamamlama varsayımı doğru değildi; 20 saniyelik subprocess timeout oluştu. Bu sonuç başarı gibi raporlanmadı. Etkileşimli sahiplik onayı ayrı yerel doğrulamaya ayrıldı; CI testi sürümler arası okumayı ve imza reddini sınar.
- Son UI açıklaması koşulsuz “parola istemez” garantisi vermez ve eski izinlerin otomatik silinmediğini açıklar. Yerel son Release derlemesi `/tmp/mssql-keychain-audit/build-final.log`: BUILD SUCCEEDED; CODE_SIGNING_ALLOWED=NO. İmza davranışı değiştirilmedi; uygulama davranışına ilişkin yeni testler CI'deki Vault regresyonudur. Bu incelemede tüm uygulama test paketi tekrar çalıştırılmadı.
- `spctl --assess --type execute` v0.2.43 ZIP uygulamasını reddetti. Kişisel sertifika Apple Developer ID / notarization sağlamaz. Gatekeeper, trust veya kullanıcı Keychain güvenliği gevşetilmedi; sertifika/özel anahtar depoya eklenmedi.
- Sınır: gerçek kullanıcının çalışan uygulaması eski sürüme düşürülüp yeniden yükseltilmedi, oturumlar kapatılmadı. İki resmi paketin kimlik eşitliği + sentetik ikililer arası parolasız okuma doğrulandı; gerçek kullanıcı oturumunda tam güncellemenin hiç parola istemeyeceği kesin çözüm olarak sunulamaz. Yeni workflow/test ve belge main'e gönderildi; yeni release oluşturulmadı, yayın v0.2.43.

# v0.2.43 yayın doğrulaması — 10 Ekim 2026

- Yayın: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.43
- Kaynak commit: `c884a4dd3cf076d77fb9e92c04124f8e9913ab12`; uygulama sürümü 0.2.43, build 44.
- GitHub Actions https://github.com/erhanulas/MSSQLStudio/actions/runs/38036179236 ilk çalışmada başarıyla tamamlandı. Kalıcı imza/izole Keychain fixture, imzalı uygulama ve installer, yayın metadata doğrulaması ve yayın paketiyle testler geçti.
- ZIP SHA256: `26e836db9896d2935f27f253a2a6ffdc3ccb1d88f8811522809d310d6e7cebc4`.
- PKG SHA256: `3d68111a38aff784e57b6d6570f8407b7f53b942b39eb25a334c58cd9fffe1c2`.
- Public latest update.json indirildi: sürüm 0.2.43, ZIP adresi doğru ve SHA256 GitHub asset digest ile eşleşiyor. Yayın draft değil; ZIP, PKG ve update.json mevcut.
- Aşağıdaki “henüz yayımlanmadı” ifadeleri yerel geliştirme aşamasının tarihsel kayıtlarıdır; Explorer, Linked Server, 7 günlük geçmiş ve Agent/sekme iyileştirmeleri bu sürümde yayımlandı. Canlı SQL Server/Linked Server doğrulama sınırları geçerliliğini korur.

# Agent otomatik yenileme ve yükleme davranışı — 10 Ekim 2026

- Görünür Explorer'da Agent dalı açıkken yüklenmiş Jobs listesi 15 saniyede bir, önceki istek tamamlandıktan sonra yenilenir. Kapalı dal/bağlantı ve gizli/küçültülmüş pencerede yeni okuma yapılmaz. Menüden durdurulabilir. Satır nesneleri ad üzerinden korunur; seçim ve kaydırma konumu geri yüklenir. Job/trigger durum yazıları kaldırıldı; ikon, tooltip ve VoiceOver durumu korur.
- Job History varsayılanı 7 gün ve özet sonuçlardır. Adım ayrıntıları isteğe bağlıdır. Özet SQL önceki outcome aramasını içermez; adım modu çalışma/adım eşleştirmesini korur. Decode/historyTree ve job özellik decode işlemleri detached worker task üzerinde yapılır. Yenilemede eski sonuçlar korunur, yükleme açıklaması gösterilir. Aynı job için görünür geçmiş/özellik penceresi yeniden kullanılır.
- QueryController çalışan sorgunun UI bildirimlerini 50 ms birleştirir; sekme çubuğu render imzası değişmeden yeniden oluşturulmaz. Bağlanan/çalışan sekmede native spinner vardır. Metadata sorgularında Task iptali ODBC cancel'a iletilir; canlı driver iptali bu görevde test edilmedi.
- Tam doğrulama: `/tmp/mssql-agent-responsive-all-verified.log` — 64 uygulama + 99 core = 163 test; 141 geçti, 22 koşullu atlandı. Build/test çıktıları `/tmp` altında üretildi.
- Yeni native testler: Agent kapalıyken sorgu yok; açık Jobs yenilemesinde aynı satır/ikon güncellenir ve seçili satır korunur; bağlantı kapanınca sorgu yok. Çalışan sorgu sırasında gerçek sekme düğmesinin eylemiyle diğer sekmeye geçiş doğrulandı. Aynı job geçmişi iki kez açılınca tek görünür pencere ve tek özet metadata sorgusu oluştu. Eski adım-ağacı testi açık ayrıntı modunda çalıştırıldı.
- Native testte NSButton.performClick ile test helper erken kapanıyordu; uygulamanın mouseDown yolunda kullandığı sendAction ile sekme eylemi gönderilince test tamamlandı. Tam test sonucu yalnız tamamlanan doğrulama çalışmasına dayanır.
- Son Release derlemesi `/tmp/mssql-agent-responsive-final-build.log`: BUILD SUCCEEDED; imzasız yerel doğrulama.
- Gerçek SQL Server/Agent üzerinde gecikme, otomatik yenileme ve iptal ölçülmedi; kullanıcı job'larına işlem yapılmadı. Genel arayüzdeki tüm olası performans sorunlarının çözüldüğü iddia edilmez. Henüz yayımlanmadı; sürüm 0.2.42.

# Linked Server nesne gezintisi — 10 Ekim 2026

- SSMS/OLE DB metadata yaklaşımı araştırıldı: Catalogs → katalog → sağlayıcının bildirdiği Tables, Views, sistem tabloları/view'ları, synonym/alias, geçici ve diğer nesne türleri. Nesne altında Columns gezintisi eklendi. Rutin klasörleri ve uzak DDL/düzenleme desteği oluşturulmadı.
- Mevcut yerel SQL Server üzerinden sp_catalogs/sp_tables_ex/sp_columns_ex kullanılır; uzak sunucuya doğrudan oturum açılmaz. Katalogsuz/şemasız nesnelerin dört parçalı adı boş bileşenleri korur. Literal ve identifier helper'ları kullanılır; tablo listelemede pattern matching kapalıdır. Sağlayıcı kısıtları yok sayarsa başka katalog/şema/nesne satırları ayıklanır.
- Native menü, uzak nesneler için yerel Design/Edit/ALTER/Delete seçeneklerini sunmaz. SELECT SQL'i önce editöre alınabilir veya açık Select Top 1000 Rows eylemiyle okunabilir; tam ad kopyalanabilir. Linked Server kökünde Test Connection ve salt okunur özellikler mevcut.
- Metadata sınırları 5.000 satır / 8 MB / 30 saniye sorgu timeout'u. Kısmi liste, boş metadata ve sağlayıcı format hatası görünür; katalog adlarını döndürmeyen sağlayıcılarda varsayılan katalog dalı vardır. Bağlantı değiştikten sonra eski metadata sonuçları yayımlanmaz.
- `/tmp/mssql-linked-verified-tests.log`: 62 uygulama + 99 core = 161 test; 139 geçti, 22 koşullu atlandı. Native NSOutlineView testi linked sunucu → katalog → tablo/view/sistem view → sütun akışını, güvenli menüleri ve dört parçalı SELECT metnini doğruladı. Ek native test boş/kısmi/hatalı sağlayıcı yanıtlarını doğruladı. Core testler ad escaping, null qualifier, metadata türleri ve tam nesne kimliği filtrelemesini kapsar.
- Son Release derlemesi `/tmp/mssql-linked-build-final.log`: BUILD SUCCEEDED; imzasız yerel doğrulama.
- Gerçek Linked Server sağlayıcısı/yetkileri ile canlı test yapılmadı. Sağlayıcı CATALOGS/TABLES/COLUMNS metadata desteği ve yerel Linked Server ayarları gerçek görünürlüğü belirler. Kullanıcı verisine veya bağlantı ayarlarına yazılmadı. Henüz yayımlanmadı; sürüm 0.2.42.
- Aynı çalışma ağacındaki Job History açılış filtresi 30 günden 7 güne değiştirildi; farklı tarih aralığı seçenekleri korunuyor.

# Explorer bağlantı yönetimi — 10 Ekim 2026

- Kapalı sunucular ve yüklenmiş ağaç korunur. Explorer bağlantısını kesmek sorgu oturumlarını, metni veya transaction'ı kapatmaz. Yeniden bağlantı aynı ConnectedServer nesnesini kullanır; aynı bağlantı ayarlarında metadata bağlantısı yenilenir, sorgu oturumları değiştirilmez.
- Satırdaki durum metni/simge, yeniden bağlanma menüsü, çevrimdışı Yenile ve çift tıklama akışı eklendi. Başarısız yeniden bağlantı hatası sunucu satırında kalır; SQL otomatik çalışmaz. Yetki hataları ile ODBC 08 sınıfı bağlantı hataları ayrılır.
- Tam test çalışması: `/tmp/mssql-explorer-final-tests.log` — 60 uygulama + 96 core = 156 test; 134 geçti, 22 koşullu atlandı. Son düzenleme sonrası native Explorer smoke: `/tmp/mssql-explorer-smoke.log` — 2/2 geçti.
- Native NSOutlineView testi, bağlantı kesildikten sonra aynı root/çocukların, açık sekme kimliğinin, SQL metninin, ready durumunun ve transaction sayısının korunmasını doğrular; bağlantı durum etiketleri ve ODBC hata sınıfları da kontrol edilir.
- Son Release derlemesi: `/tmp/mssql-explorer-build-final.log` — BUILD SUCCEEDED, imzasız yerel doğrulama.
- Canlı bağlantıyı kesip yeniden bağlama testi genişletildi ancak test parolası verilmediği için çalıştırılmadı. Gerçek sunuculara, Keychain kayıtlarına ve kullanıcı sorgularına müdahale edilmedi. Bu değişiklikler henüz GitHub'da yayımlanmadı; sürüm 0.2.42 kaldı.

# v0.2.42 yayın doğrulaması — 10 Ekim 2026

- Yayın: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.42
- Kaynak commit: `e6fe811b5abf3ae6853332fd109a3ee7f4c871de`; uygulama sürümü 0.2.42, build 43.
- GitHub Actions: https://github.com/erhanulas/MSSQLStudio/actions/runs/38014101474 — yeniden çalıştırma başarılı. Kalıcı imza, izole Keychain testi, imzalı uygulama ve kurulum paketi, paket doğrulaması ve paketle test aşamaları geçti.
- İlk denemede `indexedDiagnosticsAreDebouncedAndStaleEditsDoNotPublish` zamanlamaya duyarlı beklentileri başarısız oldu. Aynı kaynakla ikinci deneme geçti; test kararsızlığı ayrıca izlenmeli.
- İlk v0.2.41 etiketi sürüm hazırlama hatası nedeniyle yayın oluşturmadı. Etiket değiştirilmeden düzeltilmiş v0.2.42 yayımlandı.
- Public latest release taslak değil; ZIP, PKG ve update.json mevcut. Public güncelleme bildirimi 0.2.42 sürümünü gösteriyor ve ZIP özeti GitHub asset özetiyle eşleşiyor.
- ZIP SHA-256: `fcbfe139c56a04ee760d91842218e86db26be1281a29fd1f7af7ca6c6051418e`.
- Aşağıdaki geliştirme doğrulamasındaki henüz yayımlanmadı ifadeleri yerel doğrulama aşamasının tarihsel kaydıdır; bu yayınla değişiklikler dağıtıma çıktı.

# SQL Server Agent — SSMS akışı geliştirme doğrulaması

10 Ekim 2026. 59 uygulama + 96 core = 155 raporlanan test: 133 geçti, 22 koşullu test atlandı (`/tmp/mssql-agent-tests-complete.log`). Yeni testler: iş sonucu filtresinde alt adımların bağlamını koruma, farklı job/run kayıtlarının karışmaması, tekrar/severity/uzun süre çözümü, Unicode ve tırnak kaçışı, geçersiz hedef/tekrar aralığı, değişmeyen sahiplik ve eski pager/net send ayarlarını koruma, stored procedure dönüş kodları/transaction ve version_number koruması, takvim/saat/haftalık bitmask doğrulaması, ortak zamanlamayı bağlama/ayırma. Native test, geçmiş ve özellikleri açmanın yalnız iki metadata okuması yaptığını ve hiçbir SQL üretme/çalıştırma callback'i çağırmadığını; gerçek NSOutlineView'da iki sonucun açıldığında beş satıra genişlediğini doğrular.

Son Release build başarılı (`/tmp/mssql-agent-build-final-checked.log`). Son küçük düzeltme, henüz adımı olmayan bir job’ın genel özelliklerini başlangıç adımını değiştirmeden düzenlemeyi de korur; ilgili ManagementWorkflowTests tekrar koşusunda 12 raporlanan test (10 geçti, 2 koşullu canlı test atlandı) başarılı (`/tmp/mssql-agent-final-core.log`). Son arayüz kontrolünde daha büyük mesaj alanı, grup ayıracı olmadan 50000 mesaj kimliği, seçili satırda okunur durum metni, mevcut zamanlama seçicisinin zaten bağlı zamanlamayı hariç tutması ve çift tıklama ile düzenleyici açılması da doğrulandı. Pencereler ekranın görünür alanına sığdırılıyor. Üretim imzalı ZIP/PKG ve GitHub yayını bu görevde yapılmadı. Uygulamanın sürüm numarası 0.2.40 olarak bırakıldı.

Native smoke ayrı `local.mssqlstudio.uitest` kimlikli çevrimdışı Release kopyasıyla, sentetik veriler kullanılarak yapıldı: başarısız çalışma altında başarılı adım/Retry/Failed, durum filtresi sonrası alt satır ve seçim korunması, severity 16/mesaj 50000/iki tekrar ve çok satırlı mesaj ayrıntıları; soldan özellik sayfaları, başlangıç adımı, ayrı Genel/Gelişmiş adım düzenleyicisi, SQL yazma/undo; tekrar sayısını 2'den 3'e değiştirdikten sonra guarded SQL sekmesine aktarma; haftalık Pzt/Çar seçimine Cum eklenince @freq_interval=42 üretimi; üç işe bağlı zamanlama uyarısı/native tarih-saat seçicileri; Activity Monitor son/sonraki çalışma ve seçime göre başlat/etkinleştir açık, durdur kapalı durumu doğrulandı. Hiçbir job başlatılmadı/durdurulmadı veya metadata değişikliği çalıştırılmadı. Test kopyası kapatıldı; gerçek kullanıcı bağlantıları, parolaları ve job'ları kullanılmadı.

Sınırlamalar: canlı Agent/Database Mail/yetki ve gerçek eşzamanlı msdb değişikliği bu tur test edilmedi. Koşullu localhost Agent testleri etkinleştirilmedi. T-SQL dışı subsystem, uyarı ve hedefler salt okunur; step yeniden sıralama/taşıma, multiserver dağıtımı, Agent servis yönetimi ve SSMS'in tüm log dışa aktarma/temizleme işlevleri eklenmedi. Tam SSMS eşdeğerliği iddia edilmez. Geçmiş sadece tamamlanmış iş sonuçlarına bağlı mevcut adımları gruplar; saklama politikasıyla silinmiş kayıtları geri getiremez.

# MSSQL Studio 0.2.40 — yayın doğrulaması

10 Ekim 2026. `61e5a57` commit’i `v0.2.40` etiketiyle yayımlandı. GitHub Actions: https://github.com/erhanulas/MSSQLStudio/actions/runs/38012283943 . Kalıcı üretim imzasıyla gerçek ServerVault create/update/read ve ad-hoc reddi testi, imzalı uygulama/PKG derlemesi, paket/manifest doğrulaması ve yayın paketiyle testler başarılı. ZIP, PKG ve update.json yayımlandı; latest sürüm ve herkese açık latest/download/update.json 0.2.40 olarak doğrulandı. ZIP SHA-256: `85f899fae99ecd55f3ba3f33dc6cdf7164ce77a10f5c4f1d8abb549f9243e383`.

Eski kullanıcı ACL'lerini sistem onayıyla yenileme bu yayında kullanıcı tarafından doğrulanmalıdır; gerçek kullanıcı kayıtları test edilmedi/değiştirilmedi. Kurulu uygulamaya bu görevde müdahale edilmedi. Aşağıdaki henüz yayımlanmadı/üretim sertifikasıyla çalıştırılmadı ifadeleri yayın öncesi yerel test aşamasına aittir.

# Keychain izinleri — yerel geliştirme doğrulaması

10 Ekim 2026. Yeni kayıtlar uygulamaya özel SecAccess ve anlaşılır etiketle oluşturulur. Normal parola güncellemesi ACL'yi tekrar yazmaz. Ayarlardaki açık izin yenileme işlemi önce kalıcı yayın imzasını doğrular, yalnız `local.mssqlstudio.servers` hizmetindeki UUID hesaplarının ACL/etiketini değiştirir; secret verisini okumaz veya değiştirmez. Kurulu uygulamanın mevcut kalıcı designated requirement imzası geçerli bulundu. Kullanıcıya ait bağlantılar/anahtar zinciri kayıtları okunmadı, değiştirilmedi.

Son Release build başarılı (`/tmp/mssql-keychain-final-build.log`). 58 uygulama + 91 core = 149 raporlanan test; 127 geçti, 22 koşullu test atlandı (`/tmp/mssql-keychain-final-tests.log`). Gerçek ServerVault kaynak kodunu derleyen imza regresyonu ayrı geçici sertifika ve ayrı sentetik anahtar zinciriyle geçti: iki farklı derleme arasında UI olmadan create/update/read, ad-hoc uygulamaya okuma ve yenileme reddi, sentetik kayıt/anahtar zinciri temizliği (`/tmp/mssql-vault-isolated-final.log`). Üretim özel imza anahtarı yerelde bulunmadığı için bu tur üretim sertifikasıyla imzalı paket/CI koşusu yapılmadı.

Eski ACL'yi yenileme yerel başsız testte macOS onayını bekledi; bu senaryo başarılı sayılmadı. Gerçek kullanıcı kayıtlarının yenilenmesi kalıcı imzalı yayında kullanıcının sistem onayıyla doğrulanmalıdır. İşlemin bir defalık parola/onay gerektirebileceği arayüzde belirtilir. Kilitli anahtar zinciri gibi OS nedenleriyle bütün parola pencerelerinin yok olacağı garantisi verilmez.

Native smoke: ayrı `local.mssqlstudio.uitest` kimlikli çevrimdışı Release kopyası açıldı; Ayarlar ekranındaki açıklama ve `renewKeychainAccess` düğmesi AX ve görsel olarak doğrulandı. Gerçek izin yenileme düğmesine basılmadı. Test kopyası kapatıldı; kurulu uygulama ve açık kullanıcı oturumu değiştirilmedi. Bu düzeltme henüz GitHub'a yayımlanmadı.

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


## 10 Ekim 2026 — sonuç grid’i doğrudan düzenleme ve bekleyen SQL akışı

- DataGrip resmi Cells ve Submit changes dokümanları incelendi: hücrede yerel değişiklik, Enter/Escape, bekleyen DML önizlemesi ve ayrı gönderme. Kaynaklar: https://www.jetbrains.com/help/datagrip/cells.html ve https://www.jetbrains.com/help/datagrip/submitting-and-reverting-changes.html .
- Gereksiz normal PK kilidi kaldırıldı; UPDATE SET yeni anahtar, WHERE eski anahtar + mevcut optimistic kontroller kullanır. IDENTITY/computed/rowversion ve desteklenmeyen türler kilit simgesi/tooltip/açıklamayla salt okunur kalır.
- Çift tıklama / Enter kaynak doğrulamasından sonra native hücreyi açar; salt okunur sonuçların tam değer görüntülemesi korunur. Async cevapta kaynak hücre kimliği yeniden denetlenir.
- Field editor textDidChange yalnız taslak durumunu bildirir; spool/satır sözlüğünü değiştirmeden SQL Önizle ve Gönder düğmesi etkinleşir. Önizleme önce native edit’i commit eder, SQL’i gösterir ve açık onayla gönderir. Escape abortEditing yoluyla iptal edilir; değişmeyen NULL/DEFAULT görüntüsü veri haline getirilmez.
- Son doğrulama: 77 uygulama + 106 core = 183 test; 160 geçti, 23 dış koşullu test atlandı. Log `/tmp/mssql-grid-final-verified.log`. Native testlerde doğrudan edit başlangıcı, anlık taslak bildirimi, uzun değer, Escape iptali, PK eski/yeni predicate, generated engeli, kaynak satır/kolon taşıma ve iki toolbar’ın 830 pt pencereye sığması kontrol edildi.
- İzole fixture görüntüsü `/tmp/mssql-grid-direct-ui.png` incelendi; kilit ikonu ve önizleme çubuğu görünür, taşma yok. Release derlemesi başarılı: `/tmp/mssql-grid-final-release.log`. `git diff --check` temiz.
- Ara kontrolde testin doğrudan NSTextView cancelOperation çağrısı geçersiz selector üretti; gerçek Escape tuş olayı kullanıldı. Bu yol taslak durumunun açık kaldığını ortaya çıkardı; native komut/abortEditing düzeltmesi sonrası son tam test geçti.
- Canlı SQL yazma testi yapılmadı; kullanıcı uygulaması/Keychain/veritabanına dokunulmadı. Bu çalışma henüz yayımlanmadı.


## 10 Ekim 2026 — v0.2.55 yayın öncesi kolon/checkbox doğrulaması

- Kolon başlıkları gerçek native font ölçümü + 80 pt ikon/kenar payıyla boyutlandırılır. Örnek değer ölçümü başlık genişliğini azaltmaz; uzun başlık sabit 420/600 pt sınıra takılmaz. Manuel daraltma ve tam ad tooltip’i korunur.
- Filtre hit alanı sağ dış 12 pt native resize alanından ayrıldı; filtre alanında sürükleme popup açmaz. False bit boş kontur, true native işaretli checkbox olarak çizilir.
- Son tam test: 78 uygulama + 106 core = 184 test; 161 geçti, 23 dış koşullu test atlandı. Log `/tmp/mssql-v55-final-tests.log`; uzun başlık genişliği, resize kenarının filtre hit alanı dışında kalması, önceki native düzenleme/iptal/SQL kontrolleri geçti.
- Release build başarılı (`/tmp/mssql-v55-build.log`), diff kontrolü temiz. `/tmp/mssql-v55-header-checkbox.png` ve düzenleme toolbar fixture’ı görsel olarak incelendi. Canlı SQL yazma yapılmadı; gerçek kullanıcı app’i/Keychain korunuyor.
- Sürüm 0.2.55 / build 56 yayımlandı: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.55 . Kaynak `8b501d882a9a03689f253a09185a3f8afd5fe8d1`; Actions `38051856183` başarıyla tamamlandı (sabit imza, izole Keychain fixture, paket doğrulaması ve yayın paketi testleri dahil).
- Public latest v0.2.55; ZIP/PKG/update.json erişilebilir. İndirilen ZIP SHA-256 `0617bf453026aff44300dad504e356b7434f9b0e0dabc6cfb5224268ccec25b1`, PKG `a10259c1eb48e962f19511d06262c90598755fa048acd9b6a9b16215f045d91a`; manifest ve GitHub digest ile eşleşiyor.
- `/tmp/mssql-v55-verify/extracted/MSSQLStudio.app` strict/deep codesign doğrulamasından geçti; version/build 0.2.55/56, sabit DR `identifier "local.mssqlstudio.app" and certificate leaf = H"adce16b1a3567d8c5fe2ed261e89493611cb7b9d"` doğrulandı. Gerçek kullanıcı uygulaması yüklenmedi/değiştirilmedi.


## 10 Ekim 2026 — SQL alias veri tiplerinde hücre düzenleme

- `[dbo].[TDBGRUPKOD]` gibi alias tipler artık genel UDT engeline takılmaz. sys.types.system_type_id üzerinden temel tip, kolon uzunluğu (Unicode için bayt/2), precision/scale çözülür. CLR/table türleri ve çözülemeyen metadata salt okunur kalır.
- TableColumn özgün `type` adını ve ayrı `baseType` metadata’sını korur; CREATE/DDL özel tipi değiştirmez. Değer SQL’i alias adıyla CONVERT üretmez; temel tip kullanır. String conflict kontrolünün binary karşılaştırması korunur; numeric/binary/null ve INSERT dönüşümleri aynı çözümlemeyi kullanır. Gönderim öncesi kolon eşitlik kontrolü baseType değişikliğini de reddeder.
- Microsoft kaynakları: https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-types-transact-sql ve https://learn.microsoft.com/en-us/sql/t-sql/functions/cast-and-convert-transact-sql (alias tip CONVERT hedefi olamaz).
- Son test: 79 uygulama + 108 core = 187 test, 164 geçti, 23 dış koşullu test atlandı. `/tmp/mssql-alias-final-tests.log`. Metadata decode/orijinal DDL tipi, alias anahtar UPDATE/eski değer, decimal(28,8), binary hex doğrulama, NULL/INSERT ve grid hücre düzenlenebilirliği sınandı. Bilinmeyen CLR/spatial türlerin salt okunur kalması doğrulandı.
- Release derlemesi başarılı: `/tmp/mssql-alias-build.log`; `git diff --check` temiz. Kullanıcının gerçek tipi veya canlı DB yazımı test edilmedi; kullanıcı uygulamasına/Keychain’e dokunulmadı. Henüz yayımlanmadı.


## 10 Ekim 2026 — v0.2.56 yayın doğrulaması

- Alias veri tipi düzeltmesi v0.2.56 / build 57 olarak yayımlandı: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.56 . Kaynak `ca3a9daf103a7f436996e92e8aa9c422c15b268b`; Actions `38052622305` başarılı (sabit imza/izole Keychain fixture, imzalı uygulama/installer, manifest ve yayın paketi testleri).
- Public latest v0.2.56; ZIP, PKG ve update.json doğrulandı. İndirilen ZIP SHA-256 `c1c46a853208f3a58637dd76cd41be3d306a61b9163b71e8235fa1f27d88fdf8`, PKG `578c9bf2bafdc8ee14159543683b0ebaf19d0377478b9fe622cdc3a431d0bb43`; manifest ve GitHub digest eşleşiyor.
- `/tmp/mssql-v56-verify/extracted/MSSQLStudio.app` strict/deep codesign doğrulamasından geçti. Sürüm/build 0.2.56/57, sabit DR `identifier "local.mssqlstudio.app" and certificate leaf = H"adce16b1a3567d8c5fe2ed261e89493611cb7b9d"` doğrulandı. Gerçek kullanıcı app’i yüklenmedi/değiştirilmedi; canlı DB yazımı test edilmedi.


## 10 Ekim 2026 — diskten düzenleme hazırlığı ve sonuç görünümü

- Düzenleme hazırlığı mevcut SQLite katalog dosyasına eklenen `editing_metadata` tablosunu kullanır. Scope endpoint/login/server UUID/veritabanı; anahtar tam SQL + ordinal kolon ad/tip imzasının SHA-256’sıdır. İlk geçerli hazırlık sunucudan DMF + object ID + tablo metadata okur; aynı sorgu/kolonlar için sonraki hazırlık diskten yapılır. Cache okuma/yazma hatası sunucu fallback’ini engellemez. Eski disk indeksinde bu bilgiler yoktur; ilk kullanımın ağ okuması gereklidir.
- Cache TTL 24 saat, kayıt 1 MB, scope 128, toplam 4096 kayıt / 16 MB payload sınırı vardır. Sorgu metni, satır değerleri, default/computed SQL gövdeleri saklanmaz. Tam kolon metadata hash’i değişim kontrolünde kullanılır; cached kolonlarda yalnız computed niteliği kalır. Katalog build/target yenileme ve gönderim öncesi canlı kontrol hatasında scope cache’i silinir.
- Gönderimden önce canlı DMF source schema/table/kolon sırası ve güncel tablo PK/kolon metadata hash’i tekrar doğrulanır. Önceki OBJECT_ID, server/result generation, SQL preview eşitliği, orijinal değer/rowversion ve @@ROWCOUNT transaction kontrolleri korunur. İlk açılışı hızlandırmak için canlı gönderim doğrulaması atlanmaz.
- Sonuç çubuğunda ortak ölçülü ikon düğmeleri, ad/tip içeren iki satırlı başlıklar, yükleme ve kolon arama panelleri eklendi. Kolon arama varsayılan ⌘⇧J; Ayarlar → Kısayollar’dan değişebilir. Gizli/taşınmış kolonlar ordinal kimliğiyle açılıp görünür alana kaydırılır; Enter ilk eşleşmeye gider.
- Yükleme paneli özel okuma sınırı (1–5.000.000), sayfa boyutu (0–1.000.000) ve yenileme (0–3.600 sn) sunar; isteğe bağlı yeni sorgu varsayılanı kaydeder. Ayarlar → Sonuçlar aynı varsayılanları yönetir. Okuma sınırı sonraki sorguda uygulanır; mevcut sorgular global ayarla kendiliğinden değişmez. Başarılı SELECT dışındaki/transaction içindeki ve düzenleme açık durumlarda auto refresh başlamaz. Önceki 64 MB/60 sn veya 2 GB/600 sn bütçeleri korunur.
- SQLReadOnlyPreview ana editörün SQLSourceHighlighting/StudioTheme renklerini kullanır; sqlSourcePreview kimliği genel tema taramasının renkleri ezmesini önler. TextKit 2, native satır numarası cetveli, yatay kaydırma, açık/koyu temada seçim/viewport korunması vardır. Önizleme bilgi/SQL/onay alanları yeniden düzenlendi.
- Son test: 83 uygulama + 110 core = 193 test; 170 geçti, 23 dış koşullu test atlandı. Log `/tmp/mssql-premium-release-ready-tests.log`. Miss → 3 metadata çağrısı → disk hit’te 0 ek çağrı; uygulama yeniden açılışı, query/projection/DB scope ayrımı, expiry/invalidation, canlı kaynak eşleşmesi ve schema/default/baseType hash değişimi sınandı. Native testler kolon ordinal reveal/kısayol çakışması, yükleme varsayılanları, tema rengi/TextKit 2/seçim ve 830 pt toolbar kontrolünü kapsar.
- Release build başarılı: `/tmp/mssql-premium-release-ready-build.log`. `git diff --check` temiz. `/tmp/mssql-data-preview-ui.png`, `/tmp/mssql-grid-direct-ui.png`, `/tmp/mssql-premium-loading.png`, `/tmp/mssql-premium-columns.png` görsel olarak incelendi; renk, satır numarası, hizalama ve kompakt panel yerleşimi uygun.
- Ara testte eski İngilizce menü başlığı beklentisi Türkçe yeni etikete uyarlandı. Bir tam test çalışması NSTextFinderIndicatorManager._delayedUpdate içinde SIGSEGV ile kesildi; eski find testi pencereyi gecikmiş native gösterge güncellemesi bitmeden serbest bırakıyordu. Test artık find arayüzünü kapatıp client’ı 400 ms tutuyor. Son tam çalışma başarılı; çökme olan ara çalışma başarı sayılmadı. Ara Release kontrolünde eşzamanlı kaynak/API derlemesi tutarsızlığı son kaynakla yeniden derlenerek giderildi.
- Canlı SQL yazımı ve uzak sunucu süre karşılaştırması yapılmadı; hız kazanımı fixture’da ağ çağrılarının sıfırlanmasıyla doğrulandı. Gerçek kullanıcı uygulaması/Keychain/DB değiştirilmedi. Henüz yayımlanmadı.


## 10 Ekim 2026 — v0.2.57 yayın doğrulaması

- Kaynak `fd860d7014dcae01e0f6c630478803c598137884`; v0.2.57 / build 58. Actions `38054420471` başarılı: sabit kimlik/izole Keychain, imzalı build, manifest ve yayın paketi testleri geçti.
- Public latest: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.57 ; ZIP, PKG ve update.json erişilebilir. İndirilen ZIP/PKG SHA-256 değerleri manifest ve GitHub asset digest ile eşleşti.
- ZIP SHA-256: `737b1da707d738601f9ce7d538042b4681eb0d84216021a733054d5e40288093`.
- PKG SHA-256: `1f16d40178de19eb79e3973b29f43d43cbddfbb3586239c7a2fd697354795b28`.
- `/tmp/mssql-v57-verify/extracted/MSSQLStudio.app` strict/deep codesign doğrulamasından geçti. Sürüm/build 0.2.57/58; sabit DR `identifier "local.mssqlstudio.app" and certificate leaf = H"adce16b1a3567d8c5fe2ed261e89493611cb7b9d"` doğrulandı.
- Gerçek kullanıcı uygulaması/Keychain değiştirilmedi; canlı DB yazımı ve uzak sunucu hız karşılaştırması yapılmadı. Yerel sertifika Developer ID/notarization eşdeğeri değildir.

## 10 Ekim 2026 — sayısal sonuçlarda eksik baştaki sıfır

- Başlangıç kaynağı `0426101`, uzak `main` ile eşleşti; çalışma ağacı temizdi. Kök neden: `SQLGetData(SQL_C_WCHAR)` sonucunun sayısal metni ODBC okuma yolundan grid'e aynen taşınıyordu. `.00000000` ve `-.25` geçerli sayısal gösterimler olsa da beklenen kullanıcı görünümünde baştaki sıfır eksikti. Microsoft dönüşüm kuralları exact numeric metninde scale korunarak en kısa gösterime izin verir: [ODBC Rules for Conversions](https://learn.microsoft.com/en-us/sql/odbc/reference/appendixes/rules-for-conversions?view=sql-server-ver17).
- `Field.normalizedResultValue` yalnız ODBC numeric/decimal/float/real temel türlerinde eksik sıfırı ekler. Alias adına göre tahmin yapılmaz; TDBFLOAT numeric/decimal olarak işlendiğinde aynı yolu kullanır. MONEY/SMALLMONEY'nin decimal eşlemesi kapsanır. TDBBYTE/tinyint ve diğer integer, string, binary, bilinmeyen UDT alanları değişmez. Double/Decimal/NumberFormatter ile yeniden biçimlendirme yoktur; negatif işaret, bilimsel gösterim, precision/scale ve NULL korunur.
- Normalizasyon streaming/spool ve byte bütçesi hesaplamasından önce uygulanır. Grid, clipboard, export ve edit original değerleri aynı kayıpsız metni kullanır. Mevcut `sys.types` temel tür çözümlemesi ve alias için temel tip üzerinden CONVERT üretimi korunur.
- Yeni core testleri: sıfır/negatif/pozitif ve bilimsel gösterim, 28/38 basamak, 38 scale, trailing zero, NULL/boş/geçersiz metin, alias/base-type ayrımı, spool/sıralama/JSON/CSV ve decimal(28,8)/tinyint SQL dönüşümü. Yeni native test: gerçek hücre seçimi/kopyalama, başlık/sağ hizalama, field editor aç-kapat ile değişiklik oluşmaması, NULL, UPDATE/orijinal conflict değerleri, yerel kopyalama ve geri alma.
- Localhost:1433/master için benzersiz alias tipleri/tablo oluşturup tümünü transaction rollback ile temizleyen koşullu canlı test eklendi; bellek/disk ODBC sonuçlarını, alias metadata'sını ve değer dönüşümüyle UPDATE round trip'i kapsar. `MSSQL_TEST_PASSWORD` bu ortamda yok; canlı sunucu testi çalıştırılamadı. Kullanıcının gerçek TDBFLOAT tanımı ve sürücü çıktısı canlı olarak doğrulanmış değildir.
- İlk test girişimi yeni UI testinin private setter erişimi nedeniyle derlemede durdu (`/tmp/mssql-numeric-tests.log`); test gerçek mouse event ile düzeltildi. Bu girişim başarılı test sayılmaz.
- Son tam test çalışması başarılı: 84 native uygulama + 114 core = 198 test; 174 geçti, 24 dış koşullu test atlandı. Yeni üç core testi ve native grid/edit testi geçti; yeni canlı ODBC testi atlandı. Log: `/tmp/mssql-numeric-final-tests.log`. Native pencere/field editor smoke otomatik test içinde çalıştı; ayrıca manuel ekran görüntüsü incelemesi yapılmadı.
- Xcode Release derlemesi başarılı (`CODE_SIGNING_ALLOWED=NO`, `/tmp/MSSQLStudio-numeric-check`); log `/tmp/mssql-numeric-build.log`. `git diff --check` temiz. Mevcut Keychain deprecation ve GutterAction actor-isolation derleyici uyarıları bu değişikliğin dışında kaldı. Kaynaklar yerelde düzeltildi; sürüm yayımlanmadı, kurulu kullanıcı uygulaması ve gerçek DB değiştirilmedi.


## 10 Ekim 2026 — v0.2.58 yayın doğrulaması

- Sayısal sonuçlarda baştaki sıfır düzeltmesi v0.2.58 / build 59 olarak yayımlandı: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.58 . Kaynak `c24bec21c9792d93b983816980347b7a3f6bfddb`; Actions `38056058720` başarılı. Sabit imza/izole Keychain, imzalı uygulama ve installer, manifest doğrulaması ve yayın paketiyle test adımları geçti; geçici imza kimliği temizlendi.
- Public latest v0.2.58; ZIP, PKG ve update.json indirildi. ZIP SHA-256 `1a566f8cd724b86e1bb14cf0bcd2bc5cd43f8ae24884133daf96ea7ebc4d37dd`; PKG SHA-256 `baeb39a961bb8d2cb32505fa1b41dc99e51051cb74172e090e96fc242e63ffbe`. İki hash yayın manifesti ve GitHub asset digest ile eşleşti; manifestin tamamı yeniden üretilen manifestle eşleşti.
- İndirilen ZIP ve açılmış PKG payload uygulamalarında strict/deep codesign ve sabit designated requirement doğrulandı. ZIP/PKG uygulama binary, Info.plist ve bundled ReleaseNotes.json içerikleri eşleşti; sürüm/build 0.2.58/59, bundle ID local.mssqlstudio.app. GitHub sürüm notları paket içindeki notlarla eşleşti.
- Doğrulama çıktısı `/tmp/mssql-v58-verification.log`; dosyalar `/tmp/mssql-v58-verify`, çıkarılmış ZIP uygulaması `/tmp/mssql-v58-verify/extracted/MSSQLStudio.app`. Kurulu kullanıcı uygulaması/Keychain/gerçek veritabanı değiştirilmedi. Canlı SQL Server regresyonu için bağlantı bilgisi bulunmadığına ilişkin önceki sınırlama devam ediyor.


## 12 Ekim 2026 — v0.2.72 geliştirme doğrulaması

- SQL tamamlama: 26 pt tek satır, en çok 16 görünür öneri; tam satır yüksekliği, 100 öneride Home/End/Page/ok gezinmesi, Tab kabulü/undo, tooltip/AX ve açık/koyu görünüm kontrolleri geçti. Caret üst/alt alan hesaplaması artık açılış yönünü de belirler.
- Explorer: offline yenileme/heartbeat sıfır bağlantı denemesi; yeni sorgu isteğinde mevcut profil için bir kez bağlantı, eşzamanlı kısayolda tek deneme ve başarısızlıkta sekme/form açılmaması sentetik testlerle doğrulandı. Bağlantı menüsü kapatma/yeniden bağlama, cached tree ve bağımsız sorgunun açık transaction durumunu korur.
- İlgili 15 uygulama testi geçti. Tam paket çalışması 124 uygulama + 140 core = **264 test, 239 geçti / 25 dış koşullu atlandı**; iki hedefin tamamlanmış test özetleri doğrulandı. Log: `/tmp/mssql-072-tests.log`.
- Release build başarılı: `/tmp/mssql-072-release.log`. İzole `/tmp/MSSQLStudio-072-ui/MSSQLStudio.app` (local.mssqlstudio.uitest) CUA kontrolünde 100 önerinin 16 kompakt satırı, ekran altındaki caret için yukarı açılış, End ile son öneri/Home-Down-Tab ile `[Name]` ekleme ve Explorer bağlantı menüsü gözlendi. Gerçek kullanıcı app’i, Keychain ve SQL oturumları değiştirilmedi; test app’i kapatıldı.
- Canlı SQL Server ağ kesintisi/yeniden bağlantısı bu ortamda doğrulanmadı; sentetik kontrol canlı ağ kanıtı değildir. Frozen credential helper kaynak/binary/hash değişmedi.
- v0.2.72 Actions `38235910774` imzalı paketleri hazırladı fakat uygulama testlerinde favori ağacı seçimi kontrolü başarısız oldu (264 test: 238 geçti / 25 dış koşullu atlandı / 1 hata). Yayın açılmadı; etiket korunur. Başka native testlerden gelen tema bildiriminin reloadData sırasında Explorer seçimini düşürdüğü belirlendi. Tema bildirimiyle deterministik regresyon kontrolü eklendi, çalışma alanı yenilemesi mevcut node seçimini geri yükleyecek şekilde düzeltildi. Sonraki yayın adayı v0.2.73/build 74.


## 12 Ekim 2026 — v0.2.73 geliştirme doğrulaması

- v0.2.72’deki tamamlayıcı pencere ve kontrollü Explorer bağlantı değişiklikleri korunur. Çalışma alanı/tema yenilemesinde mevcut Explorer node seçimi geri yüklenir; favori seçildikten sonra tema bildirimi ve favori güncellemesi sırasıyla tetiklenerek seçim ve genişletme regresyonu denetlenir.
- Tam yerel test çalışması: **124 uygulama + 140 core = 264 test, 239 geçti / 25 dış koşullu atlandı**. İki hedefin tamamlanmış özetleri `/tmp/mssql-073-tests.log` içinde; Release build `/tmp/mssql-073-release.log` başarılı.
- Tamamlama/Explorer native CUA kanıtı önceki adayda aynı tamamlayıcı kaynakla alındı; bu revizyonda değişen seçim davranışı native regresyon testinde doğrulandı. Gerçek SQL Server kesintisi/yeniden bağlantısı doğrulanmış sayılmaz.
- **Yayımlandı:** v0.2.73/build 74, kaynak `ea21c13de03f988225a481f6570721cc415796d1`; Actions `38236647997` tüm adımları başarılı. Yayın paketleriyle CI: 124 app + 140 core = **264 test, 239 geçti / 25 dış koşullu atlandı**; iki hedefin tamamlanmış özeti `/tmp/mssql-073-ci-tests.log` içinde doğrulandı.
- Public latest ve dört asset doğrulandı: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.73 . İndirilen ZIP/PKG GitHub digest/public manifest eşleşmesi, her iki app’in strict imzası ve sabit DR’si, tam sürüm/build, metadata/release notes binary eşitliği ve v1 helper byte eşitliği geçti. Kanıt: `/tmp/MSSQLStudio-0.2.73-verify`, `/tmp/mssql-073-public-verification.log`.
- ZIP SHA-256: `e904eba49b9149ccf801017b23ed03f6650caa80a5a201f98ac6de684d63cd30`; PKG: `f30de27ab536791a00cbd4bbf26fdc8d9f80522183b762f256e2049fde93aa6a`; update.json: `1596dc9a722167d12667d210e45a618a3b54c4bf1e7e85b3b9300c4401260b5b`. Frozen helper archive `75bfb1d347f211607eda75ec2a511d3d3d38e3ffef786fec174cce932c6b5713` ve executable `5bdc54f130122075cb1d6204d49d2251f761e60cc4a8110652d1754af1a0f81b` değişmedi.
- Gerçek kullanıcı uygulaması kurulmadı/değiştirilmedi; açık sorgu/Keychain oturumları test için yeniden başlatılmadı.

## 12 Ekim 2026 — v0.2.74 geliştirme doğrulaması

- Explorer kök bağlantıları native local move ile sıralanır. State.servers ile native roots sırası eşleşir; mevcut node kimlikleri, seçili alt dal, açık dallar, çevrimdışı durum ve bağımsız sorgunun açık transaction’ı korunur. UUID sırası ayrı explorerServerOrder tercihine yazılır; restore seçimi ve Keychain değişmez.
- Yeni core kontrolü sıralama restore, bilinmeyen/bozuk/tekrarlanan UUID, yalnız seçili profiller ve yeni profil eklenmesini doğrular. Native kontrol gerçek NSOutlineView dataSource protocol dispatch ile writer/validateDrop/acceptDrop yollarını, root-on-item normalizasyonunu, yanlış source reddini, registeredDraggedTypes ve iki yönde taşımayı denetler. Named pasteboard ve geçici UserDefaults suite temizlenir; kullanıcı kayıtları okunmaz.
- Tam yerel paket çalışması: **125 app + 141 core = 266 test, 241 geçti / 25 dış koşullu atlandı**. İki hedefin tamamlanmış özetleri `/tmp/mssql-074-tests.log` içinde; Release build `/tmp/mssql-074-release.log` başarılı. Son ek native delegate kontrolü 12 Explorer testi içinde geçti.
- İzole `/tmp/MSSQLStudio-074-ui/MSSQLStudio.app` üç çevrimdışı bağlantı, başlık yardımı ve normal native ağaç sunumuyla açıldı. CUA fare sürüklemelerinde başarılı sıra değişimi gözlenmedi; arayüz aracı masaüstü müdahalesi uyarıları verdi. Bu nedenle gerçek fareyle uçtan uca taşıma doğrulanmış sayılmaz; native delegate fixture kanıtı bu kontrolün yerine geçtiği iddia edilmez. Geçici tanılama kodu kaldırıldı ve test uygulaması kapatıldı. Kullanıcı uygulaması/oturumları değiştirilmedi.
- **Yayımlandı:** v0.2.74/build 75, kaynak `00fe025e73add278a26b4e8c3bbc8d2e4a3cb9bf`; Actions `38241451880` tüm adımları başarılı. Paketlerle CI 125 app + 141 core = **266 test, 241 geçti / 25 dış koşullu atlandı**; tamamlanmış iki test özeti `/tmp/mssql-074-ci-tests.log` içinde doğrulandı.
- Public latest ve dört asset doğrulandı: https://github.com/erhanulas/MSSQLStudio/releases/tag/v0.2.74 . İndirilen ZIP/PKG GitHub digest/public manifest eşleşmesi, strict app/helper imzaları ve sabit DR, tam sürüm/build, binary/metadata/release notes eşitliği ve frozen v1 helper byte eşitliği geçti. Kanıt: `/tmp/MSSQLStudio-0.2.74-verify`, `/tmp/mssql-074-public-verification.log`.
- ZIP SHA-256 `433dc8a3494014df097b96605a6da0031293b0153d8974c2d21f6d934a4cb059`; PKG `acc5e4118d34183b5cbfd7c29493d4995035b75d9f506717cd159c97d45d3312`; update.json `85130dc136cfd5a350eb38046c7a900b3b7e1c60336f159e4d99623fa10d8f6e`. Helper archive `75bfb1d347f211607eda75ec2a511d3d3d38e3ffef786fec174cce932c6b5713` ve executable `5bdc54f130122075cb1d6204d49d2251f761e60cc4a8110652d1754af1a0f81b` değişmedi.
