import AppKit
import SwiftUI
import SQLServerKit

struct ProfilerPanel:View {
  @ObservedObject var model:ProfilerModel
  let background:()->Void
  @State private var selected:UInt64?
  @State private var selectedClient:SQLProfilerFiltering.Client.Key?
  @State private var showClients=false
  @State private var validationError=""
  @State private var confirmation:StartPreview?
  private struct StartPreview:Identifiable {let id:String;let sql:String}
  private var selectedEvent:SQLProfiler.Event? {model.visibleEvents.first {$0.id==selected}}
  var body:some View {
    VStack(spacing:8) {
      HStack {
        StudioPanelHeading(title:"SQL Profiler",icon:"list.bullet.rectangle.portrait",subtitle:model.serverName+" · Extended Events")
        Spacer()
        Label(model.running ? "İzleniyor":model.hasSession ? "Temizlik gerekiyor":"Durduruldu",systemImage:model.running ? "record.circle":"stop.circle")
          .foregroundStyle(Color(nsColor:model.running ? StudioTheme.success:StudioTheme.muted))
        if model.busy {ProgressView().controlSize(.small)}
      }
      HStack {
        if model.hasSession {
          Button {Task {await model.stop()}} label:{Label(model.running ? "Durdur":"Temizle",systemImage:"stop.fill")}
            .buttonStyle(StudioSecondaryButton()).disabled(model.busy)
        } else {
          Button {
            let name=SQLProfiler.sessionName(UUID())
            do {let sql=try model.preview(name:name);validationError="";confirmation=StartPreview(id:name,sql:sql)}
            catch {validationError=error.localizedDescription}
          } label:{Label("İzlemeyi Başlat…",systemImage:"play.fill")}
            .buttonStyle(StudioPrimaryButton()).disabled(model.busy)
        }
        Button {model.clearDisplay();selected=nil;selectedClient=nil} label:{Label("Listeyi Temizle",systemImage:"clear")}
          .buttonStyle(StudioSecondaryButton()).disabled(model.busy)
        Button {
          if let event=selectedEvent {NSPasteboard.general.clearContents();NSPasteboard.general.setString(event.sql,forType:.string)}
        } label:{Label("SQL’i Kopyala",systemImage:"doc.on.doc")}
          .buttonStyle(StudioSecondaryButton()).disabled(selectedEvent==nil)
        Spacer()
        Button(action:background) {Label("Arka Planda İzle",systemImage:"rectangle.on.rectangle")}
          .buttonStyle(StudioSecondaryButton())
          .studioHelp("Pencereyi gizler. İzleme ve olay toplama devam eder; üstteki Profiler düğmesiyle geri açın.")
      }
      ProfilerFilters(model:model,showClients:$showClients)
      if !model.filterError.isEmpty {StudioFeedback(message:model.filterError)}
      if !validationError.isEmpty {StudioFeedback(message:validationError)}
      if !model.error.isEmpty {StudioFeedback(message:model.error,tone:.error)}
      if !model.warning.isEmpty {StudioFeedback(message:model.warning,tone:.warning)}
      VSplitView {
        Group {
          if showClients {clientTable} else {eventTable}
        }.frame(minHeight:110)
        VStack(alignment:.leading,spacing:8) {
          HStack {
            Label("Olayın SQL metni",systemImage:"curlybraces").font(.headline)
            Spacer()
            if let event=selectedEvent {Text(event.timestamp).foregroundStyle(.secondary).textSelection(.enabled)}
          }
          if let event=selectedEvent,!event.message.isEmpty {Text(event.message).foregroundStyle(Color(nsColor:StudioTheme.warning)).textSelection(.enabled).lineLimit(3)}
          SQLReadOnlyPreview(sql:selectedEvent?.sql ?? "-- SQL metnini görmek için bir olay seçin.")
        }.padding(.top,8).frame(minHeight:90)
      }
      HStack {
        Text("\(model.visibleEvents.count) / \(model.events.count) olay · Son 5.000 / 8 MB · 2 sn").foregroundStyle(.secondary)
        Spacer()
        if let last=model.lastRead {Text("Son okuma: "+last.formatted(date:.omitted,time:.standard)).foregroundStyle(.secondary)}
      }.font(.system(size:11))
    }.padding(16).font(.system(size:12)).background(Color(nsColor:StudioTheme.panel))
      .sheet(item:$confirmation) {preview in
        VStack(alignment:.leading,spacing:12) {
          StudioPanelHeading(title:"Sunucuda izlemeyi başlat",icon:"record.circle",subtitle:model.serverName)
          Text("Bu işlem sunucuda yalnız bu pencereye ait Extended Events oturumu oluşturur. CREATE/ALTER EVENT SESSION ve sunucu izleme izinleri gerekir. Tam denetim kaydı değildir; yoğunlukta olay kaybı olabilir.")
          Text("Sunucu arabelleği 512 KB, oturum belleği 2 MB. Normal durdurma/çıkış oturumu kaldırır. Uygulama zorla kapatılır veya bağlantı koparsa sunucuda kalabilir; aşağıdaki adı DBA’nıza iletin.").foregroundStyle(.secondary)
          Text(preview.id).font(.system(.body,design:.monospaced)).textSelection(.enabled)
          SQLReadOnlyPreview(sql:preview.sql).frame(minHeight:240)
          HStack {Spacer();Button("Vazgeç") {confirmation=nil}.buttonStyle(StudioSecondaryButton())
            Button {confirmation=nil;Task {await model.start(name:preview.id,confirmedSQL:preview.sql)}} label:{Label("Onayla ve Başlat",systemImage:"play.fill")}.buttonStyle(StudioPrimaryButton())}
        }.padding(16).frame(width:760,height:540)
      }
  }
  private var eventTable:some View {
    ProfilerEventGrid(model:model,selection:$selected)
  }
  private var clientTable:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Text("Filtrelenen, bellekte tutulan olaylara göre · Olay sayısı azalan sıra").foregroundStyle(.secondary)
        Spacer()
        Button {
          if let client=model.clients.first(where:{$0.id==selectedClient}) {model.focusClient(client);showClients=false}
        } label:{Label("Bu İstemcinin SQL’lerini Göster",systemImage:"line.3.horizontal.decrease.circle")}
          .buttonStyle(StudioSecondaryButton()).disabled(!model.clients.contains {$0.id==selectedClient})
      }
      Table(model.clients,selection:$selectedClient) {
        TableColumn("ClientProcessID") {Text($0.id.pid)}.width(110)
        TableColumn("Host") {Text($0.id.host)}.width(min:120,ideal:180)
        TableColumn("Olay sayısı") {Text(String($0.count))}.width(100)
        TableColumn("Ölçülen süre (ms)") {Text($0.durationMS.map {String(format:"%.3f",$0)} ?? "—")}.width(140)
        TableColumn("Uygulamalar",value:\.applications).width(min:180,ideal:320)
      }.tableStyle(.inset(alternatesRowBackgrounds:true))
      if model.unknownClientEvents>0 {Text("\(model.unknownClientEvents) olayın PID/Host bilgisi yok; istemci sıralamasına dahil edilmedi.").font(.system(size:11)).foregroundStyle(.secondary)}
    }
  }

}
