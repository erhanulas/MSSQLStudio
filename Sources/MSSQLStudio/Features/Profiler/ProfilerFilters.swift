import SwiftUI
import SQLServerKit

struct ProfilerFilters:View {
  @ObservedObject var model:ProfilerModel
  @Binding var showClients:Bool
  @ObservedObject private var choices:ProfilerChoicesModel
  @State private var manualColumns:Set<SQLProfilerFiltering.Column>=[]
  init(model:ProfilerModel,showClients:Binding<Bool>) {self.model=model;_showClients=showClients;choices=model.choices}
  @State private var advancedCapture=false
  @State private var columnsExpanded=false
  var body:some View {
    ScrollView {
      VStack(spacing:8) {
        VStack(alignment:.leading,spacing:8) {
          choice("Veritabanı",column:.database,text:$model.configuration.database)
          choice("Uygulama",column:.application,text:$model.configuration.application)
          choice("Login",column:.login,text:$model.configuration.login)
          choice("ClientProcessID",column:.clientPID,text:$model.configuration.clientPID)
          VStack(alignment:.leading,spacing:4) {
            Text("En az süre (ms)").foregroundStyle(.secondary)
            TextField("0",value:$model.configuration.minimumDurationMS,format:.number).textFieldStyle(.roundedBorder)
          }
        }.disabled(model.hasSession || model.busy)
        VStack(alignment:.leading,spacing:4) {
          StudioDisclosureHeader(title:"Diğer yakalama filtreleri",icon:"line.3.horizontal.decrease.circle",tint:StudioTheme.muted,expanded:advancedCapture) {advancedCapture.toggle()}.frame(height:28)
          if choices.loading {ProgressView().controlSize(.small)}
          Button {choices.refresh()} label:{Label("Seçenekleri Yenile",systemImage:"arrow.clockwise")}
            .buttonStyle(StudioSecondaryButton()).disabled(choices.loading).studioHelp(choices.note)
        }
        if !choices.error.isEmpty {StudioFeedback(message:choices.error,tone:.warning)}
        if advancedCapture {
          VStack(alignment:.leading,spacing:8) {
            choice("Host",column:.host,text:$model.configuration.host)
            choice("SPID",column:.session,text:$model.configuration.sessionID)
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

        }
        VStack(alignment:.leading,spacing:4) {
          StudioDisclosureHeader(title:"Kolon filtreleri · \(model.displayFilter.rules.filter {!$0.value.isEmpty}.count) koşul",icon:"line.3.horizontal.decrease",tint:StudioTheme.accent,expanded:columnsExpanded) {columnsExpanded.toggle()}.frame(height:28)
          Button {model.displayFilter = .init()} label:{Label("Filtreleri Sıfırla",systemImage:"arrow.counterclockwise")}
            .buttonStyle(StudioSecondaryButton())
        }
        if columnsExpanded {
          ForEach($model.displayFilter.rules) {$rule in
            VStack(alignment:.leading,spacing:4) {
              Picker("Kolon",selection:$rule.column) {ForEach(SQLProfilerFiltering.Column.allCases) {Text($0.title).tag($0)}}
                .labelsHidden().frame(width:155)
                .onChange(of:rule.column) {_,column in rule.comparison=column.operators[0]}
              Picker("Karşılaştırma",selection:$rule.comparison) {ForEach(rule.column.operators) {Text($0.title).tag($0)}}.labelsHidden()
              TextField("Filtre değeri",text:$rule.value).textFieldStyle(.roundedBorder)
              Button {model.displayFilter.rules.removeAll {$0.id==rule.id}} label:{Image(systemName:"minus.circle")}
                .buttonStyle(StudioSecondaryButton()).accessibilityLabel("Bu filtreyi kaldır")
            }
          }
          VStack(alignment:.leading,spacing:4) {
            Button {model.displayFilter.rules.append(.init())} label:{Label("Koşul Ekle",systemImage:"plus")}
              .buttonStyle(StudioSecondaryButton()).disabled(model.displayFilter.rules.count>=20)
            Text("Koşullar VE ile birleşir. Grid filtreleri ve SQL araması toplama sırasında da çalışır; yakalanan olayları silmez.")
              .font(.system(size:11)).foregroundStyle(.secondary)
            Spacer()
          }
        }
      }
    }
  }
  private func choice(_ title:String,column:SQLProfilerFiltering.Column,text:Binding<String>)->some View {
    VStack(alignment:.leading,spacing:4) {
      HStack(spacing:4) {
        Text(title).foregroundStyle(.secondary)
        Spacer(minLength:0)
        Button {
          if !manualColumns.insert(column).inserted {manualColumns.remove(column)}
        } label:{Image(systemName:manualColumns.contains(column) ? "list.bullet":"pencil")}
          .buttonStyle(.plain)
          .accessibilityLabel(title+(manualColumns.contains(column) ? " · Listeden seç":" · Elle değer gir"))
          .studioHelp(manualColumns.contains(column) ? "Aramalı listeden seç":"Listede olmayan değeri elle gir")
      }
      if manualColumns.contains(column) {TextField("Tümü",text:text).textFieldStyle(.roundedBorder)}
      else {StudioSearchablePicker(title:title,values:choices.values(for:column),emptyTitle:"Tümü",selection:text)
          .frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("profilerChoice_"+column.rawValue)}
    }
  }
  private func field(_ title:String,text:Binding<String>)->some View {
    VStack(alignment:.leading,spacing:4) {Text(title).foregroundStyle(.secondary);TextField("Tümü",text:text).textFieldStyle(.roundedBorder)}
  }
}
