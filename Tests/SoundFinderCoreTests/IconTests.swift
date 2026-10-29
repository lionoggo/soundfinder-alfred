import XCTest
@testable import SoundFinderCore

final class IconTests: XCTestCase {
    func testBackgroundProcessHasWorkflowIcon() throws {
        let output = AlfredOutput.make(result: ScanResult(sources: [
            AudioSource(pid: 42, processName: "afplay")
        ]))
        let items = try XCTUnwrap(output["items"] as? [[String: Any]])
        let icon = try XCTUnwrap(items[0]["icon"] as? [String: String])
        XCTAssertEqual(icon, ["path": "icon.png"])
    }

    func testApplicationAndChromeIconsArePreserved() throws {
        let tab = ChromeTab(pid: 3, path: [0, 1], title: "测试网页",
            label: "测试网页 - Audio playing", state: .playing,
            selected: false, appPath: "/Applications/Google Chrome.app")
        let output = AlfredOutput.make(result: ScanResult(sources: [
            AudioSource(pid: 42, processName: "Music", appName: "Music",
                        appPath: "/System/Applications/Music.app")
        ]), chrome: ChromeScanResult(tabs: [tab]))
        let items = try XCTUnwrap(output["items"] as? [[String: Any]])
        XCTAssertEqual(items[0]["icon"] as? [String: String],
                       ["type": "fileicon", "path": "/Applications/Google Chrome.app"])
        XCTAssertEqual(items[1]["icon"] as? [String: String],
                       ["type": "fileicon", "path": "/System/Applications/Music.app"])
    }

    func testEmptyResultsWarningsAndPermissionPromptHaveIcon() throws {
        let output = AlfredOutput.make(result: ScanResult(sources: [], warnings: ["失败"]),
            chrome: ChromeScanResult(warnings: ["超时"], needsPermission: true))
        let items = try XCTUnwrap(output["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 4)
        for item in items {
            XCTAssertEqual(item["icon"] as? [String: String], ["path": "icon.png"])
        }
    }

    func testErrorResultHasWorkflowIcon() throws {
        let items = try XCTUnwrap(AlfredOutput.failure("失败")["items"] as? [[String: Any]])
        XCTAssertEqual(items[0]["icon"] as? [String: String], ["path": "icon.png"])
    }
}
