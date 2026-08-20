import Foundation
import Testing
@testable import Talkify

/// What keeps macOS from napping Talkify mid-session, and what makes sure it
/// stops keeping it awake afterwards. A stranded assertion is worse than the
/// bug it fixes: it disables App Nap for the rest of the run.
@MainActor
struct ActivityAssertionTests {
  @MainActor
  private final class Recorder {
    var begins: [(options: ProcessInfo.ActivityOptions, reason: String)] = []
    var ends = 0

    func assertion(reason: String = "test") -> ActivityAssertion {
      ActivityAssertion(
        reason: reason,
        begin: { [self] options, why in
          begins.append((options, why))
          return NSString(string: "token-\(begins.count)")
        },
        end: { [self] _ in ends += 1 }
      )
    }
  }

  @Test func holdingTakesOneAssertionAndReleasingGivesItBack() {
    let recorder = Recorder()
    let activity = recorder.assertion(reason: "Direct Dictation session")

    activity.hold()
    #expect(activity.isHeld)
    #expect(recorder.begins.count == 1)
    #expect(recorder.begins.first?.reason == "Direct Dictation session")

    activity.release()
    #expect(!activity.isHeld)
    #expect(recorder.ends == 1)
  }

  /// `.userInitiated` and not `.background`, which is the whole point: a
  /// background activity does not stop App Nap, and stopping App Nap is why
  /// this exists.
  ///
  /// Asserted as equality rather than `contains`, because these are not
  /// disjoint flags: `.userInitiated` is 0xffffff and `.background` is 0xff,
  /// so a userInitiated assertion "contains" background bitwise and a
  /// contains check would pass whatever was passed in.
  @Test func theAssertionSaysAPersonIsWaiting() {
    let recorder = Recorder()
    recorder.assertion().hold()
    #expect(recorder.begins.first?.options == .userInitiated)
  }

  /// A second hold would strand the first token, and a stranded token is an
  /// assertion nothing can ever release.
  @Test func holdingTwiceTakesOneAssertion() {
    let recorder = Recorder()
    let activity = recorder.assertion()

    activity.hold()
    activity.hold()
    activity.hold()

    #expect(recorder.begins.count == 1)
    activity.release()
    #expect(recorder.ends == 1)
    #expect(!activity.isHeld)
  }

  /// Release is called from several terminal paths that can overlap, so a
  /// second one must be silent rather than ending a token twice.
  @Test func releasingTwiceEndsOneAssertion() {
    let recorder = Recorder()
    let activity = recorder.assertion()

    activity.hold()
    activity.release()
    activity.release()

    #expect(recorder.ends == 1)
  }

  @Test func releasingWithoutHoldingDoesNothing() {
    let recorder = Recorder()
    recorder.assertion().release()
    #expect(recorder.ends == 0)
    #expect(recorder.begins.isEmpty)
  }

  /// A second session after a first has ended takes a fresh assertion, rather
  /// than quietly running unprotected because a flag was left set.
  @Test func aLaterSessionTakesItsOwnAssertion() {
    let recorder = Recorder()
    let activity = recorder.assertion()

    activity.hold()
    activity.release()
    activity.hold()

    #expect(recorder.begins.count == 2)
    #expect(activity.isHeld)
  }
}
