// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RambuPuckAgent",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RambuPuckAgentCore", targets: ["RambuPuckAgentCore"]),
        .executable(name: "rambu-puck-agent", targets: ["rambu-puck-agent"]),
    ],
    targets: [
        .target(name: "RambuPuckAgentCore"),
        .executableTarget(
            name: "rambu-puck-agent",
            dependencies: ["RambuPuckAgentCore"]
        ),
        .target(
            name: "RambuPuckController",
            dependencies: ["RambuPuckAgentCore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "RambuPuckAgentCoreTests",
            dependencies: ["RambuPuckAgentCore"]
        ),
        .testTarget(
            name: "RambuPuckControllerTests",
            dependencies: ["RambuPuckController", "RambuPuckAgentCore"]
        ),
    ]
)
