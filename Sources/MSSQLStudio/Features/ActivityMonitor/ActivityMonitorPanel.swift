import AppKit
import SwiftUI
import Charts
import SQLServerKit

@MainActor final class ActivityMonitorModel: ObservableObject {
  typealias Reader = @MainActor (String, Limits) async throws -> Execution
  @Published private(set) var samples:[ActivityMonitoring.Sample]=[]
  @Published private(set) var issues:[String]=[]
  @Published private(set) var error=""
  @Published private(set) var loading=false
  @Published private(set) var diagnostics=ActivityMonitoring.Diagnostics()
  @Published private(set) var diagnosticsTime:Date?
  @Published private(set) var diagnosticsError=""
  private var previous:ActivityMonitoring.Snapshot?
  private let reader:Reader
  private var activityRevision=UUID()
  private var diagnosticsRevision=UUID()
  private var dataGeneration:UUID?
  private(set) var visible=true
  private(set) var paused=false
  let server:ConnectedServer
  init(server:ConnectedServer,reader:Reader?=nil) {
    self.server=server
    self.reader=reader ?? {sql,limits in try await server.catalog(sql,database:"master",limits:limits)}
  }
  private var canRead:Bool {server.online || server.catalogFixture != nil || server.asyncCatalogFixture != nil}
  func breakSequence() {previous=nil}
  func clearDiagnostics() {diagnosticsRevision=UUID();diagnostics = .init();diagnosticsTime=nil;diagnosticsError=""}
  private func markOffline(_ detail:String="") {
    error="Bağlantı çevrimdışı. Son örnek güncel değil; Explorer’dan yeniden bağlanın."+(detail.isEmpty ? "":" "+detail)
    previous=nil;clearDiagnostics()
  }
  /// Explorer state notifications invalidate the visible cache without reconnecting or reading.
  func connectionChanged() {
    if dataGeneration != nil,dataGeneration != server.generation {
      samples=[];issues=[];previous=nil;clearDiagnostics();error=""
    }
    dataGeneration=server.generation
    if !canRead {markOffline()}
  }
  func setActivity(visible:Bool,paused:Bool) {
    guard self.visible != visible || self.paused != paused else {return}
    self.visible=visible;self.paused=paused;activityRevision=UUID();previous=nil
  }
  /// Pause stops automatic sampling. An explicit refresh is still permitted while visible.
  func load(includeDiagnostics:Bool=false,automatic:Bool=false) async {
    guard !loading,visible,!automatic || !paused else {return}
    connectionChanged()
    let revision=activityRevision,generation=server.generation
    guard canRead else {markOffline();return}
    let diagnosticRevision=diagnosticsRevision
    loading=true;defer {loading=false}
    func currentContext() -> Bool {revision == activityRevision && generation == server.generation && visible && (!automatic || !paused)}
    func current() -> Bool {currentContext() && canRead}
    func discardChangedGeneration() {if generation != server.generation {connectionChanged()}}
    var limits=Limits();limits.rows=30;limits.resultSets=2;limits.totalBytes=1_000_000;limits.timeout=10
    do {
      let result=try await reader(ActivityMonitoring.overviewSQL,limits)
      try Task.checkCancellation()
      guard currentContext() else {discardChangedGeneration();previous=nil;return}
      guard canRead else {markOffline();return}
      let snapshot=try ActivityMonitoring.decode(result)
      if samples.last.map({snapshot.time>$0.time}) ?? true {
        samples.append(ActivityMonitoring.sample(snapshot,previous:previous));previous=snapshot
        samples=Array(samples.filter {$0.time>=snapshot.time.addingTimeInterval(-900)}.suffix(181))
      }
      issues=snapshot.issues;error=""
    } catch is CancellationError {discardChangedGeneration();previous=nil;return}
    catch {
      guard currentContext() else {discardChangedGeneration();previous=nil;return}
      guard canRead else {markOffline(error.localizedDescription);return}
      self.error=error.localizedDescription;previous=nil;return
    }
    guard includeDiagnostics,current(),diagnosticRevision == diagnosticsRevision,!Task.isCancelled else {return}
    limits.rows=400;limits.resultSets=5;limits.totalBytes=4_000_000;limits.timeout=10
    do {
      let result=try await reader(ActivityMonitoring.diagnosticsSQL,limits)
      try Task.checkCancellation()
      guard currentContext(),diagnosticRevision == diagnosticsRevision else {discardChangedGeneration();return}
      guard canRead else {markOffline();return}
      diagnostics=try ActivityMonitoring.decodeDiagnostics(result)
      diagnosticsTime=samples.last?.time ?? Date();diagnosticsError=""
    } catch is CancellationError {discardChangedGeneration()}
    catch {
      guard currentContext(),diagnosticRevision == diagnosticsRevision else {discardChangedGeneration();return}
      if !canRead {markOffline(error.localizedDescription)}
      else {diagnosticsError=error.localizedDescription}
    }
  }
}

struct ActivityMonitorPanel:View {
  @StateObject private var model:ActivityMonitorModel
  let openTable:()->Void
  @State private var paused=false
  @State private var visible=false
  @State private var interval=10
  @State private var mode=0
  @State private var range=5
  @State private var diagnosticKind=0
  @State private var selectedRequest:String?
  @State private var selectedBlockingContext:String?
  @State private var selectedBlockingSession:Int64?
  init(server:ConnectedServer,openTable:@escaping ()->Void) {
    self.init(model:ActivityMonitorModel(server:server),openTable:openTable)
  }
  init(model:ActivityMonitorModel,initialMode:Int=0,initialDiagnosticKind:Int=0,initialSelectedRequest:String?=nil,initialSelectedBlockingContext:String?=nil,openTable:@escaping ()->Void) {
    _model=StateObject(wrappedValue:model);self.openTable=openTable
    _mode=State(initialValue:initialMode);_diagnosticKind=State(initialValue:initialDiagnosticKind)
    _selectedRequest=State(initialValue:initialSelectedRequest)
    _selectedBlockingContext=State(initialValue:initialSelectedBlockingContext)
  }
  private var latest:ActivityMonitoring.Sample? {model.samples.last}
  private var displayedSamples:[ActivityMonitoring.Sample] {ActivityChartPoint.window(model.samples,minutes:range)}
  private var diagnosticRows:[ActivityMonitoring.Request] {
    switch diagnosticKind {case 1:model.diagnostics.longRunning;case 2:model.diagnostics.backups;default:model.diagnostics.blocked}
  }
  private var selected:ActivityMonitoring.Request? {diagnosticRows.first {$0.id == selectedRequest}}
  private var notices:[String] {
    var values=model.error.isEmpty ? []:["Örnek alınamadı: "+model.error]
    values+=model.issues
    if mode == 2 {
      if !model.diagnosticsError.isEmpty {values.append("DBA verisi güncellenemedi; son örnek eski olabilir: "+model.diagnosticsError)}
      values+=model.diagnostics.issues
    }
    return values
  }
  var body:some View {
    VStack(alignment:.leading,spacing:mode == 2 ? 8:12) {
      HStack {
        StudioPanelHeading(title:"Activity Monitor",icon:"waveform.path.ecg",subtitle:model.server.profile.name+" · Sunucu sağlığı ve DBA")
        samplingStatus
      }
      controls
      healthCards
      healthStrip
      if !notices.isEmpty {issueBanner(notices.joined(separator:" · "),critical:!model.error.isEmpty || (mode == 2 && !model.diagnosticsError.isEmpty))}
      Group {
        switch mode {
        case 1: samplesTable
        case 2: diagnosticsPanel
        default: charts
        }
      }.frame(maxWidth:.infinity,maxHeight:.infinity)
      footer
    }.padding(18).studioPanel()
      .background(MonitorVisibilityProbe {visible=$0;model.setActivity(visible:$0,paused:paused)})
      .onChange(of:paused) {_,value in model.setActivity(visible:visible,paused:value)}
      .onChange(of:diagnosticKind) {_,_ in selectedRequest=nil}
      .onChange(of:selectedRequest) {_,_ in selectedBlockingContext=nil;selectedBlockingSession=nil}
      .onChange(of:mode) {_,value in if value != 2 {model.clearDiagnostics();selectedRequest=nil}}
      .onReceive(NotificationCenter.default.publisher(for:ConnectedServer.explorerConnectionChanged)) {notification in
        if notification.object as? ConnectedServer === model.server {model.connectionChanged()}
      }
      .onDisappear {model.setActivity(visible:false,paused:paused)}
      .task(id:"\(paused)|\(visible)|\(interval)|\(mode)") {
        guard visible,!paused else {return}
        repeat {
          // A mode/interval task may replace a cancelled request before its defer runs.
          // Wait for that actual work instead of delaying the new view a full refresh interval.
          while model.loading {
            do {try await Task.sleep(for:.milliseconds(25))} catch {return}
          }
          guard !Task.isCancelled else {return}
          await model.load(includeDiagnostics:mode == 2,automatic:true)
          do {try await Task.sleep(for:.seconds(interval))} catch {return}
        } while !Task.isCancelled
      }
  }
  private var controls:some View {
    HStack(spacing:10) {
      Picker("Görünüm",selection:$mode) {Text("Grafikler").tag(0);Text("Örnek tablosu").tag(1);Text("DBA").tag(2)}
        .pickerStyle(.segmented).labelsHidden().frame(width:340).studioHelp("Performans grafikleri, geçmiş örnekler veya DBA tanıları").accessibilityIdentifier("activityMode")
      Spacer(minLength:8)
      Picker("Aralık",selection:$range) {Text("Son 5 dakika").tag(5);Text("Son 15 dakika").tag(15)}
        .labelsHidden().frame(width:140).studioHelp("Grafik ve örnek tablosunun zaman aralığı").accessibilityLabel("Zaman aralığı")
      Picker("Yenileme",selection:$interval) {ForEach([5,10,30,60],id:\.self) {Text("\($0) sn").tag($0)}}
        .labelsHidden().frame(width:78).studioHelp("Otomatik yenileme sıklığı").accessibilityLabel("Yenileme sıklığı")
      StudioActionButton(paused ? "Sürdür":"Duraklat",icon:paused ? "play.fill":"pause.fill",tint:Color(nsColor:StudioTheme.warning)) {paused.toggle()}
        .accessibilityIdentifier("activityPause")
      StudioActionButton("Yenile",icon:"arrow.clockwise") {Task {await model.load(includeDiagnostics:mode == 2)}}
        .disabled(model.loading || !visible).accessibilityIdentifier("activityRefresh")
    }
  }
  private var samplingStatus:some View {
    HStack(spacing:6) {
      if model.loading {ProgressView().controlSize(.mini)}
      else {Circle().fill(Color(nsColor:!model.error.isEmpty ? StudioTheme.danger:paused || !model.issues.isEmpty ? StudioTheme.warning:latest == nil ? StudioTheme.muted:StudioTheme.success)).frame(width:6,height:6)}
      Text(paused ? "Duraklatıldı":model.loading ? "Örnekleniyor":!model.error.isEmpty ? "Veri eski":latest == nil ? "Örnek bekleniyor":!model.issues.isEmpty ? "Kısmi ölçüm":"Canlı izleme").font(.system(size:11,weight:.medium)).fixedSize()
    }.padding(.horizontal,10).padding(.vertical,6)
      .background(Color(nsColor:StudioTheme.canvas),in:Capsule())
      .overlay(Capsule().stroke(Color(nsColor:StudioTheme.border)))
      .studioHelp("Pencere gizli veya örtülüyken otomatik örnekleme durur.")
  }
  private var healthCards:some View {
    HStack(spacing:10) {
      ActivityHealthCard(title:"Aktif işlem",value:latest?.health.activeRequests,icon:"bolt.horizontal.circle.fill",color:StudioTheme.accent,detail:"Yedeklemeler hariç",help:"Kullanıcı istekleri; kendi izleme oturumu, yedekleme ve arka plan beklemeleri hariç.")
      ActivityHealthCard(title:"Bloklanan işlem",value:latest?.health.blockedRequests,icon:"lock.trianglebadge.exclamationmark",color:StudioTheme.danger,detail:"Başka oturumu bekliyor",help:"Pozitif blocking_session_id olan kullanıcı istekleri. DBA ayrıntılarını açmak için tıklayın.",action:{mode=2;diagnosticKind=0})
      ActivityHealthCard(title:"Yedekleme",value:latest?.health.backupRequests,icon:"externaldrive.badge.timemachine",color:StudioTheme.success,detail:"Devam eden işlemler",help:"BACKUP DATABASE / BACKUP LOG istekleri. İlerlemeyi görmek için tıklayın.",action:{mode=2;diagnosticKind=2})
      ActivityHealthCard(title:"Açık transaction",value:latest?.health.openTransactions,icon:"arrow.triangle.2.circlepath.circle.fill",color:StudioTheme.warning,detail:"Boşta: "+ActivityFormat.count(latest?.health.idleTransactions),help:"Kendi oturumu hariç tüm kullanıcı oturumlarının açık transaction sayısı; sleeping oturumları da içerir.")
    }.accessibilityIdentifier("activityHealthCards")
  }
  private var healthStrip:some View {
    HStack(spacing:14) {
      stripMetric("Oturum",ActivityFormat.count(latest?.health.userSessions),icon:"person.2",help:"Kendi izleme oturumu hariç kullanıcı oturumları")
      stripMetric("SQL bellek",ActivityFormat.memory(latest?.health.sqlMemoryMB),icon:"memorychip",help:"SQL Server işleminin fiziksel bellek kullanımı; MiB")
      stripMetric("Boş bellek",ActivityFormat.memory(latest?.health.availableMemoryMB),icon:"square.stack.3d.up",help:"Sunucu işletim sisteminin kullanılabilir fiziksel belleği; MiB")
      stripMetric("Okuma",ActivityFormat.number(latest?.readLatencyMS)+" ms",icon:"arrow.down.circle",help:"Ardışık örnekler arasındaki ortalama dosya okuma gecikmesi; kümülatif stall / okuma sayısı farkı")
      stripMetric("Yazma",ActivityFormat.number(latest?.writeLatencyMS)+" ms",icon:"arrow.up.circle",help:"Ardışık örnekler arasındaki ortalama dosya yazma gecikmesi; kümülatif stall / yazma sayısı farkı")
      Spacer(minLength:0)
    }.font(.system(size:11)).padding(.horizontal,12).padding(.vertical,9)
      .background(Color(nsColor:StudioTheme.canvas).opacity(0.65),in:RoundedRectangle(cornerRadius:9))
  }
  private func stripMetric(_ title:String,_ value:String,icon:String,help:String) -> some View {
    HStack(spacing:5) {Image(systemName:icon).foregroundStyle(Color(nsColor:StudioTheme.muted));Text(title).foregroundStyle(.secondary);Text(value).fontWeight(.medium).monospacedDigit()}
      .studioHelp(help).accessibilityElement(children:.combine)
  }
  private var charts:some View {
    ScrollView {
      LazyVGrid(columns:[GridItem(.adaptive(minimum:340),spacing:12)],spacing:12) {
        ActivityMetricChart(title:"SQL Server CPU",unit:"%",icon:"cpu",color:StudioTheme.accent,samples:displayedSamples,key:{$0.cpu},percent:true,help:"SQL Server işlem CPU zamanı farkı / mantıksal işlemci kapasitesi. İlk örnekte hız hesaplanmaz.")
        ActivityMetricChart(title:"Bekleyen görevler",unit:"görev",icon:"hourglass",color:StudioTheme.warning,samples:displayedSamples,key:{$0.waiting},help:"Kullanıcı oturumlarının bekleyen görevleri; tüm beklemeler bir performans sorunu değildir.")
        ActivityMetricChart(title:"Veritabanı I/O",unit:"MiB/sn",icon:"internaldrive",color:StudioTheme.success,samples:displayedSamples,key:{$0.megabytesPerSecond},help:"Tüm veritabanı dosyalarının okunan ve yazılan byte farkı / geçen süre.")
        ActivityMetricChart(title:"Batch istekleri",unit:"batch/sn",icon:"bolt.horizontal",color:StudioTheme.color(0x8A43B4,0xCB9BE8),samples:displayedSamples,key:{$0.batchesPerSecond},help:"SQL Statistics Batch Requests/sec kümülatif sayacından hesaplanan hız.")
        ActivityMetricChart(title:"Bloklanan işlemler",unit:"işlem",icon:"lock.shield",color:StudioTheme.danger,samples:displayedSamples,key:{$0.health.blockedRequests.map(Double.init)},help:"Başka bir kullanıcı oturumu tarafından bloklanan istekler; DBA sekmesinde ayrıntıları incelenir.")
        ActivityMetricChart(title:"Bellek bekleyen sorgular",unit:"istek",icon:"memorychip",color:StudioTheme.color(0x267B8C,0x78CAD8),samples:displayedSamples,key:{$0.health.memoryGrantsPending.map(Double.init)},help:"Henüz bellek tahsisi yapılmamış sorgular; sıfırdan yüksek değerler bellek baskısını incelemeyi gerektirebilir.")
      }.padding(1)
    }.accessibilityIdentifier("activityCharts")
  }
  private var samplesTable:some View {
    Table(Array(displayedSamples.reversed())) {
      TableColumn("Zaman") {Text($0.time.formatted(date:.omitted,time:.standard)).monospacedDigit()}.width(min:72,ideal:82,max:100)
      TableColumn("CPU %") {Text(ActivityFormat.number($0.cpu))}.width(min:50,ideal:60,max:80)
      TableColumn("Aktif") {Text(ActivityFormat.count($0.health.activeRequests))}.width(min:45,ideal:50,max:70)
      TableColumn("Blok") {Text(ActivityFormat.count($0.health.blockedRequests))}.width(min:45,ideal:50,max:70)
      TableColumn("Tx") {Text(ActivityFormat.count($0.health.openTransactions))}.width(min:45,ideal:50,max:70)
      TableColumn("Bekleyen") {Text(ActivityFormat.number($0.waiting))}.width(min:55,ideal:70,max:90)
      TableColumn("I/O MiB/sn") {Text(ActivityFormat.number($0.megabytesPerSecond))}.width(min:65,ideal:85,max:120)
      TableColumn("Batch/sn") {Text(ActivityFormat.number($0.batchesPerSecond))}.width(min:65,ideal:85,max:120)
      TableColumn("Okuma ms") {Text(ActivityFormat.number($0.readLatencyMS))}.width(min:65,ideal:85,max:120)
      TableColumn("Yazma ms") {Text(ActivityFormat.number($0.writeLatencyMS))}.width(min:65,ideal:85,max:120)
    }.accessibilityIdentifier("activitySamples")
  }
  private var diagnosticsPanel:some View {
    VStack(alignment:.leading,spacing:8) {
      HStack {
        Picker("Tanı",selection:$diagnosticKind) {
          Text("Bloklanan · \(model.diagnostics.blocked.count)").tag(0)
          Text("Uzun süren · \(model.diagnostics.longRunning.count)").tag(1)
          Text("Yedekleme · \(model.diagnostics.backups.count)").tag(2)
        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth:570)
          .studioHelp("Her grupta ilk 30 istek: bloklanan istekler, 30 saniyeyi aşan istekler veya devam eden yedeklemeler. Bloklayan zincirinde en çok 8 üst seviye / 60 oturum okunur.").accessibilityIdentifier("activityDiagnosticKind")
        Spacer(minLength:0)
        Text(model.diagnosticsTime.map {$0.formatted(date:.omitted,time:.standard)} ?? "Henüz okunmadı").font(.caption).foregroundStyle(.secondary)
      }
      if diagnosticRows.isEmpty {
        StudioEmptyState(title:model.diagnosticsTime == nil ? "DBA verisi bekleniyor":!model.diagnosticsError.isEmpty || !model.diagnostics.issues.isEmpty ? "Tanı verisi doğrulanamadı":"Bu grupta istek yok",icon:diagnosticKind == 2 ? "externaldrive.badge.checkmark":"checkmark.shield",detail:model.diagnosticsTime == nil ? "DBA görünümü açıkken sınırlı, salt okunur örnek alınır.":"Yetki ve filtre kapsamı yukarıdaki uyarılarla birlikte değerlendirilmelidir.")
      } else {
        Table(diagnosticRows,selection:$selectedRequest) {
          TableColumn("Oturum") {Text(String($0.sessionID)).monospacedDigit()}.width(min:50,ideal:58,max:75)
          TableColumn("Veritabanı") {Text($0.database).lineLimit(1)}.width(min:80,ideal:110,max:160)
          TableColumn("Komut") {Text($0.command).lineLimit(1)}.width(min:100,ideal:145,max:210)
          TableColumn("Süre") {Text(ActivityFormat.duration($0.elapsedMS))}.width(min:65,ideal:75,max:95)
          TableColumn("CPU") {Text(ActivityFormat.duration($0.cpuMS))}.width(min:60,ideal:70,max:90)
          TableColumn("Bloklayan") {Text($0.blocker.map(String.init) ?? "—")}.width(min:60,ideal:70,max:85)
          TableColumn(diagnosticKind == 2 ? "İlerleme":"Bekleme") {request in
            if diagnosticKind == 2 {Text(ActivityFormat.number(request.percentComplete)+" %").monospacedDigit()}
            else {Text(request.wait.isEmpty ? "—":request.wait).lineLimit(1).studioHelp(request.wait)}
          }
        }.frame(minHeight:120).accessibilityIdentifier("activityRequests")
        requestDetail
      }
    }.accessibilityIdentifier("activityDBA")
  }
  @ViewBuilder private var requestDetail:some View {
    if let selected,diagnosticKind == 0 {
      blockingDetail(selected)
    } else if let selected {
      VStack(alignment:.leading,spacing:6) {
        HStack(spacing:14) {
          Label("Oturum \(selected.sessionID) · \(selected.status)",systemImage:"text.alignleft").fontWeight(.medium)
          Text("Fiziksel okuma \(ActivityFormat.count(selected.reads)) · Yazma \(ActivityFormat.count(selected.writes)) · Tx \(ActivityFormat.count(selected.openTransactions))").foregroundStyle(.secondary)
          Spacer(minLength:0)
          StudioActionButton("SQL’i Kopyala",icon:"doc.on.doc") {NSPasteboard.general.clearContents();NSPasteboard.general.setString(String(selected.sql.prefix(2000)),forType:.string)}
            .disabled(selected.sql.isEmpty).accessibilityIdentifier("activityCopySQL")
        }.font(.system(size:11))
        if let percent=selected.percentComplete {
          HStack {ProgressView(value:min(100,max(0,percent)),total:100);Text(ActivityFormat.number(percent)+" %").monospacedDigit()}
            .studioHelp("SQL Server’ın bildirdiği tahmini ilerleme; bitiş zamanı garantisi değildir.")
        }
        Text("SQL · İlk 2.000 karakter").font(.system(size:10)).foregroundStyle(.secondary)
        SQLReadOnlyPreview(sql:selected.sql.isEmpty ? "-- SQL metni sağlanmadı veya görüntüleme yetkisi yok.":String(selected.sql.prefix(2000)))
          .frame(minHeight:100,idealHeight:140,maxHeight:190).accessibilityIdentifier("activityRequestSQL")
      }.studioCard(padding:12)
    } else {
      Label("SQL metnini ve işlem ayrıntılarını görmek için bir satır seçin.",systemImage:"cursorarrow.click")
        .font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(12)
        .background(Color(nsColor:StudioTheme.canvas),in:RoundedRectangle(cornerRadius:8))
    }
  }
  private func blockingDetail(_ request:ActivityMonitoring.Request) -> some View {
    let chain=model.diagnostics.blockingChain(for:request)
    let contexts=model.diagnostics.blockingContexts.filter {chain.sessionIDs.contains($0.sessionID) && $0.sessionID != request.sessionID}
    let chosen=contexts.first {$0.id == selectedBlockingContext}
    let session=chosen?.sessionID ?? selectedBlockingSession ?? request.blocker
    let choices=contexts.filter {$0.sessionID == session}
    // With MARS, require a request choice rather than presenting arbitrary SQL.
    let context=chosen ?? (choices.count == 1 ? choices.first:nil)
    return VStack(alignment:.leading,spacing:6) {
      HStack(spacing:6) {
        Label("Bloklanma zinciri",systemImage:"point.3.connected.trianglepath.dotted").font(.system(size:11,weight:.semibold))
        Text("Üst oturum → bekleyen · anlık örnek").font(.system(size:10)).foregroundStyle(.secondary)
        Spacer(minLength:0)
      }.studioHelp("DMV’ler farklı anlarda okunabilir. Zincir anlık bağlamdır; görünen SQL’in kilidi alan ifade olduğunu kanıtlamaz.")
      ScrollView(.horizontal) {
        HStack(spacing:6) {
          ForEach(Array(chain.sessionIDs.enumerated()),id:\.offset) {index,id in
            if index>0 {Image(systemName:"arrow.right").font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary).studioHelp("Soldaki oturum sağdaki oturumu blokluyor")}
            let leaf=id == request.sessionID
            let node=contexts.first {$0.sessionID == id}
            Button {
              if !leaf {selectedBlockingSession=id;selectedBlockingContext=nil}
            } label: {
              HStack(spacing:6) {
                Image(systemName:leaf ? "hourglass":index == 0 && chain.termination == .root ? "lock.fill":"link")
                VStack(alignment:.leading,spacing:2) {
                  Text("Oturum \(id)").font(.system(size:11,weight:.semibold))
                  Text(leaf ? "Bloklanan istek":node == nil ? "Ayrıntı okunamadı":index == 0 && chain.termination == .root ? "Üst bloklayan · \(node!.status)":"Ara oturum · \(node!.status)")
                    .font(.system(size:9)).lineLimit(1)
                }
              }.foregroundStyle(Color(nsColor:leaf ? StudioTheme.muted:StudioTheme.danger))
                .padding(.horizontal,9).padding(.vertical,6)
                .background(Color(nsColor:session == id ? StudioTheme.danger:StudioTheme.muted).opacity(session == id ? 0.12:0.06),in:RoundedRectangle(cornerRadius:7))
                .overlay(RoundedRectangle(cornerRadius:7).stroke(Color(nsColor:session == id ? StudioTheme.danger:StudioTheme.border).opacity(0.5)))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(leaf || node == nil)
              .studioHelp(leaf ? "Seçili bloklanan sorgu solda gösterilir":"Bu oturumun sorgu ve bağlantı ayrıntılarını göster")
              .accessibilityIdentifier("activityChainSession\(id)")
          }
        }.padding(1)
      }.fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("activityBlockingChain")
      if let notice=chain.notice {Text(notice).font(.system(size:10)).foregroundStyle(Color(nsColor:StudioTheme.warning)).lineLimit(2).studioHelp(notice)}
      HStack(alignment:.top,spacing:10) {
        blockingSQLPane(title:"Bekleyen · Oturum \(request.sessionID)",subtitle:"\(request.database) · \(request.wait) · Tx \(ActivityFormat.count(request.openTransactions))",sql:request.sql,help:"Bloklanan isteğin o anda çalıştırdığı ifade; ilk 2.000 karakter.")
        VStack(alignment:.leading,spacing:5) {
          HStack(spacing:5) {
            Text(session.map {"Bloklayan · Oturum \($0)"} ?? "Bloklayan oturum").font(.system(size:11,weight:.semibold))
            Spacer(minLength:0)
            if choices.count>1 {
              Menu {
                ForEach(choices) {choice in
                  Button("İstek \(choice.requestID.map(String.init) ?? "—") · \(choice.command) · \(choice.wait.isEmpty ? choice.status:choice.wait)") {selectedBlockingContext=choice.id}
                }
              } label: {Label(context?.requestID.map {"İstek \($0)"} ?? "İstek seçin",systemImage:"list.bullet")}
                .font(.system(size:10)).studioHelp("Aynı oturumdaki etkin istekler; SQL metnini açıkça seçin")
                .accessibilityIdentifier("activityBlockingRequestChoice")
            }
            copySQLButton(context?.sql ?? "")
          }
          Text(context.map {"\($0.login) · \($0.host) · \($0.program) · Tx \(ActivityFormat.count($0.openTransactions))"} ?? (choices.count>1 ? "Birden fazla etkin istek var; sorguyu seçin.":"Oturum ayrıntısı okunamadı veya sonlandı."))
            .font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
            .studioHelp(context.map {"\($0.database) · \($0.status)\n\($0.login) · \($0.host) · \($0.program)\nBekleme: \($0.wait) · \(ActivityFormat.duration($0.waitMS))\nKaynak: \($0.waitResource)"} ?? "")
          Text(context?.sqlSource == .recent ? "Bağlantının son batch’i · kilidi alan ifade olduğu kesin değil":context?.sqlSource == .current ? "O anda çalışan ifade · ilk 2.000 karakter":"SQL bağlamı okunamadı")
            .font(.system(size:9)).foregroundStyle(context?.sqlSource == .recent ? Color(nsColor:StudioTheme.warning):.secondary)
            .lineLimit(1).studioHelp("Açık transaction içindeki önceki bir ifade kilidi tutuyor olabilir. SQL metni salt okunur bağlamdır.")
          SQLReadOnlyPreview(sql:context?.sql.isEmpty == false ? context!.sql:"-- Gösterilecek SQL yok; oturum/istek bağlamını kontrol edin.")
            .frame(minHeight:100,idealHeight:115,maxHeight:150).accessibilityIdentifier("activityBlockerSQL")
        }.frame(maxWidth:.infinity,alignment:.leading)
      }
    }.studioCard(padding:10)
  }
  private func blockingSQLPane(title:String,subtitle:String,sql:String,help:String) -> some View {
    VStack(alignment:.leading,spacing:5) {
      HStack {Text(title).font(.system(size:11,weight:.semibold));Spacer(minLength:0);copySQLButton(sql)}
      Text(subtitle).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).studioHelp(subtitle)
      Text("O anda çalışan ifade · ilk 2.000 karakter").font(.system(size:9)).foregroundStyle(.secondary)
      SQLReadOnlyPreview(sql:sql.isEmpty ? "-- SQL metni sağlanmadı veya görüntüleme yetkisi yok.":sql)
        .frame(minHeight:100,idealHeight:115,maxHeight:150).accessibilityIdentifier("activityBlockedSQL")
    }.frame(maxWidth:.infinity,alignment:.leading).studioHelp(help)
  }
  private func copySQLButton(_ sql:String) -> some View {
    Button {NSPasteboard.general.clearContents();NSPasteboard.general.setString(sql,forType:.string)} label: {Image(systemName:"doc.on.doc")}
      .buttonStyle(.borderless).disabled(sql.isEmpty).studioHelp("SQL’i kopyala").accessibilityLabel("SQL’i kopyala")
  }
  private var footer:some View {
    VStack(alignment:.leading,spacing:7) {
      HStack {
        StudioActionButton("Sorguda Tablo Olarak İzle",icon:"tablecells") {openTable()}.accessibilityIdentifier("activityOpenQuery")
        Spacer(minLength:10)
        Text(latest.map {"Son örnek "+$0.time.formatted(date:.omitted,time:.standard)} ?? "Örnek bekleniyor…").font(.caption).foregroundStyle(.secondary)
        Text("\(model.samples.count) örnek").font(.caption).foregroundStyle(.secondary)
          .studioHelp("Son 15 dakika, en çok 181 örnek. Eksik ölçüm — ile gösterilir; ilk örnekte ve kesinti sonrası hızlar hesaplanmaz.")
      }
    }
  }
  private func issueBanner(_ text:String,critical:Bool=true) -> some View {
    let color=Color(nsColor:critical ? StudioTheme.danger:StudioTheme.warning)
    return Label(text,systemImage:"exclamationmark.triangle.fill").font(.system(size:11)).foregroundStyle(color)
      .lineLimit(2).studioHelp(text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
      .padding(9).background(color.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
  }
}

private struct ActivityHealthCard:View {
  let title:String
  let value:Int64?
  let icon:String
  let color:NSColor
  let detail:String
  let help:String
  var action:(()->Void)?=nil
  var body:some View {
    Group {
      if let action {Button(action:action) {cardContent}.buttonStyle(.plain).accessibilityLabel(title+" ayrıntılarını aç")}
      else {cardContent}
    }.studioHelp(help)
  }
  private var cardContent:some View {
    VStack(alignment:.leading,spacing:7) {
      HStack(spacing:7) {Image(systemName:icon).foregroundStyle(Color(nsColor:color));Text(title).font(.system(size:11,weight:.medium));Spacer(minLength:0)}
      HStack(alignment:.firstTextBaseline) {
        Text(ActivityFormat.count(value)).font(.system(size:26,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(Color(nsColor:value == nil ? StudioTheme.muted:color))
        Spacer(minLength:0)
        Text(value == nil ? "Veri alınamadı":detail).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
      }
    }.frame(maxWidth:.infinity,alignment:.leading).studioCard(padding:12).contentShape(Rectangle())
      .accessibilityElement(children:.combine).accessibilityValue(ActivityFormat.count(value))
  }
}

private struct ActivityMetricChart:View {
  let title:String
  let unit:String
  let icon:String
  let color:NSColor
  let samples:[ActivityMonitoring.Sample]
  let key:(ActivityMonitoring.Sample)->Double?
  var percent=false
  let help:String
  @State private var hoveredTime:Date?
  private var points:[ActivityChartPoint] {ActivityChartPoint.points(samples,value:key)}
  private var hovered:ActivityChartPoint? {hoveredTime.flatMap {ActivityChartPoint.nearest(points,to:$0)}}
  private var last:Double? {samples.last.flatMap(key)}
  private var peak:Double? {points.map(\.value).max()}
  var body:some View {
    VStack(alignment:.leading,spacing:7) {
      HStack {
        Label(title,systemImage:icon).font(.system(size:12,weight:.semibold)).studioHelp(help)
        Spacer(minLength:0)
        Text(unit).font(.system(size:10)).foregroundStyle(.secondary)
      }
      HStack(alignment:.firstTextBaseline) {
        Text(ActivityFormat.number(hovered?.value ?? last)).font(.system(size:24,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(Color(nsColor:color))
        Text(hovered.map {$0.time.formatted(date:.omitted,time:.standard)} ?? "Son değer").font(.system(size:10)).foregroundStyle(.secondary)
        Spacer(minLength:0)
        Text("Tepe "+ActivityFormat.number(peak)).font(.system(size:10)).foregroundStyle(.secondary).monospacedDigit()
      }
      chart.frame(height:112)
      Text(points.isEmpty ? "Ölçüm bekleniyor veya erişilemiyor":"Grafik üzerinde gezinerek örneği inceleyin")
        .font(.system(size:9)).foregroundStyle(.secondary)
    }.studioCard(padding:12).accessibilityElement(children:.contain)
      .accessibilityLabel(title).accessibilityValue(ActivityFormat.number(last)+" "+unit)
  }
  private var chart:some View {
    Chart {
      ForEach(points) {point in
        AreaMark(x:.value("Zaman",point.time),yStart:.value("Taban",0),yEnd:.value(title,point.value),series:.value("Aralık",point.segment))
          .foregroundStyle(LinearGradient(colors:[Color(nsColor:color).opacity(0.2),Color(nsColor:color).opacity(0.015)],startPoint:.top,endPoint:.bottom))
        LineMark(x:.value("Zaman",point.time),y:.value(title,point.value),series:.value("Aralık",point.segment))
          .foregroundStyle(Color(nsColor:color)).lineStyle(StrokeStyle(lineWidth:2))
      }
      if let hovered {
        RuleMark(x:.value("Seçili zaman",hovered.time)).foregroundStyle(Color(nsColor:StudioTheme.muted).opacity(0.5)).lineStyle(StrokeStyle(lineWidth:1,dash:[3,3]))
        PointMark(x:.value("Zaman",hovered.time),y:.value(title,hovered.value)).foregroundStyle(Color(nsColor:color)).symbolSize(35)
      }
    }.chartLegend(.hidden)
      .chartYScale(domain:0...(percent ? 100:max(1,(peak ?? 1)*1.15)))
      .chartXAxis {AxisMarks(values:.automatic(desiredCount:3)) {value in AxisGridLine().foregroundStyle(Color(nsColor:StudioTheme.border));AxisValueLabel(format:.dateTime.hour().minute().second())}}
      .chartYAxis {AxisMarks(position:.leading,values:.automatic(desiredCount:3)) {value in AxisGridLine().foregroundStyle(Color(nsColor:StudioTheme.border));AxisValueLabel()}}
      .chartOverlay {proxy in
        GeometryReader {geometry in
          Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover {phase in
            switch phase {
            case .active(let location):
              guard let plot=proxy.plotFrame else {hoveredTime=nil;return}
              let frame=geometry[plot]
              guard frame.contains(location) else {hoveredTime=nil;return}
              hoveredTime=proxy.value(atX:location.x-frame.minX,as:Date.self)
            case .ended:hoveredTime=nil
            }
          }
        }
      }
  }
}

enum ActivityFormat {
  static func number(_ value:Double?) -> String {value.flatMap {$0.isFinite ? $0:nil}.map {$0.formatted(.number.precision(.fractionLength(0...2)))} ?? "—"}
  static func count(_ value:Int64?) -> String {value.map {$0.formatted()} ?? "—"}
  static func memory(_ value:Double?) -> String {
    guard let value,value.isFinite,value>=0 else {return "—"}
    return value>=1024 ? number(value/1024)+" GiB":number(value)+" MiB"
  }
  static func duration(_ value:Int64?) -> String {
    guard let value,value>=0 else {return "—"}
    if value<1000 {return "\(value) ms"}
    if value<60_000 {return number(Double(value)/1000)+" sn"}
    return "\(value/60_000) dk \((value%60_000)/1000) sn"
  }
}

struct ActivityChartPoint:Identifiable {
  let id:Int
  let time:Date
  let value:Double
  let segment:Int
  static func window(_ samples:[ActivityMonitoring.Sample],minutes:Int) -> [ActivityMonitoring.Sample] {
    guard let last=samples.last else {return []}
    return samples.filter {$0.time>=last.time.addingTimeInterval(-Double(minutes)*60)}
  }
  static func nearest(_ points:[Self],to time:Date) -> Self? {points.min {abs($0.time.timeIntervalSince(time))<abs($1.time.timeIntervalSince(time))}}
  static func points(_ samples:[ActivityMonitoring.Sample],value:(ActivityMonitoring.Sample)->Double?) -> [Self] {
    var segment=0,points:[Self]=[]
    var lastTime:Date?
    for (index,sample) in samples.enumerated() {
      guard let v=value(sample),v.isFinite else {segment+=1;lastTime=nil;continue}
      if sample.beginsSequence {segment+=1}
      if let lastTime,sample.time.timeIntervalSince(lastTime)>180 {segment+=1}
      points.append(.init(id:index,time:sample.time,value:v,segment:segment));lastTime=sample.time
    }
    return points
  }
}

struct MonitorVisibilityProbe:NSViewRepresentable {
  let changed:(Bool)->Void
  func makeNSView(context:Context) -> Probe {let view=Probe();view.changed=changed;return view}
  func updateNSView(_ view:Probe,context:Context) {view.changed=changed}
  final class Probe:NSView {
    var changed:((Bool)->Void)?
    private var observers:[NSObjectProtocol]=[]
    override func viewWillMove(toWindow newWindow:NSWindow?) {
      for observer in observers {NotificationCenter.default.removeObserver(observer)};observers=[]
      if let newWindow {
        for name in [NSWindow.didChangeOcclusionStateNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification,NSWindow.willCloseNotification] {
          observers.append(NotificationCenter.default.addObserver(forName:name,object:newWindow,queue:.main) { [weak self] note in
            let closing=note.name == NSWindow.willCloseNotification
            MainActor.assumeIsolated {
              guard let self else {return}
              self.changed?(!closing && self.window?.isVisible == true && self.window?.isMiniaturized == false && self.window?.occlusionState.contains(.visible) == true)
            }
          })
        }
      }
      super.viewWillMove(toWindow:newWindow)
    }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      Task { @MainActor [weak self] in guard let self else {return};changed?(window?.isVisible == true && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true) }
    }
  }
}
