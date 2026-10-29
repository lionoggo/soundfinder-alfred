import Foundation
import XCTest
@testable import SoundFinderCore

final class SoundFinderCoreTests: XCTestCase {
    func testNestedHelperMapsToOuterApplication() {
        XCTAssertEqual(owningAppPath(of:
            "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"),
            "/Applications/Google Chrome.app")
        XCTAssertNil(owningAppPath(of: "/usr/bin/afplay"))
        XCTAssertEqual(owningAppPath(of: "/Applications/测试 空格.app/Contents/MacOS/测试"),
                       "/Applications/测试 空格.app")
    }

    func testAppKitMetadataDoesNotOverrideOwnerOrInventHeadlessApp() {
        XCTAssertEqual(resolvedAppPath(
            executable: "/Applications/抖音开发者工具.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper",
            reportedAppPath: "/Applications/抖音开发者工具.app/Contents/Frameworks/Helper.app"),
            "/Applications/抖音开发者工具.app")
        XCTAssertNil(resolvedAppPath(
            executable: "/tmp/chrome-headless-shell",
            reportedAppPath: "/tmp/chrome-headless-shell"))
        XCTAssertEqual(resolvedAppPath(executable: nil,
            reportedAppPath: "/Applications/App.app/Contents/Helper.app"),
            "/Applications/App.app")
    }

    func testGroupsBrowserHelpersAndKeepsAllPIDs() throws {
        let result = ScanResult(sources: [
            AudioSource(pid: 42, processName: "Chrome Helper", appName: "Google Chrome",
                        appPath: "/Applications/Google Chrome.app", devices: ["耳机"]),
            AudioSource(pid: 43, processName: "Chrome Helper", appName: "Google Chrome",
                        appPath: "/Applications/Google Chrome.app", devices: ["耳机"])
        ])
        let output = AlfredOutput.make(result: result)
        let items = try XCTUnwrap(output["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["arg"] as? String, "/Applications/Google Chrome.app")
        XCTAssertTrue((items[0]["subtitle"] as? String ?? "").contains("42, 43"))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(output))
        XCTAssertEqual(output["rerun"] as? Double, 2)
    }

    func testBackgroundProcessDoesNotInventAnApplication() throws {
        let output = AlfredOutput.make(result: ScanResult(sources: [
            AudioSource(pid: 123, processName: "afplay", executablePath: "/usr/bin/afplay")
        ]))
        let items = try XCTUnwrap(output["items"] as? [[String: Any]])
        XCTAssertEqual(items[0]["valid"] as? Bool, false)
        XCTAssertEqual(items[0]["title"] as? String, "afplay")
    }

    func testSearchByPIDDeviceAndMultipleWords() throws {
        let result = ScanResult(sources: [
            AudioSource(pid: 42, processName: "Helper", appName: "Chrome",
                        appPath: "/Applications/Chrome.app", devices: ["USB 耳机"])
        ])
        for query in ["42", "usb", "CHROME 耳机"] {
            let items = try XCTUnwrap(AlfredOutput.make(result: result, query: query)["items"]
                                     as? [[String: Any]])
            XCTAssertEqual(items[0]["title"] as? String, "Chrome")
        }
        let unmatched = try XCTUnwrap(
            AlfredOutput.make(result: result, query: "不存在")["items"] as? [[String: Any]])
        XCTAssertEqual(unmatched[0]["title"] as? String, "没有匹配的声音来源")
    }

    func testEmptyAndPartialResultsAreNotReportedAsSilence() throws {
        let items = try XCTUnwrap(AlfredOutput.make(result:
            ScanResult(sources: [], warnings: ["读取失败"]))["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0]["title"] as? String, "暂未发现活跃音频输出流")
        XCTAssertEqual(items[1]["title"] as? String, "检测结果可能不完整")
        XCTAssertEqual(items[0]["valid"] as? Bool, false)
    }

    func testErrorIsValidAlfredJSON() {
        let output = AlfredOutput.failure("设备 \"错误\"\n换行")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(output))
    }
}
