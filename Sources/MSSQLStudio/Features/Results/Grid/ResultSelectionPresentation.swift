import AppKit
import SQLServerKit

/// One latest-only worker per grid; scrolling and cell drawing never aggregate.
@MainActor final class ResultSelectionPresentation {
  typealias Operation=@Sendable (ResultSelectionSummary.Request) async throws -> ResultSelectionSummary
  let label=NSTextField(labelWithString:"Toplam: —   ·   Sayı: 0")
  var changed:(()->Void)?
  private var task:Task<Void,Never>?
  private var revision=UUID()
  private let operation:Operation
  init(operation:@escaping Operation=ResultSelectionPresentation.compute) {
    self.operation=operation
    label.font = .monospacedDigitSystemFont(ofSize:11,weight:.medium)
    label.textColor = .secondaryLabelColor;label.alignment = .right
    label.isSelectable=true;label.lineBreakMode = .byTruncatingMiddle
    label.setAccessibilityIdentifier("resultSelectionSummaryValues")
    label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    label.toolTip=Self.scope
  }
  deinit {task?.cancel()}
  private static let scope="Toplam: tek kolondaki dikey sayısal seçim (bit ve metin hariç). Birden fazla kolon seçilirse toplama yapılmaz. Sayı: NULL olmayan tüm seçili hücreler. Yalnız görünen sayfa/seçim ve uygulanmış yerel düzenlemeler hesaplanır; SQL çalıştırılmaz."
  func cancel() {revision=UUID();task?.cancel();label.stringValue="Toplam: —   ·   Sayı: 0";label.toolTip=Self.scope;changed?()}
  func update(_ request:ResultSelectionSummary.Request) {
    let previous=task
    cancel()
    guard !request.selection.isEmpty,!request.columns.isEmpty else {return}
    let id=revision,operation=operation
    label.stringValue="Toplam: …   ·   Sayı: …";changed?()
    task=Task { [weak self] in
      // Wait for a cancelled physical read before starting its successor.
      if let previous {await previous.value}
      do {
        try await Task.sleep(for:.milliseconds(120))
        let result=try await operation(request)
        guard let self,revision==id,!Task.isCancelled else {return}
        label.stringValue="Toplam: \(result.sum ?? "—")   ·   Sayı: \(result.count.formatted())"
        label.toolTip=label.stringValue+"\n"+Self.scope
        task=nil;changed?()
      } catch {
        guard let self,revision==id,!Task.isCancelled else {return}
        label.stringValue="Toplam: —   ·   Sayı: —"
        label.toolTip=error.localizedDescription+"\n"+Self.scope
        task=nil;changed?()
      }
    }
  }
  nonisolated static func compute(_ request:ResultSelectionSummary.Request) async throws -> ResultSelectionSummary {
    let worker=Task.detached(priority:.utility) {try ResultSelectionSummary.compute(request)}
    return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
  }
}
