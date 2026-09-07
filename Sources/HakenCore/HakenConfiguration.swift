import Foundation

public enum FeedbackMode: String, Codable, CaseIterable, Sendable {
  case menuBar
  case hud
}

public struct HakenConfiguration: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public static let defaultHUDHoldDuration: TimeInterval = 0.35
  public static let hudHoldDurationRange: ClosedRange<TimeInterval> = 0.10...1.50

  public var schemaVersion: Int
  public var isEnabled: Bool
  public var launchAtLogin: Bool
  public var slots: [HakenSlot]
  public var shortcutStyle: ShortcutStyle
  public var feedbackMode: FeedbackMode
  public var hudHoldDuration: TimeInterval
  public var developerMode: Bool

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    isEnabled: Bool = true,
    launchAtLogin: Bool = false,
    slots: [HakenSlot] = SlotKey.displayOrder.map { HakenSlot(id: $0) },
    shortcutStyle: ShortcutStyle = .optionNumber,
    feedbackMode: FeedbackMode = .menuBar,
    hudHoldDuration: TimeInterval = Self.defaultHUDHoldDuration,
    developerMode: Bool = false
  ) {
    self.schemaVersion = schemaVersion
    self.isEnabled = isEnabled
    self.launchAtLogin = launchAtLogin
    self.slots = Self.normalizedSlots(slots)
    self.shortcutStyle = shortcutStyle
    self.feedbackMode = feedbackMode
    self.hudHoldDuration = hudHoldDuration.clamped(to: Self.hudHoldDurationRange)
    self.developerMode = developerMode
  }

  public func target(for key: SlotKey) -> SwitchTarget? {
    slots.first(where: { $0.id == key })?.target
  }

  public mutating func setTarget(_ target: SwitchTarget?, for key: SlotKey) {
    slots = Self.normalizedSlots(slots)
    guard let index = slots.firstIndex(where: { $0.id == key }) else { return }
    slots[index].target = target
  }

  public var usesChromeProfiles: Bool {
    slots.contains { if case .chromeProfile? = $0.target { true } else { false } }
  }

  public static func normalizedSlots(_ slots: [HakenSlot]) -> [HakenSlot] {
    SlotKey.displayOrder.map { key in
      slots.last(where: { $0.id == key }) ?? HakenSlot(id: key)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, isEnabled, launchAtLogin, slots, shortcutStyle, feedbackMode,
      hudHoldDuration, developerMode
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
    launchAtLogin = try values.decode(Bool.self, forKey: .launchAtLogin)
    slots = Self.normalizedSlots(try values.decode([HakenSlot].self, forKey: .slots))
    shortcutStyle =
      try values.decodeIfPresent(ShortcutStyle.self, forKey: .shortcutStyle)
      ?? .optionNumber
    feedbackMode = try values.decode(FeedbackMode.self, forKey: .feedbackMode)
    hudHoldDuration =
      try values.decodeIfPresent(TimeInterval.self, forKey: .hudHoldDuration)?
      .clamped(to: Self.hudHoldDurationRange)
      ?? Self.defaultHUDHoldDuration
    developerMode = try values.decode(Bool.self, forKey: .developerMode)
  }
}

public enum ConfigurationError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedSchemaVersion(Int)
  case corruptFile
  case writeFailed

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion:
      "This configuration was created by a newer version of Haken. Keep the file and update Haken before changing settings."
    case .corruptFile:
      "Haken could not read configuration.json. Your existing file has not been changed; back it up, then reset Haken settings."
    case .writeFailed:
      "Haken could not save your changes. Check available disk space and the Application Support folder permissions."
    }
  }
}

public final class HakenConfigurationStore: @unchecked Sendable {
  public enum LoadState: Equatable, Sendable {
    case ready
    case corrupt(ConfigurationError)
  }

  private let lock = NSLock()
  private let fileURL: URL
  private var storedConfiguration: HakenConfiguration
  public private(set) var loadState: LoadState

  public init(fileURL: URL = HakenConfigurationStore.defaultFileURL()) {
    self.fileURL = fileURL
    if FileManager.default.fileExists(atPath: fileURL.path) {
      do {
        let decoded = try JSONDecoder().decode(
          HakenConfiguration.self, from: Data(contentsOf: fileURL))
        guard decoded.schemaVersion <= HakenConfiguration.currentSchemaVersion else {
          throw ConfigurationError.unsupportedSchemaVersion(decoded.schemaVersion)
        }
        self.storedConfiguration = HakenConfiguration(
          schemaVersion: HakenConfiguration.currentSchemaVersion,
          isEnabled: decoded.isEnabled,
          launchAtLogin: decoded.launchAtLogin,
          slots: decoded.slots,
          shortcutStyle: decoded.shortcutStyle,
          feedbackMode: decoded.feedbackMode,
          hudHoldDuration: decoded.hudHoldDuration,
          developerMode: decoded.developerMode
        )
        self.loadState = .ready
      } catch let error as ConfigurationError {
        self.storedConfiguration = HakenConfiguration()
        self.loadState = .corrupt(error)
      } catch {
        self.storedConfiguration = HakenConfiguration()
        self.loadState = .corrupt(.corruptFile)
      }
    } else {
      self.storedConfiguration = HakenConfiguration()
      self.loadState = .ready
    }
  }

  public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Haken", isDirectory: true)
      .appendingPathComponent("configuration.json", isDirectory: false)
  }

  public var configuration: HakenConfiguration { lock.withLock { storedConfiguration } }
  public var location: URL { fileURL }

  public func update(_ change: (inout HakenConfiguration) -> Void) throws {
    try lock.withLock {
      guard case .ready = loadState else { throw ConfigurationError.corruptFile }
      var next = storedConfiguration
      change(&next)
      try persist(next)
      storedConfiguration = next
    }
  }

  /// Deliberately destructive recovery, available only after the UI explains the existing file is preserved.
  public func resetAfterCorruption() throws {
    try lock.withLock {
      guard case .corrupt = loadState else { return }
      let replacement = HakenConfiguration()
      try persist(replacement)
      storedConfiguration = replacement
      loadState = .ready
    }
  }

  private func persist(_ configuration: HakenConfiguration) throws {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(configuration).write(to: fileURL, options: .atomic)
    } catch {
      throw ConfigurationError.writeFailed
    }
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
