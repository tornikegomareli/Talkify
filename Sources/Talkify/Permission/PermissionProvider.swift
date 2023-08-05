//
//  PermissionProvider.swift
//
//
//  Created by Tornike on 05/08/2023.
//

import Foundation

/// A protocol representing a provider for checking and requesting permissions.
///
/// Types that conform to `PermissionProvider` can be used to check the status of a specific permission
/// and request that permission if it's not already granted.
///
/// The `PermissionProvider` protocol requires conformance to two methods:
/// `checkPermissionStatus(completion:)` and `requestPermission(completion:)`.
///
/// The `PermissionStatus` associated type represents the status of the permission,
/// which could be granted, denied, or undetermined, depending on the specific permission.
public protocol PermissionProvider {

  /// Represents the status of a specific permission.
  associatedtype PermissionStatus

  /// Checks the status of a specific permission.
  ///
  /// The status is returned asynchronously through the `completion` closure.
  ///
  /// - Parameter completion: A closure that takes the status of the permission as a parameter.
  /// The status is represented by the `PermissionStatus` associated type.
  func checkPermissionStatus(completion: @escaping (PermissionStatus) -> Void)

  /// Requests a specific permission if it's not already granted.
  ///
  /// The result of the request is returned asynchronously through the `completion` closure.
  ///
  /// - Parameter completion: A closure that takes a Boolean value indicating whether the permission was granted.
  func requestPermission(completion: @escaping (Bool) async -> Void)
}
