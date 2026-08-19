import Foundation

public enum ShortcutModifier: String, Codable, Sendable {
  case option
  case command
  case none
}

public enum ShortcutStyle: String, Codable, CaseIterable, Sendable, Identifiable {
  case optionNumber
  case optionFunction
  case commandNumber
  case commandFunction
  case function

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .optionNumber: "⌥ + Number keys"
    case .optionFunction: "⌥ + Function keys"
    case .commandNumber: "⌘ + Number keys"
    case .commandFunction: "⌘ + Function keys"
    case .function: "Function keys"
    }
  }

  public var modifier: ShortcutModifier {
    switch self {
    case .optionNumber, .optionFunction: .option
    case .commandNumber, .commandFunction: .command
    case .function: .none
    }
  }

  public var usesFunctionKeys: Bool {
    switch self {
    case .optionFunction, .commandFunction, .function: true
    case .optionNumber, .commandNumber: false
    }
  }

  public func displayValue(for slot: SlotKey) -> String {
    let key = usesFunctionKeys ? "F\(slot.functionKeyNumber)" : "\(slot.rawValue)"
    return switch modifier {
    case .option: "⌥\(key)"
    case .command: "⌘\(key)"
    case .none: key
    }
  }

  public func virtualKeyCode(for slot: SlotKey) -> UInt32 {
    usesFunctionKeys ? slot.functionVirtualKeyCode : slot.virtualKeyCode
  }
}

public enum SlotKey: Int, Codable, CaseIterable, Sendable, Identifiable {
  case one = 1
  case two, three, four, five, six, seven, eight, nine
  case zero = 0

  public var id: Self { self }

  public static let displayOrder: [Self] = [
    .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero,
  ]

  public var displayValue: String { "⌥\(rawValue)" }

  public var functionKeyNumber: Int { self == .zero ? 10 : rawValue }

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

  /// Carbon virtual key code for F1 through F10.
  public var functionVirtualKeyCode: UInt32 {
    switch self {
    case .one: 122
    case .two: 120
    case .three: 99
    case .four: 118
    case .five: 96
    case .six: 97
    case .seven: 98
    case .eight: 100
    case .nine: 101
    case .zero: 109
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
