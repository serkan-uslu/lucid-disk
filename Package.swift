// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LucidDisk",
    platforms: [.macOS(.v14)],
    products: [
        // The core is a library so other editions (for example a private Pro
        // package) can depend on it and add features through its extension points.
        .library(name: "LucidDiskCore", targets: ["LucidDiskCore"]),
        .executable(name: "LucidDisk", targets: ["LucidDisk"])
    ],
    targets: [
        .target(
            name: "LucidDiskCore",
            path: "Sources/LucidDiskCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "LucidDisk",
            dependencies: ["LucidDiskCore"],
            path: "Sources/LucidDisk"
        ),
        .testTarget(
            name: "LucidDiskTests",
            dependencies: ["LucidDiskCore"],
            path: "Tests/LucidDiskTests"
        )
    ]
)
