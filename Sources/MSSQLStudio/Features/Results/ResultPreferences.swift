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
  static func save(rows: Int, refresh: Int) {
    UserDefaults.standard.set(bounded(rows,range:1...5_000_000,fallback:50_000),forKey:"gridReadLimit")
    UserDefaults.standard.set(bounded(refresh,range:0...3600,fallback:0),forKey:"gridRefreshSeconds")
    NotificationCenter.default.post(name:changed,object:nil)
  }
}
struct ResultLoadingPanel: View {
  @State var rows: Int
  @State var refresh: Int
  var refreshAllowed = true
  var readLimitAllowed = true
  var apply: (Int,Int,Bool) -> Void
  @State private var saveDefault = false
  @State private var message = ""
  var body: some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:"Sonuç Yükleme",icon:"slider.horizontal.3",subtitle:"SELECT sonuçları için tek satır sınırı")
      ScrollView {
        VStack(alignment:.leading,spacing:14) {
          StudioFormField("Sonuç başına satır sınırı") {TextField("Satır",value:$rows,format:.number.grouping(.never)).textFieldStyle(.roundedBorder)}.disabled(!readLimitAllowed)
          StudioFormField("Yenileme aralığı") {HStack {TextField("Saniye",value:$refresh,format:.number.grouping(.never)).textFieldStyle(.roundedBorder);Text("sn").foregroundStyle(.secondary)}}.disabled(!refreshAllowed)
          Text("Satır sınırı: 1–5.000.000 · Yalnız SELECT sonuçlarına uygulanır; DML ve EXEC işlemlerini sınırlamaz. Mevcut önbelleğe anında uygulanır; daha fazla veri için SELECT’i yenileyin. Yenileme: 0–3.600 sn (0 = kapalı).").font(.caption).foregroundStyle(.secondary)
          if !readLimitAllowed {Label("Satır sınırı için düzenleme modunu ve dışa aktarmayı tamamlayın.",systemImage:"lock").font(.caption).foregroundStyle(.secondary)}
          if !refreshAllowed {Label("Düzenleme sırasında otomatik yenileme kapalıdır.",systemImage:"pause.circle").font(.caption).foregroundStyle(.secondary)}
          Toggle("Yeni sorgular için varsayılan yap",isOn:$saveDefault)
          if !message.isEmpty {Text(message).font(.caption).foregroundStyle(.red)}
        }.padding(2)
      }
      Divider()
      HStack {Spacer();StudioActionButton("Uygula",icon:"checkmark") {
        guard (1...5_000_000).contains(rows),(0...3600).contains(refresh) else {message="Lütfen belirtilen aralıklarda değerler girin.";return}
        apply(rows,refreshAllowed ? refresh:0,saveDefault)
      }.buttonStyle(StudioPrimaryButton())}
    }.padding(StudioMetrics.gap).frame(maxWidth:.infinity,maxHeight:.infinity).studioPanel()
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
    }.padding(StudioMetrics.gap).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).studioPanel()
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
@MainActor enum ResultColumnNavigation {
  static func matches(_ columns:[ResultColumnChoice],search:String) -> [ResultColumnChoice] {
    let search=search.trimmingCharacters(in:.whitespacesAndNewlines)
    return columns.filter {search.isEmpty || $0.name.localizedStandardContains(search)}
  }
  static func next(_ matches:[ResultColumnChoice],selected:Int?,step:Int) -> Int? {
    guard !matches.isEmpty else {return nil}
    let index=selected.flatMap {id in matches.firstIndex {$0.id == id}} ?? 0
    return matches[max(0,min(matches.count-1,index+step))].id
  }
}
struct ResultColumnSearch: View {
  let columns:[ResultColumnChoice]
  let select:(Int)->Void
  var dismiss:()->Void = {}
  @State private var search=""
  @State private var selected:Int?
  @State private var hovered:Int?
  @FocusState private var focused:Bool
  private var matches:[ResultColumnChoice] {ResultColumnNavigation.matches(columns,search:search)}
  private func move(_ step:Int) {selected=ResultColumnNavigation.next(matches,selected:selected,step:step)}
  private func openSelected() {if let id=selected ?? matches.first?.id {select(id)}}
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack(alignment:.top) {
        StudioPanelHeading(title:"Kolona Git",icon:"text.magnifyingglass",subtitle:"Başlıkta ara ve hedefi vurgula")
        Spacer()
        Button(action:dismiss) {Image(systemName:"xmark").frame(width:24,height:24).contentShape(Rectangle())}
          .buttonStyle(.plain).studioHelp("Kapat (Esc)").accessibilityLabel("Kolon aramasını kapat")
      }
      TextField("Kolon adı ara…",text:$search).textFieldStyle(.roundedBorder).focused($focused)
        .accessibilityIdentifier("columnNavigationSearch").onSubmit(openSelected)
        .onKeyPress(.downArrow) {move(1);return .handled}
        .onKeyPress(.upArrow) {move(-1);return .handled}
      ScrollViewReader {proxy in
        ScrollView {
          LazyVStack(spacing:4) {
            ForEach(matches) {column in
              ResultColumnSearchRow(column:column,selected:selected == column.id,hovered:hovered == column.id) {selected=column.id;select(column.id)}
                .id(column.id).onHover {hovered=$0 ? column.id:nil}
            }
            if matches.isEmpty {StudioEmptyState(title:"Eşleşen kolon yok",icon:"magnifyingglass",detail:"Kolon adının bir bölümünü deneyin.").padding(.vertical,16)}
          }.padding(2)
        }.onChange(of:selected) {_,id in if let id {proxy.scrollTo(id)}}
      }.frame(maxHeight:.infinity)
      Divider()
      HStack {
        Text("\(matches.count) / \(columns.count) kolon").foregroundStyle(.secondary)
        Spacer();Text("↑ ↓  Seç · Enter  Git").foregroundStyle(.secondary)
      }.font(.caption)
    }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity).studioPanel()
      .onAppear {selected=matches.first?.id;focused=true}
      .onChange(of:search) {_,_ in selected=matches.first?.id}
      .onExitCommand(perform:dismiss)
  }
}

private struct ResultColumnSearchRow:View {
  let column:ResultColumnChoice
  let selected:Bool
  let hovered:Bool
  let action:()->Void
  @Environment(\.colorScheme) private var colorScheme
  private var background:Color {
    selected ? Color(nsColor:StudioTheme.accent).opacity(colorScheme == .dark ? 0.22:0.10):hovered ? Color.primary.opacity(0.05):.clear
  }
  private var detail:String {column.type+(column.hidden ? " · Gizli":"")}
  var body:some View {
    Button(action:action) {
      HStack(spacing:10) {
        Image(systemName:column.hidden ? "eye.slash":"tablecells").foregroundStyle(Color(nsColor:StudioTheme.accent)).frame(width:22)
        VStack(alignment:.leading,spacing:3) {
          Text(column.name).font(.system(size:12,weight:.medium)).lineLimit(1)
          Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength:6)
        Image(systemName:"arrow.turn.down.left").foregroundStyle(.secondary).opacity(selected ? 1:0)
      }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
        .background(background,in:RoundedRectangle(cornerRadius:7)).contentShape(Rectangle())
    }.buttonStyle(.plain).studioHelp(column.name+" · "+column.type).accessibilityLabel(column.name+" · "+detail)
  }
}
