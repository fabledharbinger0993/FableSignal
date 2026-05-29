// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SessionRunner",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "SessionRunner", targets: ["SessionRunner"]),
    ],
    dependencies: [
        .package(path: "../SessionKit"),
        .package(path: "../AudioEngine"),
        .package(path: "../StrobeController"),
    ],
    targets: [
        .target(
            name: "SessionRunner",
            dependencies: [
                .product(name: "SessionKit",        package: "SessionKit"),
                .product(name: "AudioEngine",       package: "AudioEngine"),
                .product(name: "StrobeController",  package: "StrobeController"),
            ]
        ),
        .testTarget(
            name: "SessionRunnerTests",
            dependencies: [
                "SessionRunner",
                .product(name: "SessionKit", package: "SessionKit"),
            ]
        ),
    ]
)
