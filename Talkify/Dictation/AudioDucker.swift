import CoreAudio
import Foundation

/// Lowers the system output while a Direct Dictation session listens, and puts
/// it back afterwards.
///
/// macOS has no per-application ducking. `kAudioSessionProperty_Other`
/// `MixableAudioShouldDuck`, which is how this is done on iOS, is
/// `API_UNAVAILABLE(macos)`, and nothing has replaced it. What is available is
/// an output device's own volume, so that is what moves. The cost is that it
/// moves for everything, Talkify's own session sounds included, which is why
/// the ducking starts after the Begin sound and ends before the End one.
///
/// Restoring is guarded the way the clipboard restore is: if the volume is no
/// longer the value this type set, the user moved it during the session and
/// their number wins. Better to leave the volume alone than to overwrite a
/// deliberate change with a stale one.
struct AudioDucker {
  /// What the output drops to while listening, as a fraction of where it was.
  static let duckedFraction: Float = 0.2

  /// The default output right now. Only read when a duck begins: the device is
  /// then remembered, because the default can change mid-session and the
  /// volume that needs putting back belongs to the device that was lowered.
  static func defaultOutputDevice() -> AudioDeviceID? {
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

  private static func volumeAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  /// A device with no settable main volume, an aggregate or some HDMI outputs,
  /// answers nil and simply does not duck.
  static func volume(of device: AudioDeviceID) -> Float? {
    var address = volumeAddress()
    guard AudioObjectHasProperty(device, &address) else { return nil }
    var value = Float(0)
    var size = UInt32(MemoryLayout<Float>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
      return nil
    }
    return value
  }

  @discardableResult
  static func setVolume(_ value: Float, of device: AudioDeviceID) -> Bool {
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

/// Holds the one duck in flight. Separate from the device access above so the
/// decisions — when to duck, when to leave the volume alone — can be tested
/// without a sound card.
@MainActor
final class AudioDuckingSession {
  /// The device that was lowered, the volume it had, and what this type set it
  /// to. The device is remembered because the default output can change during
  /// a session: restoring against whatever is default at the end would read a
  /// volume this type never set, decline to touch it, and leave the device it
  /// actually lowered quiet.
  private var ducked: (device: AudioDeviceID, original: Float, applied: Float)?

  private let defaultDevice: () -> AudioDeviceID?
  private let readVolume: (AudioDeviceID) -> Float?
  private let writeVolume: (AudioDeviceID, Float) -> Bool

  init(
    defaultDevice: @escaping () -> AudioDeviceID? = AudioDucker.defaultOutputDevice,
    readVolume: @escaping (AudioDeviceID) -> Float? = AudioDucker.volume(of:),
    writeVolume: @escaping (AudioDeviceID, Float) -> Bool = { device, value in
      AudioDucker.setVolume(value, of: device)
    }
  ) {
    self.defaultDevice = defaultDevice
    self.readVolume = readVolume
    self.writeVolume = writeVolume
  }

  var isDucked: Bool { ducked != nil }

  func duck(to fraction: Float = AudioDucker.duckedFraction) {
    // Already ducked: a second session must not stack, or restoring would put
    // back a volume that was itself already lowered.
    guard ducked == nil,
       let device = defaultDevice(),
       let current = readVolume(device)
    else {
      return
    }
    // Nothing playing loudly enough to be in the way, and ducking silence
    // only risks restoring over a change the user makes meanwhile.
    guard current > 0 else { return }

    let target = current * fraction
    guard writeVolume(device, target) else { return }
    ducked = (device: device, original: current, applied: target)
  }

  func restore() {
    guard let ducked else { return }
    self.ducked = nil
    // The user reached for the volume during the session, so their number
    // wins. Same rule as the clipboard restore: never overwrite a deliberate
    // change with a stale one. Read from the device that was lowered, not from
    // whatever is default now.
    guard let current = readVolume(ducked.device),
       abs(current - ducked.applied) < 0.001
    else {
      return
    }
    _ = writeVolume(ducked.device, ducked.original)
  }
}
