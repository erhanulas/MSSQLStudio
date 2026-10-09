# MSSQL Studio — premium çalışma alanı, 0.2.11

## Tasarım hedefi

DataGrip referansındaki düzen, yüzey ayrımı ve tutarlılık esas alındı. Solda nesne ağacı, ortada sorgu sekmeleri, altta sonuçlar/mesajlar şeklindeki kararlaştırılmış SSMS çalışma düzeni korundu. JetBrains ikonları veya marka varlıkları kopyalanmadı; native SF Symbols kullanıldı.

## Uygulanan dört adım

1. **Ortak tasarım dili:** açık/koyu yüzeyler, metin hiyerarşisi, kontrollü mavi vurgu, ince kenarlıklar, sistem arayüz yazı tipi. Tema artık bütün alanları aynı renge veya yazı ağırlığına zorlamıyor.
2. **Çalışma alanı:** ince dış boşluk, yuvarlatılmış panel sınırları, düzenli ikonlu araç çubuğu ve etiketli yeşil Çalıştır düğmesi, belge ikonlu sakin sorgu sekmeleri, daha okunur nesne ağacı. Uzun bağlantı adresi ağaç başlığından araç ipucuna taşındı; ortama ait renk ve etiketler korundu.
3. **Editör ve grid:** dengeli SQL renkleri, daha sakin satır numaraları; sayı/metin/tarih ikonlu kolonlar, filtre/sıralama göstergeleri, ince yatay/dikey çizgiler, yumuşak satır seçimi, italik NULL. Filtre yokken boş filtre şeridi kapanır. Tema değişiminde kolon genişlikleri, gizli kolonlar ve seçili satırlar korunur.
4. **Bağlantı ve yardımcı pencereler:** bağlantı bilgileri ve veritabanları ayrı yüzeylerde; mavi birincil test/bağlan düğmeleri. Ayarlar, Timeline, Assistant, şablonlar, indeks ve Agent tasarımcılarında ortak başlık/ikon/yazı dili; SQL metin alanlarında ince çerçeve. Assistant için boş yanıt durumu, plan ağacı için ortak kolon başlıkları ve seçim rengi.

## Ortak ölçüler

| Öğe | Karar |
|---|---|
| Ana yüzey | Açık `FFFFFF`; koyu `202229` |
| Araç/panel zemini | Açık `F3F4F8`; koyu `292C35` |
| Metin | Açık `272B38`; koyu `DCE0EB` |
| Vurgu | Açık `4C6FE8`; koyu `8CA7FF` |
| Seçim | Açık `E1EBFF`; koyu `334766` |
| Kenarlık | Açık `E1E4ED`; koyu `3B3F4C`, 1 pt |
| Panel / kontrol köşesi | 8 / 5–6 pt |
| Arayüz | Sistem yazı tipi, 12 pt; yardımcı bilgi 10–11 pt |
| Editör | Consolas varsa 13 pt; yoksa native monospace |
| Grid / ağaç satırı | 24 / 25 pt |
| Sorgu sekmesi / sonuç araç satırı | 34 / 34 pt |

Renk tek başına anlam taşımaz: ortam etiketi, nesne simgesi, NULL metni ve filtre işareti ayrıca görünür. İşlemler klavye kısayollarını ve erişilebilirlik etiketlerini korur. macOS pencere kontrolleri, dosya pencereleri ve menüler native kalır.

## Performans ve davranış sınırları

Yüzeylerde ağır gölgeler, grid hücrelerinde SwiftUI katmanı veya satır başına görsel varlık yoktur. Native NSTableView görünen satırları kullanır. Sorgu ilerleme bildiriminde tüm görünüm ağacını yeniden tema uygulamasından geçirme kaldırıldı. Disk destekli sonuçlar, iş parçacığı dışında filtre/sıralama, iptal ve akış halinde dışa aktarma korunur.

Kolon filtreleri yalnızca yüklenmiş sonuçlara uygulanır. Bu tasarım değişikliği sunucuda filtreleme, düzenlenebilir grid, tam docking veya yeni yönetim yeteneği eklemez. Doğrulama sonuçları ve gerçek ürün sınırları TEST-REPORT.md içindedir.

## Grid araçları ve sekmeler — 0.2.9

İki görev alanı: sorgu yenileme/zamanlama ve filtre/dışa aktarma üstte; sonuç türü gerçek sekmelerde; yüklenen satırlarda gezinme grid’in kompakt çubuğunda. Referanstaki veri düzenleme/commit/DDL ikonları uygulanmış özellikler gibi eklenmez. Hücre seçimi sakin mavi, satır numarası tüm satır seçimi, pin SF Symbol ile gösterilir. Kolon türleri başlık ipucunda açıklanır.

## Tek araç çubuğu — 0.2.11

Grid araçları yatay tek şeritte gruplanır; sonuç başına ikinci kontrol satırı kaldırılır. Görünür alanın başında gezinme ve yüklenen aralık; ardından yenileme, saatli otomatik yenileme, satır limiti, arama, başlıklı kopyalama, dışa aktarma bulunur. Filtre temizleme gezinme grubunda ikondur; kolon filtresi açılır seçicisi yoktur. İşlem ipuçları ve gerçek kısayollar tooltip’te, erişilebilir adlar kontrollerdedir. bit değerleri yerleşik native checkbox ile sakin görsel hiyerarşiye katılır; veri düzenleme eylemi oluşturmaz.

## 0.2.11 çalışma alanı

Sonuç paneli gizlenirken split view’dan çıkarılır ve ayırıcı kalınlığı sıfırlanır. Soldaki özel tab strip içerik NSTabView seçimini yönetir. GridPaging kalıcı varsayılanı ve yerel sayfa aralığını yönetir; filtre indeksleri sayfalamadan önce uygulanır. Sayfalı kopyalama/dışa aktarma kaynak satır indekslerini korur. ResultSpool kilit altında 256 satır / 8 MiB sınırlı çözülmüş satır önbelleği kullanır. Otomatik genişlik örneklemesi en fazla 32 satır / 4096 hücredir; tüm veri taranmaz. QueryTabStrip native dragging source/destination ile UUID tabanlı yeniden sıralama yapar. GridShortcuts kayıtları ayarlarda gerçek tuş yakalama, çakışma kontrolü ve menü güncellemesini paylaşır.
