import AppKit
import HakenCore

/// An app-switcher-style panel that previews every assigned shortcut while Option is held.
final class SwitchHUDController {
  private enum Layout {
    static let iconSide: CGFloat = 68
    static let tileWidth: CGFloat = 108
    static let tileHeight: CGFloat = 140
    static let tileSpacing: CGFloat = 10
    static let glassContentInset: CGFloat = 12
    static let panelInset: CGFloat = 18
  }

  private let panel: NSWindow
  private var isPresented = false

  init() {
    panel = NSWindow(
      contentRect: .zero,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.isMovableByWindowBackground = false
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.isReleasedWhenClosed = false
    panel.setAccessibilityLabel("Haken shortcuts")
  }

  func present(slots: [HakenSlot], shortcutStyle: ShortcutStyle) {
    let assignedSlots = slots.filter { $0.target != nil }
    guard !assignedSlots.isEmpty else {
      dismiss()
      return
    }

    let stack = NSStackView(
      views: assignedSlots.map { makeSlotContent(for: $0, shortcutStyle: shortcutStyle) })
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.distribution = .fill
    stack.spacing = Layout.tileSpacing
    stack.edgeInsets = NSEdgeInsets(
      top: Layout.glassContentInset,
      left: Layout.glassContentInset,
      bottom: Layout.glassContentInset,
      right: Layout.glassContentInset
    )

    let glass = makeGlassView(containing: stack)
    let root = NSView()
    root.addSubview(glass)
    glass.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      glass.leadingAnchor.constraint(
        equalTo: root.leadingAnchor, constant: Layout.panelInset),
      glass.trailingAnchor.constraint(
        equalTo: root.trailingAnchor, constant: -Layout.panelInset),
      glass.topAnchor.constraint(equalTo: root.topAnchor, constant: Layout.panelInset),
      glass.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Layout.panelInset),
    ])
    panel.contentView = root

    let count = CGFloat(assignedSlots.count)
    let contentWidth = count * Layout.tileWidth + max(0, count - 1) * Layout.tileSpacing
    panel.setContentSize(
      NSSize(
        width: contentWidth + Layout.glassContentInset * 2 + Layout.panelInset * 2,
        height: Layout.tileHeight + Layout.glassContentInset * 2 + Layout.panelInset * 2
      ))
    centerPanel()

    if !isPresented {
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.12
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().alphaValue = 1
      }
    }
    isPresented = true
  }

  func dismiss() {
    guard isPresented else { return }
    isPresented = false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().alphaValue = 0
    } completionHandler: { [weak panel] in
      panel?.orderOut(nil)
    }
  }

  private func makeSlotContent(for slot: HakenSlot, shortcutStyle: ShortcutStyle) -> NSView {
    guard let target = slot.target else { return NSView() }

    let iconView = NSImageView(image: icon(for: target))
    iconView.imageScaling = .scaleProportionallyUpOrDown
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.setContentHuggingPriority(.required, for: .vertical)
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: Layout.iconSide),
      iconView.heightAnchor.constraint(equalToConstant: Layout.iconSide),
    ])

    let displayName = hudDisplayName(for: target)
    let nameLabel = NSTextField(labelWithString: displayName)
    nameLabel.alignment = .center
    nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.maximumNumberOfLines = 1
    nameLabel.textColor = .labelColor

    let shortcut = shortcutStyle.displayValue(for: slot.id)
    let shortcutLabel = NSTextField(labelWithString: shortcut)
    shortcutLabel.alignment = .center
    shortcutLabel.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
    shortcutLabel.textColor = .secondaryLabelColor

    let content = NSStackView(views: [iconView, nameLabel, shortcutLabel])
    content.orientation = .vertical
    content.alignment = .centerX
    content.spacing = 6
    content.edgeInsets = NSEdgeInsets(top: 13, left: 10, bottom: 11, right: 10)
    content.setCustomSpacing(9, after: iconView)
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      content.widthAnchor.constraint(equalToConstant: Layout.tileWidth),
      content.heightAnchor.constraint(equalToConstant: Layout.tileHeight),
    ])
    content.setAccessibilityElement(true)
    content.setAccessibilityLabel("\(displayName), \(shortcut)")

    return content
  }

  private func makeGlassView(containing content: NSView) -> NSView {
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      // The entire shortcut row is one content view so AppKit renders one continuous lens.
      glass.contentView = content
      glass.style = .clear
      glass.cornerRadius = 30
      return glass
    }

    let fallback = NSVisualEffectView()
    fallback.material = .hudWindow
    fallback.blendingMode = .behindWindow
    fallback.state = .active
    fallback.wantsLayer = true
    fallback.layer?.cornerRadius = 30
    fallback.layer?.masksToBounds = true
    fallback.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
      content.topAnchor.constraint(equalTo: fallback.topAnchor),
      content.bottomAnchor.constraint(equalTo: fallback.bottomAnchor),
    ])
    return fallback
  }

  private func centerPanel() {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    guard let visibleFrame = screen?.visibleFrame else { return }
    panel.setFrameOrigin(
      NSPoint(
        x: visibleFrame.midX - panel.frame.width / 2,
        y: visibleFrame.midY - panel.frame.height / 2
      ))
  }

  private func icon(for target: SwitchTarget) -> NSImage {
    switch target {
    case .application(let target):
      if let path = target.lastKnownPath,
        FileManager.default.fileExists(atPath: path)
      {
        return NSWorkspace.shared.icon(forFile: path)
      }
      if let url = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: target.bundleIdentifier
      ) {
        return NSWorkspace.shared.icon(forFile: url.path)
      }
    case .chromeProfile:
      if let chrome = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.google.Chrome"
      ) {
        return NSWorkspace.shared.icon(forFile: chrome.path)
      }
    }
    return NSImage(
      systemSymbolName: "app.fill", accessibilityDescription: target.displayName
    ) ?? NSImage()
  }

  private func hudDisplayName(for target: SwitchTarget) -> String {
    switch target {
    case .application(let application): application.displayName
    case .chromeProfile(let profile): profile.profileName
    }
  }
}
