import Foundation
import XCTest
@testable import SoundFinderCore

final class LanguageTests: XCTestCase {
    func testExplicitSelectionOverridesSystemLanguage() {
        for setting in ["en", " EN ", "en-US", "en_GB"] {
            XCTAssertEqual(Language.resolve(setting: setting, preferredLanguages: ["zh-Hans-CN"]), .english)
        }
        for setting in ["zh-Hans", " zh-hans ", "zh_CN", "zh"] {
            XCTAssertEqual(Language.resolve(setting: setting, preferredLanguages: ["en-US"]), .simplifiedChinese)
        }
    }

    func testAutomaticAndInvalidSettingsFollowFirstPreference() {
        for setting in [nil, "", "auto", "invalid", "fr"] as [String?] {
            XCTAssertEqual(Language.resolve(setting: setting, preferredLanguages: ["zh-Hans-CN", "en"]), .simplifiedChinese)
            XCTAssertEqual(Language.resolve(setting: setting, preferredLanguages: ["en-US", "zh-Hans"]), .english)
            XCTAssertEqual(Language.resolve(setting: setting, preferredLanguages: ["de-DE", "zh-Hans"]), .english)
            XCTAssertEqual(Language.resolve(setting: setting, preferredLanguages: []), .english)
        }
        XCTAssertEqual(Language.resolve(setting: "auto", preferredLanguages: ["zh_CN"]), .simplifiedChinese)
        XCTAssertEqual(Language.resolve(setting: "auto", preferredLanguages: ["zh-Hant-TW"]), .english)
    }

    private func rows(_ output: [String: Any]) throws -> [[String: Any]] {
        XCTAssertTrue(JSONSerialization.isValidJSONObject(output))
        return try XCTUnwrap(output["items"] as? [[String: Any]])
    }

    func testBothLanguagesCoverAppAndBackgroundRowsWithoutChangingIdentity() throws {
        let result = ScanResult(sources: [
            AudioSource(pid: 42, processName: "Player", appName: "用户的应用",
                        appPath: "/Applications/用户的应用.app", devices: ["耳机", "USB"]),
            AudioSource(pid: 43, processName: "afplay")
        ])
        let en = try rows(AlfredOutput.make(result: result, language: .english))
        let zh = try rows(AlfredOutput.make(result: result, language: .simplifiedChinese))
        for (english, chinese) in zip(en, zh) {
            for key in ["uid", "arg", "title"] {
                XCTAssertEqual(english[key] as? String, chinese[key] as? String)
            }
        }
        XCTAssertTrue((en[0]["subtitle"] as? String ?? "").contains("Background process"))
        XCTAssertTrue((zh[0]["subtitle"] as? String ?? "").contains("后台进程"))
        XCTAssertTrue((en[1]["subtitle"] as? String ?? "").contains("Active output stream"))
        let copy = try XCTUnwrap((en[1]["text"] as? [String: String])?["copy"])
        XCTAssertTrue(copy.contains("Path: Unknown"))
        XCTAssertTrue(copy.contains("Audio Bundle ID: Unknown"))
        XCTAssertTrue(copy.contains("Output devices:"))
        XCTAssertTrue(copy.contains("耳机"))
        XCTAssertTrue(copy.contains("does not necessarily mean audible sound"))
    }

    func testChromePlayingMutedSelectionAndPermissionInBothLanguages() throws {
        let tabs = [
            ChromeTab(pid: 42, path: [0, 1], title: "中文网页",
                      label: "中文网页 - Audio playing", state: .playing,
                      selected: false, appPath: "/Applications/Google Chrome.app"),
            ChromeTab(pid: 42, path: [0, 2], title: "Muted video",
                      label: "Muted video - Audio muted", state: .muted,
                      selected: true, appPath: "/Applications/Google Chrome.app")
        ]
        for language in Language.allCases {
            let items = try rows(AlfredOutput.make(result: ScanResult(sources: []),
                chrome: ChromeScanResult(tabs: tabs, needsPermission: true), language: language))
            XCTAssertEqual(items[0]["arg"] as? String, tabs[0].argument)
            XCTAssertTrue((items[0]["subtitle"] as? String ?? "").contains(
                language.text("正在发声", "Audio playing")))
            XCTAssertTrue((items[0]["subtitle"] as? String ?? "").contains(
                language.text("后台标签页", "Background tab")))
            XCTAssertTrue((items[1]["subtitle"] as? String ?? "").contains(
                language.text("已静音", "Audio muted")))
            XCTAssertTrue((items[1]["subtitle"] as? String ?? "").contains(
                language.text("当前标签页", "Current tab")))
            XCTAssertEqual(items[2]["title"] as? String,
                           language.text("授权 Chrome 标签页检测", "Authorize Chrome tab detection"))
            XCTAssertEqual(items[2]["arg"] as? String, "chrome-permissions")
            // Changing UI language must not change English marker parsing.
            XCTAssertEqual(ChromeAudioLabel.parse(tabs[0].label)?.title, tabs[0].title)
        }
    }

    func testEmptyFilteredWarningAndFailureRowsInBothLanguages() throws {
        for language in Language.allCases {
            let empty = try rows(AlfredOutput.make(result: ScanResult(sources: []), language: language))
            XCTAssertEqual(empty[0]["title"] as? String, language.text(
                "暂未发现活跃音频输出流", "No active audio output streams found"))
            let partial = try rows(AlfredOutput.make(
                result: ScanResult(sources: [], warnings: ["Core Audio 1"]),
                chrome: ChromeScanResult(warnings: ["AX 1"]), language: language))
            XCTAssertEqual(partial[1]["title"] as? String,
                           language.text("检测结果可能不完整", "Results may be incomplete"))
            XCTAssertEqual(partial[2]["title"] as? String,
                           language.text("Chrome 网页结果可能不完整", "Chrome tab results may be incomplete"))
            let filtered = try rows(AlfredOutput.make(result: ScanResult(sources: [
                AudioSource(pid: 1, processName: "Player")
            ]), query: "missing", language: language))
            XCTAssertEqual(filtered[0]["title"] as? String,
                           language.text("没有匹配的声音来源", "No matching audio sources"))
            let failure = try rows(AlfredOutput.failure("OS error", language: language))
            XCTAssertEqual(failure[0]["title"] as? String,
                           language.text("无法读取声音来源", "Unable to read audio sources"))
        }
    }

    func testBilingualStateSearchWorksRegardlessOfUILanguage() throws {
        let tab = ChromeTab(pid: 42, path: [0], title: "Video", label: "Video - Audio muted",
                            state: .muted, selected: false, appPath: "/Applications/Google Chrome.app")
        for language in Language.allCases {
            for query in ["muted", "已静音"] {
                let items = try rows(AlfredOutput.make(result: ScanResult(sources: []), query: query,
                    chrome: ChromeScanResult(tabs: [tab]), language: language))
                XCTAssertEqual(items[0]["arg"] as? String, tab.argument)
            }
        }
    }

    func testAudioErrorsUseSelectedLanguageAndKeepStatusCode() {
        XCTAssertEqual(AudioReadError(operation: "Read audio property", status: -1,
                                      language: .english).errorDescription,
                       "Read audio property failed (Core Audio -1)")
        XCTAssertEqual(AudioReadError(operation: "读取音频属性", status: -1,
                                      language: .simplifiedChinese).errorDescription,
                       "读取音频属性失败（Core Audio -1）")
    }
}
