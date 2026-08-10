import ApplicationServices
import AVFAudio
import Speech

enum PermissionService {
  static var hasAccessibilityAccess: Bool {
    AXIsProcessTrusted()
  }

  static var hasInputMonitoringAccess: Bool {
    CGPreflightListenEventAccess()
  }

  @discardableResult
  static func requestAccessibilityAccess() -> Bool {
    let options = [
      "AXTrustedCheckOptionPrompt": true,
    ] as CFDictionary

    return AXIsProcessTrustedWithOptions(options)
  }

  @discardableResult
  static func requestInputMonitoringAccess() -> Bool {
    CGRequestListenEventAccess()
  }

  static func requestMicrophoneAccess() async -> Bool {
    switch AVAudioApplication.shared.recordPermission {
    case .granted:
      return true
    case .denied:
      return false
    case .undetermined:
      return await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      }
    @unknown default:
      return false
    }
  }

  static func requestSpeechAccess() async -> Bool {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      return true
    case .denied, .restricted:
      return false
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
          continuation.resume(returning: status == .authorized)
        }
      }
    @unknown default:
      return false
    }
  }
}
