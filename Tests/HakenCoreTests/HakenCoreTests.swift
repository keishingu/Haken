import Foundation
import Testing

@testable import HakenCore

struct HakenCoreTests {
  @Test func slotOrderAndKeyCodesAreStable() {
    #expect(SlotKey.displayOrder.map(\.rawValue) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
    #expect(SlotKey.zero.virtualKeyCode == 29)
    #expect(SlotKey.zero.functionVirtualKeyCode == 109)
    #expect(SlotKey.one.displayValue == "⌥1")
    #expect(ShortcutStyle.optionFunction.displayValue(for: .one) == "⌥F1")
    #expect(ShortcutStyle.commandFunction.displayValue(for: .two) == "⌘F2")
    #expect(ShortcutStyle.function.displayValue(for: .zero) == "F10")
  }

  @Test func legacyConfigurationDefaultsToOptionNumberShortcuts() throws {
    let data = Data(
      """
      {"schemaVersion":1,"isEnabled":true,"launchAtLogin":false,"slots":[],"feedbackMode":"menuBar","developerMode":false}
      """.utf8)
    let configuration = try JSONDecoder().decode(HakenConfiguration.self, from: data)
    #expect(configuration.shortcutStyle == .optionNumber)
    #expect(configuration.hudHoldDuration == HakenConfiguration.defaultHUDHoldDuration)
  }

  @Test func hudHoldLatchesAnAdditionalInputPulseUntilModifierRelease() {
    var state = HUDHoldGestureState()

    #expect(
      state.update(
        modifierIsPressed: true, additionalKeyIsPressed: false, now: 0,
        holdDuration: 0.35) == .none)
    #expect(
      state.update(
        modifierIsPressed: true, additionalKeyIsPressed: true, now: 0.2,
        holdDuration: 0.35) == .none)
    #expect(
      state.update(
        modifierIsPressed: true, additionalKeyIsPressed: false, now: 1,
        holdDuration: 0.35) == .none)
    #expect(
      state.update(
        modifierIsPressed: false, additionalKeyIsPressed: false, now: 1.1,
        holdDuration: 0.35) == .none)
    #expect(
      state.update(
        modifierIsPressed: true, additionalKeyIsPressed: false, now: 2,
        holdDuration: 0.35) == .none)
    #expect(
      state.update(
        modifierIsPressed: true, additionalKeyIsPressed: false, now: 2.35,
        holdDuration: 0.35) == .show)
    #expect(
      state.update(
        modifierIsPressed: true, additionalKeyIsPressed: true, now: 2.4,
        holdDuration: 0.35) == .hide)
  }

  @Test func targetsRoundTripThroughConfiguration() throws {
    var configuration = HakenConfiguration()
    configuration.shortcutStyle = .commandFunction
    configuration.hudHoldDuration = 0.8
    configuration.setTarget(
      .application(
        ApplicationTarget(
          bundleIdentifier: "com.apple.Terminal", displayName: "Terminal",
          lastKnownPath: "/Applications/Utilities/Terminal.app")),
      for: .one
    )
    configuration.setTarget(
      .chromeProfile(
        ChromeProfileTarget(
          id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, profileName: "Private")),
      for: .zero)
    let decoded = try JSONDecoder().decode(
      HakenConfiguration.self, from: JSONEncoder().encode(configuration))
    #expect(decoded == configuration)
    #expect(decoded.shortcutStyle == .commandFunction)
    #expect(decoded.hudHoldDuration == 0.8)
    #expect(decoded.usesChromeProfiles)
  }

  @Test func configurationNormalizesMissingAndDuplicateSlots() {
    let configuration = HakenConfiguration(slots: [
      HakenSlot(id: .one),
      HakenSlot(
        id: .one,
        target: .application(ApplicationTarget(bundleIdentifier: "id", displayName: "name"))),
    ])
    #expect(configuration.slots.map(\.id) == SlotKey.displayOrder)
    #expect(configuration.target(for: .one)?.displayName == "name")
  }

  @Test func matcherRequiresTheCompletePrimarySelector() {
    let root = AccessibilityNode(children: [
      AccessibilityNode(
        role: "AXMenuItem", title: "Work", identifier: "switchToProfileFromMenu:",
        actions: ["AXPress"]),
      AccessibilityNode(
        role: "AXMenuItem", title: "Work", identifier: "wrong", actions: ["AXPress"]),
    ])
    #expect(ChromeProfileMatcher.primaryMatches(in: root, profileName: "Work").count == 1)
    #expect(ChromeProfileMatcher.detectedProfileNames(in: root) == ["Work"])
  }

  @Test func diagnosticsRedactsTargetNamesAndPaths() {
    var configuration = HakenConfiguration()
    configuration.setTarget(
      .chromeProfile(ChromeProfileTarget(profileName: "Sensitive Profile")), for: .one)
    configuration.setTarget(
      .application(
        ApplicationTarget(
          bundleIdentifier: "com.example.app", displayName: "Private App",
          lastKnownPath: "/private/path")), for: .two)
    let output = DiagnosticReport(
      appVersion: "1", macOSVersion: "macOS", chromeVersion: "123", accessibilityGranted: true,
      registeredSlots: [.one, .two], configuration: configuration, recentResults: []
    ).rendered()
    #expect(!output.contains("Sensitive Profile"))
    #expect(!output.contains("Private App"))
    #expect(!output.contains("/private/path"))
    #expect(output.contains("com.example.app") == false)
  }

  @Test func corruptFileIsNotOverwrittenUntilExplicitRecovery() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      UUID().uuidString)
    let file = directory.appendingPathComponent("configuration.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: file)
    let store = HakenConfigurationStore(fileURL: file)
    #expect(store.loadState == .corrupt(.corruptFile))
    #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == "not json")
    #expect(throws: ConfigurationError.self) { try store.update { $0.isEnabled = false } }
  }
}
