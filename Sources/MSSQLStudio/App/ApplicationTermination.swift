import AppKit

/// Keep Swift async persistence on the regular application loop. terminateLater
/// enters AppKit's modal loop, which does not service the MainActor task queue.
@MainActor final class ApplicationTermination {
  private(set) var preparing=false
  private var approved=false
  func consumeApproval()->Bool {
    guard approved else {return false}
    approved=false;return true
  }
  func prepare(flush:@escaping () async -> Bool,
               discardHistory:@escaping ()->Bool,
               mayTerminate:@escaping ()->Bool,
               terminate:@escaping ()->Void,
               cancelled:@escaping ()->Void) {
    guard !preparing else {return}
    preparing=true
    Task { @MainActor in
      let saved=await flush()
      let allowed=saved || discardHistory()
      preparing=false
      guard allowed,mayTerminate() else {cancelled();return}
      approved=true
      terminate()
      // If another native delegate vetoed termination, do not retain approval.
      approved=false
    }
  }
}
