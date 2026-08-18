import CoreFoundation
import Testing
@testable import Talkify

/// Pins the shell's band decisions. The rule that hid the held draft
/// during a replacement round once lived only as private view properties,
/// so the review-context rules are computed in a pure value and locked
/// here without a window.
struct DictationBandLayoutTests {
  private func layout(
    listening: Bool,
    dismissing: Bool = false,
    reviewing: Bool = false,
    reduceMotion: Bool = false,
    visual: HUDVoiceVisualStyle = .waveform
  ) -> DictationBandLayout {
    DictationBandLayout(
      showsVoiceVisual: listening,
      isDismissing: dismissing,
      isReviewing: reviewing,
      reduceMotion: reduceMotion,
      voiceVisual: visual,
      levelMeterBandHeight: 24,
      waveBandHeight: 64
    )
  }

  @Test func ordinaryWaveformListeningReplacesTheDraftAsBefore() {
    let band = layout(listening: true)
    #expect(band.visualBandHeight == 64)
    #expect(!band.showsTextBand)
    #expect(!band.showsCompactBand)
    #expect(!band.isReplacementRoundListening)
  }

  @Test func ordinaryCompactListeningShowsTheDraftBesideItsIndicator() {
    let band = layout(listening: true, visual: .compact)
    #expect(band.visualBandHeight == 0)
    #expect(band.showsTextBand)
    #expect(band.showsCompactBand)
  }

  @Test func reduceMotionShowsTheDraftAndLevelMeter() {
    let band = layout(listening: true, reduceMotion: true)
    #expect(band.visualBandHeight == 24)
    #expect(band.showsTextBand)
    #expect(!band.showsCompactBand)
  }

  @Test func idleShowsTheTextBandAlone() {
    let band = layout(listening: false)
    #expect(band.visualBandHeight == 0)
    #expect(band.showsTextBand)
    #expect(!band.showsCompactBand)
  }

  @Test func reviewKeepsTheTextBandWhileListening() {
    // The reported bug: a replacement round hid the held draft for every
    // non-Compact visual. While reviewing, text must stay even listening.
    let band = layout(listening: true, reviewing: true)
    #expect(band.showsTextBand)
    #expect(band.isReplacementRoundListening)
    // And the voice visual must not take over: no waveform band, just the
    // compact indicator beside the text.
    #expect(band.visualBandHeight == 0)
    #expect(band.showsCompactBand)
  }

  @Test func reviewKeepsTheTextBandForCompactWhileListening() {
    let band = layout(listening: true, reviewing: true, visual: .compact)
    #expect(band.showsTextBand)
    #expect(band.visualBandHeight == 0)
    #expect(band.showsCompactBand)
  }

  @Test func reviewUnderReduceMotionKeepsPlainTextWhileListening() {
    let band = layout(listening: true, reviewing: true, reduceMotion: true)
    #expect(band.showsTextBand)
    #expect(band.visualBandHeight == 0)
    #expect(!band.showsCompactBand)
    #expect(band.isReplacementRoundListening)
  }

  @Test func settledReviewShowsTheTextBandWithoutTheIndicator() {
    let band = layout(listening: false, reviewing: true)
    #expect(band.showsTextBand)
    #expect(band.visualBandHeight == 0)
    #expect(!band.showsCompactBand)
    #expect(!band.isReplacementRoundListening)
  }

  @Test func dismissingKeepsTheLaidOutBands() {
    let band = layout(listening: true, dismissing: true)
    #expect(band.keepsVisualLayout)
  }
}
