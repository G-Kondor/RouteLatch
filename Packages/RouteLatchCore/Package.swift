// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RouteLatchCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [.library(name: "RouteLatchCore", targets: ["RouteLatchCore"])],
    targets: [
        .target(name: "RouteLatchCore"),
        .testTarget(
            name: "RouteLatchCoreTests",
            dependencies: ["RouteLatchCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
