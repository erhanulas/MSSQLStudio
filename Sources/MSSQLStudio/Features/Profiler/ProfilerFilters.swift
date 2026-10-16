import SwiftUI
import SQLServerKit

struct ProfilerFilters:View {
  @ObservedObject var model:ProfilerModel
  @Binding var showClients:Bool
  @State private var advancedCapture=false
  @State private var columnsExpanded=false
  var body:some View {
    ScrollView {
      VStack(spacing:8) {
        HStack(spacing:12) {
          field("Veritabanı",text:$model.configuration.database)
          field("Uygulama",text:$model.configuration.application)
          field("Login",text:$model.configuration.login)
          field("ClientProcessID",text:$model.configuration.clientPID)
          VStack(alignment:.leading,spacing:4) {
            Text("En az süre (ms)").foregroundStyle(.secondary)
            TextField("0",value:$model.configuration.minimumDurationMS,format:.number).textFieldStyle(.roundedBorder)
          }.frame(width:110)
        }.disabled(model.hasSession || model.busy)
        StudioDisclosureHeader(title:"Diğer yakalama filtreleri · Başlatmadan önce",icon:"line.3.horizontal.decrease.circle",tint:StudioTheme.muted,expanded:advancedCapture) {advancedCapture.toggle()}.frame(height:28)
        if advancedCapture {
          HStack(spacing:12) {
            field("Host",text:$model.configuration.host)
            field("SPID",text:$model.configuration.sessionID)
            field("SQL LIKE",text:$model.configuration.sqlLike)
            field("SQL NOT LIKE",text:$model.configuration.sqlNotLike)
          }.disabled(model.hasSession || model.busy)
          Text("Yakalama filtreleri sunucuda uygulanır; değiştirmek için durdurup yeniden başlatın. LIKE alanlarında % herhangi bir metin, _ tek karakterdir. Örnek: %STOK%.")
            .foregroundStyle(.secondary).font(.system(size:11)).frame(maxWidth:.infinity,alignment:.leading)
        }
        Divider()
        HStack(spacing:8) {
          Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
          TextField("Gelen SQL metinlerinde ara…",text:$model.displayFilter.sqlSearch).textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("profilerSQLSearch")
          if model.filtering {ProgressView().controlSize(.small)}
          Picker("Grid",selection:$showClients) {Text("Olaylar").tag(false);Text("Yoğun istemciler").tag(true)}
            .pickerStyle(.segmented).labelsHidden().frame(width:260)
        }
        HStack {
          StudioDisclosureHeader(title:"Grid kolon filtreleri · \(model.displayFilter.rules.filter {!$0.value.isEmpty}.count) koşul",icon:"line.3.horizontal.decrease",tint:StudioTheme.accent,expanded:columnsExpanded) {columnsExpanded.toggle()}.frame(height:28)
          Button {model.displayFilter = .init()} label:{Label("Filtreleri Sıfırla",systemImage:"arrow.counterclockwise")}
            .buttonStyle(StudioSecondaryButton())
        }
        if columnsExpanded {
          ForEach($model.displayFilter.rules) {$rule in
            HStack(spacing:8) {
              Picker("Kolon",selection:$rule.column) {ForEach(SQLProfilerFiltering.Column.allCases) {Text($0.title).tag($0)}}
                .labelsHidden().frame(width:155)
                .onChange(of:rule.column) {_,column in rule.comparison=column.operators[0]}
              Picker("Karşılaştırma",selection:$rule.comparison) {ForEach(rule.column.operators) {Text($0.title).tag($0)}}.labelsHidden().frame(width:140)
              TextField("Filtre değeri",text:$rule.value).textFieldStyle(.roundedBorder)
              Button {model.displayFilter.rules.removeAll {$0.id==rule.id}} label:{Image(systemName:"minus.circle")}
                .buttonStyle(StudioSecondaryButton()).accessibilityLabel("Bu filtreyi kaldır")
            }
          }
          HStack {
            Button {model.displayFilter.rules.append(.init())} label:{Label("Koşul Ekle",systemImage:"plus")}
              .buttonStyle(StudioSecondaryButton()).disabled(model.displayFilter.rules.count>=20)
            Text("Koşullar VE ile birleşir. Grid filtreleri ve SQL araması toplama sırasında da çalışır; yakalanan olayları silmez.")
              .font(.system(size:11)).foregroundStyle(.secondary)
            Spacer()
          }
        }
      }
    }.frame(maxHeight:180)
  }
  private func field(_ title:String,text:Binding<String>)->some View {
    VStack(alignment:.leading,spacing:4) {Text(title).foregroundStyle(.secondary);TextField("Tümü",text:text).textFieldStyle(.roundedBorder)}
  }
}
