import AppKit
import SQLServerKit
import SwiftUI

struct ColumnFilterPanel: View {
  let rows: Rows
  let column: Int
  let apply: (ColumnRule) throws -> Void
  @State private var rule: ColumnRule
  @State private var search = ""
  @State private var values: [CellChoice] = []
  @State private var truncated = false
  @State private var loading = false
  @State private var conditionExpanded: Bool
  @State private var error = ""
  init(rows: Rows, column: Int, initial: ColumnRule, apply: @escaping (ColumnRule) throws -> Void) {
    self.rows = rows
    self.column = column
    self.apply = apply
    _rule = State(initialValue: initial)
    _conditionExpanded = State(initialValue: initial.operation != .any)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 22)).foregroundStyle(Color(nsColor: StudioTheme.accent))
        VStack(alignment: .leading, spacing: 3) {
          Text(rows.fields[column].name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
          Text(rows.fields[column].dataType + " · Yerel filtre").font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      TextField("Değerlerde ara", text: $search).textFieldStyle(.roundedBorder)
      HStack(spacing: 10) {
        Button("Tümü") { rule.choices = nil }
        Button("Görünenleri seç") { rule.choices = (rule.choices ?? []).union(values) }
        Button("Seçimi kaldır") { rule.choices = [] }
        Spacer(minLength: 0)
        if loading { ProgressView().controlSize(.small) }
      }.controlSize(.small)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(values, id: \.self) { value in
            Toggle(String(value.title.prefix(256)), isOn: Binding(
              get: { rule.choices?.contains(value) ?? false },
              set: { selected in
                if selected { rule.choices = (rule.choices ?? []).union([value]) }
                else { rule.choices?.remove(value) }
              }))
              .toggleStyle(.checkbox).font(.system(size: 12)).lineLimit(1)
              .padding(.horizontal, 10).padding(.vertical, 4)
              .frame(maxWidth: .infinity, alignment: .leading)
              .studioHelp(String(value.title.prefix(4000)))
          }
          if values.isEmpty && !loading { Text("Eşleşen değer yok").foregroundStyle(.secondary).padding(12) }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(minHeight: 110, maxHeight: .infinity)
      .background(Color(nsColor: StudioTheme.resultCanvas))
      .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: StudioTheme.resultBorder), lineWidth: 1))
      Text(rule.choices.map { "\($0.count) değer seçili" } ?? "Tüm değerler · Henüz değer seçimi yok")
        .font(.caption).foregroundStyle(.secondary)
      if truncated { Text("İlk 500 farklı değer gösteriliyor; diğerlerini arayabilirsiniz. Seçimler korunur.").font(.caption).foregroundStyle(.secondary) }
      StudioDisclosureHeader(title:"Koşul",icon:"line.3.horizontal.decrease",tint:StudioTheme.accent,expanded:conditionExpanded) {conditionExpanded.toggle()}
        .frame(height:StudioMetrics.controlHeight)
      if conditionExpanded {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Karşılaştırma", selection: $rule.operation) {
            ForEach(ColumnOperation.allCases, id: \.self) { operation in
              if !rows.fields[column].numeric && !ResultFiltering.isDate(rows.fields[column]) || ![.contains, .notContains, .starts, .empty, .notEmpty].contains(operation) {
                Text(operation.rawValue).tag(operation)
              }
            }
          }
          if rule.operation.needsValue {
            TextField(ResultFiltering.isDate(rows.fields[column]) ? "YYYY-MM-DD veya ISO 8601" : "Değer", text: $rule.first).textFieldStyle(.roundedBorder)
          }
          if rule.operation == .between { TextField("Bitiş (dahil)", text: $rule.second).textFieldStyle(.roundedBorder) }
        }.padding(.top, 6)
      }
      if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3) }
      Divider()
      HStack {
        Button("Temizle") { commit(ColumnRule()) }
        Spacer()
        Button("Uygula") { commit(rule) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
      }
      Text("Yalnız yüklenen sonuçları filtreler.").font(.caption2).foregroundStyle(.secondary)
    }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: StudioTheme.resultCanvas))
      .task(id: search) {
        loading = true
        error = ""
        do {
          if !search.isEmpty { try await Task.sleep(for: .milliseconds(200)) }
          let input = search
          let worker = Task.detached(priority: .userInitiated) {
            try ResultFiltering.choices(rows, column: column, search: input)
          }
          let output = try await withTaskCancellationHandler {
            try await worker.value
          } onCancel: {
            worker.cancel()
          }
          try Task.checkCancellation()
          values = output.values
          truncated = output.truncated
          loading = false
        } catch is CancellationError {} catch {
          self.error = error.localizedDescription
          loading = false
        }
      }
  }
  private func commit(_ value: ColumnRule) {
    do { try apply(value) } catch { self.error = error.localizedDescription }
  }
}
