// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoundFinder",
    platforms: [.macOS("14.4")],
    products: [.executable(name: "soundfinder", targets: ["SoundFinder"])],
    targets: [
        .target(name: "SoundFinderCore"),
        .executableTarget(name: "SoundFinder", dependencies: ["SoundFinderCore"]),
        .testTarget(name: "SoundFinderCoreTests", dependencies: ["SoundFinderCore"])
    ]
)
