import CoreGraphics
import Testing

@testable import Talkify

/// Compact and Edge Glow + Draft are built around the live draft, so they
/// open with nothing. Three separate paths write the placeholder — opening,
/// latching, and coming back from a model download — and fixing only the
/// first left "Listening (latched)" still appearing.
@MainActor
@Suite("HUD placeholder text")
struct HUDPlaceholderTests {
  private func controller(_ visual: HUDVoiceVisualStyle) -> DictationHUDController {
    let store = AppSettings.previewStore()
    store.voiceVisual = visual
    return DictationHUDController(stage: HUDStage(settings: store), settings: store)
  }

  private func session(_ store: AppSettings) -> DictationSessionSettings {
    store.sessionSettings
  }

  private func recentDraft(_ stage: HUDStage, visual: HUDVoiceVisualStyle) -> Bool {
    DictationHUDShellView.showsRecentDraft(
      visual: visual,
      listening: stage.dictationContent.showsVoiceVisual,
      dismissing: stage.dictationContent.isDismissing,
      shaping: stage.dictationContent.shapingName != nil,
      reduceMotion: false
    )
  }

  @Test(arguments: [HUDVoiceVisualStyle.compact, .glowDraft])
  func aDraftVisualOpensWithNoText(visual: HUDVoiceVisualStyle) {
    let store = AppSettings.previewStore()
    store.voiceVisual = visual
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: false, settings: session(store))
    #expect(hud.textForTesting.isEmpty)

    hud.showLatched()
    #expect(hud.textForTesting.isEmpty)

    hud.showModelDownload(nil)
    #expect(hud.textForTesting.isEmpty)
  }

  /// A latched draft visual still says nothing, which is the case that was
  /// reported after the opening text was already handled.
  @Test(arguments: [HUDVoiceVisualStyle.compact, .glowDraft])
  func aDraftVisualLatchesWithNoText(visual: HUDVoiceVisualStyle) {
    let store = AppSettings.previewStore()
    store.voiceVisual = visual
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: true, settings: session(store))
    #expect(hud.textForTesting.isEmpty)
  }

  /// The other visuals replace the draft while listening, so their band is the
  /// only place a session can say what it is doing.
  @Test(arguments: [HUDVoiceVisualStyle.waveform, .glow])
  func theOtherVisualsStillSayWhatTheyAreDoing(visual: HUDVoiceVisualStyle) {
    let store = AppSettings.previewStore()
    store.voiceVisual = visual
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: false, settings: session(store))
    #expect(hud.textForTesting == "Listening…")

    hud.showLatched()
    #expect(hud.textForTesting == "Listening (latched)")
  }

  /// The shaping phase is the fourth path, and the one that clears rather
  /// than writes: the caption under it says what is happening, so a
  /// placeholder above it claims a session is still listening when it has
  /// already stopped.
  @Test(arguments: [true, false])
  func theShapingPhaseClearsTheListeningPlaceholder(isLatched: Bool) {
    let store = AppSettings.previewStore()
    store.voiceVisual = .waveform
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: isLatched, settings: session(store))
    if isLatched { hud.showLatched() }
    #expect(!hud.textForTesting.isEmpty)

    hud.showShaping(with: "Tighten grammar")
    #expect(hud.textForTesting.isEmpty)
  }

  /// The clear in showShaping only beats the writers that ran before it. A
  /// model download finishing mid-session reports nil, which restored the
  /// placeholder under the shaping caption — and the same hole is open to
  /// every other path that asks for one.
  @Test func nothingRestoresThePlaceholderAfterSpeechEnds() {
    let store = AppSettings.previewStore()
    store.voiceVisual = .waveform
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: true, settings: session(store))
    hud.showLatched()
    #expect(hud.textForTesting == "Listening (latched)")

    hud.showFinalizing()
    hud.showShaping(with: "Tighten grammar")
    #expect(hud.textForTesting.isEmpty)

    hud.showModelDownload(nil)
    #expect(hud.textForTesting.isEmpty, "the placeholder came back after the session stopped listening")
  }

  /// The next session opens with one again, so the rule above cannot leak
  /// into it.
  @Test func theNextSessionStillOpensWithAPlaceholder() {
    let store = AppSettings.previewStore()
    store.voiceVisual = .waveform
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: false, settings: session(store))
    hud.showFinalizing()
    hud.showShaping(with: "Tighten grammar")
    #expect(hud.textForTesting.isEmpty)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: false, settings: session(store))
    #expect(hud.textForTesting == "Listening…")
  }

  /// The words being rewritten are not a placeholder, so the shaping phase
  /// leaves them where they are.
  @Test func theShapingPhaseKeepsARealDraft() {
    let store = AppSettings.previewStore()
    store.voiceVisual = .waveform
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: false, settings: session(store))
    hud.showLiveText("the words it is rewriting")
    hud.showShaping(with: "Tighten grammar")
    #expect(hud.textForTesting == "the words it is rewriting")
  }

  /// A real draft always shows, whichever visual is selected.
  @Test func aLiveDraftIsNeverSuppressed() {
    let store = AppSettings.previewStore()
    store.voiceVisual = .compact
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: false, settings: session(store))
    hud.showLiveText("hello there")
    #expect(hud.textForTesting == "hello there")
  }

  @Test func aVolatileGuessShowsBeforeItCommits() {
    let store = AppSettings.previewStore()
    store.voiceVisual = .glowDraft
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: false, settings: session(store))
    hud.showLiveText("hello ", volatile: "ther")
    #expect(hud.textForTesting == "hello ther")
  }

  @Test func aStatusMessageDoesNotKeepThePreviousGuess() {
    let store = AppSettings.previewStore()
    store.voiceVisual = .glowDraft
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: false, settings: session(store))
    hud.showLiveText("hello ", volatile: "ther")
    hud.showMessage("Couldn't insert text")
    #expect(hud.textForTesting == "Couldn't insert text")
  }

  /// hide() pins the layout for the retract, then an insert failure claims
  /// the shape for a message. That message is a new occupant: the recent
  /// draft stays through shaping and the retract, and leaves with the
  /// status line.
  @Test func aStatusMessageDoesNotKeepTheRecentDraft() {
    let store = AppSettings.previewStore()
    store.voiceVisual = .glowDraft
    let stage = HUDStage(settings: store)
    let hud = DictationHUDController(stage: stage, settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: false, settings: session(store))
    hud.showLiveText("the words it is rewriting")
    hud.showShaping(with: "Tighten grammar")
    #expect(recentDraft(stage, visual: .glowDraft))

    hud.hide()
    #expect(stage.dictationContent.isDismissing)
    #expect(recentDraft(stage, visual: .glowDraft))

    hud.showMessage("Couldn't insert text")
    #expect(!stage.dictationContent.isDismissing)
    #expect(stage.dictationContent.shapingName == nil)
    #expect(!recentDraft(stage, visual: .glowDraft))
    #expect(hud.textForTesting == "Couldn't insert text")
  }
}
