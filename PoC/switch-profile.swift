import AppKit
import ApplicationServices

let targetProfile = CommandLine.arguments.dropFirst().first ?? "圭 (wellness.jp)"

guard let chrome = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == "com.google.Chrome"
}) else {
    fputs("Google Chrome is not running.\n", stderr)
    exit(1)
}

let app = AXUIElementCreateApplication(chrome.processIdentifier)

func getAttribute(
    _ element: AXUIElement,
    _ attribute: CFString
) -> CFTypeRef? {
    var value: CFTypeRef?

    guard AXUIElementCopyAttributeValue(
        element,
        attribute,
        &value
    ) == .success else {
        return nil
    }

    return value
}

func stringAttribute(
    _ element: AXUIElement,
    _ attribute: CFString
) -> String? {
    getAttribute(element, attribute) as? String
}

func findProfileMenuItem(
    _ element: AXUIElement,
    targetProfile: String
) -> AXUIElement? {

    let role = stringAttribute(
        element,
        kAXRoleAttribute as CFString
    )

    let title = stringAttribute(
        element,
        kAXTitleAttribute as CFString
    )

    let identifier = stringAttribute(
        element,
        kAXIdentifierAttribute as CFString
    )

    if role == kAXMenuItemRole as String,
       title == targetProfile,
       identifier == "switchToProfileFromMenu:" {
        return element
    }

    guard let children = getAttribute(
        element,
        kAXChildrenAttribute as CFString
    ) as? [AXUIElement] else {
        return nil
    }

    for child in children {
        if let result = findProfileMenuItem(
            child,
            targetProfile: targetProfile
        ) {
            return result
        }
    }

    return nil
}

// Chrome全体ではなくMenu Barだけ探索
guard let menuBar = getAttribute(
    app,
    kAXMenuBarAttribute as CFString
) as! AXUIElement? else {
    fputs("Chrome menu bar not found.\n", stderr)
    exit(1)
}

guard let profileItem = findProfileMenuItem(
    menuBar,
    targetProfile: targetProfile
) else {
    fputs("Profile not found: \(targetProfile)\n", stderr)
    exit(1)
}

print("Found profile: \(targetProfile)")

let result = AXUIElementPerformAction(
    profileItem,
    kAXPressAction as CFString
)

print("AXPress result: \(result.rawValue)")
