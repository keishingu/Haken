import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var model: HakenAppModel?
  private var windowController: ConfigurationWindowController?
  private var statusMenu: StatusMenuController?
  private var observation: AnyCancellable?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.regular)
    let model = HakenAppModel()
    let windowController = ConfigurationWindowController(model: model)
    let menu = StatusMenuController()
    menu.onOpen = { [weak windowController] in windowController?.present() }
    menu.onToggleEnabled = { [weak model] enabled in model?.setEnabled(enabled) }
    menu.onRefreshProfiles = { [weak model] in model?.refreshChromeProfiles() }
    menu.onCopyDiagnostics = { [weak model] in model?.copyDiagnostics() }
    observation = model.objectWillChange.sink { [weak menu, weak model] _ in
      DispatchQueue.main.async {
        guard let model else { return }
        menu?.update(
          enabled: model.configuration.isEnabled, assignedSlots: model.assignedSlots,
          lastResult: model.lastResult)
      }
    }
    self.model = model
    self.windowController = windowController
    statusMenu = menu
    windowController.present()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag { windowController?.present() }
    return true
  }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
