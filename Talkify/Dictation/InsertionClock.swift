import Foundation

/// The monotonic time source behind the insertion service's deadlines.
///
/// Injectable for the same reason `awaitValue(of:orGiveUpAfter:)` keeps its
/// waiters seam-shaped: against the wall clock, a snapshot test's 100ms budget
/// is really an assertion that the runner was fast enough, which a loaded CI
/// machine fails and a re-run passes (#82). A test drives this clock by hand,
/// so a timeout asserts the deadline was honoured rather than that the
/// machine kept up.
struct InsertionClock: Sendable {
  /// Monotonic time elapsed since this clock's own fixed origin.
  let now: @Sendable () -> Duration
  /// Suspends for `duration` of this clock's time, throwing when the
  /// sleeping task is cancelled, exactly as `Task.sleep(for:)` does.
  let sleep: @Sendable (Duration) async throws -> Void

  /// The production clock: real time, anchored when the dependencies are built.
  static var continuous: Self {
    let origin = ContinuousClock.now
    return Self(
      now: { origin.duration(to: ContinuousClock.now) },
      sleep: { try await Task.sleep(for: $0) }
    )
  }
}
