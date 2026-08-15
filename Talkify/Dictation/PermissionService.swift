import ApplicationServices
import AVFAudio
import Speech

enum PermissionService {
  static var hasAccessibilityAccess: Bool {
    AXIsProcessTrusted()
  }

  /// Asks macOS to show its Accessibility prompt, at most once per launch.
  ///
  /// `AXIsProcessTrustedWithOptions` puts a system dialog on screen every time
  /// it is called with the prompt option, and this used to run on every trigger
  /// press while untrusted — so holding the key three times produced three
  /// dialogs. Talkify explains the situation in its own dialog instead.
  @discardableResult
  static func requestAccessibilityAccess() -> Bool {
    if hasPromptedForAccessibility {
      return AXIsProcessTrusted()
    }
    hasPromptedForAccessibility = true

    let options = [
      "AXTrustedCheckOptionPrompt": true,
    ] as CFDictionary

    return AXIsProcessTrustedWithOptions(options)
  }

  nonisolated(unsafe) private static var hasPromptedForAccessibility = false

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
