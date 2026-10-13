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
  @State private var error = ""
  init(rows: Rows, column: Int, initial: ColumnRule, apply: @escaping (ColumnRule) throws -> Void) {
    self.rows = rows
    self.column = column
    self.apply = apply
    _rule = State(initialValue: initial)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(rows.fields[column].name).font(.headline).lineLimit(2)
      Picker("Koşul", selection: $rule.operation) {
        ForEach(ColumnOperation.allCases, id: \.self) { op in
          if !rows.fields[column].numeric && !ResultFiltering.isDate(rows.fields[column])
            || ![.contains, .starts, .empty, .notEmpty].contains(op)
          {
            Text(op.rawValue).tag(op)
          }
        }
      }
      if rule.operation.needsValue {
        TextField(
          ResultFiltering.isDate(rows.fields[column]) ? "YYYY-MM-DD veya ISO 8601" : "Değer",
          text: $rule.first)
      }
      if rule.operation == .between { TextField("Bitiş (dahil)", text: $rule.second) }
      Divider()
      Toggle(
        "Değer seçimini kullan",
        isOn: Binding(get: { rule.choices != nil }, set: { rule.choices = $0 ? [] : nil }))
      TextField("Kolon değerlerinde ara", text: $search).textFieldStyle(.roundedBorder)
      HStack {
        Button("Görünenleri seç") { rule.choices = (rule.choices ?? []).union(values) }
        Button("Kaldır") { if rule.choices != nil { rule.choices?.subtract(values) } }
        Spacer()
        if loading { ProgressView().controlSize(.small) }
      }.controlSize(.small)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 5) {
          ForEach(values, id: \.self) { value in
            Toggle(
              String(value.title.prefix(256)),
              isOn: Binding(
                get: { rule.choices?.contains(value) ?? false },
                set: { on in
                  if on { rule.choices?.insert(value) } else { rule.choices?.remove(value) }
                })
            )
            .toggleStyle(.checkbox).disabled(rule.choices == nil).lineLimit(1).help(
              String(value.title.prefix(4000)))
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(maxHeight: .infinity)
      Text(
        truncated
          ? "En fazla 500 farklı değer gösterilir; diğerlerini arayın. Seçimler korunur."
          : "\(values.count) farklı değer · NULL ve boş metin ayrıdır."
      ).font(.caption).foregroundStyle(.secondary)
      if let choices = rule.choices {
        Text("\(choices.count) değer seçili; koşulla birlikte uygulanır.").font(.caption)
      }
      if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3) }
      HStack {
        Button("Filtreyi Kaldır") { commit(ColumnRule()) }
        Spacer()
        Button("Uygula") { commit(rule) }.buttonStyle(.borderedProminent)
      }
    }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity)
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
