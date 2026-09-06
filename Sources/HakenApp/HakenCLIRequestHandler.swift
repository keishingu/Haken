import Foundation
import HakenCore

final class HakenCLIRequestHandler {
  private unowned let model: HakenAppModel
  private let service: HakenCommandService

  init(model: HakenAppModel) {
    self.model = model
    self.service = model.commandService
  }

  func handle(_ request: HakenCLIRequest, completion: @escaping (HakenCLIResponse) -> Void) {
    let start = ContinuousClock.now
    guard request.protocolVersion == HakenCLIRequest.protocolVersion else {
      completion(
        failure(
          request, start: start, code: "protocol_mismatch",
          message: "The CLI and Haken.app use incompatible IPC protocol versions.",
          hint: "Install the CLI bundled with this version of Haken.app.", exitCode: 76))
      return
    }

    switch request.method {
    case "slot.list":
      success(
        request, start: start,
        data: .object([
          "slots": .array(service.configuration.slots.map(slotJSON))
        ]), completion: completion)
    case "slot.get":
      guard let slot = slot(from: request, start: start, completion: completion) else { return }
      let value = service.configuration.slots.first { $0.id == slot } ?? HakenSlot(id: slot)
      success(request, start: start, data: slotJSON(value), completion: completion)
    case "slot.activate":
      guard let slot = slot(from: request, start: start, completion: completion) else { return }
      guard let target = service.configuration.target(for: slot) else {
        completion(failure(request, start: start, error: .unassignedSlot))
        return
      }
      if request.dryRun {
        success(
          request, start: start,
          data: actionJSON(
            action: "activate_slot", slot: slot, target: target, willChange: nil, dryRun: true),
          completion: completion)
      } else {
        service.activate(slot: slot) { result in
          completion(self.response(for: request, result: result, start: start))
        }
      }
    case "slot.set":
      guard let slot = slot(from: request, start: start, completion: completion) else { return }
      resolveTarget(request, start: start) { result in
        switch result {
        case .failure(let response): completion(response)
        case .success(let target):
          let willChange = self.service.configuration.target(for: slot) != target
          let plan = self.actionJSON(
            action: "set_slot", slot: slot, target: target, willChange: willChange,
            dryRun: request.dryRun)
          if request.dryRun || !willChange {
            self.success(request, start: start, data: plan, completion: completion)
            return
          }
          guard request.confirmed else {
            completion(
              self.failure(
                request, start: start, code: "confirmation_required",
                message: "Changing a slot requires confirmation.",
                hint: "Review with --dry-run, then run again with --yes.", details: plan,
                exitCode: 64))
            return
          }
          do {
            try self.service.update { $0.setTarget(target, for: slot) }
            self.success(request, start: start, data: plan, completion: completion)
          } catch {
            completion(self.configurationFailure(request, start: start))
          }
        }
      }
    case "slot.clear":
      guard let slot = slot(from: request, start: start, completion: completion) else { return }
      let willChange = service.configuration.target(for: slot) != nil
      let plan = actionJSON(
        action: "clear_slot", slot: slot, target: nil, willChange: willChange,
        dryRun: request.dryRun)
      if request.dryRun || !willChange {
        success(request, start: start, data: plan, completion: completion)
      } else if !request.confirmed {
        completion(
          failure(
            request, start: start, code: "confirmation_required",
            message: "Clearing a slot requires confirmation.",
            hint: "Review with --dry-run, then run again with --yes.", details: plan,
            exitCode: 64))
      } else {
        do {
          try service.update { $0.setTarget(nil, for: slot) }
          success(request, start: start, data: plan, completion: completion)
        } catch {
          completion(configurationFailure(request, start: start))
        }
      }
    case "app.list":
      DispatchQueue.global(qos: .userInitiated).async { [service] in
        let applications = service.applications().map(self.applicationJSON)
        completion(
          self.makeSuccess(
            request, start: start,
            data: .object(["applications": .array(applications)])))
      }
    case "app.activate":
      resolveApplicationTarget(request, start: start) { result in
        switch result {
        case .failure(let response): completion(response)
        case .success(let target):
          if request.dryRun {
            self.success(
              request, start: start,
              data: self.actionJSON(
                action: "activate_application", slot: nil, target: .application(target),
                willChange: nil, dryRun: true), completion: completion)
          } else {
            self.service.activate(target: .application(target)) { result in
              completion(self.response(for: request, result: result, start: start))
            }
          }
        }
      }
    case "chrome.profiles":
      switch service.chromeProfiles() {
      case .success(let profiles):
        success(
          request, start: start,
          data: .object(["profiles": .array(profiles.map(profileJSON))]),
          completion: completion)
      case .failure(let error): completion(failure(request, start: start, error: error))
      }
    case "chrome.activate":
      resolveChromeTarget(request, start: start) { result in
        switch result {
        case .failure(let response): completion(response)
        case .success(let target):
          if request.dryRun {
            self.success(
              request, start: start,
              data: self.actionJSON(
                action: "activate_chrome_profile", slot: nil, target: .chromeProfile(target),
                willChange: nil, dryRun: true), completion: completion)
          } else {
            self.service.activate(target: .chromeProfile(target)) { result in
              completion(self.response(for: request, result: result, start: start))
            }
          }
        }
      }
    case "config.show":
      success(request, start: start, data: configurationJSON(), completion: completion)
    case "config.path":
      success(
        request, start: start,
        data: .object([
          "storeType": .string("file"),
          "path": .string(service.configurationLocation.path),
        ]), completion: completion)
    case "config.validate":
      switch service.configurationLoadState {
      case .ready:
        success(
          request, start: start,
          data: .object([
            "valid": .bool(true),
            "schemaVersion": .int(service.configuration.schemaVersion),
            "errors": .array([]),
            "warnings": .array([]),
          ]), completion: completion)
      case .corrupt:
        completion(configurationFailure(request, start: start))
      }
    case "doctor":
      success(request, start: start, data: doctorJSON(), completion: completion)
    case "version":
      success(
        request, start: start,
        data: .object([
          "appVersion": .string(appVersion),
          "protocolVersion": .int(HakenCLIRequest.protocolVersion),
          "apiVersion": .string(HakenCLIResponse.apiVersion),
        ]), completion: completion)
    default:
      completion(
        failure(
          request, start: start, code: "unknown_method",
          message: "Haken.app does not recognize command \(request.method).",
          hint: "Install the CLI bundled with this version of Haken.app.", exitCode: 76))
    }
  }

  private func slot(
    from request: HakenCLIRequest, start: ContinuousClock.Instant,
    completion: (HakenCLIResponse) -> Void
  ) -> SlotKey? {
    guard let value = request.parameters["slot"]?.intValue, let slot = SlotKey(rawValue: value)
    else {
      completion(
        failure(
          request, start: start, code: "slot_out_of_range",
          message: "Slot must be one of 1 through 9 or 0.", exitCode: 64))
      return nil
    }
    return slot
  }

  private func resolveTarget(
    _ request: HakenCLIRequest, start: ContinuousClock.Instant,
    completion: @escaping (CLIResolution<SwitchTarget>) -> Void
  ) {
    if request.parameters["chromeProfile"] != nil {
      resolveChromeTarget(request, start: start) { result in
        switch result {
        case .success(let target): completion(.success(.chromeProfile(target)))
        case .failure(let response): completion(.failure(response))
        }
      }
    } else {
      resolveApplicationTarget(request, start: start) { result in
        switch result {
        case .success(let target): completion(.success(.application(target)))
        case .failure(let response): completion(.failure(response))
        }
      }
    }
  }

  private func resolveApplicationTarget(
    _ request: HakenCLIRequest, start: ContinuousClock.Instant,
    completion: @escaping (CLIResolution<ApplicationTarget>) -> Void
  ) {
    let name = request.parameters["name"]?.stringValue
    let bundleIdentifier = request.parameters["bundleIdentifier"]?.stringValue
    let path = request.parameters["path"]?.stringValue
    guard [name, bundleIdentifier, path].compactMap({ $0 }).count == 1 else {
      completion(
        .failure(
          failure(
            request, start: start, code: "invalid_selector",
            message: "Specify exactly one application name, bundle identifier, or path.",
            exitCode: 64)))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [service] in
      let result: Result<ApplicationDescriptor, HakenError>
      if let name {
        result = service.resolveApplication(name: name)
      } else if let bundleIdentifier {
        result = service.resolveApplication(bundleIdentifier: bundleIdentifier)
      } else {
        result = service.resolveApplication(path: path!)
      }
      switch result {
      case .success(let descriptor):
        DispatchQueue.main.async { completion(.success(descriptor.target())) }
      case .failure(let error):
        DispatchQueue.main.async {
          completion(.failure(self.failure(request, start: start, error: error)))
        }
      }
    }
  }

  private func resolveChromeTarget(
    _ request: HakenCLIRequest, start: ContinuousClock.Instant,
    completion: (CLIResolution<ChromeProfileTarget>) -> Void
  ) {
    guard let name = request.parameters["chromeProfile"]?.stringValue, !name.isEmpty else {
      completion(
        .failure(
          failure(
            request, start: start, code: "invalid_selector",
            message: "A Chrome profile name is required.", exitCode: 64)))
      return
    }
    switch service.chromeProfiles() {
    case .failure(let error): completion(.failure(failure(request, start: start, error: error)))
    case .success(let profiles):
      let matches = profiles.filter { $0.name == name }
      guard !matches.isEmpty else {
        completion(.failure(failure(request, start: start, error: .profileNotFound)))
        return
      }
      guard matches.count == 1, let match = matches.first else {
        completion(.failure(failure(request, start: start, error: .ambiguousProfile)))
        return
      }
      completion(
        .success(
          ChromeProfileTarget(profileName: match.name, lastSeenChromeVersion: match.chromeVersion)))
    }
  }

  private func response(
    for request: HakenCLIRequest, result: SwitchResult, start: ContinuousClock.Instant
  ) -> HakenCLIResponse {
    if let error = result.error { return failure(request, start: start, error: error) }
    return makeSuccess(
      request, start: start,
      data: .object([
        "outcome": .string(result.outcome.rawValue.camelCaseToSnakeCase),
        "slot": result.slot.map { .int($0.rawValue) } ?? .null,
        "targetType": result.targetKind.map { .string($0.camelCaseToSnakeCase) } ?? .null,
        "durationMs": .int(result.durationMilliseconds),
      ]))
  }

  private func configurationJSON() -> HakenJSONValue {
    let configuration = service.configuration
    return .object([
      "schemaVersion": .int(configuration.schemaVersion),
      "enabled": .bool(configuration.isEnabled),
      "launchAtLogin": .bool(configuration.launchAtLogin),
      "shortcutStyle": .string(configuration.shortcutStyle.rawValue),
      "feedbackMode": .string(configuration.feedbackMode.rawValue),
      "developerMode": .bool(configuration.developerMode),
      "slots": .array(configuration.slots.map(slotJSON)),
    ])
  }

  private func doctorJSON() -> HakenJSONValue {
    var checks: [HakenJSONValue] = []
    let configReady: Bool
    if case .ready = service.configurationLoadState {
      configReady = true
    } else {
      configReady = false
    }
    checks.append(
      checkJSON(
        name: "configuration", status: configReady ? "pass" : "fail",
        message: configReady ? "Configuration is valid." : "Configuration cannot be read."))
    let permissionNeeded = service.configuration.usesChromeProfiles
    checks.append(
      checkJSON(
        name: "accessibility",
        status: service.accessibilityGranted ? "pass" : (permissionNeeded ? "fail" : "warning"),
        message: service.accessibilityGranted
          ? "Accessibility permission is granted."
          : (permissionNeeded
            ? "Accessibility permission is required by an assigned Chrome profile."
            : "Accessibility permission is not needed by the current slots.")))
    checks.append(
      checkJSON(
        name: "hotkeys", status: model.hotKeyErrors.isEmpty ? "pass" : "fail",
        message: model.hotKeyErrors.isEmpty
          ? "Assigned hot keys are registered." : "One or more hot keys could not be registered."))
    let hasFailure = checks.contains {
      guard case .object(let object) = $0 else { return false }
      return object["status"] == .string("fail")
    }
    return .object([
      "status": .string(hasFailure ? "fail" : "pass"),
      "checks": .array(checks),
    ])
  }

  private func checkJSON(name: String, status: String, message: String) -> HakenJSONValue {
    .object([
      "name": .string(name), "status": .string(status), "message": .string(message),
    ])
  }

  private func slotJSON(_ slot: HakenSlot) -> HakenJSONValue {
    .object([
      "slot": .int(slot.id.rawValue),
      "shortcut": .string(service.configuration.shortcutStyle.displayValue(for: slot.id)),
      "target": slot.target.map(targetJSON) ?? .null,
    ])
  }

  private func applicationJSON(_ application: ApplicationDescriptor) -> HakenJSONValue {
    .object([
      "displayName": .string(application.displayName),
      "bundleIdentifier": .string(application.bundleIdentifier),
      "path": .string(application.url.path),
    ])
  }

  private func profileJSON(_ profile: ChromeProfileDescriptor) -> HakenJSONValue {
    .object([
      "displayName": .string(profile.name),
      "bundleIdentifier": .string("com.google.Chrome"),
      "chromeVersion": profile.chromeVersion.map(HakenJSONValue.string) ?? .null,
    ])
  }

  private func targetJSON(_ target: SwitchTarget) -> HakenJSONValue {
    switch target {
    case .application(let application):
      return .object([
        "type": .string("application"),
        "displayName": .string(application.displayName),
        "bundleIdentifier": .string(application.bundleIdentifier),
      ])
    case .chromeProfile(let profile):
      return .object([
        "type": .string("chrome_profile"),
        "profileName": .string(profile.profileName),
        "bundleIdentifier": .string("com.google.Chrome"),
        "chromeVersion": profile.lastSeenChromeVersion.map(HakenJSONValue.string) ?? .null,
      ])
    }
  }

  private func actionJSON(
    action: String, slot: SlotKey?, target: SwitchTarget?, willChange: Bool?, dryRun: Bool
  ) -> HakenJSONValue {
    var object: [String: HakenJSONValue] = [
      "action": .string(action),
      "slot": slot.map { .int($0.rawValue) } ?? .null,
      "target": target.map(targetJSON) ?? .null,
      "dryRun": .bool(dryRun),
    ]
    if let willChange { object["willChange"] = .bool(willChange) }
    return .object(object)
  }

  private func success(
    _ request: HakenCLIRequest, start: ContinuousClock.Instant, data: HakenJSONValue,
    completion: (HakenCLIResponse) -> Void
  ) {
    completion(makeSuccess(request, start: start, data: data))
  }

  private func makeSuccess(
    _ request: HakenCLIRequest, start: ContinuousClock.Instant, data: HakenJSONValue
  ) -> HakenCLIResponse {
    HakenCLIResponse(
      ok: true, command: request.method, data: data,
      meta: meta(request: request, start: start))
  }

  private func configurationFailure(
    _ request: HakenCLIRequest, start: ContinuousClock.Instant
  ) -> HakenCLIResponse {
    failure(
      request, start: start, code: "configuration_corrupt",
      message: HakenError.configurationCorrupt.userMessage,
      hint: "Open Haken and review Configuration recovery.", exitCode: 78)
  }

  private func failure(
    _ request: HakenCLIRequest, start: ContinuousClock.Instant, error: HakenError
  ) -> HakenCLIResponse {
    let code: String
    let exitCode: Int32
    let retryable: Bool
    switch error {
    case .applicationAmbiguous, .ambiguousProfile:
      code = error.diagnosticsCode.replacingOccurrences(of: "-", with: "_")
      exitCode = 64
      retryable = false
    case .applicationNotFound, .chromeNotRunning, .profileNotFound:
      code = error.diagnosticsCode.replacingOccurrences(of: "-", with: "_")
      exitCode = 69
      retryable = false
    case .accessibilityPermissionRequired:
      code = "accessibility_permission_required"
      exitCode = 77
      retryable = false
    case .busy:
      code = "busy"
      exitCode = 75
      retryable = true
    case .configurationCorrupt, .disabled, .unassignedSlot:
      code = error.diagnosticsCode.replacingOccurrences(of: "-", with: "_")
      exitCode = 78
      retryable = false
    default:
      code = error.diagnosticsCode.replacingOccurrences(of: "-", with: "_")
      exitCode = 71
      retryable = true
    }
    return failure(
      request, start: start, code: code, message: error.userMessage, retryable: retryable,
      exitCode: exitCode)
  }

  private func failure(
    _ request: HakenCLIRequest, start: ContinuousClock.Instant, code: String, message: String,
    retryable: Bool = false, hint: String? = nil, details: HakenJSONValue? = nil,
    exitCode: Int32
  ) -> HakenCLIResponse {
    HakenCLIResponse(
      ok: false, command: request.method,
      error: HakenCLIErrorPayload(
        code: code, message: message, retryable: retryable, hint: hint, details: details,
        exitCode: exitCode),
      meta: meta(request: request, start: start))
  }

  private func meta(
    request: HakenCLIRequest, start: ContinuousClock.Instant
  ) -> HakenCLIResponseMeta {
    let duration = start.duration(to: .now)
    let milliseconds =
      Int(duration.components.seconds * 1_000)
      + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    return HakenCLIResponseMeta(
      requestId: request.requestId, appVersion: appVersion, durationMs: milliseconds)
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "development"
  }
}

extension String {
  fileprivate var camelCaseToSnakeCase: String {
    unicodeScalars.reduce(into: "") { result, scalar in
      if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "-" {
        if !result.isEmpty, !result.hasSuffix("_") { result.append("_") }
      } else {
        if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty,
          !result.hasSuffix("_")
        {
          result.append("_")
        }
        result.append(String(scalar).lowercased())
      }
    }
  }
}

private enum CLIResolution<Value> {
  case success(Value)
  case failure(HakenCLIResponse)
}
