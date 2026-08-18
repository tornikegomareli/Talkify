import Testing
@testable import Talkify

/// When Talkify is allowed to move the system volume and when it must leave it
/// alone. The device access is separate from these decisions, so none of this
/// needs a sound card.
@MainActor
struct AudioDuckingTests {
  @MainActor
  private final class FakeOutput {
    var volume: Float?
    var writes: [Float] = []

    func session() -> AudioDuckingSession {
      AudioDuckingSession(
        readVolume: { [self] in volume },
        writeVolume: { [self] value in
          volume = value
          writes.append(value)
          return true
        }
      )
    }
  }

  @Test func duckingLowersTheOutputAndRestoringPutsItBack() {
    let output = FakeOutput()
    output.volume = 0.8
    let session = output.session()

    session.duck(to: 0.25)
    #expect(output.volume == 0.2)
    #expect(session.isDucked)

    session.restore()
    #expect(output.volume == 0.8)
    #expect(!session.isDucked)
  }

  /// The rule the clipboard restore already follows: a value the user changed
  /// during the session is theirs, and must not be overwritten with a stale one.
  @Test func aVolumeChangedDuringTheSessionIsLeftAlone() {
    let output = FakeOutput()
    output.volume = 0.8
    let session = output.session()

    session.duck(to: 0.25)
    output.volume = 0.5

    session.restore()
    #expect(output.volume == 0.5)
    #expect(!session.isDucked)
  }

  /// Ducking twice would restore to an already-lowered volume, leaving the Mac
  /// quieter after every session than before it.
  @Test func duckingIsNotCumulative() {
    let output = FakeOutput()
    output.volume = 1.0
    let session = output.session()

    session.duck(to: 0.5)
    session.duck(to: 0.5)
    #expect(output.volume == 0.5)

    session.restore()
    #expect(output.volume == 1.0)
  }

  @Test func restoringWithoutDuckingChangesNothing() {
    let output = FakeOutput()
    output.volume = 0.4
    let session = output.session()

    session.restore()
    #expect(output.writes.isEmpty)
    #expect(output.volume == 0.4)
  }

  /// Silence needs no ducking, and ducking it would only put this in a
  /// position to restore over a change the user makes meanwhile.
  @Test func silenceIsNotDucked() {
    let output = FakeOutput()
    output.volume = 0
    let session = output.session()

    session.duck()
    #expect(!session.isDucked)
    #expect(output.writes.isEmpty)
  }

  /// A device with no settable volume, an aggregate or some HDMI outputs.
  @Test func anOutputWithNoVolumeControlIsNotDucked() {
    let session = AudioDuckingSession(readVolume: { nil }, writeVolume: { _ in false })
    session.duck()
    #expect(!session.isDucked)
    session.restore()
  }

  /// A write that fails leaves nothing to restore, rather than recording a
  /// duck that never happened and later stamping the old value back.
  @Test func aFailedWriteDoesNotCountAsDucked() {
    let session = AudioDuckingSession(readVolume: { 0.7 }, writeVolume: { _ in false })
    session.duck()
    #expect(!session.isDucked)
  }
}
