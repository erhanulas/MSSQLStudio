import AppKit
import SwiftUI
import SQLServerKit

struct ProfilerFilters:View {
  @ObservedObject var model:ProfilerModel
  @ObservedObject private var choices:ProfilerChoicesModel
  @State private var manualColumns:Set<SQLProfilerFiltering.Column>=[.application,.clientPID,.host,.session]
  @State private var expanded:Set<String>=["scope","client","sql","filtering"]
  init(model:ProfilerModel,showClients:Binding<Bool>) {self.model=model;choices=model.choices}
  var body:some View {
    ScrollView {
      VStack(alignment:.leading,spacing:8) {
        Toggle("Bilgi ve uyarıları gizle",isOn:$model.displayFilter.hideInformational)
          .toggleStyle(.checkbox).accessibilityIdentifier("profilerHideInformational")
          .studioHelp("Bilgi bildirimlerini ve uyarıları görünümden gizler. Hatalar ve düzeyi bilinmeyen olaylar korunur; yakalama ve tüm olayları dışa aktarma değişmez.")
        Divider()
        Text(model.hasSession ? "Yakalama · Düzenlemek için durdurun":"Yakalama · Sunucuda uygulanır")
          .font(.system(size:11)).foregroundStyle(.secondary)
        category("scope",title:"Veritabanı ve kimlik",symbol:"externaldrive") {
          choice("Veritabanı",column:.database,text:$model.configuration.database)
          choice("Login",column:.login,text:$model.configuration.login)
        }
        category("client",title:"İstemci",symbol:"desktopcomputer") {
          choice("Uygulama",column:.application,text:$model.configuration.application)
          choice("Client PID",column:.clientPID,text:$model.configuration.clientPID)
          choice("Host",column:.host,text:$model.configuration.host)
          choice("SPID",column:.session,text:$model.configuration.sessionID)
        }
        category("sql",title:"SQL ve süre",symbol:"curlybraces") {
          field("SQL LIKE",text:$model.configuration.sqlLike)
          field("SQL NOT LIKE",text:$model.configuration.sqlNotLike)
          HStack(spacing:8) {
            Text("En az ms").foregroundStyle(.secondary).frame(width:90,alignment:.leading)
            TextField("0",value:$model.configuration.minimumDurationMS,format:.number).textFieldStyle(.roundedBorder)
          }.frame(height:28).modifier(ProfilerFilterEmphasis(active:model.configuration.minimumDurationMS>0)).disabled(model.hasSession || model.busy)
          Text("LIKE: % metin, _ tek karakter. Örnek: %STOK%.").font(.system(size:11)).foregroundStyle(.secondary)
        }
        Button {choices.refresh()} label:{Label("Seçenekleri Yenile",systemImage:"arrow.clockwise")}
          .buttonStyle(StudioSecondaryButton()).disabled(choices.loading).studioHelp(choices.note)
        if choices.loading {ProgressView().controlSize(.small)}
        if !choices.error.isEmpty {StudioFeedback(message:choices.error,tone:.warning)}
        Divider()
        category("filtering",title:"Filtreleme",symbol:"line.3.horizontal.decrease") {
          ProfilerFilterTemplateControls(model:model)
          HStack(spacing:8) {
            Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
            TextField("Yakalanan SQL’de ara…",text:$model.displayFilter.sqlSearch).textFieldStyle(.roundedBorder)
              .accessibilityIdentifier("profilerSQLSearch")
              .modifier(ProfilerFilterEmphasis(active:!model.displayFilter.sqlSearch.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty))
            if model.filtering {ProgressView().controlSize(.small)}
          }
          HStack {
            Text("Grid filtreleri · \(model.displayFilter.rules.count+model.displayFilter.columnRules.count)").foregroundStyle(.secondary)
            Spacer(minLength:0)
            Button {model.displayFilter = .init()} label:{Image(systemName:"arrow.counterclockwise")}
              .buttonStyle(StudioSecondaryButton()).accessibilityLabel("Grid filtrelerini sıfırla").studioHelp("Grid filtrelerini ve SQL aramasını sıfırla; yakalamayı değiştirmez")
          }
          Text("Kolon başlığına tıklayarak koşul ekleyin. Hücreye sağ tıklayarak değerini filtreleyin.")
            .font(.system(size:11)).foregroundStyle(.secondary)
          ForEach(SQLProfilerFiltering.Column.allCases.filter {model.displayFilter.columnRules[$0]?.active==true}) {column in
            HStack {
              VStack(alignment:.leading,spacing:4) {
                Text(column.title).fontWeight(.medium)
                Text(model.displayFilter.columnRules[column]?.summary ?? "").font(.system(size:11)).lineLimit(2)
              }
              Spacer(minLength:0)
              Button {model.displayFilter.columnRules.removeValue(forKey:column)} label:{Image(systemName:"xmark")}
                .buttonStyle(StudioSecondaryButton()).accessibilityLabel(column.title+" filtresini kaldır").studioHelp("Bu kolon filtresini kaldır")
            }
          }
          ForEach($model.displayFilter.rules) {$rule in
            VStack(alignment:.leading,spacing:4) {
              HStack {
                Text(rule.column.title).fontWeight(.medium)
                Spacer(minLength:0)
                Button {model.displayFilter.rules.removeAll {$0.id==rule.id}} label:{Image(systemName:"xmark")}
                  .buttonStyle(StudioSecondaryButton()).accessibilityLabel(rule.column.title+" filtresini kaldır").studioHelp("Bu koşulu kaldır")
              }
              HStack(spacing:4) {
                Picker("Karşılaştırma",selection:$rule.comparison) {ForEach(rule.column.operators) {Text($0.title).tag($0)}}.labelsHidden().frame(width:110)
                TextField("Değer",text:$rule.value).textFieldStyle(.roundedBorder)
                  .modifier(ProfilerFilterEmphasis(active:!rule.value.isEmpty))
              }
            }.padding(8).background(Color(nsColor:StudioTheme.controlSurface)).clipShape(RoundedRectangle(cornerRadius:6))
          }
        }
      }.padding(.trailing,4)
    }
  }
  private func category<Content:View>(_ key:String,title:String,symbol:String,@ViewBuilder content:()->Content)->some View {
    VStack(alignment:.leading,spacing:4) {
      StudioDisclosureHeader(title:title,icon:symbol,tint:StudioTheme.muted,expanded:expanded.contains(key)) {
        if !expanded.insert(key).inserted {expanded.remove(key)}
      }.frame(height:28)
      if expanded.contains(key) {content()}
    }
  }
  private func choice(_ title:String,column:SQLProfilerFiltering.Column,text:Binding<String>)->some View {
    ProfilerCaptureChoice(title:title,values:choices.values(for:column),text:text,manual:Binding(get:{manualColumns.contains(column)},set:{value in
      if value {manualColumns.insert(column)} else {manualColumns.remove(column)}
    })).disabled(model.hasSession || model.busy)
  }
  private func field(_ title:String,text:Binding<String>)->some View {
    HStack(spacing:8) {
      Text(title).foregroundStyle(.secondary).frame(width:90,alignment:.leading)
      TextField("Tümü",text:text).textFieldStyle(.roundedBorder)
    }.frame(height:28).modifier(ProfilerFilterEmphasis(active:!text.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)).disabled(model.hasSession || model.busy)
  }
}

struct ProfilerCaptureChoice:View {
  let title:String
  let values:[String]
  @Binding var text:String
  @Binding var manual:Bool
  var body:some View {
    HStack(spacing:4) {
      Text(title).foregroundStyle(.secondary).frame(width:90,alignment:.leading).lineLimit(1)
      Group {
        if manual {TextField("Tümü",text:$text).textFieldStyle(.roundedBorder)}
        else {StudioSearchablePicker(title:title,values:values,emptyTitle:"Tümü",selection:$text)}
      }.frame(maxWidth:.infinity)
      ProfilerInputModeButton(manual:$manual,title:title).frame(width:52,height:26)
    }.frame(height:28).modifier(ProfilerFilterEmphasis(active:!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty))
  }
}

private struct ProfilerFilterEmphasis:ViewModifier {
  let active:Bool
  func body(content:Content)->some View {
    content.background(RoundedRectangle(cornerRadius:6).fill(Color(nsColor:StudioTheme.selection).opacity(active ? 1:0)))
      .overlay(RoundedRectangle(cornerRadius:6).stroke(Color(nsColor:StudioTheme.accent).opacity(active ? 0.65:0),lineWidth:1).allowsHitTesting(false))
  }
}

struct ProfilerInputModeButton:NSViewRepresentable {
  @Environment(\.isEnabled) private var enabled
  @Binding var manual:Bool
  let title:String
  func makeNSView(context:Context)->Button {Button(frame:.zero)}
  func updateNSView(_ button:Button,context:Context) {
    button.isEnabled=enabled
    button.title=manual ? "Liste":"Elle"
    button.image=NSImage(systemSymbolName:manual ? "list.bullet":"square.and.pencil",accessibilityDescription:nil)
    button.setAccessibilityLabel(title+(manual ? " · Listeden seç":" · Elle değer gir"))
    StudioHoverHelp.shared.configureText(manual ? "Aramalı listeden seç":"Listede olmayan değeri elle gir",for:button)
    button.activate={manual.toggle()}
  }
  @MainActor final class Button:StudioFullAreaButton {
    var activate:(()->Void)?
    override init(frame:NSRect) {
      super.init(frame:frame);setButtonType(.momentaryPushIn);bezelStyle = .rounded;isBordered=false
      imagePosition = .imageLeading;font=StudioTheme.uiFont;target=self;action=#selector(toggleMode)
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func toggleMode() {if isEnabled {activate?()}}
  }
}
