import AppKit
import CoreAudio
import Darwin
import Foundation

public struct AudioSource: Codable, Equatable {
    public let pid: Int32
    public let processName: String
    public let bundleID: String?
    public let appName: String?
    public let appPath: String?
    public let executablePath: String?
    public let devices: [String]

    public init(pid: Int32, processName: String, bundleID: String? = nil,
                appName: String? = nil, appPath: String? = nil,
                executablePath: String? = nil, devices: [String] = []) {
        self.pid = pid
        self.processName = processName
        self.bundleID = bundleID
        self.appName = appName
        self.appPath = appPath
        self.executablePath = executablePath
        self.devices = devices
    }
}

public struct ScanResult: Codable {
    public let sources: [AudioSource]
    public let warnings: [String]
    public init(sources: [AudioSource], warnings: [String] = []) {
        self.sources = sources
        self.warnings = warnings
    }
}

public struct AudioReadError: LocalizedError {
    let operation: String
    let status: OSStatus
    var language: Language = .current
    public var errorDescription: String? {
        language.text("\(operation)失败（Core Audio \(status)）",
                      "\(operation) failed (Core Audio \(status))")
    }
}

/// First .app component is the owning application, not a nested browser Helper.
public func owningAppPath(of executable: String) -> String? {
    let components = URL(fileURLWithPath: executable).standardized.pathComponents
    guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
    return NSString.path(withComponents: Array(components.prefix(index + 1)))
}

public func resolvedAppPath(executable: String?, reportedAppPath: String?) -> String? {
    if let executable, let path = owningAppPath(of: executable) { return path }
    // NSRunningApplication.bundleURL can point to a bare executable, e.g. headless Chromium.
    guard let reportedAppPath, reportedAppPath.hasSuffix(".app") else { return nil }
    return owningAppPath(of: reportedAppPath)
}

private struct AudioProperties {
    let language: Language
    func address(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                   initial: T) throws -> T {
        var property = address(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
        }
        guard status == noErr, size == MemoryLayout<T>.size else {
            throw AudioReadError(operation: language.text("读取音频属性", "Read audio property"),
                                 status: status == noErr ? -1 : status, language: language)
        }
        return value
    }

    func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws
        -> [AudioObjectID] {
        // Process lists may change between the size query and the data query.
        for _ in 0..<3 {
            var property = address(selector, scope: scope)
            var size: UInt32 = 0
            let sizeStatus = AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size)
            guard sizeStatus == noErr else {
                throw AudioReadError(operation: language.text("读取音频对象列表", "Read audio object list"),
                                     status: sizeStatus, language: language)
            }
            guard size > 0 else { return [] }
            guard size % UInt32(MemoryLayout<AudioObjectID>.size) == 0 else {
                throw AudioReadError(operation: language.text("读取音频对象列表长度", "Read audio object list size"),
                                     status: -1, language: language)
            }
            var values = [AudioObjectID](repeating: 0,
                count: Int(size) / MemoryLayout<AudioObjectID>.size)
            let capacity = size
            let status = values.withUnsafeMutableBytes {
                AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0.baseAddress!)
            }
            if status == kAudioHardwareBadPropertySizeError { continue }
            guard status == noErr, size <= capacity else {
                throw AudioReadError(operation: language.text("读取音频对象列表", "Read audio object list"),
                                     status: status == noErr ? -1 : status, language: language)
            }
            return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
        }
        throw AudioReadError(operation: language.text("音频对象列表正在变化，请重试",
                                                     "Audio object list changed; retry"),
                             status: -1, language: language)
    }
}

public final class AudioScanner {
    private let language: Language
    public init(language: Language = .current) { self.language = language }

    public func scan() throws -> ScanResult {
        let properties = AudioProperties(language: language)
        let objects = try properties.ids(AudioObjectID(kAudioObjectSystemObject),
                                         kAudioHardwarePropertyProcessObjectList)
        let apps = NSWorkspace.shared.runningApplications
        var sources: [AudioSource] = []
        var skipped = 0
        for object in objects {
            do {
                let running: UInt32 = try properties.scalar(
                    object, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))
                guard running != 0 else { continue }
                let pid: Int32 = try properties.scalar(
                    object, kAudioProcessPropertyPID, initial: Int32(0))
                guard pid > 0 else { continue }
                let executable = Self.executablePath(pid)
                let bundleID = properties.string(object, kAudioProcessPropertyBundleID)
                let directApp = apps.first { $0.processIdentifier == pid }
                let appPath = resolvedAppPath(executable: executable,
                                             reportedAppPath: directApp?.bundleURL?.path)
                let owner = apps.first {
                    guard let appPath else { return false }
                    return $0.bundleURL?.standardizedFileURL.path == appPath
                        && $0.activationPolicy != .prohibited
                }
                let resolvedPath = appPath
                let appBundle = resolvedPath.flatMap { Bundle(path: $0) }
                let appName = owner?.localizedName
                    ?? appBundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? appBundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? resolvedPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
                let deviceIDs = (try? properties.ids(object, kAudioProcessPropertyDevices,
                                                     scope: kAudioObjectPropertyScopeOutput)) ?? []
                let devices = deviceIDs.map {
                    properties.string($0, kAudioObjectPropertyName)
                        ?? language.text("音频设备 \($0)", "Audio device \($0)")
                }
                sources.append(AudioSource(pid: pid,
                    processName: executable.map { URL(fileURLWithPath: $0).lastPathComponent }
                        ?? directApp?.localizedName ?? language.text("进程 \(pid)", "Process \(pid)"),
                    bundleID: bundleID, appName: appName, appPath: resolvedPath,
                    executablePath: executable, devices: devices))
            } catch {
                // Exited processes are common; retain a visible partial-scan warning.
                skipped += 1
            }
        }
        return ScanResult(sources: sources.sorted { $0.pid < $1.pid },
            warnings: skipped == 0 ? [] : [language.text(
                "有 \(skipped) 个音频对象读取失败或已退出；结果可能不完整",
                "\(skipped) audio objects could not be read or exited; results may be incomplete")])
    }

    public static func executablePath(_ pid: Int32) -> String? {
        // sys/proc_info.h: PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN.
        // Swift cannot import the expression macro directly.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = buffer.withUnsafeMutableBytes {
            proc_pidpath(pid, $0.baseAddress!, UInt32($0.count))
        }
        guard count > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Only focuses an already-running app, never launches a new instance.
    public func activate(appPath: String) throws -> Bool {
        let result = try scan()
        guard result.sources.contains(where: { $0.appPath == appPath }) else { return false }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: appPath).standardizedFileURL.path
                && $0.activationPolicy != .prohibited
        }) else { return false }
        return RunningAppActivation.activate(app)
    }
}
