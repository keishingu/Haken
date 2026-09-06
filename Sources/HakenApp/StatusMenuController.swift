import AppKit
import HakenCore

final class StatusMenuController: NSObject {
  var onOpen: (() -> Void)?
  var onToggleEnabled: ((Bool) -> Void)?
  var onRefreshProfiles: (() -> Void)?
  var onCopyDiagnostics: (() -> Void)?

  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let enabledItem = NSMenuItem()
  private let resultItem = NSMenuItem()
  private let slotsItem = NSMenuItem()
  private var enabled = true
  private lazy var normalIcon: NSImage? = {
    guard
      let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
      let image = NSImage(contentsOf: url)
    else {
      return NSImage(
        systemSymbolName: "arrow.left.arrow.right.circle", accessibilityDescription: "Haken")
    }
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    image.accessibilityDescription = "Haken"
    return image
  }()

  override init() {
    super.init()
    let menu = NSMenu()
    resultItem.isEnabled = false
    slotsItem.isEnabled = false
    menu.addItem(resultItem)
    menu.addItem(slotsItem)
    menu.addItem(.separator())
    menu.addItem(withTitle: "Open Haken…", action: #selector(open), keyEquivalent: "").target = self
    enabledItem.target = self
    enabledItem.action = #selector(toggleEnabled)
    menu.addItem(enabledItem)
    menu.addItem(
      withTitle: "Refresh Chrome Profiles", action: #selector(refreshProfiles), keyEquivalent: ""
    ).target = self
    menu.addItem(
      withTitle: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: ""
    ).target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit Haken", action: #selector(quit), keyEquivalent: "q").target = self
    item.menu = menu
    update(enabled: true, assignedSlots: 0, lastResult: nil)
  }

  func update(enabled: Bool, assignedSlots: Int, lastResult: SwitchResult?) {
    self.enabled = enabled
    enabledItem.title = enabled ? "Disable Haken" : "Enable Haken"
    slotsItem.title = "Slots: \(assignedSlots) / 10 assigned"
    let failure = lastResult?.error
    resultItem.title =
      failure?.userMessage
      ?? (lastResult.map { "Last switch: \($0.outcome.rawValue) · \($0.durationMilliseconds) ms" }
        ?? "Haken is ready")
    item.button?.image =
      failure == nil
      ? normalIcon
      : NSImage(
        systemSymbolName: "exclamationmark.circle", accessibilityDescription: resultItem.title)
  }

  @objc private func open() { onOpen?() }
  @objc private func toggleEnabled() { onToggleEnabled?(!enabled) }
  @objc private func refreshProfiles() { onRefreshProfiles?() }
  @objc private func copyDiagnostics() { onCopyDiagnostics?() }
  @objc private func quit() { NSApplication.shared.terminate(nil) }
}
