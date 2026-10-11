import AppKit
import SQLServerKit
import SwiftUI

@MainActor enum ResultReadPreferences {
  static let changed = Notification.Name("MSSQLStudio.resultReadPreferencesChanged")
  static func bounded(_ value: Int, range: ClosedRange<Int>, fallback: Int) -> Int { range.contains(value) ? value : fallback }
  static var readLimit: Int { bounded(UserDefaults.standard.object(forKey:"gridReadLimit") as? Int ?? 50_000,range:1...5_000_000,fallback:50_000) }
  static var refreshSeconds: Int { bounded(UserDefaults.standard.integer(forKey:"gridRefreshSeconds"),range:0...3600,fallback:0) }
  static func limits(rows: Int) -> Limits {
    var limits = Limits(); limits.diskResults = true
    limits.rows = bounded(rows,range:1...5_000_000,fallback:50_000)
    limits.totalBytes = limits.rows <= 50_000 ? 67_108_864 : 2_147_483_648
    limits.timeout = limits.rows <= 50_000 ? 60 : 600
    return limits
  }
  static func save(rows: Int, page: Int, refresh: Int) {
    UserDefaults.standard.set(bounded(rows,range:1...5_000_000,fallback:50_000),forKey:"gridReadLimit")
    UserDefaults.standard.set(bounded(page,range:0...1_000_000,fallback:500),forKey:"gridDefaultPageSize")
    UserDefaults.standard.set(bounded(refresh,range:0...3600,fallback:0),forKey:"gridRefreshSeconds")
    NotificationCenter.default.post(name:changed,object:nil)
  }
}
struct ResultLoadingPanel: View {
  @State var rows: Int
  @State var page: Int
  @State var refresh: Int
  var refreshAllowed = true
  var apply: (Int,Int,Int,Bool) -> Void
  @State private var saveDefault = false
  @State private var message = ""
  var body: some View {
    VStack(alignment:.leading,spacing:16) {
      StudioPanelHeading(title:"Sonuç Yükleme",icon:"slider.horizontal.3",subtitle:"Bu sorgu için okuma ve görüntüleme")
      StudioFormField("Okuma sınırı") { TextField("Satır",value:$rows,format:.number.grouping(.never)).textFieldStyle(.roundedBorder) }
      StudioFormField("Sayfa boyutu") { TextField("Satır",value:$page,format:.number.grouping(.never)).textFieldStyle(.roundedBorder) }
      StudioFormField("Yenileme aralığı") { HStack { TextField("Saniye",value:$refresh,format:.number.grouping(.never)).textFieldStyle(.roundedBorder); Text("sn").foregroundStyle(.secondary) } }.disabled(!refreshAllowed)
      Text("Okuma: 1–5.000.000 satır · Sayfa: 0–1.000.000 (0 = tüm yüklenenler) · Yenileme: 0–3.600 sn (0 = kapalı). Okuma sınırı sonraki çalıştırmada uygulanır.").font(.caption).foregroundStyle(.secondary)
      if !refreshAllowed { Label("Düzenleme sırasında otomatik yenileme kapalıdır.",systemImage:"pause.circle").font(.caption).foregroundStyle(.secondary) }
      Toggle("Yeni sorgular için varsayılan yap",isOn:$saveDefault)
      if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red) }
      HStack { Spacer(); StudioActionButton("Uygula",icon:"checkmark") {
        guard (1...5_000_000).contains(rows), (0...1_000_000).contains(page), (0...3600).contains(refresh) else { message="Lütfen belirtilen aralıklarda değerler girin."; return }
        apply(rows,page,refreshAllowed ? refresh : 0,saveDefault)
      }.buttonStyle(StudioPrimaryButton()) }
    }.padding(20).frame(width:440).fixedSize(horizontal:false,vertical:true).studioPanel()
  }
}

struct ResultRefreshPanel:View {
  @State var seconds:Int
  var apply:(Int)->Void
  @State private var message=""
  var body:some View {
    VStack(alignment:.leading,spacing:16) {
      StudioPanelHeading(title:"Otomatik Yenileme",icon:"clock.arrow.circlepath",subtitle:"Son başarılı SELECT sorgusunu tekrar oku")
      StudioFormField("Yenileme aralığı") {HStack {TextField("Saniye",value:$seconds,format:.number.grouping(.never)).textFieldStyle(.roundedBorder);Text("sn").foregroundStyle(.secondary)}}
      Text("0 kapalı · 1–3.600 saniye. İlk başarılı SELECT sonrası başlar; düzenleme veya açık işlem sırasında çalışmaz.").font(.caption).foregroundStyle(.secondary)
      if !message.isEmpty {Text(message).foregroundStyle(.red)}
      HStack {Spacer();StudioActionButton("Uygula",icon:"checkmark") {
        guard (0...3600).contains(seconds) else {message="0–3.600 saniye girin.";return}
        apply(seconds)
      }.buttonStyle(StudioPrimaryButton())}
    }.padding(20).frame(width:420).fixedSize(horizontal:false,vertical:true).studioPanel()
  }
}

@MainActor final class ResultWorkspaceView: NSView {
  var searchColumns: (() -> Void)?
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if GridShortcuts.matches(.columns,event) { searchColumns?(); return true }
    return super.performKeyEquivalent(with:event)
  }
}
struct ResultColumnChoice: Identifiable { let id: Int; let name: String; let type: String; let hidden: Bool }
struct ResultColumnSearch: View {
  let columns: [ResultColumnChoice]
  let select: (Int) -> Void
  @State private var search = ""
  @FocusState private var focused: Bool
  private var matches: [ResultColumnChoice] { columns.filter { search.isEmpty || $0.name.localizedStandardContains(search) } }
  var body: some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Kolona Git",icon:"text.magnifyingglass",subtitle:"Başlıkta ara ve kolonu görünür alana getir")
      TextField("Kolon adı…",text:$search).textFieldStyle(.roundedBorder).focused($focused).onSubmit { if let first=matches.first { select(first.id) } }
      ScrollView {
        LazyVStack(spacing:4) {
          ForEach(matches) { column in
            Button { select(column.id) } label: {
              HStack(spacing:10) {
                Image(systemName:column.hidden ? "eye.slash" : "tablecells").foregroundStyle(Color.accentColor).frame(width:24)
                VStack(alignment:.leading,spacing:3) { Text(column.name).font(.system(size:12,weight:.medium)); Text(column.type).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName:"arrow.right").foregroundStyle(.secondary)
              }.padding(10).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
          if matches.isEmpty { Text("Eşleşen kolon yok").foregroundStyle(.secondary).padding() }
        }
      }.frame(height:300)
    }.padding(20).frame(width:420).studioPanel().onAppear { focused=true }
  }
}
