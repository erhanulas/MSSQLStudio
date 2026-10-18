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
  @State private var sortingError=""
  @State private var exporting=false
  @StateObject private var preview=ProfilerPreviewPresentation()
  private var selectedEvents:[SQLProfiler.Event] {model.visibleEvents.filter {selected.contains($0.id)}}
  private var selectedEvent:SQLProfiler.Event? {selectedEvents.first}
  private var previewEvents:[SQLProfiler.Event] {
    model.previewEvents(selectedEvents)
  }
  private var relatedMessages:[SQLProfiler.Event] {
    guard let event=selectedEvent else {return []}
    let messages=event.kind=="error_reported" ? [event]:model.relations[event.id]?.messages ?? []
    return messages.filter {!model.displayFilter.hidesNotification($0)}
  }
  var body:some View {
    VStack(spacing:8) {
      if !model.filterError.isEmpty {StudioFeedback(message:model.filterError)}
      if !sortingError.isEmpty {StudioFeedback(message:sortingError)}
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
      HStack(spacing:4) {
        if model.hasSession {
          Button {Task {await model.stop()}} label:{Label(model.running ? "Durdur":"Temizle",systemImage:"stop.fill")}
            .buttonStyle(StudioSecondaryButton()).disabled(model.busy)
        } else {
          Button {
            let name=SQLProfiler.sessionName(UUID())
            do {let sql=try model.preview(name:name);validationError="";Task {await model.start(name:name,confirmedSQL:sql)}}
            catch {validationError=error.localizedDescription}
          } label:{Label("Başlat",systemImage:"play.fill")}
            .buttonStyle(StudioPrimaryButton()).disabled(model.busy)
            .studioHelp("Sunucuda bu pencereye ait Extended Events oturumu oluşturur. Sunucu izinleri gerekir. Yoğunlukta olay kaybı olabilir; zorla kapanma veya ağ kaybında oturum sunucuda kalabilir. Durdur işlemi oturumu kaldırır.")
        }
        Button {model.clearDisplay();selected=[];selectedClient=nil} label:{Image(systemName:"clear").accessibilityLabel("Listeyi Temizle")}
          .buttonStyle(StudioSecondaryButton()).disabled(model.busy).studioHelp("Listeyi Temizle")
        Button(action:background) {Image(systemName:"rectangle.on.rectangle").accessibilityLabel("Arka Planda İzle")}
          .buttonStyle(StudioSecondaryButton())
          .studioHelp("Pencereyi gizler. İzleme ve olay toplama devam eder; üstteki Profiler düğmesiyle geri açın.")
        ProfilerSessionsButton(model:model.sessions,currentSession:model.sessionName)
      }.controlSize(.small)
          ProfilerFilters(model:model,showClients:$showClients)
        }.padding(8).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
      } content: {
        VStack(spacing:4) {
        HStack {
          StudioTabBar(items:[.init(id:0,title:"Olaylar",icon:"list.bullet",tone:.accent),.init(id:1,title:"Yoğun istemciler",icon:"desktopcomputer",tone:.warning)],selection:Binding(get:{showClients ? 1:0},set:{showClients=$0==1})).frame(width:320)
          Spacer()
          StudioSelectionMenu(title:exporting ? "Aktarılıyor…":"Dışa Aktar",symbol:"square.and.arrow.up",items:
            ProfilerExport.Format.allCases.flatMap {format in [
              .init(title:"Seçili olaylar · "+format.title,enabled:!selectedEvents.isEmpty,action:{export(selectedEvents,format:format)}),
              .init(title:"Tüm olaylar · "+format.title,enabled:!model.events.isEmpty,action:{export(model.events,format:format)})
            ]}
          ).frame(width:142).disabled(exporting)
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
        }.frame(minWidth:480,maxWidth:.infinity,maxHeight:.infinity)
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
    ProfilerEventGrid(model:model,selection:$selected,sortingFailure:$sortingError)
  }
  private var clientTable:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Text("Filtrelenen, bellekte tutulan olaylara göre · Varsayılan: olay sayısı azalan sıra").foregroundStyle(.secondary)
        Spacer()
        Button {
          if let client=model.clients.first(where:{$0.id==selectedClient}) {model.focusClient(client);showClients=false}
        } label:{Label("Bu İstemcinin SQL’lerini Göster",systemImage:"line.3.horizontal.decrease.circle")}
          .buttonStyle(StudioSecondaryButton()).disabled(!model.clients.contains {$0.id==selectedClient})
      }
      StudioDataGrid(rows:model.clients,columns:[
        .init(title:"ClientProcessID",numeric:true,value:{$0.id.pid}),
        .init(title:"Host",width:180,value:{$0.id.host}),
        .init(title:"Olay sayısı",numeric:true,value:{String($0.count)}),
        .init(title:"Ölçülen süre (ms)",width:160,numeric:true,value:{$0.durationMS.map {String($0)}}),
        .init(title:"Uygulamalar",width:320,value:{$0.applications})
      ],selection:$selectedClient,identifier:"profilerClients")
      if model.unknownClientEvents>0 {Text("\(model.unknownClientEvents) olayın PID/Host bilgisi yok; istemci sıralamasına dahil edilmedi.").font(.system(size:11)).foregroundStyle(.secondary)}
    }
  }

}
