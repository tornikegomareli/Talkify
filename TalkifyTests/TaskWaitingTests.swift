import Foundation
import Testing
@testable import Talkify

/// What termination does with a dictation that is still being inserted. The
/// wait has to end when the insertion lands, end anyway if it wedges, and
/// never abort the insertion itself.
struct TaskWaitingTests {
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

  @Test func returnsAsSoonAsTheTaskFinishes() async {
    let task = Task { try? await Task.sleep(for: .milliseconds(20)) }
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
      await awaitValue(of: task, orGiveUpAfter: .seconds(10))
    }
    #expect(elapsed < .seconds(2), "waited \(elapsed) for a task that took 20ms")
  }

  @Test func givesUpWhenTheTaskOverrunsTheTimeout() async {
    let task = Task { try? await Task.sleep(for: .seconds(30)) }
    defer { task.cancel() }
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
      await awaitValue(of: task, orGiveUpAfter: .milliseconds(50))
    }
    #expect(elapsed < .seconds(5), "the timeout did not release the wait")
  }

  /// The point of giving up rather than cancelling: a wedged insertion still
  /// gets to finish if the process outlives the wait. Cancelling here would
  /// throw away the text the user just spoke.
  @Test func givingUpLeavesTheTaskRunning() async {
    let finished = Flag()
    let task = Task {
      try? await Task.sleep(for: .milliseconds(150))
      finished.set()
    }
    await awaitValue(of: task, orGiveUpAfter: .milliseconds(10))
    #expect(!task.isCancelled)

    await task.value
    #expect(finished.isSet)
  }
}
