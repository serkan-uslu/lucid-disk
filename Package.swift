// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LucidDisk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LucidDisk", targets: ["LucidDisk"])
    ],
    targets: [
        .executableTarget(
            name: "LucidDisk",
            path: "Sources/LucidDisk",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LucidDiskTests",
            dependencies: ["LucidDisk"],
            path: "Tests/LucidDiskTests"
        )
    ]
)
