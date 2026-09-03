import Foundation

/// The monotonic time source behind the dictation path's deadlines.
///
/// Injectable because against the wall clock a timeout test is really an
/// assertion that the runner was fast enough, which a loaded CI machine fails
/// and a re-run passes (#82, #116). A test drives this clock by hand, so a
/// timeout asserts the deadline was honoured rather than that the machine kept
/// up.
///
/// One clock for all three deadlines — the clipboard snapshot, the copy wait,
/// the quit-time insertion wait and the shaping timeout — rather than one per
/// caller. They are the same mechanism racing a `Task.sleep`, and a second
/// near-identical seam would only mean a second fake to keep in step.
struct DeadlineClock: Sendable {
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
