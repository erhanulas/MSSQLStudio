import AppKit
import CoreText
import SQLServerKit
import SwiftUI

struct HistoryPanel: View {
  let state: StudioState
  var open: (QueryRecord) -> Void
  var insert: ((QueryRecord) throws -> Void)?
  @State private var insertError=""
  @State private var gridRevision=UUID()
  @State private var records: [QueryRecord] = []
  @State private var search = ""
  @State private var selected: UUID?
  @State private var server = ""
  @State private var database = ""
  @State private var status = ""
  @State private var period = 0
  @State private var tab=0
  @State private var slowest = false
  var filtered: [QueryRecord] {
    records.filter {
      ($0.tabTitle != nil ? tab==1:tab==0) &&
      (search.isEmpty || ($0.text + $0.database + $0.server + ($0.tabTitle ?? "")).localizedCaseInsensitiveContains(search)) &&
      (server.isEmpty || $0.server == server) && (database.isEmpty || $0.database == database) &&
      (status.isEmpty || $0.status == status) && (period == 0 || $0.time >= Date().addingTimeInterval(-Double(period)*86400))
    }.sorted { slowest ? $0.seconds > $1.seconds : $0.time > $1.time }
  }
  private func refreshRecords() {
    gridRevision=UUID()
    var ids=Set<UUID>()
    records=(state.history+(state.historyEnabled ? []:state.closedTabs)).filter {ids.insert($0.id).inserted}
  }
  private func insertRecord(_ record:QueryRecord) {
    do {try insert?(record);insertError=""} catch {insertError=error.localizedDescription}
  }
  var body: some View {
    let rows = filtered
    VStack(alignment: .leading, spacing: StudioMetrics.small) {
      HStack {
        StudioPanelHeading(title: "History", icon: "clock.arrow.circlepath", subtitle: "Sorgu ve kapatılan sekme geçmişi")
        StudioTabBar(items:[.init(id:0,title:"Sorgular",icon:"text.alignleft",tone:.accent),.init(id:1,title:"Kapatılan Sekmeler",icon:"rectangle.stack",tone:.accent)],selection:$tab).frame(width:380)
      }.fixedSize(horizontal: false, vertical: true)
      TextField("SQL, sunucu veya veritabanında ara", text: $search)
        .accessibilityIdentifier("historySearch")
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) { sourceFilters; outcomeFilters }
        VStack(alignment: .leading, spacing: 6) { sourceFilters; outcomeFilters }
      }.controlSize(.small).fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("historyFilters")
      HStack {
        Text("\(rows.count) eşleşme · Toplam \(String(format: "%.2f", rows.reduce(0) { $0 + $1.seconds })) sn")
        Spacer()
        Text(tab == 1 ? "Her DB: \(state.closedTabLimit) sekme" : "Saklama: \(state.historyRetentionDays) gün")
      }.font(.caption).foregroundStyle(.secondary)
      if !state.historyEnabled {
        Label("Geçmiş kaydı kapalı · Ayarlar → Çalışma Alanı", systemImage: "info.circle")
          .font(.caption).foregroundStyle(.secondary)
      }
      VSplitView {
        historyTable(rows).frame(minHeight: 160, idealHeight: 310)
        preview(rows.first { $0.id == selected }).frame(minHeight: 150, idealHeight: 220)
      }.accessibilityIdentifier("historySplit")
    }.padding(StudioMetrics.gap).studioPanel()
      .onAppear { refreshRecords(); selected = filtered.first?.id }
      .onChange(of: tab) { _, _ in status = ""; selected = filtered.first?.id }
      .onReceive(NotificationCenter.default.publisher(for: .init("queryHistoryChanged"))) { _ in refreshRecords() }
  }

  private var sourceFilters: some View {
    HStack(spacing: 6) {
      Text("Sunucu").foregroundStyle(.secondary)
      StudioSearchablePicker(title: "Sunucu", values: [""] + Array(Set(records.map(\.server))).sorted(), emptyTitle: "Tümü", selection: $server)
        .frame(width: 160)
      Text("Veritabanı").foregroundStyle(.secondary)
      StudioSearchablePicker(title: "Veritabanı", values: [""] + Array(Set(records.map(\.database))).sorted(), emptyTitle: "Tümü", selection: $database)
        .frame(width: 160)
    }.fixedSize(horizontal: true, vertical: true)
  }
  private var outcomeFilters: some View {
    HStack(spacing: 8) {
      Picker("Durum", selection: $status) {
        Text("Tümü").tag("")
        ForEach(tab == 1 ? ["Kapatılan Sekme"] : ["Başarılı", "Hata", "Kısmi"], id: \.self) { Text($0).tag($0) }
      }.frame(width: 145)
      Picker("Tarih", selection: $period) {
        Text("Tümü").tag(0); Text("24 saat").tag(1); Text("7 gün").tag(7); Text("30 gün").tag(30)
      }.frame(width: 130)
      Toggle("En yavaş önce", isOn: $slowest).fixedSize()
    }.fixedSize(horizontal: true, vertical: true)
  }
  private func historyTable(_ rows: [QueryRecord]) -> some View {
    StudioDataGrid(rows:rows,columns:[
      .init(title:"Zaman",width:145,value:{$0.time.ISO8601Format()},display:{$0.time.formatted(date:.abbreviated,time:.standard)}),
      .init(title:"Sunucu",width:90,value:{$0.server}),
      .init(title:"Veritabanı",width:100,value:{$0.database}),
      .init(title:"Sorgu",width:142,value:{($0.tabTitle.map {$0+" · "} ?? "")+$0.text},display:{($0.tabTitle.map {$0+" · "} ?? "")+String($0.text.prefix(240)).replacingOccurrences(of:"\n",with:" ")}),
      .init(title:"Durum",width:142,value:{$0.status},tone:{row in
        row.status=="Hata" ? .danger:row.status=="Kısmi" ? .warning:row.status=="Başarılı" ? .success:.neutral
      },symbol:{row in
        row.tabTitle != nil ? "clock.arrow.circlepath":row.status=="Hata" ? "xmark.circle":row.status=="Kısmi" ? "exclamationmark.circle":"checkmark.circle"
      }),
      .init(title:"Süre",width:86,numeric:true,value:{String($0.seconds)},display:{String(format:"%.3f sn",$0.seconds)})
    ],selection:$selected,identifier:"historyTable",revision:gridRevision,menu:{record in
      [.init(title:record.tabTitle == nil ? "Yeni Sekmede Aç":"Kapatılan Sekmeyi Aç",enabled:state.historyServer(record) != nil,perform:{open(record)})]
    },activate:{record in insertRecord(record)})
  }

  @ViewBuilder private func preview(_ record: QueryRecord?) -> some View {
    if let record {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Text(record.server + " / " + record.database).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
            .studioHelp(record.server + " / " + record.database)
          Spacer(minLength: 8)
          StudioActionButton("Kopyala", icon: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.text, forType: .string) }
          StudioActionButton("İmlece Ekle", icon: "text.insert") { insertRecord(record) }.disabled(insert == nil)
          StudioActionButton(record.tabTitle == nil ? "Yeni Sekmede Aç" : "Kapatılan Sekmeyi Aç", icon: "plus.square") { open(record) }.disabled(state.historyServer(record) == nil)
        }.controlSize(.small).fixedSize(horizontal: false, vertical: true)
        if !insertError.isEmpty { Text(insertError).foregroundStyle(Color(nsColor: StudioTheme.danger)).textSelection(.enabled) }
        if let message = record.errorMessage { Text(message).foregroundStyle(Color(nsColor: StudioTheme.danger)).font(.caption).lineLimit(3).textSelection(.enabled) }
        SQLReadOnlyPreview(sql: record.text).frame(minHeight: 70).accessibilityIdentifier("historySQLPreview")
        HStack {
          if let count = record.rowCount { Text("\(count) yüklenen satır") }
          Spacer()
          if state.historyServer(record) == nil { Text("Kendi bağlantısında açmak için sunucuyu Explorer’a ekleyin.") }
        }.font(.caption).foregroundStyle(.secondary)
      }.padding(.top, 8)
    } else {
      StudioEmptyState(title: filtered.isEmpty ? "Eşleşen sorgu yok" : "Sorguyu seçin", icon: "clock", detail: "SQL önizlemesi ve yeniden açma işlemleri burada görünür.")
    }
  }
}
