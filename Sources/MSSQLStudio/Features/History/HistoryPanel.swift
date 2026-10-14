import AppKit
import CoreText
import SQLServerKit
import SwiftUI

struct HistoryPanel: View {
  let state: StudioState
  var open: (QueryRecord) -> Void
  var insert: ((QueryRecord) throws -> Void)?
  @State private var insertError=""
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
        Picker("History kapsamı", selection: $tab) {
          Text("Sorgular").tag(0); Text("Kapatılan Sekmeler").tag(1)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 270)
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
    Table(rows, selection: $selected) {
      TableColumn("Zaman") { Text($0.time.formatted(date: .abbreviated, time: .standard)) }.width(145)
      TableColumn("Sunucu", value: \.server).width(90)
      TableColumn("Veritabanı", value: \.database).width(100)
      TableColumn("Sorgu") { Text(($0.tabTitle.map { $0 + " · " } ?? "") + $0.text.replacingOccurrences(of: "\n", with: " ")).lineLimit(1) }.width(min: 120, ideal: 180)
      TableColumn("Durum") { row in
        Label(row.status, systemImage: row.tabTitle != nil ? "clock.arrow.circlepath" : row.status == "Hata" ? "xmark.circle" : row.status == "Kısmi" ? "exclamationmark.circle" : "checkmark.circle")
          .foregroundStyle(Color(nsColor: row.status == "Hata" ? StudioTheme.danger : row.status == "Kısmi" ? StudioTheme.warning : StudioTheme.muted))
          .lineLimit(1)
      }.width(85)
      TableColumn("Süre") { Text(String(format: "%.3f sn", $0.seconds)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing) }.width(75)
    }.controlSize(.small).accessibilityIdentifier("historyTable")
      .contextMenu(forSelectionType: UUID.self) { ids in
        if let id = ids.first, let record = rows.first(where: { $0.id == id }) {
          Button(record.tabTitle == nil ? "Yeni Sekmede Aç" : "Kapatılan Sekmeyi Aç") { open(record) }.disabled(state.historyServer(record) == nil)
        }
      } primaryAction: { ids in
        if let id = ids.first, let record = rows.first(where: { $0.id == id }) { insertRecord(record) }
      }
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
