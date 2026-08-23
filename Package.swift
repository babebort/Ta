// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AIScreenshot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AIScreenshotCore", targets: ["AIScreenshotCore"]),
        .executable(name: "AIScreenshotApp", targets: ["AIScreenshotApp"])
    ],
    targets: [
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
            name: "AIScreenshotAppTests",
            dependencies: ["AIScreenshotApp", "AIScreenshotCore"]
        )
    ]
)
