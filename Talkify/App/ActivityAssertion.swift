import Foundation

/// Keeps macOS from napping Talkify while something is actually happening.
///
/// Talkify is `LSUIElement` with no window on screen, which is exactly the
/// shape App Nap targets. After a few hours idle the process is throttled, and
/// the first thing to suffer is the HUD: every voice visual draws through
/// `TimelineView(.animation)`, whose clock App Nap slows right down. A session
/// then either animates wrongly or is over before its first frame lands (#77).
///
/// Held only for the length of a session or a file job, never while idle. An
/// assertion that lasted all day would trade a rare glitch for a permanent
/// battery cost, which is the wrong way round.
@MainActor
final class ActivityAssertion {
  private let reason: String
  private let begin: (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol
  private let end: (NSObjectProtocol) -> Void
  private var token: NSObjectProtocol?

  init(
    reason: String,
    begin: @escaping (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol
      = { ProcessInfo.processInfo.beginActivity(options: $0, reason: $1) },
    end: @escaping (NSObjectProtocol) -> Void
      = { ProcessInfo.processInfo.endActivity($0) }
  ) {
    self.reason = reason
    self.begin = begin
    self.end = end
  }

  var isHeld: Bool { token != nil }

  /// Idempotent: a second begin would strand the first token, and a stranded
  /// token is an assertion nothing can ever release.
  func hold() {
    guard token == nil else { return }
    token = begin(.userInitiated, reason)
  }

  func release() {
    guard let token else { return }
    end(token)
    self.token = nil
  }

  // No deinit release: the token is MainActor-isolated and deinit is not, and
  // the only owners are controllers that live as long as the app. Every path
  // that holds one also releases it.
}
