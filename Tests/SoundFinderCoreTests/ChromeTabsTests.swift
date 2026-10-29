import Foundation
import XCTest
@testable import SoundFinderCore

final class ChromeTabsTests: XCTestCase {
    private let tab = ChromeTab(pid: 42, launchTime: 123, path: [0, 2, 1],
        title: "测试 \"网页\"", label: "测试 \"网页\" - Audio playing - Memory usage - 79.5 MB",
        state: .playing, selected: false, appPath: "/Applications/Google Chrome.app")

    func testVerifiedAudioLabelsAndMemoryAnnotations() {
        XCTAssertEqual(ChromeAudioLabel.parse("测试 - Audio playing")?.title, "测试")
        XCTAssertEqual(ChromeAudioLabel.parse("测试 - Audio muted")?.state, .muted)
        XCTAssertEqual(ChromeAudioLabel.parse("测试 - Audio playing - Memory usage - 79.5 MB")?.state, .playing)
        XCTAssertEqual(ChromeAudioLabel.parse("测试 - Audio muted - High memory usage - 1.2 GB")?.title, "测试")
        XCTAssertNil(ChromeAudioLabel.parse("教程 - Audio playing 如何检测"))
        XCTAssertNil(ChromeAudioLabel.parse("测试 - Memory usage - 42.0 MB"))
        XCTAssertNil(ChromeAudioLabel.parse("测试 - Microphone recording"))
    }

    func testArgumentRoundTripsWithoutShellEvaluation() {
        XCTAssertEqual(ChromeTab.from(argument: tab.argument), tab)
        XCTAssertNil(ChromeTab.from(argument: "chrome-tab:$(open /Applications/App.app)"))
        let invalid = ChromeTab(pid: 42, path: [-1], title: "测试", label: "测试 - Audio playing",
                                state: .playing, selected: false, appPath: "/Applications/Chrome.app")
        XCTAssertNil(ChromeTab.from(argument: invalid.argument))
    }

    func testChromeRowsRemainAvailableWithoutCoreAudioSources() throws {
        let output = AlfredOutput.make(result: ScanResult(sources: []),
                                       chrome: ChromeScanResult(tabs: [tab]))
        let items = try XCTUnwrap(output["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["arg"] as? String, tab.argument)
        XCTAssertTrue((items[0]["subtitle"] as? String ?? "").contains("后台标签页"))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(output))
    }

    func testPermissionIsExplicitAndKeepsApplicationFallback() throws {
        let output = AlfredOutput.make(result: ScanResult(sources: [
            AudioSource(pid: 9, processName: "Chrome", appName: "Google Chrome",
                        appPath: "/Applications/Google Chrome.app")
        ]), chrome: ChromeScanResult(needsPermission: true))
        let items = try XCTUnwrap(output["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0]["title"] as? String, "Google Chrome")
        XCTAssertEqual(items[1]["arg"] as? String, "chrome-permissions")
    }

    func testFilterMatchesChromeTabTitleAndReportsPartialResults() throws {
        let items = try XCTUnwrap(AlfredOutput.make(result: ScanResult(sources: []),
            query: "chrome 网页", chrome: ChromeScanResult(tabs: [tab], warnings: ["超时"]))["items"]
                                 as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue((items[0]["title"] as? String ?? "").contains("网页"))
        XCTAssertEqual(items[1]["title"] as? String, "Chrome 网页结果可能不完整")
    }
}
