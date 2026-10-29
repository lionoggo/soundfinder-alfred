// Read-only diagnostic: enumerate Chrome's native tab controls, not page content.
import AppKit
import ApplicationServices
import Foundation

func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
        return nil
    }
    return result
}

guard AXIsProcessTrusted() else {
    print("{\"error\":\"辅助功能未授权\"}")
    exit(1)
}
let apps = NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == "com.google.Chrome" && $0.activationPolicy == .regular
}
var tabs: [[String: Any]] = []
var count = 0
var activated = false
let activateProbe = CommandLine.arguments.contains("--activate-probe")
func walk(_ element: AXUIElement, path: [Int], pid: Int32, depth: Int) {
    guard depth < 32, count < 20_000 else { return }
    count += 1
    let role = value(element, kAXRoleAttribute) as? String ?? ""
    guard role != "AXWebArea", role != "AXToolbar" else { return }
    let description = value(element, kAXRoleDescriptionAttribute) as? String ?? ""
    if role == "AXRadioButton" || role == "AXTab" {
        var tab: [String: Any] = ["pid": pid, "path": path, "role": role,
                                 "roleDescription": description]
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute,
                          kAXIdentifierAttribute, kAXValueAttribute, kAXURLAttribute] {
            if let item = value(element, attribute) {
                tab[attribute] = (item as? String) ?? String(describing: item)
            }
        }
        var actionNames: CFArray?
        AXUIElementCopyActionNames(element, &actionNames)
        tab["actions"] = actionNames as? [String] ?? []
        tabs.append(tab)
        if activateProbe, !activated,
           (tab[kAXTitleAttribute] as? String ?? "").hasPrefix("SoundFinder AX 验证 - Audio playing") {
            let status = AXUIElementPerformAction(element, kAXPressAction as CFString)
            activated = status == .success
        }
        return
    }
    let children = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    for (index, child) in children.enumerated() {
        walk(child, path: path + [index], pid: pid, depth: depth + 1)
    }
}
for app in apps {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.3)
    let windows = value(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
    for (index, window) in windows.enumerated() {
        walk(window, path: [index], pid: app.processIdentifier, depth: 0)
    }
}
let output = try JSONSerialization.data(withJSONObject:
    ["tabs": tabs, "visitedNodes": count, "activatedProbe": activated], options: [.sortedKeys])
print(String(decoding: output, as: UTF8.self))
