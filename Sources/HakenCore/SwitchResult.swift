import Foundation

public enum HakenError: Error, Equatable, Sendable {
  case disabled
  case unassignedSlot
  case hotKeyRegistrationFailed(SlotKey)
  case applicationNotFound
  case applicationAmbiguous
  case applicationLaunchFailed
  case applicationActivationFailed
  case chromeNotRunning
  case accessibilityPermissionRequired
  case menuBarUnavailable
  case profileNotFound
  case ambiguousProfile
  case pressRejected(Int32)
  case chromeCompatibilityIssue
  case configurationCorrupt
  case busy

  public var userMessage: String {
    switch self {
    case .disabled: "Haken is paused. Turn Haken back on in Settings to use its slots."
    case .unassignedSlot: "This slot has no target. Assign an app or Chrome profile in Settings."
    case .hotKeyRegistrationFailed(let slot):
      "\(slot.displayValue) could not be registered. Check for a conflicting app, then retry or unassign this slot."
    case .applicationNotFound:
      "The assigned application could not be found. Reinstall it or choose the application again."
    case .applicationAmbiguous:
      "More than one copy of the assigned application was found. Choose the intended .app again."
    case .applicationLaunchFailed:
      "Haken could not launch the application. Try opening it directly, then choose it again if needed."
    case .applicationActivationFailed:
      "Haken could not bring the application forward. Retry after restarting the application."
    case .chromeNotRunning:
      "Google Chrome is not running. Start Chrome, then try the profile slot again."
    case .accessibilityPermissionRequired:
      "Chrome profile switching needs Accessibility permission. Grant it in System Settings, then retry."
    case .menuBarUnavailable:
      "Haken could not read Chrome’s menu bar. Recheck Accessibility permission, restart Chrome, then refresh profiles."
    case .profileNotFound:
      "The configured Chrome profile was not found. Refresh profiles and confirm its name has not changed."
    case .ambiguousProfile:
      "More than one matching Chrome profile item was found. Use distinct profile names and copy Diagnostics if this persists."
    case .pressRejected:
      "Chrome did not accept the profile switch request. Restart Chrome and retry; Diagnostics can help identify a compatibility issue."
    case .chromeCompatibilityIssue:
      "Haken could not verify Chrome’s profile menu structure. Refresh profiles after a Chrome restart, then share Diagnostics."
    case .configurationCorrupt:
      "The configuration file cannot be read. Haken kept the original file; back it up and reset settings when ready."
    case .busy: "A switch is already in progress. Haken ignored the repeated request."
    }
  }

  public var diagnosticsCode: String {
    switch self {
    case .disabled: "disabled"
    case .unassignedSlot: "unassigned-slot"
    case .hotKeyRegistrationFailed: "hotkey-registration-failed"
    case .applicationNotFound: "application-not-found"
    case .applicationAmbiguous: "application-ambiguous"
    case .applicationLaunchFailed: "application-launch-failed"
    case .applicationActivationFailed: "application-activation-failed"
    case .chromeNotRunning: "chrome-not-running"
    case .accessibilityPermissionRequired: "accessibility-permission-required"
    case .menuBarUnavailable: "chrome-menu-bar-unavailable"
    case .profileNotFound: "chrome-profile-not-found"
    case .ambiguousProfile: "chrome-profile-ambiguous"
    case .pressRejected(let code): "chrome-press-rejected-\(code)"
    case .chromeCompatibilityIssue: "chrome-compatibility-issue"
    case .configurationCorrupt: "configuration-corrupt"
    case .busy: "busy"
    }
  }
}

public enum SwitchOutcome: String, Codable, Sendable {
  case verified, requestAccepted, alreadyActive, failed, ignored
}

public struct SwitchResult: Equatable, Sendable, Identifiable {
  public let id: UUID
  public let date: Date
  public let slot: SlotKey?
  public let targetKind: String?
  public let outcome: SwitchOutcome
  public let durationMilliseconds: Int
  public let error: HakenError?

  public init(
    slot: SlotKey?, targetKind: String?, outcome: SwitchOutcome, durationMilliseconds: Int,
    error: HakenError? = nil, date: Date = Date()
  ) {
    self.id = UUID()
    self.date = date
    self.slot = slot
    self.targetKind = targetKind
    self.outcome = outcome
    self.durationMilliseconds = durationMilliseconds
    self.error = error
  }

  public var summary: String {
    error?.userMessage ?? "\(outcome.rawValue) · \(durationMilliseconds) ms"
  }
}
