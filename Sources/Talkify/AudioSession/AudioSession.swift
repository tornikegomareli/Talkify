//
//  AudioSession.swift
//  
//
//  Created by Tornike on 05/08/2023.
//

import Foundation

public enum AudioPermissionStatus {
  case granted
  case denied
  case undetermined
}

public protocol AudioSession {
  func checkPermissionStatus(completion: @escaping (PermissionStatus) -> Void)
  func requestPermission(completion: @escaping (Bool) async -> Void)
}
