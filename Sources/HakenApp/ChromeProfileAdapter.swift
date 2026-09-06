import AppKit
import ApplicationServices
import HakenCore
import OSLog

struct ChromeProfileDescriptor: Identifiable, Hashable {
  let name: String
  let chromeVersion: String?
  var id: String { name }
}

final class ChromeProfileAdapter: @unchecked Sendable {
  private struct CachedItem {
    let pid: pid_t
    let version: String?
    let item: AXUIElement
  }

  private let permission: AccessibilityPermission
  private let logger: Logger
  private let cacheLock = NSLock()
  private var cache: [String: CachedItem] = [:]

  init(permission: AccessibilityPermission, logger: Logger) {
    self.permission = permission
    self.logger = logger
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(applicationLifecycleChanged(_:)),
      name: NSWorkspace.didLaunchApplicationNotification,
      object: nil
    )
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(applicationLifecycleChanged(_:)),
      name: NSWorkspace.didTerminateApplicationNotification,
      object: nil
    )
  }

  deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

  @objc private func applicationLifecycleChanged(_ notification: Notification) {
    guard
      let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication,
      application.bundleIdentifier == "com.google.Chrome"
    else { return }
    cacheLock.withLock { cache.removeAll() }
  }

  func availableProfiles() -> Result<[ChromeProfileDescriptor], HakenError> {
    guard permission.isGranted else { return .failure(.accessibilityPermissionRequired) }
    guard let chrome = chromeApplication() else { return .failure(.chromeNotRunning) }
    guard let menuBar = menuBar(for: chrome) else { return .failure(.menuBarUnavailable) }
    let names = profileItems(in: menuBar).compactMap {
      stringAttribute($0, kAXTitleAttribute as CFString)
    }
    let version = chromeVersion(chrome)
    logger.info("Chrome profile detection profileCount=\(names.count, privacy: .public)")
    return .success(
      Array(Set(names)).sorted().map { ChromeProfileDescriptor(name: $0, chromeVersion: version) })
  }

  func switchProfile(_ target: ChromeProfileTarget) -> Result<SwitchOutcome, HakenError> {
    guard permission.isGranted else { return .failure(.accessibilityPermissionRequired) }
    guard let chrome = chromeApplication() else { return .failure(.chromeNotRunning) }
    let version = chromeVersion(chrome)
    let cacheKey = "\(chrome.processIdentifier)|\(version ?? "unknown")|\(target.profileName)"
    if let cached = cacheLock.withLock({ cache[cacheKey] }) {
      let result = AXUIElementPerformAction(cached.item, kAXPressAction as CFString)
      if result == .success { return .success(.requestAccepted) }
      _ = cacheLock.withLock { cache.removeValue(forKey: cacheKey) }
    }
    return findAndPress(target.profileName, chrome: chrome, version: version, cacheKey: cacheKey)
  }

  private func findAndPress(
    _ name: String, chrome: NSRunningApplication, version: String?, cacheKey: String
  ) -> Result<SwitchOutcome, HakenError> {
    guard let menuBar = menuBar(for: chrome) else { return .failure(.menuBarUnavailable) }
    let matches = profileItems(in: menuBar).filter {
      stringAttribute($0, kAXTitleAttribute as CFString) == name
    }
    guard !matches.isEmpty else { return .failure(.profileNotFound) }
    guard matches.count == 1, let item = matches.first else { return .failure(.ambiguousProfile) }
    let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
    guard result == .success else {
      logger.error("Chrome AXPress failed code=\(result.rawValue, privacy: .public)")
      return .failure(.pressRejected(result.rawValue))
    }
    cacheLock.withLock {
      cache[cacheKey] = CachedItem(pid: chrome.processIdentifier, version: version, item: item)
    }
    return .success(.requestAccepted)
  }

  private func chromeApplication() -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.google.Chrome" }
  }

  private func chromeVersion(_ application: NSRunningApplication) -> String? {
    guard let url = application.bundleURL else { return nil }
    return Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
  }

  private func menuBar(for application: NSRunningApplication) -> AXUIElement? {
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    return attribute(appElement, kAXMenuBarAttribute as CFString) as! AXUIElement?
  }

  /// The PoC primary selector: only AXMenuBar descendants matching role/title/identifier/AXPress.
  private func profileItems(in menuBar: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [menuBar]
    var visited = 0
    while let element = pending.popLast(), visited < 5_000 {
      visited += 1
      if stringAttribute(element, kAXRoleAttribute as CFString) == kAXMenuItemRole as String,
        stringAttribute(element, kAXIdentifierAttribute as CFString) == "switchToProfileFromMenu:",
        actions(of: element).contains(kAXPressAction as String)
      {
        result.append(element)
      }
      pending.append(
        contentsOf: (attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement]) ?? [])
    }
    return result
  }

  private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
  }

  private func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
  }

  private func actions(of element: AXUIElement) -> [String] {
    var actions: CFArray?
    guard AXUIElementCopyActionNames(element, &actions) == .success else { return [] }
    return actions as? [String] ?? []
  }
}
