import Foundation

/// The speech surface `DirectDictationController` drives.
///
/// Everything hard about the controller is its task lifecycle: a start being
/// cancelled while it is still building, a finish landing after teardown, a
/// failure arriving mid-session. None of that could be tested, because the
/// controller reached straight for a `SpeechRecognitionService` that wants a
/// microphone and an on-device model.
///
/// This is the same seam `TextInsertionService.Dependencies` already provides
/// for the clipboard, which is what let the insertion races be pinned without
/// a real pasteboard (ADR-0005 leaves the impure half to the controller; it
/// does not say the impure half has to be untestable).
protocol SpeechRecognizing: Actor {
  func setDownloadHandler(
    _ handler: @escaping @Sendable (SpeechRecognitionService.ModelDownload) -> Void
  )
  func resolveLocale(identifier: String?) async throws -> Locale
  func supportedLocale(identifier: String) async -> Locale?
  func prewarm(locale: Locale) async throws
  func retainOnly(locales: [Locale]) async
  func start(
    locale: Locale,
    updateHandler: @escaping @Sendable (SpeechRecognitionService.Update) -> Void,
    failureHandler: @escaping @Sendable (String) -> Void,
    levelHandler: (@Sendable (Float) -> Void)?
  ) async throws
  func finish() async throws -> String
  func cancel() async
  func shutDown() async
}

extension SpeechRecognitionService: SpeechRecognizing {}
