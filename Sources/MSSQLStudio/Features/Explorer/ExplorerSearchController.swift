import Foundation
import SQLServerKit

/// Owns debouncing, cancellation and the single in-flight disk search.
/// Native tree selection/expansion remains in the presentation layer.
@MainActor final class ExplorerSearchController {
  struct Request: Sendable {
    let profile: ServerProfile
    let databases: [String]
    let text: String
    let operation: Int
    let folder: Folder?
  }
  struct Match: Sendable {
    let database: String
    let item: CatalogItem
  }
  struct Output: Sendable {
    let matches: [Match]
    let pending: Int
    let truncated: Bool
    let staleDatabases: [String]
  }
  typealias Search = @Sendable (Request) async throws -> Output
  private let operation: Search
  private let delay: Duration
  private var task: Task<Void, Never>?
  private var generation = UUID()
  private var pending: (UUID, Request, (Result<Output, Error>) -> Void)?

  init(delay: Duration = .milliseconds(350), operation: @escaping Search = ExplorerSearchController.readIndex) {
    self.delay = delay
    self.operation = operation
  }
  deinit { task?.cancel() }

  func cancel() {
    generation = UUID()
    pending = nil
    task?.cancel()
  }
  func search(_ request: Request, completion: @escaping (Result<Output, Error>) -> Void) {
    generation = UUID()
    pending = (generation, request, completion)
    task?.cancel()
    startNext()
  }
  private func startNext() {
    guard task == nil, let (id, request, completion) = pending else { return }
    pending = nil
    let operation = operation, delay = delay
    task = Task { [weak self] in
      let result: Result<Output, Error>
      do {
        try await Task.sleep(for: delay)
        result = .success(try await operation(request))
      } catch { result = .failure(error) }
      guard let self else { return }
      task = nil
      if generation == id, !Task.isCancelled { completion(result) }
      startNext()
    }
  }

  nonisolated static func readIndex(_ request: Request) async throws -> Output {
    var matches: [Match] = [], pending = 0, stale: [String] = []
    for database in request.databases {
      try Task.checkCancellation()
      let scope = CatalogDiskIndex.scope(profile: request.profile, database: database)
      guard let status = try await CatalogDiskIndex.shared.status(scope: scope) else {
        pending += 1
        continue
      }
      if Date().timeIntervalSince(status.synchronizedAt) > 300 { stale.append(database) }
      let rows = try await CatalogDiskIndex.shared.search(scope: scope, text: request.text,
        operation: request.operation, folder: request.folder, limit: 501 - matches.count)
      matches.append(contentsOf: rows.map { Match(database: database, item: $0) })
      if matches.count > 500 { break }
    }
    try Task.checkCancellation()
    return Output(matches: Array(matches.prefix(500)), pending: pending,
      truncated: matches.count > 500, staleDatabases: stale)
  }
}
