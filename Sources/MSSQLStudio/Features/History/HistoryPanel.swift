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
  var record: QueryRecord? { filtered.first { $0.id == selected } }
  private func refreshRecords() {
    var ids=Set<UUID>()
    records=(state.history+(state.historyEnabled ? []:state.closedTabs)).filter {ids.insert($0.id).inserted}
  }
  private func insertRecord(_ record:QueryRecord) {
    do {try insert?(record);insertError=""} catch {insertError=error.localizedDescription}
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StudioPanelHeading(title: "History", icon: "clock.arrow.circlepath", subtitle: "Sorgularını bul, sürelerini karşılaştır ve yeniden aç")
      Picker("History kapsamı",selection:$tab) {Text("Sorgular").tag(0);Text("Kapatılan Sekmeler").tag(1)}.pickerStyle(.segmented)
      HStack {
        Label("\(records.filter {($0.tabTitle != nil) == (tab==1)}.count) " + (tab==1 ? "sekme":"sorgu"), systemImage:tab==1 ? "rectangle.stack":"text.badge.checkmark")
        Spacer()
        Text(tab==1 ? "Her DB: \(state.closedTabLimit) sekme":"Saklama: \(state.historyRetentionDays) gün").foregroundStyle(.secondary)
      }.font(.callout)
      if !state.historyEnabled { Text("Geçmiş kaydı kapalı. Ayarlar → Çalışma Alanı'ndan açabilirsiniz.").foregroundStyle(.secondary) }
      TextField("SQL, sunucu veya veritabanında ara", text: $search)
      HStack {
        Picker("Sunucu", selection: $server) { Text("Tümü").tag(""); ForEach(Array(Set(records.map(\.server))).sorted(), id: \.self) { Text($0).tag($0) } }
        StudioSearchablePicker(title:"Veritabanı",values:[""]+Array(Set(records.map(\.database))).sorted(),emptyTitle:"Tümü",selection:$database)
        Picker("Durum", selection: $status) { Text("Tümü").tag(""); ForEach(tab==1 ? ["Kapatılan Sekme"]:["Başarılı", "Hata", "Kısmi"], id: \.self) { Text($0).tag($0) } }
        Picker("Tarih", selection: $period) { Text("Tümü").tag(0); Text("24 saat").tag(1); Text("7 gün").tag(7); Text("30 gün").tag(30) }
        Toggle("En yavaş önce", isOn: $slowest)
      }.controlSize(.small)
      Text("\(filtered.count) eşleşme · Toplam \(String(format: "%.2f", filtered.reduce(0) { $0 + $1.seconds })) sn").font(.caption).foregroundStyle(.secondary)
      Table(filtered, selection: $selected) {
        TableColumn("Zaman") { Text($0.time.formatted(date: .abbreviated, time: .standard)) }.width(min: 150, ideal: 175)
        TableColumn("Sunucu", value: \.server)
        TableColumn("Veritabanı", value: \.database)
        TableColumn("Sorgu") { Text(($0.tabTitle.map {$0+" · "} ?? "")+$0.text.replacingOccurrences(of: "\n", with: " ")).lineLimit(1) }.width(min: 180, ideal: 300)
        TableColumn("Durum") { Label($0.status, systemImage: $0.tabTitle != nil ? "clock.arrow.circlepath" : $0.status == "Hata" ? "xmark.circle" : $0.status == "Kısmi" ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle($0.status == "Hata" ? Color.red : Color.secondary) }
        TableColumn("Süre") { Text(String(format: "%.3f sn", $0.seconds)).monospacedDigit() }.width(85)
      }.contextMenu(forSelectionType: UUID.self) { ids in
        if let id=ids.first,let record=filtered.first(where:{$0.id==id}) {
          Button(record.tabTitle == nil ? "Yeni Sekmede Aç":"Kapatılan Sekmeyi Aç") {open(record)}.disabled(state.historyServer(record)==nil)
        }
      } primaryAction: { ids in
        if let id=ids.first,let record=filtered.first(where:{$0.id == id}) {insertRecord(record)}
      }.frame(minHeight: 180)
      if !insertError.isEmpty {Text(insertError).foregroundStyle(.red)}
      if let record {
        HStack {
          Text(record.server + " / " + record.database).font(.headline)
          Spacer()
          StudioActionButton("Kopyala", icon: "doc.on.doc", tint: .accentColor) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.text, forType: .string) }
          StudioActionButton("İmlece Ekle", icon: "text.insert") {insertRecord(record)}.disabled(insert == nil)
          StudioActionButton(record.tabTitle == nil ? "Yeni Sekmede Aç":"Kapatılan Sekmeyi Aç", icon: "plus.square", tint: .accentColor) { open(record) }
            .disabled(state.historyServer(record) == nil)
        }
        if let message = record.errorMessage { Text(message).foregroundStyle(.red).font(.caption).lineLimit(3).textSelection(.enabled) }
        if let count = record.rowCount { Text("\(count) yüklenen satır").font(.caption).foregroundStyle(.secondary) }
        SQLReadOnlyPreview(sql: record.text).frame(minHeight: 150, idealHeight: 240)
        if state.historyServer(record) == nil { Text("Bu sunucuyu Explorer'a ekleyerek sorguyu kendi bağlantısında açabilirsiniz.").font(.caption).foregroundStyle(.secondary) }
      } else {
        StudioEmptyState(title: filtered.isEmpty ? "Eşleşen sorgu yok" : "Sorguyu seçin", icon: "clock", detail: "SQL önizlemesi ve yeniden açma işlemleri burada görünür.").frame(height: 170)
      }
    }.padding(20).studioPanel()
      .onAppear { refreshRecords(); selected = filtered.first?.id }
      .onChange(of:tab) { _,_ in status="";selected=filtered.first?.id }
      .onReceive(NotificationCenter.default.publisher(for: .init("queryHistoryChanged"))) { _ in refreshRecords() }
  }
}
