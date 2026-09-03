import Foundation
import Synchronization

/// Resumes its continuation once, whichever waiter gets there first.
private final class FirstPastThePost: Sendable {
  private let continuation: CheckedContinuation<Void, Never>
  private let hasResumed = Mutex(false)

  init(_ continuation: CheckedContinuation<Void, Never>) {
    self.continuation = continuation
  }

  func resume() {
    let isFirst = hasResumed.withLock { resumed in
      guard !resumed else { return false }
      resumed = true
      return true
    }
    if isFirst { continuation.resume() }
  }
}

/// Waits for `task` to finish, giving up after `timeout`.
///
/// Giving up stops the waiting, not the task: the caller is termination,
/// which wants to hold the quit open for a moment but must not hold it open
/// forever if an insertion is wedged. Cancelling the task instead would drop
/// the text it is in the middle of inserting, which is the outcome the wait
/// exists to avoid.
///
/// The two waiters are unstructured on purpose. `await task.value` ignores the
/// cancellation of whoever is awaiting it, so a task group would refuse to
/// return until the task itself ended and the timeout would never release.
///
/// The clock is a seam so a test can drive the giving up rather than wait for
/// it: against real time, asserting this returns promptly asserts the runner
/// was fast enough (#116).
func awaitValue<Success: Sendable>(
  of task: Task<Success, Never>,
  orGiveUpAfter timeout: Duration,
  on clock: DeadlineClock = .continuous
) async {
  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    let post = FirstPastThePost(continuation)
    Task {
      _ = await task.value
      post.resume()
    }
    Task {
      try? await clock.sleep(timeout)
      post.resume()
    }
  }
}
