import AppKit
import Observation
import Sparkle

/// Sparkle, wrapped so the rest of the app never imports it: Settings reads
/// this observable and calls two methods. Updates are signed with EdDSA and
/// checked against the appcast in the repository; Talkify ships no server, so
/// the feed is a static file (CONTEXT.md).
@MainActor
@Observable
final class SparkleUpdaterService {
  /// False until Sparkle finishes starting, and while a check is in flight.
  /// The Updates section disables its button on this rather than guessing.
  private(set) var canCheckForUpdates = false
  /// The newest version Sparkle has seen, or nil when the app is current.
  private(set) var availableVersion: String?
  private(set) var lastCheckedAt: Date?

  @ObservationIgnored
  private var controller: SPUStandardUpdaterController?
  @ObservationIgnored
  private let updaterDelegate = UpdaterDelegate()
  @ObservationIgnored
  private let userDriverDelegate = UserDriverDelegate()
  @ObservationIgnored
  private var canCheckObservation: NSKeyValueObservation?

  /// Asked before a background check runs and before a scheduled update is
  /// shown. Wired to the dictation session in the composition root: an update
  /// window stealing focus mid-session would move the insertion target, and
  /// the text would land in the wrong place (CONTEXT.md).
  var isBusy: (() -> Bool)?

  var automaticallyChecksForUpdates: Bool {
    get { controller?.updater.automaticallyChecksForUpdates ?? true }
    set { controller?.updater.automaticallyChecksForUpdates = newValue }
  }

  var automaticallyDownloadsUpdates: Bool {
    get { controller?.updater.automaticallyDownloadsUpdates ?? false }
    set { controller?.updater.automaticallyDownloadsUpdates = newValue }
  }

  /// Starts Sparkle. Called once at launch, after the status item exists, so
  /// a scheduled check can never race the app's own setup.
  func start() {
    guard controller == nil else { return }

    updaterDelegate.service = self
    userDriverDelegate.service = self
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: updaterDelegate,
      userDriverDelegate: userDriverDelegate
    )

    guard let updater = controller?.updater else { return }
    lastCheckedAt = updater.lastUpdateCheckDate
    canCheckForUpdates = updater.canCheckForUpdates
    canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.new]) {
      [weak self] updater, _ in
      Task { @MainActor [weak self] in
        self?.canCheckForUpdates = updater.canCheckForUpdates
      }
    }
  }

  /// A user-initiated check. Sparkle shows its own window, including the
  /// "you're up to date" case, which is the feedback the user asked for by
  /// pressing the button.
  func checkForUpdates() {
    controller?.checkForUpdates(nil)
    lastCheckedAt = .now
  }

  fileprivate func foundUpdate(version: String?) {
    availableVersion = version
  }

  /// True while dictation is running. Read from Sparkle's delegate callbacks,
  /// which can fire on a background check at any moment.
  fileprivate var isDictating: Bool {
    isBusy?() ?? false
  }

  fileprivate func finishedCheck() {
    lastCheckedAt = controller?.updater.lastUpdateCheckDate ?? .now
  }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
  weak var service: SparkleUpdaterService?

  enum BusyError: LocalizedError {
    case dictating
    var errorDescription: String? { "A dictation session is in progress." }
  }

  /// A background check is postponed while dictating; Sparkle reschedules it.
  /// A check the user asked for always runs, because they are looking at the
  /// button they just pressed.
  func updater(
    _ updater: SPUUpdater,
    mayPerform updateCheck: SPUUpdateCheck,
    error outError: NSErrorPointer
  ) throws {
    guard updateCheck == .updatesInBackground else { return }
    let busy = MainActor.assumeIsolated { service?.isDictating ?? false }
    if busy {
      throw BusyError.dictating
    }
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    Task { @MainActor [weak service] in
      service?.foundUpdate(version: item.displayVersionString)
    }
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
    Task { @MainActor [weak service] in
      service?.foundUpdate(version: nil)
      service?.finishedCheck()
    }
  }

  func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
    Task { @MainActor [weak service] in
      service?.finishedCheck()
    }
  }
}

/// Talkify is `LSUIElement`: no dock icon, accessory activation policy. Sparkle
/// positions and focuses its windows like a regular app, so under `.accessory`
/// the update window can open unfocused or off-screen. Becoming `.regular`
/// while the update UI is up fixes both, and the policy reverts when the
/// session ends so the app stays out of the Dock.
private final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
  weak var service: SparkleUpdaterService?

  var supportsGentleScheduledUpdateReminders: Bool { true }

  /// A scheduled update may be shown, but never pulled into focus: taking
  /// focus moves the insertion target, and mid-dictation that puts the text in
  /// the wrong window. Sparkle keeps the window behind the active app and the
  /// menu item still says an update is waiting.
  func standardUserDriverShouldHandleShowingScheduledUpdate(
    _ update: SUAppcastItem,
    andInImmediateFocus immediateFocus: Bool
  ) -> Bool {
    !immediateFocus
  }

  /// Only a check the user asked for gets the regular activation policy. Under
  /// `LSUIElement` Sparkle's window opens unfocused or off-screen, so it needs
  /// the switch to place and focus itself; the policy reverts when the session
  /// ends, keeping Talkify out of the Dock.
  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool,
    forUpdate update: SUAppcastItem,
    state: SPUUserUpdateState
  ) {
    guard state.userInitiated else { return }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  func standardUserDriverWillFinishUpdateSession() {
    NSApp.setActivationPolicy(.accessory)
  }
}
