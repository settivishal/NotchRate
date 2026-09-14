// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchRate",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "NotchRate", path: "NotchRate", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "NotchRateTests", dependencies: ["NotchRate"], path: "Tests/NotchRateTests"),
    ]
)
