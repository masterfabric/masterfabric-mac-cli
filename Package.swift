// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MasterFabric",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "mf", targets: ["mf"]),
        .executable(name: "MasterFabricMenuBar", targets: ["MasterFabricMenuBar"]),
        .executable(name: "GenerateScreenshot", targets: ["GenerateScreenshot"]),
        .library(name: "MasterFabricCore", targets: ["MasterFabricCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "MasterFabricCore",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "mf",
            dependencies: [
                "MasterFabricCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "MasterFabricMenuBar",
            dependencies: [
                "MasterFabricCore",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "GenerateScreenshot",
            dependencies: [
                "MasterFabricCore",
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
    ]
)
