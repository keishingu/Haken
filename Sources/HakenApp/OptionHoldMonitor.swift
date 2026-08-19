import CoreGraphics
import Foundation
import HakenCore

/// Observes the session-wide modifier state without intercepting or recording key events.
final class OptionHoldMonitor {
  private let holdDuration: TimeInterval
  private let pollInterval: TimeInterval
  private var timer: Timer?
  private var pressedAt: Date?
  private var didRecognizeHold = false
  private var onLongPress: (() -> Void)?
  private var onRelease: (() -> Void)?

  init(holdDuration: TimeInterval = 0.35, pollInterval: TimeInterval = 1.0 / 30.0) {
    self.holdDuration = holdDuration
    self.pollInterval = pollInterval
  }

  deinit { timer?.invalidate() }

  func start(
    modifier: ShortcutModifier, onLongPress: @escaping () -> Void,
    onRelease: @escaping () -> Void
  ) {
    stop()
    guard modifier != .none else { return }
    self.onLongPress = onLongPress
    self.onRelease = onRelease

    let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
      self?.sampleModifierState(modifier: modifier)
    }
    timer.tolerance = min(0.015, pollInterval / 2)
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    pressedAt = nil
    didRecognizeHold = false
  }

  private func sampleModifierState(modifier: ShortcutModifier, now: Date = Date()) {
    let flag: CGEventFlags = modifier == .command ? .maskCommand : .maskAlternate
    let modifierIsPressed = CGEventSource.flagsState(.combinedSessionState).contains(flag)

    guard modifierIsPressed else {
      if didRecognizeHold { onRelease?() }
      pressedAt = nil
      didRecognizeHold = false
      return
    }

    guard !didRecognizeHold else { return }
    guard let pressedAt else {
      self.pressedAt = now
      return
    }
    guard now.timeIntervalSince(pressedAt) >= holdDuration else { return }
    didRecognizeHold = true
    onLongPress?()
  }
}
