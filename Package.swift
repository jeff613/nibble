// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nibble",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NibbleCore"),
        .executableTarget(name: "Nibble", dependencies: ["NibbleCore"]),
        .testTarget(name: "NibbleTests", dependencies: ["NibbleCore"]),
    ]
)
