import Foundation

public struct UpdateDownloadProgress:Sendable,Equatable {
  public let receivedBytes:Int64
  public let expectedBytes:Int64?
  public init(receivedBytes:Int64,expectedBytes:Int64) {
    self.receivedBytes=max(0,receivedBytes)
    self.expectedBytes=expectedBytes>0 ? expectedBytes:nil
  }
  public var fraction:Double? {
    expectedBytes.map {min(1,Double(receivedBytes)/Double($0))}
  }
}

/// Per-task delegate; bounded callbacks avoid flooding the native UI queue.
final class UpdateDownloadObserver:NSObject,URLSessionDownloadDelegate,@unchecked Sendable {
  private let report:@Sendable (UpdateDownloadProgress)->Void
  private let lock=NSLock()
  private var lastReport:TimeInterval = -1
  private var continuation:CheckedContinuation<(URL,URLResponse),Error>?
  private var session:URLSession?
  private var task:URLSessionDownloadTask?
  private var cancelled=false
  init(report:@escaping @Sendable (UpdateDownloadProgress)->Void) {self.report=report}
  func download(from url:URL) async throws -> (URL,URLResponse) {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation {continuation in
        let task=lock.withLock { () -> URLSessionDownloadTask? in
          guard !cancelled else {return nil}
          self.continuation=continuation
          let session=URLSession(configuration:.default,delegate:self,delegateQueue:nil)
          self.session=session
          let task=session.downloadTask(with:url);self.task=task
          return task
        }
        if let task {task.resume()} else {continuation.resume(throwing:CancellationError())}
      }
    } onCancel: {
      let task=self.lock.withLock {self.cancelled=true;return self.task}
      task?.cancel()
    }
  }
  private func finish(_ result:Result<(URL,URLResponse),Error>) {
    let state=lock.withLock {let value=(continuation,session);continuation=nil;session=nil;task=nil;return value}
    state.0?.resume(with:result)
    state.1?.finishTasksAndInvalidate()
  }
  func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {
    // URLSession owns location only for this callback. Keep a unique temporary
    // copy for the existing hash/installer validators, which remove it afterwards.
    let copy=FileManager.default.temporaryDirectory.appendingPathComponent("MSSQLStudio-download-"+UUID().uuidString+".tmp")
    do {
      guard let response=downloadTask.response else {throw URLError(.badServerResponse)}
      try FileManager.default.copyItem(at:location,to:copy)
      if lock.withLock({cancelled}) {throw CancellationError()}
      finish(.success((copy,response)))
    } catch {try? FileManager.default.removeItem(at:copy);finish(.failure(error))}
  }
  func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
    if let error {finish(.failure(lock.withLock {cancelled} ? CancellationError():error))}
  }
  func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
    let now=ProcessInfo.processInfo.systemUptime
    let shouldReport=lock.withLock {
      guard lastReport<0 || now-lastReport>=0.1 || (totalBytesExpectedToWrite>0 && totalBytesWritten>=totalBytesExpectedToWrite) else {return false}
      lastReport=now;return true
    }
    if shouldReport {report(.init(receivedBytes:totalBytesWritten,expectedBytes:totalBytesExpectedToWrite))}
  }
}
