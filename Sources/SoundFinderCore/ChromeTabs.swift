import AppKit
import ApplicationServices
import Foundation

public enum ChromeAudioState: String, Codable {
    case playing, muted
}

public struct ChromeTab: Codable, Equatable {
    public let pid: Int32
    public let launchTime: Double?
    public let path: [Int]
    public let title: String
    public let label: String
    public let state: ChromeAudioState
    public let selected: Bool
    public let appPath: String

    public init(pid: Int32, launchTime: Double? = nil, path: [Int], title: String,
                label: String, state: ChromeAudioState, selected: Bool, appPath: String) {
        self.pid = pid
        self.launchTime = launchTime
        self.path = path
        self.title = title
        self.label = label
        self.state = state
        self.selected = selected
        self.appPath = appPath
    }

    public var argument: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return "chrome-tab:" + json
    }

    public static func from(argument: String) -> ChromeTab? {
        guard argument.hasPrefix("chrome-tab:"), argument.utf8.count < 32_768,
              let tab = try? JSONDecoder().decode(ChromeTab.self,
                  from: Data(argument.dropFirst("chrome-tab:".count).utf8)),
              tab.pid > 0, !tab.path.isEmpty, tab.path.count <= 32,
              tab.path.allSatisfy({ $0 >= 0 && $0 < 20_000 }),
              !tab.title.isEmpty else { return nil }
        return tab
    }
}

public struct ChromeScanResult: Codable {
    public let tabs: [ChromeTab]
    public let warnings: [String]
    public let needsPermission: Bool
    public let scannedTabCount: Int
    public init(tabs: [ChromeTab] = [], warnings: [String] = [],
                needsPermission: Bool = false, scannedTabCount: Int = 0) {
        self.tabs = tabs
        self.warnings = warnings
        self.needsPermission = needsPermission
        self.scannedTabCount = scannedTabCount
    }
}

/// Chrome appends its audio state before an optional memory-use annotation.
/// Only match the final state component, not arbitrary occurrences in a page title.
public enum ChromeAudioLabel {
    public static func withoutMemory(_ label: String) -> String {
        let pattern = #" - (?:High memory usage|Memory usage) - [0-9.,]+\s*(?:B|kB|KB|MB|GB|TB)$"#
        return label.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    public static func parse(_ label: String) -> (title: String, state: ChromeAudioState)? {
        let label = withoutMemory(label)
        // English labels are verified on the user's installed Chrome.
        for (suffix, state) in [
            (" - Audio playing", ChromeAudioState.playing),
            (" - Audio muted", ChromeAudioState.muted)
        ] where label.hasSuffix(suffix) {
            let title = String(label.dropLast(suffix.count))
            if !title.isEmpty { return (title, state) }
        }
        return nil
    }
}

public final class ChromeTabScanner {
    private let language: Language
    public init(language: Language = .current) { self.language = language }
    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
            return nil
        }
        return result
    }
    private func label(_ element: AXUIElement) -> String {
        value(element, kAXTitleAttribute) as? String
            ?? value(element, kAXDescriptionAttribute) as? String ?? ""
    }
    private var apps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.google.Chrome" && $0.activationPolicy == .regular
        }
    }

    public func scan() -> ChromeScanResult {
        let apps = self.apps
        guard !apps.isEmpty else { return ChromeScanResult() }
        guard AXIsProcessTrusted() else {
            return ChromeScanResult(needsPermission: true)
        }
        var tabs: [ChromeTab] = []
        var warnings: [String] = []
        var visited = 0
        var scannedTabs = 0
        let deadline = Date().addingTimeInterval(1.0)
        var capped = false
        var readFailed = false

        func walk(_ element: AXUIElement, path: [Int], app: NSRunningApplication,
                  insideTabs: Bool) {
            guard path.count <= 32, visited < 20_000, Date() < deadline else {
                capped = true
                return
            }
            visited += 1
            guard let role = value(element, kAXRoleAttribute) as? String else {
                readFailed = true
                return
            }
            // Do not traverse DOM/page content, address bars, or extension toolbar controls.
            guard role != "AXWebArea", role != "AXToolbar" else { return }
            let inTabs = insideTabs || role == "AXTabGroup"
            if inTabs && (role == "AXRadioButton" || role == "AXTab") {
                scannedTabs += 1
                let rawLabel = label(element)
                if let parsed = ChromeAudioLabel.parse(rawLabel) {
                    let selected = (value(element, kAXValueAttribute) as? NSNumber)?.boolValue ?? false
                    tabs.append(ChromeTab(pid: app.processIdentifier,
                        launchTime: app.launchDate?.timeIntervalSince1970, path: path,
                        title: parsed.title, label: rawLabel, state: parsed.state,
                        selected: selected, appPath: app.bundleURL?.path ?? "/Applications/Google Chrome.app"))
                }
                return
            }
            var rawChildren: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element,
                kAXChildrenAttribute as CFString, &rawChildren)
            guard status == .success else {
                if status != .noValue && status != .attributeUnsupported { readFailed = true }
                return
            }
            for (index, child) in (rawChildren as? [AXUIElement] ?? []).enumerated() {
                if capped { break }
                walk(child, path: path + [index], app: app, insideTabs: inTabs)
            }
        }

        for app in apps {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.1)
            guard let windows = value(root, kAXWindowsAttribute) as? [AXUIElement] else {
                readFailed = true
                continue
            }
            for (index, window) in windows.enumerated() {
                if capped { break }
                walk(window, path: [index], app: app, insideTabs: false)
            }
        }
        if capped { warnings.append(language.text(
            "Chrome 标签栏扫描超时或达到上限；网页结果可能不完整",
            "Chrome tab scan timed out or reached its limit; tab results may be incomplete")) }
        if readFailed { warnings.append(language.text(
            "部分 Chrome 辅助功能控件读取失败；网页结果可能不完整",
            "Some Chrome Accessibility controls could not be read; tab results may be incomplete")) }
        if scannedTabs == 0 && warnings.isEmpty {
            warnings.append(language.text("未能读取 Chrome 标签栏；应用级结果仍可使用",
                                          "Could not read Chrome's tab strip; app-level results are still available"))
        }
        return ChromeScanResult(tabs: tabs, warnings: warnings, scannedTabCount: scannedTabs)
    }

    public func activate(_ expected: ChromeTab) -> String {
        guard AXIsProcessTrusted() else {
            return language.text("无法跳转：请先授权辅助功能权限。",
                                 "Unable to switch: grant Accessibility permission first.")
        }
        guard let app = apps.first(where: { $0.processIdentifier == expected.pid }),
              app.launchDate?.timeIntervalSince1970 == expected.launchTime else {
            return language.text("未跳转：Chrome 已退出或重新启动，请重新输入 sound。",
                                 "Not switched: Chrome exited or restarted. Run sound again.")
        }
        let current = scan()
        let matches = current.tabs.filter { $0.pid == expected.pid && $0.title == expected.title }
        // Do not guess when matching labels are ambiguous or tabs were reordered.
        guard current.warnings.isEmpty, matches.count == 1,
              let tab = matches.first, tab.path == expected.path, tab.state == expected.state else {
            return language.text("未跳转：标签页已变化、停止播放或标题重复，请重新输入 sound。",
                                 "Not switched: tab changed, playback stopped, or titles are duplicated. Run sound again.")
        }
        let root = AXUIElementCreateApplication(expected.pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard let windows = value(root, kAXWindowsAttribute) as? [AXUIElement],
              let windowIndex = expected.path.first, windows.indices.contains(windowIndex) else {
            return language.text("未跳转：原窗口已变化，请刷新。",
                                 "Not switched: the original window changed. Refresh results.")
        }
        let window = windows[windowIndex]
        var element = window
        for index in expected.path.dropFirst() {
            guard let children = value(element, kAXChildrenAttribute) as? [AXUIElement],
                  children.indices.contains(index) else {
                return language.text("未跳转：标签页位置已变化，请刷新。",
                                     "Not switched: tab position changed. Refresh results.")
            }
            element = children[index]
        }
        guard let parsed = ChromeAudioLabel.parse(label(element)),
              parsed.title == expected.title, parsed.state == expected.state else {
            return language.text("未跳转：目标标签页已变化，请刷新。",
                                 "Not switched: the target tab changed. Refresh results.")
        }
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            return language.text("Chrome 拒绝了标签页切换，请手动打开浏览器。",
                                 "Chrome refused the tab switch. Open the browser manually.")
        }
        // Read back selection instead of treating AXPress success as proof.
        let deadline = Date().addingTimeInterval(0.8)
        var selected = false
        repeat {
            if (value(element, kAXValueAttribute) as? NSNumber)?.boolValue == true {
                selected = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        } while Date() < deadline
        guard selected else {
            return language.text("已请求切换，但未确认标签页选中状态；请查看 Chrome。",
                                 "Switch requested, but tab selection was not confirmed. Check Chrome.")
        }
        // Only unminimize the chosen window after an explicit Return action.
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        guard RunningAppActivation.activate(app) else {
            return language.text("标签页已选中，但 Chrome 未切到前台，请手动查看。",
                                 "Tab selected, but Chrome did not come to the foreground. Check it manually.")
        }
        return language.text("已切换到 Chrome 标签页：", "Switched to Chrome tab: ") + expected.title
    }

    public func requestPermission() -> String {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        return language.text("请在辅助功能中允许 Alfred 或系统提示的 soundfinder，然后重新输入 sound。",
                             "In Accessibility settings, allow Alfred or soundfinder as prompted, then run sound again.")
    }
}
