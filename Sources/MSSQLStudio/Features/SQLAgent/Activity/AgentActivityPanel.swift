import AppKit
import SQLServerKit
import SwiftUI

struct AgentActivityPanel:View {
  let server:ConnectedServer
  let history:(String?)->Void
  let properties:(SQLAgent.Job)->Void
  let action:(SQLAgent.Job,SQLAgent.Action)->Void
  @State private var jobs:[SQLAgent.Job]=[]
  @State private var error=""
  @State private var service="Agent servisi sorgulanıyor…"
  @State private var generation=0
  @State private var search=""
  @State private var filter=0
  @State private var refresh=0
  @State private var selected:String?
  @State private var loading=false
  @State private var refreshed=""
  @State private var sortOrder=[KeyPathComparator(\SQLAgent.Job.name)]
  private var visible:[SQLAgent.Job] {jobs.filter {job in
    (search.isEmpty || job.name.localizedCaseInsensitiveContains(search)) &&
    (filter == 0 || (filter == 1 && job.state == "Running") || (filter == 2 && !job.enabled) || (filter == 3 && job.lastStatus == 0))
  }.sorted(using:sortOrder)}
  private var chosen:SQLAgent.Job? {visible.first {$0.id == selected}}
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      StudioPanelHeading(title:"Job Activity Monitor",icon:"waveform.path.ecg",subtitle:server.profile.name)
      HStack {
        TextField("İş adı ara",text:$search).textFieldStyle(.roundedBorder)
        Picker("Göster",selection:$filter) {Text("Tüm işler").tag(0);Text("Çalışanlar").tag(1);Text("Devre dışı").tag(2);Text("Son çalışması hatalı").tag(3)}.frame(width:220)
        Picker("Otomatik yenile",selection:$refresh) {Text("Kapalı").tag(0);Text("15 saniye").tag(15);Text("30 saniye").tag(30);Text("60 saniye").tag(60)}.frame(width:190)
        StudioActionButton("Yenile", icon:"arrow.clockwise", tint:.accentColor) {generation+=1}.disabled(loading)
      }
      Text(service).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      if loading {ProgressView().controlSize(.small)}
      if !error.isEmpty {StudioFeedback(message:error)}
      Table(visible,selection:$selected,sortOrder:$sortOrder) {
        TableColumn("İş",value:\.name).width(min:150,ideal:250)
        TableColumn("Etkin") {Text($0.enabled ? "Evet":"Hayır")}.width(55)
        TableColumn("Durum") {Label($0.state,systemImage:$0.state == "Running" ? "arrow.triangle.2.circlepath":"pause.circle")}.width(100)
        TableColumn("Son sonuç") {AgentStatus(status:$0.lastStatus)}.width(110)
        TableColumn("Son çalışma",value:\.lastRun).width(165)
        TableColumn("Sonraki çalışma",value:\.nextRun).width(165)
        TableColumn("Sahip",value:\.owner)
      }.accessibilityIdentifier("agentActivityTable").contextMenu(forSelectionType:String.self,menu:{ids in
        if let job=jobs.first(where:{ids.contains($0.id)}) {
          StudioActionButton("View History…",icon:"clock.arrow.circlepath",tint:.accentColor) {history(job.name)}
          StudioActionButton("Properties…",icon:"slider.horizontal.3",tint:.accentColor) {properties(job)}
          StudioActionButton("Start Job…",icon:"play.fill",tint:.green) {action(job,.start)}.disabled(job.state == "Running")
          StudioActionButton("Stop Job…",icon:"stop.fill",tint:.orange) {action(job,.stop)}.disabled(job.state != "Running")
          StudioActionButton(job.enabled ? "Disable…":"Enable…",icon:job.enabled ? "pause.circle":"checkmark.circle",tint:job.enabled ? .orange:.green) {action(job,job.enabled ? .disable:.enable)}
        }
      },primaryAction:{ids in if let job=jobs.first(where:{ids.contains($0.id)}) {properties(job)}})
      HStack {
        StudioActionButton("Geçmiş", icon:"clock.arrow.circlepath", tint:.accentColor) {history(chosen?.name)}.accessibilityIdentifier("agentActivityHistory")
        StudioActionButton("Özellikler…", icon:"slider.horizontal.3", tint:.accentColor) {if let chosen {properties(chosen)}}.disabled(chosen == nil)
        Divider().frame(height:18)
        StudioActionButton("Başlat…", icon:"play.fill", tint:.green) {if let chosen {action(chosen,.start)}}.disabled(chosen == nil || chosen?.state == "Running")
        StudioActionButton("Durdur…", icon:"stop.fill", tint:.orange) {if let chosen {action(chosen,.stop)}}.disabled(chosen?.state != "Running")
        StudioActionButton(chosen?.enabled == false ? "Etkinleştir…":"Devre Dışı Bırak…",icon:chosen?.enabled == false ? "checkmark.circle":"pause.circle",tint:chosen?.enabled == false ? .green:.orange) {if let chosen {action(chosen,chosen.enabled ? .disable:.enable)}}.disabled(chosen == nil)
        Spacer()
        Text("\(visible.count) / \(jobs.count) iş · \(refreshed)").font(.caption).foregroundStyle(.secondary)
      }
      Text("En çok 1.000 iş. Sonraki çalışma bilgisi Agent önbelleği nedeniyle gecikmeli olabilir. Agent servisi sunucu işletim sisteminden yönetilir.").font(.caption).foregroundStyle(.secondary)
    }.padding(StudioMetrics.gap).studioPanel().task(id:"\(generation)|\(refresh)") {
      repeat {
        await load()
        guard refresh>0,!Task.isCancelled else {return}
        do {try await Task.sleep(for:.seconds(refresh))} catch {return}
      } while !Task.isCancelled
    }.onReceive(NotificationCenter.default.publisher(for:.init("studioAgentChanged"))) {notification in
      if let changed=notification.object as? ConnectedServer,changed === server {generation+=1}
    }
  }
  private func load() async {
    loading=true;error="";defer {loading=false}
    do {
      let result=try await server.catalog(SQLAgent.jobs(),database:"msdb");try Task.checkCancellation()
      jobs=try SQLAgent.decodeJobs(result);refreshed=Date().formatted(date:.omitted,time:.standard)
      if !jobs.contains(where:{$0.id == selected}) {selected=nil}
    } catch is CancellationError {return} catch {jobs=[];selected=nil;self.error=error.localizedDescription}
    do {
      let result=try await server.catalog(SQLAgent.serviceStatus,database:"master");try Task.checkCancellation()
      service=result.results.first?.values.map {$0.compactMap {$0}.joined(separator:" · ")}.joined(separator:"\n") ?? ""
      if service.isEmpty {service="Agent servisi bu instance için raporlanmadı."}
    } catch is CancellationError {} catch {service="Servis durumu okunamadı: "+error.localizedDescription}
  }
}
