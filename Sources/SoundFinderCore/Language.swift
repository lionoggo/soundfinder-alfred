import Foundation

/// Workflow UI language, independent of Chrome's native audio-marker language.
public enum Language: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public static var current: Language {
        resolve(setting: ProcessInfo.processInfo.environment["soundfinder_language"],
                preferredLanguages: Locale.preferredLanguages)
    }

    public static func resolve(setting: String?, preferredLanguages: [String]) -> Language {
        let setting = setting?.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-").lowercased() ?? "auto"
        if setting == "en" || setting.hasPrefix("en-") { return .english }
        if setting == "zh" || setting == "zh-hans" || setting == "zh-cn" {
            return .simplifiedChinese
        }
        // Follow the first system preference, not any Chinese entry further down
        // the fallback list. Unsupported languages (including Traditional Chinese)
        // use English rather than claiming a translation we do not provide.
        let preferred = preferredLanguages.first?
            .replacingOccurrences(of: "_", with: "-").lowercased() ?? "en"
        if preferred == "zh" || preferred == "zh-cn" || preferred.hasPrefix("zh-hans") {
            return .simplifiedChinese
        }
        return .english
    }

    public func text(_ chinese: String, _ english: String) -> String {
        self == .simplifiedChinese ? chinese : english
    }
}
