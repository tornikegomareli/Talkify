//
//  AudioSession.swift
//  
//
//  Created by Tornike on 05/08/2023.
//

import Foundation

public enum AudioPermissionStatus: Sendable {
  case granted
  case denied
  case undetermined
}

public protocol AudioSession: Sendable {
  func checkPermissionStatus(completion: @escaping (AudioPermissionStatus) -> Void)
  func requestPermission(completion: @escaping (Bool) async -> Void)
}
