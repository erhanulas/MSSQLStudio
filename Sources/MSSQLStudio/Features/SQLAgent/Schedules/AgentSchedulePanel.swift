import AppKit
import SQLServerKit
import SwiftUI

struct AgentPickSchedule:View {
  @Environment(\.dismiss) private var dismiss
  let server:ConnectedServer
  let attached:Set<Int>
  let open:(SQLAgent.Schedule)->Void
  @State private var schedules:[SQLAgent.Schedule]=[]
  @State private var selected:Int?
  @State private var error=""
  @State private var loading=true
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Pick Schedule",icon:"calendar",subtitle:"Mevcut bir zamanlamayı bu işe bağlayın")
      if loading {ProgressView()}
      if !error.isEmpty {StudioFeedback(message:error)}
      Table(schedules,selection:$selected) {TableColumn("Ad",value:\.name);TableColumn("Tekrar",value:\.summary);TableColumn("Etkin") {Text($0.enabled ? "Evet":"Hayır")}}
      Text("Zamanlama paylaşılır; ileride yapılan düzenlemeler bu işi de etkiler. Zaten bağlı zamanlamalar listede gösterilmez.").font(.caption).foregroundStyle(.secondary)
      HStack {StudioActionButton("Vazgeç", icon:"xmark") {dismiss()};Spacer();StudioActionButton("Bağlama SQL’ini Aç", icon:"link", tint:.accentColor) {if let schedule=schedules.first(where:{$0.id == selected}) {open(schedule)}}.disabled(selected == nil)}
    }.padding(StudioMetrics.gap).frame(minWidth:620,idealWidth:850,maxWidth:.infinity,minHeight:420,idealHeight:520,maxHeight:.infinity).studioPanel().task {
      defer {loading=false}
      do {let result=try await server.catalog(SQLAgent.availableSchedules(),database:"msdb");try Task.checkCancellation();guard !result.partial else {throw SQLFailure("Zamanlama listesi kısmi.")};schedules=try SQLAgent.decodeSchedules(result.results.first.map {Array($0.values)} ?? []).filter {!attached.contains($0.id)}} catch is CancellationError {} catch {self.error=error.localizedDescription}
    }
  }
}
struct AgentSchedulePanel:View {
  let server:ConnectedServer
  let item:CatalogItem
  let close:()->Void
  let open:(String)->Void
  @State private var schedule:SQLAgent.Schedule?
  @State private var error=""
  var body:some View {
    Group {
      if let schedule {AgentScheduleEditor(schedule:schedule,isNew:false,cancel:close) {edited in
        do {open(try SQLAgent.checkedScript([SQLAgent.scheduleScript(edited)]))} catch {self.error=error.localizedDescription}
      }} else {
        VStack(spacing:16) {
          if error.isEmpty {ProgressView("Zamanlama yükleniyor…")} else {StudioFeedback(message:error)}
        }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(20)
      }
    }.task {
      do {
        let result=try await server.catalog(SQLAgent.scheduleDetails(id:item.id),database:"msdb");try Task.checkCancellation()
        guard !result.partial else {throw SQLFailure("Zamanlama bilgisi kısmi.")}
        schedule=try SQLAgent.decodeSchedules(result.results.first.map {Array($0.values)} ?? []).first
        if schedule == nil {throw SQLFailure("Zamanlama bulunamadı.")}
      } catch is CancellationError {} catch {self.error=error.localizedDescription}
    }
  }
}
