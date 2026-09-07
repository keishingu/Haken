import Foundation
import HakenCore
import OSLog

final class HakenCommandService: @unchecked Sendable {
  var onConfigurationChange: ((HakenConfiguration) -> Void)?
  var onResult: ((SwitchResult) -> Void)?

  let applicationAdapter: ApplicationAdapter
  private let store: HakenConfigurationStore
  private let permission: AccessibilityPermission
  private let chromeAdapter: ChromeProfileAdapter
  private var coordinator: SwitchCoordinator!

  init() {
    let store = HakenConfigurationStore()
    let permission = AccessibilityPermission()
    let applicationAdapter = ApplicationAdapter()
    let chromeAdapter = ChromeProfileAdapter(
      permission: permission,
      logger: Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.haken.app", category: "chrome-profile")
    )
    self.store = store
    self.permission = permission
    self.applicationAdapter = applicationAdapter
    self.chromeAdapter = chromeAdapter
    self.coordinator = SwitchCoordinator(
      applicationAdapter: applicationAdapter,
      chromeAdapter: chromeAdapter,
      configuration: { store.configuration },
      logger: Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.haken.app", category: "switch")
    )
    coordinator.onResult = { [weak self] result in self?.onResult?(result) }
  }

  var configuration: HakenConfiguration { store.configuration }
  var configurationLocation: URL { store.location }
  var configurationLoadState: HakenConfigurationStore.LoadState { store.loadState }
  var accessibilityGranted: Bool { permission.isGranted }

  func update(_ change: (inout HakenConfiguration) -> Void) throws {
    try store.update(change)
    onConfigurationChange?(store.configuration)
  }

  func resetAfterCorruption() throws {
    try store.resetAfterCorruption()
    onConfigurationChange?(store.configuration)
  }

  func requestAccessibility() -> Bool { permission.request() }
  func openAccessibilitySettings() { permission.openSystemSettings() }

  func applications() -> [ApplicationDescriptor] {
    applicationAdapter.runningAndInstalledApplications()
  }

  func resolveApplication(name: String) -> Result<ApplicationDescriptor, HakenError> {
    applicationAdapter.resolve(name: name)
  }

  func resolveApplication(bundleIdentifier: String) -> Result<ApplicationDescriptor, HakenError> {
    applicationAdapter.resolve(bundleIdentifier: bundleIdentifier)
  }

  func resolveApplication(path: String) -> Result<ApplicationDescriptor, HakenError> {
    applicationAdapter.resolve(path: path)
  }

  func chromeProfiles() -> Result<[ChromeProfileDescriptor], HakenError> {
    chromeAdapter.availableProfiles()
  }

  func activate(slot: SlotKey, completion: ((SwitchResult) -> Void)? = nil) {
    coordinator.request(slot: slot, completion: completion)
  }

  func activate(
    slot: SlotKey, target: SwitchTarget, completion: ((SwitchResult) -> Void)? = nil
  ) {
    coordinator.request(slot: slot, target: target, completion: completion)
  }

  func activate(target: SwitchTarget, completion: ((SwitchResult) -> Void)? = nil) {
    coordinator.request(target: target, completion: completion)
  }
}
