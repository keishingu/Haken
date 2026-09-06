import ArgumentParser
import Darwin
import Foundation
import HakenCore

private let cliVersion = "0.1.0"

struct GlobalOptions: ParsableArguments {
  @Flag(name: .long, help: "Emit one versioned JSON document.")
  var json = false

  @Flag(name: .customLong("no-launch"), help: "Do not start Haken.app when it is not running.")
  var noLaunch = false

  @Option(name: .long, help: "IPC timeout in milliseconds (100...10000).")
  var timeout = 2_000

  func validate() throws {
    guard (100...10_000).contains(timeout) else {
      throw ValidationError("--timeout must be between 100 and 10000 milliseconds.")
    }
  }
}

struct ActionOptions: ParsableArguments {
  @Flag(name: .customLong("dry-run"), help: "Resolve and validate without performing the action.")
  var dryRun = false
}

struct WriteOptions: ParsableArguments {
  @OptionGroup var action: ActionOptions

  @Flag(name: .long, help: "Confirm a persistent configuration change without prompting.")
  var yes = false
}

struct HakenCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "haken",
    abstract: "Control Haken slots, applications, and Chrome profiles.",
    version: cliVersion,
    subcommands: [Slot.self, Application.self, Chrome.self, Config.self, Doctor.self])
}

struct Slot: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Inspect, activate, and configure slots.",
    subcommands: [List.self, Get.self, Activate.self, Set.self, Clear.self])

  struct List: ParsableCommand {
    @OptionGroup var options: GlobalOptions

    mutating func run() throws {
      try CLIExecutor.run(HakenCLIRequest(method: "slot.list"), options: options)
    }
  }

  struct Get: ParsableCommand {
    @Argument(help: "Slot number: 1 through 9, or 0.") var slot: Int
    @OptionGroup var options: GlobalOptions

    mutating func run() throws {
      try CLIExecutor.run(
        HakenCLIRequest(method: "slot.get", parameters: ["slot": .int(slot)]),
        options: options)
    }
  }

  struct Activate: ParsableCommand {
    @Argument(help: "Slot number: 1 through 9, or 0.") var slot: Int
    @OptionGroup var action: ActionOptions
    @OptionGroup var options: GlobalOptions

    mutating func run() throws {
      try CLIExecutor.run(
        HakenCLIRequest(
          method: "slot.activate", parameters: ["slot": .int(slot)],
          dryRun: action.dryRun), options: options)
    }
  }

  struct Set: ParsableCommand {
    @Argument(help: "Slot number: 1 through 9, or 0.") var slot: Int
    @Option(name: .long, help: "Exact application display name.") var app: String?
    @Option(name: .customLong("bundle-id"), help: "Exact application bundle identifier.")
    var bundleIdentifier: String?
    @Option(name: .long, help: "Exact path to an application bundle.") var path: String?
    @Option(name: .customLong("chrome-profile"), help: "Exact Chrome profile display name.")
    var chromeProfile: String?
    @OptionGroup var write: WriteOptions
    @OptionGroup var options: GlobalOptions

    mutating func validate() throws {
      let selectors = [app, bundleIdentifier, path, chromeProfile].compactMap { $0 }
      guard selectors.count == 1 else {
        throw ValidationError(
          "Specify exactly one of --app, --bundle-id, --path, or --chrome-profile.")
      }
    }

    mutating func run() throws {
      var parameters: [String: HakenJSONValue] = ["slot": .int(slot)]
      if let app { parameters["name"] = .string(app) }
      if let bundleIdentifier { parameters["bundleIdentifier"] = .string(bundleIdentifier) }
      if let path { parameters["path"] = .string(path) }
      if let chromeProfile { parameters["chromeProfile"] = .string(chromeProfile) }
      let request = HakenCLIRequest(
        method: "slot.set", parameters: parameters, dryRun: write.action.dryRun,
        confirmed: write.yes)
      try CLIExecutor.runPersistentWrite(request, options: options)
    }
  }

  struct Clear: ParsableCommand {
    @Argument(help: "Slot number: 1 through 9, or 0.") var slot: Int
    @OptionGroup var write: WriteOptions
    @OptionGroup var options: GlobalOptions

    mutating func run() throws {
      let request = HakenCLIRequest(
        method: "slot.clear", parameters: ["slot": .int(slot)],
        dryRun: write.action.dryRun, confirmed: write.yes)
      try CLIExecutor.runPersistentWrite(request, options: options)
    }
  }
}

struct Application: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "app", abstract: "Inspect and activate macOS applications.",
    subcommands: [List.self, Activate.self])

  struct List: ParsableCommand {
    @OptionGroup var options: GlobalOptions

    mutating func run() throws {
      try CLIExecutor.run(HakenCLIRequest(method: "app.list"), options: options)
    }
  }

  struct Activate: ParsableCommand {
    @Argument(help: "Exact application display name.") var name: String?
    @Option(name: .customLong("bundle-id"), help: "Exact application bundle identifier.")
    var bundleIdentifier: String?
    @Option(name: .long, help: "Exact path to an application bundle.") var path: String?
    @OptionGroup var action: ActionOptions
    @OptionGroup var options: GlobalOptions

    mutating func validate() throws {
      guard [name, bundleIdentifier, path].compactMap({ $0 }).count == 1 else {
        throw ValidationError("Specify exactly one application name, --bundle-id, or --path.")
      }
    }

    mutating func run() throws {
      var parameters: [String: HakenJSONValue] = [:]
      if let name { parameters["name"] = .string(name) }
      if let bundleIdentifier { parameters["bundleIdentifier"] = .string(bundleIdentifier) }
      if let path { parameters["path"] = .string(path) }
      try CLIExecutor.run(
        HakenCLIRequest(
          method: "app.activate", parameters: parameters, dryRun: action.dryRun),
        options: options)
    }
  }
}

struct Chrome: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Inspect and activate Google Chrome profiles.",
    subcommands: [Profiles.self, Activate.self])

  struct Profiles: ParsableCommand {
    @OptionGroup var options: GlobalOptions

    mutating func run() throws {
      try CLIExecutor.run(HakenCLIRequest(method: "chrome.profiles"), options: options)
    }
  }

  struct Activate: ParsableCommand {
    @Argument(help: "Exact Chrome profile display name.") var profileName: String
    @OptionGroup var action: ActionOptions
    @OptionGroup var options: GlobalOptions

    mutating func run() throws {
      try CLIExecutor.run(
        HakenCLIRequest(
          method: "chrome.activate", parameters: ["chromeProfile": .string(profileName)],
          dryRun: action.dryRun), options: options)
    }
  }
}

struct Config: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Inspect and validate Haken configuration.",
    subcommands: [Show.self, Path.self, Validate.self])

  struct Show: ParsableCommand {
    @OptionGroup var options: GlobalOptions
    mutating func run() throws {
      try CLIExecutor.run(HakenCLIRequest(method: "config.show"), options: options)
    }
  }

  struct Path: ParsableCommand {
    @OptionGroup var options: GlobalOptions
    mutating func run() throws {
      try CLIExecutor.run(HakenCLIRequest(method: "config.path"), options: options)
    }
  }

  struct Validate: ParsableCommand {
    @OptionGroup var options: GlobalOptions
    mutating func run() throws {
      try CLIExecutor.run(HakenCLIRequest(method: "config.validate"), options: options)
    }
  }
}

struct Doctor: ParsableCommand {
  @OptionGroup var options: GlobalOptions
  mutating func run() throws {
    try CLIExecutor.run(HakenCLIRequest(method: "doctor"), options: options)
  }
}

private enum CLIExecutor {
  static func runPersistentWrite(
    _ request: HakenCLIRequest, options: GlobalOptions
  ) throws {
    if request.dryRun || request.confirmed || options.json || isatty(STDIN_FILENO) == 0 {
      try run(request, options: options)
      return
    }

    var preview = request
    preview.requestId = UUID()
    preview.dryRun = true
    preview.confirmed = false
    try run(preview, options: options)
    writeError("Apply this change? [y/N] ", newline: false)
    guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
      print("Cancelled.")
      return
    }
    var confirmed = request
    confirmed.confirmed = true
    try run(confirmed, options: options)
  }

  static func run(_ request: HakenCLIRequest, options: GlobalOptions) throws {
    let response: HakenCLIResponse
    do {
      response = try HakenCLIClient().send(
        request, launchApp: !options.noLaunch, timeoutMilliseconds: options.timeout)
    } catch {
      let payload = transportFailure(request: request, error: error)
      render(payload, json: options.json)
      throw ExitCode(payload.error?.exitCode ?? 74)
    }

    var rendered = response
    rendered.meta.cliVersion = cliVersion
    render(rendered, json: options.json)
    if let error = rendered.error { throw ExitCode(error.exitCode) }
  }

  private static func transportFailure(
    request: HakenCLIRequest, error: Error
  ) -> HakenCLIResponse {
    let code: String
    let message: String
    let hint: String?
    let exitCode: Int32
    switch error {
    case HakenCLIClientError.appNotFound:
      code = "haken_app_not_found"
      message = "Haken.app could not be found."
      hint = "Run the CLI bundled inside Haken.app or install Haken.app in Applications."
      exitCode = 69
    case HakenCLIClientError.appUnavailable:
      code = "haken_app_unavailable"
      message = "Haken.app did not become available before the timeout."
      hint = "Open Haken.app and retry."
      exitCode = 75
    default:
      code = "ipc_failure"
      message = "The CLI could not communicate with Haken.app."
      hint = "Open Haken.app and retry."
      exitCode = 74
    }
    return HakenCLIResponse(
      ok: false, command: request.method,
      error: HakenCLIErrorPayload(
        code: code, message: message, retryable: true, hint: hint, exitCode: exitCode),
      meta: HakenCLIResponseMeta(
        requestId: request.requestId, cliVersion: cliVersion, appVersion: "unknown",
        durationMs: 0))
  }

  private static func render(_ response: HakenCLIResponse, json: Bool) {
    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      if let data = try? encoder.encode(response), let text = String(data: data, encoding: .utf8) {
        print(text)
      }
      return
    }
    if let error = response.error {
      writeError("Error [\(error.code)]: \(error.message)")
      if let hint = error.hint { writeError("Hint: \(hint)") }
      return
    }
    guard let data = response.data else { return }
    switch response.command {
    case "slot.list":
      for slot in data.objectValue?["slots"]?.arrayValue ?? [] { print(slotLine(slot)) }
    case "slot.get": print(slotLine(data))
    case "app.list":
      for app in data.objectValue?["applications"]?.arrayValue ?? [] {
        let object = app.objectValue ?? [:]
        print(
          "\(object["displayName"]?.stringValue ?? "Unknown")\t\(object["bundleIdentifier"]?.stringValue ?? "")"
        )
      }
    case "chrome.profiles":
      for profile in data.objectValue?["profiles"]?.arrayValue ?? [] {
        print(profile.objectValue?["displayName"]?.stringValue ?? "Unknown")
      }
    case "config.path": print(data.objectValue?["path"]?.stringValue ?? "")
    case "version":
      let object = data.objectValue ?? [:]
      print("haken \(cliVersion) (Haken.app \(object["appVersion"]?.stringValue ?? "unknown"))")
    case "doctor":
      for check in data.objectValue?["checks"]?.arrayValue ?? [] {
        let object = check.objectValue ?? [:]
        print(
          "\(object["status"]?.stringValue?.uppercased() ?? "UNKNOWN")\t\(object["name"]?.stringValue ?? "")\t\(object["message"]?.stringValue ?? "")"
        )
      }
    default: print(prettyJSON(data))
    }
  }

  private static func slotLine(_ value: HakenJSONValue) -> String {
    let object = value.objectValue ?? [:]
    let slot = object["slot"]?.intValue.map(String.init) ?? "?"
    let shortcut = object["shortcut"]?.stringValue ?? ""
    let target = targetDescription(object["target"])
    return "\(slot)\t\(shortcut)\t\(target)"
  }

  private static func targetDescription(_ value: HakenJSONValue?) -> String {
    guard let object = value?.objectValue else { return "Not assigned" }
    if object["type"]?.stringValue == "application" {
      return object["displayName"]?.stringValue ?? "Application"
    }
    return "Google Chrome · \(object["profileName"]?.stringValue ?? "Profile")"
  }

  private static func prettyJSON(_ value: HakenJSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  private static func writeError(_ text: String, newline: Bool = true) {
    let output = text + (newline ? "\n" : "")
    FileHandle.standardError.write(Data(output.utf8))
  }
}

do {
  var command = try HakenCommand.parseAsRoot()
  try command.run()
} catch let exitCode as ExitCode {
  Darwin.exit(exitCode.rawValue)
} catch {
  if CommandLine.arguments.contains("--json") {
    let response = HakenCLIResponse(
      ok: false, command: "cli.parse",
      error: HakenCLIErrorPayload(
        code: "invalid_arguments", message: "Invalid command-line arguments.", retryable: false,
        hint: "Run haken --help for usage.", exitCode: 64),
      meta: HakenCLIResponseMeta(
        requestId: UUID(), cliVersion: cliVersion, appVersion: "unknown", durationMs: 0))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? encoder.encode(response), let text = String(data: data, encoding: .utf8) {
      print(text)
    }
    Darwin.exit(64)
  }
  HakenCommand.exit(withError: error)
}
