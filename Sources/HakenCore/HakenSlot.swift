import Foundation

public enum SlotKey: Int, Codable, CaseIterable, Sendable, Identifiable {
  case one = 1
  case two, three, four, five, six, seven, eight, nine
  case zero = 0

  public var id: Self { self }

  public static let displayOrder: [Self] = [
    .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero,
  ]

  public var displayValue: String { "⌥\(rawValue)" }

  /// Carbon virtual key code for the ANSI number row. This intentionally does not depend on AppKit.
  public var virtualKeyCode: UInt32 {
    switch self {
    case .one: 18
    case .two: 19
    case .three: 20
    case .four: 21
    case .five: 23
    case .six: 22
    case .seven: 26
    case .eight: 28
    case .nine: 25
    case .zero: 29
    }
  }
}

public struct HakenSlot: Codable, Equatable, Sendable, Identifiable {
  public var id: SlotKey
  public var target: SwitchTarget?

  public init(id: SlotKey, target: SwitchTarget? = nil) {
    self.id = id
    self.target = target
  }
}
