import Foundation

public enum AlfredOutput {
    public static func make(result: ScanResult, query: String = "",
                            chrome: ChromeScanResult = ChromeScanResult(),
                            language: Language = .current) -> [String: Any] {
        let grouped = Dictionary(grouping: result.sources) {
            $0.appPath ?? "pid:\($0.pid)"
        }
        var items: [[String: Any]] = grouped.values.map { sources in
            let ordered = sources.sorted { $0.pid < $1.pid }
            let first = ordered[0]
            let name = first.appName ?? first.processName
            let pids = ordered.map { String($0.pid) }.joined(separator: ", ")
            let devices = Array(Set(ordered.flatMap(\.devices))).sorted()
                .joined(separator: language.text("、", ", "))
            let unknown = language.text("未知", "Unknown")
            let details = ordered.map {
                "PID \($0.pid): \($0.processName)\n"
                    + language.text("路径：", "Path: ") + ($0.executablePath ?? unknown)
                    + "\n" + language.text("音频 Bundle ID：", "Audio Bundle ID: ")
                    + ($0.bundleID ?? unknown)
            }.joined(separator: "\n\n")
            let isBrowser = name.localizedCaseInsensitiveContains("chrome")
                || name.localizedCaseInsensitiveContains("safari")
                || name.localizedCaseInsensitiveContains("browser")
                || name.localizedCaseInsensitiveContains("firefox")
                || name.localizedCaseInsensitiveContains("edge")
                || name.localizedCaseInsensitiveContains("arc")
            let hint = first.appPath == nil
                ? language.text("后台进程：⌘C 复制详情", "Background process: ⌘C to copy details")
                : isBrowser
                    ? language.text("回车打开浏览器，查看标签页声音图标",
                                    "Return to focus browser and check tab audio icons")
                    : language.text("回车切换到应用", "Return to focus app")
            var item: [String: Any] = [
                "uid": first.appPath ?? "pid:\(first.pid)",
                "title": name,
                "subtitle": language.text("输出流活跃", "Active output stream") + " · PID \(pids)"
                    + (devices.isEmpty ? "" : " · \(devices)") + " · \(hint)",
                "valid": first.appPath != nil,
                "arg": first.appPath ?? "",
                "match": ([name, pids, devices] + ordered.map(\.processName)
                          + ordered.compactMap(\.bundleID)).joined(separator: " "),
                "text": ["copy": "\(name)\n\(details)\n"
                    + language.text("输出设备：", "Output devices: ") + "\(devices)\n"
                    + language.text("提示：输出流活跃不等于实际可听见的声音。",
                                    "Note: an active output stream does not necessarily mean audible sound."),
                         "largetype": "\(name)\nPID \(pids)\n\(devices)"]
            ]
            if let path = first.appPath { item["icon"] = ["type": "fileicon", "path": path] }
            return item
        }
        items.sort { ($0["title"] as? String ?? "") < ($1["title"] as? String ?? "") }
        let chromeItems: [[String: Any]] = chrome.tabs.sorted {
            if $0.state != $1.state { return $0.state == .playing }
            return $0.title < $1.title
        }.map { tab in
            let state = tab.state == .playing
                ? language.text("Chrome 标记：正在发声", "Chrome marker: Audio playing")
                : language.text("Chrome 标记：已静音", "Chrome marker: Audio muted")
            let selection = tab.selected
                ? language.text("当前标签页", "Current tab")
                : language.text("后台标签页", "Background tab")
            return [
                "uid": "chrome:\(tab.pid):\(tab.path.map(String.init).joined(separator: "."))",
                "title": "Chrome · \(tab.title)",
                "subtitle": "\(state) · \(selection) · " + language.text("回车跳转", "Return to focus tab"),
                "valid": true, "arg": tab.argument,
                "match": "chrome google chrome \(tab.title) \(state) "
                    + (tab.state == .playing ? "playing 正在发声" : "muted 已静音"),
                "icon": ["type": "fileicon", "path": tab.appPath],
                "text": ["copy": "\(tab.title)\n\(state)\n"
                    + language.text("辅助功能标签：", "Accessibility label: ") + tab.label,
                         "largetype": "\(tab.title)\n\(state)"]
            ]
        }
        items = chromeItems + items
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if !terms.isEmpty {
            items = items.filter { item in
                let match = item["match"] as? String ?? ""
                return terms.allSatisfy { match.localizedCaseInsensitiveContains($0) }
            }
        }
        if items.isEmpty {
            items.append([
                "title": result.sources.isEmpty && chrome.tabs.isEmpty
                    ? language.text("暂未发现活跃音频输出流", "No active audio output streams found")
                    : language.text("没有匹配的声音来源", "No matching audio sources"),
                "subtitle": result.sources.isEmpty && chrome.tabs.isEmpty
                    ? language.text("每 2 秒刷新；短促提示音可能错过，静音输出流也可能列入",
                                    "Refreshes every 2 seconds; brief sounds may be missed and silent streams may appear")
                    : language.text("可以按应用名、进程名、PID 或输出设备搜索",
                                    "Search by app, process, PID, or output device"),
                "valid": false
            ])
        }
        for warning in result.warnings {
            items.append(["title": language.text("检测结果可能不完整", "Results may be incomplete"),
                          "subtitle": warning, "valid": false])
        }
        if chrome.needsPermission {
            items.append([
                "uid": "chrome-permission",
                "title": language.text("授权 Chrome 标签页检测", "Authorize Chrome tab detection"),
                "subtitle": language.text("无需扩展；回车打开辅助功能设置。未授权时仍可检测应用。",
                                         "No extension needed. Return to open Accessibility settings; app detection works without permission."),
                "valid": true, "arg": "chrome-permissions"
            ])
        }
        for warning in chrome.warnings {
            items.append(["title": language.text("Chrome 网页结果可能不完整", "Chrome tab results may be incomplete"),
                          "subtitle": warning, "valid": false])
        }
        // Keep application-specific file icons. Use the workflow identity for
        // background processes, empty results, permission prompts, and errors.
        items = items.map { item in
            var item = item
            if item["icon"] == nil { item["icon"] = ["path": "icon.png"] }
            return item
        }
        return ["items": items, "rerun": 2.0, "skipknowledge": true]
    }

    public static func failure(_ message: String, language: Language = .current) -> [String: Any] {
        ["items": [["title": language.text("无法读取声音来源", "Unable to read audio sources"),
                    "subtitle": message, "valid": false,
                    "icon": ["path": "icon.png"]]], "rerun": 2.0]
    }
}
