import Foundation
import SQLServerKit

/// At most one parser runs per grid. Streaming rows reuse the same source/field plan.
@MainActor final class ResultQueryCopyPresentation {
  private struct Request:Equatable,Sendable {let source:SQLResultSource;let fields:[Field]}
  private var task:Task<Void,Never>?
  deinit {task?.cancel()}
  private var current:Request?
  private var pending:Request?
  private(set) var preparing=false
  private(set) var template:ResultQueryCopy?
  private(set) var reason="Sonucun kaynak SELECT bilgisi bulunamadı."
  func prepare(source:SQLResultSource?,fields:[Field]) {
    let next=source.map {Request(source:$0,fields:fields)}
    guard next != current else {return}
    current=next;template=nil;pending=nil
    reason=next == nil ? "Sonucun kaynak SELECT bilgisi bulunamadı.":"Kaynak SELECT hazırlanıyor…"
    guard let next else {return}
    if preparing {pending=next} else {start(next)}
  }
  private func start(_ request:Request) {
    preparing=true
    task=Task { [weak self] in
      let worker=Task.detached(priority:.utility) {Result {try Task.checkCancellation();return try ResultQueryCopy(source:request.source,fields:request.fields)}}
      let output=await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
      guard let self else {return}
      preparing=false;task=nil
      if current==request {
        switch output {
        case .success(let template):self.template=template;reason=""
        case .failure(let error):reason=error.localizedDescription
        }
      }
      if let pending {self.pending=nil;start(pending)}
    }
  }
}
