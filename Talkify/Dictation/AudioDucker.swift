import CoreAudio
import Foundation

/// Lowers the system output while a Direct Dictation session listens, and puts
/// it back afterwards.
///
/// macOS has no per-application ducking. `kAudioSessionProperty_Other`
/// `MixableAudioShouldDuck`, which is how this is done on iOS, is
/// `API_UNAVAILABLE(macos)`, and nothing has replaced it. What is available is
/// the default output device's own volume, so that is what moves. The cost is
/// that it moves for everything, Talkify's own session sounds included, which
/// is why the ducking starts after the Begin sound and ends before the End one.
///
/// Restoring is guarded the way the clipboard restore is: if the volume is no
/// longer the value this type set, the user moved it during the session and
/// their number wins. Better to leave the volume alone than to overwrite a
/// deliberate change with a stale one.
struct AudioDucker {
  /// What the output drops to while listening, as a fraction of where it was.
  static let duckedFraction: Float = 0.2

  /// A device with no settable main volume, an aggregate or some HDMI outputs,
  /// simply does not duck.
  private var device: AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )
    guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
    return deviceID
  }

  private func volumeAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  func volume() -> Float? {
    guard let device else { return nil }
    var address = volumeAddress()
    guard AudioObjectHasProperty(device, &address) else { return nil }
    var value = Float(0)
    var size = UInt32(MemoryLayout<Float>.size)
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
    guard status == noErr else { return nil }
    return value
  }

  @discardableResult
  func setVolume(_ value: Float) -> Bool {
    guard let device else { return false }
    var address = volumeAddress()
    guard AudioObjectHasProperty(device, &address) else { return false }
    var settable = DarwinBoolean(false)
    guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
       settable.boolValue
    else {
      return false
    }
    var value = max(0, min(1, value))
    let size = UInt32(MemoryLayout<Float>.size)
    return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
  }
}

/// Holds the one duck in flight. Separate from the pure device access above so
/// the decisions — when to duck, when to leave the volume alone — can be
/// tested without a sound card.
@MainActor
final class AudioDuckingSession {
  /// The volume before ducking, and what this type set it to. Both are needed:
  /// the first to restore, the second to notice the user moving it in between.
  private var original: Float?
  private var applied: Float?

  private let readVolume: () -> Float?
  private let writeVolume: (Float) -> Bool

  init(
    readVolume: @escaping () -> Float? = { AudioDucker().volume() },
    writeVolume: @escaping (Float) -> Bool = { AudioDucker().setVolume($0) }
  ) {
    self.readVolume = readVolume
    self.writeVolume = writeVolume
  }

  var isDucked: Bool { original != nil }

  func duck(to fraction: Float = AudioDucker.duckedFraction) {
    // Already ducked: a second session must not stack, or restoring would put
    // back a volume that was itself already lowered.
    guard original == nil, let current = readVolume() else { return }
    // Nothing playing loudly enough to be in the way, and ducking silence
    // only risks restoring over a change the user makes meanwhile.
    guard current > 0 else { return }

    let target = current * fraction
    guard writeVolume(target) else { return }
    original = current
    applied = target
  }

  func restore() {
    defer {
      original = nil
      applied = nil
    }
    guard let original, let applied else { return }
    // The user reached for the volume during the session, so their number
    // wins. Same rule as the clipboard restore: never overwrite a deliberate
    // change with a stale one.
    guard let current = readVolume(), abs(current - applied) < 0.001 else { return }
    _ = writeVolume(original)
  }
}
