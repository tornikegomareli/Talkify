import AppKit

/// Injectable speech, insertion, permission, HUD, and usage boundaries for
/// Direct Dictation, following the TextInsertionService.Dependencies
/// template: a struct of closures with a live default, so the controller's
/// begin guards, outcome routing, and cancellation races can run against
/// fakes instead of a live microphone, Accessibility, and pasteboard.
extension DirectDictationController {
  struct Dependencies {
    // Speech recognition, wrapping the SpeechRecognitionService actor.
    let setDownloadHandler: @Sendable (
      @escaping @Sendable (SpeechRecognitionService.ModelDownload) -> Void
    ) async -> Void
    let resolveLocale: @Sendable (String?) async throws -> Locale
    let supportedLocale: @Sendable (String) async -> Locale?
    let retainOnly: @Sendable ([Locale]) async -> Void
    /// The words Apple Speech should expect, applied before anything warms.
    let setVocabulary: @Sendable ([String]) async -> Void
    let prewarm: @Sendable (Locale) async throws -> Void
    let startRecognition: @Sendable (
      Locale,
      _ updateHandler: @escaping @Sendable (SpeechRecognitionService.Update) -> Void,
      _ failureHandler: @escaping @Sendable (String) -> Void,
      _ levelHandler: @escaping @Sendable (Float) -> Void
    ) async throws -> Void
    let finishRecognition: @Sendable () async throws -> String
    let cancelRecognition: @Sendable () async -> Void
    let shutDownRecognition: @Sendable () async -> Void

    /// Translation, whole. A collaborator rather than a seam: it has its own
    /// seam one layer down, and Settings talks to it directly.
    let translation: TranslationCoordinator

    // Text insertion.
    let captureFocusedTarget: @MainActor () -> TextInsertionService.Target?
    let insertText: @MainActor (
      String, TextInsertionService.Target?, InsertionDestination
    ) async -> TextInsertionService.InsertionOutcome

    // Permissions and the dialogs that explain them.
    let requestMicrophoneAccess: @Sendable () async -> Bool
    let requestSpeechAccess: @Sendable () async -> Bool
    let requestAccessibilityAccess: @MainActor () -> Void
    let hasAccessibilityAccess: @MainActor () -> Bool
    let isPermissionAlertPresenting: @MainActor () -> Bool
    let showAccessibilitySetupAlert: @MainActor () -> Void
    let showRelaunchAlert: @MainActor () -> Void

    // The HUD surface dictation drives.
    let showListening: @MainActor (
      _ displayID: CGDirectDisplayID?,
      _ isLatched: Bool,
      _ settings: DictationSessionSettings,
      _ languageTag: String?
    ) -> Void
    let showLatched: @MainActor () -> Void
    let showLiveText: @MainActor (String) -> Void
    let showFinalizing: @MainActor () -> Void
    let showMessage: @MainActor (String, CGDirectDisplayID?) -> Void
    let showModelDownload: @MainActor (String?) -> Void
    let showAudioLevel: @MainActor (Float) -> Void
    let hideHUD: @MainActor () -> Void
    let playPasteSound: @MainActor () -> Void

    // Usage aggregation.
    let recordSession: @MainActor (
      _ wordCount: Int, _ speakingDuration: TimeInterval
    ) async -> Void

    // Transcription history, written only while its setting is on.
    let recordHistory: @Sendable (
      _ text: String,
      _ translation: DictationHistoryStore.Translation?,
      _ source: String?,
      _ folder: URL
    ) async -> Void

    /// Builds the production boundaries around the live services the
    /// controller previously constructed itself.
    @MainActor
    static func live(
      hudController: DictationHUDController,
      usageTracker: UsageTracker,
      textInsertionService: TextInsertionService
    ) -> Self {
      let speechService = SpeechRecognitionService()
      let historyStore = DictationHistoryStore()

      return Self(
        setDownloadHandler: { await speechService.setDownloadHandler($0) },
        resolveLocale: { try await speechService.resolveLocale(identifier: $0) },
        supportedLocale: { await speechService.supportedLocale(identifier: $0) },
        retainOnly: { await speechService.retainOnly(locales: $0) },
        setVocabulary: { await speechService.setVocabulary($0) },
        prewarm: { try await speechService.prewarm(locale: $0) },
        startRecognition: { locale, updateHandler, failureHandler, levelHandler in
          try await speechService.start(
            locale: locale,
            updateHandler: updateHandler,
            failureHandler: failureHandler,
            levelHandler: levelHandler
          )
        },
        finishRecognition: { try await speechService.finish() },
        cancelRecognition: { await speechService.cancel() },
        shutDownRecognition: { await speechService.shutDown() },
        translation: TranslationCoordinator(
          service: TranslationService(client: .live)
        ),
        captureFocusedTarget: { textInsertionService.captureFocusedTarget() },
        insertText: { await textInsertionService.insert($0, into: $1, destination: $2) },
        requestMicrophoneAccess: { await PermissionService.requestMicrophoneAccess() },
        requestSpeechAccess: { await PermissionService.requestSpeechAccess() },
        requestAccessibilityAccess: { PermissionService.requestAccessibilityAccess() },
        hasAccessibilityAccess: { PermissionService.hasAccessibilityAccess },
        isPermissionAlertPresenting: { PermissionAlert.isPresenting },
        showAccessibilitySetupAlert: { PermissionAlert.requestAccessibilitySetup() },
        showRelaunchAlert: { PermissionAlert.requestRelaunch() },
        showListening: { displayID, isLatched, settings, languageTag in
          hudController.showListening(
            on: displayID,
            isLatched: isLatched,
            settings: settings,
            languageTag: languageTag
          )
        },
        showLatched: { hudController.showLatched() },
        showLiveText: { hudController.showLiveText($0) },
        showFinalizing: { hudController.showFinalizing() },
        showMessage: { hudController.showMessage($0, on: $1) },
        showModelDownload: { hudController.showModelDownload($0) },
        showAudioLevel: { hudController.showAudioLevel($0) },
        hideHUD: { hudController.hide() },
        playPasteSound: { hudController.playPasteSound() },
        recordSession: {
          await usageTracker.recordSession(wordCount: $0, speakingDuration: $1)
        },
        recordHistory: { text, translation, source, folder in
          // A history write must never cost the session its insertion; a
          // full disk or revoked folder loses the entry, not the words.
          try? await historyStore.record(
            text,
            translation: translation,
            from: source,
            in: folder
          )
        }
      )
    }
  }
}
