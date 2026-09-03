import Foundation
import Testing
@testable import Talkify

/// What termination does with a dictation that is still being inserted. The
/// wait has to end when the insertion lands, end anyway if it wedges, and
/// never abort the insertion itself.
struct TaskWaitingTests {
  /// A one-shot gate, so a task can be held open and released on demand
  /// rather than by sleeping for long enough.
  private final class Gate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func open() {
      semaphore.signal()
    }

    func wait() async {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async { [semaphore] in
          semaphore.wait()
          continuation.resume()
        }
      }
    }
  }

  private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
      lock.lock()
      value = true
      lock.unlock()
    }

    var isSet: Bool {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  /// The finished task releases the wait, and nothing else does: the clock is
  /// never advanced, so the deadline armed on it can never elapse.
  ///
  /// The waiter reports whether the task had finished at the moment the wait
  /// returned, which is the assertion that has teeth. Asserting the flag after
  /// the wait instead passes whether or not the wait waited, because a task
  /// this small usually finishes on its own first — that is how the version
  /// this replaces passed, on top of asserting the runner got through a 20ms
  /// task inside two seconds (#116).
  @Test func returnsAsSoonAsTheTaskFinishes() async {
    let clock = DrivenClock()
    let release = Gate()
    let finished = Flag()
    let task = Task {
      await release.wait()
      finished.set()
    }

    let waiter = Task {
      await awaitValue(of: task, orGiveUpAfter: .seconds(10), on: clock.deadlineClock)
      return finished.isSet
    }
    // The armed deadline proves the waiter is inside the wait, so releasing
    // the task cannot race it there.
    await clock.waitForSleeper()
    release.open()

    #expect(await waiter.value, "the wait returned before the task finished")
  }

  /// The timeout releases a wait whose task never finishes. Driving the clock
  /// past the deadline is what proves it, where a real 50ms timer only proved
  /// the machine noticed in time.
  @Test func givesUpWhenTheTaskOverrunsTheTimeout() async {
    let clock = DrivenClock()
    let task = Task { try? await Task.sleep(for: .seconds(30)) }
    defer { task.cancel() }

    let waiter = Task {
      await awaitValue(of: task, orGiveUpAfter: .milliseconds(50), on: clock.deadlineClock)
    }
    await clock.waitForSleeper()
    clock.advance(by: .milliseconds(50))

    await waiter.value
    #expect(!task.isCancelled, "giving up must not cancel the insertion")
  }

  /// The point of giving up rather than cancelling: a wedged insertion still
  /// gets to finish if the process outlives the wait. Cancelling here would
  /// throw away the text the user just spoke.
  @Test func givingUpLeavesTheTaskRunning() async {
    let clock = DrivenClock()
    let release = Gate()
    let finished = Flag()
    let task = Task {
      await release.wait()
      finished.set()
    }

    let waiter = Task {
      await awaitValue(of: task, orGiveUpAfter: .milliseconds(10), on: clock.deadlineClock)
    }
    await clock.waitForSleeper()
    clock.advance(by: .milliseconds(10))
    await waiter.value
    #expect(!task.isCancelled)

    // Still runnable after the wait gave up on it, which is the whole point:
    // cancelling here would throw away the text the user just spoke.
    release.open()
    await task.value
    #expect(finished.isSet)
  }
}
