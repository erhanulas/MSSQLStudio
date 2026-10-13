import Foundation

struct SettingsSearchEntry:Identifiable,Equatable {
  let id:String
  let section:SettingsSection
  let card:String
  let title:String
  let keywords:String
  var scrollID:String {
    ["fonts","undeclared","comments","update","password"].contains(id) ? card:id
  }
}

@MainActor enum SettingsSearch {
  /// Register new preferences here; shortcut entries are generated automatically.
  static var entries:[SettingsSearchEntry] {
    let cards:[(SettingsSection,String,[(String,String,String)])]=[
      (.appearance,"Renk teması",[("theme","Renk teması","sistem macOS açık koyu görünüm light dark")]),
      (.appearance,"Yazı ve okunabilirlik",[("fonts","SQL ve arayüz yazı tipi","font punto monospace Consolas okunabilirlik")]),
      (.editor,"Otomatik tamamlama",[
        ("completion","Yazarken önerileri göster","otomatik tamamlama intellisense tablo kolon autocomplete"),
        ("delay","Öneri gecikmesi","süre milisaniye ms hız bekleme"),
        ("schema","Tamamlamada şema adını ekle","schema dbo"),
        ("brackets","Tamamlamada köşeli parantez kullan","tırnak identifier quote brackets")]),
      (.editor,"SQL biçimlendirme",[
        ("formatCase","Anahtar kelime harfleri","formatter format büyük küçük upper lower preserve code style"),
        ("formatWidth","Satır genişliği","formatter format uzun satır wrap devam 120 karakter"),
        ("formatIndent","Girinti boşluk sayısı","formatter format indentation tab boşluk"),
        ("formatComma","Virgül yerleşimi","formatter format comma leading trailing"),
        ("formatLists","Kolon listelerini satırlara ayır","formatter select insert cte liste satır kırma"),
        ("formatConditions","Koşulları satırlara ayır","formatter where on having and or koşul")]),
      (.editor,"Kod yardımcıları",[
        ("validation","Eksik tablo ve kolonları vurgula","doğrulama kırmızı hata referans validation"),
        ("undeclared","Tanımsız parametre vurgusu","declare edilmemiş değişken kırmızı @ parametre undefined undeclared"),
        ("comments","Seçili SQL satırlarını yorum yap / kaldır","comment uncomment açıklama klavye kısayol"),
        ("aliases","Otomatik alias ekle","takma ad from join"),
        ("nolock","Alias sonrasında WITH(NOLOCK) ekle","kilit kirli okuma read uncommitted")]),
      (.workspace,"Geçmiş ve kurtarma",[
        ("history","Sorgu geçmişini sakla","timeline sql yerel kayıt"),
        ("retention","Saklama süresi","geçmiş gün 30 3650 history retention"),
        ("recovery","Sorgu sekmelerini kurtar","oturum yeniden açılış recovery restore")]),
      (.workspace,"Nesne tanım indeksi",[("definitionQuota","Tanım indeksi disk kotası ve doluluk","index indeks sqlite disk depolama kota quota yüzde doluluk 1 gb 1024 mb offline çevrimdışı")]),
      (.workspace,"Yerel kayıtlar",[("removeRecords","Yerel Kayıtları Sil","geçmiş kurtarma temizle disk history tabs")]),
      (.updates,"GitHub yayınları",[("repository","Yayın deposu","github repo repository url güncelleme adres kaynak")]),
      (.updates,"Güncelleme kontrolü",[("update","Güncellemeleri Kontrol Et","yeni sürüm yayın kurulum paket installer update")]),
      (.security,"Parola erişimi",[("password","Parola erişimi","macOS anahtar zinciri şifre keychain izin imza güvenlik")]),
      (.security,"Erişim sorunlarını gider",[("renew","Keychain izinlerini yenile","anahtar zinciri parola şifre erişim onay güvenlik")])
    ]
    return cards.flatMap {section,card,values in values.map {id,title,keywords in
      SettingsSearchEntry(id:id,section:section,card:card,title:title,keywords:keywords)
    }} + GridShortcuts.Action.allCases.map {
      SettingsSearchEntry(id:"shortcut."+$0.rawValue,section:.shortcuts,card:"Klavye kısayolları",title:GridShortcuts.title($0),keywords:"klavye tuş değiştir sıfırla "+GridShortcuts.binding($0).label)
    }
  }
  private static func normalized(_ text:String)->String {
    text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"tr_TR")).replacingOccurrences(of:"ı",with:"i")
  }
  static func results(_ query:String)->[SettingsSearchEntry] {
    let words=normalized(query).split(whereSeparator:{$0.isWhitespace})
    guard !words.isEmpty else {return []}
    return entries.filter {entry in
      let text=normalized(entry.title+" "+entry.section.title+" "+entry.card+" "+entry.keywords)
      return words.allSatisfy {text.contains($0)}
    }
  }
}
