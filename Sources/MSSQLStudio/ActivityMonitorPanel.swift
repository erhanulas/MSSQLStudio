import AppKit
import SwiftUI
import Charts
import SQLServerKit

@MainActor final class ActivityMonitorModel: ObservableObject {
  @Published private(set) var samples:[ActivityMonitoring.Sample]=[]
  @Published private(set) var issues:[String]=[]
  @Published private(set) var error=""
  @Published private(set) var loading=false
  private var previous:ActivityMonitoring.Snapshot?
  let server:ConnectedServer
  init(server:ConnectedServer) {self.server=server}
  func breakSequence() {previous=nil}
  func load() async {
    guard !loading else {return}
    loading=true;defer {loading=false}
    var limits=Limits();limits.rows=20;limits.resultSets=2;limits.totalBytes=1_000_000;limits.timeout=10
    do {
      let result=try await server.catalog(ActivityMonitoring.overviewSQL,database:"master",limits:limits)
      try Task.checkCancellation()
      let snapshot=try ActivityMonitoring.decode(result)
      if let last=samples.last,snapshot.time<=last.time {return}
      samples.append(ActivityMonitoring.sample(snapshot,previous:previous));previous=snapshot
      samples=Array(samples.filter {$0.time>=snapshot.time.addingTimeInterval(-900)}.suffix(120))
      issues=snapshot.issues;error=""
    } catch is CancellationError {previous=nil}
    catch {self.error=error.localizedDescription;previous=nil}
  }
}

struct ActivityMonitorPanel:View {
  @StateObject private var model:ActivityMonitorModel
  let openTable:()->Void
  @State private var paused=false
  @State private var visible=true
  @State private var interval=10
  @State private var mode=0
  init(server:ConnectedServer,openTable:@escaping ()->Void) {
    _model=StateObject(wrappedValue:ActivityMonitorModel(server:server));self.openTable=openTable
  }
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      StudioPanelHeading(title:"Activity Monitor",icon:"waveform.path.ecg",subtitle:model.server.profile.name+" · Sunucu performansı")
      HStack {
        Picker("Görünüm",selection:$mode) {Text("Grafikler").tag(0);Text("Örnek tablosu").tag(1)}.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Görünüm").frame(width:230)
        Spacer()
        Picker("Yenileme",selection:$interval) {ForEach([5,10,30,60],id:\.self) {Text("\($0) sn").tag($0)}}.frame(width:150)
        StudioActionButton(paused ? "Sürdür":"Duraklat",icon:paused ? "play.fill":"pause.fill") {paused.toggle()}.accessibilityIdentifier("activityPause")
        StudioActionButton("Yenile",icon:"arrow.clockwise") {Task {await model.load()}}.disabled(model.loading)
      }
      if !model.error.isEmpty {Label("Örnek alınamadı: "+model.error,systemImage:"exclamationmark.triangle").foregroundStyle(Color(nsColor:StudioTheme.danger)).textSelection(.enabled)}
      if mode == 0 {
        ScrollView {
          LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:16) {
            metric("SQL Server CPU",unit:"%",icon:"cpu",color:StudioTheme.accent,key:{$0.cpu},percent:true)
            metric("Bekleyen kullanıcı görevleri",unit:"görev",icon:"hourglass",color:StudioTheme.warning,key:{$0.waiting})
            metric("Veritabanı I/O",unit:"MB/sn",icon:"internaldrive",color:StudioTheme.success,key:{$0.megabytesPerSecond})
            metric("Batch istekleri",unit:"batch/sn",icon:"bolt.horizontal",color:StudioTheme.color(0x8A43B4,0xCB9BE8),key:{$0.batchesPerSecond})
          }.padding(1)
        }.accessibilityIdentifier("activityCharts")
      } else {
        Table(model.samples.reversed()) {
          TableColumn("Zaman") {Text($0.time.formatted(date:.omitted,time:.standard))}
          TableColumn("SQL CPU %") {Text(value($0.cpu))}
          TableColumn("Bekleyen görevler") {Text(value($0.waiting))}
          TableColumn("I/O MB/sn") {Text(value($0.megabytesPerSecond))}
          TableColumn("Batch/sn") {Text(value($0.batchesPerSecond))}
        }.accessibilityIdentifier("activitySamples")
      }
      if !model.issues.isEmpty {Text(model.issues.joined(separator:"\n")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
      Text("Hızlar ardışık örneklerin farkından hesaplanır; ilk örnekte ve sayaç sıfırlandığında — gösterilir. CPU sunucunun son scheduler örneğidir. Son 15 dakika / en çok 120 örnek bu pencerede tutulur.").font(.caption).foregroundStyle(.secondary)
      HStack {
        StudioActionButton("Sorguda Tablo Olarak İzle",icon:"tablecells") {openTable()}.accessibilityIdentifier("activityOpenQuery")
        Spacer()
        if model.loading {ProgressView().controlSize(.small)}
        Text(paused ? "Duraklatıldı":model.samples.last.map {"Son örnek: "+$0.time.formatted(date:.omitted,time:.standard)} ?? "Örnek bekleniyor…").font(.caption).foregroundStyle(.secondary)
      }
    }.padding(20).studioPanel()
      .background(MonitorVisibilityProbe {visible=$0})
      .task(id:"\(paused)|\(visible)|\(interval)") {
        model.breakSequence()
        guard visible,!paused else {return}
        repeat {
          await model.load()
          do {try await Task.sleep(for:.seconds(interval))} catch {return}
        } while !Task.isCancelled
      }
  }
  private func value(_ value:Double?) -> String {value.map {$0.formatted(.number.precision(.fractionLength(0...2)))} ?? "—"}
  private func metric(_ title:String,unit:String,icon:String,color:NSColor,key:(ActivityMonitoring.Sample)->Double?,percent:Bool=false) -> some View {
    let points=ActivityChartPoint.points(model.samples,value:key)
    return VStack(alignment:.leading,spacing:10) {
      HStack {Label(title,systemImage:icon).font(.system(size:12,weight:.semibold));Spacer();Text(unit).font(.caption).foregroundStyle(.secondary)}
      Text(value(model.samples.last.flatMap(key))).font(.system(size:25,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(Color(nsColor:color))
      Chart(points) {point in
        LineMark(x:.value("Zaman",point.time),y:.value(title,point.value),series:.value("Aralık",point.segment))
          .foregroundStyle(Color(nsColor:color)).lineStyle(StrokeStyle(lineWidth:2))
        PointMark(x:.value("Zaman",point.time),y:.value(title,point.value)).foregroundStyle(Color(nsColor:color)).symbolSize(10)
      }.chartYScale(domain:0...(percent ? 100:max(1,(points.map(\.value).max() ?? 1)*1.15)))
        .chartLegend(.hidden).chartXAxis {AxisMarks(values:.automatic(desiredCount:3))}.frame(height:140)
        .accessibilityLabel(title).accessibilityValue(value(model.samples.last.flatMap(key))+" "+unit)
    }.studioCard().frame(maxWidth:.infinity)
  }
}

struct ActivityChartPoint:Identifiable {
  let id:Int
  let time:Date
  let value:Double
  let segment:Int
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

private struct MonitorVisibilityProbe:NSViewRepresentable {
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
