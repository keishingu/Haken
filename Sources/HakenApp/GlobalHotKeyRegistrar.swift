import Carbon
import HakenCore

enum GlobalHotKeyRegistrarError: Error {
  case registrationFailed(SlotKey, OSStatus)
}

final class GlobalHotKeyRegistrar {
  private static let signature: OSType = 0x4841_4B4E  // HAKN
  private var eventHandler: EventHandlerRef?
  private var refs: [SlotKey: EventHotKeyRef] = [:]
  private var slotsByID: [UInt32: SlotKey] = [:]
  private var onPress: ((SlotKey) -> Void)?

  init() {
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, event, userData in
        guard let userData else { return noErr }
        let registrar = Unmanaged<GlobalHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
        registrar.handle(event)
        return noErr
      },
      1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler
    )
    if status != noErr { eventHandler = nil }
  }

  deinit {
    unregisterAll()
    if let eventHandler { RemoveEventHandler(eventHandler) }
  }

  @discardableResult
  func synchronize(slots: Set<SlotKey>, onPress: @escaping (SlotKey) -> Void) -> [SlotKey:
    HakenError]
  {
    self.onPress = onPress
    var errors: [SlotKey: HakenError] = [:]
    let additions = slots.subtracting(Set(refs.keys))
    var newlyRegistered: [SlotKey] = []
    for slot in additions {
      do {
        try register(slot)
        newlyRegistered.append(slot)
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

  private func register(_ slot: SlotKey) throws {
    let identifier = EventHotKeyID(signature: Self.signature, id: UInt32(slot.rawValue))
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      slot.virtualKeyCode, UInt32(optionKey), identifier, GetEventDispatcherTarget(),
      OptionBits(kEventHotKeyExclusive), &reference
    )
    guard status == noErr, let reference else {
      throw GlobalHotKeyRegistrarError.registrationFailed(slot, status)
    }
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
    DispatchQueue.main.async { [weak self] in self?.onPress?(slot) }
  }
}
