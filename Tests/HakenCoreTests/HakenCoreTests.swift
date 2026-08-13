import Foundation
import Testing

@testable import HakenCore

struct HakenCoreTests {
  @Test func slotOrderAndKeyCodesAreStable() {
    #expect(SlotKey.displayOrder.map(\.rawValue) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
    #expect(SlotKey.zero.virtualKeyCode == 29)
    #expect(SlotKey.one.displayValue == "⌥1")
  }

  @Test func targetsRoundTripThroughConfiguration() throws {
    var configuration = HakenConfiguration()
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
