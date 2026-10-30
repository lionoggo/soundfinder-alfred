import Foundation
import SoundFinderCore

func printJSON(_ object: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "alfred"
let language = Language.current
let scanner = AudioScanner(language: language)
let chromeScanner = ChromeTabScanner(language: language)
let chromeEnabled = !["0", "false", "off"].contains(
    ProcessInfo.processInfo.environment["soundfinder_chrome_ax"]?.lowercased() ?? "1")

do {
    switch command {
    case "alfred":
        let chrome = chromeEnabled ? chromeScanner.scan() : ChromeScanResult()
        let audio: ScanResult
        do { audio = try scanner.scan() }
        catch { audio = ScanResult(sources: [], warnings: [error.localizedDescription]) }
        try printJSON(AlfredOutput.make(result: audio,
            query: args.dropFirst().joined(separator: " "), chrome: chrome, language: language))
    case "chrome-list":
        let data = try JSONEncoder().encode(chromeScanner.scan())
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    case "list":
        let data = try JSONEncoder().encode(scanner.scan())
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    case "activate":
        guard args.count == 2 else {
            throw NSError(domain: "SoundFinder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            language.text("缺少目标应用路径", "Missing target app path")])
        }
        if args[1] == "chrome-permissions" {
            print(chromeScanner.requestPermission())
        } else if args[1].hasPrefix("chrome-tab:") {
            if let tab = ChromeTab.from(argument: args[1]) {
                print(chromeScanner.activate(tab))
            } else {
                print(language.text("无法跳转：标签页参数无效，请重新输入 sound。",
                                    "Unable to switch: invalid tab argument. Run sound again."))
            }
        } else if try scanner.activate(appPath: args[1]) {
            print(language.text("已切换到 ", "Switched to ")
                  + URL(fileURLWithPath: args[1]).deletingPathExtension().lastPathComponent)
        } else {
            print(language.text("未切换：该来源已停止输出、应用已退出，或无法激活。重新输入 sound 刷新。",
                                "Not switched: output stopped, the app exited, or activation failed. Run sound to refresh."))
        }
    default:
        throw NSError(domain: "SoundFinder", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: language.text(
                        "用法：soundfinder alfred [搜索词] | list | chrome-list | activate <目标>",
                        "Usage: soundfinder alfred [query] | list | chrome-list | activate <target>")])
    }
} catch {
    if command == "activate" {
        print(language.text("无法切换：", "Unable to switch: ") + error.localizedDescription)
    } else {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    }
    exit(1)
}
