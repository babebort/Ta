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
        .library(name: "TaAgentClient", targets: ["TaAgentClient"]),
        .executable(name: "AIScreenshotApp", targets: ["AIScreenshotApp"])
    ],
    targets: [
        .target(name: "TaAgentContracts"),
        .target(
            name: "TaAgentClient",
            dependencies: ["TaAgentContracts"]
        ),
        .target(
            name: "AIScreenshotCore",
            linkerSettings: [
                .linkedFramework("Vision")
            ]
        ),
        .executableTarget(
            name: "AIScreenshotApp",
            dependencies: ["AIScreenshotCore", "TaAgentContracts", "TaAgentClient"],
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
            name: "TaAgentClientTests",
            dependencies: ["TaAgentClient", "TaAgentContracts"]
        ),
        .testTarget(
            name: "AIScreenshotAppTests",
            dependencies: ["AIScreenshotApp", "AIScreenshotCore", "TaAgentClient", "TaAgentContracts"]
        )
    ]
)
