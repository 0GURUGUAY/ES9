// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ES9Mixer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ES9Mixer", targets: ["ES9Mixer"])],
    targets: [
        .target(name: "MixerCore"),
        .executableTarget(name: "ES9Mixer", dependencies: ["MixerCore"]),
        .executableTarget(name: "MixerCoreTests", dependencies: ["MixerCore"], path: "Tests/MixerCoreTests")
    ]
)
