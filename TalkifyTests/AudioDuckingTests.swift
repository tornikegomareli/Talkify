import CoreAudio
import Testing
@testable import Talkify

/// When Talkify is allowed to move an output's volume and when it must leave it
/// alone. The device access is separate from these decisions, so none of this
/// needs a sound card.
@MainActor
struct AudioDuckingTests {
  /// A pretend set of output devices, with one of them current.
  @MainActor
  private final class FakeAudio {
    var volumes: [AudioDeviceID: Float] = [:]
    var current: AudioDeviceID?
    var writes: [(device: AudioDeviceID, value: Float)] = []
    /// Devices that report no settable volume: aggregates, some HDMI outputs.
    var unsettable: Set<AudioDeviceID> = []

    func session() -> AudioDuckingSession {
      AudioDuckingSession(
        defaultDevice: { [self] in current },
        readVolume: { [self] device in volumes[device] },
        writeVolume: { [self] device, value in
          guard !unsettable.contains(device) else { return false }
          volumes[device] = value
          writes.append((device, value))
          return true
        }
      )
    }
  }

  private let speakers: AudioDeviceID = 1
  private let airPods: AudioDeviceID = 2

  @Test func duckingLowersTheOutputAndRestoringPutsItBack() {
    let audio = FakeAudio()
    audio.volumes = [speakers: 0.8]
    audio.current = speakers
    let session = audio.session()

    session.duck(to: 0.25)
    #expect(audio.volumes[speakers] == 0.2)
    #expect(session.isDucked)

    session.restore()
    #expect(audio.volumes[speakers] == 0.8)
    #expect(!session.isDucked)
  }

  /// The rule the clipboard restore already follows: a value the user changed
  /// during the session is theirs, and must not be overwritten with a stale one.
  @Test func aVolumeChangedDuringTheSessionIsLeftAlone() {
    let audio = FakeAudio()
    audio.volumes = [speakers: 0.8]
    audio.current = speakers
    let session = audio.session()

    session.duck(to: 0.25)
    audio.volumes[speakers] = 0.5

    session.restore()
    #expect(audio.volumes[speakers] == 0.5)
    #expect(!session.isDucked)
  }

  /// The regression: AirPods connecting mid-sentence makes them the default
  /// output, and restoring against the new default read a volume Talkify never
  /// set, declined to touch it, and left the speakers quiet.
  @Test func theDeviceThatWasLoweredIsTheOneRestored() {
    let audio = FakeAudio()
    audio.volumes = [speakers: 1.0, airPods: 0.5]
    audio.current = speakers
    let session = audio.session()

    session.duck(to: 0.2)
    #expect(audio.volumes[speakers] == 0.2)

    // AirPods connect and become the default output mid-session.
    audio.current = airPods

    session.restore()
    #expect(audio.volumes[speakers] == 1.0, "the lowered device was left quiet")
    #expect(audio.volumes[airPods] == 0.5, "an untouched device must stay untouched")
  }

  /// Ducking twice would restore to an already-lowered volume, leaving the Mac
  /// quieter after every session than before it.
  @Test func duckingIsNotCumulative() {
    let audio = FakeAudio()
    audio.volumes = [speakers: 1.0]
    audio.current = speakers
    let session = audio.session()

    session.duck(to: 0.5)
    session.duck(to: 0.5)
    #expect(audio.volumes[speakers] == 0.5)

    session.restore()
    #expect(audio.volumes[speakers] == 1.0)
  }

  @Test func restoringWithoutDuckingChangesNothing() {
    let audio = FakeAudio()
    audio.volumes = [speakers: 0.4]
    audio.current = speakers
    let session = audio.session()

    session.restore()
    #expect(audio.writes.isEmpty)
    #expect(audio.volumes[speakers] == 0.4)
  }

  /// Silence needs no ducking, and ducking it would only put this in a
  /// position to restore over a change the user makes meanwhile.
  @Test func silenceIsNotDucked() {
    let audio = FakeAudio()
    audio.volumes = [speakers: 0]
    audio.current = speakers
    let session = audio.session()

    session.duck()
    #expect(!session.isDucked)
    #expect(audio.writes.isEmpty)
  }

  /// A device with no settable volume, an aggregate or some HDMI outputs.
  @Test func anOutputWithNoVolumeControlIsNotDucked() {
    let audio = FakeAudio()
    audio.current = speakers
    let session = audio.session()

    session.duck()
    #expect(!session.isDucked)
    session.restore()
    #expect(audio.writes.isEmpty)
  }

  /// A write that fails leaves nothing to restore, rather than recording a
  /// duck that never happened and later stamping the old value back.
  @Test func aFailedWriteDoesNotCountAsDucked() {
    let audio = FakeAudio()
    audio.volumes = [speakers: 0.7]
    audio.current = speakers
    audio.unsettable = [speakers]
    let session = audio.session()

    session.duck()
    #expect(!session.isDucked)
  }

  /// No output at all, which is what a Mac with every device removed reports.
  @Test func noDefaultOutputIsNotDucked() {
    let audio = FakeAudio()
    let session = audio.session()

    session.duck()
    #expect(!session.isDucked)
  }
}
