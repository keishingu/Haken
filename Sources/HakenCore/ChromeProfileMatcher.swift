import Foundation

/// A privacy-safe snapshot used to test Chrome selector decisions without AXUIElement in Core.
public struct AccessibilityNode: Equatable, Sendable {
  public var role: String?
  public var title: String?
  public var identifier: String?
  public var actions: [String]
  public var children: [AccessibilityNode]

  public init(
    role: String? = nil, title: String? = nil, identifier: String? = nil,
    actions: [String] = [], children: [AccessibilityNode] = []
  ) {
    self.role = role
    self.title = title
    self.identifier = identifier
    self.actions = actions
    self.children = children
  }
}

public enum ChromeProfileMatcher {
  public static func primaryMatches(in root: AccessibilityNode, profileName: String)
    -> [AccessibilityNode]
  {
    var matches: [AccessibilityNode] = []
    visit(root) { node in
      if node.role == "AXMenuItem", node.title == profileName,
        node.identifier == "switchToProfileFromMenu:", node.actions.contains("AXPress")
      {
        matches.append(node)
      }
    }
    return matches
  }

  public static func detectedProfileNames(in root: AccessibilityNode) -> [String] {
    var names = Set<String>()
    visit(root) { node in
      if node.role == "AXMenuItem", let title = node.title,
        node.identifier == "switchToProfileFromMenu:", node.actions.contains("AXPress")
      {
        names.insert(title)
      }
    }
    return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private static func visit(_ node: AccessibilityNode, action: (AccessibilityNode) -> Void) {
    action(node)
    for child in node.children {
      visit(child, action: action)
    }
  }
}
