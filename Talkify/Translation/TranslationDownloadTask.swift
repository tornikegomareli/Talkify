import SwiftUI
import Translation

/// Presents Apple's translation download sheet. A zero-size view, because of
/// where Apple put the download.
///
/// `TranslationSession(installedSource:target:)` is the only initializer, and
/// the name is the whole contract: it throws at once for a pair this Mac does
/// not already have, and never fetches anything. The only API that installs a
/// model is `.translationTask`, a View modifier, so a download needs a window.
/// Settings has one and the menu-bar session does not, which is why this lives
/// here and why every install starts in Settings.
///
/// The second and last file that imports Translation.
struct TranslationDownloadTask: View {
  /// The pair to install, or `nil` when nothing is downloading. Going from
  /// `nil` to a pair is what presents the sheet, so the same pair can be
  /// retried after a failure.
  let pair: TranslationPair?

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      // @Sendable is load-bearing: without it the closure inherits `body`'s
      // main-actor isolation, `session` comes out main-actor-isolated, and
      // awaiting its nonisolated `prepareTranslation()` is a data race.
      .translationTask(configuration) { @Sendable session in
        // Deliberately not awaited for completion. This call presents the
        // sheet and does not return when the download that sheet started
        // finishes, which left the spinner up until the app was relaunched.
        // Whoever asked for the install watches availability instead.
        try? await session.prepareTranslation()
      }
  }

  private var configuration: TranslationSession.Configuration? {
    guard let pair else { return nil }
    return TranslationSession.Configuration(source: pair.source, target: pair.target)
  }
}
