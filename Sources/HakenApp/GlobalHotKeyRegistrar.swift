import Carbon
import HakenCore
import OSLog

enum GlobalHotKeyRegistrarError: Error {
  case registrationFailed(SlotKey, OSStatus)
  case eventHandlerInstallationFailed(OSStatus)
}

final class GlobalHotKeyRegistrar {
  private static let signature: OSType = 0x4841_4B4E  // HAKN
  private var eventHandler: EventHandlerRef?
  private var handlerInstallationStatus: OSStatus = noErr
  private var refs: [SlotKey: EventHotKeyRef] = [:]
  private var slotsByID: [UInt32: SlotKey] = [:]
  private var registeredStyle: ShortcutStyle?
  private var onPress: ((SlotKey) -> Void)?
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.haken.app", category: "hotkey")

  init() {
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    handlerInstallationStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let userData else { return noErr }
        let registrar = Unmanaged<GlobalHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
        registrar.handle(event)
        return noErr
      },
      1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler
    )
    if handlerInstallationStatus != noErr { eventHandler = nil }
  }

  deinit {
    unregisterAll()
    if let eventHandler { RemoveEventHandler(eventHandler) }
  }

  @discardableResult
  func synchronize(
    slots: Set<SlotKey>, style: ShortcutStyle, onPress: @escaping (SlotKey) -> Void
  ) -> [SlotKey: HakenError] {
    self.onPress = onPress
    if registeredStyle != style {
      unregisterAll()
      registeredStyle = style
    }
    var errors: [SlotKey: HakenError] = [:]
    guard handlerInstallationStatus == noErr else {
      for slot in slots { errors[slot] = .hotKeyRegistrationFailed(slot) }
      logger.error(
        "Hot key handler installation failed status=\(self.handlerInstallationStatus, privacy: .public)"
      )
      return errors
    }
    let additions = slots.subtracting(Set(refs.keys))
    for slot in additions {
      do {
        try register(slot, style: style)
      } catch {
        errors[slot] = .hotKeyRegistrationFailed(slot)
      }
    }
    // Existing working registrations stay live if a new slot conflicts.
    for slot in Set(refs.keys).subtracting(slots) { unregister(slot) }
    return errors
  }

  func unregisterAll() {
    refs.keys.forEach(unregister)
    slotsByID.removeAll()
  }

  var registeredSlots: Set<SlotKey> { Set(refs.keys) }

  private func register(_ slot: SlotKey, style: ShortcutStyle) throws {
    let identifier = EventHotKeyID(signature: Self.signature, id: UInt32(slot.rawValue))
    var reference: EventHotKeyRef?
    let modifiers: UInt32 =
      switch style.modifier {
      case .option: UInt32(optionKey)
      case .command: UInt32(cmdKey)
      case .none: 0
      }
    let keyCode = style.virtualKeyCode(for: slot)
    let status = RegisterEventHotKey(
      keyCode, modifiers, identifier, GetApplicationEventTarget(),
      OptionBits(kEventHotKeyExclusive), &reference
    )
    guard status == noErr, let reference else {
      logger.error(
        "Hot key registration failed slot=\(slot.rawValue, privacy: .public) status=\(status, privacy: .public)"
      )
      throw GlobalHotKeyRegistrarError.registrationFailed(slot, status)
    }
    logger.info(
      "Hot key registered slot=\(slot.rawValue, privacy: .public) keyCode=\(keyCode, privacy: .public) style=\(style.rawValue, privacy: .public)"
    )
    refs[slot] = reference
    slotsByID[identifier.id] = slot
  }

  private func unregister(_ slot: SlotKey) {
    if let ref = refs.removeValue(forKey: slot) { UnregisterEventHotKey(ref) }
    slotsByID.removeValue(forKey: UInt32(slot.rawValue))
  }

  private func handle(_ event: EventRef?) {
    guard let event else { return }
    var identifier = EventHotKeyID()
    var actualSize = 0
    guard
      GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, &actualSize, &identifier
      ) == noErr, identifier.signature == Self.signature, let slot = slotsByID[identifier.id]
    else { return }
    // Carbon callback only resolves the slot. Switching is intentionally delivered outside it.
    logger.info("Hot key received slot=\(slot.rawValue, privacy: .public)")
    DispatchQueue.main.async { [weak self] in self?.onPress?(slot) }
  }
}
