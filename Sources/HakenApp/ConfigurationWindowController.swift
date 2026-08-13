import AppKit
import SwiftUI

final class ConfigurationWindowController: NSWindowController {
  init(model: HakenAppModel) {
    let host = NSHostingController(rootView: HakenRootView(model: model))
    let window = NSWindow(contentViewController: host)
    window.title = "Haken"
    window.setContentSize(NSSize(width: 900, height: 650))
    window.minSize = NSSize(width: 760, height: 520)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
  }

  @available(*, unavailable) required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
