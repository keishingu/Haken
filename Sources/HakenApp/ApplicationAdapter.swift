import AppKit
import HakenCore

struct ApplicationDescriptor: Identifiable, Hashable {
  let bundleIdentifier: String
  let displayName: String
  let url: URL

  var id: String { "\(bundleIdentifier)|\(url.path)" }

  func target() -> ApplicationTarget {
    ApplicationTarget(
      bundleIdentifier: bundleIdentifier, displayName: displayName, lastKnownPath: url.path)
  }
}

final class ApplicationAdapter: @unchecked Sendable {
  func activate(_ target: ApplicationTarget) -> Result<SwitchOutcome, HakenError> {
    let running = runningApplications(matching: target)
    if target.lastKnownPath == nil,
      Set(running.compactMap { $0.bundleURL?.standardizedFileURL }).count > 1
    {
      return .failure(.applicationAmbiguous)
    }
    if frontmostProcessIdentifier().map({ processIdentifier in
      running.contains { $0.processIdentifier == processIdentifier }
    }) == true {
      return .success(.alreadyActive)
    }

    if let application = running.first {
      guard activate(application) else { return .failure(.applicationActivationFailed) }
      return waitForFrontmost(application: application, timeout: 1.5)
        ? .success(.verified)
        : .failure(.applicationActivationFailed)
    }

    guard let url = resolveURL(for: target) else { return .failure(.applicationNotFound) }
    let semaphore = DispatchSemaphore(value: 0)
    var launchError: Error?
    var launched: NSRunningApplication?
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    onMain {
      NSWorkspace.shared.openApplication(at: url, configuration: configuration) {
        application, error in
        launched = application
        launchError = error
        semaphore.signal()
      }
    }
    _ = semaphore.wait(timeout: .now() + 2)
    if launchError != nil { return .failure(.applicationLaunchFailed) }
    guard let launched else { return .failure(.applicationLaunchFailed) }
    return waitForFrontmost(application: launched, timeout: 4.0)
      ? .success(.verified)
      : .failure(.applicationActivationFailed)
  }

  func runningAndInstalledApplications() -> [ApplicationDescriptor] {
    var candidates: [String: ApplicationDescriptor] = [:]
    for application in NSWorkspace.shared.runningApplications {
      if let descriptor = descriptor(application)?.1 {
        candidates[descriptor.id] = descriptor
      }
    }
    for root in [
      URL(fileURLWithPath: "/Applications"),
      URL(fileURLWithPath: "/System/Applications"),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ] {
      guard
        let contents = FileManager.default.enumerator(
          at: root, includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles, .skipsPackageDescendants])
      else { continue }
      for case let url as URL in contents where url.pathExtension == "app" {
        if let descriptor = descriptor(for: url) { candidates[descriptor.id] = descriptor }
      }
    }
    return candidates.values.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
  }

  func resolve(name: String) -> Result<ApplicationDescriptor, HakenError> {
    let matches = runningAndInstalledApplications().filter {
      $0.displayName.compare(name, options: [.caseInsensitive, .diacriticInsensitive])
        == .orderedSame
    }
    guard !matches.isEmpty else { return .failure(.applicationNotFound) }
    guard matches.count == 1, let match = matches.first else {
      return .failure(.applicationAmbiguous)
    }
    return .success(match)
  }

  func resolve(bundleIdentifier: String) -> Result<ApplicationDescriptor, HakenError> {
    var matches: [String: ApplicationDescriptor] = [:]
    for application in onMain({ NSWorkspace.shared.runningApplications })
    where application.bundleIdentifier == bundleIdentifier {
      if let descriptor = descriptor(application)?.1 { matches[descriptor.id] = descriptor }
    }
    for url in onMain({
      NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier)
    }) {
      if let descriptor = descriptor(for: url) { matches[descriptor.id] = descriptor }
    }
    guard !matches.isEmpty else { return .failure(.applicationNotFound) }
    guard matches.count == 1, let match = matches.values.first else {
      return .failure(.applicationAmbiguous)
    }
    return .success(match)
  }

  func resolve(path: String) -> Result<ApplicationDescriptor, HakenError> {
    guard let descriptor = descriptor(for: URL(fileURLWithPath: path).standardizedFileURL) else {
      return .failure(.applicationNotFound)
    }
    return .success(descriptor)
  }

  func descriptor(for url: URL) -> ApplicationDescriptor? {
    guard url.pathExtension == "app", let bundle = Bundle(url: url),
      let identifier = bundle.bundleIdentifier
    else { return nil }
    return ApplicationDescriptor(
      bundleIdentifier: identifier,
      displayName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? url.deletingPathExtension().lastPathComponent,
      url: url
    )
  }

  private func descriptor(_ application: NSRunningApplication) -> (String, ApplicationDescriptor)? {
    guard let identifier = application.bundleIdentifier, let url = application.bundleURL else {
      return nil
    }
    let descriptor = ApplicationDescriptor(
      bundleIdentifier: identifier, displayName: application.localizedName ?? identifier, url: url)
    return (descriptor.id, descriptor)
  }

  private func resolveURL(for target: ApplicationTarget) -> URL? {
    if let path = target.lastKnownPath {
      let url = URL(fileURLWithPath: path)
      if Bundle(url: url)?.bundleIdentifier == target.bundleIdentifier { return url }
    }
    return onMain {
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier)
    }
  }

  private func runningApplications(matching target: ApplicationTarget) -> [NSRunningApplication] {
    let applications = onMain {
      NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == target.bundleIdentifier && !$0.isTerminated
      }
    }
    guard let path = target.lastKnownPath else { return applications }
    let expectedURL = URL(fileURLWithPath: path).standardizedFileURL
    return applications.sorted {
      let leftMatches = $0.bundleURL?.standardizedFileURL == expectedURL
      let rightMatches = $1.bundleURL?.standardizedFileURL == expectedURL
      return leftMatches && !rightMatches
    }
  }

  private func waitForFrontmost(application: NSRunningApplication, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let processIdentifier = application.processIdentifier
      if processIdentifier > 0, frontmostProcessIdentifier() == processIdentifier {
        return true
      }
      Thread.sleep(forTimeInterval: 0.025)
    }
    return false
  }

  private func activate(_ application: NSRunningApplication) -> Bool {
    onMain {
      // This is deliberately not a window selector: it activates the application as a whole.
      guard !application.isTerminated else { return false }
      _ = application.unhide()
      return application.activate(options: [.activateAllWindows])
    }
  }

  private func frontmostProcessIdentifier() -> pid_t? {
    onMain { NSWorkspace.shared.frontmostApplication?.processIdentifier }
  }

  private func onMain<T>(_ operation: @escaping () -> T) -> T {
    if Thread.isMainThread { return operation() }
    return DispatchQueue.main.sync(execute: operation)
  }
}
