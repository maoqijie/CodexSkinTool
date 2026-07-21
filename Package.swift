// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodexSkinTool",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CodexSkinCore", targets: ["CodexSkinCore"]),
        .executable(name: "CodexSkinTool", targets: ["CodexSkinTool"]),
        .executable(name: "CodexSkinInjector", targets: ["CodexSkinInjector"]),
    ],
    targets: [
        .target(name: "CodexSkinCore"),
        .executableTarget(
            name: "CodexSkinTool",
            dependencies: ["CodexSkinCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "CodexSkinInjector",
            dependencies: ["CodexSkinCore"]
        ),
        .executableTarget(
            name: "CodexSkinCoreChecks",
            dependencies: ["CodexSkinCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
