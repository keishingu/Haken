import Foundation

public struct DiagnosticReport: Sendable {
  public var appVersion: String
  public var macOSVersion: String
  public var chromeVersion: String?
  public var accessibilityGranted: Bool
  public var registeredSlots: Set<SlotKey>
  public var configuration: HakenConfiguration
  public var recentResults: [SwitchResult]

  public init(
    appVersion: String, macOSVersion: String, chromeVersion: String?, accessibilityGranted: Bool,
    registeredSlots: Set<SlotKey>, configuration: HakenConfiguration, recentResults: [SwitchResult]
  ) {
    self.appVersion = appVersion
    self.macOSVersion = macOSVersion
    self.chromeVersion = chromeVersion
    self.accessibilityGranted = accessibilityGranted
    self.registeredSlots = registeredSlots
    self.configuration = configuration
    self.recentResults = recentResults
  }

  public func rendered() -> String {
    let applications = configuration.slots.reduce(into: 0) {
      if case .application? = $1.target { $0 += 1 }
    }
    let profiles = configuration.slots.reduce(into: 0) {
      if case .chromeProfile? = $1.target { $0 += 1 }
    }
    let entries = recentResults.map { result in
      let error = result.error?.diagnosticsCode ?? result.outcome.rawValue
      return
        "slot=\(result.slot?.rawValue.description ?? "none") target=\(result.targetKind ?? "none") result=\(error) durationMs=\(result.durationMilliseconds)"
    }.joined(separator: "\n")
    return """
      Haken Diagnostics
      appVersion=\(appVersion)
      macOS=\(macOSVersion)
      chromeVersion=\(chromeVersion ?? "not-running")
      accessibilityGranted=\(accessibilityGranted)
      enabled=\(configuration.isEnabled)
      shortcutStyle=\(configuration.shortcutStyle.rawValue)
      registeredSlots=\(registeredSlots.count)
      applicationTargets=\(applications)
      chromeProfileTargets=\(profiles)
      recentResults:
      \(entries)
      """
  }
}
