import CoreGraphics
import Testing

@testable import Talkify

/// Compact is built around the live draft, so it opens with nothing. Three
/// separate paths write the placeholder — opening, latching, and coming back
/// from a model download — and fixing only the first left "Listening (latched)"
/// still appearing.
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

  @Test func compactOpensWithNoText() {
    let store = AppSettings.previewStore()
    store.voiceVisual = .compact
    let hud = DictationHUDController(stage: HUDStage(settings: store), settings: store)

    hud.showListening(on: CGDirectDisplayID?.none, isLatched: false, settings: session(store))
    #expect(hud.textForTesting.isEmpty)

    hud.showLatched()
    #expect(hud.textForTesting.isEmpty)

    hud.showModelDownload(nil)
    #expect(hud.textForTesting.isEmpty)
  }

  /// A latched Compact session still says nothing, which is the case that was
  /// reported after the opening text was already handled.
  @Test func compactLatchesWithNoText() {
    let store = AppSettings.previewStore()
    store.voiceVisual = .compact
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
}
