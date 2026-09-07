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
  @Published private(set) var cliInstalled = false
  @Published private(set) var cliInstallMessage: String?

  let commandService: HakenCommandService
  var applicationAdapter: ApplicationAdapter { commandService.applicationAdapter }
  private let registrar = GlobalHotKeyRegistrar()
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.haken.app", category: "lifecycle")
  private let hud = SwitchHUDController()
  private let optionHoldMonitor = OptionHoldMonitor()
  private let cliInstaller = CLIInstaller()

  init() {
    let commandService = HakenCommandService()
    self.commandService = commandService
    self.configuration = commandService.configuration
    self.configurationError = {
      if case .corrupt = commandService.configurationLoadState { return .configurationCorrupt }
      return nil
    }()
    commandService.onConfigurationChange = { [weak self] configuration in
      self?.configurationDidChange(configuration)
    }
    commandService.onResult = { [weak self] result in self?.record(result) }
    refreshEnvironment()
    synchronizeHotKeys()
    synchronizeHUDMonitor()
  }

  var assignedSlots: Int { configuration.slots.filter { $0.target != nil }.count }
  var usesChromeProfiles: Bool { configuration.usesChromeProfiles }
  var lastResult: SwitchResult? { recentResults.first }

  func refreshEnvironment() {
    accessibilityGranted = commandService.accessibilityGranted
    cliInstalled = cliInstaller.isInstalled
    DispatchQueue.global(qos: .userInitiated).async { [weak self, commandService] in
      let candidates = commandService.applications()
      DispatchQueue.main.async { self?.applicationCandidates = candidates }
    }
  }

  func refreshChromeProfiles() {
    accessibilityGranted = commandService.accessibilityGranted
    let commandService = commandService
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = commandService.chromeProfiles()
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
    _ = commandService.requestAccessibility()
    accessibilityGranted = commandService.accessibilityGranted
  }

  func openAccessibilitySettings() { commandService.openAccessibilitySettings() }

  var cliInstallPath: String { cliInstaller.destinationURL.path }

  func installCLI() {
    do {
      try cliInstaller.install()
      cliInstalled = true
      cliInstallMessage = "Installed at \(cliInstaller.destinationURL.path)"
    } catch {
      cliInstalled = false
      cliInstallMessage = error.localizedDescription
    }
  }

  func setEnabled(_ enabled: Bool) { mutate { $0.isEnabled = enabled } }

  func setFeedbackMode(_ feedbackMode: FeedbackMode) { mutate { $0.feedbackMode = feedbackMode } }

  func setHUDHoldDuration(_ duration: TimeInterval) {
    mutate { $0.hudHoldDuration = duration }
  }

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

  func test(slot: SlotKey) { commandService.activate(slot: slot) }

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
      try commandService.resetAfterCorruption()
    } catch {
      record(
        SwitchResult(
          slot: nil, targetKind: nil, outcome: .failed, durationMilliseconds: 0,
          error: .configurationCorrupt))
    }
  }

  private func mutate(_ change: (inout HakenConfiguration) -> Void) {
    do {
      try commandService.update(change)
    } catch {
      configurationError = .configurationCorrupt
      record(
        SwitchResult(
          slot: nil, targetKind: nil, outcome: .failed, durationMilliseconds: 0,
          error: .configurationCorrupt))
    }
  }

  private func configurationDidChange(_ configuration: HakenConfiguration) {
    self.configuration = configuration
    configurationError = nil
    synchronizeHotKeys()
    synchronizeHUDMonitor()
    if !configuration.isEnabled || configuration.feedbackMode != .hud { hud.dismiss() }
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
      holdDuration: configuration.hudHoldDuration,
      onLongPress: { [weak self] in self?.showShortcutHUD() },
      onDismiss: { [weak self] in self?.hud.dismiss() }
    )
  }
}
