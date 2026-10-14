import AppKit
import SwiftUI
import SQLServerKit

@MainActor final class DatabaseFilesModel:ObservableObject {
  typealias Reader=@MainActor (String,String,Limits) async throws -> Execution
  let server:ConnectedServer
  private let reader:Reader
  @Published private(set) var files:[DatabaseFilesMonitoring.File]=[]
  @Published private(set) var details:[String:DatabaseFilesMonitoring.File]=[:]
  @Published private(set) var issues:[String]=[]
  @Published private(set) var error=""
  @Published private(set) var detailError=""
  @Published private(set) var loading=false
  @Published private(set) var loadingDetails=false
  @Published private(set) var sampledAt:Date?
  @Published private(set) var selectedID:String?
  @Published var databaseFilter=""
  @Published var search=""
  private(set) var visible=true
  private var revision=UUID(),detailRevision=UUID()
  private var dataGeneration:UUID?
  private var cache:[String:[String:DatabaseFilesMonitoring.File]]=[:]
  var databases:[String] {Array(Set(files.compactMap(\.database))).sorted {$0.localizedStandardCompare($1) == .orderedAscending}}
  var filtered:[DatabaseFilesMonitoring.File] {
    let query=search.trimmingCharacters(in:.whitespacesAndNewlines)
    return files.filter {file in
      (databaseFilter.isEmpty || file.database == databaseFilter) &&
      (query.isEmpty || [file.name,file.database ?? "",file.path ?? ""].contains {$0.localizedCaseInsensitiveContains(query)})
    }
  }
  var selected:DatabaseFilesMonitoring.File? {files.first {$0.id == selectedID}.map {details[$0.id] ?? $0}}
  private var canRead:Bool {server.online || server.catalogFixture != nil || server.asyncCatalogFixture != nil}
  init(server:ConnectedServer,database:String="",reader:Reader?=nil) {
    self.server=server;databaseFilter=database
    self.reader=reader ?? {sql,database,limits in try await server.catalog(sql,database:database,limits:limits)}
  }
  func select(_ id:String?) {
    connectionChanged()
    guard id == nil || files.contains(where:{$0.id == id}) else {return}
    guard selectedID != id else {return}
    selectedID=id;detailRevision=UUID();details=[:];detailError=""
  }
  func filterChanged() {
    if !filtered.contains(where:{$0.id == selectedID}) {select(filtered.first?.id)}
  }
  func setVisible(_ value:Bool) {guard visible != value else {return};visible=value;revision=UUID();detailRevision=UUID()}
  func connectionChanged() {
    if let dataGeneration,dataGeneration != server.generation {
      files=[];details=[:];cache=[:];issues=[];sampledAt=nil;selectedID=nil;error="";detailError=""
      revision=UUID();detailRevision=UUID()
    }
    dataGeneration=server.generation
    if !canRead {
      error="Bağlantı çevrimdışı. Son liste güncel değil; Explorer’dan yeniden bağlanın."
      details=[:];cache=[:];detailError="";detailRevision=UUID()
    }
  }
  func refresh() async {
    guard visible,!loading else {return}
    connectionChanged();guard canRead else {return}
    let token=revision,generation=server.generation
    loading=true;defer {loading=false}
    var limits=Limits();limits.rows=5002;limits.resultSets=2;limits.totalBytes=4_000_000;limits.timeout=10
    do {
      let execution=try await reader(DatabaseFilesMonitoring.inventorySQL,"master",limits)
      try Task.checkCancellation()
      guard visible,token == revision,generation == server.generation else {connectionChanged();return}
      guard canRead else {connectionChanged();return}
      let inventory=try DatabaseFilesMonitoring.decodeInventory(execution)
      files=inventory.files;issues=inventory.issues+(inventory.limited ? ["İlk 5.000 dosya gösteriliyor; sunucuda daha fazla dosya var."]:[])
      cache=[:];details=[:];detailError="";detailRevision=UUID();sampledAt=Date();error=""
      filterChanged()
      await loadSelection()
    } catch is CancellationError {connectionChanged()}
    catch {
      guard visible,token == revision,generation == server.generation else {connectionChanged();return}
      if canRead {self.error=error.localizedDescription} else {connectionChanged()}
    }
  }
  func loadSelection() async {
    connectionChanged()
    // Rapid row changes replace SwiftUI's task. Let the cancelled read finish its bounded cleanup.
    while loadingDetails {
      do {try await Task.sleep(for:.milliseconds(25))} catch {return}
    }
    connectionChanged()
    guard visible,canRead,!Task.isCancelled,let file=selected,let database=file.database else {return}
    if let known=cache[database] {details=known;detailError="";return}
    let token=detailRevision,generation=server.generation,id=file.id
    loadingDetails=true;defer {loadingDetails=false}
    var limits=Limits();limits.rows=5001;limits.resultSets=1;limits.totalBytes=4_000_000;limits.timeout=10
    do {
      let execution=try await reader(DatabaseFilesMonitoring.detailSQL(database:database),database,limits)
      try Task.checkCancellation()
      guard visible,token == detailRevision,generation == server.generation,selectedID == id else {connectionChanged();return}
      guard canRead else {connectionChanged();return}
      let snapshot=try DatabaseFilesMonitoring.decodeDetails(execution,database:database)
      guard snapshot.files.contains(where:{$0.id == id}) else {throw SQLFailure("Seçili dosya artık bu veritabanında yok; dosya listesini yenileyin.")}
      details=Dictionary(uniqueKeysWithValues:snapshot.files.map {($0.id,$0)})
      if cache.count>=8 {cache=[:]}
      cache[database]=details
      detailError=snapshot.limited ? "Ayrıntıda ilk 5.000 dosya gösteriliyor.":""
    } catch is CancellationError {connectionChanged()}
    catch {
      guard visible,token == detailRevision,generation == server.generation,selectedID == id else {connectionChanged();return}
      if canRead {detailError=error.localizedDescription;details=[:]} else {connectionChanged()}
    }
  }
}

struct DatabaseFilesPanel:View {
  @StateObject private var model:DatabaseFilesModel
  let openQuery:()->Void
  @State private var visible=false
  init(server:ConnectedServer,database:String="",openQuery:@escaping ()->Void) {
    self.init(model:DatabaseFilesModel(server:server,database:database),openQuery:openQuery)
  }
  init(model:DatabaseFilesModel,openQuery:@escaping ()->Void) {_model=StateObject(wrappedValue:model);self.openQuery=openQuery}
  private var notices:[String] {model.issues+([model.error,model.detailError].filter {!$0.isEmpty})}
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack {
        StudioPanelHeading(title:"Database Files",icon:"internaldrive",subtitle:model.server.profile.name+" · Dosya envanteri ve alan kullanımı").lineLimit(1)
        Spacer(minLength:8)
        if model.loading || model.loadingDetails {ProgressView().controlSize(.small)}
        StudioActionButton("Sorguda Aç",icon:"curlybraces") {openQuery()}.studioHelp("Dosya envanterinin salt okunur SQL sorgusunu yeni sekmede aç")
        StudioActionButton("Yenile",icon:"arrow.clockwise") {Task {await model.refresh()}}
          .disabled(model.loading || !visible).studioHelp("Dosya envanterini ve seçili veritabanının alan kullanımını yenile").accessibilityIdentifier("filesRefresh")
      }
      HStack(spacing:12) {
        StudioSearchablePicker(title:"Veritabanı",values:[""]+model.databases,emptyTitle:"Tüm veritabanları",selection:$model.databaseFilter).frame(width:245).studioHelp("Dosya listesini veritabanına göre daralt").accessibilityIdentifier("filesDatabase")
        TextField("Dosya, veritabanı veya yol ara",text:$model.search).textFieldStyle(.roundedBorder)
          .studioHelp("Görünür dosyaları ad, veritabanı ve fiziksel yola göre ara").accessibilityIdentifier("filesSearch")
        Text("\(model.filtered.count) dosya").foregroundStyle(.secondary).monospacedDigit().fixedSize()
      }
      summary
      if !notices.isEmpty {
        Label(notices.joined(separator:" · "),systemImage:"exclamationmark.triangle.fill")
          .font(.system(size:11)).foregroundStyle(Color(nsColor:model.error.isEmpty ? StudioTheme.warning:StudioTheme.danger))
          .lineLimit(2).studioHelp(notices.joined(separator:"\n")).textSelection(.enabled)
      }
      Table(model.filtered,selection:Binding(get:{model.selectedID},set:{model.select($0)})) {
        TableColumn("Veritabanı") {Text($0.database ?? "Kimlik \($0.databaseID)").lineLimit(1)}.width(min:100,ideal:135,max:180)
        TableColumn("Dosya") {file in Label(file.name,systemImage:file.type == "LOG" ? "doc.text":"internaldrive").lineLimit(1).studioHelp(file.name)}.width(min:120,ideal:180,max:320)
        TableColumn("Tür") {file in Text(DatabaseFileFormat.type(file.type)).foregroundStyle(file.id == model.selectedID ? .primary:.secondary)}.width(76)
        TableColumn("Boyut") {Text(DatabaseFileFormat.pages($0.sizePages)).monospacedDigit()}.width(96)
        TableColumn("Otomatik büyüme") {Text(DatabaseFileFormat.growth($0)).monospacedDigit()}.width(125)
        TableColumn("Durum") {file in Text(file.state ?? "—").foregroundStyle(file.id == model.selectedID ? Color.primary:Color(nsColor:file.state == "ONLINE" ? StudioTheme.success:StudioTheme.warning))}.width(100)
      }.frame(minHeight:150,maxHeight:.infinity).accessibilityIdentifier("filesTable")
      detail
      HStack {
        Image(systemName:"info.circle").foregroundStyle(.secondary)
        Text("Boyutlar mantıksal tahsistir; disk boş alanını göstermez. Kullanım yalnız seçili veritabanından okunur.").lineLimit(1).studioHelp("tempdb ve FILESTREAM boyutları envanterde bilinmiyor olarak gösterilir; seçildiğinde sys.database_files üzerinden güncel değer okunur. Snapshot boyutu azami mantıksal tahsistir.")
        Spacer(minLength:0)
        if let time=model.sampledAt {Text(time,style:.time).monospacedDigit().studioHelp("Envanterin son başarılı yenilenme zamanı")}
      }.font(.system(size:10)).foregroundStyle(.secondary)
    }.padding(18).studioPanel()
      .background(MonitorVisibilityProbe {visible=$0;model.setVisible($0)})
      .onChange(of:model.databaseFilter) {_,_ in model.filterChanged()}
      .onChange(of:model.search) {_,_ in model.filterChanged()}
      .onReceive(NotificationCenter.default.publisher(for:ConnectedServer.explorerConnectionChanged)) {notification in
        if notification.object as? ConnectedServer === model.server {model.connectionChanged()}
      }
      .onDisappear {model.setVisible(false)}
      .task(id:visible) {if visible {await model.refresh()}}
      .task(id:model.selectedID) {await model.loadSelection()}
  }
  private var summary:some View {
    HStack(spacing:12) {
      let data=model.filtered.filter {$0.type == "ROWS"},logs=model.filtered.filter {$0.type == "LOG"}
      summaryCard("Bilinen tahsis",files:model.filtered,icon:"square.stack.3d.up",color:StudioTheme.accent)
      summaryCard("Veri dosyaları",files:data,icon:"internaldrive",color:StudioTheme.success)
      summaryCard("Log dosyaları",files:logs,icon:"doc.text",color:StudioTheme.warning)
    }
  }
  private func summaryCard(_ title:String,files:[DatabaseFilesMonitoring.File],icon:String,color:NSColor) -> some View {
    let known=files.compactMap(\.sizePages),unknown=files.count-known.count
    return HStack(spacing:10) {
      Image(systemName:icon).font(.system(size:19)).foregroundStyle(Color(nsColor:color)).frame(width:28)
      VStack(alignment:.leading,spacing:3) {
        Text(title).font(.system(size:11)).foregroundStyle(.secondary)
        Text(known.isEmpty ? "—":DatabaseFileFormat.megabytes(known.reduce(0.0) {$0+Double($1)/128})).font(.system(size:19,weight:.semibold)).monospacedDigit()
        Text("\(files.count) dosya"+(unknown>0 ? " · \(unknown) boyut bilinmiyor":"")).font(.system(size:10)).foregroundStyle(.secondary)
      }
      Spacer(minLength:0)
    }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
      .background(Color(nsColor:StudioTheme.canvas),in:RoundedRectangle(cornerRadius:10))
      .overlay(RoundedRectangle(cornerRadius:10).stroke(Color(nsColor:StudioTheme.border)))
  }
  @ViewBuilder private var detail:some View {
    if let file=model.selected {
      VStack(alignment:.leading,spacing:9) {
        HStack {
          Label(file.name,systemImage:file.type == "LOG" ? "doc.text":"internaldrive").font(.system(size:13,weight:.semibold)).lineLimit(1).studioHelp(file.name)
          Text("\(file.database ?? "—") · \(DatabaseFileFormat.type(file.type))").font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
          Spacer(minLength:8)
          if file.readOnly == true {Label("Salt okunur",systemImage:"lock.fill").font(.system(size:10)).foregroundStyle(.secondary)}
          StudioActionButton("Yolu Kopyala",icon:"doc.on.doc") {
            if let path=file.path {NSPasteboard.general.clearContents();NSPasteboard.general.setString(path,forType:.string)}
          }.disabled(file.path == nil).studioHelp("Seçili dosyanın fiziksel yolunu kopyala")
        }
        HStack(spacing:22) {
          detailMetric(file.sparse == true ? "Azami mantıksal boyut":"Dosya boyutu",DatabaseFileFormat.pages(file.sizePages))
          detailMetric("Kullanılan",DatabaseFileFormat.pages(file.usedPages))
          detailMetric("Dosya içi boş alan",DatabaseFileFormat.pages(file.freePages))
          detailMetric("Otomatik büyüme",DatabaseFileFormat.growth(file))
          detailMetric("Boyut sınırı",DatabaseFileFormat.maximum(file.maxPages))
          Spacer(minLength:0)
        }
        if let fraction=file.usedFraction {
          ProgressView(value:fraction).tint(Color(nsColor:fraction>=0.9 ? StudioTheme.warning:StudioTheme.accent))
            .studioHelp("Dosya içindeki ayrılmış sayfaların oranı: %"+String(format:"%.1f",fraction*100))
        } else {
          Text(file.type == "LOG" ? "Log kullanımı dosya başına güvenilir biçimde ölçülmez; kullanılan ve boş alan gösterilmez.":file.sparse == true ? "Snapshot dosyasının fiziksel disk kullanımı bu ölçümün kapsamında değil.":model.loadingDetails ? "Alan kullanımı seçili veritabanından okunuyor…":"Kullanım bilgisi henüz okunamadı veya bu dosya türünde sağlanmıyor.")
            .font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
        }
        Text(file.path ?? "Fiziksel yol bilgisi okunamadı.").font(.system(size:10,design:.monospaced)).lineLimit(2).textSelection(.enabled).studioHelp(file.path ?? "Fiziksel yol bilinmiyor")
      }.padding(12).background(Color(nsColor:StudioTheme.canvas),in:RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).stroke(Color(nsColor:StudioTheme.border))).accessibilityIdentifier("filesDetail")
    } else {
      HStack {Image(systemName:"cursorarrow.click").foregroundStyle(.secondary);Text(model.loading ? "Dosya envanteri okunuyor…":"Ayrıntısını görmek için bir dosya seçin.").foregroundStyle(.secondary);Spacer()}
        .padding(16).frame(height:118).background(Color(nsColor:StudioTheme.canvas),in:RoundedRectangle(cornerRadius:10))
    }
  }
  private func detailMetric(_ title:String,_ value:String) -> some View {
    VStack(alignment:.leading,spacing:4) {Text(title).font(.system(size:10)).foregroundStyle(.secondary);Text(value).font(.system(size:12,weight:.semibold)).monospacedDigit()}
  }
}

enum DatabaseFileFormat {
  static func type(_ value:String) -> String {value == "ROWS" ? "Veri":value == "LOG" ? "Log":value}
  static func pages(_ value:Int64?) -> String {guard let value else {return "—"};return megabytes(Double(value)/128)}
  static func megabytes(_ value:Double) -> String {
    guard value.isFinite,value>=0 else {return "—"}
    if value>=1_048_576 {return String(format:"%.2f TiB",value/1_048_576)}
    if value>=1024 {return String(format:"%.2f GiB",value/1024)}
    return String(format:"%.2f MiB",value)
  }
  static func growth(_ file:DatabaseFilesMonitoring.File) -> String {
    guard let growth=file.growth else {return "—"}
    if growth == 0 || file.maxPages == 0 {return "Kapalı"}
    guard let percent=file.percentGrowth else {return "—"}
    return percent ? "%\(growth)":pages(growth)
  }
  static func maximum(_ pages:Int64?) -> String {
    guard let pages else {return "—"}
    return pages == -1 ? "Disk sınırına kadar":pages == 0 ? "Büyüme yok":self.pages(pages)
  }
}

/// Synthetic metadata for isolated UI smoke only; no server or user files are read.
@MainActor enum DatabaseFilesUIFixture {
  static func catalog(_ sql:String,database:String?=nil) -> Execution {
    let base:[[String?]]=[
      ["5","1","DemoDB","DemoDB_Data","ROWS","/offline-fixture/data/DemoDB.mdf","1048576","-1","8192","0","ONLINE","0","0"],
      ["5","2","DemoDB","DemoDB_Log","LOG","/offline-fixture/log/DemoDB_log.ldf","262144","268435456","10","1","ONLINE","0","0"],
      ["6","1","Reporting","Reporting_Data","ROWS","/offline-fixture/data/Reporting.mdf","4194304","8388608","65536","0","ONLINE","1","0"],
      ["6","2","Reporting","Reporting_Log","LOG","/offline-fixture/log/Reporting_log.ldf","524288","268435456","8192","0","ONLINE","0","0"],
      ["2","1","tempdb","tempdev","ROWS","/offline-fixture/data/tempdb.mdf",nil,"-1","8192","0","ONLINE","0","0"]
    ]
    var execution=Execution()
    if sql == DatabaseFilesMonitoring.inventorySQL {
      execution.results=[Rows(fields:DatabaseFilesMonitoring.columns.map {Field($0)},values:base),Rows(fields:[Field("issue")],values:[])]
    } else if sql == DatabaseFilesMonitoring.detailSQL || ["DemoDB","Reporting","tempdb"].contains(where:{sql == DatabaseFilesMonitoring.detailSQL(database:$0)}) {
      let database=database ?? ["DemoDB","Reporting","tempdb"].first {sql == DatabaseFilesMonitoring.detailSQL(database:$0)}
      let values=base.filter {database == nil || $0[2] == database}.map {row -> [String?] in
        var row=row
        if row[2] == "tempdb" {row[6]="524288"}
        return row+[row[4] == "ROWS" ? row[0] == "5" ? "716800":row[0] == "2" ? "131072":"3145728":nil]
      }
      execution.results=[Rows(fields:(DatabaseFilesMonitoring.columns+["used_pages"]).map {Field($0)},values:values)]
    }
    return execution
  }
}
