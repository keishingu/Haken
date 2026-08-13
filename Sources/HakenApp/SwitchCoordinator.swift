import Foundation
import HakenCore
import OSLog

final class SwitchCoordinator: @unchecked Sendable {
  var onResult: ((SwitchResult) -> Void)?

  private let applicationAdapter: ApplicationAdapter
  private let chromeAdapter: ChromeProfileAdapter
  private let configuration: () -> HakenConfiguration
  private let queue = DispatchQueue(label: "com.haken.switch", qos: .userInitiated)
  private let logger: Logger
  private var lastRequest: (slot: SlotKey, date: Date)?
  private var isExecuting = false

  init(
    applicationAdapter: ApplicationAdapter, chromeAdapter: ChromeProfileAdapter,
    configuration: @escaping () -> HakenConfiguration, logger: Logger
  ) {
    self.applicationAdapter = applicationAdapter
    self.chromeAdapter = chromeAdapter
    self.configuration = configuration
    self.logger = logger
  }

  func request(slot: SlotKey) {
    queue.async { [weak self] in self?.perform(slot: slot) }
  }

  private func perform(slot: SlotKey) {
    let start = ContinuousClock.now
    let config = configuration()
    let target = config.target(for: slot)
    if !config.isEnabled {
      publish(slot: slot, target: target, outcome: .ignored, error: .disabled, start: start)
      return
    }
    guard let target else {
      publish(slot: slot, target: nil, outcome: .ignored, error: .unassignedSlot, start: start)
      return
    }
    if isExecuting
      || (lastRequest?.slot == slot && Date().timeIntervalSince(lastRequest!.date) < 0.25)
    {
      publish(slot: slot, target: target, outcome: .ignored, error: .busy, start: start)
      return
    }
    isExecuting = true
    lastRequest = (slot, Date())
    defer { isExecuting = false }
    let result: Result<SwitchOutcome, HakenError>
    switch target {
    case .application(let application): result = applicationAdapter.activate(application)
    case .chromeProfile(let profile): result = chromeAdapter.switchProfile(profile)
    }
    switch result {
    case .success(let outcome):
      publish(slot: slot, target: target, outcome: outcome, error: nil, start: start)
    case .failure(let error):
      publish(slot: slot, target: target, outcome: .failed, error: error, start: start)
    }
  }

  private func publish(
    slot: SlotKey, target: SwitchTarget?, outcome: SwitchOutcome, error: HakenError?,
    start: ContinuousClock.Instant
  ) {
    let duration = start.duration(to: .now)
    let milliseconds =
      Int(duration.components.seconds * 1_000)
      + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    let result = SwitchResult(
      slot: slot, targetKind: target?.kindName, outcome: outcome,
      durationMilliseconds: milliseconds, error: error)
    logger.info(
      "switch slot=\(slot.rawValue, privacy: .public) target=\(target?.kindName ?? "none", privacy: .public) outcome=\(outcome.rawValue, privacy: .public) durationMs=\(milliseconds, privacy: .public) error=\(error?.diagnosticsCode ?? "none", privacy: .public)"
    )
    DispatchQueue.main.async { [weak self] in self?.onResult?(result) }
  }
}
