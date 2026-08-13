import AppKit
import ApplicationServices

struct AccessibilityPermission {
  var isGranted: Bool { AXIsProcessTrusted() }

  @discardableResult
  func request() -> Bool {
    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
  }

  func openSystemSettings() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }
}
