import SwiftUI
import SQLServerKit

/// Uses the result viewer's value checklist, comparison editor and validation unchanged.
struct ProfilerColumnFilter:View {
  @ObservedObject var model:ProfilerModel
  let column:SQLProfilerFiltering.Column
  let events:[SQLProfiler.Event]
  let initial:ColumnRule
  let close:()->Void
  @State private var rows:Rows?
  @State private var error=""
  var body:some View {
    Group {
      if let rows {
        ColumnFilterPanel(rows:rows,column:0,initial:initial) {rule in
          try model.setColumnFilter(rule,column:column);close()
        }
      } else if !error.isEmpty {StudioFeedback(message:error,tone:.error).padding(12)}
      else {ProgressView("Değerler hazırlanıyor…")}
    }.task {
      let worker=Task.detached(priority:.utility) {try SQLProfilerFiltering.rows(events,columns:[column])}
      do {
        let snapshot=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation();rows=snapshot
      } catch is CancellationError {} catch {self.error=error.localizedDescription}
    }
  }
}
