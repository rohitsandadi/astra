// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Astra",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "AstraCore", targets: ["AstraCore"]),
        .executable(name: "Astra", targets: ["Astra"]),
        .executable(name: "AstraEnforcer", targets: ["AstraEnforcer"])
    ],
    targets: [
        .target(
            name: "AstraCore",
            path: "Sources/AstraCore"
        ),
        .executableTarget(
            name: "Astra",
            dependencies: ["AstraCore"],
            path: "Sources/Astra"
        ),
        .executableTarget(
            name: "AstraEnforcer",
            dependencies: ["AstraCore"],
            path: "Sources/AstraEnforcer",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Config/AstraEnforcer-Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "AstraCoreTests",
            dependencies: ["AstraCore"],
            path: "Tests/AstraCoreTests"
        ),
        .testTarget(
            name: "AstraEnforcerTests",
            dependencies: ["AstraCore", "AstraEnforcer"],
            path: "Tests/AstraEnforcerTests"
        ),
        .testTarget(
            name: "AstraTests",
            dependencies: ["Astra"],
            path: "Tests/AstraTests"
        )
    ]
)
