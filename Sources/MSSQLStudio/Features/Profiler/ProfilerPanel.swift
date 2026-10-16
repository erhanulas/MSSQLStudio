import AppKit
import SwiftUI
import SQLServerKit

struct ProfilerPanel:View {
  @ObservedObject var model:ProfilerModel
  let background:()->Void
  var openQuery:(([SQLProfiler.Event])->Void)?=nil
  @State private var selected:Set<UInt64>=[]
  @State private var selectedClient:SQLProfilerFiltering.Client.Key?
  @State private var showClients=false
  @State private var validationError=""
  @State private var exporting=false
  @StateObject private var preview=ProfilerPreviewPresentation()
  private var selectedEvents:[SQLProfiler.Event] {model.visibleEvents.filter {selected.contains($0.id)}}
  private var selectedEvent:SQLProfiler.Event? {selectedEvents.first}
  private var previewEvents:[SQLProfiler.Event] {
    model.previewEvents(selectedEvents)
  }
  private var relatedMessages:[SQLProfiler.Event] {
    guard let event=selectedEvent else {return []}
    if event.kind=="error_reported" {return [event]}
    return model.relations[event.id]?.messages ?? []
  }
  var body:some View {
    VStack(spacing:8) {
      if !model.filterError.isEmpty {StudioFeedback(message:model.filterError)}
      if !validationError.isEmpty {StudioFeedback(message:validationError)}
      if !model.error.isEmpty {StudioFeedback(message:model.error,tone:.error)}
      if !model.warning.isEmpty {StudioFeedback(message:model.warning,tone:.warning)}
      ProfilerSplitView {
        VStack(alignment:.leading,spacing:8) {
      HStack {
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
            do {let sql=try model.preview(name:name);validationError="";Task {await model.start(name:name,confirmedSQL:sql)}}
            catch {validationError=error.localizedDescription}
          } label:{Label("İzlemeyi Başlat",systemImage:"play.fill")}
            .buttonStyle(StudioPrimaryButton()).disabled(model.busy)
            .studioHelp("Sunucuda bu pencereye ait Extended Events oturumu oluşturur. Sunucu izinleri gerekir. Yoğunlukta olay kaybı olabilir; zorla kapanma veya ağ kaybında oturum sunucuda kalabilir. Durdur işlemi oturumu kaldırır.")
        }
        Button {model.clearDisplay();selected=[];selectedClient=nil} label:{Image(systemName:"clear").accessibilityLabel("Listeyi Temizle")}
          .buttonStyle(StudioSecondaryButton()).disabled(model.busy).studioHelp("Listeyi Temizle")
        Button(action:background) {Image(systemName:"rectangle.on.rectangle").accessibilityLabel("Arka Planda İzle")}
          .buttonStyle(StudioSecondaryButton())
          .studioHelp("Pencereyi gizler. İzleme ve olay toplama devam eder; üstteki Profiler düğmesiyle geri açın.")
      }
          ProfilerSessionsButton(model:model.sessions,currentSession:model.sessionName)
          ProfilerFilters(model:model,showClients:$showClients)
        }.padding(8).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
      } content: {
        VStack(spacing:4) {
        HStack {
          Picker("Grid",selection:$showClients) {Text("Olaylar").tag(false);Text("Yoğun istemciler").tag(true)}.pickerStyle(.segmented).labelsHidden().frame(width:240)
          Spacer()
          Menu {
            ForEach(ProfilerExport.Format.allCases) {format in
              Button("Seçili olaylar · "+format.title) {export(selectedEvents,format:format)}.disabled(selectedEvents.isEmpty)
              Button("Tüm olaylar · "+format.title) {export(model.events,format:format)}.disabled(model.events.isEmpty)
            }
          } label:{Label(exporting ? "Aktarılıyor…":"Dışa Aktar",systemImage:"square.and.arrow.up")}.disabled(exporting)
        }
        VSplitView {
        Group {
          if showClients {clientTable} else {eventTable}
        }.frame(minHeight:110)
        VStack(alignment:.leading,spacing:8) {
          HStack {
            Text(selected.count>1 ? "\(selectedEvents.count) olay · GO ile ayrılmış SQL":"SQL").font(.headline)
            Spacer()
            if preview.busy {ProgressView().controlSize(.small)}
            Button {NSPasteboard.general.clearContents();NSPasteboard.general.setString(ProfilerExport.sql(previewEvents),forType:.string)} label:{Label("SQL’i Kopyala",systemImage:"doc.on.doc")}.buttonStyle(StudioSecondaryButton()).disabled(selectedEvents.isEmpty)
            Button {openQuery?(previewEvents)} label:{Label("Yeni Sekmede Aç",systemImage:"plus.rectangle.on.rectangle")}
              .buttonStyle(StudioSecondaryButton()).disabled(selectedEvents.isEmpty || openQuery==nil)
          }
          ForEach(Array(relatedMessages.prefix(3))) { event in StudioFeedback(message:event.message,tone:ProfilerMessagePresentation.tone(event.messageLevel),heading:ProfilerMessagePresentation.heading(event))}
          if relatedMessages.count>3 {
            Text("Bu çağrıda \(relatedMessages.count) bildirim var; tümü olay listesinde korunur.")
              .font(.system(size:StudioMetrics.detailFont)).foregroundStyle(.secondary)
          }
          if let event=selectedEvent,event.sql.isEmpty,let relation=model.relations[event.id] {
            Text(relation.source.sql.isEmpty ? "Sunucu bu çağrı için SQL metni sağlamadı.":"SQL, aynı çağrının nedensellik kimliğiyle ilişkilendirildi.")
              .font(.system(size:StudioMetrics.detailFont)).foregroundStyle(.secondary)
          }
          if let event=selectedEvent,["rpc_completed","sql_batch_completed"].contains(event.kind) {
            Text("Tamamlanma olayı başarı garantisi değildir; SQL Server hata metnini error_reported olayında bildirir.")
              .font(.system(size:StudioMetrics.detailFont)).foregroundStyle(.secondary)
          }
          SQLReadOnlyPreview(sql:preview.sql,lexicalSnapshot:preview.tokens)
        }.padding(.top,8).frame(minHeight:90)
      }
        }.frame(minWidth:440,maxWidth:.infinity,maxHeight:.infinity)
      }.frame(maxWidth:.infinity,maxHeight:.infinity)
      HStack {
        Text("\(model.visibleEvents.count) / \(model.events.count) olay · Son 5.000 / 8 MB · Hedef \(model.pollingCaption)").foregroundStyle(.secondary)
        Spacer()
        if let last=model.lastRead {Text("Son okuma: "+last.formatted(date:.omitted,time:.standard)).foregroundStyle(.secondary)}
      }.font(.system(size:11))
    }.onChange(of:selected) {_,_ in preview.request(previewEvents)}
      .onChange(of:model.gridRevision) {_,_ in preview.request(previewEvents)}
      .padding(8).font(.system(size:12)).background(Color(nsColor:StudioTheme.panel))
  }
  private func export(_ events:[SQLProfiler.Event],format:ProfilerExport.Format) {
    let panel=NSSavePanel();panel.nameFieldStringValue="Profiler."+format.suffix
    exporting=true
    panel.begin {response in
      guard response == .OK,let url=panel.url else {exporting=false;return}
      Task {
        do {try await Task.detached(priority:.utility) {try ProfilerExport.data(events,format:format).write(to:url,options:.atomic)}.value;validationError=""}
        catch {validationError=error.localizedDescription}
        exporting=false
      }
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
