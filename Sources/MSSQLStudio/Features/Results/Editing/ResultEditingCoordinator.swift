import Foundation
import SQLServerKit

/// Prepares a read-only result in the background; opening edit mode reuses the same flight.
@MainActor final class ResultEditingCoordinator {
  struct Context: Equatable {
    let serverID: UUID
    let serverGeneration: UUID
    let resultGeneration: Int
    let database: String
    let sql: String
    let fields: [Field]
    var profileScope = ""
  }
  typealias Prepared = (snapshot: ResultEditingSnapshot, cached: Bool)
  private var context: Context?
  private var task: Task<Prepared, Error>?
  private var failed = false
  private var flight = UUID()
  deinit { task?.cancel() }
  func invalidate() { task?.cancel(); context = nil; failed = false; flight = UUID() }
  func warm(_ context: Context, operation: @escaping @Sendable () async throws -> Prepared) {
    guard self.context != context else { return }
    let previous = task
    invalidate()
    self.context = context
    let flight = self.flight
    task = Task { [weak self] in
      do {
        // Cancellation must physically retire the old worker before another read starts.
        if let previous { _ = await previous.result }
        try Task.checkCancellation()
        return try await operation()
      }
      catch { if self?.flight == flight { self?.failed = true }; throw error }
    }
  }
  func prepared(_ context: Context, operation: @escaping @Sendable () async throws -> Prepared) async throws -> Prepared {
    if self.context == context, failed { invalidate() }
    warm(context, operation: operation)
    guard let task else { throw CancellationError() }
    let flight = self.flight
    let value = try await task.value
    try Task.checkCancellation()
    guard self.context == context, self.flight == flight else { throw CancellationError() }
    return value
  }
}
