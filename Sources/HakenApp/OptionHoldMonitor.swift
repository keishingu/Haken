import CoreGraphics
import Foundation
import HakenCore

/// Observes the session-wide modifier state without intercepting or recording key events.
final class OptionHoldMonitor {
  private static let shortcutModifierFlags: CGEventFlags = [
    .maskCommand, .maskAlternate, .maskControl, .maskShift,
  ]
  private static let nonModifierKeyCodes =
    (0..<128).filter { !(54...63).contains($0) }.map(CGKeyCode.init)

  private let pollInterval: TimeInterval
  private var timer: Timer?
  private var state = HUDHoldGestureState()
  private var onLongPress: (() -> Void)?
  private var onDismiss: (() -> Void)?

  init(pollInterval: TimeInterval = 1.0 / 30.0) {
    self.pollInterval = pollInterval
  }

  deinit { timer?.invalidate() }

  func start(
    modifier: ShortcutModifier,
    holdDuration: TimeInterval,
    onLongPress: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    stop()
    guard modifier != .none else { return }
    self.onLongPress = onLongPress
    self.onDismiss = onDismiss

    let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
      self?.sampleKeyboardState(modifier: modifier, holdDuration: holdDuration)
    }
    timer.tolerance = min(0.015, pollInterval / 2)
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    state = HUDHoldGestureState()
  }

  private func sampleKeyboardState(modifier: ShortcutModifier, holdDuration: TimeInterval) {
    let flag: CGEventFlags = modifier == .command ? .maskCommand : .maskAlternate
    let flags = CGEventSource.flagsState(.combinedSessionState)
      .intersection(Self.shortcutModifierFlags)
    let modifierIsPressed = flags.contains(flag)
    let additionalKeyIsPressed =
      modifierIsPressed
      && (flags != flag
        || Self.nonModifierKeyCodes.contains {
          CGEventSource.keyState(.combinedSessionState, key: $0)
        })

    switch state.update(
      modifierIsPressed: modifierIsPressed,
      additionalKeyIsPressed: additionalKeyIsPressed,
      now: ProcessInfo.processInfo.systemUptime,
      holdDuration: holdDuration
    ) {
    case .show:
      onLongPress?()
    case .hide:
      onDismiss?()
    case .none:
      break
    }
  }
}
