import AppKit
import SQLServerKit
import SwiftUI

struct AgentHistoryPanel:View {
  let server:ConnectedServer
  let job:String?
  init(server:ConnectedServer,job:String?,includeSteps:Bool=false) {
    self.server=server;self.job=job;_steps=State(initialValue:includeSteps)
  }
  @State private var rows:[SQLAgent.History]=[]
  @State private var cachedTree:[SQLAgent.History]=[]
  @State private var status = -1
  @State private var days=7
  @State private var steps=false
  @State private var search=""
  @State private var loading=false
  @State private var error=""
  @State private var selected:Int?
  @State private var generation=0
  @State private var requestID=UUID()
  private var tree:[SQLAgent.History] {
    let tree=cachedTree
    guard !search.isEmpty else {return tree}
    return tree.filter {row in
      ([row]+(row.children ?? [])).contains {($0.job+" "+$0.stepName+" "+$0.message).localizedCaseInsensitiveContains(search)}
    }
  }
  var body:some View {
    VStack(alignment:.leading,spacing:10) {
      StudioPanelHeading(title:"Log File Viewer · Job History",icon:"clock.arrow.circlepath",subtitle:server.profile.name+" · "+(job ?? "Tüm işler"))
      HStack {
        Picker("Durum",selection:$status) {Text("Tümü").tag(-1);Text("Succeeded").tag(1);Text("Failed").tag(0);Text("Retry").tag(2);Text("Canceled").tag(3);Text("In Progress").tag(4)}.frame(width:210).accessibilityIdentifier("agentHistoryStatus")
        Picker("Son",selection:$days) {Text("1 gün").tag(1);Text("7 gün").tag(7);Text("30 gün").tag(30);Text("365 gün").tag(365);Text("10 yıl").tag(3650)}.frame(width:150)
        Toggle("Adım ayrıntıları",isOn:$steps).studioHelp("İlk açılışta çalışma sonuçları alınır. Adım ve yeniden deneme ayrıntıları için açın.")
        Spacer()
        Button {generation+=1} label:{Label("Yenile",systemImage:"arrow.clockwise")}.disabled(loading).accessibilityIdentifier("agentHistoryRefresh")
      }
      TextField("Yüklenen çalışmalarda iş, adım veya mesaj ara",text:$search).textFieldStyle(.roundedBorder).accessibilityIdentifier("agentHistorySearch")
      Text("Filtre: \(days) gün · \(status < 0 ? "Tüm sonuçlar":"Seçili iş sonucu") · \(tree.count) çalışma. Durum filtresi iş sonucuna uygulanır; alt adımlar kendi sonuçlarıyla gösterilir.").font(.caption).foregroundStyle(.secondary)
      if loading {HStack {ProgressView().controlSize(.small);Text("Geçmiş yükleniyor… Önceki sonuçlar yükleme bitene kadar korunur.").font(.caption)}}
      if !error.isEmpty {StudioFeedback(message:error)}
      VSplitView {
        Table(tree,children:\.children,selection:$selected) {
          TableColumn("Çalışma / Adım") {row in
            Label(row.step == 0 ? row.job:"\(row.step) · \(row.stepName)",systemImage:row.step == 0 ? "clock":"list.number")
          }.width(min:180,ideal:290)
          TableColumn("Durum") {AgentStatus(status:$0.status)}.width(110)
          TableColumn("Başlangıç",value:\.started).width(165)
          TableColumn("Süre") {Text($0.duration).monospacedDigit().frame(maxWidth:.infinity,alignment:.trailing)}.width(85)
          TableColumn("Tekrar") {Text("\($0.retries)")}.width(55)
          TableColumn("Mesaj",value:\.message).width(min:180,ideal:320)
        }.frame(minHeight:180,idealHeight:350).accessibilityIdentifier("agentHistoryTable")
        Group {
          if let row=rows.first(where:{$0.id == selected}) {
            ScrollView {
              VStack(alignment:.leading,spacing:8) {
                HStack {Text("Seçili kayıt ayrıntıları").font(.headline);Spacer();StudioActionButton("Kopyala", icon:"doc.on.doc", tint:.accentColor) {NSPasteboard.general.clearContents();NSPasteboard.general.setString(historyDetails(row),forType:.string)}}
                Text("\(row.job) · \(row.step == 0 ? "İş sonucu":row.stepName) · \(row.statusLabel)")
                Text("Sunucu: \(row.server)    Başlangıç: \(row.started)    Süre: \(row.duration)")
                Text("SQL mesajı: \(String(row.messageID))    Önem derecesi: \(row.severity)    Yeniden deneme: \(row.retries)").foregroundStyle(.secondary)
                Divider()
                Text(row.message).font(.system(size:12,design:.monospaced)).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("agentHistoryMessage")
              }.textSelection(.enabled).padding(12)
            }
          } else {
            ScrollView {Text(rows.isEmpty && !loading ? "Bu filtreye uygun geçmiş kaydı yok.":(steps ? "İşin yanındaki oku açarak adımları görün; mesajın tamamını okumak için bir kayıt seçin.":"Bir çalışma seçerek mesajı okuyun; adımlar için Adım ayrıntıları seçeneğini açın.")).foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:116,alignment:.center)}
          }
        }.frame(minHeight:140,idealHeight:220).background(Color(nsColor:StudioTheme.canvas))
      }
      Text(rows.count >= 5001 ? "5.000 kayıt sınırına ulaşıldı; en eski çalışmanın adımları eksik olabilir. Tarih filtresini daraltın.":"En yeni 500 tamamlanmış çalışma · Sunucunun yerel saati. Devam eden işleri Job Activity Monitor’den izleyin; geçmiş, adımlar tamamlandıkça oluşur.").font(.caption).foregroundStyle(.secondary)
    }.padding(StudioMetrics.gap).studioPanel().task(id:"\(generation)|\(status)|\(days)|\(steps)") {
      let token=UUID();requestID=token;loading=true;error=""
      defer {if requestID == token {loading=false}}
      do {
        let result=try await server.catalog(SQLAgent.history(name:job,status:status<0 ? nil:status,days:days,includeSteps:steps),database:"msdb")
        try Task.checkCancellation();guard requestID == token else {return}
        let decoded=try await Task.detached(priority:.userInitiated) {
          let rows=try SQLAgent.decodeHistory(result)
          return (rows,SQLAgent.historyTree(rows))
        }.value
        try Task.checkCancellation();guard requestID == token else {return}
        rows=decoded.0;cachedTree=decoded.1
        if !rows.contains(where:{$0.id == selected}) {selected=nil}
      } catch is CancellationError {} catch {if requestID == token {self.error=error.localizedDescription}}
    }
  }
  private func historyDetails(_ row:SQLAgent.History)->String {
    "\(row.job) · \(row.stepName)\n\(row.statusLabel) · \(row.started) · \(row.duration)\nSQL \(row.messageID), Severity \(row.severity), Retries \(row.retries)\n\(row.message)"
  }
}
