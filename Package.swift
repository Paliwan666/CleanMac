// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CleanMac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CleanMacCore",
            path: "Sources/CleanMacCore"
        ),
        .executableTarget(
            name: "CleanMac",
            dependencies: ["CleanMacCore"],
            path: "Sources/CleanMac"
        ),
        .executableTarget(
            name: "CleanMacSelfTest",
            dependencies: ["CleanMacCore"],
            path: "Sources/CleanMacSelfTest"
        ),
    ]
)
