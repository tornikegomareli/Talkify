//
//  AudioSession+Platform.swift
//  
//
//  Created by Tornike on 05/08/2023.
//

import Foundation

#if os(iOS)
import AVFoundation

extension AVAudioSession: AudioSession {
  func checkPermissionStatus(completion: @escaping (PermissionStatus) -> Void) {
    switch self.recordPermission {
    case .granted:
      completion(.granted)
    case .denied:
      completion(.denied)
    case .undetermined:
      completion(.undetermined)
    @unknown default:
      fatalError("Unknown record permission status")
    }
  }

  func requestPermission(completion: @escaping (Bool) async -> Void) {
    self.requestRecordPermission { granted in
      Task(priority: .background) {
        await completion(granted)
      }
    }
  }
}
#endif

#if os(macOS)
import AVFoundation

struct MacOSAudioSession: AudioSession {
  func checkPermissionStatus(completion: @escaping (PermissionStatus) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      completion(.granted)
    case .denied:
      completion(.denied)
    case .notDetermined:
      completion(.undetermined)
    case .restricted:
      completion(.denied)
    @unknown default:
      fatalError("Unknown audio authorization status")
    }
  }

  func requestPermission(completion: @escaping (Bool) async -> Void) {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      Task(priority: .background) {
        await completion(granted)
      }
    }
  }
}
#endif

