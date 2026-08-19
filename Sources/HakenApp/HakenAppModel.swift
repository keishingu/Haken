import AppKit
import Combine
import HakenCore
import OSLog
import ServiceManagement

final class HakenAppModel: ObservableObject, @unchecked Sendable {
  @Published private(set) var configuration: HakenConfiguration
  @Published private(set) var applicationCandidates: [ApplicationDescriptor] = []
  @Published private(set) var chromeProfiles: [ChromeProfileDescriptor] = []
  @Published private(set) var recentResults: [SwitchResult] = []
  @Published private(set) var hotKeyErrors: [SlotKey: HakenError] = [:]
  @Published private(set) var accessibilityGranted = false
  @Published private(set) var configurationError: HakenError?

  let applicationAdapter: ApplicationAdapter
  private let store: HakenConfigurationStore
  private let registrar = GlobalHotKeyRegistrar()
  private let permission = AccessibilityPermission()
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.haken.app", category: "lifecycle")
  private let chromeAdapter: ChromeProfileAdapter
  private let coordinator: SwitchCoordinator
  private let hud = SwitchHUDController()
  private let optionHoldMonitor = OptionHoldMonitor()

  init() {
    let store = HakenConfigurationStore()
    let applicationAdapter = ApplicationAdapter()
    let permission = AccessibilityPermission()
    let chromeAdapter = ChromeProfileAdapter(
      permission: permission,
      logger: Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.haken.app", category: "chrome-profile")
    )
    self.store = store
    self.applicationAdapter = applicationAdapter
    self.chromeAdapter = chromeAdapter
    self.configuration = store.configuration
    self.configurationError = {
      if case .corrupt = store.loadState { return .configurationCorrupt }
      return nil
    }()
    self.coordinator = SwitchCoordinator(
      applicationAdapter: applicationAdapter,
      chromeAdapter: chromeAdapter,
      configuration: { store.configuration },
      logger: Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.haken.app", category: "switch")
    )
    coordinator.onResult = { [weak self] result in self?.record(result) }
    refreshEnvironment()
    synchronizeHotKeys()
    synchronizeHUDMonitor()
  }

  var assignedSlots: Int { configuration.slots.filter { $0.target != nil }.count }
  var usesChromeProfiles: Bool { configuration.usesChromeProfiles }
  var lastResult: SwitchResult? { recentResults.first }

  func refreshEnvironment() {
    accessibilityGranted = permission.isGranted
    DispatchQueue.global(qos: .userInitiated).async { [weak self, applicationAdapter] in
      let candidates = applicationAdapter.runningAndInstalledApplications()
      DispatchQueue.main.async { self?.applicationCandidates = candidates }
    }
  }

  func refreshChromeProfiles() {
    accessibilityGranted = permission.isGranted
    let adapter = chromeAdapter
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = adapter.availableProfiles()
      DispatchQueue.main.async {
        switch result {
        case .success(let profiles): self?.chromeProfiles = profiles
        case .failure(let error):
          self?.record(
            SwitchResult(
              slot: nil, targetKind: "Chrome Profile", outcome: .failed, durationMilliseconds: 0,
              error: error))
        }
      }
    }
  }

  func requestAccessibility() {
    _ = permission.request()
    accessibilityGranted = permission.isGranted
  }

  func openAccessibilitySettings() { permission.openSystemSettings() }

  func setEnabled(_ enabled: Bool) { mutate { $0.isEnabled = enabled } }

  func setFeedbackMode(_ feedbackMode: FeedbackMode) { mutate { $0.feedbackMode = feedbackMode } }

  func setShortcutStyle(_ shortcutStyle: ShortcutStyle) {
    mutate { $0.shortcutStyle = shortcutStyle }
  }

  func setDeveloperMode(_ enabled: Bool) { mutate { $0.developerMode = enabled } }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      mutate { $0.launchAtLogin = enabled }
    } catch {
      record(
        SwitchResult(
          slot: nil, targetKind: nil, outcome: .failed, durationMilliseconds: 0,
          error: .applicationLaunchFailed))
    }
  }

  func assign(_ target: SwitchTarget?, to slot: SlotKey) {
    mutate { $0.setTarget(target, for: slot) }
  }

  func test(slot: SlotKey) { coordinator.request(slot: slot) }

  @MainActor func chooseApplication(for slot: SlotKey) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.applicationBundle]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url,
        let target = self?.applicationAdapter.descriptor(for: url)?.target()
      else { return }
      self?.assign(.application(target), to: slot)
      self?.refreshEnvironment()
    }
  }

  func copyDiagnostics() {
    let report = DiagnosticReport(
      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "development",
      macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      chromeVersion: chromeProfiles.first?.chromeVersion,
      accessibilityGranted: accessibilityGranted,
      registeredSlots: registrar.registeredSlots,
      configuration: configuration,
      recentResults: recentResults
    ).rendered()
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(report, forType: .string)
  }

  func resetCorruptConfiguration() {
    do {
      try store.resetAfterCorruption()
      configuration = store.configuration
      configurationError = nil
      synchronizeHotKeys()
      synchronizeHUDMonitor()
    } catch {
      record(
        SwitchResult(
          slot: nil, targetKind: nil, outcome: .failed, durationMilliseconds: 0,
          error: .configurationCorrupt))
    }
  }

  private func mutate(_ change: (inout HakenConfiguration) -> Void) {
    do {
      try store.update(change)
      configuration = store.configuration
      configurationError = nil
      synchronizeHotKeys()
      synchronizeHUDMonitor()
      if !configuration.isEnabled || configuration.feedbackMode != .hud { hud.dismiss() }
    } catch {
      configurationError = .configurationCorrupt
      record(
        SwitchResult(
          slot: nil, targetKind: nil, outcome: .failed, durationMilliseconds: 0,
          error: .configurationCorrupt))
    }
  }

  private func synchronizeHotKeys() {
    let slots =
      configuration.isEnabled
      ? Set(configuration.slots.compactMap { $0.target == nil ? nil : $0.id }) : []
    hotKeyErrors = registrar.synchronize(slots: slots, style: configuration.shortcutStyle) {
      [weak self] slot in self?.test(slot: slot)
    }
    for error in hotKeyErrors.values {
      record(
        SwitchResult(
          slot: nil, targetKind: nil, outcome: .failed, durationMilliseconds: 0, error: error))
    }
    logger.info(
      "Hot key registration assigned=\(slots.count, privacy: .public) registered=\(self.registrar.registeredSlots.count, privacy: .public)"
    )
  }

  private func record(_ result: SwitchResult) {
    recentResults.insert(result, at: 0)
    recentResults = Array(recentResults.prefix(20))
  }

  private func showShortcutHUD() {
    guard configuration.isEnabled, configuration.feedbackMode == .hud else { return }
    hud.present(slots: configuration.slots, shortcutStyle: configuration.shortcutStyle)
  }

  private func synchronizeHUDMonitor() {
    hud.dismiss()
    optionHoldMonitor.start(
      modifier: configuration.shortcutStyle.modifier,
      onLongPress: { [weak self] in self?.showShortcutHUD() },
      onRelease: { [weak self] in self?.hud.dismiss() }
    )
  }
}
