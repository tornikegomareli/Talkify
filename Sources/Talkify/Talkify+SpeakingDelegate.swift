//
//  TalkifySpeakingDelegate.swift
//  
//
//  Created by Tornike on 05/08/2023.
//

import Foundation

/// A protocol for delegates that receive speech synthesis-related events
public protocol TalkifySpeakingDelegate: AnyObject {
  /// Called when speech synthesis pauses
  func speakingDidPause()

  /// Called when speech synthesis continues
  func speakingDidContinue()

  /// Called when speech synthesis stops
  func speakingDidStop()

  /// Called when speech synthesis starts
  func speakingDidStart()
}
