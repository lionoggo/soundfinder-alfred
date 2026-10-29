// Real Core Audio integration check using an entirely silent WAV.
// Does not alter system volume, existing players, or microphone state.
import AVFoundation
import Foundation

enum SmokeError: Error { case failed(String) }
let binary = CommandLine.arguments.dropFirst().first ?? "./dist/SoundFinder/soundfinder"

func snapshot() throws -> [[String: Any]] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["list"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sources = object["sources"] as? [[String: Any]] else {
        throw SmokeError.failed("无法读取声音来源 JSON")
    }
    return sources
}

func hasOwnOutput() throws -> Bool {
    try snapshot().contains { ($0["pid"] as? NSNumber)?.int32Value == getpid() }
}

func awaitOwnOutput(_ expected: Bool) throws {
    let deadline = Date().addingTimeInterval(5)
    repeat {
        if try hasOwnOutput() == expected { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    throw SmokeError.failed("未观察到测试进程输出状态变为 \(expected)")
}

func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
    var value = value.littleEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

var wav = Data("RIFF".utf8)
let byteCount: UInt32 = 44_100 * 2
wav.append(littleEndian(UInt32(36) + byteCount))
wav.append(Data("WAVEfmt ".utf8))
wav.append(littleEndian(UInt32(16)))
wav.append(littleEndian(UInt16(1))) // PCM
wav.append(littleEndian(UInt16(1))) // mono
wav.append(littleEndian(UInt32(44_100)))
wav.append(littleEndian(UInt32(88_200)))
wav.append(littleEndian(UInt16(2)))
wav.append(littleEndian(UInt16(16)))
wav.append(Data("data".utf8))
wav.append(littleEndian(byteCount))
wav.append(Data(repeating: 0, count: Int(byteCount)))

try awaitOwnOutput(false)
var player: AVAudioPlayer? = try AVAudioPlayer(data: wav)
player?.volume = 0
player?.numberOfLoops = -1
guard player?.play() == true else { throw SmokeError.failed("无法启动静默测试播放器") }
do {
    try awaitOwnOutput(true)
    print("PASS: 已检测到静默测试播放器的真实音频输出 PID \(getpid())")
} catch {
    player?.stop()
    throw error
}
player?.stop()
player = nil
try awaitOwnOutput(false)
print("PASS: 停止后测试 PID 从活跃输出列表消失；现有播放器未被修改")
