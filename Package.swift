// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AIScreenshot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AIScreenshotCore", targets: ["AIScreenshotCore"]),
        .library(name: "TaAgentContracts", targets: ["TaAgentContracts"]),
        .executable(name: "AIScreenshotApp", targets: ["AIScreenshotApp"])
    ],
    targets: [
        .target(name: "TaAgentContracts"),
        .target(
            name: "AIScreenshotCore",
            linkerSettings: [
                .linkedFramework("Vision")
            ]
        ),
        .executableTarget(
            name: "AIScreenshotApp",
            dependencies: ["AIScreenshotCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "AIScreenshotCoreTests",
            dependencies: ["AIScreenshotCore"]
        ),
        .testTarget(
            name: "TaAgentContractsTests",
            dependencies: ["TaAgentContracts"]
        ),
        .testTarget(
            name: "AIScreenshotAppTests",
            dependencies: ["AIScreenshotApp", "AIScreenshotCore"]
        )
    ]
)
