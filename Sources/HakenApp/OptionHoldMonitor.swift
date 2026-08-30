import CoreGraphics
import Foundation
import HakenCore

/// Observes the session-wide modifier state without intercepting or recording key events.
final class OptionHoldMonitor {
  private static let shortcutModifierFlags: CGEventFlags = [
    .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn,
  ]

  private let pollInterval: TimeInterval
  private var timer: Timer?
  private var state = HUDHoldGestureState()
  private var keyDownCount = CGEventSource.counterForEventType(
    .combinedSessionState, eventType: .keyDown)
  private var flagsChangedCount = CGEventSource.counterForEventType(
    .combinedSessionState, eventType: .flagsChanged)
  private var modifierWasPressed = false
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
    keyDownCount = CGEventSource.counterForEventType(
      .combinedSessionState, eventType: .keyDown)
    flagsChangedCount = CGEventSource.counterForEventType(
      .combinedSessionState, eventType: .flagsChanged)
    let flag: CGEventFlags = modifier == .command ? .maskCommand : .maskAlternate
    modifierWasPressed = CGEventSource.flagsState(.combinedSessionState).contains(flag)
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
    let nextKeyDownCount = CGEventSource.counterForEventType(
      .combinedSessionState, eventType: .keyDown)
    let receivedKeyDown = nextKeyDownCount != keyDownCount
    keyDownCount = nextKeyDownCount
    let nextFlagsChangedCount = CGEventSource.counterForEventType(
      .combinedSessionState, eventType: .flagsChanged)
    let modifierIsPressed = flags.contains(flag)
    let primaryModifierChanges = modifierIsPressed == modifierWasPressed ? 0 : 1
    let receivedAdditionalModifierChange =
      nextFlagsChangedCount &- flagsChangedCount > primaryModifierChanges
    flagsChangedCount = nextFlagsChangedCount
    modifierWasPressed = modifierIsPressed
    let additionalKeyIsPressed =
      modifierIsPressed
      && (flags != flag || receivedKeyDown || receivedAdditionalModifierChange)

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
