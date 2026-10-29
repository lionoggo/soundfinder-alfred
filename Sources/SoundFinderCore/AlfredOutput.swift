import Foundation

public enum AlfredOutput {
    public static func make(result: ScanResult, query: String = "",
                            chrome: ChromeScanResult = ChromeScanResult()) -> [String: Any] {
        let grouped = Dictionary(grouping: result.sources) {
            $0.appPath ?? "pid:\($0.pid)"
        }
        var items: [[String: Any]] = grouped.values.map { sources in
            let ordered = sources.sorted { $0.pid < $1.pid }
            let first = ordered[0]
            let name = first.appName ?? first.processName
            let pids = ordered.map { String($0.pid) }.joined(separator: ", ")
            let devices = Array(Set(ordered.flatMap(\.devices))).sorted().joined(separator: "、")
            let details = ordered.map {
                "PID \($0.pid): \($0.processName)\n路径：\($0.executablePath ?? "未知")"
                    + "\n音频 Bundle ID：\($0.bundleID ?? "未知")"
            }.joined(separator: "\n\n")
            let isBrowser = name.localizedCaseInsensitiveContains("chrome")
                || name.localizedCaseInsensitiveContains("safari")
                || name.localizedCaseInsensitiveContains("browser")
                || name.localizedCaseInsensitiveContains("firefox")
                || name.localizedCaseInsensitiveContains("edge")
                || name.localizedCaseInsensitiveContains("arc")
            let hint = first.appPath == nil ? "后台进程：⌘C 复制详情"
                : isBrowser ? "回车打开浏览器，查看标签页声音图标" : "回车切换到应用"
            var item: [String: Any] = [
                "uid": first.appPath ?? "pid:\(first.pid)",
                "title": name,
                "subtitle": "输出流活跃 · PID \(pids)"
                    + (devices.isEmpty ? "" : " · \(devices)") + " · \(hint)",
                "valid": first.appPath != nil,
                "arg": first.appPath ?? "",
                "match": ([name, pids, devices] + ordered.map(\.processName)
                          + ordered.compactMap(\.bundleID)).joined(separator: " "),
                "text": ["copy": "\(name)\n\(details)\n输出设备：\(devices)\n"
                    + "提示：输出流活跃不等于实际可听见的声音。",
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
            let state = tab.state == .playing ? "Chrome 标记：正在发声" : "Chrome 标记：已静音"
            return [
                "uid": "chrome:\(tab.pid):\(tab.path.map(String.init).joined(separator: "."))",
                "title": "Chrome · \(tab.title)",
                "subtitle": "\(state) · \(tab.selected ? "当前标签页" : "后台标签页") · 回车跳转",
                "valid": true, "arg": tab.argument,
                "match": "chrome google chrome \(tab.title) \(state)",
                "icon": ["type": "fileicon", "path": tab.appPath],
                "text": ["copy": "\(tab.title)\n\(state)\n辅助功能标签：\(tab.label)",
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
                "title": result.sources.isEmpty && chrome.tabs.isEmpty ? "暂未发现活跃音频输出流" : "没有匹配的声音来源",
                "subtitle": result.sources.isEmpty && chrome.tabs.isEmpty
                    ? "每 2 秒刷新；短促提示音可能错过，静音输出流也可能列入"
                    : "可以按应用名、进程名、PID 或输出设备搜索",
                "valid": false
            ])
        }
        for warning in result.warnings {
            items.append(["title": "检测结果可能不完整", "subtitle": warning, "valid": false])
        }
        if chrome.needsPermission {
            items.append([
                "uid": "chrome-permission", "title": "授权 Chrome 标签页检测",
                "subtitle": "无需扩展；回车打开辅助功能设置。未授权时仍可检测应用。",
                "valid": true, "arg": "chrome-permissions"
            ])
        }
        for warning in chrome.warnings {
            items.append(["title": "Chrome 网页结果可能不完整", "subtitle": warning, "valid": false])
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

    public static func failure(_ message: String) -> [String: Any] {
        ["items": [["title": "无法读取声音来源", "subtitle": message, "valid": false,
                    "icon": ["path": "icon.png"]]], "rerun": 2.0]
    }
}
