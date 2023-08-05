//
//  TalkifyRecordingDelegate.swift
//  
//
//  Created by Tornike on 05/08/2023.
//

import Foundation

/// A protocol for delegates that receive recording-related events
public protocol TalkifyRecordingDelegate: AnyObject {
  /// Called when recording finishes with recognized text
  ///
  /// - Parameters:
  ///     - text: The recognized text
  func recordingDidFinishWithResults(text: String?)

  /// Called when recording starts
  func recordingDidStart()

  /// Called when recording stops
  func recordingDidStop()

  /// Called when an error occurs during recording
  ///
  /// - Parameters:
  ///     - error: The error that occurred
  func recordingDidEncounterError(error: Error)

  /// Called when microphone permission status changes
  ///
  /// - Parameters:
  ///     - status: The new microphone permission status
  func microphonePermissionDidChange(with status: AudioPermissionStatus)

  /// Called when permission to access the microphone is requested
  ///
  /// - Parameters:
  ///     - granted: Whether permission was granted or not
  func permissionDidRequest(granted: Bool)
}
