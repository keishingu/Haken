import Foundation

public struct HUDHoldGestureState: Sendable {
  public enum Transition: Equatable, Sendable {
    case none
    case show
    case hide
  }

  private var pressedAt: TimeInterval?
  private var isVisible = false
  private var isSuppressedUntilRelease = false

  public init() {}

  public mutating func update(
    modifierIsPressed: Bool,
    additionalKeyIsPressed: Bool,
    now: TimeInterval,
    holdDuration: TimeInterval
  ) -> Transition {
    guard modifierIsPressed else {
      let transition: Transition = isVisible ? .hide : .none
      self = Self()
      return transition
    }

    if additionalKeyIsPressed {
      let transition: Transition = isVisible ? .hide : .none
      pressedAt = nil
      isVisible = false
      isSuppressedUntilRelease = true
      return transition
    }

    guard !isSuppressedUntilRelease, !isVisible else { return .none }
    guard let pressedAt else {
      self.pressedAt = now
      return .none
    }
    guard now - pressedAt >= holdDuration else { return .none }
    isVisible = true
    return .show
  }
}
