import Foundation

public struct ApplicationTarget: Codable, Equatable, Sendable, Identifiable {
  public var bundleIdentifier: String
  public var displayName: String
  public var lastKnownPath: String?

  public var id: String { bundleIdentifier }

  public init(bundleIdentifier: String, displayName: String, lastKnownPath: String? = nil) {
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
    self.lastKnownPath = lastKnownPath
  }
}

public struct ChromeProfileTarget: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var profileName: String
  public var lastSeenChromeVersion: String?

  public init(
    id: UUID = UUID(), profileName: String, lastSeenChromeVersion: String? = nil
  ) {
    self.id = id
    self.profileName = profileName
    self.lastSeenChromeVersion = lastSeenChromeVersion
  }
}

public enum SwitchTarget: Equatable, Sendable {
  case application(ApplicationTarget)
  case chromeProfile(ChromeProfileTarget)

  public var displayName: String {
    switch self {
    case .application(let target): target.displayName
    case .chromeProfile(let target): "Google Chrome · \(target.profileName)"
    }
  }

  public var kindName: String {
    switch self {
    case .application: "Application"
    case .chromeProfile: "Chrome Profile"
    }
  }
}

extension SwitchTarget: Codable {
  private enum CodingKeys: String, CodingKey { case type, application, chromeProfile }
  private enum Kind: String, Codable { case application, chromeProfile }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .application:
      self = .application(try container.decode(ApplicationTarget.self, forKey: .application))
    case .chromeProfile:
      self = .chromeProfile(try container.decode(ChromeProfileTarget.self, forKey: .chromeProfile))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .application(let target):
      try container.encode(Kind.application, forKey: .type)
      try container.encode(target, forKey: .application)
    case .chromeProfile(let target):
      try container.encode(Kind.chromeProfile, forKey: .type)
      try container.encode(target, forKey: .chromeProfile)
    }
  }
}
