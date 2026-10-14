import Foundation

extension TSQL {
  public static func run(
    _ sql: String, on connection: ODBCConnection, limits: Limits = Limits(),
    events: (@Sendable (QueryEvent) -> Void)? = nil
  ) async throws -> Execution {
    try await run(sql, limits: limits, events: events) { text, budget, events in
      try await connection.execute(text, limits: budget, events: events)
    }
  }
  // Shared batch orchestration also permits deterministic budget/streaming tests
  // without connecting to a user's database.
  static func run(
    _ sql: String, limits: Limits,
    events: (@Sendable (QueryEvent) -> Void)? = nil,
    execute: @Sendable (String, Limits, (@Sendable (QueryEvent) -> Void)?) async throws -> Execution
  ) async throws -> Execution {
    let start = Date()
    var output = Execution()
    var budget = limits
    let preserveExecution=limits.readOnlyRowLimit && !usesResultRowLimit(sql)
    if preserveExecution {budget.rows=Int.max;budget.preserveExecution=true}
    for (batchIndex, batch) in try batches(sql).enumerated() {
      if !preserveExecution && (budget.resultSets <= 0 || budget.totalBytes <= 0) {
        output.partial = true
        output.stoppedEarly = true
        output.messages.append("Sorgu bütçesi doldu; sonraki batch'ler çalıştırılmadı.")
        break
      }
      do {
        try Task.checkCancellation()
        let offset = output.results.count
        let sourceMap = ResultSourceMap(sql: batch.text, batch: batchIndex + 1)
        var result = try await execute(
          batch.text, budget,
          { event in
            switch event {
            case .source(let index, let source): events?(.source(offset + index, source))
            case .result(let index, let fields):
              events?(.source(offset + index, sourceMap.batchSource))
              events?(.result(offset + index, fields))
            case .rows(let index, let rows): events?(.rows(offset + index, rows))
            case .snapshot(let index, let rows): events?(.snapshot(offset + index, rows))
            case .message(let text): events?(.message(text))
            }
          })
        let sources = sourceMap.sources(for: result.results)
        for index in result.results.indices {
          result.results[index].source = sources[index]
          if let source = sources[index] { events?(.source(offset + index, source)) }
        }
        output.results += result.results
        output.messages += result.messages
        output.partial = output.partial || result.partial
        output.stoppedEarly = result.stoppedEarly
        budget.resultSets -= ResultStreamBudget.rowsetCount(result.results)
        budget.totalBytes -= result.bytesRead
        output.bytesRead += result.bytesRead
        if output.stoppedEarly { break }
      } catch {
        let message = "Batch başlangıç satırı \(batch.line): \(error.localizedDescription)"
        guard !output.results.isEmpty else {
          let failure=error as? SQLFailure
          throw SQLFailure("Batch başlangıç satırı \(batch.line): \(failure?.message ?? error.localizedDescription)",diagnostics:failure?.diagnostics ?? [])
        }
        output.partial = true
        output.stoppedEarly = true
        output.messages.append(message)
        break
      }
    }
    output.elapsed = Date().timeIntervalSince(start)
    return output
  }
}
