import Foundation
import SQLServerKit

/// Snapshot-based filtering/sorting; native grid state and pagination stay in ResultController.
@MainActor final class ResultProjectionController {
  struct Request: Sendable {
    let rows: Rows
    let search: String
    let rules: [Int:ColumnRule]
    let sortColumn: Int?
    let ascending: Bool
  }
  typealias Operation = @Sendable (Request) async throws -> [Int]?
  private let operation:Operation
  private var task:Task<Void,Never>?
  private var generation=UUID()
  init(operation:@escaping Operation = ResultProjectionController.compute) {self.operation=operation}
  deinit {task?.cancel()}
  func cancel() {generation=UUID();task?.cancel()}
  func project(_ request:Request,debounce:Bool=true,completion:@escaping (Result<[Int]?,Error>)->Void) {
    cancel()
    let id=generation,operation=operation
    task=Task { [weak self] in
      do {
        if debounce {try await Task.sleep(for:.milliseconds(220))}
        let output=try await operation(request)
        guard let self,generation == id,!Task.isCancelled else {return}
        task=nil
        completion(.success(output))
      } catch {
        guard let self,generation == id,!Task.isCancelled else {return}
        task=nil
        completion(.failure(error))
      }
    }
  }
  nonisolated static func compute(_ request:Request) async throws -> [Int]? {
    let worker=Task.detached(priority:.userInitiated) {
      try ResultFiltering.projection(request.rows,search:request.search,rules:request.rules,
        sortColumn:request.sortColumn,ascending:request.ascending)
    }
    return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
  }
}
