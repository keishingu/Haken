import AppKit
import Combine
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var model: HakenAppModel?
  private var windowController: ConfigurationWindowController?
  private var statusMenu: StatusMenuController?
  private var ipcServer: HakenIPCServer?
  private var observation: AnyCancellable?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let backgroundLaunch = CommandLine.arguments.contains("--haken-cli-background")
    NSApplication.shared.setActivationPolicy(backgroundLaunch ? .accessory : .regular)
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
    let server = HakenIPCServer(handler: HakenCLIRequestHandler(model: model))
    do {
      try server.start()
      ipcServer = server
    } catch {
      Logger(subsystem: "com.haken.app", category: "ipc").error("CLI IPC server failed to start")
    }
    if !backgroundLaunch { windowController.present() }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag {
      NSApplication.shared.setActivationPolicy(.regular)
      windowController?.present()
    }
    return true
  }

  func applicationWillTerminate(_ notification: Notification) { ipcServer?.stop() }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
