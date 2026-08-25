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
        .executable(name: "ta", targets: ["TaCLI"]),
        .executable(name: "AIScreenshotApp", targets: ["AIScreenshotApp"])
    ],
    targets: [
        .target(name: "TaAgentContracts"),
        .target(
            name: "TaAgentClient",
            dependencies: ["TaAgentContracts"],
            linkerSettings: [.linkedFramework("AppKit")]
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
        .executableTarget(
            name: "TaCLI",
            dependencies: ["TaAgentClient", "TaAgentContracts"]
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
            name: "TaCLITests",
            dependencies: ["TaCLI", "TaAgentContracts"]
        ),
        .testTarget(
            name: "AIScreenshotAppTests",
            dependencies: ["AIScreenshotApp", "AIScreenshotCore", "TaAgentClient", "TaAgentContracts"]
        )
    ]
)
