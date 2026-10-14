import AppKit
import SQLServerKit
import SwiftUI

struct RoutineInvocationPanel:View {
  let qualified:String
  let function:Bool
  let tableValued:Bool
  let load:() async throws -> [RoutineParameter]
  let open:(String)->Void
  @State private var parameters:[RoutineParameter]=[]
  @State private var arguments:[Int:RoutineArgument]=[:]
  @State private var ready=false
  @State private var error=""
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:function ? "Invoke Function" : "Execute Stored Procedure",icon:function ? "function" : "terminal",subtitle:qualified)
      Text("Değerler metin olarak girilir, veri tipine çevrilir. DEFAULT seçimi procedure'de parametreyi atlar; zorunluysa SQL Server hata verir. SQL henüz çalıştırılmaz.").font(.caption).foregroundStyle(.secondary)
      if !ready {ProgressView("Parametreler yükleniyor…")}
      ScrollView {
        LazyVStack(alignment:.leading,spacing:10) {
          if ready && parameters.isEmpty {Text("Parametresiz nesne")}
          ForEach(parameters) { p in HStack {
            Text(p.name).frame(width:130,alignment:.leading)
            Text(p.type+(p.output ? " · OUTPUT" : "")).foregroundStyle(.secondary).frame(width:170,alignment:.leading)
            Picker("Gönderim",selection:Binding(get:{arguments[p.id]?.mode ?? "NULL"},set:{arguments[p.id,default:RoutineArgument()].mode=$0})) {Text("Değer").tag("Value");Text("NULL").tag("NULL");if !p.output {Text("DEFAULT").tag("DEFAULT")}}.labelsHidden().frame(width:110)
            TextField("Değer",text:Binding(get:{arguments[p.id]?.value ?? ""},set:{arguments[p.id,default:RoutineArgument()].value=$0})).disabled(arguments[p.id]?.mode != "Value")
          } }
        }.padding(8)
      }
      StudioFeedback(message:error)
      HStack {Spacer();StudioActionButton("SQL Editöründe İncele", icon:"doc.text.magnifyingglass", tint:.accentColor) {do {open(try RoutineScripts.invocation(qualified:qualified,function:function,tableValued:tableValued,parameters:parameters,arguments:arguments));error=""} catch {self.error=error.localizedDescription}}.disabled(!ready)}
    }.padding(StudioMetrics.gap).studioPanel().task {do {parameters=try await load();for p in parameters {arguments[p.id]=RoutineArgument()};ready=true} catch {self.error=error.localizedDescription}}
  }
}
