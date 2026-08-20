import Foundation
import Observation
import ServiceManagement

/// Registers Talkify as a login item through `SMAppService`, wrapped so the
/// rest of the app never imports `ServiceManagement`. Disabled by default
/// (CONTEXT.md): `SMAppService` is the source of truth for whether the login
/// item is registered, so this holds no preference of its own.
@MainActor
@Observable
final class LaunchAtLoginService {
  private(set) var isEnabled: Bool

  @ObservationIgnored
  private let service: SMAppService

  init(service: SMAppService = .mainApp) {
    self.service = service
    self.isEnabled = service.status == .enabled
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
      isEnabled = service.status == .enabled
    } catch {
      isEnabled = service.status == .enabled
    }
  }
}
