import Foundation
import os

@testable import Talkify

/// A clock the tests advance by hand, following the precedent #82 named: a
/// deadline driven from a test asserts the deadline was honoured, where a
/// deadline raced against real time asserts only that the runner kept up.
///
/// Shared by every suite with a deadline in it — insertion, the quit-time
/// wait, and prompt shaping (#116) — because one driven clock against one
/// `DeadlineClock` seam is one thing to keep correct rather than three.
final class DrivenClock: Sendable {
  private struct Sleeper {
    let id: UUID
    let wakeAt: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct State {
    var now: Duration = .zero
    var sleepers: [Sleeper] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// Whether any sleep is currently suspended on this clock.
  var hasSleeper: Bool {
    state.withLock { !$0.sleepers.isEmpty }
  }

  /// Yields until a sleep is armed on this clock, so an advance lands on a
  /// deadline timer rather than into empty air before it starts waiting.
  ///
  /// An event wait, not a time bound: it costs nothing on a healthy run and
  /// hangs visibly on a broken one, which is the trade #82 was about. A bound
  /// here would be another number for a starved runner to blow.
  func waitForSleeper() async {
    while !hasSleeper {
      await Task.yield()
    }
  }

  /// Moves the clock forward and wakes every sleep the move satisfies.
  func advance(by duration: Duration) {
    let woken = state.withLock { state -> [Sleeper] in
      state.now += duration
      let now = state.now
      let due = state.sleepers.filter { $0.wakeAt <= now }
      state.sleepers.removeAll { $0.wakeAt <= now }
      return due
    }
    for sleeper in woken {
      sleeper.continuation.resume()
    }
  }

  /// The injectable boundary handed to the code under test.
  var deadlineClock: DeadlineClock {
    DeadlineClock(
      now: { [self] in state.withLock { $0.now } },
      sleep: { [self] in try await sleep(for: $0) }
    )
  }

  private func sleep(for duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        // The cancellation check shares the lock with the handler below, so
        // a cancel can never slip between checking and registering and leave
        // the sleep suspended forever.
        let cancelledBeforeRegistering = state.withLock { state -> Bool in
          guard !Task.isCancelled else { return true }
          state.sleepers.append(Sleeper(
            id: id,
            wakeAt: state.now + duration,
            continuation: continuation
          ))
          return false
        }
        if cancelledBeforeRegistering {
          continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      let cancelled = state.withLock { state -> Sleeper? in
        guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
          return nil
        }
        return state.sleepers.remove(at: index)
      }
      cancelled?.continuation.resume(throwing: CancellationError())
    }
  }
}
