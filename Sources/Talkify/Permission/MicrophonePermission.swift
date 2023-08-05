//
//  MicrophonePermission.swift
//
//
//  Created by Tornike on 05/08/2023.
//

import Foundation
import AVFAudio

/// A struct representing a microphone permission provider.
///
/// `MicrophonePermission` conforms to the `PermissionProvider` protocol and provides
/// functionality to check and request microphone permissions.
///
/// The struct uses an `AudioSession` to interact with the system's audio session services,
/// with separate implementations for iOS and macOS platforms.
///
/// The `PermissionStatus` associated type is `AudioPermissionStatus`, which represents the status
/// of the microphone permission.
@available(iOS 13.0, *)
@available(macOS 10.15, *)
struct MicrophonePermission: PermissionProvider, Sendable {
  let audioSession: AudioSession
  /// Represents the status of the microphone permission.
  typealias PermissionStatus = AudioPermissionStatus

  /// Initializes a new `MicrophonePermission` with the given audio session.
  ///
  /// If no audio session is provided, a default one is used based on the platform.
  ///
  /// - Parameter audioSession: An object conforming to the `AudioSession` protocol.
  init(audioSession: AudioSession = defaultAudioSession()) {
    self.audioSession = audioSession
  }

  /// Checks the status of the microphone permission.
  ///
  /// The status is returned asynchronously through the `completion` closure.
  ///
  /// - Parameter completion: A closure that takes the status of the permission as a parameter.
  /// The status is represented by the `AudioPermissionStatus` type.
  func checkPermissionStatus(completion: @escaping (PermissionStatus) -> Void) {
    audioSession.checkPermissionStatus(completion: completion)
  }

  /// Requests the microphone permission if it's not already granted.
  ///
  /// The result of the request is returned asynchronously through the `completion` closure.
  ///
  /// - Parameter completion: A closure that takes a Boolean value indicating whether the permission was granted.
  func requestPermission(completion: @escaping (Bool) async -> Void) {
    audioSession.requestPermission(completion: completion)
  }

  /// Returns the default audio session for the current platform.
  ///
  /// On iOS, this is the shared instance of `AVAudioSession`.
  /// On macOS, this is an instance of `MacOSAudioSession`.
  ///
  /// - Returns: An object conforming to the `AudioSession` protocol.
  private static func defaultAudioSession() -> AudioSession {
    #if os(iOS)
    return AVAudioSession.sharedInstance()
    #elseif os(macOS)
    return MacOSAudioSession()
    #else
    fatalError("Unsupported platform")
    #endif
  }
}
