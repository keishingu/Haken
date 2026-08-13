import AppKit
import HakenCore

/// A non-activating, all-Spaces switch confirmation panel using macOS glass materials.
final class SwitchHUDController {
  private let panel: NSWindow
  private let keyLabel = NSTextField(labelWithString: "")
  private let iconView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")
  private let accentView = NSVisualEffectView()
  private var dismissal: DispatchWorkItem?

  init() {
    panel = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 164),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.isMovableByWindowBackground = false
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true

    let material = NSVisualEffectView()
    material.material = .hudWindow
    material.blendingMode = .behindWindow
    material.state = .active
    material.wantsLayer = true
    material.layer?.cornerRadius = 28
    material.layer?.masksToBounds = true

    accentView.material = .underWindowBackground
    accentView.blendingMode = .withinWindow
    accentView.state = .active
    accentView.wantsLayer = true
    accentView.layer?.cornerRadius = 38
    accentView.layer?.opacity = 0.5

    keyLabel.alignment = .center
    keyLabel.font = .monospacedSystemFont(ofSize: 38, weight: .medium)
    keyLabel.textColor = .labelColor
    keyLabel.wantsLayer = true
    keyLabel.layer?.cornerRadius = 18
    keyLabel.layer?.borderWidth = 1
    keyLabel.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
    keyLabel.layer?.backgroundColor =
      NSColor.controlBackgroundColor
      .withAlphaComponent(0.48)
      .cgColor

    iconView.imageScaling = .scaleProportionallyUpOrDown
    iconView.wantsLayer = true
    iconView.layer?.cornerRadius = 18
    iconView.layer?.masksToBounds = true

    titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail
    detailLabel.font = .systemFont(ofSize: 14, weight: .medium)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.lineBreakMode = .byTruncatingTail

    let textStack = NSStackView(views: [titleLabel, detailLabel])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 5
    textStack.translatesAutoresizingMaskIntoConstraints = false

    for view in [accentView, keyLabel, iconView, textStack] {
      view.translatesAutoresizingMaskIntoConstraints = false
      material.addSubview(view)
    }
    panel.contentView = material
    NSLayoutConstraint.activate([
      accentView.widthAnchor.constraint(equalToConstant: 112),
      accentView.heightAnchor.constraint(equalToConstant: 112),
      accentView.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
      accentView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

      keyLabel.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 24),
      keyLabel.centerYAnchor.constraint(equalTo: material.centerYAnchor),
      keyLabel.widthAnchor.constraint(equalToConstant: 100),
      keyLabel.heightAnchor.constraint(equalToConstant: 92),

      iconView.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 24),
      iconView.centerYAnchor.constraint(equalTo: material.centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 76),
      iconView.heightAnchor.constraint(equalToConstant: 76),

      textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 18),
      textStack.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -28),
      textStack.centerYAnchor.constraint(equalTo: material.centerYAnchor),
    ])
  }

  func present(result: SwitchResult, target: SwitchTarget?) {
    guard let slot = result.slot else { return }
    dismissal?.cancel()

    keyLabel.stringValue = slot.displayValue
    titleLabel.stringValue = target?.displayName ?? "Haken"
    detailLabel.stringValue = detail(for: result)
    detailLabel.textColor = result.error == nil ? NSColor.systemBlue : NSColor.systemRed

    let image = icon(for: target)
    iconView.image = image
    accentView.layer?.backgroundColor =
      accentColor(for: image, failed: result.error != nil)
      .withAlphaComponent(0.35)
      .cgColor

    panel.alphaValue = 1
    centerPanel()
    panel.orderFrontRegardless()

    let delay = result.error == nil ? 1.4 : 3.0
    let work = DispatchWorkItem { [weak self] in self?.dismiss() }
    dismissal = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func dismiss() {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().alphaValue = 0
    } completionHandler: { [weak panel] in
      panel?.orderOut(nil)
    }
  }

  private func centerPanel() {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    guard let visibleFrame = screen?.visibleFrame else { return }
    panel.setFrameOrigin(
      NSPoint(
        x: visibleFrame.midX - panel.frame.width / 2,
        y: visibleFrame.midY - panel.frame.height / 2
      )
    )
  }

  private func detail(for result: SwitchResult) -> String {
    if let error = result.error { return error.userMessage }
    return switch result.outcome {
    case .verified: "Activated · \(result.durationMilliseconds) ms"
    case .alreadyActive: "Already active"
    case .requestAccepted: "Switch request accepted · \(result.durationMilliseconds) ms"
    case .failed, .ignored: result.summary
    }
  }

  private func icon(for target: SwitchTarget?) -> NSImage? {
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
    case nil: break
    }
    return NSImage(
      systemSymbolName: "arrow.left.arrow.right.circle.fill",
      accessibilityDescription: "Haken"
    )
  }

  private func accentColor(for image: NSImage?, failed: Bool) -> NSColor {
    if failed { return .systemRed }
    guard let image, let color = image.averageColor else { return .systemBlue }
    return color.blended(withFraction: 0.45, of: .systemBlue) ?? .systemBlue
  }
}

extension NSImage {
  fileprivate var averageColor: NSColor? {
    guard let tiff = tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    guard let image = CIImage(bitmapImageRep: bitmap) else { return nil }
    let filter = CIFilter(name: "CIAreaAverage")
    filter?.setValue(image, forKey: kCIInputImageKey)
    filter?.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
    guard let output = filter?.outputImage else { return nil }
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext(options: nil).render(
      output,
      toBitmap: &pixel,
      rowBytes: 4,
      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    return NSColor(
      red: CGFloat(pixel[0]) / 255,
      green: CGFloat(pixel[1]) / 255,
      blue: CGFloat(pixel[2]) / 255,
      alpha: 1
    )
  }
}
